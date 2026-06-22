# Bookings Routes - /bookings/...
# Handles booking management for clients and vendors

import uuid
from datetime import datetime

import pytz
from fastapi import APIRouter, Depends, Body
from sqlalchemy.orm import Session

from core.database import get_db
from models import ServiceBookingRequest, UserService, Event, User, EventService
from utils.auth import get_current_user
from utils.helpers import standard_response

EAT = pytz.timezone("Africa/Nairobi")
router = APIRouter(prefix="/bookings", tags=["Bookings"])


def _get_primary_image(service):
    """Get primary image for a service, checking images relation and cover_image."""
    if hasattr(service, 'images') and service.images:
        for img in service.images:
            if hasattr(img, 'is_featured') and img.is_featured:
                return img.image_url
        return service.images[0].image_url
    if hasattr(service, 'cover_image_url') and service.cover_image_url:
        return service.cover_image_url
    return None


def _user_avatar(user):
    """Get avatar URL from user profile."""
    if user and hasattr(user, 'profile') and user.profile:
        return user.profile.profile_picture_url
    return None


def _booking_dict(db, b):
    service = db.query(UserService).filter(UserService.id == b.user_service_id).first() if b.user_service_id else None
    requester = db.query(User).filter(User.id == b.requester_user_id).first() if b.requester_user_id else None
    # Vendor is the service owner
    vendor = None
    if service and service.user_id:
        vendor = db.query(User).filter(User.id == service.user_id).first()
    event = db.query(Event).filter(Event.id == b.event_id).first() if b.event_id else None

    # Build enriched service dict
    service_dict = None
    if service:
        service_dict = {
            "id": str(service.id),
            "title": service.title,
            "primary_image": _get_primary_image(service),
            "category": service.category.name if hasattr(service, 'category') and service.category else None,
        }

    # Build enriched client dict
    client_dict = None
    if requester:
        client_dict = {
            "id": str(requester.id),
            "name": f"{requester.first_name} {requester.last_name}",
            "avatar": _user_avatar(requester),
            "phone": requester.phone,
            "email": requester.email,
        }

    # Build enriched vendor dict
    vendor_dict = None
    if vendor:
        vendor_dict = {
            "id": str(vendor.id),
            "name": f"{vendor.first_name} {vendor.last_name}",
            "avatar": _user_avatar(vendor),
            "phone": vendor.phone,
            "email": vendor.email,
        }

    # Build enriched event dict
    event_dict = None
    if event:
        event_date_str = None
        if event.start_date:
            event_date_str = event.start_date.isoformat() if hasattr(event.start_date, 'isoformat') else str(event.start_date)
        event_dict = {
            "id": str(event.id),
            "title": event.name,
            "date": event_date_str,
            "start_time": event.start_time if hasattr(event, 'start_time') else None,
            "end_time": event.end_time if hasattr(event, 'end_time') else None,
            "location": event.location,
            "venue": event.venue if hasattr(event, 'venue') else None,
            "guest_count": event.expected_guests if hasattr(event, 'expected_guests') else None,
        }

    return {
        "id": str(b.id),
        "service": service_dict,
        "client": client_dict,
        "provider": vendor_dict,
        "event": event_dict,
        "event_name": event.name if event else None,
        "event_date": event_dict["date"] if event_dict else None,
        "event_type": None,
        "location": event.location if event else None,
        "venue": event.venue if event and hasattr(event, 'venue') else None,
        "guest_count": event.expected_guests if event and hasattr(event, 'expected_guests') else None,
        "status": b.status if isinstance(b.status, str) else (b.status.value if hasattr(b.status, "value") else b.status),
        "message": b.message,
        "proposed_price": float(b.proposed_price) if b.proposed_price else None,
        "quoted_price": float(b.quoted_price) if b.quoted_price else None,
        "deposit_required": float(b.deposit_required) if b.deposit_required else None,
        "deposit_paid": b.deposit_paid,
        "vendor_notes": b.vendor_notes,
        "created_at": b.created_at.isoformat() if b.created_at else None,
        "updated_at": b.updated_at.isoformat() if b.updated_at else None,
    }


def _filter_bookings_by_search(items, term):
    """Filter already-built booking dicts by search term across user-visible fields."""
    if not term:
        return items
    t = term.strip().lower()
    if not t:
        return items
    out = []
    for b in items:
        haystack_parts = [
            str(b.get("service_name") or ""),
            str(b.get("event_name") or ""),
            str(b.get("client_name") or ""),
            str(b.get("vendor_name") or ""),
            str(b.get("status") or ""),
            str(b.get("notes") or ""),
            str(b.get("vendor_notes") or ""),
        ]
        if t in " ".join(haystack_parts).lower():
            out.append(b)
    return out


def _booking_status_summary(db, base_query):
    """One grouped query → status counts for the KPI strip."""
    from sqlalchemy import func as sa_func
    rows = (
        base_query.with_entities(
            ServiceBookingRequest.status, sa_func.count(ServiceBookingRequest.id)
        ).group_by(ServiceBookingRequest.status).all()
    )
    counts = {"pending": 0, "accepted": 0, "rejected": 0, "completed": 0, "cancelled": 0}
    total = 0
    for st, n in rows:
        key = st.value if hasattr(st, "value") else str(st)
        counts[key] = int(n or 0)
        total += int(n or 0)
    counts["total"] = total
    return counts


def _apply_booking_search(query, term):
    """Push search into SQL via joins on service title, event name and message."""
    if not term or not term.strip():
        return query
    from sqlalchemy import or_, func as sa_func
    t = f"%{term.strip().lower()}%"
    return (
        query.outerjoin(UserService, UserService.id == ServiceBookingRequest.user_service_id)
        .outerjoin(Event, Event.id == ServiceBookingRequest.event_id)
        .filter(or_(
            sa_func.lower(UserService.title).like(t),
            sa_func.lower(Event.name).like(t),
            sa_func.lower(ServiceBookingRequest.message).like(t),
        ))
    )


@router.get("/")
def get_my_bookings(
    page: int = 1,
    limit: int = 20,
    status: str = None,
    search: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from utils.batch_loaders import build_booking_dicts
    base = db.query(ServiceBookingRequest).filter(
        ServiceBookingRequest.requester_user_id == current_user.id
    )
    summary = _booking_status_summary(db, base)

    q = _apply_booking_search(base, search)
    if status and status != "all":
        q = q.filter(ServiceBookingRequest.status == status)

    total = q.with_entities(ServiceBookingRequest.id).count()
    page = max(1, int(page or 1))
    limit = max(1, min(int(limit or 20), 100))
    rows = (
        q.order_by(ServiceBookingRequest.created_at.desc())
        .offset((page - 1) * limit).limit(limit).all()
    )
    items = build_booking_dicts(db, rows)
    total_pages = (total + limit - 1) // limit if limit else 1
    return standard_response(True, "Bookings retrieved successfully", {
        "bookings": items,
        "summary": summary,
        "pagination": {
            "page": page, "limit": limit, "total_items": total,
            "total_pages": total_pages, "has_next": page < total_pages, "has_previous": page > 1,
        },
    })


@router.get("/received")
def get_received_bookings(
    page: int = 1,
    limit: int = 20,
    status: str = None,
    search: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from utils.batch_loaders import build_booking_dicts
    from sqlalchemy import func as sa_func
    empty_summary = {"total": 0, "pending": 0, "accepted": 0, "rejected": 0, "completed": 0, "cancelled": 0, "total_earnings": 0}
    my_service_ids = [s.id for s in db.query(UserService.id).filter(UserService.user_id == current_user.id).all()]
    if not my_service_ids:
        return standard_response(True, "Received bookings retrieved successfully", {
            "bookings": [], "summary": empty_summary,
            "pagination": {"page": 1, "limit": limit, "total_items": 0, "total_pages": 0, "has_next": False, "has_previous": False},
        })

    base = db.query(ServiceBookingRequest).filter(
        ServiceBookingRequest.user_service_id.in_(my_service_ids)
    )
    summary = _booking_status_summary(db, base)
    # Earnings — single SQL aggregate over accepted/completed (no Python loop).
    earnings = db.query(
        sa_func.coalesce(sa_func.sum(sa_func.coalesce(
            ServiceBookingRequest.quoted_price, ServiceBookingRequest.proposed_price, 0
        )), 0)
    ).filter(
        ServiceBookingRequest.user_service_id.in_(my_service_ids),
        ServiceBookingRequest.status.in_(["accepted", "completed"]),
    ).scalar() or 0
    summary["total_earnings"] = float(earnings)

    q = _apply_booking_search(base, search)
    if status and status != "all":
        q = q.filter(ServiceBookingRequest.status == status)

    total = q.with_entities(ServiceBookingRequest.id).count()
    page = max(1, int(page or 1))
    limit = max(1, min(int(limit or 20), 100))
    rows = (
        q.order_by(ServiceBookingRequest.created_at.desc())
        .offset((page - 1) * limit).limit(limit).all()
    )
    items = build_booking_dicts(db, rows)
    total_pages = (total + limit - 1) // limit if limit else 1
    return standard_response(True, "Received bookings retrieved successfully", {
        "bookings": items,
        "summary": summary,
        "pagination": {
            "page": page, "limit": limit, "total_items": total,
            "total_pages": total_pages, "has_next": page < total_pages, "has_previous": page > 1,
        },
    })


@router.get("/{booking_id}")
def get_booking(booking_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")

    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid).first()
    if not b:
        return standard_response(False, "Booking not found")

    return standard_response(True, "Booking retrieved successfully", _booking_dict(db, b))


@router.put("/{booking_id}")
def update_booking(booking_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")

    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid).first()
    if not b:
        return standard_response(False, "Booking not found")

    if "message" in body: b.message = body["message"]
    if "budget" in body: b.budget = body["budget"]
    b.updated_at = datetime.now(EAT)
    db.commit()

    return standard_response(True, "Booking updated successfully", _booking_dict(db, b))


@router.get("/{booking_id}/refund-preview")
def refund_preview(
    booking_id: str,
    cancelling_party: str = "organiser",
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Preview the refund breakdown WITHOUT cancelling. Used by the
    'see your refund before confirming' modal on web + mobile."""
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")
    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid).first()
    if not b:
        return standard_response(False, "Booking not found")

    from services.cancellation_service import calculate
    breakdown = calculate(db, b, cancelling_party)
    return standard_response(True, "Refund preview", breakdown.to_dict())


@router.post("/{booking_id}/cancel")
def cancel_booking(booking_id: str, body: dict = Body(default={}), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")

    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid).first()
    if not b:
        return standard_response(False, "Booking not found")

    # Determine cancelling party (organiser = requester, vendor = service owner).
    cancelling_party = "organiser"
    if b.user_service_id:
        from models import UserService as _US
        svc = db.query(_US).filter(_US.id == b.user_service_id).first()
        if svc and str(svc.user_id) == str(current_user.id):
            cancelling_party = "vendor"

    # Compute the policy-driven refund (Phase 1.2).
    from services.cancellation_service import calculate
    from services import escrow_service as escrow
    from models import EscrowHold

    breakdown = calculate(db, b, cancelling_party)

    # Apply the refund to escrow if any funds are held.
    hold = db.query(EscrowHold).filter(EscrowHold.booking_id == b.id).first()
    if hold and breakdown.refund_to_organiser > 0:
        escrow.refund_to_organiser(
            db, b, float(breakdown.refund_to_organiser),
            reason=breakdown.reason_code,
            actor_id=current_user.id,
        )

    b.status = "cancelled"
    b.vendor_notes = body.get("reason") or b.vendor_notes
    b.updated_at = datetime.now(EAT)

    # Cascade to the linked EventService so the organiser's services tab reflects the cancellation.
    if b.event_id and b.user_service_id:
        try:
            from models.enums import EventServiceStatusEnum
            es = db.query(EventService).filter(
                EventService.event_id == b.event_id,
                EventService.provider_user_service_id == b.user_service_id,
            ).first()
            if es:
                es.service_status = EventServiceStatusEnum.cancelled
                es.updated_at = datetime.now(EAT)
        except Exception:
            pass

    db.commit()

    return standard_response(True, "Booking cancelled", {
        "booking_id": str(b.id),
        "status": "cancelled",
        "refund": breakdown.to_dict(),
    })


@router.post("/{booking_id}/respond")
def respond_to_booking(booking_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")

    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid).first()
    if not b:
        return standard_response(False, "Booking not found")

    # Verify current user owns the service
    service = db.query(UserService).filter(UserService.id == b.user_service_id).first()
    if not service or str(service.user_id) != str(current_user.id):
        return standard_response(False, "You are not authorized to respond to this booking")

    new_status = body.get("status")
    if new_status: b.status = new_status
    if "quoted_price" in body: b.quoted_price = body["quoted_price"]
    if "deposit_required" in body: b.deposit_required = body["deposit_required"]
    if "message" in body: b.vendor_notes = body["message"]
    if "reason" in body and new_status == "rejected": b.vendor_notes = body.get("reason", "")
    b.responded_at = datetime.now(EAT)
    b.updated_at = datetime.now(EAT)

    # Sync quoted_price → EventService.agreed_price so the calendar shows correct price
    if new_status == "accepted" and b.event_id and b.user_service_id:
        es = db.query(EventService).filter(
            EventService.event_id == b.event_id,
            EventService.provider_user_service_id == b.user_service_id
        ).first()
        if es:
            if b.quoted_price:
                es.agreed_price = b.quoted_price
            if new_status == "accepted":
                es.service_status = "assigned"
            es.updated_at = datetime.now(EAT)

    db.commit()

    # SMS & notification to event organizer
    if new_status in ("accepted", "rejected") and b.requester_user_id:
        try:
            requester = db.query(User).filter(User.id == b.requester_user_id).first()
            event = db.query(Event).filter(Event.id == b.event_id).first() if b.event_id else None
            event_name = event.name if event else "your event"
            service_name = service.title if service else "service"

            if new_status == "accepted":
                from utils.notify import notify_booking_accepted
                notify_booking_accepted(db, b.requester_user_id, current_user.id, b.event_id, event_name, service_name)
                db.commit()
                # Resolve recipient language once, share across WA + SMS
                from utils.message_templates import resolve_user_language
                lang = resolve_user_language(db, requester.id) if requester else "sw"
                # WhatsApp first
                if requester and requester.phone:
                    try:
                        from utils.whatsapp import wa_booking_accepted
                        try:
                            from utils.wa_logging import set_wa_log_context
                            set_wa_log_context(event_id=str(b.event_id) if b.event_id else None,
                                               event_name=event_name,
                                               source_module="bookings", purpose="booking_accepted",
                                               recipient_type="user",
                                               related_entity_type="booking",
                                               related_entity_id=str(b.id))
                        except Exception: pass
                        wa_booking_accepted(requester.phone, requester.first_name, f"{current_user.first_name} {current_user.last_name}", service_name, event_name, lang=lang)
                    except Exception:
                        pass
                # SMS fallback (catalogue-rendered in recipient's language)
                if requester and requester.phone:
                    from utils.sms import sms_booking_accepted
                    sms_booking_accepted(
                        requester.phone,
                        requester.first_name,
                        f"{current_user.first_name} {current_user.last_name}",
                        service_name,
                        event_name,
                        lang=lang,
                    )
            elif new_status == "rejected":
                from utils.notify import notify_booking_rejected
                notify_booking_rejected(db, b.requester_user_id, current_user.id, b.event_id, event_name, service_name)
                db.commit()
        except Exception:
            pass

    return standard_response(True, "Response recorded successfully", _booking_dict(db, b))


@router.post("/{booking_id}/accept-quote")
def accept_quote(booking_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")

    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid, ServiceBookingRequest.requester_user_id == current_user.id).first()
    if not b:
        return standard_response(False, "Booking not found")

    b.status = "accepted"
    b.updated_at = datetime.now(EAT)
    db.commit()
    return standard_response(True, "Quote accepted successfully")


@router.post("/{booking_id}/pay-deposit")
def pay_deposit(booking_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")

    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid).first()
    if not b:
        return standard_response(False, "Booking not found")

    # Logical escrow: record HOLD_DEPOSIT and flip booking to funds_secured.
    from services import escrow_service as escrow
    amount = body.get("amount") or float(b.deposit_required or 0)
    hold = escrow.record_deposit_paid(db, b, amount, actor_id=current_user.id)
    db.commit()
    return standard_response(True, "Deposit recorded — funds secured in escrow",
                             {"booking_id": str(b.id), "escrow": escrow.serialize_hold(hold, include_transactions=False)})


@router.post("/{booking_id}/complete")
def mark_booking_complete(booking_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")

    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid).first()
    if not b:
        return standard_response(False, "Booking not found")

    b.status = "completed"
    b.completed_at = datetime.now(EAT)
    b.updated_at = datetime.now(EAT)
    db.commit()
    return standard_response(True, "Booking marked as completed")


@router.post("/{booking_id}/request-payment")
def request_final_payment(booking_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")

    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid).first()
    if not b:
        return standard_response(False, "Booking not found")

    b.payment_requested = True
    b.updated_at = datetime.now(EAT)
    db.commit()
    return standard_response(True, "Payment request sent to client")


@router.post("/{booking_id}/pay-balance")
def pay_balance(booking_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        bid = uuid.UUID(booking_id)
    except ValueError:
        return standard_response(False, "Invalid booking ID")

    b = db.query(ServiceBookingRequest).filter(ServiceBookingRequest.id == bid).first()
    if not b:
        return standard_response(False, "Booking not found")

    from services import escrow_service as escrow
    amount = body.get("amount")
    hold = escrow.record_balance_paid(db, b, amount, actor_id=current_user.id)
    b.balance_paid = True
    db.commit()
    return standard_response(True, "Balance paid — fully held in escrow",
                             {"booking_id": str(b.id), "escrow": escrow.serialize_hold(hold, include_transactions=False)})
