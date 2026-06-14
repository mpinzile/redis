# User Events Routes - /user-events/...
# Handles event management for authenticated users

import json
import math
import os
import re
import uuid
from collections import defaultdict
from datetime import datetime
from typing import List, Optional

import httpx
import pytz
from fastapi import APIRouter, Depends, File, Form, UploadFile, Body, Query
from sqlalchemy import func as sa_func, or_
from sqlalchemy.orm import Session

from core.config import ALLOWED_IMAGE_EXTENSIONS, MAX_EVENT_IMAGES, MAX_IMAGE_SIZE, UPLOAD_SERVICE_URL
from core.database import get_db
from models import (
    Event, EventType, EventImage, EventVenueCoordinate, EventSetting,
    EventCommitteeMember, CommitteeRole, CommitteePermission,
    EventContributionTarget, EventContributor, EventContribution,
    ContributionThankYouMessage, UserContributor,
    EventInvitation, EventAttendee, EventGuestPlusOne,
    EventService, EventServicePayment, EventScheduleItem, EventBudgetItem,
    EventExpense, EventTicket, EventTicketClass,
    Currency, User, UserProfile, UserSocialAccount, ServiceType, UserService,
    EventServiceStatusEnum, EventStatusEnum, PaymentMethodEnum, RSVPStatusEnum,
    GuestTypeEnum, EventTypeService, ServicePackage, TicketOrderStatusEnum,
    EventSponsor,
)
from utils.auth import get_current_user
from utils.helpers import format_price, standard_response, format_phone_display
from api.routes.rsvp import generate_rsvp_code
from utils.validation_functions import validate_phone_number
from utils.event_owner import get_event_owner_display_name, user_can_manage_event
from utils.sms import (
    sms_guest_added, sms_committee_invite, sms_contribution_recorded,
    sms_contribution_target_set, sms_thank_you, sms_booking_notification,
)
from utils.whatsapp_cards import wa_send_invitation_card, wa_send_invitation_text

EAT = pytz.timezone("Africa/Nairobi")
HEX_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
VALID_STATUS_FILTERS = {"draft", "confirmed", "published", "cancelled", "completed", "all"}


def _wa_event_date(event) -> str:
    try:
        if getattr(event, "start_date", None):
            return event.start_date.strftime("%a, %-d %b %Y")
    except Exception:
        try:
            return event.start_date.strftime("%a, %d %b %Y")
        except Exception:
            return ""
    return ""


def _wa_event_cover_image(db: Session, event: Event) -> str:
    cover = (getattr(event, "cover_image_url", None) or "").strip()
    if cover:
        return cover
    try:
        image = (
            db.query(EventImage)
            .filter(EventImage.event_id == event.id)
            .order_by(EventImage.is_featured.desc(), EventImage.created_at.asc())
            .first()
        )
        return (getattr(image, "image_url", None) or "").strip() if image else ""
    except Exception as e:
        print(f"[wa_cards] cover fallback lookup failed event_id={getattr(event, 'id', '')}: {e}")
        return ""


def _user_avatar_url(db: Session, user_id) -> str | None:
    """Resolve the visible user avatar from profile first, then social login."""
    if not user_id:
        return None
    profile = db.query(UserProfile).filter(UserProfile.user_id == user_id).first()
    avatar = (profile.profile_picture_url if profile else None) or ""
    if avatar.strip():
        return avatar.strip()
    social = db.query(UserSocialAccount).filter(
        UserSocialAccount.user_id == user_id,
        UserSocialAccount.is_active == True,
    ).first()
    social_avatar = (social.provider_avatar_url if social else None) or ""
    return social_avatar.strip() or None


def _parse_what_to_expect(raw: Optional[str]):
    """Accepts a JSON string from multipart Form. Returns a sanitized list
    of {icon, label, description?} items, or None when empty/invalid."""
    if not raw:
        return None
    txt = raw.strip()
    if not txt:
        return None
    try:
        data = json.loads(txt)
    except Exception:
        return None
    if not isinstance(data, list):
        return None
    out = []
    for it in data:
        if not isinstance(it, dict):
            continue
        label = (it.get("label") or it.get("title") or "").strip()
        if not label:
            continue
        icon = (it.get("icon") or "sparkle").strip() or "sparkle"
        desc = (it.get("description") or "").strip() or None
        out.append({"icon": icon, "label": label, "description": desc})
        if len(out) >= 12:
            break
    return out or None


def _parse_extra_details(raw: Optional[str]):
    """Accepts a JSON string from multipart Form. Returns a sanitized list
    of {label, details} items, or None when empty/invalid. Max 20 rows."""
    if not raw:
        return None
    txt = raw.strip()
    if not txt:
        return None
    try:
        data = json.loads(txt)
    except Exception:
        return None
    if not isinstance(data, list):
        return None
    out = []
    for it in data:
        if not isinstance(it, dict):
            continue
        label = (it.get("label") or it.get("title") or "").strip()
        details = (it.get("details") or it.get("description") or it.get("value") or "").strip()
        if not label or not details:
            continue
        out.append({"label": label[:80], "details": details[:600]})
        if len(out) >= 20:
            break
    return out or None


def _initial_status(raw: Optional[str]):
    """Map an incoming `status` form value to an EventStatusEnum.

    Accepts "draft", "published" (-> confirmed), "confirmed". Defaults to
    `confirmed` when the caller is publishing an event (omitted/unknown
    values that aren't explicitly "draft" become published) so finished
    events do not show up in the user's draft bucket. Pass "draft" to keep
    a work-in-progress event hidden from public lists.
    """
    if raw is None:
        return EventStatusEnum.confirmed
    val = raw.strip().lower()
    if val in {"draft"}:
        return EventStatusEnum.draft
    if val in {"published", "confirmed", "active"}:
        return EventStatusEnum.confirmed
    return EventStatusEnum.confirmed


router = APIRouter(prefix="/user-events", tags=["User Events"])


# ──────────────────────────────────────────────
# Shared Helpers
# ──────────────────────────────────────────────

def _vendor_summary(vendor) -> dict | None:
    """Return a compact vendor summary for budget items and expenses."""
    if not vendor:
        return None
    primary_image = None
    if hasattr(vendor, 'images') and vendor.images:
        for img in vendor.images:
            if getattr(img, 'is_primary', False):
                primary_image = img.image_url if hasattr(img, 'image_url') else getattr(img, 'url', None)
                break
        if not primary_image and vendor.images:
            first_img = vendor.images[0]
            primary_image = first_img.image_url if hasattr(first_img, 'image_url') else getattr(first_img, 'url', None)
    return {
        "id": str(vendor.id),
        "title": vendor.title,
        "category_name": vendor.category.name if vendor.category else None,
        "service_type_name": vendor.service_type.name if vendor.service_type else None,
        "location": vendor.location,
        "primary_image": primary_image,
        "is_verified": vendor.is_verified,
    }

def _currency_code(db: Session, currency_id) -> str | None:
    if not currency_id:
        return None
    cur = db.query(Currency).filter(Currency.id == currency_id).first()
    return cur.code.strip() if cur else None


def _event_currency_code(db: Session, event: Event) -> str:
    code = _currency_code(db, event.currency_id)
    if code:
        return code.upper()
    profile = db.query(UserProfile).filter(UserProfile.user_id == event.organizer_id).first()
    profile_code = (profile.currency_code or "").strip().upper() if profile else ""
    return profile_code or "TZS"


def _public_event_detail_extras(db: Session, event: Event) -> dict:
    extras = {
        "currency": _event_currency_code(db, event),
        "going_count": 0,
        "going_avatars": [],
        "contribution_payment_instructions": event.contribution_payment_instructions,
    }

    ticket_classes = db.query(EventTicketClass).filter(EventTicketClass.event_id == event.id).all()
    if ticket_classes or event.sells_tickets:
        sold_by_class = {}
        if ticket_classes:
            for class_id, qty in db.query(
                EventTicket.ticket_class_id,
                sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0),
            ).filter(
                EventTicket.event_id == event.id,
                EventTicket.status.notin_([TicketOrderStatusEnum.rejected, TicketOrderStatusEnum.cancelled]),
            ).group_by(EventTicket.ticket_class_id).all():
                sold_by_class[class_id] = int(qty or 0)
        prices = [float(tc.price) for tc in ticket_classes if tc.price is not None]
        extras.update({
            "has_tickets": True,
            "min_price": min(prices) if prices else None,
            "ticket_class_count": len(ticket_classes),
            "total_available": sum(max(0, int(tc.quantity or 0) - sold_by_class.get(tc.id, 0)) for tc in ticket_classes),
        })

    confirmed_statuses = [RSVPStatusEnum.confirmed, RSVPStatusEnum.checked_in]
    attendees = db.query(EventAttendee).filter(
        EventAttendee.event_id == event.id,
        EventAttendee.rsvp_status.in_(confirmed_statuses),
    ).order_by(EventAttendee.updated_at.desc(), EventAttendee.created_at.desc()).limit(40).all()
    extras["going_count"] = db.query(sa_func.count(EventAttendee.id)).filter(
        EventAttendee.event_id == event.id,
        EventAttendee.rsvp_status.in_(confirmed_statuses),
    ).scalar() or 0

    invitation_ids = [a.invitation_id for a in attendees if a.invitation_id]
    invitations = {i.id: i for i in db.query(EventInvitation).filter(EventInvitation.id.in_(invitation_ids)).all()} if invitation_ids else {}
    user_ids = {a.attendee_id for a in attendees if a.attendee_id}
    user_ids |= {i.invited_user_id for i in invitations.values() if i.invited_user_id}
    contributor_ids = {a.contributor_id for a in attendees if a.contributor_id}
    contributor_ids |= {i.contributor_id for i in invitations.values() if i.contributor_id}
    users = {u.id: u for u in db.query(User).filter(User.id.in_(list(user_ids))).all()} if user_ids else {}
    profiles = {p.user_id: p for p in db.query(UserProfile).filter(UserProfile.user_id.in_(list(user_ids))).all()} if user_ids else {}
    socials = {}
    if user_ids:
        for s in db.query(UserSocialAccount).filter(UserSocialAccount.user_id.in_(list(user_ids)), UserSocialAccount.is_active == True).all():
            socials.setdefault(s.user_id, s)
    contributors = {c.id: c for c in db.query(UserContributor).filter(UserContributor.id.in_(list(contributor_ids))).all()} if contributor_ids else {}

    avatars = []
    seen = set()
    for att in attendees:
        if len(avatars) >= 8:
            break
        inv = invitations.get(att.invitation_id) if att.invitation_id else None
        uid = att.attendee_id or (inv.invited_user_id if inv else None)
        cid = att.contributor_id or (inv.contributor_id if inv else None)
        if uid and uid in users:
            user = users[uid]
            profile = profiles.get(uid)
            social = socials.get(uid)
            name = f"{user.first_name or ''} {user.last_name or ''}".strip() or user.username or "Guest"
            key = f"user:{uid}"
            avatar = (profile.profile_picture_url if profile else None) or (social.provider_avatar_url if social else None)
        elif cid and cid in contributors:
            contributor = contributors[cid]
            name = contributor.name or att.guest_name or (inv.guest_name if inv else None) or "Guest"
            key = f"contributor:{cid}"
            avatar = None
        else:
            name = att.guest_name or (inv.guest_name if inv else None) or "Guest"
            key = f"guest:{att.id}"
            avatar = None
        if key in seen:
            continue
        seen.add(key)
        avatars.append({"id": key.split(":", 1)[1], "name": name, "avatar": avatar})
    extras["going_avatars"] = avatars
    return extras


def _event_images(db: Session, event_id) -> list[dict]:
    rows = db.query(EventImage).filter(EventImage.event_id == event_id).order_by(EventImage.is_featured.desc(), EventImage.created_at.asc()).all()
    return [{"id": str(img.id), "image_url": img.image_url, "caption": img.caption, "is_featured": img.is_featured, "created_at": img.created_at.isoformat() if img.created_at else None} for img in rows]


def _pick_cover_image(event, images: list[dict]) -> str | None:
    if event.cover_image_url:
        return event.cover_image_url
    for img in images:
        if img.get("is_featured"):
            return img["image_url"]
    if images:
        return images[0]["image_url"]
    return None


def _guest_counts(db: Session, event_id) -> dict:
    rows = db.query(EventAttendee.rsvp_status, sa_func.count(EventAttendee.id)).filter(EventAttendee.event_id == event_id).group_by(EventAttendee.rsvp_status).all()
    counts = {r.value: 0 for r in RSVPStatusEnum}
    total = 0
    for status, cnt in rows:
        key = status.value if hasattr(status, "value") else status
        counts[key] = cnt
        total += cnt
    checked_in = db.query(sa_func.count(EventAttendee.id)).filter(EventAttendee.event_id == event_id, EventAttendee.checked_in == True).scalar() or 0
    return {"guest_count": total, "confirmed_guest_count": counts.get("confirmed", 0), "pending_guest_count": counts.get("pending", 0), "declined_guest_count": counts.get("declined", 0), "checked_in_count": checked_in}


def _contribution_summary(db: Session, event_id) -> dict:
    result = db.query(sa_func.coalesce(sa_func.sum(EventContribution.amount), 0), sa_func.count(EventContribution.id)).filter(EventContribution.event_id == event_id, EventContribution.confirmation_status == "confirmed").first()
    return {"contribution_total": float(result[0]), "contribution_count": result[1]}


def _event_summary(db: Session, event: Event) -> dict:
    event_type = db.query(EventType).filter(EventType.id == event.event_type_id).first()
    gc = _guest_counts(db, event.id)
    cs = _contribution_summary(db, event.id)
    settings = db.query(EventSetting).filter(EventSetting.event_id == event.id).first()
    vc = db.query(EventVenueCoordinate).filter(EventVenueCoordinate.event_id == event.id).first()
    committee_count = db.query(sa_func.count(EventCommitteeMember.id)).filter(EventCommitteeMember.event_id == event.id).scalar() or 0
    service_count = db.query(sa_func.count(EventService.id)).filter(EventService.event_id == event.id).scalar() or 0
    images = _event_images(db, event.id)

    contribution_target = 0
    ct = db.query(EventContributionTarget).filter(EventContributionTarget.event_id == event.id).first()
    if settings and settings.contribution_target_amount:
        contribution_target = float(settings.contribution_target_amount)
    elif ct:
        contribution_target = float(ct.target_amount)

    return {
        "id": str(event.id), "user_id": str(event.organizer_id), "title": event.name,
        "description": event.description,
        "event_type_id": str(event.event_type_id) if event.event_type_id else None,
        "event_type": {"id": str(event_type.id), "name": event_type.name, "icon": event_type.icon} if event_type else None,
        "start_date": event.start_date.isoformat() if event.start_date else None,
        "start_time": event.start_time.strftime("%H:%M") if event.start_time else None,
        "end_date": event.end_date.isoformat() if event.end_date else None,
        "end_time": event.end_time.strftime("%H:%M") if event.end_time else None,
        "location": event.location,
        "venue": vc.venue_name if vc else None,
        "venue_address": vc.formatted_address if vc else None,
        "venue_coordinates": {"latitude": float(vc.latitude), "longitude": float(vc.longitude)} if vc and vc.latitude else None,
        "cover_image": _pick_cover_image(event, images), "images": images,
        "theme_color": event.theme_color, "is_public": event.is_public,
        "sells_tickets": event.sells_tickets or False,
        "ticket_approval_status": event.ticket_approval_status.value if event.ticket_approval_status and hasattr(event.ticket_approval_status, 'value') else "pending",
        "ticket_rejection_reason": event.ticket_rejection_reason,
        "ticket_removed_reason": event.ticket_removed_reason,
        "status": event.status.value if hasattr(event.status, "value") else event.status,
        "budget": float(event.budget) if event.budget else None,
        "currency": _currency_code(db, event.currency_id),
        "dress_code": event.dress_code, "special_instructions": event.special_instructions,
        "extra_details": event.extra_details,
        "guest_of_honor": event.guest_of_honor,
        "what_to_expect": event.what_to_expect, "what_to_expect_notes": event.what_to_expect_notes,
        "invitation_template_id": event.invitation_template_id,
        "invitation_accent_color": event.invitation_accent_color,
        "invitation_sample_names": event.invitation_sample_names,
        "invitation_content": event.invitation_content,
        "reminder_contact_phone": event.reminder_contact_phone,
        "contribution_payment_instructions": event.contribution_payment_instructions,
        "rsvp_deadline": settings.rsvp_deadline.isoformat() if settings and settings.rsvp_deadline else None,
        "contribution_enabled": settings.contributions_enabled if settings else False,
        "contribution_target": contribution_target,
        "contribution_description": ct.description if ct else None,
        "expected_guests": event.expected_guests,
        **gc, **cs,
        "committee_count": committee_count, "service_booking_count": service_count,
        "created_at": event.created_at.isoformat() if event.created_at else None,
        "updated_at": event.updated_at.isoformat() if event.updated_at else None,
    }


async def _upload_image(file: UploadFile, target_folder: str) -> dict:
    _, ext = os.path.splitext(file.filename or "unknown.jpg")
    ext = ext.lower().replace(".", "")
    if ext not in ALLOWED_IMAGE_EXTENSIONS:
        return {"success": False, "url": None, "error": f"File '{file.filename}' has invalid format."}
    content = await file.read()
    if len(content) > MAX_IMAGE_SIZE:
        file_mb = round(len(content) / (1024 * 1024), 1)
        max_mb = round(MAX_IMAGE_SIZE / (1024 * 1024), 1)
        return {"success": False, "url": None, "error": f"File '{file.filename}' is too large ({file_mb}MB). Maximum allowed size is {max_mb}MB."}
    unique_name = f"{uuid.uuid4().hex}.{ext}"
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(UPLOAD_SERVICE_URL, data={"target_path": target_folder}, files={"file": (unique_name, content, file.content_type)}, timeout=20)
        except Exception as e:
            return {"success": False, "url": None, "error": f"Upload failed: {str(e)}"}
    if resp.status_code != 200:
        return {"success": False, "url": None, "error": f"Upload service returned {resp.status_code}."}
    result = resp.json()
    if not result.get("success"):
        return {"success": False, "url": None, "error": result.get("message", "Upload failed.")}
    return {"success": True, "url": result["data"]["url"], "error": None}


def _verify_event_access(db: Session, event_id, current_user, required_permission: str = None):
    """
    Verify event access with optional permission check.
    If required_permission is None: any committee member or creator can access (view-only).
    If required_permission is set: creator always passes; committee needs that permission.
    Returns (event, error_response).
    """
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        return None, standard_response(False, "Event not found")

    is_creator = str(event.organizer_id) == str(current_user.id)
    if is_creator:
        return event, None

    cm = db.query(EventCommitteeMember).filter(
        EventCommitteeMember.event_id == event_id,
        EventCommitteeMember.user_id == current_user.id,
    ).first()
    if not cm:
        return None, standard_response(False, "You do not have permission to access this event")

    if not required_permission:
        return event, None

    perms = db.query(CommitteePermission).filter(
        CommitteePermission.committee_member_id == cm.id
    ).first()
    if not perms or not getattr(perms, required_permission, False):
        return None, standard_response(False, "You do not have permission to perform this action")

    return event, None


PERMISSION_FIELDS = [
    "can_view_guests", "can_manage_guests", "can_send_invitations", "can_check_in_guests",
    "can_view_budget", "can_manage_budget", "can_view_contributions", "can_manage_contributions",
    "can_view_vendors", "can_manage_vendors", "can_approve_bookings", "can_edit_event", "can_manage_committee",
    "can_view_expenses", "can_manage_expenses",
]

PERMISSION_MAP = {
    "view_guests": "can_view_guests", "manage_guests": "can_manage_guests",
    "send_invitations": "can_send_invitations", "checkin_guests": "can_check_in_guests",
    "view_budget": "can_view_budget", "manage_budget": "can_manage_budget",
    "view_contributions": "can_view_contributions", "manage_contributions": "can_manage_contributions",
    "view_vendors": "can_view_vendors", "manage_vendors": "can_manage_vendors",
    "approve_bookings": "can_approve_bookings", "edit_event": "can_edit_event",
    "manage_committee": "can_manage_committee",
    "view_expenses": "can_view_expenses", "manage_expenses": "can_manage_expenses",
}


# ──────────────────────────────────────────────
# Get Current User's Permissions for an Event
# ──────────────────────────────────────────────
@router.get("/{event_id}/my-permissions")
def get_my_permissions(
    event_id: str,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    """Returns the current user's role and permissions for a given event."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    is_creator = str(event.organizer_id) == str(current_user.id)
    print(f"[my-permissions] user_id={current_user.id} event_id={event_id} is_creator={is_creator}")

    if is_creator:
        # Creator has all permissions
        perms = {field: True for field in PERMISSION_FIELDS}
        payload = {"is_creator": True, "role": "creator", **perms}
        print(f"[my-permissions] payload={payload}")
        return standard_response(True, "Permissions retrieved", payload)

    cm = db.query(EventCommitteeMember).filter(
        EventCommitteeMember.event_id == eid,
        EventCommitteeMember.user_id == current_user.id,
    ).first()
    if not cm:
        perms = {field: False for field in PERMISSION_FIELDS}
        payload = {"is_creator": False, "role": None, **perms}
        print(f"[my-permissions] payload={payload}")
        return standard_response(True, "Permissions retrieved", payload)

    role_obj = db.query(CommitteeRole).filter(CommitteeRole.id == cm.role_id).first() if cm.role_id else None
    perm_row = db.query(CommitteePermission).filter(CommitteePermission.committee_member_id == cm.id).first()

    perms = {}
    for field in PERMISSION_FIELDS:
        perms[field] = bool(getattr(perm_row, field, False)) if perm_row else False

    # Auto-grant view when manage is granted (defensive, should already be set in DB)
    if perms.get("can_manage_contributions"):
        perms["can_view_contributions"] = True
    if perms.get("can_manage_budget"):
        perms["can_view_budget"] = True
    if perms.get("can_manage_guests"):
        perms["can_view_guests"] = True
    if perms.get("can_manage_vendors"):
        perms["can_view_vendors"] = True
    if perms.get("can_manage_expenses"):
        perms["can_view_expenses"] = True

    payload = {
        "is_creator": False,
        "role": role_obj.role_name if role_obj else "member",
        **perms,
    }
    print(f"[my-permissions] payload={payload}")
    return standard_response(True, "Permissions retrieved", payload)


# ──────────────────────────────────────────────
# Management Overview — aggregated KPIs for the Event Management dashboard
# ──────────────────────────────────────────────
@router.get("/{event_id}/management-overview")
def get_management_overview(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Returns Event Overview KPIs, ticket sales breakdown, revenue summary,
    contribution status and sponsor totals — all derived from real data."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    # ── Ticket sales (per class)
    classes = db.query(EventTicketClass).filter(EventTicketClass.event_id == eid).order_by(EventTicketClass.display_order).all()
    ticket_classes_payload = []
    tickets_sold = 0
    tickets_capacity = 0
    ticket_revenue = 0.0
    for tc in classes:
        sold_q = db.query(
            sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0),
            sa_func.coalesce(sa_func.sum(EventTicket.total_amount), 0),
        ).filter(
            EventTicket.ticket_class_id == tc.id,
            # Only count tickets with verified payments (confirmed or admin-approved)
            EventTicket.status.in_([TicketOrderStatusEnum.confirmed, TicketOrderStatusEnum.approved]),
        ).first()
        sold = int(sold_q[0] or 0)
        rev = float(sold_q[1] or 0)
        tickets_sold += sold
        tickets_capacity += tc.quantity or 0
        ticket_revenue += rev
        ticket_classes_payload.append({
            "id": str(tc.id), "name": tc.name,
            "price": float(tc.price), "quantity": tc.quantity,
            "sold": sold, "revenue": rev,
        })

    # ── Contribution totals (paid + pledged)
    paid_total = float(db.query(sa_func.coalesce(sa_func.sum(EventContribution.amount), 0)).filter(
        EventContribution.event_id == eid,
        EventContribution.confirmation_status == "confirmed",
    ).scalar() or 0)
    paid_count = int(db.query(sa_func.count(EventContribution.id)).filter(
        EventContribution.event_id == eid,
        EventContribution.confirmation_status == "confirmed",
    ).scalar() or 0)
    pledged_total = float(db.query(sa_func.coalesce(sa_func.sum(EventContributor.pledge_amount), 0)).filter(
        EventContributor.event_id == eid,
    ).scalar() or 0)
    pledged_count = int(db.query(sa_func.count(EventContributor.id)).filter(
        EventContributor.event_id == eid,
    ).scalar() or 0)

    # ── Sponsors
    sponsors = db.query(EventSponsor).filter(EventSponsor.event_id == eid).all()
    sponsor_revenue = sum(float(s.contribution_amount or 0) for s in sponsors if s.status == "accepted")
    sponsor_summary = {
        "total": len(sponsors),
        "accepted": sum(1 for s in sponsors if s.status == "accepted"),
        "pending": sum(1 for s in sponsors if s.status == "pending"),
        "declined": sum(1 for s in sponsors if s.status == "declined"),
        "revenue": sponsor_revenue,
    }

    # ── Days to go
    days_to_go = 0
    if event.start_date:
        delta = (event.start_date - datetime.utcnow().date()).days if hasattr(event.start_date, 'year') else 0
        days_to_go = max(0, delta)

    # ── Revenue trend vs previous 7 days (tickets only — confirmed contributions also)
    from datetime import timedelta
    now = datetime.utcnow()
    last7_start = now - timedelta(days=7)
    prev7_start = now - timedelta(days=14)
    def _rev_window(start, end):
        t = float(db.query(sa_func.coalesce(sa_func.sum(EventTicket.total_amount), 0)).filter(
            EventTicket.event_id == eid,
            EventTicket.status.notin_([TicketOrderStatusEnum.rejected, TicketOrderStatusEnum.cancelled]),
            EventTicket.created_at >= start, EventTicket.created_at < end,
        ).scalar() or 0)
        c = float(db.query(sa_func.coalesce(sa_func.sum(EventContribution.amount), 0)).filter(
            EventContribution.event_id == eid,
            EventContribution.confirmation_status == "confirmed",
            EventContribution.created_at >= start, EventContribution.created_at < end,
        ).scalar() or 0)
        return t + c
    last7 = _rev_window(last7_start, now)
    prev7 = _rev_window(prev7_start, last7_start)
    trend_pct = None
    if prev7 > 0:
        trend_pct = round(((last7 - prev7) / prev7) * 100)
    elif last7 > 0:
        trend_pct = 100

    total_revenue = ticket_revenue + paid_total + sponsor_revenue
    is_ticketed = bool(event.sells_tickets) and len(classes) > 0

    return standard_response(True, "Overview retrieved", {
        "is_ticketed": is_ticketed,
        "kpis": {
            "tickets_sold": tickets_sold,
            "tickets_capacity": tickets_capacity,
            "total_revenue": total_revenue,
            "contributions_count": pledged_count or paid_count,
            "days_to_go": days_to_go,
        },
        "ticket_sales": {
            "total_sold": tickets_sold,
            "total_capacity": tickets_capacity,
            "classes": ticket_classes_payload,
        },
        "contribution_status": {
            "paid_count": paid_count,
            "pledged_count": pledged_count,
            "outstanding_count": max(0, pledged_count - paid_count),
            "paid_total": paid_total,
            "pledged_total": pledged_total,
        },
        "revenue_summary": {
            "total_revenue": total_revenue,
            "tickets": ticket_revenue,
            "contributions": paid_total,
            "sponsors": sponsor_revenue,
            "trend_pct": trend_pct,
            "trend_window_days": 7,
        },
        "sponsors": sponsor_summary,
    })



# ──────────────────────────────────────────────
@router.get("/")
def get_all_user_events(
    page: int = 1, limit: int = 20, status: str = "all",
    sort_by: str = "created_at", sort_order: str = "desc",
    search: Optional[str] = None,
    created_only: bool = False,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    """Returns events where the user is the creator OR the recorded event owner.

    Pass ``created_only=true`` to restrict the result to events the user
    actually created (``organizer_id == current_user.id``). Used by the
    mobile **My Events** tab so events the user was only invited to, or
    events recorded against them as ``event_owner_user_id`` by someone else,
    never leak into the creator list.
    """
    if status not in VALID_STATUS_FILTERS:
        return standard_response(False, f"Invalid status filter. Must be one of: {', '.join(VALID_STATUS_FILTERS)}")

    if created_only:
        query = db.query(Event).filter(Event.organizer_id == current_user.id)
    else:
        # Include both creator-owned events AND events the user owns via event_owner_user_id
        query = db.query(Event).filter(or_(
            Event.organizer_id == current_user.id,
            Event.event_owner_user_id == current_user.id,
        ))

    if status != "all":
        mapped = status
        if hasattr(EventStatusEnum, mapped):
            query = query.filter(Event.status == getattr(EventStatusEnum, mapped))

    if search:
        term = f"%{search.strip().lower()}%"
        query = query.filter(or_(
            sa_func.lower(Event.name).like(term),
            sa_func.lower(Event.location).like(term),
            sa_func.lower(Event.description).like(term),
        ))

    sort_col = {"created_at": Event.created_at, "start_date": Event.start_date, "title": Event.name}.get(sort_by, Event.created_at)
    query = query.order_by(sort_col.desc() if sort_order == "desc" else sort_col.asc())

    total = query.count()
    total_pages = max(1, math.ceil(total / limit))
    events = query.offset((page - 1) * limit).limit(limit).all()

    from utils.batch_loaders import build_event_summaries
    return standard_response(True, "Events retrieved successfully", {
        "events": build_event_summaries(db, events),
        "pagination": {"page": page, "limit": limit, "total_items": total, "total_pages": total_pages, "has_next": page < total_pages, "has_previous": page > 1},
    })


# ──────────────────────────────────────────────
# Get Events Where User Is Invited
# ──────────────────────────────────────────────
@router.get("/invited")
def get_invited_events(
    page: int = 1, limit: int = 20,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    """Returns events the current user has been invited to, with RSVP status."""
    # 1. Direct invitations by invited_user_id
    invitations = (
        db.query(EventInvitation)
        .filter(EventInvitation.invited_user_id == current_user.id)
        .order_by(EventInvitation.created_at.desc())
        .all()
    )
    inv_map = {inv.event_id: inv for inv in invitations}

    # 2. Also find events via EventAttendee (covers cases where invited_user_id is NULL)
    attendee_records = (
        db.query(EventAttendee)
        .filter(EventAttendee.attendee_id == current_user.id)
        .all()
    )
    for att in attendee_records:
        if att.event_id not in inv_map and att.invitation_id:
            inv = db.query(EventInvitation).filter(EventInvitation.id == att.invitation_id).first()
            if inv:
                inv_map[att.event_id] = inv
        elif att.event_id not in inv_map:
            # Attendee exists but no invitation record — synthesise minimal data
            inv_map[att.event_id] = att  # we'll handle both types below

    event_ids = list(inv_map.keys())
    if not event_ids:
        return standard_response(True, "No event invitations found", {"events": [], "pagination": {"page": 1, "limit": limit, "total_items": 0, "total_pages": 1, "has_next": False, "has_previous": False}})

    total = len(event_ids)
    total_pages = max(1, math.ceil(total / limit))
    paged_ids = event_ids[(page - 1) * limit : page * limit]

    events = db.query(Event).filter(Event.id.in_(paged_ids)).all()
    event_order = {eid: i for i, eid in enumerate(paged_ids)}
    events.sort(key=lambda e: event_order.get(e.id, 0))

    # Batch load context
    from utils.batch_loaders import batch_load_event_context, batch_load_users
    ctx = batch_load_event_context(db, [e.id for e in events])
    organizer_map = batch_load_users(db, {e.organizer_id for e in events if e.organizer_id})

    # Batch load current user's attendee record per event
    att_rows = db.query(EventAttendee).filter(
        EventAttendee.event_id.in_(paged_ids),
        EventAttendee.attendee_id == current_user.id,
    ).all()
    att_by_event = {str(a.event_id): a for a in att_rows}

    results = []
    for ev in events:
        eid_str = str(ev.id)
        c = ctx[eid_str]
        inv_or_att = inv_map.get(ev.id)
        is_invitation = isinstance(inv_or_att, EventInvitation)
        et = c["event_type"]; vc = c["vc"]; images = c["images"]
        cover = ev.cover_image_url
        if not cover:
            for img in images:
                if img.get("is_featured"):
                    cover = img["image_url"]; break
            if not cover and images:
                cover = images[0]["image_url"]
        attendee = att_by_event.get(eid_str)

        if is_invitation:
            inv = inv_or_att
            invitation_data = {
                "id": str(inv.id),
                "rsvp_status": inv.rsvp_status.value if hasattr(inv.rsvp_status, "value") else inv.rsvp_status,
                "invitation_code": inv.invitation_code if inv.invitation_code else None,
                "invited_at": inv.invited_at.isoformat() if inv.invited_at else None,
                "rsvp_at": inv.rsvp_at.isoformat() if inv.rsvp_at else None,
            }
        else:
            att_record = inv_or_att
            invitation_data = {
                "id": None,
                "rsvp_status": att_record.rsvp_status.value if hasattr(att_record.rsvp_status, "value") else (att_record.rsvp_status or "pending"),
                "invitation_code": None,
                "invited_at": att_record.created_at.isoformat() if att_record.created_at else None,
                "rsvp_at": None,
            }

        org = organizer_map.get(str(ev.organizer_id), {})
        results.append({
            "id": eid_str,
            "title": ev.name,
            "description": ev.description,
            "event_type": {"id": str(et.id), "name": et.name, "icon": et.icon} if et else None,
            "start_date": ev.start_date.isoformat() if ev.start_date else None,
            "start_time": ev.start_time.strftime("%H:%M") if ev.start_time else None,
            "end_date": ev.end_date.isoformat() if ev.end_date else None,
            "location": ev.location,
            "venue": vc.venue_name if vc else None,
            "cover_image": cover,
            "theme_color": ev.theme_color,
            "organizer": {"name": org.get("name")} if org else None,
            "status": ev.status.value if hasattr(ev.status, "value") else ev.status,
            "invitation": invitation_data,
            "attendee_id": str(attendee.id) if attendee else None,
        })

    return standard_response(True, "Invited events retrieved successfully", {
        "events": results,
        "pagination": {"page": page, "limit": limit, "total_items": total, "total_pages": total_pages, "has_next": page < total_pages, "has_previous": page > 1},
    })


# ──────────────────────────────────────────────
# Get Events Where User Is Committee Member
# ──────────────────────────────────────────────
@router.get("/committee")
def get_committee_events(
    page: int = 1, limit: int = 20,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    """Returns events where the current user is a committee member, with role and permissions."""
    memberships = (
        db.query(EventCommitteeMember)
        .filter(EventCommitteeMember.user_id == current_user.id)
        .order_by(EventCommitteeMember.created_at.desc())
        .all()
    )

    if not memberships:
        return standard_response(True, "You are not a committee member of any events", {"events": [], "pagination": {"page": 1, "limit": limit, "total_items": 0, "total_pages": 1, "has_next": False, "has_previous": False}})

    total = len(memberships)
    total_pages = max(1, math.ceil(total / limit))
    paged = memberships[(page - 1) * limit : page * limit]

    # Batch fetch events + context
    paged_event_ids = [cm.event_id for cm in paged]
    events_map = {e.id: e for e in db.query(Event).filter(Event.id.in_(paged_event_ids)).all()}

    from utils.batch_loaders import batch_load_event_context, batch_load_users
    ctx = batch_load_event_context(db, list(events_map.keys()))
    organizer_map = batch_load_users(db, {e.organizer_id for e in events_map.values() if e.organizer_id})

    # Batch roles + perms
    role_ids = {cm.role_id for cm in paged if cm.role_id}
    role_map = {r.id: r for r in db.query(CommitteeRole).filter(CommitteeRole.id.in_(list(role_ids))).all()} if role_ids else {}
    cm_ids = [cm.id for cm in paged]
    perms_map = {p.committee_member_id: p for p in db.query(CommitteePermission).filter(
        CommitteePermission.committee_member_id.in_(cm_ids)
    ).all()} if cm_ids else {}

    results = []
    for cm in paged:
        ev = events_map.get(cm.event_id)
        if not ev:
            continue
        eid_str = str(ev.id)
        c = ctx.get(eid_str, {})
        et = c.get("event_type"); vc = c.get("vc"); images = c.get("images", [])
        cover = ev.cover_image_url
        if not cover:
            for img in images:
                if img.get("is_featured"):
                    cover = img["image_url"]; break
            if not cover and images:
                cover = images[0]["image_url"]
        org = organizer_map.get(str(ev.organizer_id), {})
        role = role_map.get(cm.role_id) if cm.role_id else None
        perms = perms_map.get(cm.id)
        perm_dict = {f: getattr(perms, f, False) for f in PERMISSION_FIELDS} if perms else {}
        gc = c.get("guest_counts", {})

        results.append({
            "id": eid_str,
            "title": ev.name,
            "description": ev.description,
            "event_type": {"id": str(et.id), "name": et.name, "icon": et.icon} if et else None,
            "start_date": ev.start_date.isoformat() if ev.start_date else None,
            "start_time": ev.start_time.strftime("%H:%M") if ev.start_time else None,
            "end_date": ev.end_date.isoformat() if ev.end_date else None,
            "location": ev.location,
            "venue": vc.venue_name if vc else None,
            "cover_image": cover,
            "images": images,
            "theme_color": ev.theme_color,
            "organizer": {"name": org.get("name")} if org else None,
            "status": ev.status.value if hasattr(ev.status, "value") else ev.status,
            "committee_membership": {
                "id": str(cm.id),
                "role": role.role_name if role else None,
                "role_description": role.description if role else None,
                "assigned_at": cm.assigned_at.isoformat() if cm.assigned_at else None,
                "permissions": perm_dict,
            },
            **gc,
        })

    return standard_response(True, "Committee events retrieved successfully", {
        "events": results,
        "pagination": {"page": page, "limit": limit, "total_items": total, "total_pages": total_pages, "has_next": page < total_pages, "has_previous": page > 1},
    })


# ──────────────────────────────────────────────
# Get Digital Invitation Card (Printable)
# ──────────────────────────────────────────────
@router.get("/{event_id}/invitation-card")
def get_invitation_card(
    event_id: str,
    guest_id: str = None,
    attendee_id: str = None,
    guestId: str = None,
    attendeeId: str = None,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    """Returns all data needed to render and print a digital invitation card with QR code.
    Organizers can pass guest id via guest_id/attendee_id (or legacy guestId/attendeeId)."""
    target_guest_id = guest_id or attendee_id or guestId or attendeeId
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    # If guest_id/attendee_id is provided, organizer is requesting a specific guest's card
    if target_guest_id:
        # Verify requester is the organizer or has manage_guests permission
        is_organizer = (event.organizer_id == current_user.id)
        if not is_organizer:
            committee = db.query(EventCommitteeMember).filter(
                EventCommitteeMember.event_id == eid,
                EventCommitteeMember.user_id == current_user.id,
            ).first()
            role = db.query(CommitteeRole).filter(CommitteeRole.id == committee.role_id).first() if committee else None
            if not role or not role.can_manage_guests:
                return standard_response(False, "You do not have permission to view guest cards")

        try:
            gid = uuid.UUID(target_guest_id)
        except ValueError:
            return standard_response(False, "Invalid guest ID format")

        attendee = db.query(EventAttendee).filter(EventAttendee.id == gid, EventAttendee.event_id == eid).first()
        if not attendee:
            return standard_response(False, "Guest not found")

        guest_user = db.query(User).filter(User.id == attendee.attendee_id).first()
        invitation = db.query(EventInvitation).filter(
            EventInvitation.event_id == eid, EventInvitation.invited_user_id == attendee.attendee_id
        ).first()

        current_rsvp = (
            attendee.rsvp_status.value if hasattr(attendee.rsvp_status, "value")
            else attendee.rsvp_status
        )
        if str(current_rsvp).lower() != RSVPStatusEnum.confirmed.value:
            return standard_response(False, "Only confirmed guests can have invitation cards")

        guest_name = f"{guest_user.first_name} {guest_user.last_name}" if guest_user else (attendee.guest_name if hasattr(attendee, 'guest_name') else "Guest")
    else:
        # Default: fetch current user's own card
        invitation = db.query(EventInvitation).filter(
            EventInvitation.event_id == eid, EventInvitation.invited_user_id == current_user.id
        ).first()
        if not invitation:
            return standard_response(False, "You do not have an invitation for this event")

        attendee = db.query(EventAttendee).filter(
            EventAttendee.event_id == eid, EventAttendee.attendee_id == current_user.id
        ).first()

        current_rsvp = (
            attendee.rsvp_status.value if attendee and hasattr(attendee.rsvp_status, "value")
            else attendee.rsvp_status if attendee
            else invitation.rsvp_status.value if hasattr(invitation.rsvp_status, "value")
            else invitation.rsvp_status
        )
        if str(current_rsvp).lower() != RSVPStatusEnum.confirmed.value:
            return standard_response(False, "Only confirmed guests can print/download invitation cards")

        guest_name = f"{current_user.first_name} {current_user.last_name}"
        guest_user = current_user

    event_type = db.query(EventType).filter(EventType.id == event.event_type_id).first()
    vc = db.query(EventVenueCoordinate).filter(EventVenueCoordinate.event_id == eid).first()
    organizer = db.query(User).filter(User.id == event.organizer_id).first()
    settings = db.query(EventSetting).filter(EventSetting.event_id == eid).first()

    qr_data = f"nuru://event/{event_id}/checkin/{str(attendee.id)}" if attendee else f"nuru://event/{event_id}/rsvp/{invitation.invitation_code}"

    # Prefer the latest rendered invitation card image (if it was already
    # delivered to this guest via WhatsApp). Falls back to None so the
    # client renders the live in-app card.
    rendered_card_url = None
    try:
        if attendee:
            from models.event_cards import SentEventCard
            sent = (
                db.query(SentEventCard)
                .filter(
                    SentEventCard.event_id == eid,
                    SentEventCard.guest_attendee_id == attendee.id,
                    SentEventCard.rendered_card_url.isnot(None),
                )
                .order_by(SentEventCard.sent_at.desc().nullslast(), SentEventCard.created_at.desc())
                .first()
            )
            if sent and sent.rendered_card_url:
                rendered_card_url = sent.rendered_card_url
    except Exception:
        rendered_card_url = None

    return standard_response(True, "Invitation card retrieved successfully", {
        "event": {
            "id": str(event.id),
            "title": event.name,
            "description": event.description,
            "event_type": event_type.name if event_type else None,
            "start_date": event.start_date.isoformat() if event.start_date else None,
            "start_time": event.start_time.strftime("%H:%M") if event.start_time else None,
            "end_date": event.end_date.isoformat() if event.end_date else None,
            "location": event.location,
            "venue": vc.venue_name if vc else None,
            "venue_address": vc.formatted_address if vc else None,
            "cover_image": event.cover_image_url,
            "theme_color": event.theme_color,
            "dress_code": event.dress_code,
            "special_instructions": event.special_instructions,
            "what_to_expect": event.what_to_expect,
            "what_to_expect_notes": event.what_to_expect_notes,
            "extra_details": event.extra_details,
            "guest_of_honor": event.guest_of_honor,
            "invitation_template_id": event.invitation_template_id,
            "invitation_accent_color": event.invitation_accent_color,
            "invitation_content": event.invitation_content,
        },
        "guest": {
            "name": guest_name,
            "attendee_id": str(attendee.id) if attendee else None,
            "rsvp_status": (attendee.rsvp_status.value if hasattr(attendee.rsvp_status, "value") else attendee.rsvp_status) if attendee else (invitation.rsvp_status.value if hasattr(invitation.rsvp_status, "value") else invitation.rsvp_status),
            "meal_preference": attendee.meal_preference if attendee else None,
        },
        "organizer": {
            "name": get_event_owner_display_name(event, db=db) or (f"{organizer.first_name} {organizer.last_name}" if organizer else None),
        },
        "invitation_code": invitation.invitation_code,
        "qr_code_data": qr_data,
        "rendered_card_url": rendered_card_url,

        "card_template": {
            "id": str(event.card_template.id),
            "name": event.card_template.name,
            "pdf_url": event.card_template.pdf_url,
            "name_placeholder_x": float(event.card_template.name_placeholder_x) if event.card_template.name_placeholder_x is not None else 50,
            "name_placeholder_y": float(event.card_template.name_placeholder_y) if event.card_template.name_placeholder_y is not None else 35,
            "name_font_size": float(event.card_template.name_font_size) if event.card_template.name_font_size is not None else 16,
            "name_font_color": event.card_template.name_font_color or "#000000",
            "qr_placeholder_x": float(event.card_template.qr_placeholder_x) if event.card_template.qr_placeholder_x is not None else 50,
            "qr_placeholder_y": float(event.card_template.qr_placeholder_y) if event.card_template.qr_placeholder_y is not None else 75,
            "qr_size": float(event.card_template.qr_size) if event.card_template.qr_size is not None else 80,
        } if event.card_template else None,
        "rsvp_deadline": settings.rsvp_deadline.isoformat() if settings and settings.rsvp_deadline else None,
    })



# ──────────────────────────────────────────────
# Get Single Event (Detailed)
# ──────────────────────────────────────────────
@router.get("/{event_id}")
def get_event(
    event_id: str,
    fields: str = "essential",
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Returns detailed information about a specific event.

    fields:
      - "essential" (default): event meta + counts + viewer_role + inline permissions.
        Lightweight payload optimized for the Event Management Overview tab.
        Heavy collections (guests, committee, contributions, service_bookings,
        schedule, budget_items) are NOT included — request them per-tab via
        their dedicated endpoints, or pass fields=full.
      - "full": legacy payload with every child collection eagerly loaded.
    """
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    from utils.event_owner import user_can_manage_event, get_event_owner_display_name
    is_owner = user_can_manage_event(event, current_user)
    cm = None
    if not is_owner:
        cm = db.query(EventCommitteeMember).filter(
            EventCommitteeMember.event_id == eid,
            EventCommitteeMember.user_id == current_user.id,
        ).first()
    is_committee = cm is not None

    is_invited = False
    if not is_owner and not is_committee:
        inv = db.query(EventInvitation).filter(
            EventInvitation.event_id == eid,
            EventInvitation.invited_user_id == current_user.id,
        ).first()
        is_invited = inv is not None

    viewer_role = "creator" if is_owner else ("committee" if is_committee else ("guest" if is_invited else "public"))

    if not is_owner and not is_committee and not is_invited and not event.is_public:
        return standard_response(False, "You do not have permission to view this event")

    # ── Build essential summary (cached for 60s to absorb burst traffic) ──
    from utils.batch_loaders import build_event_summaries
    try:
        from core.redis import cache_get, cache_set
    except Exception:
        cache_get = cache_set = None

    cache_key = f"event_essential:v5:{event_id}"
    data = None
    if cache_get is not None:
        try:
            cached = cache_get(cache_key)
            if cached:
                data = dict(cached)
        except Exception:
            data = None

    if data is None:
        summaries = build_event_summaries(db, [event])
        data = summaries[0] if summaries else _event_summary(db, event)
        data.update(_public_event_detail_extras(db, event))
        if cache_set is not None:
            try:
                cache_set(cache_key, data, ttl=60)
            except Exception:
                pass

    data["viewer_role"] = viewer_role
    data["is_creator"] = is_owner
    data["is_committee"] = is_committee
    # Event-owner feature - surface fields so the edit screen can render.
    data["event_owner_user_id"] = str(event.event_owner_user_id) if event.event_owner_user_id else None
    data["submitted_by_user_id"] = str(event.organizer_id) if event.organizer_id else None
    data["recognizable_event_owner_name"] = event.recognizable_event_owner_name
    data["created_for_someone_else"] = bool(
        event.event_owner_user_id
        and event.organizer_id
        and str(event.event_owner_user_id) != str(event.organizer_id)
    )
    data["owner_display_name"] = get_event_owner_display_name(event, db=db)
    # Owner profile info for edit-screen hydration
    if event.event_owner_user_id and str(event.event_owner_user_id) != str(event.organizer_id):
        _owner_u = db.query(User).filter(User.id == event.event_owner_user_id).first()
        if _owner_u:
            data["event_owner_first_name"] = _owner_u.first_name
            data["event_owner_last_name"] = _owner_u.last_name
            data["event_owner_username"] = _owner_u.username
            data["event_owner_email"] = _owner_u.email
            data["event_owner_phone"] = _owner_u.phone
            data["event_owner_full_name"] = f"{(_owner_u.first_name or '').strip()} {(_owner_u.last_name or '').strip()}".strip()
            data["event_owner_avatar"] = _user_avatar_url(db, _owner_u.id)

    # ── Inline permissions so clients don't need a second round-trip ──
    if is_owner:
        data["permissions"] = {"is_creator": True, "role": "creator", **{f: True for f in PERMISSION_FIELDS}}
    elif is_committee and cm is not None:
        role_obj = db.query(CommitteeRole).filter(CommitteeRole.id == cm.role_id).first() if cm.role_id else None
        perm_row = db.query(CommitteePermission).filter(CommitteePermission.committee_member_id == cm.id).first()
        perms = {f: bool(getattr(perm_row, f, False)) if perm_row else False for f in PERMISSION_FIELDS}
        # Auto-grant view when manage is granted
        if perms.get("can_manage_contributions"): perms["can_view_contributions"] = True
        if perms.get("can_manage_budget"):        perms["can_view_budget"] = True
        if perms.get("can_manage_guests"):        perms["can_view_guests"] = True
        if perms.get("can_manage_vendors"):       perms["can_view_vendors"] = True
        if perms.get("can_manage_expenses"):      perms["can_view_expenses"] = True
        data["permissions"] = {
            "is_creator": False,
            "role": role_obj.role_name if role_obj else "member",
            **perms,
        }
    else:
        data["permissions"] = {
            "is_creator": False, "role": None,
            **{f: False for f in PERMISSION_FIELDS},
        }

    # ── ESSENTIAL MODE: stop here. Tabs lazy-load their own data. ──
    if fields != "full":
        return standard_response(True, "Event retrieved successfully", data)

    # ─── FULL MODE: legacy heavy payload (kept for backwards compatibility) ───
    attendees = db.query(EventAttendee).filter(EventAttendee.event_id == eid).all()
    cms = db.query(EventCommitteeMember).filter(EventCommitteeMember.event_id == eid).all()
    contributions = db.query(EventContribution).filter(EventContribution.event_id == eid).all()
    event_services_rows = db.query(EventService).filter(EventService.event_id == eid).all()
    schedule_items = db.query(EventScheduleItem).filter(EventScheduleItem.event_id == eid).order_by(EventScheduleItem.display_order.asc()).all()
    budget_items = db.query(EventBudgetItem).filter(EventBudgetItem.event_id == eid).all()

    # ─── Pre-load all referenced users/contributors/invitations in bulk ───
    from models import UserServiceImage as _USImg
    attendee_user_ids = {a.attendee_id for a in attendees if a.attendee_id} | \
                       {cm.user_id for cm in cms if cm.user_id} | \
                       {cm.assigned_by for cm in cms if cm.assigned_by}
    contributor_ids = {a.contributor_id for a in attendees if a.contributor_id}
    invitation_ids = {a.invitation_id for a in attendees if a.invitation_id}
    attendee_ids = [a.id for a in attendees]
    cm_ids_all = [cm.id for cm in cms]
    role_ids = {cm.role_id for cm in cms if cm.role_id}
    contribution_ids = [c.id for c in contributions]
    provider_svc_ids = {es.provider_user_service_id for es in event_services_rows if es.provider_user_service_id}
    provider_user_ids = {es.provider_user_id for es in event_services_rows if es.provider_user_id}
    svc_type_ids = {es.service_id for es in event_services_rows if es.service_id}
    vendor_ids = {bi.vendor_id for bi in budget_items if bi.vendor_id}

    users_bulk = {u.id: u for u in db.query(User).filter(User.id.in_(list(attendee_user_ids | provider_user_ids))).all()} if (attendee_user_ids or provider_user_ids) else {}
    profiles_bulk = {p.user_id: p for p in db.query(UserProfile).filter(UserProfile.user_id.in_(list(attendee_user_ids))).all()} if attendee_user_ids else {}
    contributors_bulk = {c.id: c for c in db.query(UserContributor).filter(UserContributor.id.in_(list(contributor_ids))).all()} if contributor_ids else {}
    invitations_bulk = {i.id: i for i in db.query(EventInvitation).filter(EventInvitation.id.in_(list(invitation_ids))).all()} if invitation_ids else {}
    plus_ones_by_attendee = defaultdict(list)
    if attendee_ids:
        for po in db.query(EventGuestPlusOne).filter(EventGuestPlusOne.attendee_id.in_(attendee_ids)).all():
            plus_ones_by_attendee[po.attendee_id].append(po)
    roles_bulk = {r.id: r for r in db.query(CommitteeRole).filter(CommitteeRole.id.in_(list(role_ids))).all()} if role_ids else {}
    perms_bulk = {p.committee_member_id: p for p in db.query(CommitteePermission).filter(CommitteePermission.committee_member_id.in_(cm_ids_all)).all()} if cm_ids_all else {}
    thank_you_bulk = {t.contribution_id: t for t in db.query(ContributionThankYouMessage).filter(ContributionThankYouMessage.contribution_id.in_(contribution_ids)).all()} if contribution_ids else {}
    provider_svcs_bulk = {s.id: s for s in db.query(UserService).filter(UserService.id.in_(list(provider_svc_ids))).all()} if provider_svc_ids else {}
    svc_types_bulk = {st.id: st for st in db.query(ServiceType).filter(ServiceType.id.in_(list(svc_type_ids))).all()} if svc_type_ids else {}
    svc_images_bulk = defaultdict(list)
    if provider_svc_ids:
        for img in db.query(_USImg).filter(_USImg.user_service_id.in_(list(provider_svc_ids))).order_by(_USImg.is_featured.desc()).all():
            svc_images_bulk[img.user_service_id].append(img)
    vendors_bulk = {}
    if vendor_ids:
        for v in db.query(UserService).filter(UserService.id.in_(list(vendor_ids))).all():
            vendors_bulk[v.id] = v

    currency_code = data.get("currency")

    # ─── Build guests ───
    guests = []
    for att in attendees:
        guest_type = att.guest_type.value if hasattr(att.guest_type, "value") else (att.guest_type or "user")
        name = email = phone = avatar = None
        if guest_type == "contributor":
            contributor = contributors_bulk.get(att.contributor_id) if att.contributor_id else None
            if contributor:
                name, email, phone = contributor.name, contributor.email, contributor.phone
            else:
                name, email, phone = att.guest_name, att.guest_email, att.guest_phone
        else:
            u = users_bulk.get(att.attendee_id) if att.attendee_id else None
            if u:
                name = f"{u.first_name} {u.last_name}"
                email, phone = u.email, u.phone
                p = profiles_bulk.get(u.id)
                avatar = p.profile_picture_url if p else None
            else:
                name = att.guest_name
        invitation = invitations_bulk.get(att.invitation_id) if att.invitation_id else None
        plus_ones = plus_ones_by_attendee.get(att.id, [])
        guests.append({
            "id": str(att.id), "event_id": str(att.event_id),
            "guest_type": guest_type,
            "name": name, "avatar": avatar, "email": email, "phone": phone,
            "rsvp_status": att.rsvp_status.value if hasattr(att.rsvp_status, "value") else att.rsvp_status,
            "dietary_requirements": att.dietary_restrictions, "meal_preference": att.meal_preference,
            "special_requests": att.special_requests,
            "plus_ones": len(plus_ones), "plus_one_names": [po.name for po in plus_ones],
            "notes": invitation.notes if invitation else None,
            "invitation_sent": invitation.sent_at is not None if invitation else False,
            "invitation_sent_at": invitation.sent_at.isoformat() if invitation and invitation.sent_at else None,
            "invitation_method": invitation.sent_via if invitation else None,
            "checked_in": att.checked_in,
            "checked_in_at": att.checked_in_at.isoformat() if att.checked_in_at else None,
            "created_at": att.created_at.isoformat() if att.created_at else None,
        })
    data["guests"] = guests

    # ─── Build committee ───
    members_out = []
    for cm in cms:
        member_user = users_bulk.get(cm.user_id) if cm.user_id else None
        profile = profiles_bulk.get(cm.user_id) if cm.user_id else None
        role = roles_bulk.get(cm.role_id) if cm.role_id else None
        perms = perms_bulk.get(cm.id)
        assigned_user = users_bulk.get(cm.assigned_by) if cm.assigned_by else None
        permissions_list = [api_name for api_name, db_field in PERMISSION_MAP.items() if perms and getattr(perms, db_field, False)]
        members_out.append({
            "id": str(cm.id), "event_id": str(cm.event_id),
            "user_id": str(cm.user_id) if cm.user_id else None,
            "name": f"{member_user.first_name} {member_user.last_name}" if member_user else "Invited Member",
            "email": member_user.email if member_user else (cm.invited_email if hasattr(cm, 'invited_email') else None),
            "phone": member_user.phone if member_user else None,
            "avatar": profile.profile_picture_url if profile else None,
            "role": role.role_name if role else None,
            "role_description": role.description if role else None,
            "permissions": permissions_list,
            "status": "active" if cm.user_id else "invited",
            "assigned_by": {"id": str(assigned_user.id), "name": f"{assigned_user.first_name} {assigned_user.last_name}"} if assigned_user else None,
            "assigned_at": cm.assigned_at.isoformat() if cm.assigned_at else None,
            "created_at": cm.created_at.isoformat() if cm.created_at else None,
        })
    data["committee_members"] = members_out

    # ─── Build contributions ───
    contributions_out = []
    for c in contributions:
        contributor_user = None
        if c.event_contributor and c.event_contributor.contributor:
            contributor_user = c.event_contributor.contributor.user
        contact = c.contributor_contact or {}
        thank_you = thank_you_bulk.get(c.id)
        contributions_out.append({
            "id": str(c.id), "event_id": str(c.event_id),
            "contributor_name": f"{contributor_user.first_name} {contributor_user.last_name}" if contributor_user else (c.contributor_name or "Anonymous"),
            "contributor_email": contributor_user.email if contributor_user else contact.get("email"),
            "contributor_phone": contributor_user.phone if contributor_user else contact.get("phone"),
            "contributor_user_id": str(contributor_user.id) if contributor_user else None,
            "amount": float(c.amount), "currency": currency_code,
            "payment_method": c.payment_method.value if hasattr(c.payment_method, "value") else c.payment_method,
            "payment_reference": c.transaction_ref, "status": "confirmed",
            "is_anonymous": contributor_user is None and (not c.contributor_name or c.contributor_name.lower() == "anonymous"),
            "thank_you_sent": thank_you.is_sent if thank_you else False,
            "created_at": c.created_at.isoformat() if c.created_at else None,
            "confirmed_at": c.contributed_at.isoformat() if c.contributed_at else None,
        })
    data["contributions"] = contributions_out

    # ─── Build service bookings ───
    bookings_out = []
    for es in event_services_rows:
        svc_type = svc_types_bulk.get(es.service_id) if es.service_id else None
        provider_svc = provider_svcs_bulk.get(es.provider_user_service_id) if es.provider_user_service_id else None
        provider_user = users_bulk.get(es.provider_user_id) if es.provider_user_id else None
        service_image = None
        if provider_svc:
            imgs = svc_images_bulk.get(provider_svc.id, [])
            featured = next((i for i in imgs if i.is_featured), None)
            if featured:
                service_image = featured.image_url
            elif imgs:
                service_image = imgs[0].image_url
        bookings_out.append({
            "id": str(es.id), "event_id": str(es.event_id), "service_id": str(es.service_id),
            "service": {
                "title": provider_svc.title if provider_svc else (svc_type.name if svc_type else None),
                "category": svc_type.category.name if svc_type and hasattr(svc_type, "category") and svc_type.category else None,
                "provider_name": f"{provider_user.first_name} {provider_user.last_name}" if provider_user else None,
                "image": service_image,
                "verification_status": provider_svc.verification_status.value if provider_svc and hasattr(provider_svc.verification_status, "value") else (str(provider_svc.verification_status) if provider_svc and provider_svc.verification_status else "unverified"),
                "verified": provider_svc.is_verified if provider_svc else False,
            },
            "quoted_price": float(es.agreed_price) if es.agreed_price else None,
            "currency": currency_code,
            "status": es.service_status.value if hasattr(es.service_status, "value") else es.service_status,
            "notes": es.notes,
            "created_at": es.created_at.isoformat() if es.created_at else None,
        })
    data["service_bookings"] = bookings_out

    # ─── Schedule + Budget ───
    data["schedule"] = [{"id": str(si.id), "title": si.title, "description": si.description, "start_time": si.start_time.isoformat() if si.start_time else None, "end_time": si.end_time.isoformat() if si.end_time else None, "location": si.location, "display_order": si.display_order} for si in schedule_items]
    data["budget_items"] = [{"id": str(bi.id), "category": bi.category, "item_name": bi.item_name, "estimated_cost": float(bi.estimated_cost) if bi.estimated_cost else None, "actual_cost": float(bi.actual_cost) if bi.actual_cost else None, "vendor_name": bi.vendor_name, "vendor_id": str(bi.vendor_id) if bi.vendor_id else None, "vendor": _vendor_summary(vendors_bulk.get(bi.vendor_id)) if bi.vendor_id else None, "status": bi.status, "notes": bi.notes} for bi in budget_items]

    return standard_response(True, "Event retrieved successfully", data)


# ──────────────────────────────────────────────
# Create Event
# ──────────────────────────────────────────────
@router.post("/")
async def create_event(
    title: Optional[str] = Form(None), description: Optional[str] = Form(None),
    event_type_id: Optional[str] = Form(None), start_date: Optional[str] = Form(None),
    end_date: Optional[str] = Form(None), location: Optional[str] = Form(None),
    venue: Optional[str] = Form(None), venue_address: Optional[str] = Form(None),
    venue_latitude: Optional[float] = Form(None), venue_longitude: Optional[float] = Form(None),
    time: Optional[str] = Form(None), cover_image: Optional[UploadFile] = File(None),
    theme_color: Optional[str] = Form(None), is_public: Optional[bool] = Form(False),
    sells_tickets: Optional[bool] = Form(False),
    budget: Optional[float] = Form(None), currency: Optional[str] = Form(None),
    expected_guests: Optional[int] = Form(None), dress_code: Optional[str] = Form(None),
    special_instructions: Optional[str] = Form(None), rsvp_deadline: Optional[str] = Form(None),
    what_to_expect: Optional[str] = Form(None),
    what_to_expect_notes: Optional[str] = Form(None),
    extra_details: Optional[str] = Form(None),
    guest_of_honor: Optional[str] = Form(None),
    reminder_contact_phone: Optional[str] = Form(None),
    contribution_payment_instructions: Optional[str] = Form(None),
    contribution_enabled: Optional[bool] = Form(False), contribution_target: Optional[float] = Form(None),
    contribution_description: Optional[str] = Form(None), services: Optional[str] = Form(None),
    images: Optional[List[UploadFile]] = File(None),
    status: Optional[str] = Form(None),
    # Event-owner feature: when ``created_for_someone_else`` is true,
    # ``event_owner_user_id`` is the real owner. Otherwise the creator
    # is also the owner. ``recognizable_event_owner_name`` overrides
    # the display name used in owner-mentioning communications.
    created_for_someone_else: Optional[bool] = Form(False),
    event_owner_user_id: Optional[str] = Form(None),
    recognizable_event_owner_name: Optional[str] = Form(None),
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    """Creates a new event with comprehensive validation."""
    is_draft = (status or "").strip().lower() == "draft"
    errors = []
    if not title or not title.strip():
        errors.append({"field": "title", "message": "Title is required."})
    if not event_type_id:
        errors.append({"field": "event_type_id", "message": "Event type is required."})
    # Drafts allow saving without a start date so users can come back later.
    if not is_draft and (not start_date or not start_date.strip()):
        errors.append({"field": "start_date", "message": "Start date is required."})

    parsed_start = parsed_end = parsed_rsvp = None
    if start_date and start_date.strip():
        try:
            parsed_start = datetime.fromisoformat(start_date.replace("Z", "+00:00"))
        except ValueError:
            errors.append({"field": "start_date", "message": "Invalid start_date format."})

    if end_date and end_date.strip():
        try:
            parsed_end = datetime.fromisoformat(end_date.replace("Z", "+00:00"))
        except ValueError:
            errors.append({"field": "end_date", "message": "Invalid end_date format."})

    if rsvp_deadline and rsvp_deadline.strip():
        try:
            parsed_rsvp = datetime.fromisoformat(rsvp_deadline.replace("Z", "+00:00"))
        except ValueError:
            errors.append({"field": "rsvp_deadline", "message": "Invalid rsvp_deadline format."})

    if theme_color and not HEX_COLOR_RE.match(theme_color):
        errors.append({"field": "theme_color", "message": "Must be a valid hex color (e.g. #FF6B6B)."})

    if errors:
        return standard_response(False, "Validation failed", errors)

    event_type = db.query(EventType).filter(EventType.id == event_type_id).first()
    if not event_type:
        return standard_response(False, "Selected event type does not exist.")

    currency_id = None
    if currency:
        cur = db.query(Currency).filter(Currency.code == currency.upper()).first()
        if cur:
            currency_id = cur.id

    parsed_time = None
    if time and time.strip():
        try:
            parts = time.strip().split(":")
            parsed_time = datetime.strptime(time.strip(), "%H:%M").time() if len(parts) == 2 else datetime.strptime(time.strip(), "%H:%M:%S").time()
        except ValueError:
            pass

    now = datetime.now(EAT)

    # Resolve event owner.
    resolved_owner_id = current_user.id
    if created_for_someone_else:
        if not event_owner_user_id:
            return standard_response(False, "Please select the event owner.")
        try:
            owner_uuid = uuid.UUID(event_owner_user_id)
        except (ValueError, TypeError):
            return standard_response(False, "Invalid event owner id.")
        owner_user = db.query(User).filter(User.id == owner_uuid).first()
        if not owner_user:
            return standard_response(False, "Selected event owner not found. Please register them first.")
        resolved_owner_id = owner_user.id

    new_event = Event(
        id=uuid.uuid4(), organizer_id=current_user.id, name=title.strip(),
        event_owner_user_id=resolved_owner_id,
        recognizable_event_owner_name=(recognizable_event_owner_name.strip() or None)
            if recognizable_event_owner_name else None,
        event_type_id=uuid.UUID(event_type_id),
        description=description.strip() if description else None,
        start_date=parsed_start.date() if parsed_start else None,
        start_time=parsed_time if parsed_time else (parsed_start.time() if parsed_start else None),
        end_date=parsed_end.date() if parsed_end else None,
        end_time=parsed_end.time() if parsed_end else None,
        location=location.strip() if location else None,
        expected_guests=expected_guests, budget=budget,
        status=_initial_status(status), currency_id=currency_id,
        is_public=is_public or False,
        sells_tickets=sells_tickets or False,
        theme_color=theme_color.strip() if theme_color else None,
        dress_code=dress_code.strip() if dress_code else None,
        special_instructions=special_instructions.strip() if special_instructions else None,
        what_to_expect=_parse_what_to_expect(what_to_expect),
        what_to_expect_notes=(what_to_expect_notes.strip() or None) if what_to_expect_notes else None,
        extra_details=_parse_extra_details(extra_details),
        guest_of_honor=(guest_of_honor.strip() or None) if guest_of_honor else None,
        reminder_contact_phone=reminder_contact_phone.strip() if reminder_contact_phone else None,
        contribution_payment_instructions=(contribution_payment_instructions.strip() or None) if contribution_payment_instructions else None,
        created_at=now, updated_at=now,
    )
    db.add(new_event)
    db.flush()

    # Venue coordinates
    if venue_latitude is not None and venue_longitude is not None:
        db.add(EventVenueCoordinate(id=uuid.uuid4(), event_id=new_event.id, latitude=venue_latitude, longitude=venue_longitude, formatted_address=venue_address.strip() if venue_address else None, venue_name=venue.strip() if venue else None, created_at=now, updated_at=now))
    elif venue or venue_address:
        db.add(EventVenueCoordinate(id=uuid.uuid4(), event_id=new_event.id, latitude=0, longitude=0, formatted_address=venue_address.strip() if venue_address else None, venue_name=venue.strip() if venue else None, created_at=now, updated_at=now))

    # Settings
    db.add(EventSetting(id=uuid.uuid4(), event_id=new_event.id, rsvp_deadline=parsed_rsvp, contributions_enabled=contribution_enabled or False, contribution_target_amount=contribution_target, created_at=now, updated_at=now))

    # Contribution target
    if contribution_target and contribution_target > 0:
        db.add(EventContributionTarget(id=uuid.uuid4(), event_id=new_event.id, target_amount=contribution_target, description=contribution_description.strip() if contribution_description else None, created_at=now, updated_at=now))

    # Cover image
    if cover_image and cover_image.filename:
        result = await _upload_image(cover_image, f"nuru/uploads/events/{new_event.id}/cover/")
        if not result["success"]:
            db.rollback()
            return standard_response(False, result["error"])
        new_event.cover_image_url = result["url"]

    # Gallery images
    if images:
        real_images = [f for f in images if f and f.filename]
        if len(real_images) > MAX_EVENT_IMAGES:
            db.rollback()
            return standard_response(False, f"Maximum of {MAX_EVENT_IMAGES} images allowed.")
        for file in real_images:
            result = await _upload_image(file, f"nuru/uploads/events/{new_event.id}/gallery/")
            if not result["success"]:
                db.rollback()
                return standard_response(False, result["error"])
            db.add(EventImage(id=uuid.uuid4(), event_id=new_event.id, image_url=result["url"], created_at=now, updated_at=now))

    # Services
    assigned_providers = []  # Track providers to notify after commit
    if services:
        try:
            service_list = json.loads(services)
            for s in service_list:
                service_id_val = None
                provider_service_id = None
                provider_user_id_val = None

                if s.get("service_id"):
                    service_id_val = uuid.UUID(s["service_id"])
                if s.get("provider_service_id"):
                    provider_service_id = uuid.UUID(s["provider_service_id"])
                    # Resolve service_type_id from provider's service
                    psvc = db.query(UserService).filter(UserService.id == provider_service_id).first()
                    if psvc:
                        if psvc.service_type_id:
                            service_id_val = psvc.service_type_id
                        provider_user_id_val = psvc.user_id
                if s.get("provider_user_id"):
                    provider_user_id_val = uuid.UUID(s["provider_user_id"])

                es = EventService(
                    id=uuid.uuid4(), event_id=new_event.id,
                    service_id=service_id_val,
                    provider_user_service_id=provider_service_id,
                    provider_user_id=provider_user_id_val,
                    agreed_price=s.get("quoted_price"),
                    service_status=EventServiceStatusEnum.pending,
                    notes=s.get("notes"),
                    created_at=now, updated_at=now,
                )
                db.add(es)

                # Create a ServiceBookingRequest so it shows in vendor's incoming bookings
                if provider_service_id:
                    from models import ServiceBookingRequest
                    booking_req = ServiceBookingRequest(
                        id=uuid.uuid4(),
                        user_service_id=provider_service_id,
                        requester_user_id=current_user.id,
                        event_id=new_event.id,
                        message=s.get("notes") or f"Service requested for {new_event.name}",
                        proposed_price=s.get("quoted_price"),
                        status="pending",
                        created_at=now, updated_at=now,
                    )
                    db.add(booking_req)

                if provider_user_id_val and str(provider_user_id_val) != str(current_user.id):
                    assigned_providers.append({
                        "provider_user_id": provider_user_id_val,
                        "provider_service_id": provider_service_id,
                    })
        except (json.JSONDecodeError, ValueError):
            pass

    try:
        db.commit()
    except Exception as e:
        db.rollback()
        return standard_response(False, f"Failed to save event: {str(e)}")

    # Notify assigned service providers after successful commit
    for prov in assigned_providers:
        try:
            provider_user = db.query(User).filter(User.id == prov["provider_user_id"]).first()
            if provider_user:
                from utils.notify import notify_booking
                service_name = "service"
                if prov["provider_service_id"]:
                    psvc = db.query(UserService).filter(UserService.id == prov["provider_service_id"]).first()
                    if psvc:
                        service_name = psvc.title or "service"
                notify_booking(db, provider_user.id, current_user.id, new_event.id, new_event.name, service_name)
                db.commit()
                from utils.event_owner import get_event_owner_display_name
                organizer_name = get_event_owner_display_name(
                    new_event, db=db,
                    fallback=f"{current_user.first_name} {current_user.last_name}".strip(),
                )
                from utils.message_templates import resolve_user_language
                lang = resolve_user_language(db, provider_user.id)
                # WhatsApp first
                if provider_user.phone:
                    try:
                        from utils.whatsapp import wa_booking_notification
                        try:
                            from utils.wa_logging import set_wa_log_context
                            set_wa_log_context(event_id=str(new_event.id), event_name=new_event.name,
                                               source_module="event_create", purpose="booking_request",
                                               recipient_type="vendor")
                        except Exception: pass
                        wa_booking_notification(provider_user.phone, provider_user.first_name, new_event.name, organizer_name, service_name, lang=lang)
                    except Exception:
                        pass
                sms_booking_notification(provider_user.phone, f"{provider_user.first_name}", new_event.name, organizer_name, service_name, lang=lang)
        except Exception:
            pass

    return standard_response(True, "Event created successfully", _event_summary(db, new_event))


# ──────────────────────────────────────────────
# Update Event
# ──────────────────────────────────────────────
@router.put("/{event_id}")
async def update_event(
    event_id: str,
    title: Optional[str] = Form(None), description: Optional[str] = Form(None),
    event_type_id: Optional[str] = Form(None), start_date: Optional[str] = Form(None),
    end_date: Optional[str] = Form(None), location: Optional[str] = Form(None),
    venue: Optional[str] = Form(None), venue_address: Optional[str] = Form(None),
    venue_latitude: Optional[float] = Form(None), venue_longitude: Optional[float] = Form(None),
    cover_image: Optional[UploadFile] = File(None), remove_cover_image: Optional[bool] = Form(False),
    theme_color: Optional[str] = Form(None), is_public: Optional[bool] = Form(None),
    sells_tickets: Optional[bool] = Form(None),
    status: Optional[str] = Form(None), budget: Optional[float] = Form(None),
    currency: Optional[str] = Form(None), expected_guests: Optional[int] = Form(None),
    dress_code: Optional[str] = Form(None), special_instructions: Optional[str] = Form(None),
    what_to_expect: Optional[str] = Form(None),
    what_to_expect_notes: Optional[str] = Form(None),
    extra_details: Optional[str] = Form(None),
    guest_of_honor: Optional[str] = Form(None),
    reminder_contact_phone: Optional[str] = Form(None),
    contribution_payment_instructions: Optional[str] = Form(None),
    invitation_template_id: Optional[str] = Form(None),
    invitation_accent_color: Optional[str] = Form(None),
    invitation_content: Optional[str] = Form(None),
    rsvp_deadline: Optional[str] = Form(None), contribution_enabled: Optional[bool] = Form(None),
    contribution_target: Optional[float] = Form(None), contribution_description: Optional[str] = Form(None),
    time: Optional[str] = Form(None), images: Optional[List[UploadFile]] = File(None),
    # Event-owner feature (optional on update).
    created_for_someone_else: Optional[bool] = Form(None),
    event_owner_user_id: Optional[str] = Form(None),
    recognizable_event_owner_name: Optional[str] = Form(None),
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    """Updates an existing event."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    # Permission check: creator OR recorded owner, otherwise a committee
    # member with explicit ``can_edit_event``.
    from utils.event_owner import user_can_manage_event
    if not user_can_manage_event(event, current_user):
        cm = db.query(EventCommitteeMember).filter(EventCommitteeMember.event_id == eid, EventCommitteeMember.user_id == current_user.id).first()
        if cm:
            perms = db.query(CommitteePermission).filter(CommitteePermission.committee_member_id == cm.id).first()
            if not perms or not perms.can_edit_event:
                return standard_response(False, "You do not have permission to edit this event")
        else:
            return standard_response(False, "You do not have permission to edit this event")

    # Apply event-owner changes (only creator/current owner may change them).
    if created_for_someone_else is not None and user_can_manage_event(event, current_user):
        if created_for_someone_else:
            if event_owner_user_id:
                try:
                    owner_uuid = uuid.UUID(event_owner_user_id)
                except (ValueError, TypeError):
                    return standard_response(False, "Invalid event owner id.")
                owner_user = db.query(User).filter(User.id == owner_uuid).first()
                if not owner_user:
                    return standard_response(False, "Selected event owner not found.")
                event.event_owner_user_id = owner_user.id
        else:
            event.event_owner_user_id = event.organizer_id
    elif event_owner_user_id is not None and user_can_manage_event(event, current_user):
        try:
            owner_uuid = uuid.UUID(event_owner_user_id)
            owner_user = db.query(User).filter(User.id == owner_uuid).first()
            if owner_user:
                event.event_owner_user_id = owner_user.id
        except (ValueError, TypeError):
            pass

    if recognizable_event_owner_name is not None:
        nice = recognizable_event_owner_name.strip()
        event.recognizable_event_owner_name = nice or None

    now = datetime.now(EAT)
    errors = []

    if title is not None:
        if not title.strip():
            errors.append({"field": "title", "message": "Title cannot be empty."})
        else:
            event.name = title.strip()

    if description is not None:
        event.description = description.strip() if description.strip() else None

    if event_type_id is not None:
        try:
            et = db.query(EventType).filter(EventType.id == uuid.UUID(event_type_id)).first()
            if et:
                event.event_type_id = et.id
        except ValueError:
            errors.append({"field": "event_type_id", "message": "Invalid UUID."})

    if start_date is not None:
        try:
            ps = datetime.fromisoformat(start_date.replace("Z", "+00:00"))
            event.start_date = ps.date()
            if time is None:
                event.start_time = ps.time()
        except ValueError:
            errors.append({"field": "start_date", "message": "Invalid format."})

    if time is not None and time.strip():
        try:
            parts = time.strip().split(":")
            event.start_time = datetime.strptime(time.strip(), "%H:%M").time() if len(parts) == 2 else datetime.strptime(time.strip(), "%H:%M:%S").time()
        except ValueError:
            errors.append({"field": "time", "message": "Invalid time format."})

    if end_date is not None:
        if end_date.strip():
            try:
                pe = datetime.fromisoformat(end_date.replace("Z", "+00:00"))
                event.end_date = pe.date()
                event.end_time = pe.time()
            except ValueError:
                errors.append({"field": "end_date", "message": "Invalid format."})
        else:
            event.end_date = None
            event.end_time = None

    if location is not None:
        event.location = location.strip() if location.strip() else None
    if budget is not None:
        event.budget = budget
    if expected_guests is not None:
        event.expected_guests = expected_guests
    if is_public is not None:
        event.is_public = is_public
    if sells_tickets is not None:
        event.sells_tickets = sells_tickets
    if currency is not None:
        cur = db.query(Currency).filter(Currency.code == currency.upper()).first()
        if cur:
            event.currency_id = cur.id
    if status is not None:
        mapped = "confirmed" if status == "published" else status
        valid = {s.value for s in EventStatusEnum}
        if mapped in valid:
            event.status = EventStatusEnum(mapped)
    if theme_color is not None:
        if HEX_COLOR_RE.match(theme_color):
            event.theme_color = theme_color
    if dress_code is not None:
        event.dress_code = dress_code.strip() if dress_code.strip() else None
    if special_instructions is not None:
        event.special_instructions = special_instructions.strip() if special_instructions.strip() else None
    if what_to_expect is not None:
        event.what_to_expect = _parse_what_to_expect(what_to_expect)
    if what_to_expect_notes is not None:
        wte_n = what_to_expect_notes.strip()
        event.what_to_expect_notes = wte_n if wte_n else None
    if extra_details is not None:
        event.extra_details = _parse_extra_details(extra_details)
    if guest_of_honor is not None:
        goh = guest_of_honor.strip()
        event.guest_of_honor = goh if goh else None
    if reminder_contact_phone is not None:
        rcp = reminder_contact_phone.strip()
        event.reminder_contact_phone = rcp if rcp else None
    if contribution_payment_instructions is not None:
        cpi = contribution_payment_instructions.strip()
        event.contribution_payment_instructions = cpi if cpi else None
    if invitation_template_id is not None:
        v = invitation_template_id.strip()
        event.invitation_template_id = v if v else None
    if invitation_accent_color is not None:
        v = invitation_accent_color.strip()
        if not v:
            event.invitation_accent_color = None
        elif HEX_COLOR_RE.match(v):
            event.invitation_accent_color = v
    if invitation_content is not None:
        # Accept JSON string from clients; empty string clears the override.
        raw = invitation_content.strip()
        if not raw:
            event.invitation_content = None
        else:
            try:
                import json as _json
                parsed = _json.loads(raw)
                if isinstance(parsed, dict):
                    # Strip empty-string fields so the renderer falls back to
                    # template defaults instead of showing blank lines.
                    cleaned = {
                        k: v for k, v in parsed.items()
                        if v not in (None, "")
                    }
                    event.invitation_content = cleaned or None
                else:
                    errors.append({
                        "field": "invitation_content",
                        "message": "Must be a JSON object."
                    })
            except (ValueError, TypeError):
                errors.append({
                    "field": "invitation_content",
                    "message": "Invalid JSON."
                })

    if errors:
        return standard_response(False, "Validation failed", errors)

    # Venue coordinates
    if any(v is not None for v in [venue, venue_address, venue_latitude, venue_longitude]):
        vc = db.query(EventVenueCoordinate).filter(EventVenueCoordinate.event_id == eid).first()
        if not vc:
            vc = EventVenueCoordinate(id=uuid.uuid4(), event_id=eid, latitude=venue_latitude or 0, longitude=venue_longitude or 0, created_at=now)
            db.add(vc)
        if venue_latitude is not None: vc.latitude = venue_latitude
        if venue_longitude is not None: vc.longitude = venue_longitude
        if venue is not None: vc.venue_name = venue.strip() if venue.strip() else None
        if venue_address is not None: vc.formatted_address = venue_address.strip() if venue_address.strip() else None
        vc.updated_at = now

    # Settings
    settings = db.query(EventSetting).filter(EventSetting.event_id == eid).first()
    if not settings:
        settings = EventSetting(id=uuid.uuid4(), event_id=eid, created_at=now)
        db.add(settings)
    if rsvp_deadline is not None:
        if rsvp_deadline.strip():
            try:
                settings.rsvp_deadline = datetime.fromisoformat(rsvp_deadline.replace("Z", "+00:00"))
            except ValueError:
                pass
        else:
            settings.rsvp_deadline = None
    if contribution_enabled is not None:
        settings.contributions_enabled = contribution_enabled
    if contribution_target is not None:
        settings.contribution_target_amount = contribution_target
    settings.updated_at = now

    # Cover image
    if remove_cover_image:
        old_cover = event.cover_image_url
        event.cover_image_url = None
        if old_cover:
            from utils.helpers import delete_storage_file_sync
            delete_storage_file_sync(old_cover)
    elif cover_image and cover_image.filename:
        old_cover = event.cover_image_url
        result = await _upload_image(cover_image, f"nuru/uploads/events/{eid}/cover/")
        if not result["success"]:
            db.rollback()
            return standard_response(False, result["error"])
        event.cover_image_url = result["url"]
        # Unlink old cover if it was replaced
        if old_cover:
            from utils.helpers import delete_storage_file
            await delete_storage_file(old_cover)

    # Gallery images (append)
    if images:
        real_images = [f for f in images if f and f.filename]
        if real_images:
            existing_count = db.query(sa_func.count(EventImage.id)).filter(EventImage.event_id == eid).scalar() or 0
            if existing_count + len(real_images) > MAX_EVENT_IMAGES:
                db.rollback()
                return standard_response(False, f"Total images would exceed maximum of {MAX_EVENT_IMAGES}.")
            for file in real_images:
                result = await _upload_image(file, f"nuru/uploads/events/{eid}/gallery/")
                if not result["success"]:
                    db.rollback()
                    return standard_response(False, result["error"])
                db.add(EventImage(id=uuid.uuid4(), event_id=eid, image_url=result["url"], created_at=now, updated_at=now))

    event.updated_at = now

    try:
        db.commit()
    except Exception as e:
        db.rollback()
        return standard_response(False, f"Failed to update event: {str(e)}")

    # Invalidate public event cache
    try:
        from core.redis import cache_delete, cache_delete_pattern
        cache_delete(f"public_event:{event_id}")
        cache_delete(f"event_essential:v5:{event_id}")
        cache_delete_pattern("events:featured:*")
        cache_delete_pattern("events:nearby:*")
        cache_delete_pattern("events:search:*")
    except Exception:
        pass

    return standard_response(True, "Event updated successfully", _event_summary(db, event))


# ──────────────────────────────────────────────
# Delete Event
# ──────────────────────────────────────────────
@router.delete("/{event_id}")
def delete_event(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Deletes an event."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")
    if str(event.organizer_id) != str(current_user.id):
        return standard_response(False, "You do not have permission to delete this event")

    confirmed = db.query(EventService).filter(EventService.event_id == eid, EventService.service_status.in_([EventServiceStatusEnum.assigned, EventServiceStatusEnum.in_progress])).count()
    if confirmed > 0:
        return standard_response(False, "Cannot delete event with confirmed bookings. Cancel bookings first.")

    # Collect file URLs to unlink before deleting from DB
    cover_url = event.cover_image_url
    gallery_images = db.query(EventImage).filter(EventImage.event_id == eid).all()
    gallery_urls = [img.image_url for img in gallery_images]

    db.delete(event)
    try:
        db.commit()
    except Exception as e:
        db.rollback()
        return standard_response(False, f"Failed to delete event: {str(e)}")

    # Invalidate public event cache
    try:
        from core.redis import cache_delete, cache_delete_pattern
        cache_delete(f"public_event:{event_id}")
        cache_delete(f"event_essential:v5:{event_id}")
        cache_delete_pattern("events:featured:*")
        cache_delete_pattern("events:nearby:*")
        cache_delete_pattern("events:search:*")
    except Exception:
        pass

    # Physically unlink all storage files (best-effort, synchronous)
    from utils.helpers import delete_storage_file_sync
    if cover_url:
        delete_storage_file_sync(cover_url)
    for url in gallery_urls:
        if url:
            delete_storage_file_sync(url)

    return standard_response(True, "Event deleted successfully")


# ──────────────────────────────────────────────
# Update Event Status
# ──────────────────────────────────────────────
@router.put("/{event_id}/status")
def update_event_status(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Updates event status (publish, cancel, complete)."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")
    if str(event.organizer_id) != str(current_user.id):
        return standard_response(False, "Only the event organizer can change the status")

    new_status = body.get("status", "").strip()
    mapped = new_status
    valid = {s.value for s in EventStatusEnum}
    if mapped not in valid:
        return standard_response(False, f"Invalid status. Must be one of: {', '.join(valid)}")

    now = datetime.now(EAT)
    event.status = EventStatusEnum(mapped)
    event.updated_at = now

    if mapped == "confirmed":
        event.is_public = True

    try:
        db.commit()
    except Exception as e:
        db.rollback()
        return standard_response(False, f"Failed to update status: {str(e)}")

    try:
        from core.redis import cache_delete, cache_delete_pattern
        cache_delete(f"public_event:{event_id}")
        cache_delete(f"event_essential:v5:{event_id}")
        cache_delete_pattern("events:featured:*")
        cache_delete_pattern("events:nearby:*")
        cache_delete_pattern("events:search:*")
    except Exception:
        pass

    return standard_response(True, "Event status updated successfully", {
        "id": str(event.id),
        "status": mapped,
        "updated_at": now.isoformat(),
    })


# ──────────────────────────────────────────────
# Upload Event Images
# ──────────────────────────────────────────────
@router.post("/{event_id}/images")
async def upload_event_images(event_id: str, images: List[UploadFile] = File(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_edit_event")
    if err:
        return err

    now = datetime.now(EAT)
    uploaded = []
    for file in images:
        if not file or not file.filename:
            continue
        result = await _upload_image(file, f"nuru/uploads/events/{eid}/gallery/")
        if result["success"]:
            img = EventImage(id=uuid.uuid4(), event_id=eid, image_url=result["url"], created_at=now, updated_at=now)
            db.add(img)
            uploaded.append({"id": str(img.id), "image_url": result["url"]})

    db.commit()
    return standard_response(True, f"{len(uploaded)} images uploaded successfully", uploaded)


# ──────────────────────────────────────────────
# Delete Event Image
# ──────────────────────────────────────────────
@router.delete("/{event_id}/images/{image_id}")
def delete_event_image(event_id: str, image_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        iid = uuid.UUID(image_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_edit_event")
    if err:
        return err

    img = db.query(EventImage).filter(EventImage.id == iid, EventImage.event_id == eid).first()
    if not img:
        return standard_response(False, "Image not found")

    image_url = img.image_url  # capture before delete
    db.delete(img)
    db.commit()

    # Physically remove file from storage (best-effort, synchronous)
    from utils.helpers import delete_storage_file_sync
    delete_storage_file_sync(image_url)

    return standard_response(True, "Image deleted successfully")


# ──────────────────────────────────────────────
# Update Event Settings
# ──────────────────────────────────────────────
@router.put("/{event_id}/settings")
def update_event_settings(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_edit_event")
    if err:
        return err

    settings = db.query(EventSetting).filter(EventSetting.event_id == eid).first()
    if not settings:
        settings = EventSetting(id=uuid.uuid4(), event_id=eid)
        db.add(settings)

    for field in ["rsvp_enabled", "allow_plus_ones", "require_meal_preference", "contributions_enabled", "show_contribution_progress", "allow_anonymous_contributions", "checkin_enabled", "allow_nfc_checkin", "allow_qr_checkin", "allow_manual_checkin", "is_public", "show_guest_list", "show_committee"]:
        if field in body:
            setattr(settings, field, body[field])

    if "max_plus_ones" in body:
        settings.max_plus_ones = body["max_plus_ones"]
    if "meal_options" in body:
        settings.meal_options = body["meal_options"]
    if "contribution_target_amount" in body:
        settings.contribution_target_amount = body["contribution_target_amount"]
    if "minimum_contribution" in body:
        settings.minimum_contribution = body["minimum_contribution"]
    if "rsvp_deadline" in body and body["rsvp_deadline"]:
        try:
            settings.rsvp_deadline = datetime.fromisoformat(body["rsvp_deadline"].replace("Z", "+00:00"))
        except ValueError:
            pass

    settings.updated_at = datetime.now(EAT)
    db.commit()

    return standard_response(True, "Event settings updated successfully")


# ──────────────────────────────────────────────
# GUEST MANAGEMENT HELPERS
# ──────────────────────────────────────────────

def _resolve_guest_name(db: Session, att: EventAttendee) -> str | None:
    """Resolve display name for an attendee regardless of guest type."""
    guest_type = att.guest_type.value if hasattr(att.guest_type, "value") else (att.guest_type or "user")
    if guest_type == "contributor":
        if att.contributor_id:
            contributor = db.query(UserContributor).filter(UserContributor.id == att.contributor_id).first()
            if contributor:
                return contributor.name
        return att.guest_name
    else:
        if att.attendee_id:
            user = db.query(User).filter(User.id == att.attendee_id).first()
            if user:
                return f"{user.first_name} {user.last_name}"
        return att.guest_name


def _attendee_dict(db: Session, att: EventAttendee) -> dict:
    guest_type = att.guest_type.value if hasattr(att.guest_type, "value") else (att.guest_type or "user")

    # Resolve guest info based on type
    name = email = phone = avatar = None
    if guest_type == "contributor":
        contributor = db.query(UserContributor).filter(UserContributor.id == att.contributor_id).first() if att.contributor_id else None
        if contributor:
            name = contributor.name
            email = contributor.email
            phone = contributor.phone
        else:
            name = att.guest_name
            email = att.guest_email
            phone = att.guest_phone
    else:
        user = db.query(User).filter(User.id == att.attendee_id).first() if att.attendee_id else None
        if user:
            name = f"{user.first_name} {user.last_name}"
            email = user.email
            phone = user.phone
            avatar = user.profile.profile_picture_url if user.profile else None
        else:
            name = att.guest_name

    invitation = db.query(EventInvitation).filter(EventInvitation.id == att.invitation_id).first() if att.invitation_id else None
    plus_ones = db.query(EventGuestPlusOne).filter(EventGuestPlusOne.attendee_id == att.id).all()
    return {
        "id": str(att.id), "event_id": str(att.event_id),
        "guest_type": guest_type,
        "name": name, "avatar": avatar,
        "common_name": getattr(att, "common_name", None),
        "email": email, "phone": phone,
        "rsvp_status": att.rsvp_status.value if hasattr(att.rsvp_status, "value") else att.rsvp_status,
        "dietary_requirements": att.dietary_restrictions, "meal_preference": att.meal_preference,
        "special_requests": att.special_requests,
        "plus_ones": len(plus_ones), "plus_one_names": [po.name for po in plus_ones],
        "notes": invitation.notes if invitation else None,
        "invitation_sent": invitation.sent_at is not None if invitation else False,
        "invitation_sent_at": invitation.sent_at.isoformat() if invitation and invitation.sent_at else None,
        "invitation_method": invitation.sent_via if invitation else None,
        "checked_in": att.checked_in,
        "checked_in_at": att.checked_in_at.isoformat() if att.checked_in_at else None,
        "created_at": att.created_at.isoformat() if att.created_at else None,
    }


@router.get("/{event_id}/guests")
def get_guests(event_id: str, page: int = 1, limit: int = 50, rsvp_status: str = "all", search: str = "", db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_view_guests")
    if err:
        return err

    query = db.query(EventAttendee).filter(EventAttendee.event_id == eid)
    if rsvp_status != "all":
        query = query.filter(EventAttendee.rsvp_status == rsvp_status)

    total = query.count()
    total_pages = max(1, math.ceil(total / limit))
    attendees = query.order_by(EventAttendee.created_at.desc()).offset((page - 1) * limit).limit(limit).all()

    # Summary counts — collapse 6 queries into 1 grouped count + 1 invitation count
    status_rows = db.query(
        EventAttendee.rsvp_status, sa_func.count(EventAttendee.id)
    ).filter(EventAttendee.event_id == eid).group_by(EventAttendee.rsvp_status).all()
    status_counts = {row[0].value if hasattr(row[0], "value") else str(row[0]): row[1] for row in status_rows}
    checked_in_count = db.query(sa_func.count(EventAttendee.id)).filter(
        EventAttendee.event_id == eid, EventAttendee.checked_in == True
    ).scalar() or 0
    invitations_sent = db.query(sa_func.count(EventInvitation.id)).filter(
        EventInvitation.event_id == eid
    ).scalar() or 0

    summary = {
        "total": sum(status_counts.values()),
        "confirmed": status_counts.get("confirmed", 0),
        "pending": status_counts.get("pending", 0),
        "declined": status_counts.get("declined", 0),
        "maybe": status_counts.get("maybe", 0),
        "checked_in": checked_in_count,
        "invitations_sent": invitations_sent,
    }

    from utils.batch_loaders import build_event_attendee_dicts
    return standard_response(True, "Guests retrieved successfully", {
        "guests": build_event_attendee_dicts(db, attendees),
        "summary": summary,
        "pagination": {"page": page, "limit": limit, "total_items": total, "total_pages": total_pages, "has_next": page < total_pages, "has_previous": page > 1},
    })


@router.post("/{event_id}/guests")
def add_guest(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_guests")
    if err:
        return err

    name = body.get("name", "").strip()
    if not name:
        return standard_response(False, "Guest name is required.")

    guest_type_str = body.get("guest_type", "user")
    now = datetime.now(EAT)

    if guest_type_str == "contributor":
        # ── Contributor guest ──
        contributor_id = body.get("contributor_id")
        if not contributor_id:
            return standard_response(False, "contributor_id is required for contributor guests")
        try:
            cid = uuid.UUID(contributor_id)
        except ValueError:
            return standard_response(False, "Invalid contributor_id format")

        contributor = db.query(UserContributor).filter(UserContributor.id == cid).first()
        if not contributor:
            return standard_response(False, "Contributor not found in address book")

        # Pre-insertion duplicate check
        existing = db.query(EventAttendee).filter(
            EventAttendee.event_id == eid,
            EventAttendee.guest_type == GuestTypeEnum.contributor,
            EventAttendee.contributor_id == cid,
        ).first()
        if existing:
            return standard_response(False, f"{contributor.name} is already on the guest list for this event.")

        # Phone-based dedupe so the same number can't be added via a
        # different contributor record or as a free-text guest.
        if contributor.phone:
            digits = "".join(ch for ch in str(contributor.phone) if ch.isdigit())
            if len(digits) >= 9:
                last9 = digits[-9:]
                dup_phone = db.query(EventAttendee).filter(
                    EventAttendee.event_id == eid,
                    sa_func.right(sa_func.regexp_replace(EventAttendee.guest_phone, r'\D', '', 'g'), 9) == last9,
                ).first()
                if dup_phone:
                    return standard_response(False, f"A guest with phone {contributor.phone} is already on the guest list for this event.")

        invitation = EventInvitation(
            id=uuid.uuid4(), event_id=eid,
            guest_type=GuestTypeEnum.contributor,
            contributor_id=cid,
            guest_name=contributor.name,
            invited_by_user_id=current_user.id,
            invitation_code=generate_rsvp_code(),
            rsvp_status=RSVPStatusEnum.pending,
            notes=body.get("notes"),
            created_at=now, updated_at=now,
        )
        db.add(invitation)
        db.flush()

        att = EventAttendee(
            id=uuid.uuid4(), event_id=eid,
            guest_type=GuestTypeEnum.contributor,
            contributor_id=cid,
            guest_name=contributor.name,
            guest_phone=contributor.phone,
            guest_email=contributor.email,
            common_name=(body.get("common_name") or None),
            invitation_id=invitation.id,
            rsvp_status=RSVPStatusEnum.pending,
            dietary_restrictions=body.get("dietary_requirements"),
            meal_preference=body.get("meal_preference"),
            special_requests=body.get("special_requests"),
            created_at=now, updated_at=now,
        )
        db.add(att)

        for po_name in body.get("plus_one_names", []):
            db.add(EventGuestPlusOne(id=uuid.uuid4(), attendee_id=att.id, name=po_name, created_at=now, updated_at=now))

        try:
            db.commit()
        except Exception as e:
            db.rollback()
            return standard_response(False, f"Failed to add guest: {str(e)}")

        # SMS + WhatsApp to contributor if they have a phone
        if contributor.phone:
            event_date = _wa_event_date(event)
            from utils.event_owner import get_event_owner_display_name
            organizer_name = get_event_owner_display_name(
                event, db=db,
                fallback=f"{current_user.first_name} {current_user.last_name}".strip(),
            )
            try:
                from utils.wa_logging import set_wa_log_context
                set_wa_log_context(event_id=str(event.id), event_name=event.name,
                                   source_module="event_guests", purpose="invitation_card",
                                   recipient_type="contributor",
                                   related_entity_type="event_attendee",
                                   related_entity_id=str(att.id))
            except Exception: pass
            sms_guest_added(contributor.phone, contributor.name.split(" ")[0], event.name, event_date, organizer_name, invitation.invitation_code)
            wa_send_invitation_card(contributor.phone, str(event.id), str(invitation.id), contributor.name, event.name, event_date, organizer_name, invitation.invitation_code, getattr(event, "cover_image_url", None) or "", event_time=getattr(event, "start_time", None).isoformat() if getattr(event, "start_time", None) else "", venue=getattr(event, "location", None) or "")

        return standard_response(True, "Guest added successfully", _attendee_dict(db, att))

    else:
        # ── User guest (existing behavior) ──
        user_id = body.get("user_id")
        attendee_user = None
        if user_id:
            try:
                attendee_user = db.query(User).filter(User.id == uuid.UUID(user_id)).first()
            except ValueError:
                pass
        email = body.get("email")
        phone = body.get("phone")
        if not attendee_user:
            if email:
                attendee_user = db.query(User).filter(User.email == email).first()
            if not attendee_user and phone:
                attendee_user = db.query(User).filter(User.phone == phone).first()

        # Pre-insertion duplicate check
        if attendee_user:
            existing_attendee = db.query(EventAttendee).filter(
                EventAttendee.event_id == eid,
                EventAttendee.attendee_id == attendee_user.id,
            ).first()
            if existing_attendee:
                return standard_response(False, f"{name} is already on the guest list for this event.")

            existing_invitation = db.query(EventInvitation).filter(
                EventInvitation.event_id == eid,
                EventInvitation.invited_user_id == attendee_user.id,
            ).first()
            if existing_invitation:
                return standard_response(False, f"{name} has already been invited to this event.")

        # Phone-based dedupe for free-text guests (no linked user/contributor).
        # Matches by last 9 digits to ignore country-code formatting differences.
        if phone:
            digits = "".join(ch for ch in str(phone) if ch.isdigit())
            if len(digits) >= 9:
                last9 = digits[-9:]
                dup_att = db.query(EventAttendee).filter(
                    EventAttendee.event_id == eid,
                    sa_func.right(sa_func.regexp_replace(EventAttendee.guest_phone, r'\D', '', 'g'), 9) == last9,
                ).first()
                if dup_att:
                    return standard_response(False, f"A guest with phone {phone} is already on the guest list for this event.")

        # Name-based dedupe for free-text guests with no phone, to stop
        # accidental double-taps creating identical rows.
        if not attendee_user and not phone and name:
            dup_named = db.query(EventAttendee).filter(
                EventAttendee.event_id == eid,
                EventAttendee.attendee_id.is_(None),
                EventAttendee.contributor_id.is_(None),
                sa_func.lower(EventAttendee.guest_name) == name.lower(),
            ).first()
            if dup_named:
                return standard_response(False, f"{name} is already on the guest list for this event.")

        invitation = EventInvitation(
            id=uuid.uuid4(), event_id=eid,
            guest_type=GuestTypeEnum.user,
            invited_user_id=attendee_user.id if attendee_user else None,
            guest_name=name if not attendee_user else None,
            invited_by_user_id=current_user.id,
            invitation_code=generate_rsvp_code(),
            rsvp_status=RSVPStatusEnum.pending,
            notes=body.get("notes"),
            created_at=now, updated_at=now,
        )
        db.add(invitation)
        db.flush()

        att = EventAttendee(
            id=uuid.uuid4(), event_id=eid,
            guest_type=GuestTypeEnum.user,
            attendee_id=attendee_user.id if attendee_user else None,
            guest_name=name if not attendee_user else None,
            guest_phone=phone if phone else None,
            guest_email=email if email else None,
            common_name=(body.get("common_name") or None),
            invitation_id=invitation.id,
            rsvp_status=RSVPStatusEnum.pending,
            dietary_restrictions=body.get("dietary_requirements"),
            meal_preference=body.get("meal_preference"),
            special_requests=body.get("special_requests"),
            created_at=now, updated_at=now,
        )
        db.add(att)

        for po_name in body.get("plus_one_names", []):
            db.add(EventGuestPlusOne(id=uuid.uuid4(), attendee_id=att.id, name=po_name, created_at=now, updated_at=now))

        try:
            db.commit()
        except Exception as e:
            db.rollback()
            return standard_response(False, f"Failed to add guest: {str(e)}")

        # Create notification + send SMS for the invited user
        if attendee_user and attendee_user.id != current_user.id:
            try:
                from utils.notify import notify_event_invitation
                notify_event_invitation(db, attendee_user.id, current_user.id, eid, event.name)
                db.commit()
            except Exception:
                pass
            event_date = _wa_event_date(event)
            from utils.event_owner import get_event_owner_display_name
            organizer_name = get_event_owner_display_name(
                event, db=db,
                fallback=f"{current_user.first_name} {current_user.last_name}".strip(),
            )
            try:
                from utils.wa_logging import set_wa_log_context
                set_wa_log_context(event_id=str(event.id), event_name=event.name,
                                   source_module="event_guests", purpose="invitation_card",
                                   recipient_type="user",
                                   related_entity_type="event_attendee",
                                   related_entity_id=str(att.id))
            except Exception: pass
            sms_guest_added(attendee_user.phone, f"{attendee_user.first_name}", event.name, event_date, organizer_name, invitation.invitation_code)
            guest_full_name = f"{attendee_user.first_name or ''} {attendee_user.last_name or ''}".strip() or f"{attendee_user.first_name}"
            wa_send_invitation_card(attendee_user.phone, str(event.id), str(invitation.id), guest_full_name, event.name, event_date, organizer_name, invitation.invitation_code, getattr(event, "cover_image_url", None) or "", event_time=getattr(event, "start_time", None).isoformat() if getattr(event, "start_time", None) else "", venue=getattr(event, "location", None) or "")

        return standard_response(True, "Guest added successfully", _attendee_dict(db, att))


@router.post("/{event_id}/guests/bulk")
def add_guests_bulk(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_guests")
    if err:
        return err

    guests_data = body.get("guests", [])
    now = datetime.now(EAT)
    imported = []
    skipped = 0
    errors_list = []

    for i, guest in enumerate(guests_data):
        name = guest.get("name", "").strip()
        if not name:
            errors_list.append({"row": i + 1, "error": "Name is required"})
            continue

        email = guest.get("email")
        phone = guest.get("phone")
        if body.get("skip_duplicates", True) and email:
            existing = db.query(EventAttendee).join(User, EventAttendee.attendee_id == User.id).filter(EventAttendee.event_id == eid, User.email == email).first()
            if existing:
                skipped += 1
                continue

        # Phone-based dedupe (last 9 digits) to prevent the same phone
        # number being added multiple times across imports.
        if body.get("skip_duplicates", True) and phone:
            digits = "".join(ch for ch in str(phone) if ch.isdigit())
            if len(digits) >= 9:
                last9 = digits[-9:]
                dup = db.query(EventAttendee).filter(
                    EventAttendee.event_id == eid,
                    sa_func.right(sa_func.regexp_replace(EventAttendee.guest_phone, r'\D', '', 'g'), 9) == last9,
                ).first()
                if dup:
                    skipped += 1
                    continue

        attendee_user = db.query(User).filter(User.email == email).first() if email else None

        invitation = EventInvitation(id=uuid.uuid4(), event_id=eid, guest_type=GuestTypeEnum.user, invited_user_id=attendee_user.id if attendee_user else None, guest_name=name if not attendee_user else None, invited_by_user_id=current_user.id, invitation_code=generate_rsvp_code(), rsvp_status=RSVPStatusEnum.pending, created_at=now, updated_at=now)
        db.add(invitation)

        att = EventAttendee(id=uuid.uuid4(), event_id=eid, guest_type=GuestTypeEnum.user, attendee_id=attendee_user.id if attendee_user else None, guest_name=name if not attendee_user else None, guest_phone=phone if phone else None, guest_email=email if email else None, invitation_id=invitation.id, rsvp_status=RSVPStatusEnum.pending, created_at=now, updated_at=now)
        db.add(att)
        imported.append({"id": str(att.id), "name": name})

    try:
        db.commit()
    except Exception as e:
        db.rollback()
        return standard_response(False, f"Failed to import guests: {str(e)}")

    return standard_response(True, "Guests imported successfully", {"imported": len(imported), "skipped": skipped, "errors": errors_list})


# ──────────────────────────────────────────────
# Add Contributors as Guests (batch)
# ──────────────────────────────────────────────
@router.post("/{event_id}/guests/from-contributors")
def add_contributors_as_guests(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Add one or more event contributors as guests. Expects { contributor_ids: [...], send_sms: bool }."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_guests")
    if err:
        return err

    contributor_ids_raw = body.get("contributor_ids", [])
    send_sms = body.get("send_sms", False)
    if not contributor_ids_raw:
        return standard_response(False, "No contributor IDs provided.")

    now = datetime.now(EAT)
    added = 0
    skipped = 0
    errors_list = []

    for raw_id in contributor_ids_raw:
        try:
            cid = uuid.UUID(raw_id)
        except ValueError:
            errors_list.append({"contributor_id": raw_id, "error": "Invalid ID format"})
            continue

        # Accept either an EventContributor link id OR an underlying
        # UserContributor id. The address-book invitation panel passes
        # the UserContributor id, while older callers pass the link id.
        ec = db.query(EventContributor).filter(
            EventContributor.event_id == eid,
            ((EventContributor.id == cid) | (EventContributor.contributor_id == cid)),
        ).first()
        if not ec:
            errors_list.append({"contributor_id": raw_id, "error": "Event contributor not found"})
            continue

        contributor = db.query(UserContributor).filter(UserContributor.id == ec.contributor_id).first()
        if not contributor:
            errors_list.append({"contributor_id": raw_id, "error": "Contributor record not found"})
            continue

        # Duplicate check
        existing = db.query(EventAttendee).filter(
            EventAttendee.event_id == eid,
            EventAttendee.guest_type == GuestTypeEnum.contributor,
            EventAttendee.contributor_id == contributor.id,
        ).first()
        if existing:
            skipped += 1
            continue

        # Phone-based dedupe — different contributor records sharing the
        # same phone shouldn't all land on the guest list.
        if contributor.phone:
            digits = "".join(ch for ch in str(contributor.phone) if ch.isdigit())
            if len(digits) >= 9:
                last9 = digits[-9:]
                dup_phone = db.query(EventAttendee).filter(
                    EventAttendee.event_id == eid,
                    sa_func.right(sa_func.regexp_replace(EventAttendee.guest_phone, r'\D', '', 'g'), 9) == last9,
                ).first()
                if dup_phone:
                    skipped += 1
                    continue

        invitation = EventInvitation(
            id=uuid.uuid4(), event_id=eid,
            guest_type=GuestTypeEnum.contributor,
            contributor_id=contributor.id,
            guest_name=contributor.name,
            invited_by_user_id=current_user.id,
            invitation_code=generate_rsvp_code(),
            rsvp_status=RSVPStatusEnum.pending,
            created_at=now, updated_at=now,
        )
        db.add(invitation)
        db.flush()

        att = EventAttendee(
            id=uuid.uuid4(), event_id=eid,
            guest_type=GuestTypeEnum.contributor,
            contributor_id=contributor.id,
            guest_name=contributor.name,
            guest_phone=contributor.phone,
            guest_email=contributor.email,
            invitation_id=invitation.id,
            rsvp_status=RSVPStatusEnum.pending,
            created_at=now, updated_at=now,
        )
        db.add(att)
        added += 1

        # Send SMS if opted in
        if send_sms and contributor.phone:
            event_date = _wa_event_date(event)
            from utils.event_owner import get_event_owner_display_name
            organizer_name = get_event_owner_display_name(
                event, db=db,
                fallback=f"{current_user.first_name} {current_user.last_name}".strip(),
            )
            try:
                from utils.wa_logging import set_wa_log_context
                set_wa_log_context(event_id=str(event.id), event_name=event.name,
                                   source_module="event_guests_bulk", purpose="invitation_card",
                                   recipient_type="contributor",
                                   related_entity_type="event_attendee",
                                   related_entity_id=str(att.id))
            except Exception: pass
            try:
                sms_guest_added(contributor.phone, contributor.name.split(" ")[0], event.name, event_date, organizer_name, invitation.invitation_code)
                wa_send_invitation_card(contributor.phone, str(event.id), str(invitation.id), contributor.name, event.name, event_date, organizer_name, invitation.invitation_code, getattr(event, "cover_image_url", None) or "", event_time=getattr(event, "start_time", None).isoformat() if getattr(event, "start_time", None) else "", venue=getattr(event, "location", None) or "")
            except Exception:
                pass  # Don't fail the whole batch for one SMS/WhatsApp error

    try:
        db.commit()
    except Exception as e:
        db.rollback()
        return standard_response(False, f"Failed to add guests: {str(e)}")

    return standard_response(True, f"{added} contributor(s) added as guests", {
        "added": added,
        "skipped": skipped,
        "errors": errors_list,
    })


@router.put("/{event_id}/guests/{guest_id}")
def update_guest(event_id: str, guest_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        gid = uuid.UUID(guest_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_guests")
    if err:
        return err

    att = db.query(EventAttendee).filter(EventAttendee.id == gid, EventAttendee.event_id == eid).first()
    if not att:
        return standard_response(False, "Guest not found")

    now = datetime.now(EAT)
    if "dietary_requirements" in body: att.dietary_restrictions = body["dietary_requirements"]
    if "meal_preference" in body: att.meal_preference = body["meal_preference"]
    if "special_requests" in body: att.special_requests = body["special_requests"]
    if "rsvp_status" in body:
        new_status = (body.get("rsvp_status") or "").strip().lower()
        valid_statuses = {"pending", "confirmed", "declined", "maybe", "checked_in"}
        if new_status not in valid_statuses:
            return standard_response(False, f"Invalid RSVP status. Must be one of: {', '.join(sorted(valid_statuses))}")
        att.rsvp_status = new_status
        # Mirror to the linked invitation row so the RSVP tab and webhook stay in sync.
        if att.invitation_id:
            inv = db.query(EventInvitation).filter(EventInvitation.id == att.invitation_id).first()
            if inv:
                inv.rsvp_status = new_status
                inv.rsvp_at = now
                inv.updated_at = now
    if "common_name" in body:
        cn = (body.get("common_name") or "").strip()
        att.common_name = cn or None
    att.updated_at = now

    if "plus_one_names" in body:
        db.query(EventGuestPlusOne).filter(EventGuestPlusOne.attendee_id == att.id).delete()
        for po_name in body.get("plus_one_names", []):
            db.add(EventGuestPlusOne(id=uuid.uuid4(), attendee_id=att.id, name=po_name, created_at=now, updated_at=now))

    db.commit()
    return standard_response(True, "Guest updated successfully", _attendee_dict(db, att))


@router.delete("/{event_id}/guests/{guest_id}")
def remove_guest(event_id: str, guest_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        gid = uuid.UUID(guest_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_guests")
    if err:
        return err

    att = db.query(EventAttendee).filter(EventAttendee.id == gid, EventAttendee.event_id == eid).first()
    if not att:
        return standard_response(False, "Guest not found")

    # Delete associated plus-ones
    db.query(EventGuestPlusOne).filter(EventGuestPlusOne.attendee_id == att.id).delete()

    # Delete associated invitation
    if att.invitation_id:
        db.query(EventInvitation).filter(EventInvitation.id == att.invitation_id).delete()
    else:
        # Also check by user/contributor match
        inv_q = db.query(EventInvitation).filter(EventInvitation.event_id == eid)
        if att.attendee_id:
            inv_q = inv_q.filter(EventInvitation.invited_user_id == att.attendee_id)
        elif att.contributor_id:
            inv_q = inv_q.filter(EventInvitation.contributor_id == att.contributor_id)
        inv_q.delete()

    db.delete(att)
    db.commit()
    return standard_response(True, "Guest removed successfully")


@router.delete("/{event_id}/guests/bulk")
def remove_guests_bulk(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_guests")
    if err:
        return err

    deleted = 0
    for gid_str in body.get("guest_ids", []):
        try:
            att = db.query(EventAttendee).filter(EventAttendee.id == uuid.UUID(gid_str), EventAttendee.event_id == eid).first()
            if att:
                db.query(EventGuestPlusOne).filter(EventGuestPlusOne.attendee_id == att.id).delete()
                if att.invitation_id:
                    db.query(EventInvitation).filter(EventInvitation.id == att.invitation_id).delete()
                db.delete(att)
                deleted += 1
        except ValueError:
            continue

    db.commit()
    return standard_response(True, f"{deleted} guests removed successfully", {"deleted": deleted})


@router.post("/{event_id}/guests/{guest_id}/invite")
def send_invitation(event_id: str, guest_id: str, body: dict = Body(default={}), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        gid = uuid.UUID(guest_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_send_invitations")
    if err:
        return err

    att = db.query(EventAttendee).filter(EventAttendee.id == gid, EventAttendee.event_id == eid).first()
    if not att:
        return standard_response(False, "Guest not found")

    method = body.get("method", "email")
    now = datetime.now(EAT)

    invitation = db.query(EventInvitation).filter(EventInvitation.id == att.invitation_id).first() if att.invitation_id else None
    if invitation:
        invitation.sent_via = method
        invitation.sent_at = now
        invitation.updated_at = now
    else:
        invitation = EventInvitation(id=uuid.uuid4(), event_id=eid, invited_by_user_id=current_user.id, invitation_code=uuid.uuid4().hex[:16], rsvp_status=RSVPStatusEnum.pending, sent_via=method, sent_at=now, created_at=now, updated_at=now)
        db.add(invitation)
        att.invitation_id = invitation.id

    db.commit()

    # Actually deliver the invitation through the requested channel.
    # Resolve guest name/phone from the attendee row, falling back to the linked
    # User if this is a registered attendee.
    guest_name = (att.guest_name or "").strip()
    guest_phone = (att.guest_phone or "").strip()
    guest_email = (att.guest_email or "").strip()
    if att.attendee_id and (not guest_name or not guest_phone or not guest_email):
        u = db.query(User).filter(User.id == att.attendee_id).first()
        if u:
            if not guest_name:
                guest_name = f"{(u.first_name or '').strip()} {(u.last_name or '').strip()}".strip() or "Guest"
            if not guest_phone:
                guest_phone = (u.phone or "").strip()
            if not guest_email:
                guest_email = (u.email or "").strip()
    if not guest_name:
        guest_name = "Guest"

    try:
        from utils.event_owner import get_event_owner_display_name
        organizer_name = get_event_owner_display_name(event, db=db)
    except Exception:
        organizer_name = ""

    event_date_str = _wa_event_date(event)
    event_cover_image = _wa_event_cover_image(db, event)
    print(f"[send_invitation] event_id={event.id} cover_image={event_cover_image!r}")

    first_name = guest_name.split(" ")[0] if guest_name else "Guest"
    delivered = False
    try:
        try:
            from utils.wa_logging import set_wa_log_context
            set_wa_log_context(event_id=str(event.id), event_name=event.name,
                               source_module="send_invitation", purpose="invitation_card",
                               recipient_type="guest",
                               related_entity_type="event_invitation",
                               related_entity_id=str(invitation.id))
        except Exception: pass
        if method == "whatsapp" and guest_phone:
            wa_send_invitation_card(guest_phone, str(event.id), str(invitation.id), guest_name, event.name or "your event", event_date_str, organizer_name, invitation.invitation_code or "", event_cover_image, event_time=getattr(event, "start_time", None).isoformat() if getattr(event, "start_time", None) else "", venue=getattr(event, "location", None) or "")
            delivered = True
        elif method == "whatsapp_text" and guest_phone:
            wa_send_invitation_text(guest_phone, guest_name, event.name or "your event", organizer_name, event_date_str, getattr(event, "start_time", None).isoformat() if getattr(event, "start_time", None) else "", getattr(event, "location", None) or "", invitation.invitation_code or "")
            delivered = True
        elif method == "sms" and guest_phone:
            sms_guest_added(guest_phone, first_name, event.name or "your event", event_date_str, organizer_name, invitation.invitation_code or "")
            delivered = True
        elif method == "email":
            # Email delivery path is not wired yet — keep DB stamp but report honestly.
            delivered = False
    except Exception as e:
        print(f"[send_invitation] delivery failed via {method}: {e}")
        delivered = False

    return standard_response(True, "Invitation sent successfully" if delivered else "Invitation recorded (delivery pending)", {
        "guest_id": str(att.id),
        "method": method,
        "delivered": delivered,
        "sent_at": now.isoformat(),
        "invitation_url": f"https://nuru.tz/rsvp/{invitation.invitation_code}",
    })


@router.post("/{event_id}/guests/invite-all")
def send_bulk_invitations(event_id: str, body: dict = Body(default={}), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_send_invitations")
    if err:
        return err

    method = body.get("method", "email")
    now = datetime.now(EAT)
    attendees = db.query(EventAttendee).filter(EventAttendee.event_id == eid).all()
    sent = 0
    for att in attendees:
        inv = db.query(EventInvitation).filter(EventInvitation.id == att.invitation_id).first() if att.invitation_id else None
        if inv:
            inv.sent_via = method
            inv.sent_at = now
            inv.updated_at = now
            sent += 1

    db.commit()
    return standard_response(True, "Invitations sent", {"total_selected": len(attendees), "sent_count": sent})


@router.post("/{event_id}/guests/{guest_id}/resend-invite")
def resend_invitation(event_id: str, guest_id: str, body: dict = Body(default={}), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return send_invitation(event_id, guest_id, body or {}, db, current_user)


@router.post("/{event_id}/guests/{guest_id}/checkin")
def checkin_guest(event_id: str, guest_id: str, body: dict = Body(default={}), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        gid = uuid.UUID(guest_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_check_in_guests")
    if err:
        return err

    att = db.query(EventAttendee).filter(EventAttendee.id == gid, EventAttendee.event_id == eid).first()
    if not att:
        return standard_response(False, "Guest not found")

    if att.checked_in:
        return standard_response(False, "Guest already checked in", {"checked_in_at": att.checked_in_at.isoformat() if att.checked_in_at else None})

    now = datetime.now(EAT)
    att.checked_in = True
    att.checked_in_at = now
    att.rsvp_status = RSVPStatusEnum.confirmed
    att.updated_at = now
    db.commit()

    name = _resolve_guest_name(db, att)
    return standard_response(True, "Guest checked in successfully", {"guest_id": str(att.id), "name": name, "checked_in": True, "checked_in_at": now.isoformat()})


def _extract_scan_code(raw: str) -> str:
    """Extract a usable code from raw QR payload.

    Accepts: bare codes, `nuru://event/<eid>/checkin/<id>`,
    `nuru://event/<eid>/rsvp/<code>`, `nuru://ticket/<code>`,
    `https://.../verify/<code>`, `https://.../checkin/<id>`.
    """
    s = (raw or "").strip()
    if not s:
        return ""
    markers = [
        "/checkin/", "/rsvp/", "/verify/contribution/", "/contributions/verify/",
        "/verify/", "/ticket/", "/tickets/",
    ]
    lower = s.lower()
    for m in markers:
        i = lower.rfind(m)
        if i >= 0:
            tail = s[i + len(m):]
            for sep in ["?", "#", "/"]:
                j = tail.find(sep)
                if j >= 0:
                    tail = tail[:j]
            if tail:
                return tail.strip()
    return s


def _event_has_ticket_sales(db: Session, event: Event) -> bool:
    if bool(getattr(event, "sells_tickets", False)):
        return True
    return db.query(EventTicketClass.id).filter(EventTicketClass.event_id == event.id).first() is not None


def _scan_event_aggregates(db: Session, event: Event) -> dict:
    """Scan stats for the unified scanner UI.

    For ticketed events: counts ticket seats (sum of quantity over confirmed/
    approved orders). Total/Checked In/Pending refer to TICKETS.

    For non-ticketed events: counts ATTENDEES who have accepted the
    invitation (rsvp_status = confirmed OR checked_in). Total = accepted
    guests, Checked In = those scanned, Pending = accepted but not yet
    scanned. Guests who declined or never replied are not counted.
    """
    eid = event.id
    sells_tickets = _event_has_ticket_sales(db, event)

    if sells_tickets:
        total = int(db.query(sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0)).filter(
            EventTicket.event_id == eid,
            EventTicket.status.in_([TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed]),
        ).scalar() or 0)
        checked = int(db.query(sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0)).filter(
            EventTicket.event_id == eid,
            EventTicket.status.in_([TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed]),
            EventTicket.checked_in == True,
        ).scalar() or 0)
        mode = "tickets"
        labels = {"total": "Total Tickets", "checked_in": "Checked In", "pending": "Pending"}
    else:
        accepted_statuses = [RSVPStatusEnum.confirmed, RSVPStatusEnum.checked_in]
        total = int(db.query(sa_func.count(EventAttendee.id)).filter(
            EventAttendee.event_id == eid,
            EventAttendee.rsvp_status.in_(accepted_statuses),
        ).scalar() or 0)
        checked = int(db.query(sa_func.count(EventAttendee.id)).filter(
            EventAttendee.event_id == eid,
            EventAttendee.checked_in == True,
        ).scalar() or 0)
        mode = "guests"
        labels = {"total": "Total Guests", "checked_in": "Checked In", "pending": "Pending"}

    return {
        "mode": mode,
        "labels": labels,
        "total": total,
        "checked_in": checked,
        "pending": max(0, total - checked),
    }


@router.get("/{event_id}/scan/stats")
def get_scan_stats(event_id: str, limit: int = Query(10, ge=1, le=100), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Premium scanner header data: event card + aggregate counts + recent scans."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_check_in_guests")
    if err:
        return err

    from api.routes.ticketing import _resolve_event_cover

    stats = _scan_event_aggregates(db, event)
    sells_tickets = _event_has_ticket_sales(db, event)
    title = "Ticket Check In" if sells_tickets else "Guest Check In"
    cover = _resolve_event_cover(event, db)

    # Recent scans — restricted to the relevant kind for this event mode.
    # Includes the latest checked-in records first, then pending ones to fill
    # the list (mirrors the design mockup which shows both states).
    recent: list[dict] = []
    if sells_tickets:
        rows = db.query(EventTicket).filter(
            EventTicket.event_id == eid,
            EventTicket.status.in_([TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed]),
        ).order_by(
            EventTicket.checked_in.desc(),
            EventTicket.checked_in_at.desc().nullslast(),
            EventTicket.created_at.desc(),
        ).limit(limit).all()
        buyer_ids = {t.buyer_user_id for t in rows if t.buyer_user_id}
        avatars = {}
        if buyer_ids:
            for uid, pic in db.query(UserProfile.user_id, UserProfile.profile_picture_url).filter(
                UserProfile.user_id.in_(buyer_ids)
            ).all():
                if pic:
                    avatars[uid] = pic
        for t in rows:
            recent.append({
                "kind": "ticket",
                "name": t.buyer_name or "Ticket Holder",
                "ref": t.ticket_code,
                "avatar": avatars.get(t.buyer_user_id),
                "checked_in_at": t.checked_in_at.isoformat() if t.checked_in_at else None,
                "status": "checked_in" if t.checked_in else "pending",
            })
    else:
        rows = db.query(EventAttendee).filter(
            EventAttendee.event_id == eid,
            EventAttendee.rsvp_status.in_([RSVPStatusEnum.confirmed, RSVPStatusEnum.checked_in]),
        ).order_by(
            EventAttendee.checked_in.desc(),
            EventAttendee.checked_in_at.desc().nullslast(),
            EventAttendee.updated_at.desc(),
        ).limit(limit).all()
        user_ids = {att.user_id for att in rows if getattr(att, 'user_id', None)}
        avatars = {}
        if user_ids:
            for uid, pic in db.query(UserProfile.user_id, UserProfile.profile_picture_url).filter(
                UserProfile.user_id.in_(user_ids)
            ).all():
                if pic:
                    avatars[uid] = pic
        for att in rows:
            recent.append({
                "kind": "guest",
                "name": _resolve_guest_name(db, att) or "Guest",
                "ref": str(att.id)[:8].upper(),
                "avatar": avatars.get(getattr(att, 'user_id', None)),
                "checked_in_at": att.checked_in_at.isoformat() if att.checked_in_at else None,
                "status": "checked_in" if att.checked_in else "pending",
            })

    return standard_response(True, "Scan stats", {
        "title": title,
        "event": {
            "id": str(event.id),
            "name": event.name,
            "start_date": str(event.start_date) if event.start_date else None,
            "location": event.location,
            "cover_image": cover,
            "image": cover,
            "sells_tickets": sells_tickets,
        },
        "stats": stats,
        "recent_scans": recent,
    })


def _ticket_payload(db: Session, ticket: EventTicket, event: Event, *, reason: str | None = None) -> dict:
    tc = db.query(EventTicketClass).filter(EventTicketClass.id == ticket.ticket_class_id).first()
    return {
        "kind": "ticket",
        "id": str(ticket.id),
        "code": ticket.ticket_code,
        "name": ticket.buyer_name or "Ticket Holder",
        "phone": ticket.buyer_phone,
        "email": ticket.buyer_email,
        "ticket_class": tc.name if tc else None,
        "ticket_id": ticket.ticket_code,
        "quantity": ticket.quantity or 1,
        "checked_in": ticket.checked_in,
        "checked_in_at": ticket.checked_in_at.isoformat() if ticket.checked_in_at else None,
        "event": {
            "id": str(event.id),
            "name": event.name,
            "start_date": str(event.start_date) if event.start_date else None,
            "location": event.location,
        },
        "reason": reason,
    }


def _attendee_payload(db: Session, att: EventAttendee, event: Event, *, reason: str | None = None) -> dict:
    plus_ones = db.query(EventGuestPlusOne).filter(EventGuestPlusOne.attendee_id == att.id).all()
    inv = db.query(EventInvitation).filter(EventInvitation.id == att.invitation_id).first() if att.invitation_id else None
    return {
        "kind": "guest",
        "id": str(att.id),
        "code": inv.invitation_code if inv else str(att.id)[:8].upper(),
        "name": _resolve_guest_name(db, att) or att.guest_name or "Guest",
        "phone": att.guest_phone,
        "email": att.guest_email,
        "ticket_class": "Guest Pass",
        "ticket_id": (inv.invitation_code if inv else str(att.id)[:8].upper()),
        "quantity": 1 + len(plus_ones),
        "rsvp_status": att.rsvp_status.value if hasattr(att.rsvp_status, "value") else att.rsvp_status,
        "checked_in": att.checked_in,
        "checked_in_at": att.checked_in_at.isoformat() if att.checked_in_at else None,
        "event": {
            "id": str(event.id),
            "name": event.name,
            "start_date": str(event.start_date) if event.start_date else None,
            "location": event.location,
        },
        "reason": reason,
    }


@router.post("/{event_id}/guests/checkin-qr")
def checkin_guest_qr(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Unified scanner: checks in either an event guest (invitation/attendee)
    OR a paid ticket. Returns a rich payload that the mobile success/failed
    screens render verbatim, plus refreshed aggregate stats.
    """
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_check_in_guests")
    if err:
        return err

    now = datetime.now(EAT)
    stats = _scan_event_aggregates(db, event)

    # Validate event timing
    if hasattr(event, 'start_date') and event.start_date:
        from datetime import date as date_type, timedelta
        event_date = event.start_date if isinstance(event.start_date, date_type) else (event.start_date.date() if hasattr(event.start_date, 'date') else None)
        if event_date:
            today = now.date()
            if event_date < today:
                return standard_response(False, "Cannot check in — this event has already ended", {
                    "reason": "event_ended",
                    "scan_time": now.isoformat(),
                    "event": {"id": str(event.id), "name": event.name},
                    "stats": stats,
                })
            if event_date > today + timedelta(days=1):
                return standard_response(False, "Cannot check in — this event hasn't started yet", {
                    "reason": "event_not_started",
                    "scan_time": now.isoformat(),
                    "event": {"id": str(event.id), "name": event.name},
                    "stats": stats,
                })

    raw = (body.get("code") or body.get("qr_code") or "").strip()
    if not raw:
        return standard_response(False, "QR code is required", {
            "reason": "empty_code",
            "scan_time": now.isoformat(),
            "event": {"id": str(event.id), "name": event.name},
            "stats": stats,
        })
    code = _extract_scan_code(raw)

    # ── Try TICKET first by ticket_code (most distinctive) ──
    ticket = db.query(EventTicket).filter(
        EventTicket.event_id == eid, EventTicket.ticket_code == code
    ).first()

    att = None
    if not ticket:
        # Try attendee UUID
        try:
            att_id = uuid.UUID(code)
            att = db.query(EventAttendee).filter(EventAttendee.id == att_id, EventAttendee.event_id == eid).first()
        except ValueError:
            pass
        # Try invitation code
        if not att:
            inv = db.query(EventInvitation).filter(EventInvitation.event_id == eid, EventInvitation.invitation_code == code).first()
            if inv:
                att = db.query(EventAttendee).filter(EventAttendee.invitation_id == inv.id).first()

    if not ticket and not att:
        return standard_response(False, "QR code not recognised for this event", {
            "reason": "not_found",
            "scanned_code": code,
            "scan_time": now.isoformat(),
            "event": {"id": str(event.id), "name": event.name},
            "stats": stats,
        })

    # ── TICKET branch ──
    if ticket:
        if ticket.status not in (TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed):
            payload = _ticket_payload(db, ticket, event, reason=f"ticket_{ticket.status.value}")
            payload.update({"scan_time": now.isoformat(), "stats": stats})
            return standard_response(False, f"Ticket is {ticket.status.value} — cannot check in", payload)
        if ticket.checked_in:
            payload = _ticket_payload(db, ticket, event, reason="already_used")
            payload.update({"scan_time": now.isoformat(), "stats": stats})
            return standard_response(False, "Ticket already used for check-in", payload)

        ticket.checked_in = True
        ticket.checked_in_at = now
        db.commit()
        stats = _scan_event_aggregates(db, event)
        payload = _ticket_payload(db, ticket, event)
        payload.update({"scan_time": now.isoformat(), "stats": stats})
        return standard_response(True, "Ticket checked in successfully", payload)

    # ── GUEST branch ──
    if att.checked_in:
        payload = _attendee_payload(db, att, event, reason="already_used")
        payload.update({"scan_time": now.isoformat(), "stats": stats})
        return standard_response(False, "Guest already checked in", payload)

    att.checked_in = True
    att.checked_in_at = now
    att.rsvp_status = RSVPStatusEnum.checked_in
    att.updated_at = now
    db.commit()
    stats = _scan_event_aggregates(db, event)
    payload = _attendee_payload(db, att, event)
    payload.update({"scan_time": now.isoformat(), "stats": stats})
    return standard_response(True, "Guest checked in successfully", payload)


@router.post("/{event_id}/guests/{guest_id}/undo-checkin")
def undo_checkin(event_id: str, guest_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        gid = uuid.UUID(guest_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_check_in_guests")
    if err:
        return err

    att = db.query(EventAttendee).filter(EventAttendee.id == gid, EventAttendee.event_id == eid).first()
    if not att:
        return standard_response(False, "Guest not found")

    att.checked_in = False
    att.checked_in_at = None
    att.updated_at = datetime.now(EAT)
    db.commit()

    return standard_response(True, "Check-in reverted successfully", {"guest_id": str(att.id), "checked_in": False})


@router.get("/{event_id}/guests/export")
def export_guests(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_view_guests")
    if err:
        return err

    attendees = db.query(EventAttendee).filter(EventAttendee.event_id == eid).all()
    from utils.batch_loaders import build_event_attendee_dicts
    data = build_event_attendee_dicts(db, attendees)
    return standard_response(True, "Guest list exported successfully", data)


# ──────────────────────────────────────────────
# COMMITTEE MANAGEMENT
# ──────────────────────────────────────────────

def _member_dict(db: Session, cm) -> dict:
    member_user = db.query(User).filter(User.id == cm.user_id).first() if cm.user_id else None
    profile = db.query(UserProfile).filter(UserProfile.user_id == cm.user_id).first() if cm.user_id else None
    role = db.query(CommitteeRole).filter(CommitteeRole.id == cm.role_id).first() if cm.role_id else None
    perms = db.query(CommitteePermission).filter(CommitteePermission.committee_member_id == cm.id).first()
    assigned_user = db.query(User).filter(User.id == cm.assigned_by).first() if cm.assigned_by else None

    permissions_list = []
    if perms:
        for api_name, db_field in PERMISSION_MAP.items():
            if getattr(perms, db_field, False):
                permissions_list.append(api_name)

    return {
        "id": str(cm.id), "event_id": str(cm.event_id),
        "user_id": str(cm.user_id) if cm.user_id else None,
        "name": f"{member_user.first_name} {member_user.last_name}" if member_user else "Invited Member",
        "email": member_user.email if member_user else (cm.invited_email if hasattr(cm, 'invited_email') else None),
        "phone": member_user.phone if member_user else None,
        "avatar": profile.profile_picture_url if profile else None,
        "role": role.role_name if role else None,
        "role_description": role.description if role else None,
        "permissions": permissions_list,
        "status": "active" if cm.user_id else "invited",
        "assigned_by": {"id": str(assigned_user.id), "name": f"{assigned_user.first_name} {assigned_user.last_name}"} if assigned_user else None,
        "assigned_at": cm.assigned_at.isoformat() if cm.assigned_at else None,
        "created_at": cm.created_at.isoformat() if cm.created_at else None,
    }


@router.get("/{event_id}/committee")
def get_committee_members(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    members = db.query(EventCommitteeMember).filter(EventCommitteeMember.event_id == eid).all()
    from utils.batch_loaders import build_committee_member_dicts
    return standard_response(True, "Committee members retrieved successfully", build_committee_member_dicts(db, members, PERMISSION_MAP))


@router.post("/{event_id}/committee")
def add_committee_member(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")
    if str(event.organizer_id) != str(current_user.id):
        return standard_response(False, "Only the event organizer can add committee members")

    role_name = body.get("role", "").strip()
    if not role_name:
        return standard_response(False, "Role is required")

    email = body.get("email")
    user_id_str = body.get("user_id")
    now = datetime.now(EAT)

    role = db.query(CommitteeRole).filter(CommitteeRole.role_name == role_name).first()
    if not role:
        role = CommitteeRole(id=uuid.uuid4(), role_name=role_name, description=body.get("role_description", role_name), created_at=now, updated_at=now)
        db.add(role)

    # Resolve user: prefer user_id, fallback to email lookup
    member_user = None
    if user_id_str:
        try:
            member_user = db.query(User).filter(User.id == uuid.UUID(user_id_str)).first()
        except ValueError:
            pass
    if not member_user and email:
        member_user = db.query(User).filter(sa_func.lower(User.email) == email.strip().lower()).first()

    if not member_user:
        return standard_response(False, "User not found. Please search and select a valid platform user.")

    # Check duplicate
    existing = db.query(EventCommitteeMember).filter(
        EventCommitteeMember.event_id == eid,
        EventCommitteeMember.user_id == member_user.id,
    ).first()
    if existing:
        return standard_response(False, "This user is already a committee member for this event")

    cm = EventCommitteeMember(id=uuid.uuid4(), event_id=eid, user_id=member_user.id, role_id=role.id, assigned_by=current_user.id, assigned_at=now, created_at=now, updated_at=now)
    db.add(cm)
    db.flush()

    perms = CommitteePermission(id=uuid.uuid4(), committee_member_id=cm.id, created_at=now, updated_at=now)
    for perm_name in body.get("permissions", []):
        db_field = PERMISSION_MAP.get(perm_name)
        if db_field and hasattr(perms, db_field):
            setattr(perms, db_field, True)
    # Auto-grant view when manage is granted
    if perms.can_manage_contributions:
        perms.can_view_contributions = True
    if perms.can_manage_budget:
        perms.can_view_budget = True
    if perms.can_manage_guests:
        perms.can_view_guests = True
    if perms.can_manage_vendors:
        perms.can_view_vendors = True
    db.add(perms)

    try:
        db.commit()
    except Exception as e:
        db.rollback()
        return standard_response(False, f"Failed to add committee member: {str(e)}")

    # Create notification + send SMS for the committee member
    if member_user and member_user.id != current_user.id:
        try:
            from utils.notify import notify_committee_invite
            notify_committee_invite(db, member_user.id, current_user.id, eid, event.name, role_name)
            db.commit()
        except Exception:
            pass
        # SMS to committee member (include custom message if provided)
        from utils.event_owner import get_event_owner_display_name
        organizer_name = get_event_owner_display_name(
            event, db=db,
            fallback=f"{current_user.first_name} {current_user.last_name}".strip(),
        )
        custom_msg = (body.get("invitation_message") or "").strip()
        sms_committee_invite(member_user.phone, f"{member_user.first_name}", event.name, role_name, organizer_name, custom_message=custom_msg)

    return standard_response(True, "Committee member added successfully", _member_dict(db, cm))


@router.put("/{event_id}/committee/{member_id}")
def update_committee_member(event_id: str, member_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        mid = uuid.UUID(member_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")
    if str(event.organizer_id) != str(current_user.id):
        return standard_response(False, "Only the event organizer can update committee members")

    cm = db.query(EventCommitteeMember).filter(EventCommitteeMember.id == mid, EventCommitteeMember.event_id == eid).first()
    if not cm:
        return standard_response(False, "Committee member not found")

    now = datetime.now(EAT)

    if "role" in body:
        role_name = body["role"].strip()
        role = db.query(CommitteeRole).filter(CommitteeRole.role_name == role_name).first()
        if not role:
            role = CommitteeRole(id=uuid.uuid4(), role_name=role_name, description=body.get("role_description", role_name), created_at=now, updated_at=now)
            db.add(role)
        cm.role_id = role.id

    if "permissions" in body:
        perms = db.query(CommitteePermission).filter(CommitteePermission.committee_member_id == cm.id).first()
        if not perms:
            perms = CommitteePermission(id=uuid.uuid4(), committee_member_id=cm.id, created_at=now, updated_at=now)
            db.add(perms)
        for field in PERMISSION_FIELDS:
            setattr(perms, field, False)
        for perm_name in body["permissions"]:
            db_field = PERMISSION_MAP.get(perm_name)
            if db_field and hasattr(perms, db_field):
                setattr(perms, db_field, True)
        # Auto-grant view when manage is granted
        if perms.can_manage_contributions:
            perms.can_view_contributions = True
        if perms.can_manage_budget:
            perms.can_view_budget = True
        if perms.can_manage_guests:
            perms.can_view_guests = True
        if perms.can_manage_vendors:
            perms.can_view_vendors = True
        perms.updated_at = now

    cm.updated_at = now
    db.commit()
    return standard_response(True, "Committee member updated successfully", _member_dict(db, cm))


@router.delete("/{event_id}/committee/{member_id}")
def remove_committee_member(event_id: str, member_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        mid = uuid.UUID(member_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")
    if str(event.organizer_id) != str(current_user.id):
        return standard_response(False, "Only the event organizer can remove committee members")

    cm = db.query(EventCommitteeMember).filter(EventCommitteeMember.id == mid, EventCommitteeMember.event_id == eid).first()
    if not cm:
        return standard_response(False, "Committee member not found")

    # Delete associated permissions first to avoid NOT NULL violation
    db.query(CommitteePermission).filter(CommitteePermission.committee_member_id == mid).delete()
    db.delete(cm)
    db.commit()
    return standard_response(True, "Committee member removed successfully")


@router.put("/{event_id}/committee/{member_id}/permissions")
def update_committee_permissions(event_id: str, member_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        mid = uuid.UUID(member_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event or str(event.organizer_id) != str(current_user.id):
        return standard_response(False, "Not authorized")

    cm = db.query(EventCommitteeMember).filter(EventCommitteeMember.id == mid, EventCommitteeMember.event_id == eid).first()
    if not cm:
        return standard_response(False, "Committee member not found")

    now = datetime.now(EAT)
    perms = db.query(CommitteePermission).filter(CommitteePermission.committee_member_id == cm.id).first()
    if not perms:
        perms = CommitteePermission(id=uuid.uuid4(), committee_member_id=cm.id, created_at=now, updated_at=now)
        db.add(perms)

    for field in PERMISSION_FIELDS:
        setattr(perms, field, False)
    for perm_name in body.get("permissions", []):
        db_field = PERMISSION_MAP.get(perm_name)
        if db_field and hasattr(perms, db_field):
            setattr(perms, db_field, True)
    # Auto-grant view when manage is granted
    if perms.can_manage_contributions:
        perms.can_view_contributions = True
    if perms.can_manage_budget:
        perms.can_view_budget = True
    if perms.can_manage_guests:
        perms.can_view_guests = True
    if perms.can_manage_vendors:
        perms.can_view_vendors = True
    perms.updated_at = now

    db.commit()
    return standard_response(True, "Permissions updated successfully", _member_dict(db, cm))


# ──────────────────────────────────────────────
# CONTRIBUTIONS MANAGEMENT
# ──────────────────────────────────────────────

def _contribution_dict(db: Session, c: EventContribution, currency_id) -> dict:
    # Get the contributor user via relationships
    contributor_user = None
    if c.event_contributor and c.event_contributor.contributor:
        contributor_user = c.event_contributor.contributor.user

    contact = c.contributor_contact or {}
    thank_you = db.query(ContributionThankYouMessage).filter(
        ContributionThankYouMessage.contribution_id == c.id
    ).first()

    return {
        "id": str(c.id),
        "event_id": str(c.event_id),
        "contributor_name": f"{contributor_user.first_name} {contributor_user.last_name}" 
                            if contributor_user else (c.contributor_name or "Anonymous"),
        "contributor_email": contributor_user.email if contributor_user else contact.get("email"),
        "contributor_phone": contributor_user.phone if contributor_user else contact.get("phone"),
        "contributor_user_id": str(contributor_user.id) if contributor_user else None,
        "amount": float(c.amount),
        "currency": _currency_code(db, currency_id),
        "payment_method": c.payment_method.value if hasattr(c.payment_method, "value") else c.payment_method,
        "payment_reference": c.transaction_ref,
        "status": "confirmed",
        "is_anonymous": contributor_user is None and (not c.contributor_name or c.contributor_name.lower() == "anonymous"),
        "thank_you_sent": thank_you.is_sent if thank_you else False,
        "created_at": c.created_at.isoformat() if c.created_at else None,
        "confirmed_at": c.contributed_at.isoformat() if c.contributed_at else None,
    }


@router.get("/{event_id}/contributions")
def get_contributions(event_id: str, page: int = 1, limit: int = 20, sort_by: str = "created_at", sort_order: str = "desc", db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    query = db.query(EventContribution).filter(EventContribution.event_id == eid)
    sort_col = EventContribution.amount if sort_by == "amount" else EventContribution.created_at
    query = query.order_by(sort_col.desc() if sort_order == "desc" else sort_col.asc())

    total = query.count()
    total_pages = max(1, math.ceil(total / limit))
    contributions = query.offset((page - 1) * limit).limit(limit).all()

    total_amount = db.query(sa_func.coalesce(sa_func.sum(EventContribution.amount), 0)).filter(
        EventContribution.event_id == eid,
        EventContribution.confirmation_status == "confirmed",
    ).scalar()
    ct = db.query(EventContributionTarget).filter(EventContributionTarget.event_id == eid).first()
    settings = db.query(EventSetting).filter(EventSetting.event_id == eid).first()
    target = float(ct.target_amount) if ct else (float(settings.contribution_target_amount) if settings and settings.contribution_target_amount else 0)

    return standard_response(True, "Contributions retrieved successfully", {
        "contributions": [_contribution_dict(db, c, event.currency_id) for c in contributions],
        "summary": {
            "total_amount": float(total_amount), "target_amount": target,
            "progress_percentage": round((float(total_amount) / target * 100), 1) if target > 0 else 0,
            "total_contributors": total, "currency": _currency_code(db, event.currency_id),
        },
        "pagination": {"page": page, "limit": limit, "total_items": total, "total_pages": total_pages, "has_next": page < total_pages, "has_previous": page > 1},
    })


@router.post("/{event_id}/contributions")
def record_contribution(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    amount = body.get("amount")
    if not amount or float(amount) <= 0:
        return standard_response(False, "Amount must be greater than 0")

    now = datetime.now(EAT)
    contributor_user_id = None
    if body.get("contributor_user_id"):
        try:
            contributor_user_id = uuid.UUID(body["contributor_user_id"])
        except ValueError:
            pass

    # Validate contributor phone if provided
    contributor_phone = body.get("contributor_phone")
    if contributor_phone:
        try:
            contributor_phone = validate_phone_number(contributor_phone)
        except ValueError as e:
            return standard_response(False, str(e))

    c = EventContribution(
        id=uuid.uuid4(), event_id=eid, contributor_user_id=contributor_user_id,
        contributor_name=body.get("contributor_name"), contributor_contact={"email": body.get("contributor_email"), "phone": contributor_phone},
        amount=float(amount), payment_method=body.get("payment_method", "mobile"),
        transaction_ref=body.get("transaction_reference"), contributed_at=now, created_at=now,
    )
    db.add(c)

    try:
        db.commit()
    except Exception as e:
        db.rollback()
        return standard_response(False, f"Failed to record contribution: {str(e)}")

    # Notify contributor + SMS
    currency = _currency_code(db, event.currency_id) or "TZS"
    if contributor_user_id:
        contributor_user = db.query(User).filter(User.id == contributor_user_id).first()
        if contributor_user:
            try:
                from utils.notify import notify_contribution
                notify_contribution(db, contributor_user.id, current_user.id, eid, event.name, float(amount), currency)
                db.commit()
            except Exception:
                pass
            # Calculate total paid for this contributor
            total_paid = float(db.query(sa_func.coalesce(sa_func.sum(EventContribution.amount), 0)).filter(
                EventContribution.event_id == eid,
                EventContribution.contributor_user_id == contributor_user_id,
                EventContribution.confirmation_status == "confirmed",
            ).scalar())
            ct = db.query(EventContributionTarget).filter(EventContributionTarget.event_id == eid).first()
            target = float(ct.target_amount) if ct else 0
            organizer_phone = format_phone_display(current_user.phone) if current_user.phone else None
            sms_contribution_recorded(contributor_user.phone, f"{contributor_user.first_name}", event.name, float(amount), target, total_paid, currency, organizer_phone=organizer_phone)

    return standard_response(True, "Contribution recorded successfully", _contribution_dict(db, c, event.currency_id))


@router.put("/{event_id}/contributions/{contribution_id}")
def update_contribution(event_id: str, contribution_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        cid = uuid.UUID(contribution_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    c = db.query(EventContribution).filter(EventContribution.id == cid, EventContribution.event_id == eid).first()
    if not c:
        return standard_response(False, "Contribution not found")

    if "amount" in body: c.amount = float(body["amount"])
    if "payment_method" in body: c.payment_method = body["payment_method"]
    if "transaction_reference" in body: c.transaction_ref = body["transaction_reference"]

    db.commit()

    event = db.query(Event).filter(Event.id == eid).first()
    return standard_response(True, "Contribution updated successfully", _contribution_dict(db, c, event.currency_id))


@router.delete("/{event_id}/contributions/{contribution_id}")
def delete_contribution(event_id: str, contribution_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        cid = uuid.UUID(contribution_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event or str(event.organizer_id) != str(current_user.id):
        return standard_response(False, "Not authorized")

    c = db.query(EventContribution).filter(EventContribution.id == cid, EventContribution.event_id == eid).first()
    if not c:
        return standard_response(False, "Contribution not found")

    db.delete(c)
    db.commit()
    return standard_response(True, "Contribution deleted successfully")


@router.get("/{event_id}/contributions/export")
def export_contributions(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    contributions = db.query(EventContribution).filter(EventContribution.event_id == eid).all()
    return standard_response(True, "Contributions exported", [_contribution_dict(db, c, event.currency_id) for c in contributions])


@router.post("/{event_id}/contributions/{contribution_id}/thank-you")
def send_thank_you(event_id: str, contribution_id: str, body: dict = Body(default={}), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        cid = uuid.UUID(contribution_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    c = db.query(EventContribution).filter(EventContribution.id == cid, EventContribution.event_id == eid).first()
    if not c:
        return standard_response(False, "Contribution not found")

    now = datetime.now(EAT)
    method = body.get("method", "email")
    msg = body.get("custom_message", "Thank you for your generous contribution!")

    thank_you = db.query(ContributionThankYouMessage).filter(ContributionThankYouMessage.contribution_id == cid).first()
    if not thank_you:
        thank_you = ContributionThankYouMessage(id=uuid.uuid4(), event_id=eid, contribution_id=cid, message=msg, sent_via=method, sent_at=now, is_sent=True, created_at=now)
        db.add(thank_you)
    else:
        thank_you.message = msg
        thank_you.sent_via = method
        thank_you.sent_at = now
        thank_you.is_sent = True

    db.commit()

    # Send thank-you SMS
    contributor_user = db.query(User).filter(User.id == c.contributor_user_id).first() if c.contributor_user_id else None
    if contributor_user and contributor_user.phone:
        event = db.query(Event).filter(Event.id == eid).first()
        organizer_phone = format_phone_display(current_user.phone) if current_user.phone else None
        sms_thank_you(contributor_user.phone, f"{contributor_user.first_name}", event.name if event else "your event", msg, organizer_phone=organizer_phone)

    return standard_response(True, "Thank you sent successfully", {"contribution_id": str(cid), "thank_you_sent": True, "sent_at": now.isoformat()})


@router.put("/{event_id}/contributions/target")
def update_contribution_target(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_contributions")
    if err:
        return err

    now = datetime.now(EAT)
    ct = db.query(EventContributionTarget).filter(EventContributionTarget.event_id == eid).first()
    if not ct:
        ct = EventContributionTarget(id=uuid.uuid4(), event_id=eid, created_at=now)
        db.add(ct)

    if "target_amount" in body: ct.target_amount = body["target_amount"]
    if "description" in body: ct.description = body["description"]
    ct.updated_at = now

    settings = db.query(EventSetting).filter(EventSetting.event_id == eid).first()
    if settings and "target_amount" in body:
        settings.contribution_target_amount = body["target_amount"]

    db.commit()

    # SMS all contributors about the new target
    if "target_amount" in body:
        target_val = float(body["target_amount"])
        currency = _currency_code(db, event.currency_id) or "TZS"
        contributors = db.query(EventContribution).filter(EventContribution.event_id == eid).all()
        notified_users = set()
        for contrib in contributors:
            uid = contrib.contributor_user_id
            if uid and uid not in notified_users:
                notified_users.add(uid)
                cuser = db.query(User).filter(User.id == uid).first()
                if cuser and cuser.phone:
                    total_paid = float(db.query(sa_func.coalesce(sa_func.sum(EventContribution.amount), 0)).filter(
                        EventContribution.event_id == eid,
                        EventContribution.contributor_user_id == uid,
                        EventContribution.confirmation_status == "confirmed",
                    ).scalar())
                    organizer_phone = format_phone_display(current_user.phone) if current_user.phone else None
                    sms_contribution_target_set(cuser.phone, f"{cuser.first_name}", event.name, target_val, total_paid, currency, organizer_phone=organizer_phone)

    return standard_response(True, "Contribution target updated successfully")


# ──────────────────────────────────────────────
# RECENT ACTIVITY (Event Management overview feed)
# ──────────────────────────────────────────────

@router.get("/{event_id}/recent-activity")
def get_recent_activity(event_id: str, limit: int = 10, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Returns a unified, time-ordered activity feed for the event management overview.
    Includes contributions (pledges/payments), ticket purchases, expenses, RSVPs, and service updates.
    """
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    items: list[dict] = []

    def _name_for_user(uid):
        if not uid:
            return None
        u = db.query(User).filter(User.id == uid).first()
        if not u:
            return None
        full = f"{u.first_name or ''} {u.last_name or ''}".strip()
        return full or u.username or None

    # Contributions — distinguish pledge vs payment using payment_method/status
    try:
        contribs = db.query(EventContribution).filter(EventContribution.event_id == eid).order_by(EventContribution.created_at.desc()).limit(limit).all()
        for c in contribs:
            status = (c.confirmation_status.value if hasattr(c.confirmation_status, 'value') else str(c.confirmation_status or '')).lower()
            is_payment = bool(c.payment_method) or status == 'confirmed'
            verb = 'paid' if is_payment else 'pledged'
            items.append({
                'type': 'contribution',
                'subtype': 'payment' if is_payment else 'pledge',
                'actor_name': c.contributor_name or 'A contributor',
                'title': f"{c.contributor_name or 'A contributor'} {verb}",
                'amount': float(c.amount or 0),
                'time': (c.created_at or c.contributed_at).isoformat() if (c.created_at or c.contributed_at) else None,
            })
    except Exception:
        pass

    # Ticket purchases
    try:
        tickets = db.query(EventTicket).filter(EventTicket.event_id == eid).order_by(EventTicket.created_at.desc()).limit(limit).all()
        for t in tickets:
            buyer = t.buyer_name or _name_for_user(t.buyer_user_id) or 'A guest'
            items.append({
                'type': 'ticket',
                'subtype': 'purchase',
                'actor_name': buyer,
                'title': f"{buyer} bought {t.quantity or 1} ticket(s)",
                'amount': float(t.total_amount or 0),
                'time': t.created_at.isoformat() if t.created_at else None,
            })
    except Exception:
        pass

    # Expenses
    try:
        expenses = db.query(EventExpense).filter(EventExpense.event_id == eid).order_by(EventExpense.created_at.desc()).limit(limit).all()
        for e in expenses:
            recorder = _name_for_user(e.recorded_by) or 'Organiser'
            items.append({
                'type': 'expense',
                'subtype': 'recorded',
                'actor_name': recorder,
                'title': f"{recorder} recorded expense: {e.description or e.category or 'Expense'}",
                'amount': float(e.amount or 0),
                'time': e.created_at.isoformat() if e.created_at else None,
            })
    except Exception:
        pass

    # RSVPs (confirmed)
    try:
        rsvps = db.query(EventAttendee).filter(EventAttendee.event_id == eid, EventAttendee.rsvp_status == RSVPStatusEnum.confirmed).order_by(EventAttendee.updated_at.desc()).limit(limit).all()
        for a in rsvps:
            who = a.guest_name or _name_for_user(a.attendee_id) or 'A guest'
            items.append({
                'type': 'rsvp',
                'subtype': 'confirmed',
                'actor_name': who,
                'title': f"{who} confirmed attendance",
                'amount': None,
                'time': (a.updated_at or a.created_at).isoformat() if (a.updated_at or a.created_at) else None,
            })
    except Exception:
        pass

    # Sort by time desc and trim
    items.sort(key=lambda x: x.get('time') or '', reverse=True)
    items = items[:limit]

    return standard_response(True, "Recent activity retrieved", {
        'items': items,
        'currency': _currency_code(db, event.currency_id) or 'TZS',
    })


# ──────────────────────────────────────────────
# SCHEDULE MANAGEMENT
# ──────────────────────────────────────────────

@router.get("/{event_id}/schedule")
def get_schedule(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    items = db.query(EventScheduleItem).filter(EventScheduleItem.event_id == eid).order_by(EventScheduleItem.display_order.asc()).all()
    return standard_response(True, "Schedule retrieved successfully", [{"id": str(si.id), "title": si.title, "description": si.description, "start_time": si.start_time.isoformat() if si.start_time else None, "end_time": si.end_time.isoformat() if si.end_time else None, "location": si.location, "display_order": si.display_order} for si in items])


@router.post("/{event_id}/schedule")
def add_schedule_item(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_edit_event")
    if err:
        return err

    now = datetime.now(EAT)
    max_order = db.query(sa_func.max(EventScheduleItem.display_order)).filter(EventScheduleItem.event_id == eid).scalar() or 0

    start_time = end_time = None
    if body.get("start_time"):
        try:
            start_time = datetime.fromisoformat(body["start_time"].replace("Z", "+00:00"))
        except ValueError:
            pass
    if body.get("end_time"):
        try:
            end_time = datetime.fromisoformat(body["end_time"].replace("Z", "+00:00"))
        except ValueError:
            pass

    si = EventScheduleItem(id=uuid.uuid4(), event_id=eid, title=body.get("title", ""), description=body.get("description"), start_time=start_time, end_time=end_time, location=body.get("location"), display_order=max_order + 1, created_at=now, updated_at=now)
    db.add(si)
    db.commit()

    return standard_response(True, "Schedule item added successfully", {"id": str(si.id), "title": si.title, "display_order": si.display_order})


@router.put("/{event_id}/schedule/{item_id}")
def update_schedule_item(event_id: str, item_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        iid = uuid.UUID(item_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_edit_event")
    if err:
        return err

    si = db.query(EventScheduleItem).filter(EventScheduleItem.id == iid, EventScheduleItem.event_id == eid).first()
    if not si:
        return standard_response(False, "Schedule item not found")

    if "title" in body: si.title = body["title"]
    if "description" in body: si.description = body["description"]
    if "location" in body: si.location = body["location"]
    if "start_time" in body:
        try:
            si.start_time = datetime.fromisoformat(body["start_time"].replace("Z", "+00:00"))
        except ValueError:
            pass
    if "end_time" in body:
        try:
            si.end_time = datetime.fromisoformat(body["end_time"].replace("Z", "+00:00"))
        except ValueError:
            pass
    si.updated_at = datetime.now(EAT)
    db.commit()

    return standard_response(True, "Schedule item updated successfully")


@router.delete("/{event_id}/schedule/{item_id}")
def delete_schedule_item(event_id: str, item_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        iid = uuid.UUID(item_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_edit_event")
    if err:
        return err

    si = db.query(EventScheduleItem).filter(EventScheduleItem.id == iid, EventScheduleItem.event_id == eid).first()
    if not si:
        return standard_response(False, "Schedule item not found")

    db.delete(si)
    db.commit()
    return standard_response(True, "Schedule item deleted successfully")


@router.put("/{event_id}/schedule/reorder")
def reorder_schedule(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_edit_event")
    if err:
        return err

    order = body.get("order", [])
    for i, item_id in enumerate(order):
        try:
            si = db.query(EventScheduleItem).filter(EventScheduleItem.id == uuid.UUID(item_id), EventScheduleItem.event_id == eid).first()
            if si:
                si.display_order = i + 1
        except ValueError:
            continue

    db.commit()
    return standard_response(True, "Schedule reordered successfully")


# ──────────────────────────────────────────────
# BUDGET MANAGEMENT
# ──────────────────────────────────────────────

@router.get("/{event_id}/budget")
def get_budget(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_view_budget")
    if err:
        return err

    items = db.query(EventBudgetItem).filter(EventBudgetItem.event_id == eid).order_by(EventBudgetItem.category, EventBudgetItem.item_name).all()
    total_estimated = sum(float(bi.estimated_cost) for bi in items if bi.estimated_cost)
    total_actual = sum(float(bi.actual_cost) for bi in items if bi.actual_cost)

    return standard_response(True, "Budget retrieved successfully", {
        "items": [{"id": str(bi.id), "category": bi.category, "item_name": bi.item_name, "estimated_cost": float(bi.estimated_cost) if bi.estimated_cost else None, "actual_cost": float(bi.actual_cost) if bi.actual_cost else None, "vendor_name": bi.vendor_name, "vendor_id": str(bi.vendor_id) if bi.vendor_id else None, "vendor": _vendor_summary(bi.vendor) if bi.vendor_id else None, "status": bi.status, "notes": bi.notes, "created_at": bi.created_at.isoformat() if bi.created_at else None} for bi in items],
        "summary": {"total_estimated": total_estimated, "total_actual": total_actual, "variance": total_estimated - total_actual, "currency": "TZS"},
    })


@router.post("/{event_id}/budget")
def add_budget_item(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_budget")
    if err:
        return err

    now = datetime.now(EAT)
    bi = EventBudgetItem(id=uuid.uuid4(), event_id=eid, category=body.get("category"), item_name=body.get("item_name", ""), estimated_cost=body.get("estimated_cost"), actual_cost=body.get("actual_cost"), vendor_name=body.get("vendor_name"), vendor_id=body.get("vendor_id") or None, status=body.get("status", "pending"), notes=body.get("notes"), created_at=now, updated_at=now)
    db.add(bi)
    db.commit()

    return standard_response(True, "Budget item added successfully", {"id": str(bi.id)})


@router.put("/{event_id}/budget/{item_id}")
def update_budget_item(event_id: str, item_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        iid = uuid.UUID(item_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_budget")
    if err:
        return err

    bi = db.query(EventBudgetItem).filter(EventBudgetItem.id == iid, EventBudgetItem.event_id == eid).first()
    if not bi:
        return standard_response(False, "Budget item not found")

    for field in ["category", "item_name", "vendor_name", "status", "notes"]:
        if field in body: setattr(bi, field, body[field])
    if "estimated_cost" in body: bi.estimated_cost = body["estimated_cost"]
    if "actual_cost" in body: bi.actual_cost = body["actual_cost"]
    if "vendor_id" in body: bi.vendor_id = body["vendor_id"] or None
    bi.updated_at = datetime.now(EAT)
    db.commit()

    return standard_response(True, "Budget item updated successfully")


@router.delete("/{event_id}/budget/{item_id}")
def delete_budget_item(event_id: str, item_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        iid = uuid.UUID(item_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_budget")
    if err:
        return err

    bi = db.query(EventBudgetItem).filter(EventBudgetItem.id == iid, EventBudgetItem.event_id == eid).first()
    if not bi:
        return standard_response(False, "Budget item not found")

    db.delete(bi)
    db.commit()
    return standard_response(True, "Budget item deleted successfully")


# ──────────────────────────────────────────────
# EVENT SERVICES (Vendor Bookings)
# ──────────────────────────────────────────────

def _service_booking_dict(db: Session, es: EventService, currency_id) -> dict:
    from models import UserServiceImage
    svc_type = db.query(ServiceType).filter(ServiceType.id == es.service_id).first()
    provider_svc = db.query(UserService).filter(UserService.id == es.provider_user_service_id).first() if es.provider_user_service_id else None
    provider_user = db.query(User).filter(User.id == es.provider_user_id).first() if es.provider_user_id else None

    # Get service image
    service_image = None
    if provider_svc:
        featured_img = db.query(UserServiceImage).filter(
            UserServiceImage.user_service_id == provider_svc.id,
            UserServiceImage.is_featured == True,
        ).first()
        if featured_img:
            service_image = featured_img.image_url
        elif provider_svc.images:
            service_image = provider_svc.images[0].image_url if provider_svc.images else None

    return {
        "id": str(es.id), "event_id": str(es.event_id), "service_id": str(es.service_id),
        "provider_user_id": str(es.provider_user_id) if es.provider_user_id else None,
        "provider_user_service_id": str(es.provider_user_service_id) if es.provider_user_service_id else None,
        "service": {
            "title": provider_svc.title if provider_svc else (svc_type.name if svc_type else None),
            "category": svc_type.category.name if svc_type and hasattr(svc_type, "category") and svc_type.category else None,
            "provider_name": f"{provider_user.first_name} {provider_user.last_name}" if provider_user else None,
            "image": service_image,
            "verification_status": provider_svc.verification_status.value if provider_svc and hasattr(provider_svc.verification_status, "value") else (str(provider_svc.verification_status) if provider_svc and provider_svc.verification_status else "unverified"),
            "verified": provider_svc.is_verified if provider_svc else False,
        },
        "quoted_price": float(es.agreed_price) if es.agreed_price else None,
        "currency": _currency_code(db, currency_id),
        "status": es.service_status.value if hasattr(es.service_status, "value") else es.service_status,
        "notes": es.notes,
        "created_at": es.created_at.isoformat() if es.created_at else None,
    }


@router.get("/{event_id}/services")
def get_event_services(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_view_vendors")
    if err:
        return err

    services = db.query(EventService).filter(EventService.event_id == eid).all()
    from utils.batch_loaders import build_event_service_dicts
    return standard_response(True, "Event services retrieved successfully", build_event_service_dicts(db, services, _currency_code(db, event.currency_id)))


@router.post("/{event_id}/services")
def add_event_service(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_vendors")
    if err:
        return err

    now = datetime.now(EAT)

    # Resolve service_id from the provider's user service
    service_id_val = None
    if body.get("service_id"):
        service_id_val = uuid.UUID(body["service_id"])
    elif body.get("provider_service_id"):
        provider_svc = db.query(UserService).filter(UserService.id == uuid.UUID(body["provider_service_id"])).first()
        if provider_svc and provider_svc.service_type_id:
            service_id_val = provider_svc.service_type_id

    # Also create a booking request so it shows in vendor's incoming bookings
    provider_service_id = uuid.UUID(body["provider_service_id"]) if body.get("provider_service_id") else None
    provider_user_id_val = uuid.UUID(body["provider_user_id"]) if body.get("provider_user_id") else None

    # Check for duplicate: skip if this provider service is already assigned to this event
    if provider_service_id:
        existing = db.query(EventService).filter(
            EventService.event_id == eid,
            EventService.provider_user_service_id == provider_service_id,
        ).first()
        if existing:
            return standard_response(True, "Service provider already assigned to this event", _service_booking_dict(db, existing, event.currency_id))

    es = EventService(
        id=uuid.uuid4(), event_id=eid,
        service_id=service_id_val,
        provider_user_service_id=provider_service_id,
        provider_user_id=provider_user_id_val,
        agreed_price=body.get("quoted_price"),
        service_status=EventServiceStatusEnum.pending,
        notes=body.get("notes"),
        created_at=now, updated_at=now,
    )
    db.add(es)

    # Create a ServiceBookingRequest entry for bookings page
    if provider_service_id:
        from models import ServiceBookingRequest
        booking_req = ServiceBookingRequest(
            id=uuid.uuid4(),
            user_service_id=provider_service_id,
            requester_user_id=current_user.id,
            event_id=eid,
            message=body.get("notes") or f"Service requested for {event.name}",
            proposed_price=body.get("quoted_price"),
            status="pending",
            created_at=now, updated_at=now,
        )
        db.add(booking_req)

    db.commit()

    # Notify & SMS the service provider
    if body.get("provider_user_id"):
        try:
            provider_user = db.query(User).filter(User.id == uuid.UUID(body["provider_user_id"])).first()
            if provider_user and provider_user.id != current_user.id:
                from utils.notify import notify_booking
                provider_svc = db.query(UserService).filter(UserService.id == es.provider_user_service_id).first() if es.provider_user_service_id else None
                service_name = provider_svc.title if provider_svc else "service"
                notify_booking(db, provider_user.id, current_user.id, eid, event.name, service_name)
                db.commit()
                from utils.event_owner import get_event_owner_display_name
                organizer_name = get_event_owner_display_name(
                    event, db=db,
                    fallback=f"{current_user.first_name} {current_user.last_name}".strip(),
                )
                from utils.message_templates import resolve_user_language
                lang = resolve_user_language(db, provider_user.id)
                if provider_user.phone:
                    try:
                        from utils.whatsapp import wa_booking_notification
                        try:
                            from utils.wa_logging import set_wa_log_context
                            set_wa_log_context(event_id=str(event.id), event_name=event.name,
                                               source_module="event_services", purpose="booking_request",
                                               recipient_type="vendor")
                        except Exception: pass
                        wa_booking_notification(provider_user.phone, provider_user.first_name, event.name, organizer_name, service_name, lang=lang)
                    except Exception:
                        pass
                sms_booking_notification(provider_user.phone, f"{provider_user.first_name}", event.name, organizer_name, service_name, lang=lang)
        except Exception:
            pass

    return standard_response(True, "Service added to event successfully", _service_booking_dict(db, es, event.currency_id))


@router.put("/{event_id}/services/{service_id}")
def update_event_service(event_id: str, service_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        sid = uuid.UUID(service_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_vendors")
    if err:
        return err

    es = db.query(EventService).filter(EventService.id == sid, EventService.event_id == eid).first()
    if not es:
        return standard_response(False, "Event service not found")

    # Service status is system-driven (booking acceptance, delivery OTP, cancellation).
    # Organisers/vendors cannot change it directly here — silently ignore any attempts.
    if "quoted_price" in body: es.agreed_price = body["quoted_price"]
    if "notes" in body: es.notes = body["notes"]
    es.updated_at = datetime.now(EAT)
    db.commit()

    return standard_response(True, "Event service updated successfully")


@router.delete("/{event_id}/services/{service_id}")
def remove_event_service(event_id: str, service_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        sid = uuid.UUID(service_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_vendors")
    if err:
        return err

    es = db.query(EventService).filter(EventService.id == sid, EventService.event_id == eid).first()
    if not es:
        return standard_response(False, "Event service not found")

    db.delete(es)
    db.commit()
    return standard_response(True, "Event service removed successfully")


@router.post("/{event_id}/services/{service_id}/payment")
def record_service_payment(event_id: str, service_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        sid = uuid.UUID(service_id)
    except ValueError:
        return standard_response(False, "Invalid ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_approve_bookings")
    if err:
        return err

    es = db.query(EventService).filter(EventService.id == sid, EventService.event_id == eid).first()
    if not es:
        return standard_response(False, "Event service not found")

    now = datetime.now(EAT)
    payment = EventServicePayment(
        id=uuid.uuid4(), event_service_id=es.id,
        amount=body.get("amount"), payment_method=body.get("payment_method", "mobile"),
        transaction_ref=body.get("transaction_reference"),
        paid_at=now, created_at=now,
    )
    db.add(payment)
    db.commit()

    return standard_response(True, "Payment recorded successfully", {"id": str(payment.id), "amount": float(payment.amount) if payment.amount else None})


# ──────────────────────────────────────────────
# RSVP Respond (Authenticated – for invited users)
# ──────────────────────────────────────────────
@router.put("/invited/{event_id}/rsvp")
def respond_to_invitation(
    event_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Allows an invited user to accept/decline an event invitation."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format")

    rsvp_status = body.get("rsvp_status")
    valid_statuses = {"confirmed", "declined", "pending"}
    if rsvp_status not in valid_statuses:
        return standard_response(False, f"Invalid rsvp_status. Must be one of: {', '.join(valid_statuses)}")

    # Find the invitation
    invitation = db.query(EventInvitation).filter(
        EventInvitation.event_id == eid,
        EventInvitation.invited_user_id == current_user.id,
    ).first()

    if not invitation:
        # Also check if user is an attendee without an invitation record
        attendee = db.query(EventAttendee).filter(
            EventAttendee.event_id == eid,
            EventAttendee.attendee_id == current_user.id,
        ).first()
        if not attendee:
            return standard_response(False, "You do not have an invitation for this event")

        # Update attendee directly
        attendee.rsvp_status = RSVPStatusEnum(rsvp_status)
        attendee.updated_at = datetime.now(EAT)
        db.commit()

        return standard_response(True, "RSVP updated successfully", {
            "event_id": str(eid),
            "rsvp_status": rsvp_status,
            "rsvp_at": attendee.updated_at.isoformat(),
        })

    # Update invitation
    invitation.rsvp_status = RSVPStatusEnum(rsvp_status)
    invitation.rsvp_at = datetime.now(EAT)
    invitation.updated_at = datetime.now(EAT)

    # Update or create attendee record
    attendee = db.query(EventAttendee).filter(
        EventAttendee.event_id == eid,
        EventAttendee.attendee_id == current_user.id,
    ).first()

    now = datetime.now(EAT)
    if attendee:
        attendee.rsvp_status = RSVPStatusEnum(rsvp_status)
        attendee.updated_at = now
    else:
        attendee = EventAttendee(
            id=uuid.uuid4(),
            event_id=eid,
            attendee_id=current_user.id,
            invitation_id=invitation.id,
            rsvp_status=RSVPStatusEnum(rsvp_status),
            created_at=now,
            updated_at=now,
        )
        db.add(attendee)

    # Update meal/dietary if provided
    if body.get("meal_preference"):
        attendee.meal_preference = body["meal_preference"]
    if body.get("dietary_restrictions"):
        attendee.dietary_restrictions = body["dietary_restrictions"]
    if body.get("special_requests"):
        attendee.special_requests = body["special_requests"]

    db.commit()

    return standard_response(True, "RSVP updated successfully", {
        "event_id": str(eid),
        "rsvp_status": rsvp_status,
        "rsvp_at": invitation.rsvp_at.isoformat(),
        "attendee_id": str(attendee.id),
    })

# ──────────────────────────────────────────────
# Bulk member import (committee + guests) — CSV / XLSX
# Triggered from EventCommittee + EventGuestList "Import from file"
# action. Parses the upload synchronously into a row payload, persists a
# MemberImportJob, and queues the Celery worker for the heavy lifting so
# the request returns immediately.
# ──────────────────────────────────────────────

def _parse_member_upload(
    file_bytes: bytes,
    filename: str,
    mode: str,
) -> tuple[list[dict], list[dict]]:
    """Returns (rows, parse_errors). Accepts CSV.

    XLSX is converted to CSV in the browser before upload (see
    MemberImportDialog.tsx), so this parser only needs to handle CSV.

    Expected columns (case-insensitive, in order or by header):
      committee → s/n, full name, phone
      guests    → s/n, full name, phone, common name
    """
    def _norm_header(h: str) -> str:
        return (h or "").strip().lower().replace("/", "").replace("_", " ").replace("-", " ").strip()

    raw_rows: list[list[str]] = []
    try:
        import csv
        from io import StringIO
        text = file_bytes.decode("utf-8-sig", errors="replace")
        reader = csv.reader(StringIO(text))
        for row in reader:
            raw_rows.append([("" if c is None else str(c)) for c in row])
    except Exception as e:
        return ([], [{"row": 0, "message": f"Could not read CSV file: {e}"}])

    if not raw_rows:
        return ([], [{"row": 0, "message": "File is empty"}])

    header = [_norm_header(c) for c in raw_rows[0]]
    has_header = any(h in header for h in ("full name", "phone", "name", "common name"))
    start_idx = 1 if has_header else 0

    # Column resolution — by header name if available, else by position.
    def _col(row: list[str], names: list[str], pos: int) -> str:
        if has_header:
            for n in names:
                if n in header:
                    i = header.index(n)
                    return row[i] if i < len(row) else ""
        return row[pos] if pos < len(row) else ""

    rows: list[dict] = []
    parse_errors: list[dict] = []
    for i in range(start_idx, len(raw_rows)):
        cells = raw_rows[i]
        if not any((c or "").strip() for c in cells):
            continue
        row_num = i + 1
        full_name = _col(cells, ["full name", "name"], 1).strip()
        phone = _col(cells, ["phone", "phone number", "mobile"], 2).strip()
        item = {"_row": row_num, "full_name": full_name, "phone": phone}
        if mode == "guests":
            item["common_name"] = _col(cells, ["common name", "card name", "display name"], 3).strip()
        rows.append(item)

    return (rows, parse_errors)


def _enqueue_member_import(
    db: Session,
    event_id: uuid.UUID,
    current_user: User,
    mode: str,
    file: UploadFile,
    notify_sms: bool,
):
    from models import MemberImportJob

    try:
        contents = file.file.read()
    finally:
        try:
            file.file.close()
        except Exception:
            pass
    if not contents:
        return standard_response(False, "Uploaded file is empty")
    if len(contents) > 5 * 1024 * 1024:
        return standard_response(False, "File is too large (max 5 MB)")

    rows, parse_errors = _parse_member_upload(contents, file.filename or "", mode)
    if not rows:
        msg = parse_errors[0]["message"] if parse_errors else "No data rows found in file"
        return standard_response(False, msg)

    job = MemberImportJob(
        id=uuid.uuid4(),
        event_id=event_id,
        created_by=current_user.id,
        mode=mode,
        status="queued",
        notify_sms=bool(notify_sms),
        total_rows=len(rows),
        payload={"rows": rows, "filename": file.filename, "parse_errors": parse_errors},
        errors=list(parse_errors),
    )
    db.add(job)
    db.commit()
    db.refresh(job)

    try:
        from tasks.member_imports import process_member_import_job
        process_member_import_job.delay(str(job.id))
    except Exception as e:
        # Celery / Redis not reachable (e.g. local Windows dev box without a
        # worker running). Fall back to a background thread so the import
        # still completes without requiring the broker.
        print(f"[member_import] celery enqueue failed, running inline: {e}")
        try:
            import threading
            from tasks.member_imports import process_member_import_job as _proc
            job_id_str = str(job.id)
            def _run_inline():
                try:
                    # Celery task is callable directly — bypasses the broker.
                    _proc.run(job_id_str)  # type: ignore[attr-defined]
                except Exception as inner:
                    print(f"[member_import] inline run failed: {inner}")
            threading.Thread(target=_run_inline, daemon=True).start()
        except Exception as e2:
            print(f"[member_import] inline fallback failed too: {e2}")

    return standard_response(True, "Import queued", {
        "job_id": str(job.id),
        "status": job.status,
        "total_rows": job.total_rows,
    })


@router.post("/{event_id}/committee/import")
def import_committee_members(
    event_id: str,
    file: UploadFile = File(...),
    notify_sms: bool = Form(False),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")
    if str(event.organizer_id) != str(current_user.id):
        return standard_response(False, "Only the event organizer can import committee members")

    return _enqueue_member_import(db, eid, current_user, "committee", file, notify_sms)


@router.post("/{event_id}/guests/import")
def import_guest_members(
    event_id: str,
    file: UploadFile = File(...),
    notify_sms: bool = Form(False),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID format.")

    event, err = _verify_event_access(db, eid, current_user, "can_manage_guests")
    if err:
        return err

    return _enqueue_member_import(db, eid, current_user, "guests", file, notify_sms)


@router.get("/{event_id}/imports/{job_id}")
def get_member_import_job(
    event_id: str,
    job_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from models import MemberImportJob
    try:
        eid = uuid.UUID(event_id)
        jid = uuid.UUID(job_id)
    except ValueError:
        return standard_response(False, "Invalid ID format")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")
    if str(event.organizer_id) != str(current_user.id):
        # Committee with view access can still poll their own queued imports.
        pass

    job = db.query(MemberImportJob).filter(MemberImportJob.id == jid, MemberImportJob.event_id == eid).first()
    if not job:
        return standard_response(False, "Import job not found")

    return standard_response(True, "OK", {
        "job_id": str(job.id),
        "mode": job.mode,
        "status": job.status,
        "notify_sms": job.notify_sms,
        "total_rows": job.total_rows,
        "processed_rows": job.processed_rows,
        "summary": {
            "total": job.total_rows,
            "successful": job.successful_rows,
            "reused": job.reused_rows,
            "duplicates": job.duplicate_rows,
            "invalid_phone": job.invalid_phone_rows,
            "failed": job.failed_rows,
        },
        "errors": (job.errors or [])[:200],
        "started_at": job.started_at.isoformat() if job.started_at else None,
        "finished_at": job.finished_at.isoformat() if job.finished_at else None,
    })
