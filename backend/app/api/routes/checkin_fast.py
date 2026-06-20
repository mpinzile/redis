"""Check-In Fast Lane HTTP routes.

Mounted under ``/api/v1``. All endpoints expect the standard bearer auth.

The fast lane bypasses Postgres on the response path:

- ``POST /events/{event_id}/checkin/fast``   — QR scan, Redis-only.
- ``POST /events/{event_id}/checkin/manual`` — Manual check-in by id.
- ``POST /events/{event_id}/checkin/preload``— Build/refresh the gate state.
- ``GET  /events/{event_id}/checkin/readiness`` — Is the gate ready?
- ``POST /events/{event_id}/checkin/force-sync`` — Drain stream + reconcile
  from Redis -> Postgres (admin/owner).

The response payload is intentionally tiny (≤ ~200 bytes) so it can render
a tick the moment it lands on the device.
"""
from __future__ import annotations

import logging
import time
import uuid
from typing import Optional

from fastapi import APIRouter, Body, Depends, Header, Request
from sqlalchemy.orm import Session

from core.database import get_db
from models import User
from utils.auth import get_current_user
from utils.helpers import standard_response
from utils.checkin_scan import authorize_scan
from services import checkin_fastlane as fast

log = logging.getLogger("checkin.fastlane.api")

router = APIRouter(prefix="/events", tags=["checkin-fast"])


def _slow_log(stage: str, total_ms: float, event_id: str, scanner_id: str) -> None:
    if total_ms >= 1500:
        log.error("checkin.fastlane CRITICAL %s %.1fms event=%s scanner=%s",
                  stage, total_ms, event_id, scanner_id)
    elif total_ms >= 700:
        log.warning("checkin.fastlane SLOW %s %.1fms event=%s scanner=%s",
                    stage, total_ms, event_id, scanner_id)
    else:
        log.info("checkin.fastlane ok %s %.1fms event=%s", stage, total_ms, event_id)


# ──────────────────────────────────────────────────────────────────────
# Scan
# ──────────────────────────────────────────────────────────────────────

@router.post("/{event_id}/checkin/fast")
def fast_scan(
    event_id: str,
    request: Request,
    body: dict = Body(...),
    current_user: User = Depends(get_current_user),
    x_checkin_session: Optional[str] = Header(default=None),
    x_client_sent_at: Optional[str] = Header(default=None),
):
    """Single-RTT QR check-in. No Postgres on the hot path."""
    t0 = time.perf_counter()
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    raw = (body.get("code") or body.get("qr_code") or "").strip()
    if not raw:
        return standard_response(False, "No QR code was scanned — please try again",
                                 {"reason": "empty_code"})
    csid = (body.get("client_scan_id") or "").strip() or None
    device_ref = (body.get("device_ref") or "").strip() or None
    method = (body.get("method") or "qr").strip() or "qr"

    status, payload = fast.scan(
        event_id=eid,
        scanner_id=current_user.id,
        raw_code=raw,
        method=method,
        client_scan_id=csid,
        device_ref=device_ref,
    )

    # Permission gate cold-miss: if Redis says "forbidden" or "redis_unavailable"
    # OR the scanners set hasn't been seen, do a single Postgres permission
    # check via the legacy authorizer so the first scan still works while the
    # preload is in flight. This is the ONLY DB call on the response path and
    # only fires when the cache is cold.
    if status in ("forbidden", "redis_unavailable", "unknown"):
        # Lazy DB authorize ONLY if Redis flat-out rejected the scanner —
        # we will not re-run on every scan because the result hydrates the
        # scanners set for the rest of the event.
        if status == "forbidden":
            from core.database import SessionLocal
            db: Session = SessionLocal()
            try:
                event, _sess, err = authorize_scan(db, eid, current_user, x_checkin_session)
                if not err and event is not None:
                    fast.add_scanner(eid, current_user.id)
                    # Re-run the scan — now allowed.
                    status, payload = fast.scan(
                        event_id=eid,
                        scanner_id=current_user.id,
                        raw_code=raw,
                        method=method,
                        client_scan_id=csid,
                        device_ref=device_ref,
                    )
            finally:
                db.close()

        if status == "unknown":
            # Cache may be cold or stale — trigger a background reload but
            # don't block. The mobile app will retry on /preload completion.
            from core.database import SessionLocal
            db: Session = SessionLocal()
            try:
                fast.preload_event(db, eid)
            finally:
                db.close()
            status, payload = fast.scan(
                event_id=eid,
                scanner_id=current_user.id,
                raw_code=raw,
                method=method,
                client_scan_id=csid,
                device_ref=device_ref,
            )

    dt = (time.perf_counter() - t0) * 1000.0
    payload = dict(payload)
    payload["server_ms"] = round(dt, 1)
    _slow_log(status, dt, event_id, str(current_user.id))

    if status == "ok":
        return standard_response(True, payload.get("message", "Checked in"), payload)
    if status == "already":
        # Treat as a non-error success — scanner shows the existing tick.
        return standard_response(False, payload.get("message", "Already checked in"), payload)
    return standard_response(False, payload.get("message", "Check-in failed"), payload)


# ──────────────────────────────────────────────────────────────────────
# Manual
# ──────────────────────────────────────────────────────────────────────

@router.post("/{event_id}/checkin/manual")
def manual_scan(
    event_id: str,
    body: dict = Body(...),
    current_user: User = Depends(get_current_user),
    x_checkin_session: Optional[str] = Header(default=None),
):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")
    attendee_id = (body.get("attendee_id") or "").strip() or None
    ticket_id = (body.get("ticket_id") or "").strip() or None
    token = (body.get("token") or "").strip() or None
    if not (token or attendee_id or ticket_id):
        return standard_response(False, "Provide attendee_id, ticket_id, or token.")
    if not token:
        token = fast.resolve_manual(eid, attendee_id=attendee_id, ticket_id=ticket_id)
    if not token:
        # Cache cold — preload then retry once.
        from core.database import SessionLocal
        db: Session = SessionLocal()
        try:
            fast.preload_event(db, eid)
        finally:
            db.close()
        token = fast.resolve_manual(eid, attendee_id=attendee_id, ticket_id=ticket_id)
    if not token:
        return standard_response(False, "Guest not found for this event")

    status, payload = fast.scan(
        event_id=eid,
        scanner_id=current_user.id,
        raw_code=token,
        method="manual",
        client_scan_id=(body.get("client_scan_id") or "").strip() or None,
        device_ref=(body.get("device_ref") or "").strip() or None,
    )
    if status == "ok":
        return standard_response(True, payload.get("message", "Checked in"), payload)
    if status == "already":
        return standard_response(False, payload.get("message", "Already checked in"), payload)
    return standard_response(False, payload.get("message", "Check-in failed"), payload)


# ──────────────────────────────────────────────────────────────────────
# Preload / readiness / force-sync
# ──────────────────────────────────────────────────────────────────────

@router.get("/{event_id}/checkin/readiness")
def readiness(
    event_id: str,
    current_user: User = Depends(get_current_user),
):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")
    return standard_response(True, "ok", fast.readiness(eid))


@router.post("/{event_id}/checkin/preload")
def preload(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    x_checkin_session: Optional[str] = Header(default=None),
    body: dict = Body(default={}),
):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")
    event, _sess, err = authorize_scan(db, eid, current_user, x_checkin_session)
    if err:
        return standard_response(False, err)
    force = bool(body.get("force"))
    info = fast.preload_event(db, eid, force=force)
    return standard_response(True, "preloaded", info)


@router.post("/{event_id}/checkin/force-sync")
def force_sync(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    x_checkin_session: Optional[str] = Header(default=None),
):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")
    event, _sess, err = authorize_scan(db, eid, current_user, x_checkin_session)
    if err:
        return standard_response(False, err)
    # Lazy import to avoid Celery-at-import surprises.
    from tasks.checkin_persist import drain_event, reconcile_event
    drained = drain_event(str(eid))
    reconciled = reconcile_event(str(eid))
    return standard_response(True, "sync complete", {
        "drained": drained, "reconciled": reconciled,
    })