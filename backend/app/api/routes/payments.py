"""Customer-facing payment endpoints.

POST /payments/initiate
    Body: { target_type, target_id, gross_amount, currency_code, country_code,
            method_type, provider_id?, payment_channel, phone_number?,
            payment_description, beneficiary_user_id? }
    Response: { transaction, checkout_request_id?, next_action }

GET  /payments/{transaction_id}/status         → polled by frontend
POST /payments/callback                         → SasaPay webhook (no auth)
GET  /payments/providers                        → active providers for a country
GET  /payments/my-transactions                  → payer history
"""

from datetime import datetime, timezone


def _iso_utc(dt):
    """Serialize a datetime as a UTC ISO-8601 string with explicit ``+00:00``.

    Database columns are timezone-naive but values are stored in UTC, so
    naive timestamps are tagged with UTC before being serialized. Without
    this the frontend interprets them as local time and shows wrong
    timezones on receipts and history rows.
    """
    if not dt:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()
from decimal import Decimal
import uuid as uuid_lib
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from core.database import get_db
from utils.auth import get_current_user
from utils.helpers import api_response, paginate
from models.users import User
from models.payments import (
    Transaction, MobilePaymentAttempt, PaymentCallbackLog,
    PaymentProvider, Wallet,
)
from models.ticketing import EventTicket
from models.enums import (
    PaymentTargetTypeEnum, TransactionStatusEnum, PaymentStatusEnum,
)
from services.payment_gateway import gateway, PaymentGateway
from services.transaction_service import create_transaction
from services.wallet_service import get_or_create_wallet, credit_available, commission_charge


router = APIRouter(prefix="/payments", tags=["payments"])

TARGET_TYPE_ALIASES = {
    "event_ticket": PaymentTargetTypeEnum.ticket.value,
    "ticket_purchase": PaymentTargetTypeEnum.ticket.value,
    "event_contribution": PaymentTargetTypeEnum.contribution.value,
    "service_booking": PaymentTargetTypeEnum.booking.value,
    "payout": PaymentTargetTypeEnum.withdrawal.value,
}


# Phrases the gateway returns as a generic "we got your query" ack — these
# are NOT failure descriptions and must never be persisted as failure_reason.
_GATEWAY_ACK_NOISE = (
    "your request has been received",
    "check your callback url",
    "request received",
    "queued for processing",
    "staged for processing",
)


def _clean_failure_reason(reason):
    """Strip gateway acknowledgement noise so users see a real failure cause.

    SasaPay's status-query may answer ``{"status": true, "message": "Your
    request has been received. Check your callback url for response"}`` while
    the real result is in flight via the webhook. That message is meaningless
    to end users and must never appear under a "Failure reason" label.
    """
    if not reason:
        return None
    text = str(reason).strip()
    if not text:
        return None
    low = text.lower()
    for noise in _GATEWAY_ACK_NOISE:
        if noise in low:
            return None
    return text


def _failure_reason_from_callbacks(db: Session, tx, attempt) -> Optional[str]:
    """Inspect persisted callback rows for this tx and return a human reason.

    Used when the gateway's status-query is silent (returns the async ack
    "Your request has been received…") but a real C2B callback has already
    landed on /payments/callback with a non-zero ResultCode. We match
    callbacks via:
      • PaymentCallbackLog.transaction_id == tx.id (post-link)
      • PaymentCallbackLog.checkout_request_id == attempt.checkout_request_id
        (rows that arrived before linkage was possible)
    """
    conds = [PaymentCallbackLog.transaction_id == tx.id]
    if attempt and attempt.checkout_request_id:
        conds.append(PaymentCallbackLog.checkout_request_id == attempt.checkout_request_id)
    from sqlalchemy import or_ as _or
    rows = (
        db.query(PaymentCallbackLog)
        .filter(_or(*conds))
        .order_by(PaymentCallbackLog.received_at.desc())
        .limit(10)
        .all()
    )
    for r in rows:
        p = r.payload or {}
        if not isinstance(p, dict):
            continue
        rc = p.get("ResultCode") if p.get("ResultCode") is not None else p.get("ResponseCode")
        if rc is None or str(rc) == "0":
            continue
        reason = (
            p.get("ResultDesc")
            or p.get("ResultDescription")
            or p.get("ResponseDescription")
            or p.get("detail")
        )
        cleaned = _clean_failure_reason(reason)
        if cleaned:
            return cleaned
        # Even with no description, surface the code so the user gets a hint
        return f"Gateway error (code {rc})."
    return None


# ──────────────────────────────────────────────
# Serializers
# ──────────────────────────────────────────────

def _serialize_tx(tx: Transaction) -> dict:
    return {
        "id": str(tx.id),
        "transaction_code": tx.transaction_code,
        "target_type": tx.target_type.value if tx.target_type else None,
        "target_id": str(tx.target_id) if tx.target_id else None,
        "country_code": tx.country_code,
        "currency_code": tx.currency_code,
        "gross_amount": float(tx.gross_amount or 0),
        "commission_amount": float(tx.commission_amount or 0),
        "net_amount": float(tx.net_amount or 0),
        "method_type": tx.method_type,
        "provider_name": tx.provider_name,
        "payment_channel": tx.payment_channel,
        "external_reference": tx.external_reference,
        "payment_description": tx.payment_description,
        "status": tx.status.value if tx.status else None,
        "failure_reason": tx.failure_reason,
        "initiated_at": _iso_utc(tx.initiated_at),
        "confirmed_at": _iso_utc(tx.confirmed_at),
        "completed_at": _iso_utc(tx.completed_at),
    }


def _normalize_target_type(target_type_raw: str) -> PaymentTargetTypeEnum:
    normalized = TARGET_TYPE_ALIASES.get((target_type_raw or "").strip(), (target_type_raw or "").strip())
    try:
        return PaymentTargetTypeEnum(normalized)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid target_type.")


def _payer_label(user: Optional[User]) -> str:
    if not user:
        return "a Nuru user"
    name = " ".join(filter(None, [getattr(user, "first_name", None), getattr(user, "last_name", None)])).strip()
    return name or getattr(user, "phone", None) or getattr(user, "email", None) or "a Nuru user"


def _format_purpose(target_type: PaymentTargetTypeEnum) -> str:
    return {
        PaymentTargetTypeEnum.ticket: "Ticket Purchase",
        PaymentTargetTypeEnum.contribution: "Event Contribution",
        PaymentTargetTypeEnum.booking: "Service Booking",
        PaymentTargetTypeEnum.wallet_topup: "Wallet Top-up",
        PaymentTargetTypeEnum.withdrawal: "Wallet Withdrawal",
        PaymentTargetTypeEnum.settlement: "Settlement",
    }.get(target_type, "Payment")


def _enrich_payment_description(
    *,
    target_type: PaymentTargetTypeEnum,
    user_supplied: str,
    payer: Optional[User],
    transaction_code: Optional[str] = None,
) -> str:
    """Always store a Nuru-branded, audit-friendly description.

    Format: ``Nuru · {Purpose} · {Detail} · by {Payer}[ · ref {code}]``
    Keeps any meaningful detail the caller already typed in.
    """
    purpose = _format_purpose(target_type)
    detail = (user_supplied or "").strip()
    parts = ["Nuru", purpose]
    if detail:
        parts.append(detail)
    parts.append(f"by {_payer_label(payer)}")
    if transaction_code:
        parts.append(f"ref {transaction_code}")
    return " · ".join(parts)


def _ledger_text(prefix: str, tx: Transaction, payer: Optional[User]) -> str:
    """Wallet ledger row text — explicit and Nuru-branded."""
    purpose = _format_purpose(tx.target_type)
    return (
        f"Nuru · {prefix} · {purpose} · by {_payer_label(payer)} · "
        f"ref {tx.transaction_code}"
    )


def _sync_target_after_payment(db: Session, tx: Transaction):
    """Propagate a successful payment to the underlying resource.

    Handles:
      • ticket      → mark EventTicket as paid
      • contribution → record a confirmed EventContribution so the contributor's
        "My contributions" totals update automatically (idempotent).
    """
    if not tx.target_id:
        return

    # ── Tickets ────────────────────────────────────────────────────────────
    if tx.target_type == PaymentTargetTypeEnum.ticket:
        ticket = db.query(EventTicket).filter(EventTicket.id == tx.target_id).first()
        if not ticket:
            return
        # Multi-class bulk orders share a `BULK:<token>` payment_ref across
        # sibling EventTicket rows. When the user pays for the primary
        # ticket, every sibling must be confirmed as part of the same order.
        from models.enums import TicketOrderStatusEnum
        tickets_to_confirm = [ticket]
        if ticket.payment_ref and ticket.payment_ref.startswith("BULK:"):
            siblings = db.query(EventTicket).filter(
                EventTicket.payment_ref == ticket.payment_ref,
                EventTicket.id != ticket.id,
            ).all()
            tickets_to_confirm.extend(siblings)
        for _t in tickets_to_confirm:
            # Idempotency guard: if this ticket was already confirmed by a
            # prior callback, skip the WhatsApp delivery so repeated webhook
            # calls don't spam the buyer with duplicate ticket cards.
            already_confirmed = (
                _t.payment_status == PaymentStatusEnum.completed
                and _t.status == TicketOrderStatusEnum.confirmed
            )
            _t.payment_status = PaymentStatusEnum.completed
            _t.payment_ref = tx.transaction_code
            # Gateway-paid tickets are auto-confirmed — funds already received
            # via SasaPay, no organiser approval needed.
            if _t.status not in (
                TicketOrderStatusEnum.cancelled,
                TicketOrderStatusEnum.rejected,
            ):
                _t.status = TicketOrderStatusEnum.confirmed
            if already_confirmed:
                continue
            # Auto-deliver each ticket via WhatsApp (fire-and-forget).
            try:
                if _t.buyer_phone:
                    from utils.whatsapp_cards import wa_send_ticket
                    from models.events import Event as _Ev
                    from models.ticketing import EventTicketClass as _Tc
                    ev = db.query(_Ev).filter(_Ev.id == _t.event_id).first()
                    tc = db.query(_Tc).filter(_Tc.id == _t.ticket_class_id).first()
                    ev_date = ""
                    try:
                        if ev and getattr(ev, "start_date", None):
                            ev_date = ev.start_date.strftime("%a, %-d %b %Y")
                    except Exception:
                        try:
                            ev_date = ev.start_date.strftime("%a, %d %b %Y") if ev and getattr(ev, "start_date", None) else ""
                        except Exception:
                            pass
                    wa_send_ticket(
                        phone=_t.buyer_phone,
                        event_id=str(_t.event_id),
                        ticket_code=_t.ticket_code,
                        buyer_name=_t.buyer_name or "Friend",
                        event_name=(ev.name if ev else "the event"),
                        event_date=ev_date or "",
                        ticket_class=(tc.name if tc else "General"),
                        cover_image=(getattr(ev, "cover_image_url", None) if ev else None) or "",
                        event_time=(getattr(ev, "start_time", None).isoformat() if ev and getattr(ev, "start_time", None) else ""),
                        venue=(getattr(ev, "location", None) if ev else None) or "",
                    )
            except Exception as _e:
                print(f"[payments] wa_send_ticket (online) failed: {_e}")
        return



    # ── Event contributions ────────────────────────────────────────────────
    if tx.target_type == PaymentTargetTypeEnum.contribution:
        from models.contributions import (
            UserContributor, EventContributor, EventContribution,
        )
        from models.enums import ContributionStatusEnum, PaymentMethodEnum
        from sqlalchemy import func as _sa_func

        event_id = tx.target_id
        payer_id = tx.payer_user_id
        if not payer_id:
            return

        # Idempotency: skip if we've already recorded this transaction.
        existing = db.query(EventContribution).filter(
            EventContribution.event_id == event_id,
            EventContribution.transaction_ref == tx.transaction_code,
        ).first()
        if existing:
            if existing.confirmation_status != ContributionStatusEnum.confirmed:
                existing.confirmation_status = ContributionStatusEnum.confirmed
                existing.confirmed_at = existing.confirmed_at or datetime.utcnow()
            return

        payer = db.query(User).filter(User.id == payer_id).first()
        if not payer:
            return

        # Find (or create) the EventContributor row for this payer on the event.
        # Match via contributor_user_id first, then phone equivalence.
        ec = (
            db.query(EventContributor)
            .join(UserContributor, UserContributor.id == EventContributor.contributor_id)
            .filter(
                EventContributor.event_id == event_id,
                UserContributor.contributor_user_id == payer_id,
            )
            .first()
        )

        if not ec and getattr(payer, "phone", None):
            phone_digits = "".join(ch for ch in str(payer.phone) if ch.isdigit())[-9:]
            if phone_digits:
                ec = (
                    db.query(EventContributor)
                    .join(UserContributor, UserContributor.id == EventContributor.contributor_id)
                    .filter(
                        EventContributor.event_id == event_id,
                        _sa_func.right(
                            _sa_func.regexp_replace(UserContributor.phone, r'[^0-9]', '', 'g'),
                            9,
                        ) == phone_digits,
                    )
                    .first()
                )

        # If the payer isn't listed as a contributor yet, create a self-contributor
        # + EventContributor pair so the payment is still recorded against the event.
        if not ec:
            from models.events import Event
            event = db.query(Event).filter(Event.id == event_id).first()
            if not event:
                return
            display_name = (
                f"{(payer.first_name or '').strip()} {(payer.last_name or '').strip()}".strip()
                or payer.phone
                or "Contributor"
            )
            # Reuse an existing UserContributor row owned by the organiser if one
            # already maps to this payer, otherwise create one.
            uc = db.query(UserContributor).filter(
                UserContributor.user_id == event.organizer_id,
                UserContributor.contributor_user_id == payer_id,
            ).first()
            if not uc:
                uc = UserContributor(
                    user_id=event.organizer_id,
                    contributor_user_id=payer_id,
                    name=display_name,
                    email=getattr(payer, "email", None),
                    phone=getattr(payer, "phone", None),
                )
                db.add(uc)
                db.flush()
            ec = EventContributor(
                event_id=event_id,
                contributor_id=uc.id,
                pledge_amount=0,
            )
            db.add(ec)
            db.flush()

        contact = {}
        if getattr(payer, "phone", None):
            contact["phone"] = payer.phone
        if getattr(payer, "email", None):
            contact["email"] = payer.email

        # Prefer the event-specific display name so contributions are stamped
        # with the name the organiser entered for THIS event.
        ec_display = (getattr(ec, "display_name", None) or "").strip()
        contributor_name = (
            ec_display
            or (ec.contributor.name if ec.contributor and ec.contributor.name else None)
            or f"{(payer.first_name or '').strip()} {(payer.last_name or '').strip()}".strip()
            or "Contributor"
        )

        # Map payment method loosely — mobile money is the dominant rail.
        pm = None
        try:
            mt = (tx.method_type or "").lower()
            if "cash" in mt:
                pm = PaymentMethodEnum.cash
            else:
                pm = PaymentMethodEnum.mobile
        except Exception:
            pm = None

        now = datetime.utcnow()
        contribution = EventContribution(
            event_id=event_id,
            event_contributor_id=ec.id,
            contributor_name=contributor_name,
            contributor_contact=contact or None,
            amount=tx.net_amount or tx.gross_amount,
            payment_method=pm,
            transaction_ref=tx.transaction_code,
            recorded_by=payer_id,
            confirmation_status=ContributionStatusEnum.confirmed,
            confirmed_at=now,
            contributed_at=now,
        )
        db.add(contribution)
        db.flush()

        # Post the contribution bubble into the event group chat (best-effort).
        # Mirrors the manual-record path in user_contributors.py so members see
        # gateway-paid contributions in the workspace chat too.
        try:
            from api.routes.event_groups import post_payment_system_message
            paid_amount = float(contribution.amount or 0)
            total_paid_after = sum(
                float(c.amount or 0) for c in ec.contributions
                if c.confirmation_status is None
                or c.confirmation_status == ContributionStatusEnum.confirmed
            )
            # `ec.contributions` may not yet include the just-flushed row in
            # this session — guarantee it's counted.
            if contribution not in ec.contributions:
                total_paid_after += paid_amount
            pledge_amount = float(ec.pledge_amount or 0)
            currency = tx.currency_code or "TZS"
            post_payment_system_message(
                db, event_id,
                contributor_name,
                paid_amount, pledge_amount, total_paid_after, currency,
            )
        except Exception:
            pass
        return


def _event_contributor_paid_total(ec, confirmed_enum) -> float:
    return sum(
        float(c.amount or 0)
        for c in getattr(ec, "contributions", [])
        if c.confirmation_status is None or c.confirmation_status == confirmed_enum
    )


def _notify_event_contributor_payment_recorded(db: Session, tx: Transaction) -> None:
    """Notify contributor phones according to primary/secondary/both after gateway payments."""
    if tx.target_type != PaymentTargetTypeEnum.contribution or not tx.target_id:
        return

    try:
        from sqlalchemy.orm import joinedload
        from models.events import Event
        from models.contributions import EventContributor, UserContributor
        from models.enums import ContributionStatusEnum
        from utils.helpers import format_phone_display
        from utils.offline_claims import contributor_notify_phones

        payer = db.query(User).filter(User.id == tx.payer_user_id).first() if tx.payer_user_id else None
        if not payer:
            return

        ec = (
            db.query(EventContributor)
            .options(joinedload(EventContributor.contributor), joinedload(EventContributor.contributions))
            .join(UserContributor, UserContributor.id == EventContributor.contributor_id)
            .filter(
                EventContributor.event_id == tx.target_id,
                UserContributor.contributor_user_id == tx.payer_user_id,
            )
            .first()
        )
        if not ec and getattr(payer, "phone", None):
            from sqlalchemy import func as _sa_func
            digits = "".join(ch for ch in str(payer.phone) if ch.isdigit())[-9:]
            if digits:
                ec = (
                    db.query(EventContributor)
                    .options(joinedload(EventContributor.contributor), joinedload(EventContributor.contributions))
                    .join(UserContributor, UserContributor.id == EventContributor.contributor_id)
                    .filter(
                        EventContributor.event_id == tx.target_id,
                        _sa_func.right(
                            _sa_func.regexp_replace(UserContributor.phone, r'[^0-9]', '', 'g'),
                            9,
                        ) == digits,
                    )
                    .first()
                )
        if not ec or not ec.contributor:
            return

        recipients = contributor_notify_phones(ec)
        if not recipients:
            return

        event = db.query(Event).filter(Event.id == tx.target_id).first()
        organizer = db.query(User).filter(User.id == event.organizer_id).first() if event and event.organizer_id else None
        organizer_phone = format_phone_display(organizer.phone) if organizer and organizer.phone else None
        amount = float(tx.net_amount or tx.gross_amount or 0)
        total_paid = _event_contributor_paid_total(ec, ContributionStatusEnum.confirmed)
        pledge = float(ec.pledge_amount or 0)
        currency = tx.currency_code or "TZS"
        event_name = event.name if event else "your event"
        contributor_name = (getattr(ec, "display_name", None) or ec.contributor.name or _payer_label(payer))

        for phone in recipients:
            try:
                from utils.whatsapp import wa_contribution_recorded
                wa_contribution_recorded(
                    phone, contributor_name, event_name,
                    amount, pledge, total_paid, currency,
                    organizer_phone=organizer_phone,
                    meta={
                        "event_id": str(event.id) if event else None,
                        "event_name": event_name,
                        "recipient_type": "contributor",
                        "recipient_id": str(ec.contributor.id) if ec and ec.contributor else None,
                        "recipient_name": contributor_name,
                        "message_purpose": "contribution_receipt",
                        "source_module": "payments",
                        "related_entity_type": "transaction",
                        "related_entity_id": str(tx.id) if tx else None,
                    },
                )
            except Exception as e:
                print(f"[payments] WA contribution recorded failed for {phone}: {e}")

            try:
                from utils.sms import sms_contribution_recorded
                sms_contribution_recorded(
                    phone, contributor_name, event_name,
                    amount, pledge, total_paid, currency,
                    organizer_phone=organizer_phone,
                )
            except Exception as e:
                print(f"[payments] SMS contribution recorded failed for {phone}: {e}")
    except Exception as e:
        print(f"[payments] contributor payment notify failed: {e}")


def _notify_payment_received(db: Session, tx: Transaction) -> None:
    """Fan-out SMS notifications for a successfully credited payment.

    Sends to:
      • the payer        — confirmation of their payment
      • the beneficiary  — funds-received notice (organizer / vendor / self)
      • the admin line   — ops heads-up so they can reconcile externally

    All sends are best-effort and silently log failures — they must never
    break the payment commit path.
    """
    try:
        from utils.sms import (
            sms_payment_received, sms_payment_confirmed_to_payer,
            sms_organizer_contribution_received, sms_vendor_booking_paid,
            sms_admin_payment_alert, get_admin_notify_phone,
        )
    except Exception as e:
        print(f"[payments] sms imports failed: {e}")
        return

    payer = (
        db.query(User).filter(User.id == tx.payer_user_id).first()
        if tx.payer_user_id else None
    )
    payer_name = _payer_label(payer)
    payer_phone = getattr(payer, "phone", None) if payer else None
    purpose = _format_purpose(tx.target_type)
    amount = float(tx.net_amount or tx.gross_amount or 0)
    currency = tx.currency_code or "TZS"
    method = (tx.provider_name or tx.method_type or "").strip() or None
    code = tx.transaction_code

    # ── 1. Confirm to the payer (skip contribution fan-out here; it is routed
    # by EventContributor.notify_target via _notify_event_contributor_payment_recorded).
    if (
        payer_phone
        and tx.target_type not in (
            PaymentTargetTypeEnum.wallet_topup,
            PaymentTargetTypeEnum.contribution,
        )
    ):
        try:
            sms_payment_confirmed_to_payer(
                phone=payer_phone, payer_name=payer_name,
                purpose=purpose, amount=float(tx.gross_amount or 0),
                currency=currency, transaction_code=code,
            )
        except Exception as e:
            print(f"[payments] sms_payment_confirmed_to_payer failed: {e}")

    if tx.target_type == PaymentTargetTypeEnum.contribution:
        _notify_event_contributor_payment_recorded(db, tx)

    # ── 2. Notify the recipient (specialised per target type)
    target_label = None
    try:
        if tx.target_type == PaymentTargetTypeEnum.wallet_topup:
            if payer and getattr(payer, "phone", None):
                sms_payment_received(
                    phone=payer.phone, payer_name=payer_name, purpose=purpose,
                    amount=amount, currency=currency, transaction_code=code,
                    payee_label="your Nuru wallet",
                )
            target_label = "wallet top-up"

        elif tx.target_type == PaymentTargetTypeEnum.contribution and tx.target_id:
            from models.events import Event
            event = db.query(Event).filter(Event.id == tx.target_id).first()
            organizer = (
                db.query(User).filter(User.id == event.organizer_id).first()
                if event and event.organizer_id else None
            )
            target_label = event.name if event else "event contribution"
            # Prefer the per-event display name the organiser stored for THIS
            # contributor on THIS event. The same global contributor can show
            # up as different names on different events; phone is the bridge.
            display_for_organizer = payer_name
            try:
                from models import EventContributor as _EC, UserContributor as _UC
                if event and payer and getattr(payer, "phone", None):
                    row = (
                        db.query(_EC, _UC)
                        .join(_UC, _UC.id == _EC.contributor_id)
                        .filter(_EC.event_id == event.id, _UC.phone == payer.phone)
                        .first()
                    )
                    if row:
                        ec_row, uc_row = row
                        ev_name = (getattr(ec_row, "display_name", None) or "").strip()
                        display_for_organizer = ev_name or (uc_row.name or payer_name)
            except Exception:
                pass
            if organizer and getattr(organizer, "phone", None):
                sms_organizer_contribution_received(
                    phone=organizer.phone,
                    organizer_name=_payer_label(organizer),
                    contributor_name=display_for_organizer,
                    event_title=event.name if event else "your event",
                    amount=amount, currency=currency, transaction_code=code,
                )

        elif tx.target_type == PaymentTargetTypeEnum.booking and tx.target_id:
            from models.bookings import ServiceBookingRequest
            from models import UserService
            booking = db.query(ServiceBookingRequest).filter(
                ServiceBookingRequest.id == tx.target_id
            ).first()
            service = (
                db.query(UserService).filter(UserService.id == booking.user_service_id).first()
                if booking and booking.user_service_id else None
            )
            vendor = (
                db.query(User).filter(User.id == service.user_id).first()
                if service and service.user_id else None
            )
            target_label = service.title if service else "service booking"
            if vendor and getattr(vendor, "phone", None):
                # Agreed/expected service amount = quoted_price (fallback proposed_price).
                service_amount = float(
                    (booking.quoted_price if booking and booking.quoted_price is not None else
                     (booking.proposed_price if booking else 0)) or 0
                )
                # Total paid to this booking so far = sum of successful credit
                # transactions for this booking target.
                try:
                    from sqlalchemy import func as _sa_func
                    total_paid = float(
                        db.query(_sa_func.coalesce(_sa_func.sum(Transaction.gross_amount), 0))
                        .filter(
                            Transaction.target_type == PaymentTargetTypeEnum.booking,
                            Transaction.target_id == tx.target_id,
                            Transaction.status == TransactionStatusEnum.success,
                        )
                        .scalar()
                        or 0
                    )
                except Exception:
                    total_paid = float(tx.gross_amount or 0)
                balance = max(0.0, service_amount - total_paid) if service_amount > 0 else 0.0
                sms_vendor_booking_paid(
                    phone=vendor.phone,
                    vendor_name=_payer_label(vendor),
                    client_name=payer_name,
                    service_title=service.title if service else "your service",
                    amount=amount, currency=currency, transaction_code=code,
                    service_amount=service_amount,
                    total_paid=total_paid,
                    balance=balance,
                )

        elif tx.beneficiary_user_id:
            recipient = db.query(User).filter(User.id == tx.beneficiary_user_id).first()
            if recipient and getattr(recipient, "phone", None):
                sms_payment_received(
                    phone=recipient.phone, payer_name=payer_name, purpose=purpose,
                    amount=amount, currency=currency, transaction_code=code,
                    payee_label="your Nuru account",
                )
    except Exception as e:
        print(f"[payments] beneficiary notify failed: {e}")

    # ── 3. Admin heads-up — always
    try:
        admin_phone = get_admin_notify_phone(db)
        sms_admin_payment_alert(
            phone=admin_phone, payer_name=payer_name, payer_phone=payer_phone,
            purpose=purpose, amount=float(tx.gross_amount or 0), currency=currency,
            transaction_code=code, method=method, target_label=target_label,
        )
    except Exception as e:
        print(f"[payments] sms_admin_payment_alert failed: {e}")

    # ── 4. Push notifications (FCM) to payer + beneficiary so the mobile
    # app surfaces "Payment received" / "Payment approved" instantly.
    try:
        from utils.fcm import send_push_async
        push_data = {
            "type": "payment_received",
            "transaction_code": code or "",
            "amount": str(amount),
            "currency": currency,
            "target_type": str(tx.target_type.value if hasattr(tx.target_type, "value") else tx.target_type),
            "reference_id": str(tx.target_id) if tx.target_id else "",
        }
        if tx.payer_user_id:
            send_push_async(
                db, tx.payer_user_id,
                title="Payment confirmed",
                body=f"Your {purpose} of {currency} {amount:,.0f} was successful.",
                data={**push_data, "type": "payment_confirmed"},
                high_priority=True,
                collapse_key=f"pay:{code or tx.id}",
            )
        if tx.beneficiary_user_id and str(tx.beneficiary_user_id) != str(tx.payer_user_id or ""):
            send_push_async(
                db, tx.beneficiary_user_id,
                title="Payment received",
                body=f"{payer_name} sent {currency} {amount:,.0f} ({purpose}).",
                data=push_data,
                high_priority=True,
                collapse_key=f"pay:{code or tx.id}",
            )
    except Exception as e:
        print(f"[payments] push notify failed: {e}")



# ──────────────────────────────────────────────
# Providers (dynamic, admin-managed)
# ──────────────────────────────────────────────

@router.get("/providers")
def list_providers(
    country_code: str = Query(..., min_length=2, max_length=2),
    purpose: str = Query("collection", regex="^(collection|payout)$"),
    db: Session = Depends(get_db),
):
    q = db.query(PaymentProvider).filter(
        PaymentProvider.country_code == country_code.upper(),
        PaymentProvider.is_active == True,  # noqa: E712
    )
    if purpose == "collection":
        q = q.filter(PaymentProvider.is_collection_enabled == True)  # noqa: E712
    else:
        q = q.filter(PaymentProvider.is_payout_enabled == True)  # noqa: E712
    rows = q.order_by(PaymentProvider.display_order, PaymentProvider.name).all()
    return api_response(True, "Providers retrieved.", [
        {
            "id": str(r.id),
            "country_code": r.country_code,
            "currency_code": r.currency_code,
            "provider_type": r.provider_type.value if r.provider_type else None,
            "name": r.name,
            "code": r.code,
            "logo_url": r.logo_url,
            "display_order": r.display_order,
        }
        for r in rows
    ])


# ──────────────────────────────────────────────
# Public fee preview
# ──────────────────────────────────────────────

@router.get("/fee-preview")
def fee_preview(
    country_code: str = Query(..., min_length=2, max_length=2),
    currency_code: str = Query(..., min_length=3, max_length=3),
    target_type: str = Query(...),
    gross_amount: float = Query(..., gt=0),
    db: Session = Depends(get_db),
):
    """Preview fees so the checkout UI can show 'You pay = amount + fee'.

    Top-ups never carry a commission; everything else adds the active
    `CommissionSetting` flat fee on top of the requested amount.
    """
    from services.commission_service import resolve_commission_snapshot, commission_amount_from_snapshot
    target_enum = _normalize_target_type(target_type)
    snap = resolve_commission_snapshot(db, country_code.upper(), currency_code.upper())
    fee = float(commission_amount_from_snapshot(snap))
    if target_enum == PaymentTargetTypeEnum.wallet_topup:
        fee = 0.0
    total = float(gross_amount) + fee
    return api_response(True, "Fee preview.", {
        "requested_amount": float(gross_amount),
        "commission_amount": fee,
        "total_charged": total,
        "currency_code": currency_code.upper(),
        "country_code": country_code.upper(),
        "target_type": target_enum.value,
    })


# ──────────────────────────────────────────────
# Initiate payment
# ──────────────────────────────────────────────

@router.post("/initiate", status_code=201)
async def initiate_payment(
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid request body.")

    # ─── Required fields
    target_type_raw = (payload.get("target_type") or "").strip()
    target_type = _normalize_target_type(target_type_raw)

    try:
        gross_amount = Decimal(str(payload.get("gross_amount") or "0"))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid gross_amount.")
    if gross_amount <= 0:
        raise HTTPException(status_code=400, detail="gross_amount must be > 0.")

    country_code = (payload.get("country_code") or "").upper().strip()
    currency_code = (payload.get("currency_code") or "").upper().strip()
    if not country_code or not currency_code:
        raise HTTPException(status_code=400, detail="country_code and currency_code are required.")

    method_type = (payload.get("method_type") or "").strip()
    if method_type not in ("mobile_money", "bank", "wallet"):
        raise HTTPException(status_code=400, detail="method_type must be mobile_money|bank|wallet.")

    payment_description = (payload.get("payment_description") or "").strip()
    if len(payment_description) < 8:
        raise HTTPException(
            status_code=400,
            detail="payment_description must be highly descriptive (min 8 chars).",
        )

    payment_channel = (payload.get("payment_channel") or "stk_push").strip()
    target_id = payload.get("target_id")
    try:
        target_id_uuid = uuid_lib.UUID(str(target_id)) if target_id else None
    except Exception:
        target_id_uuid = None

    beneficiary_user_id = payload.get("beneficiary_user_id")
    try:
        beneficiary_uuid = uuid_lib.UUID(str(beneficiary_user_id)) if beneficiary_user_id else None
    except Exception:
        beneficiary_uuid = None

    # ─── Auto-resolve / verify the beneficiary for targets where it's
    # deterministically derivable from `target_id`. This is defence-in-depth:
    # the client should send `beneficiary_user_id`, but if it forgets (or
    # sends the wrong user), the wallet credit at confirmation time would
    # silently no-op or land in the wrong wallet. We resolve from the DB and
    # OVERRIDE any client-supplied value that disagrees, logging a warning.
    resolved_beneficiary: Optional[uuid_lib.UUID] = None
    try:
        if target_type == PaymentTargetTypeEnum.booking and target_id_uuid:
            from models.bookings import ServiceBookingRequest
            from models import UserService
            booking = db.query(ServiceBookingRequest).filter(
                ServiceBookingRequest.id == target_id_uuid
            ).first()
            if booking and booking.user_service_id:
                svc = db.query(UserService).filter(
                    UserService.id == booking.user_service_id
                ).first()
                if svc and svc.user_id:
                    resolved_beneficiary = svc.user_id
        elif target_type == PaymentTargetTypeEnum.contribution and target_id_uuid:
            from models.events import Event
            ev = db.query(Event).filter(Event.id == target_id_uuid).first()
            if ev and ev.organizer_id:
                resolved_beneficiary = ev.organizer_id
    except Exception as e:
        print(f"[payments] beneficiary auto-resolve failed: {e}")

    if resolved_beneficiary:
        if beneficiary_uuid and beneficiary_uuid != resolved_beneficiary:
            print(
                f"[payments] client-supplied beneficiary_user_id "
                f"{beneficiary_uuid} disagrees with target-derived "
                f"{resolved_beneficiary}; using derived value."
            )
        beneficiary_uuid = resolved_beneficiary

    # Sanity: block self-pay only for bookings (paying yourself for your own
    # service makes no sense). Contributions are explicitly allowed — an
    # organizer is welcome to seed their own event, and the resulting wallet
    # credit (net of commission) is the expected behaviour.
    if (
        beneficiary_uuid
        and beneficiary_uuid == current_user.id
        and target_type == PaymentTargetTypeEnum.booking
    ):
        raise HTTPException(
            status_code=400,
            detail="You cannot pay yourself for this booking.",
        )

    # ─── Provider snapshot (optional but recommended)
    provider_id = payload.get("provider_id")
    provider = None
    if provider_id:
        try:
            provider = db.query(PaymentProvider).filter(
                PaymentProvider.id == uuid_lib.UUID(str(provider_id)),
                PaymentProvider.is_active == True,  # noqa: E712
            ).first()
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid provider_id.")
        if not provider or not provider.is_collection_enabled:
            raise HTTPException(status_code=400, detail="Provider not available for collection.")

    # ─── Server-side amount validation for tickets ───────────────────────
    # Defence against tampered client `gross_amount`. For ticket targets we
    # know the authoritative subtotal: it's the sum of `total_amount` across
    # the EventTicket row pointed to by `target_id` (plus its BULK siblings,
    # if any). Reject any request whose pre-commission amount disagrees.
    if target_type == PaymentTargetTypeEnum.ticket and target_id_uuid:
        primary_ticket = db.query(EventTicket).filter(
            EventTicket.id == target_id_uuid,
        ).first()
        if not primary_ticket:
            raise HTTPException(status_code=404, detail="Ticket not found.")
        if primary_ticket.buyer_user_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not your ticket.")
        ticket_rows = [primary_ticket]
        if primary_ticket.payment_ref and primary_ticket.payment_ref.startswith("BULK:"):
            siblings = db.query(EventTicket).filter(
                EventTicket.payment_ref == primary_ticket.payment_ref,
                EventTicket.id != primary_ticket.id,
            ).all()
            ticket_rows.extend(siblings)
        expected = sum(
            (Decimal(str(t.total_amount or 0)) for t in ticket_rows),
            Decimal("0"),
        )
        # Allow a tiny rounding tolerance (1 minor unit).
        if abs(expected - gross_amount) > Decimal("1"):
            print(
                f"[payments] ticket gross_amount mismatch: client={gross_amount} "
                f"expected={expected} ticket_id={primary_ticket.id} "
                f"user={current_user.id}"
            )
            raise HTTPException(
                status_code=400,
                detail="Payment amount does not match ticket order total.",
            )
        # Use the trusted, DB-derived amount for the rest of the flow.
        gross_amount = expected

    # ─── Build the transaction (with enriched, Nuru-branded description)
    enriched_description = _enrich_payment_description(

        target_type=target_type,
        user_supplied=payment_description,
        payer=current_user,
    )
    tx = create_transaction(
        db,
        payer_user_id=current_user.id,
        beneficiary_user_id=beneficiary_uuid,
        target_type=target_type,
        target_id=target_id_uuid,
        country_code=country_code,
        currency_code=currency_code,
        gross_amount=gross_amount,
        method_type=method_type,
        payment_description=enriched_description,
        provider_id=provider.id if provider else None,
        provider_name=provider.name if provider else None,
        payment_channel=payment_channel,
    )

    # ─── Branch by channel
    if payment_channel == "wallet_balance":
        # Pay from wallet — debit available, credit beneficiary if any.
        # NOTE: use `tx.gross_amount`, NOT the local `gross_amount` variable.
        # `create_transaction` inflates `gross_amount` by the commission for
        # non-topup targets so the payer is charged base + commission. The
        # local var still holds the pre-commission value the client sent.
        from services.wallet_service import debit_available
        payer_wallet = get_or_create_wallet(db, current_user.id, currency_code)
        try:
            debit_available(
                db, payer_wallet, Decimal(str(tx.gross_amount)),
                description=_ledger_text("Paid", tx, current_user),
                transaction_id=tx.id,
            )
        except ValueError as e:
            db.rollback()
            raise HTTPException(status_code=400, detail=str(e))

        if beneficiary_uuid:
            ben_wallet = get_or_create_wallet(db, beneficiary_uuid, currency_code)
            credit_available(
                db, ben_wallet, tx.net_amount,
                description=_ledger_text("Received", tx, current_user),
                transaction_id=tx.id,
            )
            if tx.commission_amount and tx.commission_amount > 0:
                commission_charge(
                    db, ben_wallet, tx.commission_amount,
                    description=_ledger_text("Commission", tx, current_user),
                    transaction_id=tx.id,
                )

        now = datetime.utcnow()
        tx.status = TransactionStatusEnum.credited
        tx.confirmed_at = now
        tx.completed_at = now
        _sync_target_after_payment(db, tx)
        _notify_payment_received(db, tx)
        db.commit()
        db.refresh(tx)
        return api_response(True, "Wallet payment completed.", {
            "transaction": _serialize_tx(tx),
            "next_action": "completed",
        })

    if method_type == "mobile_money":
        phone = PaymentGateway.normalize_phone_number(
            (payload.get("phone_number") or "").strip(),
            country_code,
        )
        if not phone:
            db.rollback()
            raise HTTPException(status_code=400, detail="phone_number is required for mobile money.")
        network_key = PaymentGateway.identify_network(phone, country_code)
        if network_key == "UNKNOWN":
            db.rollback()
            raise HTTPException(status_code=400, detail="Unsupported phone number network.")

        # IMPORTANT: charge the payer the *post-commission* total. `tx.gross_amount`
        # has already been inflated by the commission (see create_transaction);
        # the local `gross_amount` variable still holds the pre-commission value
        # the client sent. Sending the local value would push only the base
        # amount via STK and Nuru would absorb the commission.
        charge_amount = Decimal(str(tx.gross_amount))

        attempt = MobilePaymentAttempt(
            transaction_id=tx.id,
            gateway="SASAPAY",
            provider_name=provider.name if provider else network_key,
            network_code=PaymentGateway.gateway_code_for(network_key, country_code),
            phone_number=phone,
            amount=charge_amount,
        )
        db.add(attempt)
        db.flush()

        try:
            resp = await gateway.request_payment(
                phone_number=phone,
                amount=float(charge_amount),
                description=payment_description,
                merchant_request_id=str(attempt.id),
                country_code=country_code,
                currency=currency_code,
            )
        except HTTPException:
            db.rollback()
            raise
        except Exception as e:
            db.rollback()
            raise HTTPException(status_code=502, detail=f"Payment gateway error: {e}")

        attempt.merchant_request_id = resp.get("MerchantRequestID", "")
        attempt.checkout_request_id = resp.get("CheckoutRequestID", "")
        attempt.transaction_reference = resp.get("TransactionReference", "")
        attempt.response_payload = resp

        tx.status = TransactionStatusEnum.processing
        tx.external_reference = attempt.checkout_request_id or attempt.merchant_request_id
        tx.api_request_payload_snapshot = resp.get("_request_payload")
        tx.api_response_payload_snapshot = {k: v for k, v in resp.items() if k != "_request_payload"}
        db.commit()
        db.refresh(tx)

        return api_response(True, "Payment request sent. Confirm on your phone.", {
            "transaction": _serialize_tx(tx),
            "checkout_request_id": attempt.checkout_request_id,
            "next_action": "poll_status",
        })

    # bank — manual settlement for now
    db.commit()
    db.refresh(tx)
    return api_response(True, "Bank transfer recorded. Awaiting confirmation.", {
        "transaction": _serialize_tx(tx),
        "next_action": "manual_confirm",
    })


# ──────────────────────────────────────────────
# Status polling
# ──────────────────────────────────────────────

async def _try_credit_beneficiary(db: Session, tx: Transaction):
    """Idempotent wallet credit.

    BUSINESS RULE: Wallet balances are reserved for explicit top-ups.
    Contributions, ticket purchases, service bookings, and other transfers
    flow through Nuru collection accounts and are surfaced to the
    beneficiary in dedicated "Received Payments" views — they MUST NOT
    inflate `Wallet.available_balance`.

    Only `wallet_topup` transactions credit a wallet here.
    """
    if tx.status == TransactionStatusEnum.credited:
        return

    # Only top-ups touch the wallet.
    if tx.target_type != PaymentTargetTypeEnum.wallet_topup:
        return

    recipient_id = tx.payer_user_id  # top-up payer == beneficiary
    if not recipient_id:
        return

    payer = (
        db.query(User).filter(User.id == tx.payer_user_id).first()
        if tx.payer_user_id else None
    )
    ben_wallet = get_or_create_wallet(db, recipient_id, tx.currency_code)
    credit_available(
        db, ben_wallet, Decimal(str(tx.net_amount or 0)),
        description=_ledger_text("Top-up", tx, payer),
        transaction_id=tx.id,
    )
    if tx.commission_amount and Decimal(str(tx.commission_amount)) > 0:
        commission_charge(
            db, ben_wallet, Decimal(str(tx.commission_amount)),
            description=_ledger_text("Commission", tx, payer),
            transaction_id=tx.id,
        )


def _resolve_tx(db: Session, identifier: str) -> Optional[Transaction]:
    """Look up a transaction by UUID or by human-readable transaction_code."""
    try:
        tid = uuid_lib.UUID(identifier)
        tx = db.query(Transaction).filter(Transaction.id == tid).first()
        if tx:
            return tx
    except (ValueError, AttributeError):
        pass
    return (
        db.query(Transaction)
        .filter(Transaction.transaction_code == identifier)
        .first()
    )


def _resolve_offline_receipt(db: Session, identifier: str) -> Optional[dict]:
    """Resolve an offline-confirmed payment (ticket claim or contribution)
    by its transaction_code and return it shaped like a Transaction so the
    /wallet/receipt UI renders it identically to a gateway payment.

    Falls back to None when nothing matches — callers should treat this as
    "no receipt available".
    """
    from models.ticket_offline_claims import TicketOfflineClaim
    from models.contributions import (
        EventContribution, EventContributor, UserContributor,
    )
    from models.events import Event as _Event
    from models.references import Currency as _Currency
    from models.enums import ContributionStatusEnum

    def _event_currency_code(event: Optional[_Event]) -> str:
        if event and getattr(event, "currency_id", None):
            cur = (
                db.query(_Currency)
                .filter(_Currency.id == event.currency_id)
                .first()
            )
            if cur and getattr(cur, "code", None):
                return cur.code.strip()
        return "TZS"

    # 1. Offline ticket claim
    claim = (
        db.query(TicketOfflineClaim)
        .filter(
            TicketOfflineClaim.transaction_code == identifier,
            TicketOfflineClaim.status == "confirmed",
        )
        .first()
    )
    if claim:
        event = (
            db.query(_Event).filter(_Event.id == claim.event_id).first()
            if claim.event_id else None
        )
        confirmed_at = (
            claim.reviewed_at.isoformat() if getattr(claim, "reviewed_at", None) else None
        )
        description = (
            f"Ticket · {event.name}" if event and event.name
            else "Ticket payment"
        )
        return {
            "id": f"oc-tkt-{claim.id}",
            "transaction_code": claim.transaction_code or f"OFFLINE-{str(claim.id)[:8].upper()}",
            "target_type": PaymentTargetTypeEnum.ticket.value,
            "target_id": str(claim.issued_ticket_id) if claim.issued_ticket_id else None,
            "country_code": getattr(event, "country_code", None) if event else None,
            "currency_code": _event_currency_code(event),
            "gross_amount": float(claim.amount or 0),
            "commission_amount": 0.0,
            "net_amount": float(claim.amount or 0),
            "method_type": claim.payment_channel,
            "provider_name": claim.provider_name,
            "payment_channel": claim.payment_channel,
            "external_reference": claim.transaction_code,
            "payment_description": description,
            "status": TransactionStatusEnum.credited.value,
            "failure_reason": None,
            "initiated_at": claim.created_at.isoformat() if getattr(claim, "created_at", None) else confirmed_at,
            "confirmed_at": confirmed_at,
            "completed_at": confirmed_at,
            "_payer_user_id": claim.claimant_user_id,
            "_beneficiary_user_id": getattr(event, "organizer_id", None) if event else None,
        }

    # 2. Offline contribution payment
    contrib = (
        db.query(EventContribution)
        .filter(
            EventContribution.transaction_ref == identifier,
            EventContribution.payment_channel.isnot(None),
            EventContribution.confirmation_status == ContributionStatusEnum.confirmed,
        )
        .first()
    )
    if contrib:
        event = (
            db.query(_Event).filter(_Event.id == contrib.event_id).first()
            if contrib.event_id else None
        )
        ec = (
            db.query(EventContributor)
            .filter(EventContributor.id == contrib.event_contributor_id)
            .first()
            if contrib.event_contributor_id else None
        )
        contributor = (
            db.query(UserContributor)
            .filter(UserContributor.id == ec.contributor_id)
            .first()
            if ec else None
        )
        confirmed_at = (
            contrib.confirmed_at.isoformat() if contrib.confirmed_at else None
        )
        description = (
            f"Contribution · {event.name}" if event and event.name
            else "Event contribution"
        )
        return {
            "id": f"oc-con-{contrib.id}",
            "transaction_code": contrib.transaction_ref or f"OFFLINE-{str(contrib.id)[:8].upper()}",
            "target_type": PaymentTargetTypeEnum.contribution.value,
            "target_id": str(contrib.event_id) if contrib.event_id else None,
            "country_code": getattr(event, "country_code", None) if event else None,
            "currency_code": _event_currency_code(event),
            "gross_amount": float(contrib.amount or 0),
            "commission_amount": 0.0,
            "net_amount": float(contrib.amount or 0),
            "method_type": contrib.payment_channel,
            "provider_name": contrib.provider_name,
            "payment_channel": contrib.payment_channel,
            "external_reference": contrib.transaction_ref,
            "payment_description": description,
            "status": TransactionStatusEnum.credited.value,
            "failure_reason": None,
            "initiated_at": contrib.contributed_at.isoformat() if contrib.contributed_at else confirmed_at,
            "confirmed_at": confirmed_at,
            "completed_at": confirmed_at,
            "_payer_user_id": getattr(contributor, "user_id", None) if contributor else None,
            "_beneficiary_user_id": getattr(event, "organizer_id", None) if event else None,
        }

    return None



@router.get("/{transaction_id}/status")
async def transaction_status(
    transaction_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    tx = _resolve_tx(db, transaction_id)
    if not tx:
        # Fallback: offline-confirmed payments aren't in the Transaction
        # table. Resolve them from the offline-claim tables and return the
        # same shape so the receipt UI renders identically.
        offline = _resolve_offline_receipt(db, transaction_id)
        if offline:
            payer = offline.pop("_payer_user_id", None)
            beneficiary = offline.pop("_beneficiary_user_id", None)
            if current_user.id not in (payer, beneficiary):
                raise HTTPException(status_code=403, detail="Forbidden.")
            return api_response(True, "Transaction status.", offline)
        raise HTTPException(status_code=404, detail="Transaction not found.")
    if tx.payer_user_id != current_user.id and tx.beneficiary_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")

    if tx.status in (TransactionStatusEnum.paid, TransactionStatusEnum.credited):
        _sync_target_after_payment(db, tx)
        db.commit()
        db.refresh(tx)
        return api_response(True, "Transaction status.", _serialize_tx(tx))

    # Poll the gateway for any non-terminal mobile-money txn. We also re-poll
    # `failed` txns: gateways occasionally flip late callbacks from FAILED →
    # PAID (user retried PIN), and admins/users explicitly clicking "Refresh"
    # expect us to reconcile with the source of truth.
    attempt = (
        db.query(MobilePaymentAttempt)
        .filter(MobilePaymentAttempt.transaction_id == tx.id)
        .order_by(MobilePaymentAttempt.created_at.desc())
        .first()
    )
    repollable = (
        TransactionStatusEnum.processing,
        TransactionStatusEnum.pending,
        TransactionStatusEnum.failed,
    )
    if attempt and attempt.checkout_request_id and tx.status in repollable:
        gw_status, gw_reason = await gateway.check_transaction_status_detail(
            attempt.checkout_request_id
        )
        now = datetime.utcnow()
        if gw_status == "PAID":
            attempt.status = "paid"
            tx.status = TransactionStatusEnum.paid
            tx.confirmed_at = now
            tx.failure_reason = None  # clear stale failure note on late success
            await _try_credit_beneficiary(db, tx)
            _sync_target_after_payment(db, tx)
            tx.status = TransactionStatusEnum.credited
            tx.completed_at = now
            _notify_payment_received(db, tx)
            db.commit()
            db.refresh(tx)
        elif gw_status == "FAILED":
            attempt.status = "failed"
            tx.status = TransactionStatusEnum.failed
            tx.failure_reason = (
                _clean_failure_reason(gw_reason)
                or _failure_reason_from_callbacks(db, tx, attempt)
                or "Gateway reported failure (no reason returned)."
            )
            db.commit()
            db.refresh(tx)
        else:
            # gw_status == PENDING — the status-query was an async ack OR the
            # gateway is still mid-flight. Even so, a real C2B callback may
            # already have landed on /payments/callback for this checkout.
            # Lift `ResultDesc` from the most recent non-success callback so
            # users clicking "Refresh" see why their payment failed instead
            # of "Your request has been received…".
            cb_reason = _failure_reason_from_callbacks(db, tx, attempt)
            if cb_reason:
                if tx.status != TransactionStatusEnum.failed:
                    tx.status = TransactionStatusEnum.failed
                    attempt.status = "failed"
                if cb_reason != tx.failure_reason:
                    tx.failure_reason = cb_reason
                db.commit()
                db.refresh(tx)

    return api_response(True, "Transaction status.", _serialize_tx(tx))


# ──────────────────────────────────────────────
# Public receipt — no auth, safe subset only
# Used by the /shared/receipt/:code link recipients can open without an account.
# ──────────────────────────────────────────────

@router.get("/public/{transaction_code}")
def public_receipt(transaction_code: str, db: Session = Depends(get_db)):
    tx = (
        db.query(Transaction)
        .filter(Transaction.transaction_code == transaction_code)
        .first()
    )
    if tx:
        # Only successful payments are shareable — pending/failed receipts
        # leak nothing meaningful and could be abused for phishing.
        if tx.status not in (TransactionStatusEnum.paid, TransactionStatusEnum.credited):
            raise HTTPException(status_code=404, detail="Receipt not available.")
        safe = _serialize_tx(tx)
        safe.pop("failure_reason", None)
        return api_response(True, "Public receipt.", safe)

    # Offline-confirmed payment fallback (ticket claim or contribution).
    offline = _resolve_offline_receipt(db, transaction_code)
    if offline:
        offline.pop("_payer_user_id", None)
        offline.pop("_beneficiary_user_id", None)
        offline.pop("failure_reason", None)
        return api_response(True, "Public receipt.", offline)

    raise HTTPException(status_code=404, detail="Receipt not found.")



@router.get("/my-transactions")
def my_transactions(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    role: str = Query("all", regex="^(all|payer|beneficiary)$"),
    target_type: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(Transaction)
    if role == "payer":
        q = q.filter(Transaction.payer_user_id == current_user.id)
    elif role == "beneficiary":
        q = q.filter(Transaction.beneficiary_user_id == current_user.id)
    else:
        q = q.filter(
            (Transaction.payer_user_id == current_user.id)
            | (Transaction.beneficiary_user_id == current_user.id)
        )

    if target_type:
        try:
            tt_enum = _normalize_target_type(target_type)
            q = q.filter(Transaction.target_type == tt_enum)
        except HTTPException:
            pass  # ignore invalid filter rather than 400 the wallet UI

    if status:
        try:
            q = q.filter(Transaction.status == TransactionStatusEnum(status))
        except ValueError:
            pass

    q = q.order_by(Transaction.created_at.desc())
    items, pagination = paginate(q, page=page, limit=limit)
    return api_response(True, "Transactions retrieved.", {
        "transactions": [_serialize_tx(t) for t in items],
        "pagination": pagination,
    })


# ──────────────────────────────────────────────
# Aggregated Payment History (mobile + web)
# Returns: total_spent, percent_change_vs_previous_period,
#          per-category counts and a paginated list of transactions
#          for the requested category. "Promotions" / "Ads" return an
#          empty list with a friendly empty-state — those money flows
#          do not yet pass through the unified Transaction table.
# ──────────────────────────────────────────────


_HISTORY_CATEGORY_TO_TARGET = {
    "tickets": PaymentTargetTypeEnum.ticket,
    "contributions": PaymentTargetTypeEnum.contribution,
    "vendors": PaymentTargetTypeEnum.booking,
}

_HISTORY_VIRTUAL_CATEGORIES = {"promotions", "ads"}


def _history_base_query(db: Session, user_id):
    """All payer-side transactions for this user that count as 'spent'.
    We exclude wallet_topup / withdrawal / settlement which aren't actual
    purchases the user would expect to see in 'Payment History'.
    """
    return db.query(Transaction).filter(
        Transaction.payer_user_id == user_id,
        Transaction.target_type.in_([
            PaymentTargetTypeEnum.ticket,
            PaymentTargetTypeEnum.contribution,
            PaymentTargetTypeEnum.booking,
        ]),
    )


def _history_paid_only(q):
    return q.filter(
        Transaction.status.in_([
            TransactionStatusEnum.paid,
            TransactionStatusEnum.credited,
        ])
    )


@router.get("/history")
def payment_history(
    category: str = Query("all", regex="^(all|tickets|contributions|vendors|promotions|ads)$"),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Aggregated payment-history feed used by the mobile Payment History
    screen. Computes:
        - total_spent (paid + credited only) for the *current* 30-day window
        - percent_change vs the prior 30-day window
        - per-category counts (for tab badges)
        - paginated list of transactions for the selected category
    """
    from sqlalchemy import func as sa_func
    from datetime import timedelta

    now = datetime.utcnow()
    window_start = now - timedelta(days=30)
    prev_window_start = now - timedelta(days=60)

    base_paid = _history_paid_only(_history_base_query(db, current_user.id))

    # ── Total Spent (last 30 days) ──────────────────────────────────
    current_total = (
        base_paid.filter(Transaction.created_at >= window_start)
        .with_entities(sa_func.coalesce(sa_func.sum(Transaction.gross_amount), 0))
        .scalar()
    ) or 0
    previous_total = (
        base_paid.filter(
            Transaction.created_at >= prev_window_start,
            Transaction.created_at < window_start,
        )
        .with_entities(sa_func.coalesce(sa_func.sum(Transaction.gross_amount), 0))
        .scalar()
    ) or 0

    if float(previous_total) > 0:
        percent_change = round(
            ((float(current_total) - float(previous_total)) / float(previous_total)) * 100,
            1,
        )
    else:
        percent_change = 100.0 if float(current_total) > 0 else 0.0

    # ── Lifetime totals (used for the big "Total Spent" card) ───────
    lifetime_total = (
        base_paid.with_entities(sa_func.coalesce(sa_func.sum(Transaction.gross_amount), 0))
        .scalar()
    ) or 0
    lifetime_count = base_paid.with_entities(sa_func.count(Transaction.id)).scalar() or 0

    # ── Per-category counts (tab badges) ────────────────────────────
    counts = {"tickets": 0, "contributions": 0, "vendors": 0, "promotions": 0, "ads": 0}
    rows = (
        _history_base_query(db, current_user.id)
        .with_entities(Transaction.target_type, sa_func.count(Transaction.id))
        .group_by(Transaction.target_type)
        .all()
    )
    for tt, c in rows:
        if tt == PaymentTargetTypeEnum.ticket:
            counts["tickets"] = int(c)
        elif tt == PaymentTargetTypeEnum.contribution:
            counts["contributions"] = int(c)
        elif tt == PaymentTargetTypeEnum.booking:
            counts["vendors"] = int(c)
    counts["all"] = counts["tickets"] + counts["contributions"] + counts["vendors"]

    # ── Paginated list for the active category ──────────────────────
    if category in _HISTORY_VIRTUAL_CATEGORIES:
        # No payment flow exists yet for promotions/ads — return empty list.
        return api_response(True, "Payment history retrieved.", {
            "category": category,
            "summary": {
                "total_spent": float(lifetime_total),
                "transaction_count": int(lifetime_count),
                "currency_code": _user_currency_code(current_user),
                "percent_change_30d": percent_change,
                "current_period_total": float(current_total),
                "previous_period_total": float(previous_total),
            },
            "counts": counts,
            "transactions": [],
            "pagination": {"page": 1, "limit": limit, "total": 0, "total_pages": 0},
            "empty_reason": "no_promotion_payments_yet",
        })

    list_q = _history_base_query(db, current_user.id)
    if category != "all":
        list_q = list_q.filter(
            Transaction.target_type == _HISTORY_CATEGORY_TO_TARGET[category]
        )
    list_q = list_q.order_by(Transaction.created_at.desc())
    items, pagination = paginate(list_q, page=page, limit=limit)

    return api_response(True, "Payment history retrieved.", {
        "category": category,
        "summary": {
            "total_spent": float(lifetime_total),
            "transaction_count": int(lifetime_count),
            "currency_code": _user_currency_code(current_user),
            "percent_change_30d": percent_change,
            "current_period_total": float(current_total),
            "previous_period_total": float(previous_total),
        },
        "counts": counts,
        "transactions": [_serialize_tx(t) for t in items],
        "pagination": pagination,
    })


def _user_currency_code(user: User) -> str:
    """Best-effort currency code for the payer."""
    cc = (getattr(user, "country_code", None) or "").upper()
    if cc == "TZ":
        return "TZS"
    if cc == "KE":
        return "KES"
    return "TZS"


# ──────────────────────────────────────────────
# ──────────────────────────────────────────────
# Webhook (no auth — idempotent)
#
# SasaPay sends TWO independent server-to-server notifications:
#   1. C2B Callback Results — POSTed to the per-request CallBackURL we send
#      with `request-payment`. Confirms the STK push outcome.
#   2. Instant Payment Notification (IPN) — POSTed to the merchant-wide IPN
#      URL configured on the SasaPay dashboard whenever a payment lands on
#      the merchant wallet. Used for till/paybill walk-ins and back-office
#      reconciliation. Field shape is different from the callback above.
#
# Both endpoints are idempotent: every payload is logged raw to
# PaymentCallbackLog, and a transaction can never be credited twice.
# ──────────────────────────────────────────────


def _resolve_attempt_from_payload(db: Session, payload: dict) -> Optional[MobilePaymentAttempt]:
    """Find the originating attempt for a webhook payload by trying every
    identifier SasaPay might echo back to us."""
    candidates_checkout = [
        payload.get("CheckoutRequestID"),
        payload.get("CheckoutRequestId"),
        payload.get("checkout_request_id"),
    ]
    for cid in candidates_checkout:
        if not cid:
            continue
        attempt = db.query(MobilePaymentAttempt).filter(
            MobilePaymentAttempt.checkout_request_id == cid
        ).first()
        if attempt:
            return attempt

    # Fall back to MerchantRequestID / our own AccountReference (== attempt.id)
    candidates_merchant = [
        payload.get("MerchantRequestID"),
        payload.get("MerchantRequestId"),
        payload.get("BillRefNumber"),
        payload.get("AccountReference"),
    ]
    for mid in candidates_merchant:
        if not mid:
            continue
        attempt = db.query(MobilePaymentAttempt).filter(
            MobilePaymentAttempt.merchant_request_id == str(mid)
        ).first()
        if attempt:
            return attempt
        # Our AccountReference is attempt.id — try that too.
        try:
            tid = uuid_lib.UUID(str(mid))
            attempt = db.query(MobilePaymentAttempt).filter(
                MobilePaymentAttempt.id == tid
            ).first()
            if attempt:
                return attempt
        except (ValueError, AttributeError):
            pass
    return None


def _capture_callback_fields(attempt: MobilePaymentAttempt, payload: dict) -> None:
    """Persist all SasaPay C2B callback fields onto the attempt row.

    Spec fields:
      MerchantRequestID, CheckoutRequestID, PaymentRequestID, ResultCode,
      ResultDesc, SourceChannel, TransAmount, RequestedAmount, Paid,
      BillRefNumber, TransactionDate, CustomerMobile, TransactionCode,
      ThirdPartyTransID
    """
    def _g(*keys):
        for k in keys:
            v = payload.get(k)
            if v not in (None, ""):
                return v
        return None

    def _dec(v):
        if v in (None, ""):
            return None
        try:
            return Decimal(str(v))
        except Exception:
            return None

    if not attempt.checkout_request_id:
        attempt.checkout_request_id = _g("CheckoutRequestID", "CheckoutRequestId")
    if not attempt.merchant_request_id:
        attempt.merchant_request_id = _g("MerchantRequestID", "MerchantRequestId")
    pr = _g("PaymentRequestID", "PaymentRequestId")
    if pr:
        attempt.payment_request_id = str(pr)
    sc = _g("SourceChannel", "PaymentMethod")
    if sc:
        attempt.source_channel = str(sc)
    br = _g("BillRefNumber")
    if br:
        attempt.bill_ref_number = str(br)
    cm = _g("CustomerMobile", "MSISDN")
    if cm:
        attempt.customer_mobile = str(cm)
    td = _g("TransactionDate", "TransTime")
    if td:
        attempt.transaction_date = str(td)
    rc = payload.get("ResultCode")
    if rc not in (None, ""):
        attempt.result_code = str(rc)
    rd = _g("ResultDesc", "ResultDescription")
    if rd:
        attempt.result_desc = str(rd)
    tpt = _g("ThirdPartyTransID")
    if tpt:
        attempt.third_party_trans_id = str(tpt)
    ra = _dec(_g("RequestedAmount"))
    if ra is not None:
        attempt.requested_amount = ra
    pa = _dec(_g("TransAmount", "PaidAmount"))
    if pa is not None:
        attempt.paid_amount = pa


async def _apply_successful_payment(db: Session, tx: Transaction, attempt: MobilePaymentAttempt,
                                     payload: dict) -> None:
    """Shared success path: idempotently credit + notify."""
    if tx.status in (TransactionStatusEnum.paid, TransactionStatusEnum.credited):
        return
    now = datetime.utcnow()
    attempt.status = "paid"
    _capture_callback_fields(attempt, payload)
    # Persist gateway transaction codes for support/audit if SasaPay sent them.
    sasa_code = (
        payload.get("TransactionCode")
        or payload.get("TransID")
        or payload.get("ThirdPartyTransID")
    )
    if sasa_code and not attempt.transaction_reference:
        attempt.transaction_reference = str(sasa_code)
    if sasa_code:
        tx.external_reference = tx.external_reference or str(sasa_code)
    tx.status = TransactionStatusEnum.paid
    tx.confirmed_at = now
    tx.failure_reason = None
    tx.callback_payload_snapshot = payload
    await _try_credit_beneficiary(db, tx)
    _sync_target_after_payment(db, tx)
    tx.status = TransactionStatusEnum.credited
    tx.completed_at = now
    _notify_payment_received(db, tx)


@router.post("/callback")
async def payment_callback(request: Request, db: Session = Depends(get_db)):
    """SasaPay C2B Callback — invoked once per `request-payment` outcome.

    Spec sample::

        {
          "MerchantRequestID": "Test callbacks",
          "CheckoutRequestID": "542011ce-…-c4df09e18d74",
          "PaymentRequestID":  "PR6**3",
          "ResultCode": "0",
          "ResultDesc": "Transaction processed successfully.",
          "SourceChannel": "M-PESA",
          "TransAmount": "1.00",
          "BillRefNumber": "Test callbacks",
          "TransactionDate": "20240701105155",
          "CustomerMobile": "25470******0",
          "TransactionCode": "SPEJ***0O78GY2T",
          "ThirdPartyTransID": "SG1****1T5G"
        }

    The presence of ``Paid`` in our older payload shape is also tolerated
    so older SasaPay sandbox responses keep working.
    """
    try:
        payload = await request.json()
    except Exception:
        return {"status": "error", "message": "Invalid payload"}

    checkout_id = (
        payload.get("CheckoutRequestID")
        or payload.get("CheckoutRequestId")
        or payload.get("checkout_request_id")
        or ""
    )

    log = PaymentCallbackLog(
        gateway="SASAPAY_C2B",
        checkout_request_id=str(checkout_id) if checkout_id else None,
        payload=payload,
        headers={k: v for k, v in request.headers.items()},
        processed=False,
    )
    db.add(log)
    db.flush()

    attempt = _resolve_attempt_from_payload(db, payload)
    if not attempt:
        log.processing_error = "No matching attempt for callback payload."
        db.commit()
        # Always 200 OK — SasaPay retries on non-2xx and we have logged it.
        return {"status": "ok"}

    tx = db.query(Transaction).filter(Transaction.id == attempt.transaction_id).first()
    log.transaction_id = tx.id if tx else None

    result_code = str(payload.get("ResultCode", "")).strip()
    # `Paid` is older shape; current spec uses ResultCode == "0" alone.
    paid_raw = payload.get("Paid")
    paid_flag = paid_raw is True or str(paid_raw).strip().lower() == "true"
    success = result_code == "0" and (paid_flag or paid_raw is None)

    if tx and success:
        await _apply_successful_payment(db, tx, attempt, payload)
        log.processed = True
    elif tx and result_code and result_code != "0":
        attempt.status = "failed"
        _capture_callback_fields(attempt, payload)
        tx.status = TransactionStatusEnum.failed
        tx.failure_reason = (
            _clean_failure_reason(payload.get("ResultDesc"))
            or _clean_failure_reason(payload.get("ResultDescription"))
            or f"Gateway error (code {result_code})."
        )
        tx.callback_payload_snapshot = payload
        log.processed = True

    db.commit()
    return {"status": "ok"}


@router.post("/ipn")
async def payment_ipn(request: Request, db: Session = Depends(get_db)):
    """SasaPay Instant Payment Notification — back-office reconciliation.

    Spec sample::

        {
          "MerchantCode": "6****8",
          "BusinessShortCode": "6****8",
          "InvoiceNumber": "INV-278-RID-6754",
          "PaymentMethod": "SasaPay",
          "TransID": "CDVISAIHD",
          "ThirdPartyTransID": "7***2",
          "FullName": "John kym Doe",
          "FirstName": "John", "MiddleName": "kym", "LastName": "Doe",
          "TransactionType": "C2B",
          "MSISDN": "2547*****5",
          "OrgAccountBalance": "10.00",
          "TransAmount": "10.00",
          "TransTime": "20240703062353",
          "BillRefNumber": "12345"
        }

    IPNs may arrive for payments that didn't originate from one of OUR
    request-payment calls (e.g. paybill walk-ins). When we can match
    `BillRefNumber` to a known transaction we credit it; otherwise we just
    log the payload so admins can reconcile manually.
    """
    try:
        payload = await request.json()
    except Exception:
        return {"status": "error", "message": "Invalid payload"}

    log = PaymentCallbackLog(
        gateway="SASAPAY_IPN",
        checkout_request_id=None,
        payload=payload,
        headers={k: v for k, v in request.headers.items()},
        processed=False,
    )
    db.add(log)
    db.flush()

    attempt = _resolve_attempt_from_payload(db, payload)
    if attempt:
        tx = db.query(Transaction).filter(Transaction.id == attempt.transaction_id).first()
        log.transaction_id = tx.id if tx else None
        if tx:
            await _apply_successful_payment(db, tx, attempt, payload)
            log.processed = True
    else:
        log.processing_error = "IPN with no matching attempt — manual reconcile."

    db.commit()
    return {"status": "ok"}


# ──────────────────────────────────────────────
# Admin / ops — inspect raw gateway callbacks
#
# Every inbound POST to /payments/callback and /payments/ipn is persisted
# to the `payment_callback_logs` table BEFORE we try to process it. These
# endpoints expose those rows so support can answer "did the gateway ever
# call us back?" and "what reason did the gateway give?".
# ──────────────────────────────────────────────

from api.routes.admin import require_admin  # noqa: E402  (avoid circular at import)
from models.admin import AdminUser  # noqa: E402


def _serialize_callback_log(log: PaymentCallbackLog) -> dict:
    return {
        "id": str(log.id),
        "gateway": log.gateway,
        "checkout_request_id": log.checkout_request_id,
        "transaction_id": str(log.transaction_id) if log.transaction_id else None,
        "processed": bool(log.processed),
        "processing_error": log.processing_error,
        "received_at": _iso_utc(getattr(log, "received_at", None)),
        "payload": log.payload,
        "headers": log.headers,
    }


@router.get("/admin/webhook-logs")
def admin_list_webhook_logs(
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    gateway_filter: Optional[str] = Query(None, alias="gateway"),
    processed: Optional[bool] = Query(None),
    checkout_request_id: Optional[str] = Query(None),
    transaction_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin),
):
    """List recent SasaPay callback / IPN payloads for ops debugging."""
    q = db.query(PaymentCallbackLog)
    if gateway_filter:
        q = q.filter(PaymentCallbackLog.gateway == gateway_filter)
    if processed is not None:
        q = q.filter(PaymentCallbackLog.processed == processed)
    if checkout_request_id:
        q = q.filter(PaymentCallbackLog.checkout_request_id == checkout_request_id)
    if transaction_id:
        try:
            q = q.filter(PaymentCallbackLog.transaction_id == uuid_lib.UUID(transaction_id))
        except Exception:
            pass

    total = q.count()
    rows = (
        q.order_by(PaymentCallbackLog.received_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )
    return api_response(True, "Webhook logs.", {
        "items": [_serialize_callback_log(r) for r in rows],
        "total": total,
        "page": page,
        "limit": limit,
    })


@router.get("/admin/webhook-logs/by-transaction/{transaction_id}")
def admin_logs_for_transaction(
    transaction_id: str,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin),
):
    """Return all callback rows tied to a given transaction (chronological).

    Includes rows matched via `transaction_id` AND rows whose
    `checkout_request_id` matches any attempt of this transaction — so even
    callbacks that arrived before we could link them appear here.
    """
    try:
        tx_uuid = uuid_lib.UUID(transaction_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid transaction id.")

    checkout_ids = [
        a.checkout_request_id for a in
        db.query(MobilePaymentAttempt)
        .filter(MobilePaymentAttempt.transaction_id == tx_uuid)
        .all()
        if a.checkout_request_id
    ]

    from sqlalchemy import or_  # local import keeps top of file clean
    conds = [PaymentCallbackLog.transaction_id == tx_uuid]
    if checkout_ids:
        conds.append(PaymentCallbackLog.checkout_request_id.in_(checkout_ids))

    rows = (
        db.query(PaymentCallbackLog)
        .filter(or_(*conds))
        .order_by(PaymentCallbackLog.received_at.asc())
        .all()
    )
    return api_response(True, "Callback logs for transaction.",
                        [_serialize_callback_log(r) for r in rows])


# ──────────────────────────────────────────────
# Pending-transaction background verifier
#
# A user-facing endpoint (`/payments/pending`) returns the caller's stale
# pending transactions so the browser/mobile client can poll status one by
# one. A separate worker endpoint (`/payments/verify-pending`) re-checks
# every stale transaction in the system — wired to a cron / Celery beat
# later but exposed now so the same reconciliation logic runs server-side.
#
# "Stale" = non-terminal status AND created more than VERIFY_AFTER_SECONDS
# ago. Terminal statuses (paid / credited / failed / cancelled) are
# excluded.
# ──────────────────────────────────────────────

VERIFY_AFTER_SECONDS = 30
VERIFY_MAX_AGE_HOURS = 24

_NON_TERMINAL = (
    TransactionStatusEnum.pending,
    TransactionStatusEnum.processing,
)


@router.get("/pending")
def my_pending_transactions(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Pending transactions older than VERIFY_AFTER_SECONDS for the caller.

    The browser polls this every 15s; for each row returned it should call
    `/payments/{id}/status` which already drives gateway re-poll + credit.
    """
    from datetime import timedelta
    cutoff_old = datetime.utcnow() - timedelta(seconds=VERIFY_AFTER_SECONDS)
    cutoff_max = datetime.utcnow() - timedelta(hours=VERIFY_MAX_AGE_HOURS)
    rows = (
        db.query(Transaction)
        .filter(
            Transaction.payer_user_id == current_user.id,
            Transaction.status.in_(_NON_TERMINAL),
            Transaction.created_at <= cutoff_old,
            Transaction.created_at >= cutoff_max,
        )
        .order_by(Transaction.created_at.asc())
        .limit(20)
        .all()
    )
    return api_response(True, "Pending transactions.", {
        "transactions": [{
            "id": str(t.id),
            "transaction_code": t.transaction_code,
            "status": t.status.value if t.status else None,
            "target_type": t.target_type.value if t.target_type else None,
            "created_at": _iso_utc(t.created_at),
        } for t in rows],
    })


@router.post("/verify-pending")
async def verify_pending_transactions(
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """Worker entrypoint — re-poll every stale pending tx with the gateway.

    Public + unauthenticated for now (cron will be inside the VPS). Wrap
    with admin auth or shared-secret header when exposing externally.
    """
    from datetime import timedelta
    cutoff_old = datetime.utcnow() - timedelta(seconds=VERIFY_AFTER_SECONDS)
    cutoff_max = datetime.utcnow() - timedelta(hours=VERIFY_MAX_AGE_HOURS)

    txs = (
        db.query(Transaction)
        .filter(
            Transaction.status.in_(_NON_TERMINAL),
            Transaction.created_at <= cutoff_old,
            Transaction.created_at >= cutoff_max,
        )
        .order_by(Transaction.created_at.asc())
        .limit(limit)
        .all()
    )

    checked = 0
    promoted = 0
    failed = 0

    for tx in txs:
        attempt = (
            db.query(MobilePaymentAttempt)
            .filter(MobilePaymentAttempt.transaction_id == tx.id)
            .order_by(MobilePaymentAttempt.created_at.desc())
            .first()
        )
        if not attempt or not attempt.checkout_request_id:
            continue
        try:
            gw_status, gw_reason = await gateway.check_transaction_status_detail(
                attempt.checkout_request_id
            )
        except Exception as e:  # gateway hiccup — try again next tick
            print(f"[verify-pending] gateway error for {tx.transaction_code}: {e}")
            continue

        checked += 1
        now = datetime.utcnow()
        if gw_status == "PAID":
            attempt.status = "paid"
            tx.status = TransactionStatusEnum.paid
            tx.confirmed_at = now
            tx.failure_reason = None
            await _try_credit_beneficiary(db, tx)
            _sync_target_after_payment(db, tx)
            tx.status = TransactionStatusEnum.credited
            tx.completed_at = now
            try:
                _notify_payment_received(db, tx)
            except Exception as e:
                print(f"[verify-pending] notify failed for {tx.transaction_code}: {e}")
            promoted += 1
        elif gw_status == "FAILED":
            attempt.status = "failed"
            tx.status = TransactionStatusEnum.failed
            tx.failure_reason = (
                _clean_failure_reason(gw_reason)
                or _failure_reason_from_callbacks(db, tx, attempt)
                or "Gateway reported failure (no reason returned)."
            )
            failed += 1
        # else: still in flight — leave alone
        db.commit()

    return api_response(True, "Pending verification swept.", {
        "scanned": len(txs),
        "checked": checked,
        "promoted": promoted,
        "failed": failed,
    })
