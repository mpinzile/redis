"""Event Sponsors routes.

Lets organisers invite vendor services as event sponsors, vendors accept/reject
the request from their bookings page, and exposes a per-event aggregate used
by the event management overview.
"""
from uuid import UUID
from datetime import datetime
from fastapi import APIRouter, Depends, Body
from sqlalchemy import func as sa_func
from sqlalchemy.orm import Session

from core.database import get_db
from models import (
    Event, EventSponsor, UserService, User, UserProfile,
)
from utils.auth import get_current_user
from utils.helpers import standard_response

router = APIRouter(tags=["Event Sponsors"])


def _vendor_summary(db: Session, vendor: User | None) -> dict | None:
    if not vendor:
        return None
    profile = db.query(UserProfile).filter(UserProfile.user_id == vendor.id).first()
    full = " ".join(
        p for p in [getattr(vendor, "first_name", None), getattr(vendor, "last_name", None)] if p
    ).strip()
    return {
        "id": str(vendor.id),
        "name": full or vendor.username or None,
        "username": vendor.username,
        "avatar_url": getattr(profile, "avatar_url", None) if profile else None,
    }


def _service_summary(service: UserService | None) -> dict | None:
    if not service:
        return None
    img = None
    if service.images:
        first = service.images[0]
        img = getattr(first, "image_url", None)
    return {
        "id": str(service.id),
        "title": service.title,
        "image": img,
    }


def _sponsor_dict(db: Session, s: EventSponsor) -> dict:
    return {
        "id": str(s.id),
        "event_id": str(s.event_id),
        "user_service_id": str(s.user_service_id),
        "vendor_user_id": str(s.vendor_user_id),
        "invited_by_user_id": str(s.invited_by_user_id),
        "status": s.status,
        "message": s.message,
        "contribution_amount": float(s.contribution_amount) if s.contribution_amount is not None else None,
        "response_note": s.response_note,
        "responded_at": s.responded_at.isoformat() if s.responded_at else None,
        "created_at": s.created_at.isoformat() if s.created_at else None,
        "service": _service_summary(s.user_service),
        "vendor": _vendor_summary(db, s.vendor),
        "event": {
            "id": str(s.event.id),
            "title": s.event.name,
            "start_date": s.event.start_date.isoformat() if s.event.start_date else None,
        } if s.event else None,
    }


# ────────────────────────────────────────────────
# Organizer endpoints
# ────────────────────────────────────────────────
@router.get("/user-events/{event_id}/sponsors")
def list_event_sponsors(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        eid = UUID(event_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid event ID")
    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")
    from sqlalchemy import func as sa_func, case
    rows = db.query(EventSponsor).filter(EventSponsor.event_id == eid).order_by(EventSponsor.created_at.desc()).all()
    # Single aggregate query for the summary (no Python sum loops).
    summary_row = db.query(
        sa_func.count(EventSponsor.id).label("total"),
        sa_func.count(case((EventSponsor.status == "accepted", 1))).label("accepted"),
        sa_func.count(case((EventSponsor.status == "pending", 1))).label("pending"),
        sa_func.count(case((EventSponsor.status == "declined", 1))).label("declined"),
        sa_func.coalesce(
            sa_func.sum(case((EventSponsor.status == "accepted", EventSponsor.contribution_amount))), 0
        ).label("contribution_total"),
    ).filter(EventSponsor.event_id == eid).one()
    return standard_response(True, "Sponsors retrieved", {
        "items": [_sponsor_dict(db, r) for r in rows],
        "summary": {
            "total": int(summary_row.total or 0),
            "accepted": int(summary_row.accepted or 0),
            "pending": int(summary_row.pending or 0),
            "declined": int(summary_row.declined or 0),
            "contribution_total": float(summary_row.contribution_total or 0),
        },
    })


@router.post("/user-events/{event_id}/sponsors")
def invite_sponsor(
    event_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        eid = UUID(event_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid event ID")
    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")
    if event.organizer_id != current_user.id:
        return standard_response(False, "Only the organizer can invite sponsors")

    user_service_id = body.get("user_service_id")
    if not user_service_id:
        return standard_response(False, "user_service_id is required")
    try:
        sid = UUID(user_service_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid user_service_id")
    service = db.query(UserService).filter(UserService.id == sid).first()
    if not service:
        return standard_response(False, "Service not found")

    # Pre-insertion duplicate check
    existing = db.query(EventSponsor).filter(
        EventSponsor.event_id == eid,
        EventSponsor.user_service_id == sid,
        EventSponsor.status.in_(["pending", "accepted"]),
    ).first()
    if existing:
        return standard_response(False, "This service has already been invited", _sponsor_dict(db, existing))

    sponsor = EventSponsor(
        event_id=eid,
        user_service_id=sid,
        vendor_user_id=service.user_id,
        invited_by_user_id=current_user.id,
        status="pending",
        message=(body.get("message") or None),
        contribution_amount=body.get("contribution_amount"),
    )
    db.add(sponsor)
    db.commit()
    db.refresh(sponsor)
    return standard_response(True, "Sponsor invitation sent", _sponsor_dict(db, sponsor))


@router.delete("/user-events/{event_id}/sponsors/{sponsor_id}")
def cancel_sponsor(
    event_id: str,
    sponsor_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        eid = UUID(event_id); sid = UUID(sponsor_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid id")
    sponsor = db.query(EventSponsor).filter(EventSponsor.id == sid, EventSponsor.event_id == eid).first()
    if not sponsor:
        return standard_response(False, "Sponsor not found")
    event = db.query(Event).filter(Event.id == eid).first()
    if not event or event.organizer_id != current_user.id:
        return standard_response(False, "Only the organizer can cancel")
    db.delete(sponsor)
    db.commit()
    return standard_response(True, "Sponsor invitation removed")


# ────────────────────────────────────────────────
# Vendor endpoints
# ────────────────────────────────────────────────
@router.get("/sponsor-requests")
def my_sponsor_requests(
    status: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List sponsor requests addressed to services owned by the current user."""
    q = db.query(EventSponsor).filter(EventSponsor.vendor_user_id == current_user.id)
    if status:
        q = q.filter(EventSponsor.status == status)
    rows = q.order_by(EventSponsor.created_at.desc()).all()
    return standard_response(True, "Sponsor requests retrieved", {
        "items": [_sponsor_dict(db, r) for r in rows],
        "pending_count": sum(1 for r in rows if r.status == "pending"),
    })


@router.post("/sponsor-requests/{sponsor_id}/respond")
def respond_to_sponsor_request(
    sponsor_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        sid = UUID(sponsor_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid id")
    sponsor = db.query(EventSponsor).filter(EventSponsor.id == sid).first()
    if not sponsor:
        return standard_response(False, "Request not found")
    if sponsor.vendor_user_id != current_user.id:
        return standard_response(False, "Not allowed")
    action = (body.get("action") or "").lower()
    if action not in ("accept", "decline"):
        return standard_response(False, "action must be 'accept' or 'decline'")
    sponsor.status = "accepted" if action == "accept" else "declined"
    sponsor.response_note = body.get("response_note")
    if body.get("contribution_amount") is not None:
        sponsor.contribution_amount = body.get("contribution_amount")
    sponsor.responded_at = datetime.utcnow()
    db.commit()
    db.refresh(sponsor)
    return standard_response(True, f"Sponsor request {sponsor.status}", _sponsor_dict(db, sponsor))
