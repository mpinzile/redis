"""Check-In Fast Lane persistence worker.

Reads from the per-event Redis stream populated by ``services.checkin_fastlane.scan``
and applies the matching Postgres UPDATEs.

Two entry points:

- ``drain_active_events`` (Celery beat, every 2s) — walks every active
  ``event:*:checkin:stream`` and persists pending entries.
- ``reconcile_event(event_id)`` — final safety net: walk all "in" tokens
  in Redis and force the Postgres rows to match. Run after an event ends
  or via ``POST /events/{id}/checkin/force-sync``.

All SQL is idempotent (``WHERE checked_in = false``) so duplicate stream
entries cannot corrupt the row. Failed entries are pushed to a dead-letter
stream and acked so the main loop never gets stuck.
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime

from sqlalchemy import text

from core.celery_app import celery_app
from core.database import SessionLocal
from core.redis import get_redis
from services import checkin_fastlane as fast

log = logging.getLogger("checkin.persist")


def _persist_entry(db, event_id: str, fields: dict) -> bool:
    kind = (fields.get("kind") or "").decode() if isinstance(fields.get("kind"), (bytes, bytearray)) else fields.get("kind", "")
    oid = (fields.get("id") or "").decode() if isinstance(fields.get("id"), (bytes, bytearray)) else fields.get("id", "")
    scanner = (fields.get("scanner") or "").decode() if isinstance(fields.get("scanner"), (bytes, bytearray)) else fields.get("scanner", "")
    ts = (fields.get("ts") or "").decode() if isinstance(fields.get("ts"), (bytes, bytearray)) else fields.get("ts", "")
    method = (fields.get("method") or "").decode() if isinstance(fields.get("method"), (bytes, bytearray)) else fields.get("method", "")
    device_ref = (fields.get("device_ref") or "").decode() if isinstance(fields.get("device_ref"), (bytes, bytearray)) else fields.get("device_ref", "")

    if not (kind and oid and ts):
        return False
    try:
        ts_dt = datetime.fromisoformat(ts)
    except Exception:
        ts_dt = datetime.utcnow()
    try:
        scanner_uuid = uuid.UUID(scanner) if scanner else None
    except Exception:
        scanner_uuid = None
    try:
        oid_uuid = uuid.UUID(oid)
    except Exception:
        return False
    try:
        event_uuid = uuid.UUID(event_id)
    except Exception:
        return False

    params = {
        "ts": ts_dt,
        "scanner": scanner_uuid,
        "device_ref": (device_ref or None),
        "id": oid_uuid,
        "event_id": event_uuid,
    }
    if kind == "guest":
        db.execute(text("""
            UPDATE event_attendees
               SET checked_in = true,
                   checked_in_at = COALESCE(checked_in_at, :ts),
                   checked_in_by_user_id = COALESCE(checked_in_by_user_id, :scanner),
                   checkin_device_ref = COALESCE(checkin_device_ref, :device_ref),
                   rsvp_status = 'checked_in',
                   updated_at = NOW()
             WHERE id = :id
               AND event_id = :event_id
               AND checked_in = false
        """), params)
        return True
    if kind == "ticket":
        db.execute(text("""
            UPDATE event_tickets
               SET checked_in = true,
                   checked_in_at = COALESCE(checked_in_at, :ts),
                   checked_in_by_user_id = COALESCE(checked_in_by_user_id, :scanner),
                   checkin_device_ref = COALESCE(checkin_device_ref, :device_ref),
                   updated_at = NOW()
             WHERE id = :id
               AND event_id = :event_id
               AND checked_in = false
        """), params)
        return True
    return False


def drain_event(event_id: str, batch: int = 500) -> int:
    """Drain pending stream entries for a single event. Returns count
    persisted (including no-ops where the row was already checked in)."""
    # block_ms=None → non-blocking. Earlier we passed 0, which redis-py
    # interprets as BLOCK forever; the socket read then hit its 4s timeout
    # and logged warnings even when the stream was empty.
    entries = fast.read_stream(event_id, count=batch, block_ms=None)
    if not entries:
        return 0
    persisted_ids: list[str] = []
    dead_ids: list[tuple[str, dict]] = []
    db = SessionLocal()
    try:
        for _stream, items in entries:
            for entry_id, fields in items:
                eid = entry_id.decode() if isinstance(entry_id, (bytes, bytearray)) else entry_id
                try:
                    if _persist_entry(db, event_id, fields):
                        persisted_ids.append(eid)
                    else:
                        dead_ids.append((eid, fields))
                except Exception as e:
                    log.warning("persist failure event=%s entry=%s err=%s", event_id, eid, e)
                    dead_ids.append((eid, fields))
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()

    if persisted_ids:
        fast.ack_stream(event_id, persisted_ids)
        # Bust the cached Guests tab summary so the check-in totals on the
        # web/mobile organizer view reflect the drain without waiting 30s.
        try:
            from core.redis import invalidate_event_guest_summary
            invalidate_event_guest_summary(event_id)
        except Exception:
            pass
    if dead_ids:
        r = get_redis()
        if r is not None:
            try:
                pipe = r.pipeline()
                for _eid, fields in dead_ids:
                    pipe.xadd(f"event:{event_id}:checkin:dlq", fields)
                pipe.execute()
            except Exception:
                pass
            fast.ack_stream(event_id, [eid for eid, _ in dead_ids])
    return len(persisted_ids) + len(dead_ids)


_DRAIN_LOCK_KEY = "fastlane:drain:lock"
_DRAIN_LOCK_TTL = 30  # seconds — auto-released if a worker dies mid-drain


@celery_app.task(name="tasks.checkin_persist.drain_active_events")
def drain_active_events() -> dict:
    """Drain every active event's stream. Cheap when no events are live —
    only walks keys that exist.

    Wrapped in a single-flight Redis lock so overlapping beat ticks (the
    schedule fires every few seconds) never run two drainers in parallel.
    """
    r = get_redis()
    have_lock = False
    if r is not None:
        try:
            have_lock = bool(r.set(_DRAIN_LOCK_KEY, "1", nx=True, ex=_DRAIN_LOCK_TTL))
        except Exception:
            have_lock = True  # fall through if Redis can't lock
        if not have_lock:
            # Another worker is already draining — exit cleanly.
            return {"events": 0, "entries": 0, "skipped": "locked"}

    try:
        drained: dict[str, int] = {}
        for eid in fast.active_event_ids():
            try:
                n = drain_event(eid)
                if n:
                    drained[eid] = n
            except Exception as e:
                log.warning("drain event=%s failed: %s", eid, e)
        return {"events": len(drained), "entries": sum(drained.values())}
    finally:
        if have_lock and r is not None:
            try:
                r.delete(_DRAIN_LOCK_KEY)
            except Exception:
                pass


@celery_app.task(name="tasks.checkin_persist.reconcile_event")
def reconcile_event(event_id: str) -> int:
    """Backfill any Redis-marked check-ins that the stream lost."""
    state = fast.dump_state(event_id)
    if not state:
        return 0
    fixed = 0
    db = SessionLocal()
    try:
        for tok, h in state.items():
            kind = h.get("kind")
            oid = h.get("id")
            if not (kind and oid):
                continue
            ts = h.get("checked_in_at") or datetime.utcnow().isoformat()
            scanner = h.get("checked_in_by") or None
            try:
                ok = _persist_entry(db, event_id, {
                    "kind": kind, "id": oid, "ts": ts,
                    "scanner": scanner or "", "method": h.get("method", "manual"),
                    "device_ref": h.get("device_ref", ""),
                })
                if ok:
                    fixed += 1
            except Exception as e:
                log.warning("reconcile event=%s token=%s err=%s", event_id, tok, e)
        db.commit()
    except Exception:
        db.rollback()
    finally:
        db.close()
    return fixed