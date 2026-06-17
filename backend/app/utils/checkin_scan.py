"""Shared helpers for guest/ticket scan endpoints.

Centralizes:
- Acceptance of the `X-Checkin-Session` header (mobile Check In Mode).
- Permission resolution that honours both committee perms and an active
  check-in session.
- A small in-process idempotency cache so a duplicate scan (same QR + same
  `client_scan_id` within 10s) returns the previous response instead of
  double-stamping.

Per-worker is fine — the cache is a defense-in-depth complement to the
client-side scan lock, not the primary guarantee.
"""
from __future__ import annotations

import time
import uuid
from threading import Lock
from typing import Any, Optional, Tuple

from sqlalchemy.orm import Session

from models import Event, EventCommitteeMember, CommitteePermission, User
from models.checkin_team import EventCheckinSession, EventCheckinTeamMember


_IDEMPOTENCY_TTL = 10.0
_idem_lock = Lock()
_idem_cache: dict[str, tuple[float, Any]] = {}


def resolve_checkin_session(db: Session, token: Optional[str]) -> Optional[EventCheckinSession]:
    if not token:
        return None
    return db.query(EventCheckinSession).filter(
        EventCheckinSession.session_token == token.strip(),
        EventCheckinSession.status == "active",
    ).first()


def can_scan_event(db: Session, event: Event, user: User) -> bool:
    if event.organizer_id == user.id or getattr(event, "event_owner_user_id", None) == user.id:
        return True
    cm = db.query(EventCommitteeMember).filter(
        EventCommitteeMember.event_id == event.id,
        EventCommitteeMember.user_id == user.id,
        EventCommitteeMember.status == "active",
    ).first()
    if cm:
        perms = db.query(CommitteePermission).filter(
            CommitteePermission.committee_member_id == cm.id
        ).first()
        if perms and perms.can_check_in_guests:
            return True
    member = db.query(EventCheckinTeamMember).filter(
        EventCheckinTeamMember.event_id == event.id,
        EventCheckinTeamMember.user_id == user.id,
        EventCheckinTeamMember.status == "active",
    ).first()
    return member is not None


def authorize_scan(
    db: Session,
    event_id: uuid.UUID,
    current_user: User,
    session_token: Optional[str],
) -> Tuple[Optional[Event], Optional[EventCheckinSession], Optional[str]]:
    """Return (event, session, error_message).

    Accepts either an active check-in session bound to this event OR a
    user who has scan permission through ownership/committee/team.
    """
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        return None, None, "Event not found"

    session = resolve_checkin_session(db, session_token)
    if session and session.event_id == event.id:
        # Session-authorised: verify the bound user still has scan rights.
        bound_user = db.query(User).filter(User.id == session.user_id).first() if session.user_id else None
        if not bound_user or not can_scan_event(db, event, bound_user):
            return event, None, "Your check-in access has been revoked"
        return event, session, None

    if can_scan_event(db, event, current_user):
        return event, None, None

    return event, None, "You do not have permission to check in for this event"


def stamp_audit(target, *, user: User, session: Optional[EventCheckinSession], device_ref: Optional[str]) -> None:
    """Attach audit columns to an attendee or ticket row prior to commit."""
    try:
        target.checked_in_by_user_id = user.id
    except Exception:
        pass
    if session is not None:
        try:
            target.checkin_session_id = session.id
            target.checkin_code_id = session.code_id
        except Exception:
            pass
    if device_ref:
        try:
            target.checkin_device_ref = device_ref[:200]
        except Exception:
            pass


def idempotent(key: Optional[str]) -> Tuple[Optional[Any], Optional[callable]]:
    """Returns (cached_value, store_fn). If cached_value is not None,
    return it directly. Otherwise call store_fn(value) once you have it.
    """
    if not key:
        return None, None
    now = time.time()
    with _idem_lock:
        # Sweep
        if len(_idem_cache) > 512:
            for k, (ts, _) in list(_idem_cache.items()):
                if now - ts > _IDEMPOTENCY_TTL:
                    _idem_cache.pop(k, None)
        hit = _idem_cache.get(key)
        if hit and now - hit[0] < _IDEMPOTENCY_TTL:
            return hit[1], None

    def _store(value: Any) -> Any:
        with _idem_lock:
            _idem_cache[key] = (time.time(), value)
        return value

    return None, _store
