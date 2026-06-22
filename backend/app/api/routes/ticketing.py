import secrets
import traceback
from uuid import UUID
from datetime import datetime
from fastapi import APIRouter, Request, Depends
from sqlalchemy.orm import Session

from core.database import get_db
from models import (
    User, Event, EventTicketClass, EventTicket, EventImage,
    TicketStatusEnum, TicketOrderStatusEnum, PaymentStatusEnum,
    TicketApprovalStatusEnum,
)
from utils.auth import get_current_user, get_optional_user
from utils.helpers import standard_response


def _resolve_event_cover(event, db):
    """Resolve best cover image: cover_image_url → featured EventImage → first EventImage."""
    if event.cover_image_url:
        return event.cover_image_url
    img = db.query(EventImage).filter(
        EventImage.event_id == event.id
    ).order_by(EventImage.is_featured.desc(), EventImage.created_at.asc()).first()
    return img.image_url if img else None

router = APIRouter(prefix="/ticketing", tags=["Ticketing"])


# ──────────────────────────────────────────────
# Get ticket classes for an event (public)
# ──────────────────────────────────────────────
@router.get("/events/{event_id}/ticket-classes")
def get_ticket_classes(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_optional_user),
):
    """Get all ticket classes for a public ticketed event.

    The organizer of the event can also fetch ticket classes while approval
    is still pending, so they can preview their own listing.
    """
    try:
        eid = UUID(event_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(
        Event.id == eid, Event.sells_tickets == True,
    ).first()
    if not event:
        return standard_response(False, "Event not found or does not sell tickets")

    is_owner = bool(current_user and event.organizer_id == current_user.id)
    is_publicly_visible = (
        event.is_public is True
        and event.ticket_approval_status == TicketApprovalStatusEnum.approved
    )
    if not (is_owner or is_publicly_visible):
        return standard_response(False, "Event not found or does not sell tickets")

    classes = db.query(EventTicketClass).filter(
        EventTicketClass.event_id == eid
    ).order_by(EventTicketClass.display_order).all()

    from sqlalchemy import func as sa_func

    # Inline cleanup: hard-delete every expired reservation for this event so
    # stale unpaid holds never make a class look sold out. Safe + idempotent.
    now = datetime.utcnow()
    db.query(EventTicket).filter(
        EventTicket.event_id == eid,
        EventTicket.status == TicketOrderStatusEnum.reserved,
        EventTicket.reserved_until.isnot(None),
        EventTicket.reserved_until < now,
    ).delete(synchronize_session=False)
    db.commit()

    # Batch-load "sold" and "active reserved" quantities for ALL ticket
    # classes in two grouped queries (previously: 2 queries per class).
    class_ids = [tc.id for tc in classes]
    sold_map: dict = {}
    reserved_map: dict = {}
    if class_ids:
        sold_map = {
            cid: int(qty or 0) for cid, qty in db.query(
                EventTicket.ticket_class_id,
                sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0),
            ).filter(
                EventTicket.ticket_class_id.in_(class_ids),
                EventTicket.status.in_([
                    TicketOrderStatusEnum.approved,
                    TicketOrderStatusEnum.confirmed,
                ]),
            ).group_by(EventTicket.ticket_class_id).all()
        }
        reserved_map = {
            cid: int(qty or 0) for cid, qty in db.query(
                EventTicket.ticket_class_id,
                sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0),
            ).filter(
                EventTicket.ticket_class_id.in_(class_ids),
                EventTicket.status == TicketOrderStatusEnum.reserved,
                EventTicket.reserved_until.isnot(None),
                EventTicket.reserved_until > now,
            ).group_by(EventTicket.ticket_class_id).all()
        }

    result = []
    for tc in classes:
        sold = sold_map.get(tc.id, 0)
        active_reserved = reserved_map.get(tc.id, 0)
        blocking = sold + active_reserved
        available = max(0, tc.quantity - blocking)
        is_sold_out = available <= 0
        if is_sold_out:
            status_label = "sold_out"
        elif available <= max(3, int(tc.quantity * 0.05)):
            status_label = "almost_sold_out"
        elif available <= max(10, int(tc.quantity * 0.20)):
            status_label = "few_left"
        else:
            status_label = "available"
        result.append({
            "id": str(tc.id),
            "name": tc.name,
            "description": tc.description,
            "price": float(tc.price),
            "quantity": tc.quantity,
            "capacity": tc.quantity,
            "sold": sold,
            "sold_count": sold,
            "active_reserved_count": active_reserved,
            "available": available,
            "available_count": available,
            "status": tc.status.value if tc.status else "available",
            "status_label": status_label,
            "is_sold_out": is_sold_out,
            "sale_start_date": str(tc.sale_start_date) if tc.sale_start_date else None,
            "sale_end_date": str(tc.sale_end_date) if tc.sale_end_date else None,
            "display_order": tc.display_order,
        })

    return standard_response(True, "Ticket classes retrieved", {
        "event_id": event_id,
        "event_name": event.name,
        "ticket_classes": result,
    })


# ──────────────────────────────────────────────
# Get ticket classes for own event (organizer)
# ──────────────────────────────────────────────
@router.get("/my-events/{event_id}/ticket-classes")
def get_my_ticket_classes(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get ticket classes for an event owned by the current user."""
    try:
        eid = UUID(event_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Event not found or not authorized")

    classes = db.query(EventTicketClass).filter(
        EventTicketClass.event_id == eid
    ).order_by(EventTicketClass.display_order).all()

    from sqlalchemy import func as sa_func

    # Batch grouped queries for sold / reserved / pending across all classes.
    class_ids = [tc.id for tc in classes]
    def _group(status_filter):
        return {
            cid: int(qty or 0) for cid, qty in db.query(
                EventTicket.ticket_class_id,
                sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0),
            ).filter(
                EventTicket.ticket_class_id.in_(class_ids),
                status_filter,
            ).group_by(EventTicket.ticket_class_id).all()
        } if class_ids else {}

    sold_map = _group(EventTicket.status.in_([TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed]))
    reserved_map = _group(EventTicket.status == TicketOrderStatusEnum.reserved)
    pending_map = _group(EventTicket.status == TicketOrderStatusEnum.pending)

    result = []
    for tc in classes:
        sold = sold_map.get(tc.id, 0)
        reserved = reserved_map.get(tc.id, 0)
        blocked_other = pending_map.get(tc.id, 0)
        available = tc.quantity - sold - reserved - blocked_other
        result.append({
            "id": str(tc.id),
            "name": tc.name,
            "description": tc.description,
            "price": float(tc.price),
            "quantity": tc.quantity,
            "sold": sold,
            "reserved": reserved,
            "available": max(0, available),
            "status": tc.status.value if tc.status else "available",
            "display_order": tc.display_order,
        })

    return standard_response(True, "Ticket classes retrieved", {
        "event_id": event_id,
        "event_name": event.name,
        "ticket_approval_status": event.ticket_approval_status.value if event.ticket_approval_status and hasattr(event.ticket_approval_status, 'value') else "pending",
        "ticket_rejection_reason": event.ticket_rejection_reason,
        "ticket_removed_reason": event.ticket_removed_reason,
        "ticket_classes": result,
    })


# ──────────────────────────────────────────────
# Create/Update ticket classes (organizer)
# ──────────────────────────────────────────────
@router.post("/events/{event_id}/ticket-classes")
async def create_ticket_class(
    event_id: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a new ticket class for an event."""
    try:
        eid = UUID(event_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Event not found or you are not the organizer")

    payload = await request.json()
    name = payload.get("name", "").strip()
    price = payload.get("price")
    quantity = payload.get("quantity")
    description = payload.get("description", "").strip()

    if not name:
        return standard_response(False, "Ticket class name is required")
    if price is None or float(price) < 0:
        return standard_response(False, "Valid price is required")
    if not quantity or int(quantity) < 1:
        return standard_response(False, "Quantity must be at least 1")

    # Mark event as selling tickets (approval stays pending until admin approves)
    event.sells_tickets = True
    event.is_public = True
    if not event.ticket_approval_status or (hasattr(event.ticket_approval_status, 'value') and event.ticket_approval_status.value == 'pending'):
        pass  # Keep pending

    tc = EventTicketClass(
        event_id=eid,
        name=name,
        description=description,
        price=float(price),
        quantity=int(quantity),
        display_order=payload.get("display_order", 0),
        sale_start_date=payload.get("sale_start_date"),
        sale_end_date=payload.get("sale_end_date"),
    )
    db.add(tc)
    db.commit()
    db.refresh(tc)

    return standard_response(True, "Ticket class created", {"id": str(tc.id)})


@router.put("/ticket-classes/{class_id}")
async def update_ticket_class(
    class_id: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update an existing ticket class."""
    try:
        cid = UUID(class_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid ticket class ID")

    tc = db.query(EventTicketClass).filter(EventTicketClass.id == cid).first()
    if not tc:
        return standard_response(False, "Ticket class not found")

    event = db.query(Event).filter(Event.id == tc.event_id, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Not authorized")

    from sqlalchemy import func as sa_func
    # Organizer context: count only approved/confirmed as truly "sold"
    actual_sold = db.query(sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0)).filter(
        EventTicket.ticket_class_id == tc.id,
        EventTicket.status.in_([TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed]),
    ).scalar()
    actual_sold = int(actual_sold)

    payload = await request.json()
    for field in ["name", "description", "price", "quantity", "display_order", "sale_start_date", "sale_end_date"]:
        if field in payload:
            if field == "price":
                setattr(tc, field, float(payload[field]))
            elif field == "quantity":
                new_qty = int(payload[field])
                if new_qty < actual_sold:
                    return standard_response(False, f"Cannot set quantity below {actual_sold} (already sold)")
                tc.quantity = new_qty
            else:
                setattr(tc, field, payload[field])

    if "status" in payload:
        try:
            tc.status = TicketStatusEnum(payload["status"])
        except (ValueError, KeyError):
            pass

    db.commit()
    return standard_response(True, "Ticket class updated")


@router.delete("/ticket-classes/{class_id}")
def delete_ticket_class(
    class_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete a ticket class (only if no tickets sold)."""
    try:
        cid = UUID(class_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid ticket class ID")

    tc = db.query(EventTicketClass).filter(EventTicketClass.id == cid).first()
    if not tc:
        return standard_response(False, "Ticket class not found")

    event = db.query(Event).filter(Event.id == tc.event_id, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Not authorized")

    from sqlalchemy import func as sa_func
    actual_sold = db.query(sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0)).filter(
        EventTicket.ticket_class_id == tc.id,
        EventTicket.status.in_([TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed]),
    ).scalar()
    if int(actual_sold) > 0:
        return standard_response(False, "Cannot delete ticket class with sold tickets")

    db.delete(tc)
    db.commit()
    return standard_response(True, "Ticket class deleted")


# ──────────────────────────────────────────────
# Purchase tickets
# ──────────────────────────────────────────────
@router.post("/purchase")
async def purchase_ticket(
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Purchase tickets for an event."""
    payload = await request.json()
    ticket_class_id = payload.get("ticket_class_id")
    quantity = int(payload.get("quantity", 1))

    if not ticket_class_id:
        return standard_response(False, "Ticket class ID is required")
    if quantity < 1:
        return standard_response(False, "Quantity must be at least 1")

    try:
        tcid = UUID(ticket_class_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid ticket class ID")

    tc = db.query(EventTicketClass).filter(EventTicketClass.id == tcid).first()
    if not tc:
        return standard_response(False, "Ticket class not found")

    from sqlalchemy import func as sa_func, and_, or_
    _now = datetime.utcnow()
    # Sweep expired reservations for this class before checking availability.
    db.query(EventTicket).filter(
        EventTicket.ticket_class_id == tc.id,
        EventTicket.status == TicketOrderStatusEnum.reserved,
        EventTicket.reserved_until.isnot(None),
        EventTicket.reserved_until < _now,
    ).delete(synchronize_session=False)
    db.commit()
    # Calculate sold from actual orders (SUM of quantity), excluding rejected/
    # cancelled and any reserved row whose hold window has expired.
    current_sold = db.query(sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0)).filter(
        EventTicket.ticket_class_id == tc.id,
        EventTicket.status.notin_([TicketOrderStatusEnum.rejected, TicketOrderStatusEnum.cancelled]),
        or_(
            EventTicket.status != TicketOrderStatusEnum.reserved,
            EventTicket.reserved_until.is_(None),
            EventTicket.reserved_until > _now,
        ),
    ).scalar()
    current_sold = int(current_sold)
    available = tc.quantity - current_sold
    if available < quantity:
        return standard_response(False, f"Only {available} tickets available for '{tc.name}'. You requested {quantity}.")

    total = float(tc.price) * quantity
    ticket_code = f"NTK-{secrets.token_hex(4).upper()}"

    ticket = EventTicket(
        ticket_class_id=tcid,
        event_id=tc.event_id,
        buyer_user_id=current_user.id,
        ticket_code=ticket_code,
        quantity=quantity,
        total_amount=total,
        buyer_name=f"{current_user.first_name} {current_user.last_name}",
        buyer_phone=current_user.phone,
        buyer_email=current_user.email,
        status=TicketOrderStatusEnum.pending,
        payment_status=PaymentStatusEnum.pending,
    )

    # No need to maintain tc.sold column — sold count is always computed from orders

    db.add(ticket)
    db.commit()
    db.refresh(ticket)

    return standard_response(True, "Ticket purchased successfully", {
        "ticket_id": str(ticket.id),
        "ticket_code": ticket_code,
        "quantity": quantity,
        "total_amount": total,
        "event_id": str(tc.event_id),
        "ticket_class": tc.name,
    })


# ──────────────────────────────────────────────
# Bulk purchase (multiple ticket classes in one order)
# ──────────────────────────────────────────────
@router.post("/purchase-bulk")
async def purchase_tickets_bulk(
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Purchase tickets across multiple ticket classes in one atomic order.

    Request body:
        { "items": [ { "ticket_class_id": "...", "quantity": 2 }, ... ] }

    Backend is the source of truth for pricing. All items must belong to the
    same event. Each item becomes a pending EventTicket row; siblings share a
    `BULK:<token>` payment_ref so a single payment confirms the whole order.

    Returns the primary ticket (used as the payment target) plus the line
    items, subtotal per class, and grand total.
    """
    from sqlalchemy import func as sa_func
    from uuid import uuid4 as _uuid4

    payload = await request.json()
    raw_items = payload.get("items") or []
    if not isinstance(raw_items, list) or not raw_items:
        return standard_response(False, "At least one ticket item is required")

    # Validate + normalise
    parsed = []  # list of (tc, quantity)
    event_id = None
    for entry in raw_items:
        if not isinstance(entry, dict):
            return standard_response(False, "Invalid item format")
        tcid_raw = entry.get("ticket_class_id")
        try:
            qty = int(entry.get("quantity", 0))
        except (TypeError, ValueError):
            return standard_response(False, "Invalid quantity")
        if not tcid_raw or qty < 1:
            continue  # skip zero-quantity selections
        try:
            tcid = UUID(str(tcid_raw))
        except (ValueError, TypeError):
            return standard_response(False, "Invalid ticket class ID")
        tc = db.query(EventTicketClass).filter(EventTicketClass.id == tcid).first()
        if not tc:
            return standard_response(False, "Ticket class not found")
        if event_id is None:
            event_id = tc.event_id
        elif tc.event_id != event_id:
            return standard_response(False, "All ticket classes must belong to the same event")
        # Availability check using actual order rows (exclude expired reserved).
        from sqlalchemy import or_ as _or
        _now2 = datetime.utcnow()
        current_sold = db.query(sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0)).filter(
            EventTicket.ticket_class_id == tc.id,
            EventTicket.status.notin_([TicketOrderStatusEnum.rejected, TicketOrderStatusEnum.cancelled]),
            _or(
                EventTicket.status != TicketOrderStatusEnum.reserved,
                EventTicket.reserved_until.is_(None),
                EventTicket.reserved_until > _now2,
            ),
        ).scalar()
        available = tc.quantity - int(current_sold)
        if available < qty:
            return standard_response(False, f"Only {available} tickets available for '{tc.name}'. You requested {qty}.")
        parsed.append((tc, qty))

    if not parsed:
        return standard_response(False, "No tickets selected")

    group_token = f"BULK:{_uuid4().hex}"
    grand_total = 0.0
    created_tickets = []
    items_response = []

    buyer_name = f"{current_user.first_name} {current_user.last_name}".strip() or "Guest"

    for tc, qty in parsed:
        subtotal = float(tc.price) * qty
        grand_total += subtotal
        ticket_code = f"NTK-{secrets.token_hex(4).upper()}"
        t = EventTicket(
            ticket_class_id=tc.id,
            event_id=tc.event_id,
            buyer_user_id=current_user.id,
            ticket_code=ticket_code,
            quantity=qty,
            total_amount=subtotal,
            buyer_name=buyer_name,
            buyer_phone=current_user.phone,
            buyer_email=current_user.email,
            status=TicketOrderStatusEnum.pending,
            payment_status=PaymentStatusEnum.pending,
            payment_ref=group_token,
        )
        db.add(t)
        created_tickets.append((t, tc, qty, subtotal))

    db.commit()
    for t, _tc, _q, _s in created_tickets:
        db.refresh(t)

    primary = created_tickets[0][0]
    for t, tc, qty, subtotal in created_tickets:
        items_response.append({
            "ticket_id": str(t.id),
            "ticket_code": t.ticket_code,
            "ticket_class_id": str(tc.id),
            "ticket_class": tc.name,
            "quantity": qty,
            "unit_price": float(tc.price),
            "subtotal": subtotal,
        })

    return standard_response(True, "Tickets reserved successfully", {
        "primary_ticket_id": str(primary.id),
        "primary_ticket_code": primary.ticket_code,
        "group_token": group_token,
        "event_id": str(event_id),
        "items": items_response,
        "grand_total": grand_total,
        # Back-compat aliases for clients that read the single-purchase shape.
        "ticket_id": str(primary.id),
        "ticket_code": primary.ticket_code,
        "total_amount": grand_total,
        "quantity": sum(q for _t, _tc, q, _s in created_tickets),
    })



# ──────────────────────────────────────────────
# Get my tickets
# ──────────────────────────────────────────────
@router.get("/my-tickets")
def get_my_tickets(
    page: int = 1,
    limit: int = 20,
    search: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get all tickets purchased by the current user.

    Optional ``?search=`` filters by event name, location, ticket class name
    or ticket code (case-insensitive substring match)."""
    from sqlalchemy import func as sa_func, or_

    page = max(1, page)
    limit = max(1, min(limit, 50))
    offset = (page - 1) * limit

    # Buyers should only see tickets they have actually paid for. Pending
    # reservations (created at checkout time but never paid) stay hidden so
    # we never advertise an unconfirmed ticket as "issued".
    # Show tickets that are either paid OR approved/confirmed by the organizer
    # (covers comp tickets, organizer-issued tickets, and tickets the event owner
    # bought from their own event where settlement bypasses payment_status).
    query = db.query(EventTicket).filter(
        EventTicket.buyer_user_id == current_user.id,
        EventTicket.status.notin_([TicketOrderStatusEnum.cancelled, TicketOrderStatusEnum.rejected]),
        or_(
            EventTicket.payment_status == PaymentStatusEnum.completed,
            EventTicket.status.in_([TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed]),
        ),
    )

    if search and search.strip():
        term = f"%{search.strip().lower()}%"
        query = query.outerjoin(Event, EventTicket.event_id == Event.id) \
                     .outerjoin(EventTicketClass, EventTicket.ticket_class_id == EventTicketClass.id) \
                     .filter(or_(
                         sa_func.lower(EventTicket.ticket_code).like(term),
                         sa_func.lower(Event.name).like(term),
                         sa_func.lower(Event.location).like(term),
                         sa_func.lower(EventTicketClass.name).like(term),
                     ))

    query = query.order_by(EventTicket.created_at.desc())

    total = query.count()
    tickets = query.offset(offset).limit(limit).all()

    from models.users import UserProfile

    # Batch event + ticket_class + organizer + organizer profile lookups
    # (previously: 4 per-row queries × page size = up to 200 trips per page).
    event_ids = {t.event_id for t in tickets if t.event_id}
    class_ids = {t.ticket_class_id for t in tickets if t.ticket_class_id}
    events_map = {e.id: e for e in db.query(Event).filter(Event.id.in_(event_ids)).all()} if event_ids else {}
    classes_map = {c.id: c for c in db.query(EventTicketClass).filter(EventTicketClass.id.in_(class_ids)).all()} if class_ids else {}

    organizer_ids = {e.organizer_id for e in events_map.values() if getattr(e, "organizer_id", None)}
    organizers_map = {u.id: u for u in db.query(User).filter(User.id.in_(organizer_ids)).all()} if organizer_ids else {}
    organizer_profiles_map = {
        p.user_id: p for p in db.query(UserProfile).filter(UserProfile.user_id.in_(organizer_ids)).all()
    } if organizer_ids else {}

    # Cover images: batch one fallback EventImage lookup per event when needed.
    event_cover_cache: dict = {}
    for e in events_map.values():
        if e.cover_image_url:
            event_cover_cache[e.id] = e.cover_image_url
    missing_cover_ids = [eid for eid in events_map if eid not in event_cover_cache]
    if missing_cover_ids:
        imgs = (
            db.query(EventImage)
            .filter(EventImage.event_id.in_(missing_cover_ids))
            .order_by(EventImage.is_featured.desc(), EventImage.created_at.asc())
            .all()
        )
        for img in imgs:
            event_cover_cache.setdefault(img.event_id, img.image_url)

    result = []
    for t in tickets:
        event = events_map.get(t.event_id)
        tc = classes_map.get(t.ticket_class_id)
        organizer_block = None
        if event and event.organizer_id in organizers_map:
            organizer = organizers_map[event.organizer_id]
            op = organizer_profiles_map.get(organizer.id)
            full = " ".join(filter(None, [organizer.first_name, organizer.last_name])).strip()
            organizer_block = {
                "id": str(organizer.id),
                "name": full or organizer.username or "Organizer",
                "avatar": op.profile_picture_url if op else None,
                "is_verified": bool(getattr(organizer, "is_identity_verified", False)),
            }

        result.append({
            "id": str(t.id),
            "ticket_code": t.ticket_code,
            "event": {
                "id": str(event.id) if event else None,
                "name": event.name if event else None,
                "start_date": str(event.start_date) if event and event.start_date else None,
                "start_time": str(event.start_time) if event and event.start_time else None,
                "location": event.location if event else None,
                "cover_image": event_cover_cache.get(t.event_id) if event else None,
                "description": event.description if event else None,
                "organizer": organizer_block,
            },
            "ticket_class": tc.name if tc else None,
            "ticket_class_name": tc.name if tc else None,
            "quantity": t.quantity,
            "total_amount": float(t.total_amount),
            "currency": "TZS",
            "status": t.status.value if t.status else "pending",
            "payment_status": t.payment_status.value if t.payment_status else "pending",
            "checked_in": bool(t.checked_in),
            "checked_in_at": str(t.checked_in_at) if t.checked_in_at else None,
            "created_at": str(t.created_at) if t.created_at else None,
        })

    return standard_response(True, "Tickets retrieved", {
        "tickets": result,
        "pagination": {
            "page": page, "limit": limit, "total_items": total,
            "total_pages": (total + limit - 1) // limit,
            "has_next": (page * limit) < total, "has_previous": page > 1
        }
    })


# ──────────────────────────────────────────────
# Get event tickets (organizer view)
# ──────────────────────────────────────────────
@router.get("/events/{event_id}/tickets")
def get_event_tickets(
    event_id: str,
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get all tickets sold for an event (organizer only)."""
    try:
        eid = UUID(event_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Event not found or not authorized")

    page = max(1, page)
    limit = max(1, min(limit, 100))
    offset = (page - 1) * limit

    query = db.query(EventTicket).filter(EventTicket.event_id == eid).order_by(EventTicket.created_at.desc())
    total = query.count()
    tickets = query.offset(offset).limit(limit).all()

    # Batch-load ticket classes for the visible page.
    class_ids = {t.ticket_class_id for t in tickets if t.ticket_class_id}
    classes_map = {c.id: c for c in db.query(EventTicketClass).filter(EventTicketClass.id.in_(class_ids)).all()} if class_ids else {}

    result = []
    for t in tickets:
        tc = classes_map.get(t.ticket_class_id)
        result.append({
            "id": str(t.id),
            "ticket_code": t.ticket_code,
            "buyer_name": t.buyer_name,
            "buyer_phone": t.buyer_phone,
            "buyer_email": t.buyer_email,
            "ticket_class": tc.name if tc else None,
            "quantity": t.quantity,
            "total_amount": float(t.total_amount),
            "status": t.status.value if t.status else "pending",
            "payment_status": t.payment_status.value if t.payment_status else "pending",
            "checked_in": t.checked_in,
            "reserved_until": t.reserved_until.isoformat() if t.reserved_until else None,
            "created_at": str(t.created_at) if t.created_at else None,
        })

    return standard_response(True, "Event tickets retrieved", {
        "tickets": result,
        "pagination": {
            "page": page, "limit": limit, "total_items": total,
            "total_pages": (total + limit - 1) // limit,
            "has_next": (page * limit) < total, "has_previous": page > 1
        }
    })


# ──────────────────────────────────────────────
# Organizer: Approve / Reject a ticket
# ──────────────────────────────────────────────
@router.put("/tickets/{ticket_id}/status")
async def update_ticket_status(
    ticket_id: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Organizer approves or rejects a ticket order."""
    try:
        tid = UUID(ticket_id)
    except (ValueError, TypeError):
        return standard_response(False, "Invalid ticket ID")

    ticket = db.query(EventTicket).filter(EventTicket.id == tid).first()
    if not ticket:
        return standard_response(False, "Ticket not found")

    event = db.query(Event).filter(Event.id == ticket.event_id, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Not authorized to manage this ticket")

    payload = await request.json()
    new_status = payload.get("status", "").lower()

    if new_status not in ("approved", "rejected", "confirmed", "cancelled"):
        return standard_response(False, "Invalid status. Use: approved, rejected, confirmed, cancelled")

    try:
        ticket.status = TicketOrderStatusEnum(new_status)
    except (ValueError, KeyError):
        return standard_response(False, "Invalid status value")

    # No need to manually adjust tc.sold — sold is always computed from orders
    # Rejected orders are excluded by the notin_ filter in sold calculations

    db.commit()

    # Notify buyer
    try:
        from utils.notify import create_notification
        if new_status == "approved":
            create_notification(
                db, ticket.buyer_user_id, current_user.id,
                "general",
                f"Your ticket for {event.name} has been approved!",
                reference_id=event.id, reference_type="event",
                message_data={"event_title": event.name, "ticket_code": ticket.ticket_code},
            )
        elif new_status == "rejected":
            create_notification(
                db, ticket.buyer_user_id, current_user.id,
                "general",
                f"Your ticket for {event.name} has been rejected.",
                reference_id=event.id, reference_type="event",
                message_data={"event_title": event.name, "ticket_code": ticket.ticket_code},
            )
        db.commit()
    except Exception:
        pass

    return standard_response(True, f"Ticket {new_status} successfully")


# ──────────────────────────────────────────────
# Get my upcoming tickets (for sidebar)
# ──────────────────────────────────────────────
@router.get("/my-upcoming-tickets")
def get_my_upcoming_tickets(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get approved/confirmed tickets for upcoming events (today or future)."""
    today = datetime.now().date()

    # SQL-side join + date filter + limit (previously: unbounded fetch +
    # per-ticket Event/EventTicketClass queries + Python date filter).
    rows = (
        db.query(EventTicket, Event, EventTicketClass)
        .join(Event, Event.id == EventTicket.event_id)
        .outerjoin(EventTicketClass, EventTicketClass.id == EventTicket.ticket_class_id)
        .filter(
            EventTicket.buyer_user_id == current_user.id,
            EventTicket.status.in_([TicketOrderStatusEnum.confirmed, TicketOrderStatusEnum.approved]),
            Event.start_date >= today,
        )
        .order_by(Event.start_date.asc())
        .limit(10)
        .all()
    )

    # Batch cover image fallback for events missing cover_image_url.
    event_cover_cache: dict = {}
    missing_cover_ids = []
    for _, e, _ in rows:
        if e.cover_image_url:
            event_cover_cache[e.id] = e.cover_image_url
        else:
            missing_cover_ids.append(e.id)
    if missing_cover_ids:
        imgs = (
            db.query(EventImage)
            .filter(EventImage.event_id.in_(missing_cover_ids))
            .order_by(EventImage.is_featured.desc(), EventImage.created_at.asc())
            .all()
        )
        for img in imgs:
            event_cover_cache.setdefault(img.event_id, img.image_url)

    result = []
    for t, event, tc in rows:
        result.append({
            "id": str(t.id),
            "ticket_code": t.ticket_code,
            "quantity": t.quantity,
            "total_amount": float(t.total_amount),
            "currency": "TZS",
            "status": t.status.value if t.status else "confirmed",
            "ticket_class": tc.name if tc else None,
            "ticket_class_name": tc.name if tc else None,
            "event": {
                "id": str(event.id),
                "name": event.name,
                "start_date": str(event.start_date),
                "start_time": str(event.start_time) if event.start_time else None,
                "location": event.location,
                "cover_image": event_cover_cache.get(event.id),
                "description": event.description,
            },
        })

    return standard_response(True, "Upcoming tickets retrieved", {"tickets": result})


# ──────────────────────────────────────────────
# Verify ticket by code (public - for QR scan)
# ──────────────────────────────────────────────
@router.get("/verify/{ticket_code}")
def verify_ticket(
    ticket_code: str,
    db: Session = Depends(get_db),
):
    """Public endpoint to verify a ticket by its code (used by QR scan)."""
    from models.users import UserProfile

    ticket = db.query(EventTicket).filter(EventTicket.ticket_code == ticket_code).first()
    if not ticket:
        return standard_response(False, "Ticket not found")

    event = db.query(Event).filter(Event.id == ticket.event_id).first()
    tc = db.query(EventTicketClass).filter(EventTicketClass.id == ticket.ticket_class_id).first()

    # Resolve buyer profile picture
    buyer = db.query(User).filter(User.id == ticket.buyer_user_id).first()
    buyer_avatar = None
    if buyer:
        profile = db.query(UserProfile).filter(UserProfile.user_id == buyer.id).first()
        buyer_avatar = profile.profile_picture_url if profile else None

    return standard_response(True, "Ticket verified", {
        "ticket": {
            "ticket_code": ticket.ticket_code,
            "event_title": event.name if event else "Unknown Event",
            "event_date": str(event.start_date) if event and event.start_date else None,
            "event_time": str(event.start_time) if event and event.start_time else None,
            "event_location": event.location if event else None,
            "event_cover": _resolve_event_cover(event, db) if event else None,
            "ticket_class": tc.name if tc else None,
            "ticket_class_price": float(tc.price) if tc else None,
            "quantity": ticket.quantity,
            "buyer_name": ticket.buyer_name,
            "buyer_phone": ticket.buyer_phone,
            "buyer_email": ticket.buyer_email,
            "buyer_avatar": buyer_avatar,
            "total_amount": float(ticket.total_amount),
            "currency": "TZS",
            "status": ticket.status.value if ticket.status else "pending",
            "checked_in": ticket.checked_in,
            "checked_in_at": str(ticket.checked_in_at) if ticket.checked_in_at else None,
            "event_id": str(event.id) if event else None,
            "purchased_at": str(ticket.created_at) if ticket.created_at else None,
        }
    })


# ──────────────────────────────────────────────
# Check-in ticket (organizer scans QR)
# ──────────────────────────────────────────────
@router.put("/verify/{ticket_code}/check-in")
def check_in_ticket(
    ticket_code: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Mark a ticket as checked-in (used). Only the event organizer can do this."""
    ticket = db.query(EventTicket).filter(EventTicket.ticket_code == ticket_code).first()
    if not ticket:
        return standard_response(False, "Ticket not found")

    event = db.query(Event).filter(Event.id == ticket.event_id).first()
    if not event:
        return standard_response(False, "Event not found")

    # Only organizer can check in
    if event.organizer_id != current_user.id:
        return standard_response(False, "Only the event organizer can check in tickets")

    # Must be approved/confirmed
    if ticket.status not in (TicketOrderStatusEnum.approved, TicketOrderStatusEnum.confirmed):
        return standard_response(False, f"Cannot check in a ticket with status '{ticket.status.value}'. Must be approved or confirmed.")

    if ticket.checked_in:
        return standard_response(False, "Ticket has already been checked in", {
            "checked_in_at": str(ticket.checked_in_at) if ticket.checked_in_at else None
        })

    ticket.checked_in = True
    ticket.checked_in_at = datetime.now()
    db.commit()

    return standard_response(True, "Ticket checked in successfully", {
        "ticket_code": ticket.ticket_code,
        "checked_in_at": str(ticket.checked_in_at),
    })


# ──────────────────────────────────────────────
# Get ticketed events (public, for right panel)
# ──────────────────────────────────────────────
@router.get("/events")
def get_ticketed_events(
    page: int = 1,
    limit: int = 10,
    search: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_optional_user),
):
    """Get all public events that sell tickets.

    Visibility rules:
      - Approved + public events are visible to everyone.
      - The organizer ALWAYS sees their own ticketed event regardless of
        approval status (with `ticket_approval_status` in the payload so the
        UI can render a "Pending review" badge).
    """
    from sqlalchemy import func as sa_func, or_, and_

    page = max(1, page)
    limit = max(1, min(limit, 50))
    offset = (page - 1) * limit

    base_filter = [Event.sells_tickets == True]
    visibility_filter = and_(
        Event.is_public == True,
        Event.ticket_approval_status == TicketApprovalStatusEnum.approved,
    )

    if current_user:
        # Organizer sees own events even if pending; everyone else only approved+public
        query = db.query(Event).filter(
            *base_filter,
            or_(visibility_filter, Event.organizer_id == current_user.id),
        )
    else:
        query = db.query(Event).filter(*base_filter, visibility_filter)

    # Live search filter
    if search and search.strip():
        search_term = f"%{search.strip().lower()}%"
        query = query.filter(
            sa_func.lower(Event.name).like(search_term) |
            sa_func.lower(Event.location).like(search_term)
        )

    query = query.order_by(Event.start_date.asc())

    total = query.count()
    events = query.offset(offset).limit(limit).all()

    result = []
    for e in events:
        ticket_classes = db.query(EventTicketClass).filter(EventTicketClass.event_id == e.id).all()
        min_price = min([float(tc.price) for tc in ticket_classes], default=0) if ticket_classes else 0

        # Calculate available using SUM(quantity) from actual ticket orders
        total_sold_qty = db.query(sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0)).filter(
            EventTicket.event_id == e.id,
            EventTicket.status.notin_([TicketOrderStatusEnum.rejected, TicketOrderStatusEnum.cancelled]),
        ).scalar()
        total_qty = sum([tc.quantity for tc in ticket_classes]) if ticket_classes else 0
        total_available = total_qty - int(total_sold_qty)

        approval_status = e.ticket_approval_status.value if e.ticket_approval_status and hasattr(e.ticket_approval_status, "value") else "pending"
        is_owner = bool(current_user and e.organizer_id == current_user.id)

        result.append({
            "id": str(e.id),
            "name": e.name,
            "start_date": str(e.start_date) if e.start_date else None,
            "location": e.location,
            "cover_image": _resolve_event_cover(e, db),
            "min_price": min_price,
            "total_available": max(0, total_available),
            "ticket_class_count": len(ticket_classes),
            "ticket_approval_status": approval_status,
            "is_owner": is_owner,
            "is_public": bool(e.is_public),
        })

    return standard_response(True, "Ticketed events retrieved", {
        "events": result,
        "pagination": {
            "page": page, "limit": limit, "total_items": total,
            "total_pages": (total + limit - 1) // limit,
            "has_next": (page * limit) < total, "has_previous": page > 1
        }
    })
