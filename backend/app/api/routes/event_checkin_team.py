"""Check-In Team & Access Code endpoints.

Lets an event organizer:
- Add/remove Nuru users authorized to scan guests/tickets for an event.
- Generate, rotate, and revoke a per-event access code.
- Redeem a code to open a check-in session (used by the mobile Check In Mode).
"""
import hashlib
import secrets
import uuid
from datetime import datetime, timedelta
from typing import Optional

import pytz
from fastapi import APIRouter, Body, Depends, Header
from sqlalchemy.orm import Session

from core.database import get_db
from models import (
    Event, EventCommitteeMember, CommitteePermission, User, UserProfile,
    EventAttendee, EventTicket,
)
from models.checkin_team import (
    EventCheckinCode, EventCheckinTeamMember, EventCheckinSession,
)
from utils.auth import get_current_user
from utils.helpers import standard_response

router = APIRouter(prefix="/user-events", tags=["Event Check-In Team"])
redeem_router = APIRouter(prefix="/checkin", tags=["Event Check-In Team"])

EAT = pytz.timezone("Africa/Nairobi")
SESSION_TTL_HOURS = 24


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

def _now() -> datetime:
    return datetime.now(EAT).replace(tzinfo=None)


def _hash_code(plain: str) -> str:
    return hashlib.sha256(plain.strip().upper().encode("utf-8")).hexdigest()


def _generate_code() -> tuple[str, str]:
    """Returns (plain_code, display_prefix). Format: NRU-XXXX-XXXX."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no confusing chars
    raw = "".join(secrets.choice(alphabet) for _ in range(8))
    plain = f"NRU-{raw[:4]}-{raw[4:]}"
    prefix = f"NRU-{raw[:4]}-••••"
    return plain, prefix


def _can_manage_team(db: Session, event: Event, user: User) -> bool:
    """Manage = add/remove team, rotate/revoke access code.

    Restricted to the event owner/organizer and committee members with
    `can_manage_committee`. Plain check-in permission is not enough — that
    only lets you scan, not change who else can.
    """
    if event.organizer_id == user.id or event.event_owner_user_id == user.id:
        return True
    cm = db.query(EventCommitteeMember).filter(
        EventCommitteeMember.event_id == event.id,
        EventCommitteeMember.user_id == user.id,
        EventCommitteeMember.status == "active",
    ).first()
    if not cm:
        return False
    perms = db.query(CommitteePermission).filter(
        CommitteePermission.committee_member_id == cm.id
    ).first()
    return bool(perms and perms.can_manage_committee)


def _can_scan(db: Session, event: Event, user: User) -> bool:
    if event.organizer_id == user.id or event.event_owner_user_id == user.id:
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


def _user_brief(db: Session, user_id) -> dict:
    if not user_id:
        return {}
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        return {"id": str(user_id)}
    profile = db.query(UserProfile).filter(UserProfile.user_id == u.id).first()
    return {
        "id": str(u.id),
        "first_name": u.first_name,
        "last_name": u.last_name,
        "full_name": f"{u.first_name or ''} {u.last_name or ''}".strip() or u.email,
        "email": u.email,
        "phone": getattr(u, "phone", None),
        "avatar": getattr(profile, "profile_picture_url", None) if profile else None,
    }


def _resolve_event(db: Session, event_id: str) -> Optional[Event]:
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return None
    return db.query(Event).filter(Event.id == eid).first()


# ──────────────────────────────────────────────
# Team management
# ──────────────────────────────────────────────

@router.get("/{event_id}/checkin-team")
def list_checkin_team(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    event = _resolve_event(db, event_id)
    if not event:
        return standard_response(False, "Event not found")
    can_manage = _can_manage_team(db, event, current_user)
    can_scan = _can_scan(db, event, current_user)
    if not (can_manage or can_scan):
        return standard_response(False, "You do not have permission to view the check-in team")

    members = db.query(EventCheckinTeamMember).filter(
        EventCheckinTeamMember.event_id == event.id,
        EventCheckinTeamMember.status == "active",
    ).order_by(EventCheckinTeamMember.created_at.desc()).all()

    code = db.query(EventCheckinCode).filter(
        EventCheckinCode.event_id == event.id,
        EventCheckinCode.status == "active",
    ).first()

    return standard_response(True, "ok", {
        "members": [{
            "id": str(m.id),
            "user": _user_brief(db, m.user_id),
            "added_by": _user_brief(db, m.added_by_user_id) if can_manage else None,
            "added_at": m.created_at.isoformat() if m.created_at else None,
        } for m in members],
        "code": {
            "id": str(code.id),
            "prefix": code.code_prefix,
            "status": code.status,
            "created_at": code.created_at.isoformat() if code.created_at else None,
            "expires_at": code.expires_at.isoformat() if code.expires_at else None,
        } if code else None,
        "permissions": {
            "can_manage": can_manage,
            "can_scan": can_scan,
        },
    })


@router.post("/{event_id}/checkin-team")
def add_checkin_team_member(
    event_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _resolve_event(db, event_id)
    if not event:
        return standard_response(False, "Event not found")
    if not _can_manage_team(db, event, current_user):
        return standard_response(False, "You do not have permission to add check-in team members")

    user_id = body.get("user_id")
    if not user_id:
        return standard_response(False, "user_id is required")
    try:
        uid = uuid.UUID(user_id)
    except ValueError:
        return standard_response(False, "Invalid user_id")

    target = db.query(User).filter(User.id == uid).first()
    if not target:
        return standard_response(False, "Nuru user not found")

    existing = db.query(EventCheckinTeamMember).filter(
        EventCheckinTeamMember.event_id == event.id,
        EventCheckinTeamMember.user_id == uid,
    ).first()
    if existing:
        if existing.status == "active":
            return standard_response(True, "Already on the team", {"id": str(existing.id)})
        existing.status = "active"
        existing.removed_at = None
        existing.added_by_user_id = current_user.id
        existing.updated_at = _now()
        db.commit()
        return standard_response(True, "Re-added to the team", {"id": str(existing.id)})

    member = EventCheckinTeamMember(
        event_id=event.id,
        user_id=uid,
        added_by_user_id=current_user.id,
        status="active",
    )
    db.add(member)
    db.commit()
    db.refresh(member)
    return standard_response(True, "Added to the team", {"id": str(member.id)})


@router.delete("/{event_id}/checkin-team/{member_id}")
def remove_checkin_team_member(
    event_id: str,
    member_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _resolve_event(db, event_id)
    if not event:
        return standard_response(False, "Event not found")
    if not _can_manage_team(db, event, current_user):
        return standard_response(False, "You do not have permission to remove team members")

    try:
        mid = uuid.UUID(member_id)
    except ValueError:
        return standard_response(False, "Invalid member id")

    member = db.query(EventCheckinTeamMember).filter(
        EventCheckinTeamMember.id == mid,
        EventCheckinTeamMember.event_id == event.id,
    ).first()
    if not member:
        return standard_response(False, "Member not found")

    member.status = "removed"
    member.removed_at = _now()
    member.updated_at = _now()
    # End any active sessions held by this user for this event
    db.query(EventCheckinSession).filter(
        EventCheckinSession.event_id == event.id,
        EventCheckinSession.user_id == member.user_id,
        EventCheckinSession.status == "active",
    ).update({
        EventCheckinSession.status: "revoked",
        EventCheckinSession.ended_at: _now(),
        EventCheckinSession.updated_at: _now(),
    })
    db.commit()
    return standard_response(True, "Removed from the team")


# ──────────────────────────────────────────────
# Access code
# ──────────────────────────────────────────────

@router.post("/{event_id}/checkin-code/generate")
def generate_checkin_code(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    event = _resolve_event(db, event_id)
    if not event:
        return standard_response(False, "Event not found")
    if not _can_manage_team(db, event, current_user):
        return standard_response(False, "You do not have permission to manage the access code")

    # Revoke any existing active codes
    db.query(EventCheckinCode).filter(
        EventCheckinCode.event_id == event.id,
        EventCheckinCode.status == "active",
    ).update({
        EventCheckinCode.status: "revoked",
        EventCheckinCode.revoked_at: _now(),
        EventCheckinCode.updated_at: _now(),
    })

    plain, prefix = _generate_code()
    code = EventCheckinCode(
        event_id=event.id,
        code_hash=_hash_code(plain),
        code_prefix=prefix,
        status="active",
        created_by_user_id=current_user.id,
    )
    db.add(code)
    db.commit()
    db.refresh(code)
    return standard_response(True, "Access code generated", {
        "id": str(code.id),
        "code": plain,        # shown ONCE
        "prefix": code.code_prefix,
        "status": code.status,
        "created_at": code.created_at.isoformat() if code.created_at else None,
    })


@router.post("/{event_id}/checkin-code/revoke")
def revoke_checkin_code(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    event = _resolve_event(db, event_id)
    if not event:
        return standard_response(False, "Event not found")
    if not _can_manage_team(db, event, current_user):
        return standard_response(False, "You do not have permission to revoke the access code")

    n = db.query(EventCheckinCode).filter(
        EventCheckinCode.event_id == event.id,
        EventCheckinCode.status == "active",
    ).update({
        EventCheckinCode.status: "revoked",
        EventCheckinCode.revoked_at: _now(),
        EventCheckinCode.updated_at: _now(),
    })
    # Revoke active sessions too
    db.query(EventCheckinSession).filter(
        EventCheckinSession.event_id == event.id,
        EventCheckinSession.status == "active",
    ).update({
        EventCheckinSession.status: "revoked",
        EventCheckinSession.ended_at: _now(),
        EventCheckinSession.updated_at: _now(),
    })
    db.commit()
    return standard_response(True, "Access code revoked", {"revoked": n})


# ──────────────────────────────────────────────
# Redeem / session lifecycle
# ──────────────────────────────────────────────

@redeem_router.post("/redeem")
def redeem_checkin_code(
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    code_input = (body.get("code") or "").strip().upper().replace(" ", "")
    if not code_input:
        return standard_response(False, "Please enter a check-in code")
    # Accept with or without dashes
    if "-" not in code_input and len(code_input) == 11:
        code_input = f"NRU-{code_input[3:7]}-{code_input[7:]}" if code_input.startswith("NRU") else code_input

    code_hash = _hash_code(code_input)
    code = db.query(EventCheckinCode).filter(
        EventCheckinCode.code_hash == code_hash,
        EventCheckinCode.status == "active",
    ).first()
    if not code:
        return standard_response(False, "This code is invalid, expired, or has been revoked")
    if code.expires_at and code.expires_at < _now():
        return standard_response(False, "This code has expired")

    event = db.query(Event).filter(Event.id == code.event_id).first()
    if not event:
        return standard_response(False, "Event no longer exists")

    if not _can_scan(db, event, current_user):
        return standard_response(False, "You are not authorized to check in for this event. Ask the organizer to add you to the check-in team.")

    device_label = (body.get("device_label") or "").strip()[:120] or None
    session_token = secrets.token_urlsafe(32)
    expires_at = _now() + timedelta(hours=SESSION_TTL_HOURS)

    session = EventCheckinSession(
        event_id=event.id,
        code_id=code.id,
        user_id=current_user.id,
        device_label=device_label,
        session_token=session_token,
        status="active",
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    return standard_response(True, "Check-in session started", {
        "session_token": session_token,
        "session_id": str(session.id),
        "expires_at": expires_at.isoformat(),
        "event": {
            "id": str(event.id),
            "name": event.name,
            "start_date": event.start_date.isoformat() if event.start_date else None,
            "location": event.location,
            "cover_image_url": event.cover_image_url,
        },
    })


def _resolve_session(db: Session, token: Optional[str]) -> Optional[EventCheckinSession]:
    if not token:
        return None
    return db.query(EventCheckinSession).filter(
        EventCheckinSession.session_token == token,
        EventCheckinSession.status == "active",
    ).first()


@redeem_router.post("/session/heartbeat")
def heartbeat(x_checkin_session: Optional[str] = Header(default=None), db: Session = Depends(get_db)):
    session = _resolve_session(db, x_checkin_session)
    if not session:
        return standard_response(False, "Session is no longer active")
    session.last_seen_at = _now()
    session.updated_at = _now()
    db.commit()
    return standard_response(True, "ok")


@redeem_router.post("/session/end")
def end_session(x_checkin_session: Optional[str] = Header(default=None), db: Session = Depends(get_db)):
    session = _resolve_session(db, x_checkin_session)
    if not session:
        return standard_response(True, "Already ended")
    session.status = "ended"
    session.ended_at = _now()
    session.updated_at = _now()
    db.commit()
    return standard_response(True, "Session ended")


# ──────────────────────────────────────────────
# Audit log — who scanned what, when (Activity tab)
# ──────────────────────────────────────────────

@router.get("/{event_id}/checkin-log")
def checkin_audit_log(
    event_id: str,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Unified, time-ordered feed of guest and ticket check-ins for an event.

    Powers the "Activity" panel in the event check-in page so organizers can
    see who on the check-in team scanned which attendee/ticket and when.
    """
    event = _resolve_event(db, event_id)
    if not event:
        return standard_response(False, "Event not found")
    if not _can_scan(db, event, current_user) and not _can_manage_team(db, event, current_user):
        return standard_response(False, "You do not have permission to view the check-in log")

    limit = max(1, min(int(limit or 100), 500))

    attendees = db.query(EventAttendee).filter(
        EventAttendee.event_id == event.id,
        EventAttendee.checked_in_at.isnot(None),
    ).order_by(EventAttendee.checked_in_at.desc()).limit(limit).all()

    tickets = db.query(EventTicket).filter(
        EventTicket.event_id == event.id,
        EventTicket.checked_in_at.isnot(None),
    ).order_by(EventTicket.checked_in_at.desc()).limit(limit).all()

    performer_ids = set()
    for a in attendees:
        if getattr(a, "checked_in_by_user_id", None):
            performer_ids.add(a.checked_in_by_user_id)
    for t in tickets:
        if getattr(t, "checked_in_by_user_id", None):
            performer_ids.add(t.checked_in_by_user_id)

    performer_map: dict = {}
    if performer_ids:
        users = db.query(User).filter(User.id.in_(list(performer_ids))).all()
        profiles = {p.user_id: p for p in db.query(UserProfile).filter(UserProfile.user_id.in_(list(performer_ids))).all()}
        for u in users:
            prof = profiles.get(u.id)
            performer_map[u.id] = {
                "id": str(u.id),
                "full_name": f"{u.first_name or ''} {u.last_name or ''}".strip() or u.email,
                "avatar": getattr(prof, "profile_picture_url", None) if prof else None,
            }

    entries: list = []
    for a in attendees:
        entries.append({
            "kind": "guest",
            "id": str(a.id),
            "name": a.guest_name or "Guest",
            "ref": str(a.id)[:8].upper(),
            "checked_in_at": a.checked_in_at.isoformat() if a.checked_in_at else None,
            "checked_in_by": performer_map.get(getattr(a, "checked_in_by_user_id", None)),
            "device_ref": getattr(a, "checkin_device_ref", None),
        })
    for t in tickets:
        entries.append({
            "kind": "ticket",
            "id": str(t.id),
            "name": t.buyer_name or "Ticket Holder",
            "ref": t.ticket_code,
            "checked_in_at": t.checked_in_at.isoformat() if t.checked_in_at else None,
            "checked_in_by": performer_map.get(getattr(t, "checked_in_by_user_id", None)),
            "device_ref": getattr(t, "checkin_device_ref", None),
        })

    entries.sort(key=lambda e: e["checked_in_at"] or "", reverse=True)
    entries = entries[:limit]

    return standard_response(True, "ok", {
        "entries": entries,
        "total": len(entries),
    })
