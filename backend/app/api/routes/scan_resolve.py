"""Universal QR Scan Resolver.

POST /scan/resolve
------------------
A single dispatcher the scanner UI can hit with ANY QR payload. It inspects
the payload (stripping URL wrappers if present), figures out which Nuru
object the code maps to, and returns a normalized envelope the frontend
result cards already understand — plus a `route` discriminator and a
`actions[]` list so the UI can offer the right follow-up call without
hard-coding URL conventions.

This endpoint never mutates anything. Acting on the resolved code (checking
in a guest/ticket, opening a contribution receipt, redeeming an access
code, ...) is always a follow-up call to the dedicated endpoint, so we
keep idempotency and audit guarantees from earlier phases intact.

Supported payload kinds:
- NTK-XXXXXXXX               → ticket
- UUID                       → event attendee (guest)
- Invitation code            → event invitation → attendee
- NRU-XXXX-XXXX              → check-in team access code (instructs redeem)
- {body}.{sig}               → signed contribution verify token
- https://nuru.tz/c/{token}  → public contribution share link
- https://.../t/{ticket}     → ticket URL wrapper
- https://.../i/{invitation} → invitation URL wrapper
- Anything else              → `unknown`
"""
from __future__ import annotations

import re
import uuid
from datetime import datetime
from typing import Optional

import pytz
from fastapi import APIRouter, Body, Depends, Header
from sqlalchemy.orm import Session

from core.database import get_db
from models import (
    Event, EventAttendee, EventInvitation, EventTicket, EventTicketClass,
    User, UserProfile, EventContributor,
)
from models.checkin_team import EventCheckinCode
from utils.auth import get_current_user
from utils.helpers import standard_response
from utils.checkin_scan import resolve_checkin_session, can_scan_event
from services.share_links import find_by_token as find_contribution_by_token

# Reuse the existing aggregate-receipt verify logic so we return the
# same summary the receipt page shows.
from api.routes.user_contributors import (
    _verify_contribution_token, _aggregate_summary_for,
)

router = APIRouter(prefix="/scan", tags=["Scan Resolver"])
EAT = pytz.timezone("Africa/Nairobi")


# ──────────────────────────────────────────────
# Code extraction
# ──────────────────────────────────────────────

_URL_TAIL_RE = re.compile(r"^https?://[^/]+/(?:c|t|i|r|m|verify/[^/]+)/([^/?#]+)", re.IGNORECASE)


def _extract(raw: str) -> str:
    s = (raw or "").strip()
    if not s:
        return ""
    # URL wrapper → keep the meaningful tail segment.
    m = _URL_TAIL_RE.match(s)
    if m:
        return m.group(1).strip()
    # Bare nuru host with path
    if s.startswith("http"):
        try:
            tail = s.rstrip("/").rsplit("/", 1)[-1]
            return tail or s
        except Exception:
            return s
    return s


_TICKET_RE = re.compile(r"^NTK-[A-Z0-9]{6,}$", re.IGNORECASE)
_ACCESS_CODE_RE = re.compile(r"^NRU-[A-Z0-9]{4}-[A-Z0-9]{4}$", re.IGNORECASE)
_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.IGNORECASE)
_VERIFY_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{16,}$")


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

def _event_brief(ev: Optional[Event]) -> Optional[dict]:
    if not ev:
        return None
    return {
        "id": str(ev.id),
        "name": ev.name,
        "start_date": ev.start_date.isoformat() if ev.start_date else None,
        "location": ev.location,
        "cover_image": getattr(ev, "cover_image_url", None),
    }


def _user_brief(db: Session, user_id) -> Optional[dict]:
    if not user_id:
        return None
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        return None
    prof = db.query(UserProfile).filter(UserProfile.user_id == u.id).first()
    return {
        "id": str(u.id),
        "full_name": f"{u.first_name or ''} {u.last_name or ''}".strip() or u.email,
        "avatar": getattr(prof, "profile_picture_url", None) if prof else None,
    }


def _envelope(route: str, *, message: str, kind: Optional[str] = None,
              name: Optional[str] = None, code: str = "",
              event: Optional[dict] = None, payload: Optional[dict] = None,
              actions: Optional[list] = None, reason: Optional[str] = None,
              status: str = "ok") -> dict:
    return {
        "route": route,
        "status": status,            # ok | warning | error
        "kind": kind or route,
        "name": name,
        "code": code,
        "event": event,
        "payload": payload or {},
        "actions": actions or [],
        "reason": reason,
        "message": message,
        "scan_time": datetime.now(EAT).isoformat(),
    }


# ──────────────────────────────────────────────
# Endpoint
# ──────────────────────────────────────────────

@router.post("/resolve")
def resolve_scan(
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    x_checkin_session: Optional[str] = Header(default=None),
):
    raw = (body.get("code") or body.get("qr_code") or "").strip()
    event_id_hint = (body.get("event_id") or "").strip() or None
    code = _extract(raw)

    if not code:
        return standard_response(True, "No QR detected",
            _envelope("unknown", message="No QR code was scanned",
                      status="error", reason="empty_code"))

    # Where the scanner currently is (optional context). If supplied + the
    # user can scan there, ticket/guest results add a "Check in" action
    # pointing at the existing event endpoint.
    context_event: Optional[Event] = None
    if event_id_hint:
        try:
            context_event = db.query(Event).filter(Event.id == uuid.UUID(event_id_hint)).first()
        except ValueError:
            context_event = None

    session = resolve_checkin_session(db, x_checkin_session)

    # ── 1. Check-in team access code ──
    if _ACCESS_CODE_RE.match(code):
        return standard_response(True, "Check-in access code",
            _envelope(
                "checkin_code",
                kind="checkin_code",
                name="Check-In Access Code",
                code=code,
                message="This is a Check-In Team access code. Redeem it to enter Check-In Mode.",
                actions=[{
                    "label": "Enter Check-In Mode",
                    "method": "POST",
                    "endpoint": "/checkin/redeem",
                    "body": {"code": code},
                }],
            ))

    # ── 2. Signed contribution verify token ──
    if _VERIFY_TOKEN_RE.match(code):
        payload = _verify_contribution_token(code)
        if payload:
            try:
                eid = uuid.UUID(payload["e"])
                uid = uuid.UUID(payload["u"])
                summary = _aggregate_summary_for(db, uid, eid)
            except Exception:
                summary = None
            if summary:
                ev = db.query(Event).filter(Event.id == eid).first()
                return standard_response(True, "Verified contribution receipt",
                    _envelope(
                        "contribution_receipt",
                        kind="contribution",
                        name=summary.get("contributor_name") or "Contributor",
                        code=code,
                        event=_event_brief(ev),
                        payload={"summary": summary, "verified": True},
                        message="Aggregate contribution receipt verified",
                    ))
        return standard_response(True, "Invalid receipt token",
            _envelope("contribution_receipt", message="This receipt token is invalid or tampered",
                      status="error", reason="invalid_token", code=code))

    # ── 3. Public contribution share link ──
    # share tokens are 22+ char url-safe strings (no dots, no dashes pattern)
    if len(code) >= 16 and re.match(r"^[A-Za-z0-9_-]+$", code) and not _UUID_RE.match(code):
        ec = find_contribution_by_token(db, code)
        if ec:
            ev = db.query(Event).filter(Event.id == ec.event_id).first()
            contributor_name = None
            try:
                from models import UserContributor
                uc = db.query(UserContributor).filter(UserContributor.id == ec.contributor_id).first()
                contributor_name = uc.name if uc else None
            except Exception:
                pass
            return standard_response(True, "Contribution link",
                _envelope(
                    "contribution_pay",
                    kind="contribution",
                    name=contributor_name or "Contributor",
                    code=code,
                    event=_event_brief(ev),
                    payload={
                        "event_contributor_id": str(ec.id),
                        "pledge_amount": float(ec.pledge_amount or 0),
                    },
                    actions=[{
                        "label": "Open contribution",
                        "method": "GET",
                        "endpoint": f"/public/contributions/{code}",
                    }],
                    message="Contribution payment link",
                ))
        # fall through — might still be an invitation code etc.

    # ── 4. Ticket code ──
    if _TICKET_RE.match(code):
        ticket = db.query(EventTicket).filter(EventTicket.ticket_code == code).first()
        if not ticket:
            return standard_response(True, "Ticket not found",
                _envelope("ticket", message="No ticket matches this code",
                          status="error", reason="not_found", code=code))
        ev = db.query(Event).filter(Event.id == ticket.event_id).first()
        tc = db.query(EventTicketClass).filter(EventTicketClass.id == ticket.ticket_class_id).first()
        actions: list = []
        # Only offer a check-in action if the scanner is on the matching event
        # and the user actually has scan permission.
        if context_event and ev and context_event.id == ev.id and (
            (session and session.event_id == ev.id) or can_scan_event(db, ev, current_user)
        ):
            actions.append({
                "label": "Check in attendee",
                "method": "POST",
                "endpoint": f"/user-events/{ev.id}/guests/checkin-qr",
                "body": {"code": code},
            })
        return standard_response(True, "Ticket resolved",
            _envelope(
                "ticket",
                kind="ticket",
                name=ticket.buyer_name or "Ticket Holder",
                code=code,
                event=_event_brief(ev),
                payload={
                    "ticket_id": str(ticket.id),
                    "ticket_code": ticket.ticket_code,
                    "ticket_class": tc.name if tc else None,
                    "quantity": ticket.quantity or 1,
                    "buyer_name": ticket.buyer_name,
                    "buyer_phone": ticket.buyer_phone,
                    "buyer_email": ticket.buyer_email,
                    "status": getattr(ticket.status, "value", ticket.status),
                    "checked_in": ticket.checked_in,
                    "checked_in_at": ticket.checked_in_at.isoformat() if ticket.checked_in_at else None,
                    "checked_in_by": _user_brief(db, getattr(ticket, "checked_in_by_user_id", None)),
                    "cross_event": bool(context_event and ev and context_event.id != ev.id),
                },
                actions=actions,
                status="warning" if ticket.checked_in else "ok",
                message="Already checked in" if ticket.checked_in else "Valid ticket",
            ))

    # ── 5. UUID → attendee ──
    att: Optional[EventAttendee] = None
    if _UUID_RE.match(code):
        try:
            att = db.query(EventAttendee).filter(EventAttendee.id == uuid.UUID(code)).first()
        except ValueError:
            pass

    # ── 6. Invitation code → attendee ──
    if not att:
        inv = db.query(EventInvitation).filter(EventInvitation.invitation_code == code).first()
        if inv:
            att = db.query(EventAttendee).filter(EventAttendee.invitation_id == inv.id).first()

    if att:
        ev = db.query(Event).filter(Event.id == att.event_id).first()
        guest_name = att.guest_name or "Guest"
        actions = []
        if context_event and ev and context_event.id == ev.id and (
            (session and session.event_id == ev.id) or can_scan_event(db, ev, current_user)
        ):
            actions.append({
                "label": "Check in guest",
                "method": "POST",
                "endpoint": f"/user-events/{ev.id}/guests/checkin-qr",
                "body": {"code": code},
            })
        return standard_response(True, "Guest resolved",
            _envelope(
                "guest",
                kind="guest",
                name=guest_name,
                code=code,
                event=_event_brief(ev),
                payload={
                    "attendee_id": str(att.id),
                    "rsvp_status": getattr(att.rsvp_status, "value", att.rsvp_status),
                    "checked_in": att.checked_in,
                    "checked_in_at": att.checked_in_at.isoformat() if att.checked_in_at else None,
                    "checked_in_by": _user_brief(db, getattr(att, "checked_in_by_user_id", None)),
                    "email": att.guest_email,
                    "phone": att.guest_phone,
                    "cross_event": bool(context_event and ev and context_event.id != ev.id),
                },
                actions=actions,
                status="warning" if att.checked_in else "ok",
                message="Already checked in" if att.checked_in else "Valid guest pass",
            ))

    # ── 7. Unknown — give the UI a usable failure card ──
    return standard_response(True, "Unrecognized code",
        _envelope("unknown",
                  message="We couldn't recognize this QR code",
                  status="error", reason="unknown", code=code))
