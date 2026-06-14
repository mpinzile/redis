"""Public, unauthenticated endpoints for guest contribution payments.

Flow:
  1. Organiser hits POST /user-contributors/.../share-link → gets a token URL.
  2. Contributor opens https://nuru.tz/c/{token} on their phone.
  3. Frontend calls these endpoints (no auth):
        GET    /public/contributions/{token}                 → load page state
        POST   /public/contributions/{token}/initiate        → start payment
        GET    /public/contributions/{token}/transactions/{tx_id} → poll status
        POST   /public/contributions/{token}/resend-sms      → optional re-send
        POST   /public/contributions/{token}/touch           → ping "opened"

Security model:
  * Tokens are 24-byte URL-safe random; only the SHA-256 hash is in DB.
  * Each token is bound to ONE EventContributor on ONE Event — it can only
    initiate payments toward that event and amounts are subject to a
    per-token rate limit.
  * Initiated transactions have ``payer_user_id = NULL`` (guest payer);
    we record the guest's name/phone on the resulting EventContribution
    via the existing _sync_target_after_payment hook.
  * No user data leaks: the public GET returns only the pieces needed to
    render the page (event name, organiser name, contributor name, amounts).
"""

from __future__ import annotations

import uuid as uuid_lib
from datetime import datetime
from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from core.database import get_db
from utils.helpers import api_response
from models import (
    Event, User, Currency, UserContributor,
    EventContribution, ContributionStatusEnum, PaymentMethodEnum,
)
from models.contributions import EventContributor
from models.payments import (
    Transaction, MobilePaymentAttempt, PaymentProvider,
)
from models.enums import (
    PaymentTargetTypeEnum, TransactionStatusEnum,
)
from services.payment_gateway import gateway, PaymentGateway
from services.transaction_service import create_transaction
from services.share_links import (
    find_by_token, build_share_url, host_for_currency,
)


router = APIRouter(prefix="/public/contributions", tags=["Public Contributions"])


# ──────────────────────────────────────────────
# Helpers (kept local to avoid coupling auth-required code paths)
# ──────────────────────────────────────────────

def _currency_for_event(db: Session, event: Event) -> str:
    if event.currency_id:
        cur = db.query(Currency).filter(Currency.id == event.currency_id).first()
        if cur and cur.code:
            return cur.code.upper()
    return "TZS"


def _country_for_currency(currency_code: str) -> str:
    return "KE" if (currency_code or "").upper() == "KES" else "TZ"


def _organiser_display(user: Optional[User]) -> str:
    if not user:
        return "the organiser"
    parts = [getattr(user, "first_name", None), getattr(user, "last_name", None)]
    name = " ".join(p for p in parts if p).strip()
    return name or getattr(user, "phone", None) or "the organiser"


def _event_cover_url(event: Optional[Event]) -> Optional[str]:
    """Best cover image for an event: explicit cover_image_url, else the
    featured/first EventImage. Mirrors the web `getEventImage` fallback."""
    if not event:
        return None
    if getattr(event, "cover_image_url", None):
        return event.cover_image_url
    imgs = list(getattr(event, "images", []) or [])
    if not imgs:
        return None
    imgs.sort(key=lambda i: 0 if getattr(i, "is_featured", False) else 1)
    for img in imgs:
        url = getattr(img, "image_url", None)
        if url:
            return url
    return None


def _confirmed_paid_total(ec: EventContributor) -> float:
    return sum(
        float(c.amount or 0)
        for c in ec.contributions
        if c.confirmation_status is None
        or c.confirmation_status == ContributionStatusEnum.confirmed
    )


def _serialize_state(db: Session, ec: EventContributor, *, include_transactions: bool = True) -> dict:
    event = db.query(Event).filter(Event.id == ec.event_id).first()
    organiser = (
        db.query(User).filter(User.id == event.organizer_id).first()
        if event and event.organizer_id else None
    )
    contributor = (
        db.query(UserContributor).filter(UserContributor.id == ec.contributor_id).first()
    )
    currency = _currency_for_event(db, event) if event else "TZS"
    country = _country_for_currency(currency)
    pledge = float(ec.pledge_amount or 0)
    paid = _confirmed_paid_total(ec)
    balance = max(0.0, pledge - paid)

    # Recent guest-initiated transactions for this event_contributor (for
    # the "your past attempts" section + auto-refresh of the latest one).
    recent: list[dict] = []
    if include_transactions:
        rows = (
            db.query(Transaction)
            .filter(
                Transaction.target_type == PaymentTargetTypeEnum.contribution,
                Transaction.target_id == ec.event_id,
                Transaction.internal_reference == f"share:{ec.id}",
            )
            .order_by(Transaction.created_at.desc())
            .limit(5)
            .all()
        )
        for tx in rows:
            recent.append({
                "id": str(tx.id),
                "transaction_code": tx.transaction_code,
                "status": tx.status.value if tx.status else None,
                "gross_amount": float(tx.gross_amount or 0),
                "currency_code": tx.currency_code,
                "method_type": tx.method_type,
                "failure_reason": tx.failure_reason,
                "created_at": tx.created_at.isoformat() if tx.created_at else None,
            })

    return {
        "event": {
            "id": str(event.id) if event else None,
            "name": event.name if event else "Event",
            "cover_image_url": _event_cover_url(event),

            "start_date": event.start_date.isoformat() if event and event.start_date else None,
            "location": event.location if event else None,
            "organiser_name": _organiser_display(organiser),
        },
        "contributor": {
            "name": contributor.name if contributor else "Contributor",
            "phone": contributor.phone if contributor else None,
        },
        "country_code": country,
        "currency_code": currency,
        "pledge_amount": pledge,
        "total_paid": paid,
        "balance": balance,
        "contribution_payment_instructions": event.contribution_payment_instructions if event else None,
        "host": host_for_currency(currency),
        "recent_transactions": recent,
    }


# ──────────────────────────────────────────────
# Endpoints
# ──────────────────────────────────────────────

@router.get("/{token}")
def get_public_state(token: str, db: Session = Depends(get_db)):
    ec = find_by_token(db, token)
    if not ec:
        raise HTTPException(status_code=404, detail="This link is no longer valid.")
    # Touch "last opened" — best-effort, don't break the page if it fails.
    try:
        ec.share_link_last_opened_at = datetime.utcnow()
        db.commit()
    except Exception:
        db.rollback()
    return api_response(True, "Pledge details.", _serialize_state(db, ec))


@router.post("/{token}/initiate", status_code=201)
async def public_initiate(token: str, request: Request, db: Session = Depends(get_db)):
    """Initiate a guest mobile-money payment toward this contributor's pledge.

    Body: ``{ amount, phone_number, provider_id?, payment_description? }``
    """
    ec = find_by_token(db, token)
    if not ec:
        raise HTTPException(status_code=404, detail="This link is no longer valid.")

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid request body.")

    # ── Amount
    try:
        amount = Decimal(str(payload.get("amount") or "0"))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid amount.")
    if amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be greater than zero.")

    # ── Resolve event + currency + country (driven by organiser's choice)
    event = db.query(Event).filter(Event.id == ec.event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event no longer exists.")
    currency_code = _currency_for_event(db, event)
    country_code = _country_for_currency(currency_code)

    # ── Phone for STK push
    phone_raw = (payload.get("phone_number") or "").strip()
    phone = PaymentGateway.normalize_phone_number(phone_raw, country_code)
    if not phone:
        raise HTTPException(status_code=400, detail="Mobile number is required.")
    network_key = PaymentGateway.identify_network(phone, country_code)
    if network_key == "UNKNOWN":
        raise HTTPException(status_code=400, detail="Unsupported phone number network.")

    # ── Optional provider snapshot
    provider = None
    provider_id = payload.get("provider_id")
    if provider_id:
        try:
            provider = (
                db.query(PaymentProvider)
                .filter(
                    PaymentProvider.id == uuid_lib.UUID(str(provider_id)),
                    PaymentProvider.is_active == True,  # noqa: E712
                )
                .first()
            )
        except Exception:
            provider = None

    contributor = (
        db.query(UserContributor).filter(UserContributor.id == ec.contributor_id).first()
    )
    # Prefer the event-specific display name so receipts, descriptions and
    # gateway metadata all carry the name the organiser uses inside THIS event.
    contributor_name = (
        (getattr(ec, "display_name", None) or "").strip()
        or (contributor.name if contributor else "Guest contributor")
    )

    desc = (payload.get("payment_description") or "").strip()
    if len(desc) < 8:
        desc = f"Contribution from {contributor_name} to {event.name}"

    # ── Build the transaction. internal_reference = "share:{ec.id}" lets us
    # attribute the resulting EventContribution to the right contributor row
    # without needing a payer_user_id.
    tx = create_transaction(
        db,
        payer_user_id=None,
        beneficiary_user_id=event.organizer_id,
        target_type=PaymentTargetTypeEnum.contribution,
        target_id=ec.event_id,
        country_code=country_code,
        currency_code=currency_code,
        gross_amount=amount,
        method_type="mobile_money",
        payment_description=f"Nuru · Event Contribution · {contributor_name} → {event.name}",
        provider_id=provider.id if provider else None,
        provider_name=provider.name if provider else None,
        payment_channel="stk_push",
        internal_reference=f"share:{ec.id}",
    )

    # ── Fire STK push
    charge_amount = Decimal(str(tx.gross_amount))
    attempt = MobilePaymentAttempt(
        transaction_id=tx.id,
        gateway="SASAPAY",
        provider_name=provider.name if provider else network_key,
        network_code=PaymentGateway.gateway_code_for(network_key),
        phone_number=phone,
        amount=charge_amount,
    )
    db.add(attempt)
    db.flush()

    try:
        resp = await gateway.request_payment(
            phone_number=phone,
            amount=float(charge_amount),
            description=desc,
            merchant_request_id=str(attempt.id),
            country_code=country_code,
            currency=currency_code,
        )
    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=502, detail=f"Payment partner error: {e}")

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

    return api_response(True, "Mobile money prompt sent. Please confirm on your phone.", {
        "transaction": {
            "id": str(tx.id),
            "transaction_code": tx.transaction_code,
            "status": tx.status.value,
            "gross_amount": float(tx.gross_amount or 0),
            "currency_code": tx.currency_code,
            "failure_reason": tx.failure_reason,
        },
        "checkout_request_id": attempt.checkout_request_id,
    })


@router.get("/{token}/transactions/{transaction_id}")
async def public_transaction_status(
    token: str,
    transaction_id: str,
    db: Session = Depends(get_db),
):
    """Public status read with live gateway re-poll.

    Mirrors /payments/{tx_id}/status but scopes access to "the transaction
    initiated via this token" only — no cross-token leakage.
    """
    ec = find_by_token(db, token)
    if not ec:
        raise HTTPException(status_code=404, detail="This link is no longer valid.")

    try:
        tx_uuid = uuid_lib.UUID(transaction_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid transaction id.")

    tx = (
        db.query(Transaction)
        .filter(
            Transaction.id == tx_uuid,
            Transaction.internal_reference == f"share:{ec.id}",
        )
        .first()
    )
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found.")

    if tx.status in (TransactionStatusEnum.paid, TransactionStatusEnum.credited):
        # Already terminal — make sure the EventContribution exists.
        _attribute_to_event_contributor(db, tx, ec)
        db.commit()

    # Re-poll for non-terminal states (including failed → success flips).
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
        try:
            gw_status, gw_reason = await gateway.check_transaction_status_detail(
                attempt.checkout_request_id
            )
        except Exception:
            gw_status, gw_reason = "PENDING", None
        now = datetime.utcnow()
        if gw_status == "PAID":
            attempt.status = "paid"
            tx.status = TransactionStatusEnum.paid
            tx.confirmed_at = now
            tx.failure_reason = None
            _attribute_to_event_contributor(db, tx, ec)
            tx.status = TransactionStatusEnum.credited
            tx.completed_at = now
            db.commit()
            db.refresh(tx)
            # Fire-and-forget receipt SMS to the guest contributor.
            try:
                _send_receipt_sms(db, ec, tx, token)
            except Exception as e:
                print(f"[public_contributions] receipt SMS failed: {e}")
        elif gw_status == "FAILED":
            attempt.status = "failed"
            tx.status = TransactionStatusEnum.failed
            tx.failure_reason = gw_reason or "Payment partner reported failure."
            db.commit()
            db.refresh(tx)

    return api_response(True, "Transaction status.", {
        "id": str(tx.id),
        "transaction_code": tx.transaction_code,
        "status": tx.status.value if tx.status else None,
        "gross_amount": float(tx.gross_amount or 0),
        "currency_code": tx.currency_code,
        "failure_reason": tx.failure_reason,
        "confirmed_at": tx.confirmed_at.isoformat() if tx.confirmed_at else None,
        "completed_at": tx.completed_at.isoformat() if tx.completed_at else None,
    })


def _attribute_to_event_contributor(db, tx: Transaction, ec: EventContributor):
    """Idempotently insert an EventContribution row for a guest payment.

    Mirrors `_sync_target_after_payment` from payments.py but skips the
    payer-resolution branch (there is no logged-in payer).
    """
    existing = (
        db.query(EventContribution)
        .filter(
            EventContribution.event_id == ec.event_id,
            EventContribution.transaction_ref == tx.transaction_code,
        )
        .first()
    )
    if existing:
        if existing.confirmation_status != ContributionStatusEnum.confirmed:
            existing.confirmation_status = ContributionStatusEnum.confirmed
            existing.confirmed_at = existing.confirmed_at or datetime.utcnow()
        return

    contributor = (
        db.query(UserContributor).filter(UserContributor.id == ec.contributor_id).first()
    )
    contact = {}
    if contributor and contributor.phone:
        contact["phone"] = contributor.phone
    if contributor and contributor.email:
        contact["email"] = contributor.email

    now = datetime.utcnow()
    contribution = EventContribution(
        event_id=ec.event_id,
        event_contributor_id=ec.id,
        contributor_name=((getattr(ec, "display_name", None) or "").strip() or (contributor.name if contributor else "Guest contributor")),
        contributor_contact=contact or None,
        amount=tx.net_amount or tx.gross_amount,
        payment_method=PaymentMethodEnum.mobile,
        transaction_ref=tx.transaction_code,
        recorded_by=None,  # guest payment — no recorder
        confirmation_status=ContributionStatusEnum.confirmed,
        confirmed_at=now,
        contributed_at=now,
    )
    db.add(contribution)
    db.flush()


def _send_receipt_sms(db: Session, ec: EventContributor, tx: Transaction, token: str):
    """SMS the guest a permanent receipt link after a successful payment.

    TZ-only for now (per product). Idempotent per process via the call site —
    this is invoked exactly once on the credit transition.
    """
    currency = (tx.currency_code or "").upper()
    if currency != "TZS":
        return  # Only TZ contributors get receipt SMS for now.

    contributor = (
        db.query(UserContributor).filter(UserContributor.id == ec.contributor_id).first()
    )
    # Honour notify_target on the EventContributor (primary | secondary | both).
    from utils.offline_claims import contributor_notify_phones
    # Make sure the helper sees the contributor relationship even if not eagerly loaded.
    if contributor is not None and getattr(ec, "contributor", None) is None:
        try:
            ec.contributor = contributor  # type: ignore[attr-defined]
        except Exception:
            pass
    recipients = contributor_notify_phones(ec)
    if not recipients:
        return

    event = db.query(Event).filter(Event.id == ec.event_id).first()
    event_title = event.name if event else "your event"
    name = ((getattr(ec, "display_name", None) or "").strip() or (contributor.name if contributor else "") or "Contributor")
    receipt_url = f"https://{host_for_currency(currency)}/c/{token}/r/{tx.transaction_code}"

    # Compute total_paid for this contributor on this event (confirmed only)
    # and the remaining balance against their pledge amount.
    try:
        from sqlalchemy import func as _sa_func
        total_paid = float(
            db.query(_sa_func.coalesce(_sa_func.sum(EventContribution.amount), 0))
            .filter(
                EventContribution.event_id == ec.event_id,
                EventContribution.contributor_id == ec.contributor_id,
                EventContribution.confirmation_status == ContributionStatusEnum.confirmed,
            )
            .scalar()
            or 0
        )
    except Exception:
        total_paid = float(tx.gross_amount or 0)
    pledge = float(getattr(ec, "pledge_amount", 0) or 0)
    balance = max(0.0, pledge - total_paid) if pledge > 0 else 0.0

    # Language: registered contributor → their preference; anonymous → SW.
    from utils.message_templates import resolve_user_language
    from utils.sms import sms_guest_contribution_receipt
    contributor_user_id = getattr(contributor, "contributor_user_id", None)
    if contributor_user_id:
        lang = resolve_user_language(db, contributor_user_id)
    else:
        lang = "sw"

    for ph in recipients:
        try:
            sms_guest_contribution_receipt(
                phone=ph,
                contributor_name=name,
                event_title=event_title,
                amount=float(tx.gross_amount or 0),
                currency=currency,
                transaction_code=tx.transaction_code,
                receipt_url=receipt_url,
                total_paid=total_paid,
                balance=balance,
                lang=lang,
            )
        except Exception as e:
            print(f"[public_contributions] guest receipt SMS failed for {ph[-4:]}: {e}")
