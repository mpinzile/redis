# Public RSVP endpoints – no authentication required
# Guests use their unique invitation_code to view event details and respond

import secrets
import string
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from typing import Optional, List
from sqlalchemy import func as sql_func

from core.database import SessionLocal
from models import (
    EventInvitation, EventAttendee, EventGuestPlusOne,
    Event, EventImage, EventSetting, EventVenueCoordinate,
    User, UserContributor,
    RSVPStatusEnum, GuestTypeEnum,
)
from utils.helpers import standard_response, format_phone_display

router = APIRouter(prefix="/rsvp", tags=["RSVP"])


# ── Schemas ──────────────────────────────────────────

class RSVPResponseInput(BaseModel):
    rsvp_status: str = Field(..., pattern="^(confirmed|declined|maybe)$")
    meal_preference: Optional[str] = Field(None, max_length=200)
    dietary_restrictions: Optional[str] = Field(None, max_length=500)
    special_requests: Optional[str] = Field(None, max_length=500)
    # Origin of the response. When set to "whatsapp_button" we suppress the
    # auto-resend of the invitation card (the guest already has it in the
    # same WhatsApp thread) and instead reply with a short text ack.
    source: Optional[str] = Field(None, max_length=64)
    whatsapp_from: Optional[str] = Field(None, max_length=32)


def _status_to_enum(status: str) -> RSVPStatusEnum:
    s = (status or "").lower().strip()
    if s == "confirmed":
        return RSVPStatusEnum.confirmed
    if s == "declined":
        return RSVPStatusEnum.declined
    if s in ("maybe", "tentative"):
        return RSVPStatusEnum.maybe
    raise ValueError(f"Unsupported RSVP status: {status!r}")


def _lookup_by_phone(phone: str, db=None):
    """Find the most recent pending invitation for a phone number.
    Returns dict {code, guest_name} or None. Used by the WhatsApp bot
    when the guest replies with free text (no button payload)."""
    from utils.phone_numbers import normalize_phone
    close = False
    if db is None:
        db = SessionLocal()
        close = True
    try:
        intl = normalize_phone(phone) if phone else None
        if not intl:
            return None
        digits = "".join(c for c in intl if c.isdigit())[-9:]
        if not digits:
            return None
        # Match on the last 9 digits, the project-wide TZ phone convention.
        inv = (
            db.query(EventInvitation)
            .filter(sql_func.right(EventInvitation.guest_phone, 9) == digits)
            .order_by(EventInvitation.created_at.desc())
            .first()
        )
        if not inv:
            return None
        return {
            "code": inv.invitation_code,
            "guest_name": inv.guest_name,
        }
    except Exception:
        return None
    finally:
        if close:
            db.close()


def _respond_internal(db, code: str, status: str) -> bool:
    """Apply an RSVP response from the WhatsApp bot (button or text).
    Mirrors the URL respond endpoint but skips HTTP plumbing and the
    auto-resend of the invitation card. Returns True on success.
    Accepts statuses: confirmed | declined | maybe."""
    if not code:
        return False
    try:
        rsvp_enum = _status_to_enum(status)
    except ValueError:
        return False

    lookup_code = (code or "").strip()
    inv = db.query(EventInvitation).filter(
        EventInvitation.invitation_code == lookup_code
    ).first()
    if not inv:
        try:
            inv = db.query(EventInvitation).join(
                EventAttendee, EventAttendee.invitation_id == EventInvitation.id
            ).filter(EventAttendee.id == lookup_code).order_by(
                EventInvitation.created_at.desc()
            ).first()
        except Exception:
            inv = None
    if not inv:
        return False

    # Refuse to overwrite an invitation that's already been used for check-in.
    existing_att = None
    if inv.guest_type == GuestTypeEnum.user and inv.invited_user_id:
        existing_att = db.query(EventAttendee).filter(
            EventAttendee.event_id == inv.event_id,
            EventAttendee.attendee_id == inv.invited_user_id,
        ).first()
    elif inv.guest_type == GuestTypeEnum.contributor and inv.contributor_id:
        existing_att = db.query(EventAttendee).filter(
            EventAttendee.event_id == inv.event_id,
            EventAttendee.contributor_id == inv.contributor_id,
        ).first()
    else:
        existing_att = db.query(EventAttendee).filter(
            EventAttendee.invitation_id == inv.id,
        ).first()
    if existing_att and getattr(existing_att, "checked_in", False):
        return False

    inv.rsvp_status = rsvp_enum
    inv.rsvp_at = sql_func.now()

    attendee = existing_att
    if not attendee:
        attendee = EventAttendee(
            event_id=inv.event_id,
            guest_type=inv.guest_type or GuestTypeEnum.user,
            attendee_id=inv.invited_user_id if inv.guest_type == GuestTypeEnum.user else None,
            contributor_id=inv.contributor_id if inv.guest_type == GuestTypeEnum.contributor else None,
            guest_name=inv.guest_name,
            invitation_id=inv.id,
            rsvp_status=rsvp_enum,
        )
        db.add(attendee)
    else:
        attendee.rsvp_status = rsvp_enum

    db.commit()
    try:
        from core.redis import invalidate_event_guest_summary
        invalidate_event_guest_summary(str(inv.event_id))
    except Exception:
        pass
    return True



# ── Code Generation ─────────────────────────────────

RSVP_CODE_CHARS = string.ascii_uppercase + string.digits  # A-Z, 0-9
RSVP_CODE_LENGTH = 8  # e.g. "K7X3M9PQ" → nuru.tz/rsvp/K7X3M9PQ

def generate_rsvp_code() -> str:
    """Generate a short, URL-safe, cryptographically secure RSVP code."""
    return ''.join(secrets.choice(RSVP_CODE_CHARS) for _ in range(RSVP_CODE_LENGTH))


# ── Helpers ──────────────────────────────────────────

def _resolve_guest_name(inv: EventInvitation, db) -> str:
    """Return guest display name from invitation record.

    Prefers organiser-supplied ``common_name`` on the matching attendee or
    contributor record so cards render the human-friendly label (e.g.
    "Mr & Mrs Mpinzile") without touching the stored legal name.
    """
    # 1. Attendee common_name takes top priority (set per-event by organiser).
    try:
        attendees = getattr(inv, "attendees", None) or []
        for att in attendees:
            common = (getattr(att, "common_name", None) or "").strip()
            if common:
                return common
    except Exception:
        pass

    # 2. Contributor common_name (global address book override).
    if inv.guest_type == GuestTypeEnum.contributor and inv.contributor_id:
        c = db.query(UserContributor).filter(UserContributor.id == inv.contributor_id).first()
        if c:
            common = (getattr(c, "common_name", None) or "").strip()
            if common:
                return common
            if c.name:
                return c.name

    if inv.guest_name:
        return inv.guest_name
    if inv.guest_type == GuestTypeEnum.user and inv.invited_user_id:
        user = db.query(User).filter(User.id == inv.invited_user_id).first()
        if user:
            parts = [user.first_name, user.last_name]
            return " ".join(p for p in parts if p) or "Guest"
    if inv.guest_type == GuestTypeEnum.contributor and inv.contributor_id:
        c = db.query(UserContributor).filter(UserContributor.id == inv.contributor_id).first()
        if c:
            return c.name or "Guest"
    return "Guest"


def _get_event_image(event: Event, db) -> Optional[str]:
    """Resolve event image using the standard fallback chain."""
    if event.cover_image_url:
        return event.cover_image_url
    img = db.query(EventImage).filter(
        EventImage.event_id == event.id,
        EventImage.is_featured == True
    ).first()
    if img:
        return img.image_url
    img = db.query(EventImage).filter(EventImage.event_id == event.id).first()
    if img:
        return img.image_url
    return None


# ── GET /rsvp/lookup?phone= ──────────────────────────

@router.get("/lookup")
def lookup_by_phone(phone: str):
    """Find the most recent pending invitation for a phone number (WhatsApp bot)."""
    if not phone or len(phone) > 30:
        return standard_response(False, "Invalid phone number")

    # Normalize: strip leading + and spaces
    normalized = phone.strip().lstrip("+").replace(" ", "")
    last9 = normalized[-9:]  # match last 9 digits for flexible lookup

    db = SessionLocal()
    try:
        inv = None

        # 1. Search by registered user phone
        users = db.query(User).filter(
            User.phone.ilike(f"%{last9}")
        ).all()

        if users:
            user_ids = [u.id for u in users]
            inv = db.query(EventInvitation).filter(
                EventInvitation.invited_user_id.in_(user_ids),
                EventInvitation.invitation_code.isnot(None),
            ).order_by(EventInvitation.created_at.desc()).first()

        # 2. If not found, search by contributor phone
        if not inv:
            contributors = db.query(UserContributor).filter(
                UserContributor.phone.ilike(f"%{last9}")
            ).all()

            if contributors:
                contributor_ids = [c.id for c in contributors]
                inv = db.query(EventInvitation).filter(
                    EventInvitation.contributor_id.in_(contributor_ids),
                    EventInvitation.invitation_code.isnot(None),
                ).order_by(EventInvitation.created_at.desc()).first()

        # 3. Fallback: search by guest_phone on the invitation itself
        if not inv:
            inv = db.query(EventInvitation).filter(
                EventInvitation.guest_phone.ilike(f"%{last9}"),
                EventInvitation.invitation_code.isnot(None),
            ).order_by(EventInvitation.created_at.desc()).first()

        if not inv:
            return standard_response(False, "No invitation found for this phone number")

        # Resolve the actual guest name (don't rely on raw guest_name which may be empty)
        guest_name = _resolve_guest_name(inv, db)

        return standard_response(True, "Invitation found", data={
            "code": inv.invitation_code,
            "event_id": str(inv.event_id),
            "guest_name": guest_name,
        })
    finally:
        db.close()


# ── GET /rsvp/{code} ────────────────────────────────

@router.get("/{code}")
def get_rsvp_details(code: str):
    """Fetch event details and guest info for a given invitation code."""
    if not code or len(code) > 200:
        raise HTTPException(status_code=400, detail="Invalid invitation code")

    db = SessionLocal()
    try:
        inv = db.query(EventInvitation).filter(
            EventInvitation.invitation_code == code
        ).first()

        if not inv:
            return standard_response(False, "Invalid or expired invitation link", errors=["NOT_FOUND"])

        event = db.query(Event).filter(Event.id == inv.event_id).first()
        if not event:
            return standard_response(False, "Event not found", errors=["EVENT_NOT_FOUND"])

        # Get the event-owner display name (recognizable name > owner > creator)
        from utils.event_owner import get_event_owner_display_name
        organizer_name = get_event_owner_display_name(event, db=db)

        settings = db.query(EventSetting).filter(EventSetting.event_id == event.id).first()
        vc = db.query(EventVenueCoordinate).filter(EventVenueCoordinate.event_id == event.id).first()

        # Existing attendee record (if already responded)
        attendee = None
        if inv.guest_type == GuestTypeEnum.user and inv.invited_user_id:
            attendee = db.query(EventAttendee).filter(
                EventAttendee.event_id == event.id,
                EventAttendee.attendee_id == inv.invited_user_id
            ).first()
        elif inv.guest_type == GuestTypeEnum.contributor and inv.contributor_id:
            attendee = db.query(EventAttendee).filter(
                EventAttendee.event_id == event.id,
                EventAttendee.contributor_id == inv.contributor_id
            ).first()
        else:
            attendee = db.query(EventAttendee).filter(
                EventAttendee.invitation_id == inv.id
            ).first()

        # Existing plus-ones
        existing_plus_ones = []
        if attendee:
            plus_ones = db.query(EventGuestPlusOne).filter(
                EventGuestPlusOne.attendee_id == attendee.id
            ).all()
            existing_plus_ones = [
                {"name": po.name, "email": po.email, "phone": po.phone, "meal_preference": po.meal_preference}
                for po in plus_ones
            ]

        guest_name = _resolve_guest_name(inv, db)
        event_image = _get_event_image(event, db)

        data = {
            "invitation": {
                "id": str(inv.id),
                "code": inv.invitation_code,
                "rsvp_status": inv.rsvp_status.value if inv.rsvp_status else "pending",
                "guest_name": guest_name,
                "guest_type": inv.guest_type.value if inv.guest_type else "user",
            },
            "event": {
                "id": str(event.id),
                "name": event.name,
                "description": event.description,
                "start_date": event.start_date.isoformat() if event.start_date else None,
                "start_time": event.start_time.strftime("%H:%M") if event.start_time else None,
                "end_date": event.end_date.isoformat() if event.end_date else None,
                "end_time": event.end_time.strftime("%H:%M") if event.end_time else None,
                "location": event.location,
                "venue": vc.venue_name if vc else None,
                "venue_address": vc.formatted_address if vc else None,
                "venue_coordinates": {"latitude": float(vc.latitude), "longitude": float(vc.longitude)} if vc and vc.latitude and float(vc.latitude) != 0 else None,
                "dress_code": event.dress_code,
                "special_instructions": event.special_instructions,
                "image_url": event_image,
                "organizer_name": organizer_name,
            },
            "settings": {
                "allow_plus_ones": settings.allow_plus_ones if settings else False,
                "max_plus_ones": settings.max_plus_ones if settings else 1,
                "require_meal_preference": settings.require_meal_preference if settings else False,
                "meal_options": settings.meal_options if settings else [],
            },
            "current_response": None,
        }

        if attendee:
            data["current_response"] = {
                "rsvp_status": attendee.rsvp_status.value if attendee.rsvp_status else "pending",
                "meal_preference": attendee.meal_preference,
                "dietary_restrictions": attendee.dietary_restrictions,
                "special_requests": attendee.special_requests,
                "plus_ones": existing_plus_ones,
                "checked_in": bool(getattr(attendee, "checked_in", False)),
                "checked_in_at": attendee.checked_in_at.isoformat() if getattr(attendee, "checked_in_at", None) else None,
            }
        data["invitation"]["is_used"] = bool(attendee and getattr(attendee, "checked_in", False))

        return standard_response(True, "RSVP details retrieved", data=data)
    finally:
        db.close()


# ── POST /rsvp/{code}/respond ────────────────────────

@router.post("/{code}/respond")
def respond_to_rsvp(code: str, body: RSVPResponseInput):
    """Submit or update RSVP response for an invitation."""
    if not code or len(code) > 200:
        raise HTTPException(status_code=400, detail="Invalid invitation code")

    db = SessionLocal()
    try:
        inv = db.query(EventInvitation).filter(
            EventInvitation.invitation_code == code
        ).first()

        if not inv:
            return standard_response(False, "Invalid or expired invitation link", errors=["NOT_FOUND"])

        event = db.query(Event).filter(Event.id == inv.event_id).first()
        if not event:
            return standard_response(False, "Event not found", errors=["EVENT_NOT_FOUND"])

        try:
            rsvp_enum = _status_to_enum(body.rsvp_status)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid RSVP status")

        # If guest already checked in (manually by organizer or via QR scan),
        # the invitation is "used" and cannot be modified.
        existing_att = None
        if inv.guest_type == GuestTypeEnum.user and inv.invited_user_id:
            existing_att = db.query(EventAttendee).filter(
                EventAttendee.event_id == event.id,
                EventAttendee.attendee_id == inv.invited_user_id,
            ).first()
        elif inv.guest_type == GuestTypeEnum.contributor and inv.contributor_id:
            existing_att = db.query(EventAttendee).filter(
                EventAttendee.event_id == event.id,
                EventAttendee.contributor_id == inv.contributor_id,
            ).first()
        else:
            existing_att = db.query(EventAttendee).filter(
                EventAttendee.invitation_id == inv.id,
            ).first()
        if existing_att and getattr(existing_att, "checked_in", False):
            return standard_response(
                False,
                "This invitation has already been used for check-in and can no longer be changed.",
                errors=["ALREADY_USED"],
            )

        # Update invitation record
        inv.rsvp_status = rsvp_enum
        inv.rsvp_at = sql_func.now()

        # Find or create attendee record
        attendee = None
        if inv.guest_type == GuestTypeEnum.user and inv.invited_user_id:
            attendee = db.query(EventAttendee).filter(
                EventAttendee.event_id == event.id,
                EventAttendee.attendee_id == inv.invited_user_id
            ).first()
        elif inv.guest_type == GuestTypeEnum.contributor and inv.contributor_id:
            attendee = db.query(EventAttendee).filter(
                EventAttendee.event_id == event.id,
                EventAttendee.contributor_id == inv.contributor_id
            ).first()
        else:
            attendee = db.query(EventAttendee).filter(
                EventAttendee.invitation_id == inv.id
            ).first()

        if not attendee:
            attendee = EventAttendee(
                event_id=event.id,
                guest_type=inv.guest_type or GuestTypeEnum.user,
                attendee_id=inv.invited_user_id if inv.guest_type == GuestTypeEnum.user else None,
                contributor_id=inv.contributor_id if inv.guest_type == GuestTypeEnum.contributor else None,
                guest_name=inv.guest_name,
                invitation_id=inv.id,
                rsvp_status=rsvp_enum,
            )
            db.add(attendee)
        else:
            attendee.rsvp_status = rsvp_enum

        # Update preferences
        if body.meal_preference is not None:
            attendee.meal_preference = body.meal_preference
        if body.dietary_restrictions is not None:
            attendee.dietary_restrictions = body.dietary_restrictions
        if body.special_requests is not None:
            attendee.special_requests = body.special_requests


        db.commit()
        try:
            from core.redis import invalidate_event_guest_summary
            invalidate_event_guest_summary(str(event.id))
        except Exception:
            pass

        status_label = rsvp_enum.value

        is_whatsapp_button = (body.source or "").lower() == "whatsapp_button"

        # Resolve guest phone + display name once (used by both branches).
        guest_phone = None
        guest_display = inv.guest_name or "Guest"
        try:
            from models.users import User as _U
            if inv.invited_user_id:
                u = db.query(_U).filter(_U.id == inv.invited_user_id).first()
                if u:
                    guest_phone = u.phone
                    guest_display = (
                        f"{u.first_name or ''} {u.last_name or ''}".strip()
                        or guest_display
                    )
            if not guest_phone:
                guest_phone = getattr(inv, "guest_phone", None)
        except Exception:
            guest_phone = guest_phone or getattr(inv, "guest_phone", None)
        if not guest_phone and body.whatsapp_from:
            guest_phone = body.whatsapp_from

        try:
            from utils.wa_logging import set_wa_log_context
            set_wa_log_context(
                event_id=str(event.id),
                event_name=event.name,
                source_module="rsvp",
                purpose="rsvp_response",
                recipient_type="guest",
            )
        except Exception:
            pass

        if is_whatsapp_button:
            # Guest tapped a quick-reply on the invitation card already in
            # their WhatsApp thread. Don't resend the card — just send a
            # short bilingual text acknowledgement. Use the FULL guest
            # name (not just the first token) and ASCII-only punctuation
            # (no em dashes, no curly quotes) so the message renders
            # identically across Android, iOS and WhatsApp Web.
            try:
                from utils.whatsapp import _send_whatsapp_text
                full_name = (guest_display or "").strip() or "rafiki"
                event_label = event.name or "the event"
                if rsvp_enum == RSVPStatusEnum.confirmed:
                    msg = (
                        f"Asante {full_name}! Tumepokea jibu lako. "
                        f"Umethibitisha kuhudhuria {event_label}. Karibu sana!\n\n"
                        f"Thank you {full_name}! Your response has been received. "
                        f"You have confirmed attendance for {event_label}. See you there!"
                    )
                elif rsvp_enum == RSVPStatusEnum.declined:
                    msg = (
                        f"Asante {full_name} kwa kujibu. Tumepokea taarifa kuwa "
                        f"hutaweza kuhudhuria {event_label}. Tutakukumbuka.\n\n"
                        f"Thanks {full_name} for letting us know. Your response has "
                        f"been received. We are sorry you cannot make it to {event_label}."
                    )
                else:  # maybe
                    msg = (
                        f"Asante {full_name}. Tumepokea jibu lako la \"labda\" "
                        f"kwa {event_label}. Unaweza kubadilisha jibu wakati wowote.\n\n"
                        f"Thanks {full_name}. Your \"maybe\" response for "
                        f"{event_label} has been received. You can update it any time."
                    )
                if guest_phone:
                    _send_whatsapp_text(guest_phone, msg)
            except Exception as _e:
                print(f"[rsvp] whatsapp_button ack failed: {_e}")
        elif rsvp_enum == RSVPStatusEnum.confirmed:
            # Web/URL confirmation — auto-send the invitation card so the
            # guest receives it on WhatsApp (fire-and-forget).
            try:
                from utils.whatsapp_cards import wa_send_invitation_card
                from utils.event_owner import get_event_owner_display_name
                organizer_name = get_event_owner_display_name(
                    event, db=db, fallback="Your host"
                )
                event_date = ""
                try:
                    if getattr(event, "start_date", None):
                        event_date = event.start_date.strftime("%a, %-d %b %Y")
                except Exception:
                    try:
                        event_date = event.start_date.strftime("%a, %d %b %Y") if getattr(event, "start_date", None) else ""
                    except Exception:
                        pass
                if guest_phone:
                    wa_send_invitation_card(
                        phone=guest_phone,
                        event_id=str(event.id),
                        guest_id=str(inv.id),
                        guest_name=guest_display,
                        event_name=event.name or "the event",
                        event_date=event_date or "",
                        organizer_name=organizer_name,
                        rsvp_code=inv.invitation_code or "",
                        cover_image=getattr(event, "cover_image_url", None) or "",
                        event_time=getattr(event, "start_time", None).isoformat() if getattr(event, "start_time", None) else "",
                        venue=getattr(event, "location", None) or "",
                    )
            except Exception as _e:
                print(f"[rsvp] wa_send_invitation_card failed: {_e}")


        return standard_response(True, f"Your RSVP has been {status_label} successfully", data={
            "rsvp_status": status_label,
            "event_name": event.name,
        })
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        db.close()
