"""Check-In Fast Lane
====================

Redis-only gate-state for live events. The scan endpoint hits ONLY this
module — no Postgres reads on the response path, no `db.commit()`.
Persistence is drained asynchronously by ``tasks.checkin_persist``.

Why
---
Audit of the legacy ``/guests/checkin-qr`` path showed three blocking
stages on every scan:

 1. ``authorize_scan`` ran 3–5 sequential ``SELECT``s through Postgres.
 2. The check-in itself ran ``UPDATE ... ; commit; refresh`` before
    returning a payload.
 3. Mobile then awaited a second round trip for ``ScanResolveService``
    *before* the scan, plus ``getScanStats`` after success.

End-to-end was ~9s on 3G. This module collapses the backend work to a
single Redis round-trip via a Lua script — typically 5–30ms — and shoves
the Postgres write onto a Celery worker via a Redis Stream.

Keys
----
    event:{eid}:checkin:scanners        SET<user_id>
    event:{eid}:checkin:token:{token}   HASH {kind,id,name,ticket_name,state,
                                              checked_in_at,checked_in_by,method}
    event:{eid}:checkin:id:{kind}:{id}  STRING -> token (for manual lookup)
    event:{eid}:checkin:stream          STREAM persistence queue
    event:{eid}:checkin:meta            HASH {ready, last_preloaded_at,
                                              tokens_loaded, scanners_loaded}
    checkin:idem:{csid}                 NX guard (10s) for client retries

The keys all live under ``event:{eid}:checkin:*`` so they can be flushed
with one ``cache_delete_pattern`` call after an event ends.
"""
from __future__ import annotations

import json
import logging
import time
import uuid
from datetime import datetime
from typing import Optional, Tuple

from sqlalchemy.orm import Session

from core.redis import get_redis, redis_available
from models import (
    Event,
    EventAttendee,
    EventCommitteeMember,
    CommitteePermission,
    EventInvitation,
    EventTicket,
    TicketOrderStatusEnum,
)
from models.checkin_team import EventCheckinTeamMember

log = logging.getLogger("checkin.fastlane")

# ──────────────────────────────────────────────────────────────────────
# Key helpers
# ──────────────────────────────────────────────────────────────────────

def k_scanners(eid: str) -> str:       return f"event:{eid}:checkin:scanners"
def k_token(eid: str, tok: str) -> str: return f"event:{eid}:checkin:token:{tok}"
def k_id(eid: str, kind: str, oid: str) -> str: return f"event:{eid}:checkin:id:{kind}:{oid}"
def k_stream(eid: str) -> str:         return f"event:{eid}:checkin:stream"
def k_meta(eid: str) -> str:           return f"event:{eid}:checkin:meta"
def k_idem(csid: str) -> str:          return f"checkin:idem:{csid}"

# 24h TTL is plenty — preload re-runs on demand and on event-open.
_TTL_SECONDS = 24 * 3600


# ──────────────────────────────────────────────────────────────────────
# Lua script — the atomic gate
# ──────────────────────────────────────────────────────────────────────

# KEYS[1] = scanners set
# KEYS[2] = token hash
# KEYS[3] = stream
# ARGV[1] = scanner_id     ARGV[2] = now_iso
# ARGV[3] = method         ARGV[4] = csid
# ARGV[5] = device_ref
#
# Returns:
#   {"forbidden"}
#   {"unknown"}
#   {"already", name, kind, id, checked_in_at, ticket_name}
#   {"ok",      name, kind, id, checked_in_at, ticket_name}
_SCAN_LUA = """
if redis.call('SISMEMBER', KEYS[1], ARGV[1]) == 0 then
    return {'forbidden'}
end
if redis.call('EXISTS', KEYS[2]) == 0 then
    return {'unknown'}
end
local data = redis.call('HMGET', KEYS[2], 'state','name','kind','id','ticket_name','checked_in_at','blocked_reason')
local state         = data[1]
local name          = data[2] or ''
local kind          = data[3] or ''
local oid           = data[4] or ''
local ticket_name   = data[5] or ''
local checked_at    = data[6] or ''
local blocked       = data[7]
if blocked and blocked ~= '' then
    return {'blocked', name, kind, oid, blocked, ticket_name}
end
if state == 'in' then
    return {'already', name, kind, oid, checked_at, ticket_name}
end
redis.call('HSET', KEYS[2],
    'state', 'in',
    'checked_in_at', ARGV[2],
    'checked_in_by', ARGV[1],
    'method', ARGV[3],
    'device_ref', ARGV[5])
redis.call('XADD', KEYS[3], 'MAXLEN', '~', '10000', '*',
    'token', ARGV[4],
    'kind', kind,
    'id', oid,
    'scanner', ARGV[1],
    'ts', ARGV[2],
    'method', ARGV[3],
    'device_ref', ARGV[5])
return {'ok', name, kind, oid, ARGV[2], ticket_name}
"""

_lua_sha: Optional[str] = None


def _load_lua() -> Optional[str]:
    global _lua_sha
    r = get_redis()
    if not r:
        return None
    if _lua_sha is None:
        try:
            _lua_sha = r.script_load(_SCAN_LUA)
        except Exception as e:
            log.warning("fastlane: lua load failed: %s", e)
            return None
    return _lua_sha


# ──────────────────────────────────────────────────────────────────────
# Preload
# ──────────────────────────────────────────────────────────────────────

def _collect_scanner_ids(db: Session, event: Event) -> set[str]:
    ids: set[str] = set()
    if event.organizer_id:
        ids.add(str(event.organizer_id))
    owner = getattr(event, "event_owner_user_id", None)
    if owner:
        ids.add(str(owner))
    # Committee members with explicit scan permission
    rows = (
        db.query(EventCommitteeMember.user_id)
        .join(CommitteePermission, CommitteePermission.committee_member_id == EventCommitteeMember.id)
        .filter(
            EventCommitteeMember.event_id == event.id,
            EventCommitteeMember.status == "active",
            CommitteePermission.can_check_in_guests == True,  # noqa: E712
        )
        .all()
    )
    for (uid,) in rows:
        if uid:
            ids.add(str(uid))
    # Check-in team members
    team = (
        db.query(EventCheckinTeamMember.user_id)
        .filter(
            EventCheckinTeamMember.event_id == event.id,
            EventCheckinTeamMember.status == "active",
        )
        .all()
    )
    for (uid,) in team:
        if uid:
            ids.add(str(uid))
    return ids


def preload_event(db: Session, event_id: uuid.UUID | str, *, force: bool = False) -> dict:
    """Bulk-load the gate state for an event into Redis.

    Idempotent — calling it twice in a row is a no-op (returns the cached
    counts) unless ``force=True``.
    """
    r = get_redis()
    if not r:
        return {"ready": False, "reason": "redis_unavailable"}

    eid = str(event_id)
    meta_key = k_meta(eid)
    if not force:
        meta = r.hgetall(meta_key) or {}
        if meta.get("ready") == "1":
            return {
                "ready": True,
                "cached": True,
                "tokens_loaded": int(meta.get("tokens_loaded", 0)),
                "scanners_loaded": int(meta.get("scanners_loaded", 0)),
                "last_preloaded_at": meta.get("last_preloaded_at"),
            }

    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        return {"ready": False, "reason": "event_not_found"}

    scanners = _collect_scanner_ids(db, event)

    # Attendees — token is the attendee.id (UUID as string).
    attendees = (
        db.query(
            EventAttendee.id,
            EventAttendee.guest_name,
            EventAttendee.checked_in,
            EventAttendee.checked_in_at,
            EventAttendee.invitation_id,
        )
        .filter(EventAttendee.event_id == event.id)
        .all()
    )

    # Invitations — invitation_code resolves to the matching attendee.id.
    inv_rows = (
        db.query(EventInvitation.id, EventInvitation.invitation_code)
        .filter(EventInvitation.event_id == event.id)
        .all()
    )
    inv_code_by_id = {iid: code for iid, code in inv_rows if code}

    # Tickets — token is ticket_code.
    tickets = (
        db.query(
            EventTicket.id,
            EventTicket.ticket_code,
            EventTicket.buyer_name,
            EventTicket.checked_in,
            EventTicket.checked_in_at,
            EventTicket.status,
        )
        .filter(EventTicket.event_id == event.id)
        .all()
    )

    pipe = r.pipeline(transaction=False)
    # Scanners
    pipe.delete(k_scanners(eid))
    if scanners:
        pipe.sadd(k_scanners(eid), *scanners)
    pipe.expire(k_scanners(eid), _TTL_SECONDS)

    tokens_loaded = 0
    for att_id, name, checked, checked_at, inv_id in attendees:
        tok = str(att_id)
        state = "in" if checked else "out"
        h = {
            "kind": "guest",
            "id": tok,
            "name": (name or "Guest"),
            "ticket_name": "",
            "state": state,
            "checked_in_at": checked_at.isoformat() if checked_at else "",
        }
        pipe.hset(k_token(eid, tok), mapping=h)
        pipe.expire(k_token(eid, tok), _TTL_SECONDS)
        # Manual-lookup index by attendee id
        pipe.set(k_id(eid, "guest", tok), tok, ex=_TTL_SECONDS)
        tokens_loaded += 1
        # Invitation-code alias (points to same hash, separate key)
        inv_code = inv_code_by_id.get(inv_id) if inv_id else None
        if inv_code and inv_code != tok:
            pipe.hset(k_token(eid, inv_code), mapping=h)
            pipe.expire(k_token(eid, inv_code), _TTL_SECONDS)

    for tid, code, buyer, checked, checked_at, status in tickets:
        if not code:
            continue
        state = "in" if checked else "out"
        blocked = ""
        if status not in (TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed):
            blocked = f"ticket_{status.value if hasattr(status,'value') else status}"
        h = {
            "kind": "ticket",
            "id": str(tid),
            "name": (buyer or "Ticket"),
            "ticket_name": "",
            "state": state,
            "checked_in_at": checked_at.isoformat() if checked_at else "",
            "blocked_reason": blocked,
        }
        pipe.hset(k_token(eid, code), mapping=h)
        pipe.expire(k_token(eid, code), _TTL_SECONDS)
        pipe.set(k_id(eid, "ticket", str(tid)), code, ex=_TTL_SECONDS)
        tokens_loaded += 1

    pipe.hset(meta_key, mapping={
        "ready": "1",
        "tokens_loaded": tokens_loaded,
        "scanners_loaded": len(scanners),
        "last_preloaded_at": datetime.utcnow().isoformat(),
    })
    pipe.expire(meta_key, _TTL_SECONDS)
    pipe.execute()

    # Make sure the stream + consumer group exist before any scan tries XADD.
    try:
        r.xgroup_create(k_stream(eid), "persist", id="0", mkstream=True)
    except Exception:
        pass  # BUSYGROUP – already exists.

    _load_lua()  # warm
    return {
        "ready": True,
        "cached": False,
        "tokens_loaded": tokens_loaded,
        "scanners_loaded": len(scanners),
        "last_preloaded_at": datetime.utcnow().isoformat(),
    }


def readiness(event_id: uuid.UUID | str) -> dict:
    r = get_redis()
    if not r:
        return {"ready": False, "redis_available": False}
    meta = r.hgetall(k_meta(str(event_id))) or {}
    return {
        "ready": meta.get("ready") == "1",
        "redis_available": True,
        "tokens_loaded": int(meta.get("tokens_loaded", 0)),
        "scanners_loaded": int(meta.get("scanners_loaded", 0)),
        "last_preloaded_at": meta.get("last_preloaded_at"),
    }


def add_scanner(event_id: uuid.UUID | str, user_id: uuid.UUID | str) -> None:
    r = get_redis()
    if not r:
        return
    r.sadd(k_scanners(str(event_id)), str(user_id))
    r.expire(k_scanners(str(event_id)), _TTL_SECONDS)


def remove_scanner(event_id: uuid.UUID | str, user_id: uuid.UUID | str) -> None:
    r = get_redis()
    if not r:
        return
    r.srem(k_scanners(str(event_id)), str(user_id))


# ──────────────────────────────────────────────────────────────────────
# Scan
# ──────────────────────────────────────────────────────────────────────

def _extract_code(raw: str) -> str:
    s = (raw or "").strip()
    if not s:
        return ""
    lower = s.lower()
    for m in ("/checkin/", "/rsvp/", "/verify/", "/ticket/", "/tickets/"):
        i = lower.rfind(m)
        if i >= 0:
            tail = s[i + len(m):]
            for sep in ("?", "#", "/"):
                j = tail.find(sep)
                if j >= 0:
                    tail = tail[:j]
            if tail:
                return tail.strip()
    return s


ScanOutcome = Tuple[str, dict]  # (status, payload)


def scan(
    *,
    event_id: uuid.UUID | str,
    scanner_id: uuid.UUID | str,
    raw_code: str,
    method: str = "qr",
    client_scan_id: Optional[str] = None,
    device_ref: Optional[str] = None,
) -> ScanOutcome:
    """Run the atomic Redis gate. Returns ``(status, payload)``.

    Statuses: ``ok``, ``already``, ``forbidden``, ``unknown``, ``blocked``,
    ``redis_unavailable``.
    """
    r = get_redis()
    if not r:
        return "redis_unavailable", {"message": "Live gate unavailable — please retry"}

    token = _extract_code(raw_code)
    if not token:
        return "unknown", {"message": "No QR code was scanned — please try again"}

    eid = str(event_id)
    sid = str(scanner_id)
    csid = (client_scan_id or "").strip() or f"{sid}:{token}:{int(time.time()*1000)}"
    dev = (device_ref or "")[:200]

    # Cheap dedupe across workers — if the same csid came in within 10s,
    # we replay a synthetic "already" so the scanner shows the same screen
    # without paying for the Lua call.
    if not r.set(k_idem(csid), "1", nx=True, ex=10):
        # Re-read the token state directly; this is one HMGET, still fast.
        h = r.hgetall(k_token(eid, token)) or {}
        if h:
            return "already", _payload_from_hash(h)

    sha = _load_lua()
    try:
        if sha:
            res = r.evalsha(
                sha, 3,
                k_scanners(eid), k_token(eid, token), k_stream(eid),
                sid, datetime.utcnow().isoformat(), method, csid, dev,
            )
        else:
            res = r.eval(
                _SCAN_LUA, 3,
                k_scanners(eid), k_token(eid, token), k_stream(eid),
                sid, datetime.utcnow().isoformat(), method, csid, dev,
            )
    except Exception as e:
        # NOSCRIPT or transient — fall back to a one-shot eval next time.
        global _lua_sha
        _lua_sha = None
        log.warning("fastlane: lua exec failed: %s", e)
        return "redis_unavailable", {"message": "Live gate hiccup — please retry"}

    if not res:
        return "unknown", {"message": "Could not read this QR code"}
    tag = (res[0] or b"").decode() if isinstance(res[0], (bytes, bytearray)) else str(res[0])

    def _s(idx: int) -> str:
        if idx >= len(res) or res[idx] is None:
            return ""
        v = res[idx]
        return v.decode() if isinstance(v, (bytes, bytearray)) else str(v)

    if tag == "forbidden":
        return "forbidden", {"message": "You do not have permission to scan this event",
                             "reason": "forbidden"}
    if tag == "unknown":
        return "unknown", {"message": "We couldn't match this QR code to any guest or ticket",
                           "reason": "not_found"}
    if tag == "blocked":
        reason = _s(4)
        return "blocked", {
            "message": _blocked_message(reason),
            "reason": reason,
            "kind": _s(2),
            "id": _s(3),
            "display_name": _s(1),
            "ticket_name": _s(5),
        }
    now_iso = datetime.utcnow().isoformat()
    payload = {
        "kind": _s(2),
        "id": _s(3),
        "display_name": _s(1),
        "ticket_name": _s(5),
        "checked_in_at": _s(4),
        "scan_time": now_iso,
    }
    if tag == "already":
        payload["already_checked_in"] = True
        payload["reason"] = "already_used"
        payload["message"] = "Already checked in"
        return "already", payload
    payload["already_checked_in"] = False
    payload["message"] = "Welcome!"
    return "ok", payload


def _payload_from_hash(h: dict) -> dict:
    is_in = h.get("state") == "in"
    return {
        "kind": h.get("kind", ""),
        "id": h.get("id", ""),
        "display_name": h.get("name", ""),
        "ticket_name": h.get("ticket_name", ""),
        "checked_in_at": h.get("checked_in_at", ""),
        "scan_time": datetime.utcnow().isoformat(),
        "already_checked_in": is_in,
        "reason": "already_used" if is_in else "",
        "message": "Already checked in" if is_in else "Pending",
    }


def _blocked_message(reason: str) -> str:
    if reason.startswith("ticket_pending"):
        return "This ticket hasn't been paid for yet"
    if reason.startswith("ticket_rejected"):
        return "This ticket was rejected and cannot be used"
    if reason.startswith("ticket_cancelled"):
        return "This ticket was cancelled and is no longer valid"
    if reason.startswith("ticket_"):
        return f"Ticket cannot be checked in ({reason[7:]})"
    return "This pass is not valid for check-in"


def resolve_manual(event_id: uuid.UUID | str, *, attendee_id: Optional[str] = None,
                   ticket_id: Optional[str] = None) -> Optional[str]:
    """Look up the QR token for a manual check-in target."""
    r = get_redis()
    if not r:
        return None
    eid = str(event_id)
    if attendee_id:
        v = r.get(k_id(eid, "guest", attendee_id))
        if v:
            return v
    if ticket_id:
        v = r.get(k_id(eid, "ticket", ticket_id))
        if v:
            return v
    return None


# ──────────────────────────────────────────────────────────────────────
# Stream consumption (used by the Celery persister)
# ──────────────────────────────────────────────────────────────────────

def read_stream(event_id: uuid.UUID | str, *, count: int = 200, block_ms: int = 0) -> list:
    r = get_redis()
    if not r:
        return []
    try:
        r.xgroup_create(k_stream(str(event_id)), "persist", id="0", mkstream=True)
    except Exception:
        pass
    try:
        return r.xreadgroup("persist", "worker-1", {k_stream(str(event_id)): ">"},
                            count=count, block=block_ms) or []
    except Exception as e:
        log.warning("fastlane: xreadgroup failed for %s: %s", event_id, e)
        return []


def ack_stream(event_id: uuid.UUID | str, ids: list[str]) -> None:
    if not ids:
        return
    r = get_redis()
    if not r:
        return
    try:
        r.xack(k_stream(str(event_id)), "persist", *ids)
    except Exception as e:
        log.warning("fastlane: xack failed: %s", e)


def active_event_ids(scan_count: int = 500) -> list[str]:
    """Enumerate events that currently have a fast-lane stream."""
    r = get_redis()
    if not r:
        return []
    out: list[str] = []
    cursor = 0
    while True:
        cursor, keys = r.scan(cursor=cursor, match="event:*:checkin:stream", count=scan_count)
        for key in keys:
            parts = key.split(":")
            if len(parts) >= 4:
                out.append(parts[1])
        if cursor == 0:
            break
    return out


def dump_state(event_id: uuid.UUID | str) -> dict:
    """Return the full Redis token state for an event — used by the
    reconcile job to backfill any rows the stream lost."""
    r = get_redis()
    if not r:
        return {}
    eid = str(event_id)
    out: dict[str, dict] = {}
    cursor = 0
    while True:
        cursor, keys = r.scan(cursor=cursor, match=f"event:{eid}:checkin:token:*", count=500)
        for key in keys:
            h = r.hgetall(key) or {}
            if h.get("state") == "in":
                tok = key.rsplit(":", 1)[-1]
                out[tok] = h
        if cursor == 0:
            break
    return out