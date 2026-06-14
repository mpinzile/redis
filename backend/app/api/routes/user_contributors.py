# User Contributors Routes - /user-contributors/...
# Handles personal contributor address book & event contributor management

import math
import uuid
from datetime import datetime
from typing import Optional

import pytz
from fastapi import APIRouter, Depends, Body, Query, File, Form, UploadFile, Request, BackgroundTasks
from sqlalchemy import func as sa_func, or_, and_, text
from sqlalchemy.orm import Session, joinedload, selectinload

from core.database import get_db
from models import (
    UserContributor, EventContributor, EventContribution,
    ContributionThankYouMessage,
    Event, EventImage, User, Currency,
    EventCommitteeMember, CommitteePermission,
    PaymentMethodEnum, ContributionStatusEnum,
    EventMessagingTemplate,
)
from utils.auth import get_current_user
from utils.helpers import standard_response, format_phone_display
from utils.validation_functions import validate_phone_number
from utils.event_owner import get_event_owner_display_name

EAT = pytz.timezone("Africa/Nairobi")

router = APIRouter(prefix="/user-contributors", tags=["User Contributors"])


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

def _wa_block(wa: Optional[dict]) -> dict:
    """Always emit the same three WhatsApp fields so the frontend has a
    stable shape (defaults to 'unknown' when we have no cached row yet)."""
    if not wa:
        return {
            "whatsapp_status": "unknown",
            "is_whatsapp": None,
            "whatsapp_last_checked_at": None,
        }
    return {
        "whatsapp_status": wa.get("whatsapp_status") or "unknown",
        "is_whatsapp": wa.get("is_whatsapp"),
        "whatsapp_last_checked_at": wa.get("whatsapp_last_checked_at"),
    }


def _contributor_dict(c: UserContributor, wa_map: Optional[dict] = None,
                      nuru_user_map: Optional[dict] = None) -> dict:
    """Serialize a UserContributor. Enriches with linked Nuru user (avatar +
    flag) so the mobile address book can show real profile pictures whenever
    the contributor has a Nuru account. Resolution order:
      1. The persisted contributor_user_id FK (loaded relationship)
      2. nuru_user_map: phone -> {id, profile_picture_url, name} prepared by
         the caller via a single batched query (avoids N+1).
    """
    from utils.phone_numbers import normalize_phone
    wa_primary = None
    wa_secondary = None
    if wa_map:
        if c.phone:
            n = normalize_phone(c.phone).get("normalized")
            wa_primary = wa_map.get(n) if n else None
        sp = getattr(c, "secondary_phone", None)
        if sp:
            n2 = normalize_phone(sp).get("normalized")
            wa_secondary = wa_map.get(n2) if n2 else None

    linked_user = None
    try:
        linked_user = c.contributor_user
    except Exception:
        linked_user = None
    if linked_user is None and nuru_user_map and c.phone:
        key = _normalize_phone_digits(c.phone)
        if key:
            linked_user = nuru_user_map.get(key)

    nuru_user_id = None
    avatar_url = None
    if linked_user is not None:
        nuru_user_id = str(getattr(linked_user, "id", "") or "") or None
        avatar_url = getattr(linked_user, "profile_picture_url", None) or \
            getattr(linked_user, "provider_avatar_url", None)

    return {
        "id": str(c.id),
        "user_id": str(c.user_id),
        "contributor_user_id": str(c.contributor_user_id) if c.contributor_user_id else nuru_user_id,
        "name": c.name,
        "email": c.email,
        "phone": c.phone,
        "notes": c.notes,
        # Address-book defaults (comms-only). NEVER used to map a Nuru user.
        "secondary_phone": getattr(c, "secondary_phone", None),
        "notify_target": getattr(c, "notify_target", None) or "primary",
        "created_at": c.created_at.isoformat() if c.created_at else None,
        "updated_at": c.updated_at.isoformat() if c.updated_at else None,
        # Linked Nuru-account enrichment (avatar + flag for the mobile address book).
        "is_nuru_user": linked_user is not None,
        "avatar_url": avatar_url,
        "nuru_user": ({
            "id": nuru_user_id,
            "avatar_url": avatar_url,
            "name": getattr(linked_user, "full_name", None) or getattr(linked_user, "name", None),
        } if linked_user is not None else None),
        # WhatsApp availability (cached; never blocks request path)
        **_wa_block(wa_primary),
        "secondary_whatsapp": _wa_block(wa_secondary) if getattr(c, "secondary_phone", None) else None,
    }


def _build_nuru_user_map(db: Session, contribs) -> dict:
    """Batch-resolve Nuru users for a list of contributors by last-9-digit
    phone match. Returns {last9_digits: User}. Skips contributors that
    already have contributor_user_id set."""
    digits = set()
    for c in contribs:
        if getattr(c, "contributor_user_id", None):
            continue
        p = getattr(c, "phone", None)
        if not p:
            continue
        d = _normalize_phone_digits(p)
        if d:
            digits.add(d)
    if not digits:
        return {}
    from sqlalchemy import func as _f
    rows = db.query(User).filter(
        User.phone.isnot(None),
        _f.right(_f.regexp_replace(User.phone, r'[^0-9]', '', 'g'), 9).in_(list(digits)),
    ).all()
    out = {}
    for u in rows:
        d = _normalize_phone_digits(u.phone or "")
        if d and d not in out:
            out[d] = u
    return out


def _normalize_phone_digits(phone: str) -> str:
    """Return last 9 digits of a phone for cross-format matching."""
    if not phone:
        return ""
    digits = "".join(ch for ch in phone if ch.isdigit())
    return digits[-9:] if len(digits) >= 9 else digits


def _find_user_by_phone(db: Session, phone: str):
    """Find a registered Nuru User whose phone matches (last-9-digit comparison)."""
    if not phone:
        return None
    target = _normalize_phone_digits(phone)
    if not target:
        return None
    from sqlalchemy import func as _f
    matches = db.query(User).filter(
        User.phone.isnot(None),
        _f.right(_f.regexp_replace(User.phone, r'[^0-9]', '', 'g'), 9) == target,
    ).limit(1).all()
    return matches[0] if matches else None


def _collect_contributor_phones(contribs) -> list:
    phones = []
    for c in contribs:
        p = getattr(c, "phone", None)
        sp = getattr(c, "secondary_phone", None)
        if p:
            phones.append(p)
        if sp:
            phones.append(sp)
    return phones


def _event_contributor_dict(ec: EventContributor, show_recorder: bool = False,
                            wa_map: Optional[dict] = None) -> dict:
    total_paid = sum(float(c.amount or 0) for c in ec.contributions if c.confirmation_status is None or c.confirmation_status == ContributionStatusEnum.confirmed)
    pledge = float(ec.pledge_amount or 0)
    has_link = bool(getattr(ec, "share_token_hash", None)) and not getattr(ec, "share_token_revoked_at", None)
    # Event-specific display name override. Falls back to the global
    # ``user_contributors.name`` so legacy rows continue to render. We also
    # override ``contributor.name`` in the serialised payload so every
    # existing consumer (lists, reports, exports, payment logs) automatically
    # shows the per-event name — while preserving the original under
    # ``contributor.global_name`` for picker UIs that still want it.
    global_name = ec.contributor.name if ec.contributor else None
    display_name = (getattr(ec, "display_name", None) or "").strip() or global_name
    contributor_payload = _contributor_dict(ec.contributor, wa_map=wa_map) if ec.contributor else None
    if contributor_payload is not None:
        contributor_payload["global_name"] = global_name
        contributor_payload["name"] = display_name or contributor_payload.get("name")
    return {
        "id": str(ec.id),
        "event_id": str(ec.event_id),
        "contributor_id": str(ec.contributor_id),
        "contributor": contributor_payload,
        "display_name": display_name,
        "global_name": global_name,
        "pledge_amount": pledge,
        "total_paid": total_paid,
        "balance": max(0.0, pledge - total_paid),
        "notes": ec.notes,
        # Secondary contact + notification routing (comms-only).
        "secondary_phone": getattr(ec, "secondary_phone", None),
        "notify_target": getattr(ec, "notify_target", None) or "primary",
        "has_share_link": has_link,
        "share_link_last_opened_at": ec.share_link_last_opened_at.isoformat() if getattr(ec, "share_link_last_opened_at", None) else None,
        "share_link_sms_last_sent_at": ec.share_link_sms_last_sent_at.isoformat() if getattr(ec, "share_link_sms_last_sent_at", None) else None,
        "created_at": ec.created_at.isoformat() if ec.created_at else None,
        "updated_at": ec.updated_at.isoformat() if ec.updated_at else None,
    }



# ──────────────────────────────────────────────
# Aggregate Contribution Receipt — QR Verification
# ──────────────────────────────────────────────
# A signed, opaque token that encodes (event_id, user_id, issued_at).
# Used for the QR on the aggregate contribution receipt so an organiser
# (or anyone with the token) can verify the totals are authentic.

import base64
import hmac
import hashlib
import json as _json
from core.config import SECRET_KEY as _SECRET

_VERIFY_TOKEN_VERSION = "v1"


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(data: str) -> bytes:
    pad = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + pad)


def _sign_contribution_token(event_id: str, user_id: str) -> str:
    payload = {
        "v": _VERIFY_TOKEN_VERSION,
        "e": str(event_id),
        "u": str(user_id),
        "t": int(datetime.utcnow().timestamp()),
    }
    body = _b64url_encode(_json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    sig = hmac.new(
        (_SECRET or "nuru-dev").encode("utf-8"),
        body.encode("ascii"),
        hashlib.sha256,
    ).digest()
    return f"{body}.{_b64url_encode(sig)[:32]}"


def _verify_contribution_token(token: str) -> Optional[dict]:
    try:
        body, sig = token.split(".", 1)
        expected = hmac.new(
            (_SECRET or "nuru-dev").encode("utf-8"),
            body.encode("ascii"),
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(sig, _b64url_encode(expected)[:32]):
            return None
        return _json.loads(_b64url_decode(body))
    except Exception:
        return None


def _aggregate_summary_for(db: Session, user_id: uuid.UUID, event_id: uuid.UUID) -> Optional[dict]:
    """Compute the same aggregate the receipt shows: pledge / paid /
    pending / balance for a (user, event) pair, including phone-mapped
    contributor rows. Returns None if no contributor record exists."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        return None
    me_phone_digits = _normalize_phone_digits(user.phone) if getattr(user, "phone", None) else ""
    contribs = db.query(UserContributor).filter(
        UserContributor.contributor_user_id == user.id
    ).all()
    if me_phone_digits:
        from sqlalchemy import func as _f
        legacy = db.query(UserContributor).filter(
            UserContributor.contributor_user_id.is_(None),
            UserContributor.phone.isnot(None),
            _f.right(_f.regexp_replace(UserContributor.phone, r'[^0-9]', '', 'g'), 9) == me_phone_digits,
        ).all()
        contribs.extend(legacy)
    if not contribs:
        return None
    contributor_ids = list({c.id for c in contribs})

    ev = db.query(Event).filter(Event.id == event_id).first()
    if not ev:
        return None
    currency = "TZS"
    if ev.currency_id:
        cur = db.query(Currency).filter(Currency.id == ev.currency_id).first()
        if cur:
            currency = cur.code.strip()

    ecs = db.query(EventContributor).options(joinedload(EventContributor.contributions)).filter(
        EventContributor.event_id == event_id,
        EventContributor.contributor_id.in_(contributor_ids),
    ).all()

    pledge = sum(float(ec.pledge_amount or 0) for ec in ecs)
    paid = 0.0
    pending = 0.0
    last_at = None
    payment_count = 0
    for ec in ecs:
        for p in ec.contributions:
            amt = float(p.amount or 0)
            if p.confirmation_status == ContributionStatusEnum.pending:
                pending += amt
            else:
                paid += amt
            payment_count += 1
            d = p.contributed_at or p.confirmed_at or p.created_at
            if d and (last_at is None or d > last_at):
                last_at = d
    balance = max(0.0, pledge - paid - pending)

    return {
        "event_id": str(ev.id),
        "event_name": ev.name,
        "event_cover_image": getattr(ev, "cover_image_url", None),
        "contributor_name": (f"{user.first_name or ''} {user.last_name or ''}".strip() or user.phone or "Contributor"),
        "currency": currency,
        "total_pledged": round(pledge, 2),
        "total_paid": round(paid, 2),
        "total_pending": round(pending, 2),
        "balance": round(balance, 2),
        "payment_count": payment_count,
        "is_complete": pledge > 0 and balance == 0 and pending == 0,
        "last_contribution_at": last_at.isoformat() if last_at else None,
    }


@router.get("/my-contributions/{event_id}/verify-token")
def get_aggregate_verify_token(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Issue a signed token for the current user's aggregate contribution
    receipt for an event. Embedded into the QR code on the receipt."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    summary = _aggregate_summary_for(db, current_user.id, eid)
    if summary is None:
        return standard_response(False, "No contributions found for this event")

    token = _sign_contribution_token(event_id, str(current_user.id))
    return standard_response(True, "Token issued", {
        "token": token,
        "verify_url": f"https://nuru.tz/verify/contribution/{token}",
        "summary": summary,
    })


@router.get("/contributions/verify/{token}")
def verify_contribution_token(
    token: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Resolve an aggregate-receipt verification token and return the
    authoritative summary. Auth-required: only Nuru users (typically the
    organiser scanning the QR) can verify."""
    payload = _verify_contribution_token(token)
    if not payload:
        return standard_response(False, "Invalid or tampered token")
    try:
        eid = uuid.UUID(payload["e"])
        uid = uuid.UUID(payload["u"])
    except Exception:
        return standard_response(False, "Malformed token payload")

    summary = _aggregate_summary_for(db, uid, eid)
    if summary is None:
        return standard_response(False, "No contribution record matches this token")

    issued_at = payload.get("t")
    summary["issued_at"] = (
        datetime.utcfromtimestamp(issued_at).isoformat() + "Z" if issued_at else None
    )
    summary["verified"] = True
    return standard_response(True, "Verified", summary)



def _get_event_access(db: Session, event_id, current_user) -> tuple:
    """Returns (event, is_creator, committee_member_or_None, permissions_or_None)"""
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        return None, False, None, None
    is_creator = str(event.organizer_id) == str(current_user.id)
    if is_creator:
        return event, True, None, None
    cm = db.query(EventCommitteeMember).filter(
        EventCommitteeMember.event_id == event_id,
        EventCommitteeMember.user_id == current_user.id,
    ).first()
    if not cm:
        return event, False, None, None
    perms = db.query(CommitteePermission).filter(
        CommitteePermission.committee_member_id == cm.id
    ).first()
    return event, False, cm, perms


def _currency_code(db: Session, event: Event) -> str:
    if event.currency_id:
        cur = db.query(Currency).filter(Currency.id == event.currency_id).first()
        if cur:
            return cur.code.strip()
    return "TZS"


# ══════════════════════════════════════════════
# ADDRESS BOOK (UserContributor CRUD)
# ══════════════════════════════════════════════

@router.get("/")
def get_all_contributors(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    sort_by: Optional[str] = Query("name"),
    sort_order: Optional[str] = Query("asc"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(UserContributor).options(
        joinedload(UserContributor.contributor_user)
    ).filter(UserContributor.user_id == current_user.id)

    if search:
        like = f"%{search}%"
        q = q.filter(or_(
            UserContributor.name.ilike(like),
            UserContributor.email.ilike(like),
            UserContributor.phone.ilike(like),
        ))

    total = q.count()

    if sort_by == "created_at":
        order_col = UserContributor.created_at
    else:
        order_col = UserContributor.name

    if sort_order == "desc":
        q = q.order_by(order_col.desc())
    else:
        q = q.order_by(order_col.asc())

    contributors = q.offset((page - 1) * limit).limit(limit).all()

    from utils.whatsapp_availability import statuses_by_phones
    wa_map = statuses_by_phones(db, _collect_contributor_phones(contributors))
    nuru_user_map = _build_nuru_user_map(db, contributors)

    return standard_response(True, "Contributors fetched", {
        "contributors": [
            _contributor_dict(c, wa_map=wa_map, nuru_user_map=nuru_user_map)
            for c in contributors
        ],
        "pagination": {
            "page": page,
            "limit": limit,
            "total": total,
            "total_pages": math.ceil(total / limit) if limit else 1,
        },
    })


# NOTE: Static routes (e.g. /my-contributions) MUST be registered BEFORE the
# dynamic /{contributor_id} route, otherwise FastAPI captures them as a
# contributor_id and returns "Invalid contributor ID". The actual handler for
# /my-contributions lives further down in this file; we register a thin
# forwarding route here so it wins the route-matching race.
@router.get("/my-contributions")
def my_contributions_early(
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return my_contributions(search=search, db=db, current_user=current_user)  # type: ignore[name-defined]


@router.get("/my-contributions/insights")
def my_contributions_insights(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Aggregate "Contribution Insights" for the current user — total
    pledged/paid/balance, giving streak (consecutive months with at least
    one payment), monthly trend (last 12 months), method mix, top
    organisations supported, biggest gift, on-time completion rate and
    a friendly impact message. Used by the mobile Insights screen."""
    me_phone_digits = _normalize_phone_digits(current_user.phone) if getattr(current_user, "phone", None) else ""
    contribs = db.query(UserContributor).filter(
        UserContributor.contributor_user_id == current_user.id
    ).all()
    if me_phone_digits:
        from sqlalchemy import func as _f
        legacy = db.query(UserContributor).filter(
            UserContributor.contributor_user_id.is_(None),
            UserContributor.phone.isnot(None),
            _f.right(_f.regexp_replace(UserContributor.phone, r'[^0-9]', '', 'g'), 9) == me_phone_digits,
        ).all()
        contribs.extend(legacy)

    user_currency = (getattr(current_user, "currency_code", None) or "").strip() or "TZS"

    if not contribs:
        return standard_response(True, "No insights yet", {
            "summary": {"total_pledged": 0, "total_paid": 0, "total_balance": 0,
                        "total_pending": 0, "currency": user_currency},
            "counts": {"events_count": 0, "complete_count": 0, "active_count": 0,
                       "pending_count": 0, "payments_count": 0, "organisations_supported": 0},
            "streak_months": 0, "biggest_contribution": None,
            "first_contribution_at": None, "last_contribution_at": None,
            "avg_per_event": 0, "on_time_rate": 0,
            "by_month": [], "by_method": [], "top_organisers": [],
            "impact_message": "Make your first contribution to see your impact.",
        })

    contributor_ids = [c.id for c in contribs]
    ecs = db.query(EventContributor).options(
        joinedload(EventContributor.event),
        joinedload(EventContributor.contributions),
    ).filter(EventContributor.contributor_id.in_(contributor_ids)).all()

    per_event = []
    for ec in ecs:
        if not ec.event:
            continue
        ev = ec.event
        if ev.currency_id:
            cur = db.query(Currency).filter(Currency.id == ev.currency_id).first()
            currency = (cur.code.strip() if cur else user_currency)
        else:
            currency = user_currency
        pledge = float(ec.pledge_amount or 0)
        paid = sum(
            float(c.amount or 0) for c in ec.contributions
            if c.confirmation_status is None or c.confirmation_status == ContributionStatusEnum.confirmed
        )
        pending = sum(
            float(c.amount or 0) for c in ec.contributions
            if c.confirmation_status == ContributionStatusEnum.pending
        )
        balance = max(0.0, pledge - paid - pending)
        complete = pledge > 0 and balance == 0 and pending == 0
        per_event.append({"ec": ec, "event": ev, "currency": currency,
                          "pledge": pledge, "paid": paid, "pending": pending,
                          "balance": balance, "complete": complete})

    cur_amounts = {}
    for r in per_event:
        cur_amounts[r["currency"]] = cur_amounts.get(r["currency"], 0) + r["paid"] + r["pledge"]
    dominant_currency = max(cur_amounts.items(), key=lambda x: x[1])[0] if cur_amounts else user_currency

    filtered = [r for r in per_event if r["currency"] == dominant_currency]
    total_pledged = sum(r["pledge"] for r in filtered)
    total_paid = sum(r["paid"] for r in filtered)
    total_pending = sum(r["pending"] for r in filtered)
    total_balance = sum(r["balance"] for r in filtered)
    events_count = len(filtered)
    complete_count = sum(1 for r in filtered if r["complete"])
    active_count = sum(1 for r in filtered if not r["complete"] and (r["paid"] > 0 or r["pending"] > 0))
    pending_count = sum(1 for r in filtered if r["paid"] == 0 and r["pending"] == 0)
    organisations_supported = len({str(r["event"].organizer_id) for r in filtered if r["event"].organizer_id})

    payments = []
    for r in filtered:
        for p in r["ec"].contributions:
            if not (p.confirmation_status is None or p.confirmation_status == ContributionStatusEnum.confirmed):
                continue
            payments.append({"p": p, "event": r["event"], "currency": r["currency"]})
    payments_count = len(payments)

    biggest = None
    if payments:
        bp = max(payments, key=lambda x: float(x["p"].amount or 0))
        d = bp["p"].contributed_at or bp["p"].confirmed_at or bp["p"].created_at
        biggest = {
            "amount": float(bp["p"].amount or 0),
            "currency": bp["currency"],
            "event_id": str(bp["event"].id),
            "event_name": bp["event"].name,
            "contributed_at": d.isoformat() if d else None,
        }

    payment_dates = [
        (x["p"].contributed_at or x["p"].confirmed_at or x["p"].created_at)
        for x in payments
        if (x["p"].contributed_at or x["p"].confirmed_at or x["p"].created_at)
    ]
    first_at = min(payment_dates).isoformat() if payment_dates else None
    last_at = max(payment_dates).isoformat() if payment_dates else None

    from collections import OrderedDict
    now_eat = datetime.now(EAT)
    months = OrderedDict()
    for i in range(11, -1, -1):
        y = now_eat.year + ((now_eat.month - 1 - i) // 12)
        m = ((now_eat.month - 1 - i) % 12) + 1
        months[f"{y:04d}-{m:02d}"] = {"month": f"{y:04d}-{m:02d}", "amount": 0.0, "count": 0}
    for x in payments:
        d = x["p"].contributed_at or x["p"].confirmed_at or x["p"].created_at
        if not d:
            continue
        try:
            d_local = d.astimezone(EAT) if d.tzinfo else EAT.localize(d)
        except Exception:
            d_local = d
        key = f"{d_local.year:04d}-{d_local.month:02d}"
        if key in months:
            months[key]["amount"] += float(x["p"].amount or 0)
            months[key]["count"] += 1
    by_month = list(months.values())

    streak = 0
    for k in reversed(list(months.keys())):
        if months[k]["count"] > 0:
            streak += 1
        else:
            break

    method_totals = {}
    for x in payments:
        m = x["p"].payment_method.value if x["p"].payment_method else (
            "manual" if x["p"].recorded_by else "other"
        )
        method_totals.setdefault(m, {"method": m, "amount": 0.0, "count": 0})
        method_totals[m]["amount"] += float(x["p"].amount or 0)
        method_totals[m]["count"] += 1
    mt_total = sum(v["amount"] for v in method_totals.values()) or 1
    by_method = sorted(
        [{**v, "percent": round((v["amount"] / mt_total) * 100, 1)} for v in method_totals.values()],
        key=lambda v: v["amount"], reverse=True,
    )

    org_totals = {}
    for r in filtered:
        oid = str(r["event"].organizer_id) if r["event"].organizer_id else None
        if not oid:
            continue
        org_totals.setdefault(oid, {"organizer_id": oid, "amount": 0.0, "events": 0, "name": None, "profile_image": None})
        org_totals[oid]["amount"] += r["paid"]
        org_totals[oid]["events"] += 1
    if org_totals:
        org_users = db.query(User).filter(User.id.in_(list(org_totals.keys()))).all()
        for u in org_users:
            org_totals[str(u.id)]["name"] = f"{u.first_name or ''} {u.last_name or ''}".strip() or "Organiser"
            org_totals[str(u.id)]["profile_image"] = getattr(u, "profile_picture_url", None)
    top_organisers = sorted(org_totals.values(), key=lambda v: v["amount"], reverse=True)[:5]

    pledged_events = [r for r in filtered if r["pledge"] > 0]
    on_time_total = len(pledged_events)
    on_time_kept = 0
    for r in pledged_events:
        if not r["complete"]:
            continue
        ev_d = r["event"].start_date
        if not ev_d:
            on_time_kept += 1
            continue
        last_pay = max(
            (c.contributed_at for c in r["ec"].contributions if c.contributed_at),
            default=None,
        )
        # event.start_date is a `date`; contributed_at is a `datetime`.
        # Compare as dates to avoid TypeError.
        last_pay_d = last_pay.date() if hasattr(last_pay, 'date') else last_pay
        ev_d_d = ev_d.date() if hasattr(ev_d, 'date') and hasattr(ev_d, 'hour') else ev_d
        if last_pay is None or last_pay_d <= ev_d_d:
            on_time_kept += 1
    on_time_rate = round((on_time_kept / on_time_total) * 100, 1) if on_time_total else 0.0
    avg_per_event = round((total_paid / events_count), 2) if events_count else 0

    if total_paid <= 0:
        impact_message = "Your generosity story starts with your first contribution."
    elif organisations_supported >= 3:
        impact_message = (f"You've helped {organisations_supported} organisers across "
                          f"{events_count} event{'s' if events_count != 1 else ''}. Keep showing up.")
    elif streak >= 3:
        impact_message = f"{streak} months of giving in a row — that's real consistency."
    else:
        impact_message = (f"You've contributed {payments_count} time"
                          f"{'s' if payments_count != 1 else ''} so far. Every gift counts.")

    return standard_response(True, "Insights fetched", {
        "summary": {"total_pledged": total_pledged, "total_paid": total_paid,
                    "total_pending": total_pending, "total_balance": total_balance,
                    "currency": dominant_currency},
        "counts": {"events_count": events_count, "complete_count": complete_count,
                   "active_count": active_count, "pending_count": pending_count,
                   "payments_count": payments_count,
                   "organisations_supported": organisations_supported},
        "streak_months": streak,
        "biggest_contribution": biggest,
        "first_contribution_at": first_at,
        "last_contribution_at": last_at,
        "avg_per_event": avg_per_event,
        "on_time_rate": on_time_rate,
        "by_month": by_month,
        "by_method": by_method,
        "top_organisers": top_organisers,
        "impact_message": impact_message,
    })


@router.get("/my-contributions/{event_id}/payments")
def my_contribution_payments(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """All EventContribution rows the current user has paid towards a given
    event. Matches the user across every event_contributor row that points
    to them either via contributor_user_id OR phone-equivalence (Nuru
    contributors don't have to be Nuru users — we map by phone). Includes
    online (gateway), offline-claim, and organiser-recorded payments."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    me_phone_digits = _normalize_phone_digits(current_user.phone) if getattr(current_user, "phone", None) else ""
    contribs = db.query(UserContributor).filter(
        UserContributor.contributor_user_id == current_user.id
    ).all()
    if me_phone_digits:
        from sqlalchemy import func as _f
        legacy = db.query(UserContributor).filter(
            UserContributor.contributor_user_id.is_(None),
            UserContributor.phone.isnot(None),
            _f.right(_f.regexp_replace(UserContributor.phone, r'[^0-9]', '', 'g'), 9) == me_phone_digits,
        ).all()
        contribs.extend(legacy)
    if not contribs:
        return standard_response(True, "No payments", {"payments": [], "total_paid": 0, "total_pending": 0})

    contributor_ids = list({c.id for c in contribs})

    ecs = db.query(EventContributor).options(joinedload(EventContributor.contributions)).filter(
        EventContributor.event_id == eid,
        EventContributor.contributor_id.in_(contributor_ids),
    ).all()
    if not ecs:
        return standard_response(True, "No payments", {"payments": [], "total_paid": 0, "total_pending": 0})

    rows = []
    total_paid = 0.0
    total_pending = 0.0
    for ec in ecs:
        for p in ec.contributions:
            amt = float(p.amount or 0)
            status = p.confirmation_status.value if p.confirmation_status else "confirmed"
            if status == "pending":
                total_pending += amt
            else:
                total_paid += amt
            method = p.payment_method.value if p.payment_method else None
            if method == "wallet":
                source = "Wallet"
            elif method == "mobile_money":
                source = (p.provider_name or "Mobile Money")
            elif method == "bank":
                source = (p.provider_name or "Bank Transfer")
            elif method == "cash":
                source = "Cash"
            elif method == "card":
                source = (p.provider_name or "Card")
            elif p.recorded_by:
                source = "Recorded by organiser"
            else:
                source = (p.provider_name or "Other")

            rows.append({
                "id": str(p.id),
                "event_contributor_id": str(p.event_contributor_id),
                "amount": amt,
                "payment_method": method,
                "payment_channel": p.payment_channel,
                "provider_name": p.provider_name,
                "transaction_ref": p.transaction_ref,
                "source_label": source,
                "confirmation_status": status,
                "recorded_by_organiser": p.recorded_by is not None,
                "contributed_at": p.contributed_at.isoformat() if p.contributed_at else None,
                "confirmed_at": p.confirmed_at.isoformat() if p.confirmed_at else None,
                "created_at": p.created_at.isoformat() if p.created_at else None,
            })

    rows.sort(key=lambda r: r["contributed_at"] or r["created_at"] or "", reverse=True)

    return standard_response(True, "Payments fetched", {
        "payments": rows,
        "count": len(rows),
        "total_paid": total_paid,
        "total_pending": total_pending,
    })


@router.get("/{contributor_id}")
def get_contributor(contributor_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(contributor_id)
    except ValueError:
        return standard_response(False, "Invalid contributor ID")

    c = db.query(UserContributor).filter(UserContributor.id == cid, UserContributor.user_id == current_user.id).first()
    if not c:
        return standard_response(False, "Contributor not found")

    old_secondary_phone = getattr(c, "secondary_phone", None)
    old_notify_target = (getattr(c, "notify_target", None) or "primary")

    return standard_response(True, "Contributor fetched", _contributor_dict(c))


@router.post("/")
def create_contributor(body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    name = (body.get("name") or "").strip()
    if not name:
        return standard_response(False, "Name is required")

    now = datetime.now(EAT)
    phone = (body.get("phone") or "").strip() or None
    if phone:
        try:
            phone = validate_phone_number(phone)
        except ValueError as e:
            return standard_response(False, str(e))

    # Check phone uniqueness first (DB constraint: user_id + phone)
    if phone:
        existing_phone = db.query(UserContributor).filter(
            UserContributor.user_id == current_user.id,
            UserContributor.phone == phone,
        ).first()
        if existing_phone:
            return standard_response(False, f"A contributor with phone number {format_phone_display(phone)} already exists ({existing_phone.name})")

    # Check name uniqueness
    existing_name = db.query(UserContributor).filter(
        UserContributor.user_id == current_user.id,
        UserContributor.name == name,
    ).first()
    if existing_name:
        return standard_response(False, "A contributor with this name already exists")

    # Auto-link to a registered Nuru user if their phone matches
    linked_user = _find_user_by_phone(db, phone) if phone else None

    nt = (body.get("notify_target") or "primary").strip().lower()
    if nt not in ("primary", "secondary", "both"):
        nt = "primary"

    # Normalize secondary phone to international digits-only (no '+'),
    # matching the primary phone storage convention. Prevents downstream
    # WhatsApp / SMS gateways from receiving a stray '+'.
    secondary_raw = (body.get("secondary_phone") or "").strip() or None
    if secondary_raw:
        try:
            secondary_raw = validate_phone_number(secondary_raw)
        except ValueError as e:
            return standard_response(False, f"Secondary phone: {e}")

    c = UserContributor(
        id=uuid.uuid4(),
        user_id=current_user.id,
        contributor_user_id=linked_user.id if linked_user else None,
        name=name,
        email=(body.get("email") or "").strip() or None,
        phone=phone,
        notes=(body.get("notes") or "").strip() or None,
        secondary_phone=secondary_raw,
        notify_target=nt,
        created_at=now,
        updated_at=now,
    )
    db.add(c)
    db.commit()

    # Queue WhatsApp availability checks (best-effort; never blocks).
    try:
        from tasks.whatsapp_availability import check_one_phone
        if phone:
            check_one_phone.delay(phone)
        if secondary_raw:
            check_one_phone.delay(secondary_raw)
    except Exception:
        pass

    return standard_response(True, "Contributor created", _contributor_dict(c))


@router.put("/{contributor_id}")
def update_contributor(contributor_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(contributor_id)
    except ValueError:
        return standard_response(False, "Invalid contributor ID")

    c = db.query(UserContributor).filter(UserContributor.id == cid, UserContributor.user_id == current_user.id).first()
    if not c:
        return standard_response(False, "Contributor not found")

    # Capture pre-mutation values so we can decide which linked event_contributor rows
    # are still "in sync" with the address-book defaults and should be cascaded.
    old_secondary_phone = c.secondary_phone
    old_notify_target = (c.notify_target or "primary")

    if "name" in body and body["name"]:
        new_name = body["name"].strip()
        if new_name != c.name:
            existing_name = db.query(UserContributor).filter(
                UserContributor.user_id == current_user.id,
                UserContributor.name == new_name,
                UserContributor.id != cid,
            ).first()
            if existing_name:
                return standard_response(False, f"A contributor named '{new_name}' already exists")
        c.name = new_name
    if "email" in body:
        c.email = (body["email"] or "").strip() or None
    old_phone = c.phone
    old_secondary = getattr(c, "secondary_phone", None)
    if "phone" in body:
        phone_val = (body["phone"] or "").strip() or None
        if phone_val:
            try:
                phone_val = validate_phone_number(phone_val)
            except ValueError as e:
                return standard_response(False, str(e))
            if phone_val != c.phone:
                existing_phone = db.query(UserContributor).filter(
                    UserContributor.user_id == current_user.id,
                    UserContributor.phone == phone_val,
                    UserContributor.id != cid,
                ).first()
                if existing_phone:
                    return standard_response(False, f"Phone number {format_phone_display(phone_val)} is already used by contributor '{existing_phone.name}'")
        c.phone = phone_val
        # Re-link to a registered Nuru user when phone changes
        linked_user = _find_user_by_phone(db, phone_val) if phone_val else None
        c.contributor_user_id = linked_user.id if linked_user else None
    if "notes" in body:
        c.notes = (body["notes"] or "").strip() or None
    if "secondary_phone" in body:
        sp = (body["secondary_phone"] or "").strip() or None
        if sp:
            try:
                sp = validate_phone_number(sp)
            except ValueError as e:
                return standard_response(False, f"Secondary phone: {e}")
        c.secondary_phone = sp
    if "notify_target" in body:
        nt = (body["notify_target"] or "primary").strip().lower()
        c.notify_target = nt if nt in ("primary", "secondary", "both") else "primary"

    if "secondary_phone" in body or "notify_target" in body:
        linked_event_rows = db.query(EventContributor).filter(EventContributor.contributor_id == cid).all()
        for ec in linked_event_rows:
            ec_secondary = getattr(ec, "secondary_phone", None)
            ec_notify = (getattr(ec, "notify_target", None) or "primary")
            if (not ec_secondary or ec_secondary == old_secondary_phone) and ec_notify == old_notify_target:
                ec.secondary_phone = c.secondary_phone
                ec.notify_target = c.notify_target
                ec.updated_at = datetime.now(EAT)

    c.updated_at = datetime.now(EAT)
    db.commit()

    # When a phone changes, queue a fresh WhatsApp availability check for
    # the new number(s). The old cache row stays put (it may still be valid
    # for another contributor that shares the number).
    try:
        from tasks.whatsapp_availability import check_one_phone
        if c.phone and c.phone != old_phone:
            check_one_phone.delay(c.phone)
        new_secondary = getattr(c, "secondary_phone", None)
        if new_secondary and new_secondary != old_secondary:
            check_one_phone.delay(new_secondary)
    except Exception:
        pass

    return standard_response(True, "Contributor updated", _contributor_dict(c))


@router.delete("/{contributor_id}")
def delete_contributor(contributor_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(contributor_id)
    except ValueError:
        return standard_response(False, "Invalid contributor ID")

    c = db.query(UserContributor).filter(UserContributor.id == cid, UserContributor.user_id == current_user.id).first()
    if not c:
        return standard_response(False, "Contributor not found")

    # SAFETY: Check if this contributor has any recorded payments across any events.
    # Deleting the UserContributor would CASCADE-delete EventContributors and their
    # EventContributions, causing permanent data loss.
    linked_ecs = db.query(EventContributor).filter(EventContributor.contributor_id == cid).all()
    for ec in linked_ecs:
        payment_count = db.query(EventContribution).filter(
            EventContribution.event_contributor_id == ec.id
        ).count()
        if payment_count > 0:
            event = db.query(Event).filter(Event.id == ec.event_id).first()
            event_name = event.name if event else "an event"
            return standard_response(
                False,
                f"Cannot delete '{c.name}' because they have {payment_count} recorded contribution(s) in '{event_name}'. "
                f"Remove their contributions first, or remove them from the event."
            )

    # Safe to delete — no contributions exist, cascade will only remove empty event links
    db.delete(c)
    db.commit()

    return standard_response(True, "Contributor deleted")


# ══════════════════════════════════════════════
# EVENT CONTRIBUTORS
# ══════════════════════════════════════════════

@router.get("/events/{event_id}/contributors")
def get_event_contributors(
    event_id: str,
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=5000),
    search: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event, is_creator, cm, perms = _get_event_access(db, eid, current_user)
    if not event:
        return standard_response(False, "Event not found")
    if not is_creator and not cm:
        return standard_response(False, "Event not found or access denied")

    # Build base query WITHOUT joinedload (to avoid row inflation from one-to-many JOINs)
    base_q = db.query(EventContributor).filter(EventContributor.event_id == eid)

    if search:
        like = f"%{search}%"
        base_q = base_q.join(UserContributor).filter(or_(
            UserContributor.name.ilike(like),
            UserContributor.email.ilike(like),
            UserContributor.phone.ilike(like),
        ))

    total = base_q.count()

    # Paginate on IDs FIRST — use (created_at DESC, id DESC) for stable ordering
    # Without the id tiebreaker, records with identical timestamps shift between pages
    id_rows = base_q.with_entities(EventContributor.id).order_by(
        EventContributor.created_at.desc(),
        EventContributor.id.desc(),
    ).offset((page - 1) * limit).limit(limit).all()
    ec_ids = [r[0] for r in id_rows]

    # Now load full objects with relationships for just those IDs
    if ec_ids:
        ecs = db.query(EventContributor).options(
            joinedload(EventContributor.contributor),
            joinedload(EventContributor.contributions),
        ).filter(EventContributor.id.in_(ec_ids)).all()
        # Deduplicate (joinedload may still produce duplicate parent rows)
        seen = set()
        unique_ecs = []
        for ec in ecs:
            if ec.id not in seen:
                seen.add(ec.id)
                unique_ecs.append(ec)
        # Restore original ordering (created_at desc, id desc)
        id_order = {eid: idx for idx, eid in enumerate(ec_ids)}
        ecs = sorted(unique_ecs, key=lambda ec: id_order.get(ec.id, 0))
    else:
        ecs = []

    from utils.whatsapp_availability import statuses_by_phones
    all_contribs = [ec.contributor for ec in ecs if ec.contributor]
    wa_map = statuses_by_phones(db, _collect_contributor_phones(all_contribs))
    ec_dicts = [_event_contributor_dict(ec, wa_map=wa_map) for ec in ecs]

    # Compute summary from ALL event contributors (not just current page)
    all_ecs_for_summary = db.query(EventContributor).options(
        joinedload(EventContributor.contributions),
    ).filter(EventContributor.event_id == eid).all()
    # Deduplicate
    seen_summary = set()
    unique_summary_ecs = []
    for ec in all_ecs_for_summary:
        if ec.id not in seen_summary:
            seen_summary.add(ec.id)
            unique_summary_ecs.append(ec)
    summary_contribs = [ec.contributor for ec in unique_summary_ecs if ec.contributor]
    summary_wa_map = statuses_by_phones(db, _collect_contributor_phones(summary_contribs))
    all_dicts = [_event_contributor_dict(ec, wa_map=summary_wa_map) for ec in unique_summary_ecs]
    total_pledged = sum(d["pledge_amount"] for d in all_dicts)
    total_paid = sum(d["total_paid"] for d in all_dicts)
    total_balance = sum(d.get("balance", 0) for d in all_dicts)
    currency = _currency_code(db, event)

    # WhatsApp availability rollup (uses primary phone)
    wa_counts = {"whatsapp": 0, "not_whatsapp": 0, "unknown": 0, "checking": 0, "failed": 0}
    for d in all_dicts:
        st = ((d.get("contributor") or {}).get("whatsapp_status")) or "unknown"
        wa_counts[st] = wa_counts.get(st, 0) + 1

    return standard_response(True, "Event contributors fetched", {
        "event_contributors": ec_dicts,
        "summary": {
            "total_pledged": total_pledged,
            "total_paid": total_paid,
            "total_balance": total_balance,
            "count": total,
            "currency": currency,
            "whatsapp": wa_counts,
        },
        "pagination": {
            "page": page,
            "limit": limit,
            "total": total,
            "total_pages": math.ceil(total / limit) if limit else 1,
        },
    })


@router.post("/events/{event_id}/contributors")
def add_to_event(event_id: str, body: dict = Body(...), background_tasks: BackgroundTasks = None, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event, is_creator, cm, perms = _get_event_access(db, eid, current_user)
    if not event:
        return standard_response(False, "Event not found")
    if not is_creator and not cm:
        return standard_response(False, "Event not found or access denied")

    # Use organizer's user_id for contributor address book lookups
    owner_id = event.organizer_id

    now = datetime.now(EAT)
    contributor_id = body.get("contributor_id")
    provided_name = (body.get("name") or "").strip()

    if contributor_id:
        # Link existing contributor
        try:
            cid = uuid.UUID(contributor_id)
        except ValueError:
            return standard_response(False, "Invalid contributor ID")

        contributor = db.query(UserContributor).filter(UserContributor.id == cid, UserContributor.user_id == owner_id).first()
        if not contributor:
            return standard_response(False, "Contributor not found in address book")
    else:
        # Create new contributor inline
        if not provided_name:
            return standard_response(False, "Name is required for new contributors")

        inline_phone = (body.get("phone") or "").strip() or None
        if inline_phone:
            try:
                inline_phone = validate_phone_number(inline_phone)
            except ValueError as e:
                return standard_response(False, str(e))

        # Look up by phone first (unique constraint), then by name. When we
        # find the contributor by phone we keep the global ``name`` intact
        # so other events that reuse this address-book entry don't get
        # silently renamed — the new name becomes a per-event override
        # further down.
        contributor = None
        if inline_phone:
            contributor = db.query(UserContributor).filter(
                UserContributor.user_id == owner_id,
                UserContributor.phone == inline_phone,
            ).first()
        if not contributor:
            contributor = db.query(UserContributor).filter(
                UserContributor.user_id == owner_id,
                UserContributor.name == provided_name,
            ).first()

        if not contributor:
            contributor = UserContributor(
                id=uuid.uuid4(),
                user_id=owner_id,
                name=provided_name,
                email=(body.get("email") or "").strip() or None,
                phone=inline_phone,
                created_at=now,
                updated_at=now,
            )
            db.add(contributor)
            db.flush()
        else:
            # Only fill email if we don't have one yet. Never overwrite the
            # global name from inside an event — that's what display_name is for.
            if body.get("email") and not contributor.email:
                contributor.email = (body.get("email") or "").strip() or contributor.email
                contributor.updated_at = now

    # Per-event display name: prefer the explicit name on this request,
    # otherwise inherit the global name. Stored as NULL when it would just
    # duplicate the global value so we can tell intentional overrides apart.
    effective_name = provided_name or contributor.name
    new_display = effective_name if effective_name and effective_name != contributor.name else None

    # If a link already exists, support "soft re-add": same name → idempotent
    # duplicate signal; different name → silently update the per-event
    # display_name without erroring out.
    existing = db.query(EventContributor).options(
        joinedload(EventContributor.contributor),
        joinedload(EventContributor.contributions),
    ).filter(
        EventContributor.event_id == eid,
        EventContributor.contributor_id == contributor.id,
    ).first()
    if existing:
        current_effective = (existing.display_name or contributor.name or "").strip()
        if effective_name and effective_name != current_effective:
            existing.display_name = new_display
            existing.updated_at = now
            db.commit()
            db.refresh(existing)
            return standard_response(True, "Event contributor name updated",
                                     _event_contributor_dict(existing))
        return standard_response(False, "This contributor is already added to this event")

    # Fall back to address-book defaults when not explicitly provided.
    # Always normalize an explicitly-provided secondary phone to international
    # digits-only (no '+') so downstream WA/SMS senders don't choke.
    raw_secondary = body.get("secondary_phone")
    if raw_secondary is None:
        ec_secondary = (getattr(contributor, "secondary_phone", None) or None)
    else:
        ec_secondary = (raw_secondary or "").strip() or None
        if ec_secondary:
            try:
                ec_secondary = validate_phone_number(ec_secondary)
            except ValueError as e:
                return standard_response(False, f"Secondary phone: {e}")

    raw_notify = body.get("notify_target")
    if raw_notify is None:
        ec_notify = (getattr(contributor, "notify_target", None) or "primary")
    else:
        ec_notify = (raw_notify or "primary").strip().lower()

    ec = EventContributor(
        id=uuid.uuid4(),
        event_id=eid,
        contributor_id=contributor.id,
        display_name=new_display,
        pledge_amount=body.get("pledge_amount", 0),
        notes=(body.get("notes") or "").strip() or None,
        secondary_phone=ec_secondary,
        notify_target=ec_notify,
        created_at=now,
        updated_at=now,
    )
    if ec.notify_target not in ("primary", "secondary", "both"):
        ec.notify_target = "primary"
    db.add(ec)
    db.commit()

    # Reload with relationships
    ec = db.query(EventContributor).options(
        joinedload(EventContributor.contributor),
        joinedload(EventContributor.contributions),
    ).filter(EventContributor.id == ec.id).first()

    # Auto-add this contributor to the event group workspace if one exists
    try:
        from api.routes.event_groups import ensure_member_for_contributor
        ensure_member_for_contributor(db, eid, contributor)
        db.commit()
    except Exception:
        db.rollback()

    # Send WhatsApp (primary) + SMS (fallback) when contributor is added with a pledge amount.
    # Offloaded to BackgroundTasks so the request returns immediately. The
    # helpers internally enqueue Celery jobs, but Redis hiccups can still add
    # 100s of ms — keep them off the hot path entirely.
    pledge_val = float(body.get("pledge_amount", 0))
    if pledge_val > 0 and background_tasks is not None:
        from utils.offline_claims import contributor_notify_phones
        recipients = contributor_notify_phones(ec)
        if recipients:
            currency = _currency_code(db, event)
            organizer = db.query(User).filter(User.id == event.organizer_id).first()
            organizer_phone = format_phone_display(organizer.phone) if organizer and organizer.phone else None
            pay_instr = (event.contribution_payment_instructions or "").strip() or None
            contrib_name = (ec.display_name or contributor.name)
            event_name = event.name

            try:
                from utils.wa_logging import set_wa_log_context
                set_wa_log_context(event_id=str(event.id), event_name=event.name,
                                   source_module="contributors", purpose="contribution_target",
                                   recipient_type="contributor",
                                   related_entity_type="event_contributor",
                                   related_entity_id=str(ec.id))
            except Exception: pass
            def _notify_added():
                for ph in recipients:
                    try:
                        from utils.whatsapp import wa_contribution_target_set
                        wa_contribution_target_set(
                            ph, contrib_name, event_name, pledge_val, 0, currency,
                            organizer_phone=organizer_phone,
                            payment_instructions=pay_instr,
                        )
                    except Exception:
                        pass
                    try:
                        from utils.sms import sms_contribution_target_set
                        sms_contribution_target_set(
                            ph, contrib_name, event_name, pledge_val, currency=currency,
                            organizer_phone=organizer_phone,
                            payment_instructions=pay_instr,
                        )
                    except Exception:
                        pass
            background_tasks.add_task(_notify_added)

    return standard_response(True, "Contributor added to event", _event_contributor_dict(ec))


@router.put("/events/{event_id}/contributors/{ec_id}")
def update_event_contributor(event_id: str, ec_id: str, body: dict = Body(...), background_tasks: BackgroundTasks = None, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        ecid = uuid.UUID(ec_id)
    except ValueError:
        return standard_response(False, "Invalid ID")

    event, is_creator, cm, perms = _get_event_access(db, eid, current_user)
    if not event or (not is_creator and not cm):
        return standard_response(False, "Event not found or access denied")

    ec = db.query(EventContributor).options(
        joinedload(EventContributor.contributor),
        joinedload(EventContributor.contributions),
    ).filter(EventContributor.id == ecid, EventContributor.event_id == eid).first()
    if not ec:
        return standard_response(False, "Event contributor not found")

    old_pledge = float(ec.pledge_amount or 0)
    if "pledge_amount" in body:
        ec.pledge_amount = body["pledge_amount"]
    if "notes" in body:
        ec.notes = (body["notes"] or "").strip() or None
    if "secondary_phone" in body:
        sp = (body["secondary_phone"] or "").strip() or None
        if sp:
            try:
                sp = validate_phone_number(sp)
            except ValueError as e:
                return standard_response(False, f"Secondary phone: {e}")
        ec.secondary_phone = sp
    if "notify_target" in body:
        nt = (body["notify_target"] or "primary").strip().lower()
        ec.notify_target = nt if nt in ("primary", "secondary", "both") else "primary"
    # Per-event display name override. Accept either ``display_name`` or a
    # plain ``name`` field — never propagates to the global address book.
    if "display_name" in body or "name" in body:
        raw_name = (body.get("display_name") if "display_name" in body else body.get("name"))
        new_name = (raw_name or "").strip() or None
        # Store NULL when it would just duplicate the global name so explicit
        # overrides remain distinguishable from defaults.
        global_name = (ec.contributor.name if ec.contributor else None)
        ec.display_name = new_name if (new_name and new_name != global_name) else None

    ec.updated_at = datetime.now(EAT)
    db.commit()

    # Send WhatsApp (primary) + SMS (fallback) when pledge target is changed.
    # Offloaded to BackgroundTasks so the HTTP response returns instantly.
    new_pledge = float(ec.pledge_amount or 0)
    if new_pledge > 0 and new_pledge != old_pledge and ec.contributor and background_tasks is not None:
        from utils.offline_claims import contributor_notify_phones
        recipients = contributor_notify_phones(ec)
        if recipients:
            currency = _currency_code(db, event)
            organizer = db.query(User).filter(User.id == event.organizer_id).first()
            organizer_phone = format_phone_display(organizer.phone) if organizer and organizer.phone else None
            pay_instr = (event.contribution_payment_instructions or "").strip() or None
            is_increase = new_pledge > old_pledge and old_pledge > 0
            contrib_name = (ec.display_name or ec.contributor.name)
            event_name = event.name

            try:
                from utils.wa_logging import set_wa_log_context
                set_wa_log_context(event_id=str(event.id), event_name=event.name,
                                   source_module="contributors", purpose="contribution_target",
                                   recipient_type="contributor",
                                   related_entity_type="event_contributor",
                                   related_entity_id=str(ec.id))
            except Exception: pass
            def _notify_pledge_change():
                for ph in recipients:
                    try:
                        if is_increase:
                            from utils.whatsapp import wa_contribution_target_updated
                            wa_contribution_target_updated(
                                ph, contrib_name, event_name,
                                increase=(new_pledge - old_pledge),
                                total_target=new_pledge,
                                currency=currency,
                                organizer_phone=organizer_phone,
                                payment_instructions=pay_instr,
                            )
                        else:
                            from utils.whatsapp import wa_contribution_target_set
                            wa_contribution_target_set(
                                ph, contrib_name, event_name, new_pledge, 0, currency,
                                organizer_phone=organizer_phone,
                                payment_instructions=pay_instr,
                            )
                    except Exception:
                        pass
                    try:
                        if is_increase:
                            from utils.sms import sms_contribution_target_updated
                            sms_contribution_target_updated(
                                ph, contrib_name, event_name,
                                increase=(new_pledge - old_pledge),
                                total_target=new_pledge,
                                currency=currency,
                                organizer_phone=organizer_phone,
                                payment_instructions=pay_instr,
                            )
                        else:
                            from utils.sms import sms_contribution_target_set
                            sms_contribution_target_set(
                                ph, contrib_name, event_name, new_pledge,
                                currency=currency,
                                organizer_phone=organizer_phone,
                                payment_instructions=pay_instr,
                            )
                    except Exception:
                        pass
            background_tasks.add_task(_notify_pledge_change)

    return standard_response(True, "Event contributor updated", _event_contributor_dict(ec))


@router.delete("/events/{event_id}/contributors/{ec_id}")
def remove_from_event(event_id: str, ec_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        ecid = uuid.UUID(ec_id)
    except ValueError:
        return standard_response(False, "Invalid ID")

    event, is_creator, cm_del, perms_del = _get_event_access(db, eid, current_user)
    if not event or not is_creator:
        return standard_response(False, "Only event creator can remove contributors")

    ec = db.query(EventContributor).filter(EventContributor.id == ecid, EventContributor.event_id == eid).first()
    if not ec:
        return standard_response(False, "Event contributor not found")

    # Manually cascade: delete thank-you messages → contributions → event contributor
    contribution_ids = [c.id for c in db.query(EventContribution.id).filter(EventContribution.event_contributor_id == ecid).all()]
    if contribution_ids:
        db.query(ContributionThankYouMessage).filter(
            ContributionThankYouMessage.contribution_id.in_(contribution_ids)
        ).delete(synchronize_session=False)
        db.query(EventContribution).filter(
            EventContribution.event_contributor_id == ecid
        ).delete(synchronize_session=False)

    db.delete(ec)
    db.commit()

    return standard_response(True, "Contributor removed from event")


@router.post("/events/{event_id}/contributors/bulk-remove")
def bulk_remove_from_event(
    event_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Remove many event contributors at once.

    Body: ``{"ids": ["<event_contributor_id>", ...]}`` or
    ``{"all": true}`` to remove every contributor on the event.

    Only detaches them from the event — the underlying ``UserContributor``
    rows in the organiser's address book are kept intact.
    """
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event, is_creator, _cm_del, _perms_del = _get_event_access(db, eid, current_user)
    if not event or not is_creator:
        return standard_response(False, "Only event creator can remove contributors")

    raw_ids = body.get("ids") or []
    select_all = bool(body.get("all"))

    q = db.query(EventContributor).filter(EventContributor.event_id == eid)
    if not select_all:
        ecids: list[uuid.UUID] = []
        for v in raw_ids:
            try:
                ecids.append(uuid.UUID(str(v)))
            except Exception:
                continue
        if not ecids:
            return standard_response(False, "No valid IDs provided")
        q = q.filter(EventContributor.id.in_(ecids))

    rows = q.all()
    if not rows:
        return standard_response(True, "Nothing to remove", {"removed": 0})

    ec_id_list = [r.id for r in rows]
    contribution_ids = [
        c.id for c in db.query(EventContribution.id).filter(
            EventContribution.event_contributor_id.in_(ec_id_list)
        ).all()
    ]
    if contribution_ids:
        db.query(ContributionThankYouMessage).filter(
            ContributionThankYouMessage.contribution_id.in_(contribution_ids)
        ).delete(synchronize_session=False)
        db.query(EventContribution).filter(
            EventContribution.event_contributor_id.in_(ec_id_list)
        ).delete(synchronize_session=False)

    db.query(EventContributor).filter(
        EventContributor.id.in_(ec_id_list)
    ).delete(synchronize_session=False)
    db.commit()

    return standard_response(True, f"Removed {len(ec_id_list)} contributor(s) from event", {"removed": len(ec_id_list)})



# ══════════════════════════════════════════════
# PAYMENTS
# ══════════════════════════════════════════════

@router.post("/events/{event_id}/contributors/{ec_id}/payments")
def record_payment(
    event_id: str,
    ec_id: str,
    body: dict = Body(...),
    request: Request = None,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    import time as _time
    _t0 = _time.perf_counter()

    try:
        eid = uuid.UUID(event_id)
        ecid = uuid.UUID(ec_id)
    except ValueError:
        return standard_response(False, "Invalid ID")

    # Idempotency: if the client passes Idempotency-Key, replay-safe.
    idem_key = None
    try:
        if request is not None:
            idem_key = (request.headers.get("Idempotency-Key") or "").strip() or None
    except Exception:
        idem_key = None
    if idem_key:
        try:
            existing = db.execute(
                text(
                    "SELECT response_id FROM contribution_idempotency "
                    "WHERE user_id = :u AND scope = :s AND idem_key = :k"
                ),
                {"u": str(current_user.id), "s": f"contrib:{ec_id}", "k": idem_key},
            ).first()
            if existing and existing[0]:
                return standard_response(True, "Payment recorded (idempotent replay)", {
                    "id": str(existing[0]),
                    "replayed": True,
                })
        except Exception as _e:
            print(f"[record_payment] idempotency lookup failed: {_e}")

    event, is_creator, cm, perms = _get_event_access(db, eid, current_user)
    if not event:
        return standard_response(False, "Event not found")
    if not is_creator:
        if not cm or not perms or not perms.can_manage_contributions:
            return standard_response(False, "You do not have permission to record contributions")

    # Load contributor + ALL existing contributions in one round-trip so the
    # total_paid recompute below doesn't trigger a lazy SELECT.
    ec = db.query(EventContributor).options(
        joinedload(EventContributor.contributor),
        selectinload(EventContributor.contributions),
    ).filter(EventContributor.id == ecid, EventContributor.event_id == eid).first()
    if not ec:
        return standard_response(False, "Event contributor not found")
    print(f"[contrib.timing] step=load ms={int((_time.perf_counter()-_t0)*1000)}")

    amount = body.get("amount")
    if not amount or float(amount) <= 0:
        return standard_response(False, "A valid payment amount is required")

    payment_method_str = body.get("payment_method")
    payment_method = None
    if payment_method_str:
        try:
            payment_method = PaymentMethodEnum(payment_method_str)
        except ValueError:
            pass

    now = datetime.now(EAT)
    # If recorded by committee member (not creator), status is pending
    confirmation_status = ContributionStatusEnum.confirmed if is_creator else ContributionStatusEnum.pending
    
    contribution = EventContribution(
        id=uuid.uuid4(),
        event_id=eid,
        event_contributor_id=ec.id,
        contributor_name=(getattr(ec, "display_name", None) or (ec.contributor.name if ec.contributor else "Unknown")),
        amount=float(amount),
        payment_method=payment_method,
        transaction_ref=(body.get("payment_reference") or "").strip() or None,
        recorded_by=current_user.id if not is_creator else None,
        confirmation_status=confirmation_status,
        confirmed_at=now if is_creator else None,
        contributed_at=now,
        created_at=now,
        updated_at=now,
    )
    db.add(contribution)
    db.commit()
    print(f"[contrib.timing] step=insert ms={int((_time.perf_counter()-_t0)*1000)}")

    # Persist idempotency record so retries return the same contribution id.
    if idem_key:
        try:
            db.execute(
                text(
                    "INSERT INTO contribution_idempotency (idem_key, user_id, scope, response_id) "
                    "VALUES (:k, :u, :s, :r) ON CONFLICT (user_id, scope, idem_key) DO NOTHING"
                ),
                {"k": idem_key, "u": str(current_user.id), "s": f"contrib:{ec_id}", "r": str(contribution.id)},
            )
            db.commit()
        except Exception as _e:
            print(f"[record_payment] idempotency persist failed: {_e}")

    # Post into event group workspace + send contributor receipts. Both are
    # offloaded to BackgroundTasks so the request returns instantly. Without
    # this the round-trip blocks on Celery enqueue + workspace insert and
    # users perceive the "Record payment" button as slow.
    contributor = ec.contributor
    contrib_name = contributor.name if contributor else "Someone"
    pledge_amount_snapshot = float(ec.pledge_amount or 0)
    total_paid_after = sum(
        float(c.amount or 0) for c in ec.contributions
        if c.confirmation_status is None
        or c.confirmation_status == ContributionStatusEnum.confirmed
    )
    currency = _currency_code(db, event)
    organizer = db.query(User).filter(User.id == event.organizer_id).first()
    organizer_phone = format_phone_display(organizer.phone) if organizer and organizer.phone else None
    event_name = event.name
    event_id_str = eid
    amount_val = float(amount)
    is_creator_flag = is_creator
    recorder_label = f"{current_user.first_name} {current_user.last_name}"

    from utils.offline_claims import contributor_notify_phones
    recipients = contributor_notify_phones(ec) if contributor else []

    def _post_payment_side_effects():
        try:
            from utils.wa_logging import set_wa_log_context
            set_wa_log_context(event_id=str(event_id_str), event_name=event_name,
                               source_module="contributions", purpose="contribution_receipt",
                               recipient_type="contributor",
                               related_entity_type="contribution",
                               related_entity_id=str(contribution.id))
        except Exception: pass
        # Workspace announcement — confirmed payments only.
        if confirmation_status == ContributionStatusEnum.confirmed:
            try:
                from api.routes.event_groups import post_payment_system_message
                from core.database import SessionLocal
                _db = SessionLocal()
                try:
                    post_payment_system_message(
                        _db, event_id_str, contrib_name,
                        amount_val, pledge_amount_snapshot, total_paid_after, currency,
                    )
                finally:
                    _db.close()
            except Exception:
                pass
        # Contributor receipt / acknowledgement.
        if not recipients:
            return
        if confirmation_status == ContributionStatusEnum.confirmed:
            for ph in recipients:
                try:
                    from utils.whatsapp import wa_contribution_recorded
                    wa_contribution_recorded(
                        ph, contrib_name, event_name, amount_val,
                        pledge_amount_snapshot, total_paid_after, currency,
                        organizer_phone=organizer_phone, recorder_name=None,
                    )
                except Exception:
                    pass
                try:
                    from utils.sms import sms_contribution_recorded
                    sms_contribution_recorded(
                        ph, contrib_name, event_name, amount_val,
                        pledge_amount_snapshot, total_paid_after, currency,
                        organizer_phone=organizer_phone, recorder_name=None,
                    )
                except Exception:
                    pass
        else:
            pending_msg = (
                f"Hello {contrib_name}, {recorder_label} has logged your contribution of "
                f"{currency} {amount_val:,.0f} for {event_name}. You'll receive a confirmation "
                f"once the event organiser approves it."
            )
            try:
                from utils.notify_channels import notify_user_wa_sms
                for ph in recipients:
                    try:
                        notify_user_wa_sms(ph, pending_msg)
                    except Exception:
                        pass
            except Exception:
                pass

    if background_tasks is not None:
        background_tasks.add_task(_post_payment_side_effects)
    else:
        _post_payment_side_effects()

    return standard_response(True, "Payment recorded", {
        "id": str(contribution.id),
        "amount": float(contribution.amount),
        "payment_method": payment_method_str,
        "payment_reference": contribution.transaction_ref,
        "confirmation_status": confirmation_status.value,
        "created_at": contribution.created_at.isoformat(),
    })


@router.post("/events/{event_id}/contributors/{ec_id}/thank-you")
def send_thank_you_sms(event_id: str, ec_id: str, body: dict = Body(default={}), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Send a thank you SMS to an event contributor."""
    try:
        eid = uuid.UUID(event_id)
        ecid = uuid.UUID(ec_id)
    except ValueError:
        return standard_response(False, "Invalid ID")

    event, is_creator, cm_ty, perms_ty = _get_event_access(db, eid, current_user)
    if not event or (not is_creator and not cm_ty):
        return standard_response(False, "Event not found or access denied")

    ec = db.query(EventContributor).options(
        joinedload(EventContributor.contributor),
    ).filter(EventContributor.id == ecid, EventContributor.event_id == eid).first()
    if not ec:
        return standard_response(False, "Event contributor not found")

    contributor = ec.contributor
    from utils.offline_claims import contributor_notify_phones
    recipients = contributor_notify_phones(ec)
    if not contributor or not recipients:
        return standard_response(False, "Contributor has no phone number")

    custom_message = (body.get("custom_message") or "").strip()
    organizer_phone = format_phone_display(current_user.phone) if current_user.phone else None

    # Compute total contributed amount (confirmed contributions) for this contributor on this event
    total_paid = sum(
        float(c.amount or 0) for c in ec.contributions
        if c.confirmation_status is None or c.confirmation_status == ContributionStatusEnum.confirmed
    )
    currency_code = _currency_code(db, event)

    try:
        from utils.wa_logging import set_wa_log_context
        set_wa_log_context(event_id=str(event.id), event_name=event.name,
                           source_module="contributors", purpose="thank_you_message",
                           recipient_type="contributor",
                           related_entity_type="event_contributor",
                           related_entity_id=str(ec.id))
    except Exception: pass

    sms_failed = False
    for ph in recipients:
        # WhatsApp first
        try:
            from utils.whatsapp import wa_thank_you
            wa_thank_you(ph, contributor.name, event.name, custom_message, organizer_phone=organizer_phone, total_paid=total_paid, currency=currency_code)
        except Exception:
            pass

        # SMS fallback
        try:
            from utils.sms import sms_thank_you
            sms_thank_you(ph, contributor.name, event.name, custom_message, organizer_phone=organizer_phone, total_paid=total_paid, currency=currency_code)
        except Exception:
            sms_failed = True

    if sms_failed:
        return standard_response(False, "We couldn't send the message. Please try again.")

    return standard_response(True, "Thank you sent", {"sent": True})


# ══════════════════════════════════════════════
# BULK CONTRIBUTORS
# ══════════════════════════════════════════════

@router.post("/events/{event_id}/contributors/bulk")
def bulk_add_contributors(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Queue a contributor bulk-import job and return immediately.

    Body: { contributors: [{ name, phone, amount? }], send_sms?: bool,
            mode?: "targets" | "contributions", payment_method?: str }

    Processing happens in a Celery background task
    (``tasks.contributor_imports.process_contributor_import_job``). The
    caller polls ``GET /events/{event_id}/contributor-imports/{job_id}``
    for live status, counts and per-row errors.
    """
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    # Owner OR creator may bulk-upload.
    from utils.event_owner import user_can_manage_event
    event = db.query(Event).filter(Event.id == eid).first()
    if not event or not user_can_manage_event(event, current_user):
        return standard_response(False, "Only the event owner or creator can perform bulk uploads")

    rows = body.get("contributors", [])
    if not rows or not isinstance(rows, list):
        return standard_response(False, "No contributors provided")

    if len(rows) > 2000:
        return standard_response(False, "Maximum 2000 contributors per upload")

    from models import ContributorImportJob
    job = ContributorImportJob(
        id=uuid.uuid4(),
        event_id=eid,
        created_by=current_user.id,
        status="queued",
        mode=(body.get("mode") or "targets"),
        payment_method=body.get("payment_method"),
        send_sms=bool(body.get("send_sms", False)),
        total_rows=len(rows),
        payload={"contributors": rows},
        errors=[],
    )
    db.add(job)
    db.commit()
    db.refresh(job)

    # Return immediately after the job row is accepted. Dispatch happens in a
    # daemon thread so Redis/Celery connection timeouts never block the user.
    import threading

    def _dispatch_job(jid: str):
        try:
            from tasks.contributor_imports import process_contributor_import_job
            process_contributor_import_job.delay(jid)
        except Exception as e:
            print(f"[bulk_import] celery enqueue failed, falling back to thread: {e}")
            try:
                from tasks.contributor_imports import process_contributor_import_job as _proc
                _proc.run(jid)
            except Exception as ex:
                print(f"[bulk_import] background thread failed: {ex}")

    threading.Thread(target=_dispatch_job, args=(str(job.id),), daemon=True).start()


    return standard_response(
        True,
        "Upload received. Processing contributors in the background.",
        {
            "job_id": str(job.id),
            "status": job.status,
            "total_rows": job.total_rows,
        },
    )


@router.get("/events/{event_id}/contributor-imports/{job_id}")
def get_contributor_import_status(event_id: str, job_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Poll a contributor-import job for status and progress."""
    try:
        eid = uuid.UUID(event_id)
        jid = uuid.UUID(job_id)
    except ValueError:
        return standard_response(False, "Invalid id")

    from utils.event_owner import user_can_manage_event
    from models import ContributorImportJob
    event = db.query(Event).filter(Event.id == eid).first()
    if not event or not user_can_manage_event(event, current_user):
        return standard_response(False, "Not authorised")

    job = db.query(ContributorImportJob).filter(
        ContributorImportJob.id == jid,
        ContributorImportJob.event_id == eid,
    ).first()
    if not job:
        return standard_response(False, "Job not found")

    return standard_response(True, "OK", {
        "job_id": str(job.id),
        "status": job.status,
        "mode": job.mode,
        "total_rows": job.total_rows,
        "processed_rows": job.processed_rows,
        "successful_rows": job.successful_rows,
        "failed_rows": job.failed_rows,
        "error_message": job.error_message,
        "started_at": job.started_at.isoformat() if job.started_at else None,
        "finished_at": job.finished_at.isoformat() if job.finished_at else None,
        "created_at": job.created_at.isoformat() if job.created_at else None,
    })


@router.get("/events/{event_id}/contributor-imports/{job_id}/errors")
def get_contributor_import_errors(event_id: str, job_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Return the list of per-row errors for a completed job."""
    try:
        eid = uuid.UUID(event_id)
        jid = uuid.UUID(job_id)
    except ValueError:
        return standard_response(False, "Invalid id")

    from utils.event_owner import user_can_manage_event
    from models import ContributorImportJob
    event = db.query(Event).filter(Event.id == eid).first()
    if not event or not user_can_manage_event(event, current_user):
        return standard_response(False, "Not authorised")

    job = db.query(ContributorImportJob).filter(
        ContributorImportJob.id == jid,
        ContributorImportJob.event_id == eid,
    ).first()
    if not job:
        return standard_response(False, "Job not found")

    return standard_response(True, "OK", {
        "job_id": str(job.id),
        "errors": list(job.errors or []),
    })


# NOTE: the original synchronous bulk implementation has been moved into
# ``tasks.contributor_imports.process_contributor_import_job``. The legacy
# inline body below is retained as a private helper for reference but is
# no longer reachable from the HTTP layer.
def _legacy_bulk_add_contributors_inline(event_id: str, body: dict, db: Session, current_user: User):
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Only event creator can perform bulk uploads")
    rows = body.get("contributors", [])
    if not rows or not isinstance(rows, list):
        return standard_response(False, "No contributors provided")
    if len(rows) > 500:
        return standard_response(False, "Maximum 500 contributors per upload")

    send_sms = body.get("send_sms", False)
    mode = body.get("mode", "targets")  # "targets" or "contributions"
    payment_method_str = body.get("payment_method", "other")

    now = datetime.now(EAT)
    currency = _currency_code(db, event)
    organizer = db.query(User).filter(User.id == event.organizer_id).first()
    organizer_phone = format_phone_display(organizer.phone) if organizer and organizer.phone else None

    results = []
    errors_list = []

    for idx, row in enumerate(rows):
        row_num = idx + 1
        name = (row.get("name") or "").strip()
        phone_raw = (row.get("phone") or "").strip()
        amount = float(row.get("amount") or 0)

        if not name:
            errors_list.append({"row": row_num, "message": "Name is required"})
            continue

        if not phone_raw:
            errors_list.append({"row": row_num, "message": f"Phone is required for {name}"})
            continue

        # Validate & format phone
        try:
            phone = validate_phone_number(phone_raw)
        except ValueError:
            errors_list.append({"row": row_num, "message": f"Invalid phone for {name}: {phone_raw}"})
            continue

        # Find existing contributor by phone ONLY in user's address book
        contributor = db.query(UserContributor).filter(
            UserContributor.user_id == current_user.id,
            UserContributor.phone == phone,
        ).first()

        if not contributor:
            # Create new contributor — does NOT remove any existing ones
            contributor = UserContributor(
                id=uuid.uuid4(),
                user_id=current_user.id,
                name=name,
                phone=phone,
                created_at=now,
                updated_at=now,
            )
            db.add(contributor)
            db.flush()
        else:
            # Update name if provided and different
            if name and contributor.name != name:
                contributor.name = name
                contributor.updated_at = now

        # Check if already linked to event
        ec = db.query(EventContributor).filter(
            EventContributor.event_id == eid,
            EventContributor.contributor_id == contributor.id,
        ).first()

        if mode == "targets":
            if ec:
                old_pledge = float(ec.pledge_amount or 0)
                ec.pledge_amount = amount
                ec.updated_at = now
                action = "updated"

                if send_sms and amount > 0 and amount != old_pledge:
                    from utils.offline_claims import contributor_notify_phones
                    # Pledge reductions fall back to ``set`` (no reduction template yet).
                    is_increase = amount > old_pledge and old_pledge > 0
                    pay_instr = (event.contribution_payment_instructions or "").strip() or None
                    for ph in contributor_notify_phones(ec):
                        try:
                            if is_increase:
                                from utils.sms import sms_contribution_target_updated
                                sms_contribution_target_updated(
                                    ph, contributor.name, event.name,
                                    increase=(amount - old_pledge),
                                    total_target=amount,
                                    currency=currency,
                                    organizer_phone=organizer_phone,
                                    payment_instructions=pay_instr,
                                )
                            else:
                                from utils.sms import sms_contribution_target_set
                                sms_contribution_target_set(
                                    ph, contributor.name, event.name,
                                    amount, currency=currency,
                                    organizer_phone=organizer_phone,
                                    payment_instructions=pay_instr,
                                )
                        except Exception:
                            pass
            else:
                ec = EventContributor(
                    id=uuid.uuid4(),
                    event_id=eid,
                    contributor_id=contributor.id,
                    pledge_amount=amount,
                    created_at=now,
                    updated_at=now,
                )
                db.add(ec)
                db.flush()
                action = "added"

                if send_sms and amount > 0:
                    from utils.offline_claims import contributor_notify_phones
                    pay_instr = (event.contribution_payment_instructions or "").strip() or None
                    for ph in contributor_notify_phones(ec):
                        try:
                            from utils.sms import sms_contribution_target_set
                            sms_contribution_target_set(
                                ph, contributor.name,
                                event.name, amount, 0, currency,
                                organizer_phone=organizer_phone,
                                payment_instructions=pay_instr,
                            )
                        except Exception:
                            pass
        else:  # mode == "contributions"
            if not ec:
                ec = EventContributor(
                    id=uuid.uuid4(),
                    event_id=eid,
                    contributor_id=contributor.id,
                    pledge_amount=0,
                    created_at=now,
                    updated_at=now,
                )
                db.add(ec)
                db.flush()

            if amount > 0:
                payment_method = None
                if payment_method_str:
                    try:
                        payment_method = PaymentMethodEnum(payment_method_str)
                    except ValueError:
                        pass

                contribution = EventContribution(
                    id=uuid.uuid4(),
                    event_id=eid,
                    event_contributor_id=ec.id,
                    contributor_name=(getattr(ec, "display_name", None) or contributor.name),
                    amount=amount,
                    payment_method=payment_method,
                    confirmation_status=ContributionStatusEnum.confirmed,
                    confirmed_at=now,
                    contributed_at=now,
                    created_at=now,
                    updated_at=now,
                )
                db.add(contribution)

                if send_sms:
                    from utils.offline_claims import contributor_notify_phones
                    for ph in contributor_notify_phones(ec):
                        try:
                            from utils.sms import sms_contribution_recorded
                            total_paid_so_far = sum(float(c.amount or 0) for c in ec.contributions) + amount
                            pledge = float(ec.pledge_amount or 0)
                            sms_contribution_recorded(
                                ph, contributor.name,
                                event.name, amount, pledge, total_paid_so_far, currency,
                                organizer_phone=organizer_phone
                            )
                        except Exception:
                            pass

            action = "recorded"

        results.append({"row": row_num, "name": name, "action": action})

    db.commit()

    return standard_response(True, f"Bulk operation complete: {len(results)} processed, {len(errors_list)} errors", {
        "processed": len(results),
        "errors_count": len(errors_list),
        "results": results,
        "errors": errors_list,
    })


@router.get("/events/{event_id}/contributors/{ec_id}/payments")
def get_payment_history(event_id: str, ec_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        eid = uuid.UUID(event_id)
        ecid = uuid.UUID(ec_id)
    except ValueError:
        return standard_response(False, "Invalid ID")

    event, is_creator, cm_ph, perms_ph = _get_event_access(db, eid, current_user)
    if not event or (not is_creator and not cm_ph):
        return standard_response(False, "Event not found or access denied")

    ec = db.query(EventContributor).options(
        joinedload(EventContributor.contributor),
        joinedload(EventContributor.contributions),
    ).filter(EventContributor.id == ecid, EventContributor.event_id == eid).first()
    if not ec:
        return standard_response(False, "Event contributor not found")

    payments = sorted(ec.contributions, key=lambda p: p.created_at or datetime.min, reverse=True)

    return standard_response(True, "Payment history fetched", {
        "contributor": _contributor_dict(ec.contributor) if ec.contributor else None,
        "pledge_amount": float(ec.pledge_amount or 0),
        "total_paid": sum(float(p.amount or 0) for p in payments),
        "payments": [{
            "id": str(p.id),
            "amount": float(p.amount),
            "payment_method": p.payment_method.value if p.payment_method else None,
            "payment_reference": p.transaction_ref,
            "confirmation_status": p.confirmation_status.value if p.confirmation_status else "confirmed",
            "recorded_by_name": (
                f"{p.recorder.first_name} {p.recorder.last_name}" if is_creator and p.recorded_by and hasattr(p, 'recorder') and p.recorder else None
            ),
            "created_at": p.created_at.isoformat() if p.created_at else None,
        } for p in payments],
    })


# ══════════════════════════════════════════════
# CONTRIBUTION CONFIRMATION (Creator only)
# ══════════════════════════════════════════════

@router.get("/events/{event_id}/pending-contributions")
def get_pending_contributions(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Get all pending contributions awaiting creator confirmation."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Only event creator can view pending contributions")

    pending = db.query(EventContribution).filter(
        EventContribution.event_id == eid,
        EventContribution.confirmation_status == ContributionStatusEnum.pending,
    ).order_by(EventContribution.created_at.desc()).all()

    from utils.batch_loaders import build_pending_contribution_dicts
    # Organiser is the auditor of record — always include offline-claim audit fields.
    items = build_pending_contribution_dicts(db, pending, include_status=False, include_audit=True)

    return standard_response(True, "Pending contributions fetched", {"contributions": items, "count": len(items)})


@router.get("/events/{event_id}/my-recorded-contributions")
def get_my_recorded_contributions(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Get contributions recorded by the current committee member."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event, is_creator, cm, perms = _get_event_access(db, eid, current_user)
    if not event:
        return standard_response(False, "Event not found")
    if is_creator:
        return standard_response(False, "Event creator cannot use this endpoint; use pending-contributions instead")
    if not cm or not perms or not perms.can_manage_contributions:
        return standard_response(False, "You do not have permission to record contributions")

    # Get all contributions recorded by this committee member
    contributions = db.query(EventContribution).filter(
        EventContribution.event_id == eid,
        EventContribution.recorded_by == current_user.id,
    ).order_by(EventContribution.created_at.desc()).all()

    from utils.batch_loaders import build_pending_contribution_dicts
    # Committee members with `can_manage_contributions` already see amounts;
    # show full audit (channel, payer account, receipt) to them too.
    can_audit = bool(perms and getattr(perms, "can_manage_contributions", False))
    items = build_pending_contribution_dicts(db, contributions, include_status=True, include_audit=can_audit)

    return standard_response(True, "Your recorded contributions fetched", {"contributions": items, "count": len(items)})


@router.post("/events/{event_id}/confirm-contributions")
def confirm_contributions(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Confirm one or more pending contributions. Body: { contribution_ids: [...] }"""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Only event creator can confirm contributions")

    ids = body.get("contribution_ids", [])
    if not ids:
        return standard_response(False, "No contribution IDs provided")

    now = datetime.now(EAT)
    currency = _currency_code(db, event)
    confirmed_count = 0
    notify_targets = []  # collect (phone, msg) tuples for after-commit dispatch

    for cid_str in ids:
        try:
            cid = uuid.UUID(cid_str)
        except ValueError:
            continue
        c = db.query(EventContribution).filter(
            EventContribution.id == cid,
            EventContribution.event_id == eid,
            EventContribution.confirmation_status == ContributionStatusEnum.pending,
        ).first()
        if c:
            c.confirmation_status = ContributionStatusEnum.confirmed
            c.confirmed_at = now
            c.claim_reviewed_at = now
            c.claim_reviewed_by = current_user.id
            c.updated_at = now
            confirmed_count += 1

            # Approval notification — routed via secondary-phone helper.
            ec = db.query(EventContributor).options(
                joinedload(EventContributor.contributor),
            ).filter(EventContributor.id == c.event_contributor_id).first()
            if ec:
                from utils.offline_claims import contributor_notify_phones
                msg = (
                    f"Hello {ec.contributor.name if ec.contributor else 'there'}, your contribution of "
                    f"{currency} {float(c.amount):,.0f} for {event.name} has been "
                    f"confirmed by the event organiser. Thank you!"
                )
                for phone in contributor_notify_phones(ec):
                    notify_targets.append((phone, msg))

                # Now that the contribution is approved, announce it in the
                # event group chat. We deliberately skip this on initial
                # submission so members never see contributions that may
                # later be rejected.
                try:
                    from api.routes.event_groups import post_payment_system_message
                    total_paid_after = sum(
                        float(x.amount or 0) for x in ec.contributions
                        if x.confirmation_status is None
                        or x.confirmation_status == ContributionStatusEnum.confirmed
                    )
                    pledge_amount = float(ec.pledge_amount or 0)
                    post_payment_system_message(
                        db, eid,
                        ec.contributor.name if ec.contributor else "Someone",
                        float(c.amount or 0), pledge_amount,
                        total_paid_after, currency,
                    )
                except Exception:
                    pass

    db.commit()

    # Fire WhatsApp + SMS-fallback notifications (best-effort, post-commit)
    try:
        from utils.notify_channels import notify_user_wa_sms
        for phone, msg in notify_targets:
            try:
                notify_user_wa_sms(phone, msg)
            except Exception as e:
                print(f"[confirm-contributions] notify failed: {e}")
    except Exception:
        pass

    return standard_response(True, f"{confirmed_count} contributions confirmed", {"confirmed": confirmed_count})


# ══════════════════════════════════════════════
# REJECT PENDING CONTRIBUTIONS (Creator only)
# ══════════════════════════════════════════════

@router.post("/events/{event_id}/reject-contributions")
def reject_contributions(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Reject one or more pending contributions. Deletes the record and notifies the contributor."""
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Only event creator can reject contributions")

    ids = body.get("contribution_ids", [])
    reason = (body.get("rejection_reason") or "").strip() or None
    delete_records = bool(body.get("delete", True))  # legacy default = delete
    if not ids:
        return standard_response(False, "No contribution IDs provided")

    currency = _currency_code(db, event)
    now = datetime.now(EAT)
    rejected_count = 0
    for cid_str in ids:
        try:
            cid = uuid.UUID(cid_str)
        except ValueError:
            continue
        c = db.query(EventContribution).filter(
            EventContribution.id == cid,
            EventContribution.event_id == eid,
            EventContribution.confirmation_status == ContributionStatusEnum.pending,
        ).first()
        if c:
            ec = db.query(EventContributor).options(
                joinedload(EventContributor.contributor),
            ).filter(EventContributor.id == c.event_contributor_id).first()
            recorder = db.query(User).filter(User.id == c.recorded_by).first() if c.recorded_by else None
            recorder_name = f"{recorder.first_name} {recorder.last_name}" if recorder else "a committee member"

            # Notify contributor (routed via secondary-phone helper).
            if ec:
                try:
                    from utils.notify_channels import notify_user_wa_sms
                    from utils.offline_claims import contributor_notify_phones
                    why = f" Reason: {reason}." if reason else ""
                    msg = (
                        f"Hello {ec.contributor.name if ec.contributor else 'there'}, "
                        f"a contribution record of {currency} {float(c.amount):,.0f} for {event.name} "
                        f"recorded by {recorder_name} could not be verified by the event organiser.{why} "
                        f"Please contact the organiser if you believe this is an error."
                    )
                    for phone in contributor_notify_phones(ec):
                        try:
                            notify_user_wa_sms(phone, msg)
                        except Exception:
                            pass
                except Exception:
                    pass

            if delete_records:
                # Delete associated thank-you message if any
                db.query(ContributionThankYouMessage).filter(
                    ContributionThankYouMessage.contribution_id == cid
                ).delete()
                db.delete(c)
            else:
                # Soft-reject: keep the row + audit trail, mark as rejected
                c.confirmation_status = ContributionStatusEnum.rejected
                c.claim_reviewed_at = now
                c.claim_reviewed_by = current_user.id
                c.claim_rejection_reason = reason
                c.updated_at = now
            rejected_count += 1

    db.commit()
    return standard_response(True, f"{rejected_count} contributions rejected and removed", {"rejected": rejected_count})


# ══════════════════════════════════════════════
# DELETE A SPECIFIC CONTRIBUTION/TRANSACTION
# ══════════════════════════════════════════════

@router.delete("/events/{event_id}/contributors/{ec_id}/payments/{payment_id}")
def delete_contribution(event_id: str, ec_id: str, payment_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Delete a specific payment/transaction record. Creator only."""
    try:
        eid = uuid.UUID(event_id)
        ecid = uuid.UUID(ec_id)
        pid = uuid.UUID(payment_id)
    except ValueError:
        return standard_response(False, "Invalid ID")

    event = db.query(Event).filter(Event.id == eid, Event.organizer_id == current_user.id).first()
    if not event:
        return standard_response(False, "Only event creator can delete transactions")

    contribution = db.query(EventContribution).filter(
        EventContribution.id == pid,
        EventContribution.event_id == eid,
        EventContribution.event_contributor_id == ecid,
    ).first()
    if not contribution:
        return standard_response(False, "Transaction not found")

    # Delete associated thank you message
    db.query(ContributionThankYouMessage).filter(
        ContributionThankYouMessage.contribution_id == pid
    ).delete()
    db.delete(contribution)
    db.commit()

    return standard_response(True, "Transaction deleted successfully")


# ══════════════════════════════════════════════
# CONTRIBUTION REPORT (date-filtered)
# ══════════════════════════════════════════════

@router.get("/events/{event_id}/contribution-report")
def get_contribution_report(
    event_id: str,
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Returns contributor payment totals filtered by date range.
    Only payments (EventContribution) within the date range are summed.
    Pledges are shown as-is (not date-filtered) for context, but the
    report header warns that balances may be partial.
    """
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event, is_creator, cm, perms = _get_event_access(db, eid, current_user)
    if not event:
        return standard_response(False, "Event not found")
    if not is_creator and not cm:
        return standard_response(False, "Access denied")

    # Parse dates
    from_dt = None
    to_dt = None
    if date_from:
        try:
            from_dt = datetime.strptime(date_from, "%Y-%m-%d").replace(hour=0, minute=0, second=0, tzinfo=EAT)
        except ValueError:
            return standard_response(False, "Invalid date_from format, use YYYY-MM-DD")
    if date_to:
        try:
            to_dt = datetime.strptime(date_to, "%Y-%m-%d").replace(hour=23, minute=59, second=59, tzinfo=EAT)
        except ValueError:
            return standard_response(False, "Invalid date_to format, use YYYY-MM-DD")

    # Get all event contributors (deduplicate joinedload inflation)
    raw_ecs = db.query(EventContributor).options(
        joinedload(EventContributor.contributor),
        joinedload(EventContributor.contributions),
    ).filter(EventContributor.event_id == eid).all()
    seen_ids = set()
    ecs = []
    for ec in raw_ecs:
        if ec.id not in seen_ids:
            seen_ids.add(ec.id)
            ecs.append(ec)

    currency = _currency_code(db, event)
    results = []
    # Full (all-time) totals for summary cards
    full_total_pledged = 0
    full_total_paid = 0
    full_total_balance = 0

    for ec in ecs:
        pledge = float(ec.pledge_amount or 0)
        # All confirmed payments (for full summary)
        all_confirmed = [
            c for c in ec.contributions
            if (not hasattr(c, 'confirmation_status') or c.confirmation_status is None or c.confirmation_status == ContributionStatusEnum.confirmed)
        ]
        all_paid = sum(float(c.amount or 0) for c in all_confirmed)
        all_balance = max(0, pledge - all_paid)
        full_total_pledged += pledge
        full_total_paid += all_paid
        full_total_balance += all_balance

        # Filter payments by date range (for table rows)
        if from_dt or to_dt:
            def _make_aware(dt):
                """Ensure datetime is timezone-aware for comparison."""
                if dt is None:
                    return None
                if dt.tzinfo is None:
                    return EAT.localize(dt)
                return dt

            filtered_payments = [
                c for c in all_confirmed
                if (not from_dt or (c.contributed_at and _make_aware(c.contributed_at) >= from_dt))
                and (not to_dt or (c.contributed_at and _make_aware(c.contributed_at) <= to_dt))
            ]
            paid_in_range = sum(float(c.amount or 0) for c in filtered_payments)
        else:
            paid_in_range = all_paid

        # When date-filtered, only include contributors with payments in range
        if from_dt or to_dt:
            if paid_in_range > 0:
                results.append({
                    "name": ec.contributor.name if ec.contributor else "Unknown",
                    "phone": ec.contributor.phone if ec.contributor else None,
                    "pledged": pledge,
                    "paid": paid_in_range,
                    "balance": max(0, pledge - paid_in_range),
                })
        else:
            # Include ALL event contributors in unfiltered reports — even
            # those with no pledge/target and no payments yet. Owners want
            # the full roster on the PDF, not just active payers.
            results.append({
                "name": ec.contributor.name if ec.contributor else "Unknown",
                "phone": ec.contributor.phone if ec.contributor else None,
                "pledged": pledge,
                "paid": paid_in_range,
                "balance": max(0, pledge - paid_in_range),
            })

    # Sort alphabetically
    results.sort(key=lambda r: r["name"])

    table_total_paid = sum(r["paid"] for r in results)

    return standard_response(True, "Report data fetched", {
        "contributors": results,
        "full_summary": {
            "total_pledged": full_total_pledged,
            "total_paid": full_total_paid,
            "total_balance": full_total_balance,
            "count": len(ecs),
            "currency": currency,
        },
        "filtered_summary": {
            "total_paid": table_total_paid,
            "contributor_count": len(results),
        },
        "date_from": date_from,
        "date_to": date_to,
        "is_filtered": bool(date_from or date_to),
    })


# ──────────────────────────────────────────────
# Bulk Messaging by Contribution Status
# ──────────────────────────────────────────────

@router.post("/events/{event_id}/bulk-message")
def send_bulk_contributor_message(event_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """
    Send bulk SMS to contributors filtered by contribution status.
    Body: {
        case_type: "no_contribution" | "partial" | "completed",
        message_template: str,
        payment_info?: str,
        contributor_ids: [ec_id, ...]
    }
    Template variables: {name}, {event_name}, {event_title}, {payment}
    """
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    # Permission: must be event creator or committee member with contribution permissions
    is_creator = str(event.organizer_id) == str(current_user.id)
    if not is_creator:
        member = db.query(EventCommitteeMember).filter(
            EventCommitteeMember.event_id == eid,
            EventCommitteeMember.user_id == current_user.id,
            EventCommitteeMember.status == "active",
        ).first()
        if not member:
            return standard_response(False, "Not authorized", status_code=403)

    case_type = body.get("case_type", "")
    message_template = (body.get("message_template") or "").strip()
    payment_info = (body.get("payment_info") or "").strip()
    contributor_ids = body.get("contributor_ids", [])

    if not message_template:
        return standard_response(False, "Message template is required")
    if not contributor_ids:
        return standard_response(False, "No contributors selected")
    if len(contributor_ids) > 1000:
        return standard_response(False, "Maximum 1000 recipients per batch")

    # Persist the customisation per (event, case_type) so the organiser
    # doesn't have to retype the message template, payment info or contact
    # phone next time. Best-effort — never block the actual send.
    if case_type in ("no_contribution", "partial", "completed", "not_pledged"):
        try:
            tpl = db.query(EventMessagingTemplate).filter(
                EventMessagingTemplate.event_id == eid,
                EventMessagingTemplate.case_type == case_type,
            ).first()
            contact_phone_save = (body.get("contact_phone") or "").strip() or None
            if tpl:
                tpl.message_template = message_template
                tpl.payment_info = payment_info or None
                tpl.contact_phone = contact_phone_save
                tpl.updated_by = current_user.id
            else:
                db.add(EventMessagingTemplate(
                    event_id=eid,
                    case_type=case_type,
                    message_template=message_template,
                    payment_info=payment_info or None,
                    contact_phone=contact_phone_save,
                    updated_by=current_user.id,
                ))
            db.commit()
        except Exception as e:
            print(f"[bulk-message] template save failed (non-fatal): {e}")
            db.rollback()

    # Fetch event contributors with their contributor details
    ec_uuids = []
    for cid in contributor_ids:
        try:
            ec_uuids.append(uuid.UUID(cid))
        except ValueError:
            continue

    ecs = db.query(EventContributor).options(
        joinedload(EventContributor.contributor),
        joinedload(EventContributor.contributions)
    ).filter(
        EventContributor.event_id == eid,
        EventContributor.id.in_(ec_uuids)
    ).all()

    # Build the recipient list once, then hand off to the async batch
    # pipeline. The endpoint returns 202 Accepted in <1s — actual SMS
    # dispatch happens in a Celery worker (or inline with a wall-clock
    # budget when running on Vercel). Idempotency, dedup and retry are
    # all enforced inside utils.sms_batch.
    recipients = []
    invalid = []
    for ec in ecs:
        c = ec.contributor
        if not c or not c.phone:
            invalid.append(c.name if c else "Unknown")
            continue
        recipients.append({
            "phone": c.phone,
            "name": c.name or "Contributor",
            "event_contributor_id": str(ec.id),
        })

    organiser = db.query(User).filter(User.id == event.organizer_id).first()
    override_phone = (body.get("contact_phone") or "").strip() or None

    from utils.sms_batch import build_batch
    batch_row, _jobs, dedup, was_existing = build_batch(
        db,
        event=event,
        organiser=organiser,
        recipients=recipients,
        message_template=message_template,
        payment_info=payment_info or None,
        override_contact_phone=override_phone,
    )
    batch_id = str(batch_row._mapping["id"])
    recipient_count = int(batch_row._mapping["recipient_count"] or 0)

    # Decide dispatch mode: prefer Celery+Redis, fall back to inline.
    # Skip dispatch entirely when there's nothing to send — otherwise the
    # worker logs the misleading "{'sent': 0, 'failed': 0}" we've been
    # chasing.
    mode = "skipped_empty" if recipient_count == 0 and not was_existing else "inline"
    if recipient_count > 0 or was_existing:
        try:
            from core.celery_app import CELERY_ENABLED
            from core.redis import redis_available
            if CELERY_ENABLED and redis_available():
                from tasks.sms_dispatch import send_batch as send_batch_task
                send_batch_task.delay(batch_id)
                mode = "queued"
                print(f"[bulk-message] queued batch={batch_id} recipients={recipient_count} reused={was_existing} case={case_type}")
        except Exception as e:  # noqa: BLE001
            print(f"[bulk-message] celery dispatch unavailable, falling back inline: {e}")

        if mode == "inline":
            # Vercel / no-broker path: do as much work as we can within the
            # serverless time budget; the beat task picks up the rest.
            try:
                from utils.sms_batch import flush_batch_inline
                result = flush_batch_inline(db, batch_id, time_budget_seconds=8.0)
                print(f"[bulk-message] inline flush batch={batch_id} result={result}")
            except Exception as e:  # noqa: BLE001
                print(f"[bulk-message] inline flush error: {e}")
    else:
        print(f"[bulk-message] SKIPPED dispatch batch={batch_id} — 0 valid recipients after dedup/normalisation (case={case_type})")

    return standard_response(
        True,
        "Reminder batch accepted" if not was_existing else "Existing batch reused (idempotent — already sent within last hour)",
        {
            "batch_id": batch_id,
            "queued": recipient_count,
            "skipped_self": dedup.self_skipped,
            "skipped_duplicate": dedup.duplicate_skipped,
            "skipped_invalid_phone": dedup.invalid_phone + invalid,
            "mode": mode,
            "idempotent_replay": was_existing,
        },
    )


@router.get("/events/{event_id}/bulk-message/{batch_id}")
def get_bulk_message_status(
    event_id: str,
    batch_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Poll the progress of a previously accepted bulk SMS batch."""
    try:
        eid = uuid.UUID(event_id)
        bid = uuid.UUID(batch_id)
    except ValueError:
        return standard_response(False, "Invalid id")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    is_creator = str(event.organizer_id) == str(current_user.id)
    if not is_creator:
        member = db.query(EventCommitteeMember).filter(
            EventCommitteeMember.event_id == eid,
            EventCommitteeMember.user_id == current_user.id,
            EventCommitteeMember.status == "active",
        ).first()
        if not member:
            return standard_response(False, "Not authorized", status_code=403)

    from utils.sms_batch import batch_status
    status = batch_status(db, str(bid))
    if not status or status.get("event_id") != str(eid):
        return standard_response(False, "Batch not found")
    return standard_response(True, "Batch status", status)

# ══════════════════════════════════════════════════════════════════════════════
# MY CONTRIBUTIONS — events where the logged-in user is listed as a contributor
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/my-contributions")
def my_contributions(
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Return all events where the logged-in user is recorded as a contributor
    (matched via UserContributor.contributor_user_id OR phone-equivalence
    backfill), with pledge / paid / balance / pending totals per event.
    """
    # 1. Find every user_contributors row that points to the current user.
    #    We match on contributor_user_id (preferred) AND on phone equivalence
    #    (covers legacy rows where the FK wasn't set yet).
    me_phone_digits = _normalize_phone_digits(current_user.phone) if getattr(current_user, "phone", None) else ""

    q = db.query(UserContributor).filter(UserContributor.contributor_user_id == current_user.id)
    contributors = q.all()

    if me_phone_digits:
        from sqlalchemy import func as _f
        legacy = db.query(UserContributor).filter(
            UserContributor.contributor_user_id.is_(None),
            UserContributor.phone.isnot(None),
            _f.right(_f.regexp_replace(UserContributor.phone, r'[^0-9]', '', 'g'), 9) == me_phone_digits,
        ).all()
        # Opportunistically backfill the FK so future queries are fast.
        if legacy:
            for c in legacy:
                c.contributor_user_id = current_user.id
            try:
                db.commit()
            except Exception:
                db.rollback()
        contributors.extend(legacy)

    if not contributors:
        return standard_response(True, "No contributions found", {"events": [], "count": 0})

    contributor_ids = [c.id for c in contributors]

    # 2. Fetch every EventContributor row for those contributors, joined with
    #    the event and contributions.
    ecs = db.query(EventContributor).options(
        joinedload(EventContributor.event),
        joinedload(EventContributor.contributions),
    ).filter(EventContributor.contributor_id.in_(contributor_ids)).all()

    # Fallback currency: prefer the signed-in user's profile currency over a
    # hardcoded "TZS" so users in other regions never see the wrong code.
    user_currency = (getattr(current_user, "currency_code", None) or "").strip() or None

    results = []
    for ec in ecs:
        event = ec.event
        if not event:
            continue
        # Prefer the event's own currency; otherwise fall back to the user's
        # profile currency (set at signup based on locale), and only as a
        # last resort to the global default.
        if event.currency_id:
            cur = db.query(Currency).filter(Currency.id == event.currency_id).first()
            currency = cur.code.strip() if cur else (user_currency or "TZS")
        else:
            currency = user_currency or "TZS"
        pledge = float(ec.pledge_amount or 0)
        paid = sum(
            float(c.amount or 0)
            for c in ec.contributions
            if c.confirmation_status is None or c.confirmation_status == ContributionStatusEnum.confirmed
        )
        pending = sum(
            float(c.amount or 0)
            for c in ec.contributions
            if c.confirmation_status == ContributionStatusEnum.pending
        )
        organizer = db.query(User).filter(User.id == event.organizer_id).first()

        cover = event.cover_image_url
        if not cover:
            featured = (
                db.query(EventImage)
                .filter(EventImage.event_id == event.id)
                .order_by(EventImage.is_featured.desc(), EventImage.created_at.asc())
                .first()
            )
            if featured:
                cover = featured.image_url

        balance_val = max(0.0, pledge - paid - pending)
        # status:
        #   complete = fully paid (no balance, no pending)
        #   pending  = nothing paid yet
        #   active   = partially paid with remaining balance/pending
        if pledge > 0 and balance_val == 0 and pending == 0:
            status = "complete"
        elif paid == 0 and pending == 0:
            status = "pending"
        else:
            status = "active"

        results.append({
            "event_id": str(event.id),
            "event_name": event.name,
            "event_cover_image_url": cover,
            "event_start_date": event.start_date.isoformat() if event.start_date else None,
            "event_start_time": event.start_date.strftime("%H:%M") if event.start_date else None,
            "event_location": event.location,
            "organizer_name": get_event_owner_display_name(event, db=db) or (f"{organizer.first_name} {organizer.last_name}".strip() if organizer else None),
            "event_contributor_id": str(ec.id),
            "currency": currency,
            "pledge_amount": pledge,
            "total_paid": paid,
            "pending_amount": pending,
            "balance": balance_val,
            "status": status,
            "last_payment_at": max(
                (c.contributed_at for c in ec.contributions if c.contributed_at),
                default=None,
            ).isoformat() if any(c.contributed_at for c in ec.contributions) else None,
        })

    # Sort by upcoming event date asc, then by name
    results.sort(key=lambda r: (r["event_start_date"] or "9999", r["event_name"] or ""))

    if search:
        term = search.strip().lower()
        results = [
            r for r in results
            if term in (r.get("event_name") or "").lower()
            or term in (r.get("event_location") or "").lower()
            or term in (r.get("organizer_name") or "").lower()
        ]

    summary = {
        "total_pledged": sum(r["pledge_amount"] for r in results),
        "total_paid": sum(r["total_paid"] for r in results),
        "total_pending": sum(r["pending_amount"] for r in results),
        "total_balance": sum(r["balance"] for r in results),
        "active_pledges": sum(1 for r in results if r["status"] == "active"),
        "complete_count": sum(1 for r in results if r["status"] == "complete"),
        "pending_count": sum(1 for r in results if r["status"] == "pending"),
        "currency": (results[0]["currency"] if results else None) or user_currency,
    }

    return standard_response(True, "My contributions fetched", {
        "events": results,
        "count": len(results),
        "summary": summary,
    })


# ──────────────────────────────────────────────────────────────────────────────
# Per-event saved messaging templates (composer customisations)
# ──────────────────────────────────────────────────────────────────────────────

@router.get("/events/{event_id}/messaging-templates")
def get_messaging_templates(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return saved customisations keyed by case_type for this event.

    Response shape: ``{ templates: { no_contribution: {...}, partial: {...}, completed: {...} } }``
    Only the event creator or an active committee member may read.
    """
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    is_creator = str(event.organizer_id) == str(current_user.id)
    if not is_creator:
        member = db.query(EventCommitteeMember).filter(
            EventCommitteeMember.event_id == eid,
            EventCommitteeMember.user_id == current_user.id,
            EventCommitteeMember.status == "active",
        ).first()
        if not member:
            return standard_response(False, "Not authorized", status_code=403)

    rows = db.query(EventMessagingTemplate).filter(
        EventMessagingTemplate.event_id == eid
    ).all()
    templates = {}
    for r in rows:
        templates[r.case_type] = {
            "message_template": r.message_template,
            "payment_info": r.payment_info,
            "contact_phone": r.contact_phone,
            "updated_at": r.updated_at.isoformat() if r.updated_at else None,
        }
    return standard_response(True, "OK", {"templates": templates})


@router.put("/events/{event_id}/messaging-templates/{case_type}")
def upsert_messaging_template(
    event_id: str,
    case_type: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Manually save (without sending) a per-event messaging customisation.

    Use this when the organiser tweaks the template and wants to persist the
    change without actually sending. The send endpoint also auto-saves.
    """
    if case_type not in ("no_contribution", "partial", "completed", "not_pledged"):
        return standard_response(False, "Invalid case_type")

    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    is_creator = str(event.organizer_id) == str(current_user.id)
    if not is_creator:
        member = db.query(EventCommitteeMember).filter(
            EventCommitteeMember.event_id == eid,
            EventCommitteeMember.user_id == current_user.id,
            EventCommitteeMember.status == "active",
        ).first()
        if not member:
            return standard_response(False, "Not authorized", status_code=403)

    message_template = (body.get("message_template") or "").strip() or None
    payment_info = (body.get("payment_info") or "").strip() or None
    contact_phone = (body.get("contact_phone") or "").strip() or None

    tpl = db.query(EventMessagingTemplate).filter(
        EventMessagingTemplate.event_id == eid,
        EventMessagingTemplate.case_type == case_type,
    ).first()

    if tpl:
        tpl.message_template = message_template
        tpl.payment_info = payment_info
        tpl.contact_phone = contact_phone
        tpl.updated_by = current_user.id
    else:
        tpl = EventMessagingTemplate(
            event_id=eid,
            case_type=case_type,
            message_template=message_template,
            payment_info=payment_info,
            contact_phone=contact_phone,
            updated_by=current_user.id,
        )
        db.add(tpl)
    db.commit()
    db.refresh(tpl)

    return standard_response(True, "Saved", {
        "case_type": case_type,
        "message_template": tpl.message_template,
        "payment_info": tpl.payment_info,
        "contact_phone": tpl.contact_phone,
    })


@router.post("/events/{event_id}/self-contribute")
async def self_contribute(
    event_id: str,
    # Backwards compatible: accept either JSON body OR multipart/form-data.
    # Multipart unlocks the new offline-claim audit fields + receipt image.
    amount: Optional[float] = Form(None),
    payment_reference: Optional[str] = Form(None),
    note: Optional[str] = Form(None),
    payment_channel: Optional[str] = Form(None),     # mobile_money | bank
    provider_id: Optional[str] = Form(None),
    provider_name: Optional[str] = Form(None),
    payer_account: Optional[str] = Form(None),
    transaction_code: Optional[str] = Form(None),
    receipt_image: Optional[UploadFile] = File(None),
    body: Optional[dict] = Body(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """A logged-in contributor records a pending payment for an event.

    Two intake modes:
      * JSON `{ amount, payment_reference?, note? }` — legacy quick path.
      * multipart/form-data with `payment_channel`, `transaction_code`,
        optional `receipt_image` etc. — full offline-claim audit trail.
    Status is always `pending`; the organiser approves/rejects later.
    """
    try:
        eid = uuid.UUID(event_id)
    except ValueError:
        return standard_response(False, "Invalid event ID")

    # Merge JSON body fallback (when caller posts JSON instead of form)
    if body:
        amount = amount if amount is not None else body.get("amount")
        payment_reference = payment_reference or body.get("payment_reference")
        note = note or body.get("note")
        payment_channel = payment_channel or body.get("payment_channel")
        provider_id = provider_id or body.get("provider_id")
        provider_name = provider_name or body.get("provider_name")
        payer_account = payer_account or body.get("payer_account")
        transaction_code = transaction_code or body.get("transaction_code")

    try:
        amount_val = float(amount or 0)
    except (TypeError, ValueError):
        return standard_response(False, "Invalid amount")
    if amount_val <= 0:
        return standard_response(False, "Amount must be greater than zero")

    payment_reference = (payment_reference or "").strip() or None
    note = (note or "").strip() or None
    transaction_code = (transaction_code or "").strip() or None
    payer_account = (payer_account or "").strip() or None
    provider_name = (provider_name or "").strip() or None
    pc = (payment_channel or "").strip().lower() or None
    if pc and pc not in ("mobile_money", "bank"):
        return standard_response(False, "payment_channel must be 'mobile_money' or 'bank'")

    provider_uuid = None
    if provider_id:
        try:
            provider_uuid = uuid.UUID(provider_id)
        except ValueError:
            return standard_response(False, "Invalid provider_id")

    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        return standard_response(False, "Event not found")

    # Locate the EventContributor row for this user (id link, then phone fallback).
    me_phone_digits = _normalize_phone_digits(current_user.phone) if getattr(current_user, "phone", None) else ""
    contributor_q = db.query(UserContributor).filter(
        UserContributor.contributor_user_id == current_user.id,
    )
    candidates = {str(c.id): c for c in contributor_q.all()}
    if me_phone_digits:
        from sqlalchemy import func as _f
        more = db.query(UserContributor).filter(
            UserContributor.phone.isnot(None),
            _f.right(_f.regexp_replace(UserContributor.phone, r'[^0-9]', '', 'g'), 9) == me_phone_digits,
        ).all()
        for c in more:
            candidates[str(c.id)] = c
    if not candidates:
        return standard_response(False, "You are not listed as a contributor for any event", status_code=403)

    ec = db.query(EventContributor).filter(
        EventContributor.event_id == eid,
        EventContributor.contributor_id.in_([c.id for c in candidates.values()]),
    ).first()
    if not ec:
        return standard_response(False, "You are not listed as a contributor for this event", status_code=403)

    contributor = ec.contributor

    # Optional receipt image upload (validated: image-only, ≤5 MB).
    receipt_url = None
    if receipt_image and getattr(receipt_image, "filename", None):
        from utils.offline_claims import upload_receipt_image
        ok, msg, url = await upload_receipt_image(receipt_image)
        if not ok:
            return standard_response(False, msg)
        receipt_url = url

    contact = {}
    if getattr(current_user, "phone", None):
        contact["phone"] = current_user.phone
    if getattr(current_user, "email", None):
        contact["email"] = current_user.email

    contributor_name = contributor.name if contributor else f"{current_user.first_name} {current_user.last_name}".strip()
    now = datetime.now(EAT)

    # Use transaction_code as the canonical reference when given.
    txn_ref = transaction_code or payment_reference

    # Idempotency / gateway dedupe:
    # When the contributor pays via the gateway (SasaPay etc.), the payments
    # webhook (payments.py) already inserts a CONFIRMED EventContribution keyed
    # by transaction_ref. The web/mobile UI then ALSO posts here with the same
    # `payment_reference` (= gateway transaction_code) — without this guard we
    # would create a duplicate row in `pending` state, polluting the organiser's
    # approval queue with payments that are already settled. Detect that case
    # and short-circuit, returning the already-confirmed record.
    if txn_ref:
        existing = db.query(EventContribution).filter(
            EventContribution.event_id == eid,
            EventContribution.transaction_ref == txn_ref,
        ).first()
        if existing:
            return standard_response(True, "Contribution already recorded", {
                "contribution_id": str(existing.id),
                "amount": float(existing.amount or 0),
                "status": (
                    "confirmed"
                    if existing.confirmation_status == ContributionStatusEnum.confirmed
                    else "pending"
                ),
                "deduped": True,
            })

    # Offline claims (no gateway proof) stay pending for organiser review.
    # Anything submitted via this endpoint without a matching gateway txn is
    # treated as an "I already paid another way" claim.
    contribution = EventContribution(
        id=uuid.uuid4(),
        event_id=eid,
        event_contributor_id=ec.id,
        contributor_name=contributor_name,
        contributor_contact=contact or None,
        amount=amount_val,
        payment_method=None,
        transaction_ref=txn_ref,
        recorded_by=current_user.id,
        payment_channel=pc,
        provider_id=provider_uuid,
        provider_name=provider_name,
        payer_account=payer_account,
        receipt_image_url=receipt_url,
        claim_submitted_at=now,
        confirmation_status=ContributionStatusEnum.pending,
        contributed_at=now,
    )
    db.add(contribution)
    db.commit()
    db.refresh(contribution)

    # In-app notification to organiser
    try:
        from utils.notify import notify_contribution_pending
        currency = _currency_code(db, event)
        notify_contribution_pending(
            db,
            recipient_id=event.organizer_id,
            sender_id=current_user.id,
            event_id=str(eid),
            event_title=event.name,
            contributor_name=contributor_name,
            amount=amount_val,
            currency=currency,
        )
        db.commit()
    except Exception as e:
        print(f"[self-contribute] in-app notify failed: {e}")

    # SMS/WA to organiser
    try:
        organizer = db.query(User).filter(User.id == event.organizer_id).first()
        if organizer and organizer.phone:
            from utils.notify_channels import notify_user_wa_sms
            currency = _currency_code(db, event)
            extra = f" via {pc.replace('_', ' ')}" if pc else ""
            org_msg = (
                f"Hello {organizer.first_name}, {contributor_name} just submitted a "
                f"contribution of {currency} {amount_val:,.0f}{extra} for {event.name}. "
                f"Open Nuru to confirm or reject this entry."
            )
            notify_user_wa_sms(organizer.phone, org_msg)
    except Exception as e:
        print(f"[self-contribute] organiser notify failed: {e}")

    return standard_response(True, "Contribution submitted for approval", {
        "contribution_id": str(contribution.id),
        "amount": amount_val,
        "status": "pending",
        "receipt_image_url": receipt_url,
    })


# ══════════════════════════════════════════════
# SHARE LINK — let organiser hand a contributor a public payment URL
# ══════════════════════════════════════════════

def _ensure_can_manage(db: Session, event_id, current_user) -> Event:
    """Resolve the event and verify the caller can manage contributors."""
    event, is_creator, _cm, perms = _get_event_access(db, event_id, current_user)
    if not event:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Event not found.")
    if not (is_creator or (perms and getattr(perms, "can_manage_contributions", False))):
        from fastapi import HTTPException
        raise HTTPException(status_code=403, detail="You don't have permission to manage contributors here.")
    return event


@router.post("/events/{event_id}/contributors/{ec_id}/share-link")
def generate_share_link(
    event_id: str,
    ec_id: str,
    body: dict = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Generate or fetch the public payment URL for one contributor.

    Body (optional): ``{ "regenerate": true }`` — rotate the token. When
    ``regenerate`` is false (default) we return the existing URL so the
    share link stays stable across "Share payment link" clicks.
    """
    from services.share_links import (
        issue_share_token, build_share_url, host_for_currency,
        can_send_sms_for_currency, get_active_token,
    )
    from fastapi import HTTPException

    event = _ensure_can_manage(db, event_id, current_user)
    try:
        ec_uuid = uuid.UUID(ec_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid contributor id.")
    ec = (
        db.query(EventContributor)
        .filter(EventContributor.id == ec_uuid, EventContributor.event_id == event.id)
        .first()
    )
    if not ec:
        raise HTTPException(status_code=404, detail="Contributor not found on this event.")

    regenerate = bool(body.get("regenerate"))
    plain = None if regenerate else get_active_token(ec)
    if not plain:
        plain = issue_share_token(db, ec)
        db.commit()
        db.refresh(ec)

    currency_code = _currency_code(db, event)
    url = build_share_url(currency_code, plain)
    return standard_response(True, "Payment link ready.", {
        "url": url,
        "host": host_for_currency(currency_code),
        "currency_code": currency_code,
        "expires_at": ec.share_token_expires_at.isoformat() if ec.share_token_expires_at else None,
        "sms_supported": can_send_sms_for_currency(currency_code),
    })


@router.post("/events/{event_id}/contributors/{ec_id}/send-share-sms")
@router.post("/events/{event_id}/contributors/{ec_id}/share-link/send-sms")
def send_share_link_sms(
    event_id: str,
    ec_id: str,
    body: dict = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Send the share link to the contributor via WhatsApp (primary) + SMS (fallback).

    Reuses the existing token if one is active so the contributor keeps
    receiving the same URL across re-sends.
    """
    from services.share_links import (
        issue_share_token, build_share_url, can_send_sms_for_currency,
        get_active_token,
    )
    from utils.sms import sms_guest_contribution_invite
    from utils.whatsapp import wa_guest_contribution_invite
    from fastapi import HTTPException

    event = _ensure_can_manage(db, event_id, current_user)
    try:
        ec_uuid = uuid.UUID(ec_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid contributor id.")
    ec = (
        db.query(EventContributor)
        .options(joinedload(EventContributor.contributor))
        .filter(EventContributor.id == ec_uuid, EventContributor.event_id == event.id)
        .first()
    )
    if not ec or not ec.contributor:
        raise HTTPException(status_code=404, detail="Contributor not found on this event.")

    currency_code = _currency_code(db, event)
    sms_ok = can_send_sms_for_currency(currency_code)

    plain = get_active_token(ec)
    if not plain:
        plain = issue_share_token(db, ec)
    url = build_share_url(currency_code, plain)
    from utils.event_owner import get_event_owner_display_name
    organiser_name = get_event_owner_display_name(event, db=db, fallback="Your host")

    from utils.offline_claims import contributor_notify_phones
    recipients = contributor_notify_phones(ec)
    if not recipients:
        raise HTTPException(status_code=400, detail="This contributor doesn't have a phone number for the selected notify option.")

    pledge_val = float(ec.pledge_amount or 0)
    contributor_name = ec.contributor.name or "there"
    event_title = event.name or "the event"

    try:
        from utils.wa_logging import set_wa_log_context
        set_wa_log_context(event_id=str(event.id), event_name=event.name,
                           source_module="contributors", purpose="contribution_invite",
                           recipient_type="contributor",
                           related_entity_type="event_contributor",
                           related_entity_id=str(ec.id))
    except Exception: pass

    sent_wa = False
    sent_sms = False
    for phone in recipients:
        try:
            wa_guest_contribution_invite(
                phone=phone,
                contributor_name=contributor_name,
                organiser_name=organiser_name,
                event_name=event_title,
                pledge_amount=pledge_val,
                share_token=plain,
                currency=currency_code,
            )
            sent_wa = True
        except Exception:
            pass
        if sms_ok:
            try:
                sms_guest_contribution_invite(
                    phone=phone,
                    contributor_name=contributor_name,
                    organiser_name=organiser_name,
                    event_title=event_title,
                    pledge_amount=pledge_val,
                    currency=currency_code,
                    payment_url=url,
                )
                sent_sms = True
            except Exception:
                pass

    ec.share_link_sms_last_sent_at = datetime.utcnow()
    db.commit()
    channels = []
    if sent_wa: channels.append("WhatsApp")
    if sent_sms: channels.append("SMS")
    msg = f"Payment link sent via {' and '.join(channels)}." if channels else "Payment link generated."
    return standard_response(True, msg, {
        "url": url,
        "sms_supported": sms_ok,
        "sent_whatsapp": sent_wa,
        "sent_sms": sent_sms,
    })



@router.post("/events/{event_id}/contributors/{ec_id}/revoke-share-link")
def revoke_share_link(
    event_id: str,
    ec_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Invalidate the existing public link without removing the contributor."""
    from fastapi import HTTPException
    event = _ensure_can_manage(db, event_id, current_user)
    try:
        ec_uuid = uuid.UUID(ec_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid contributor id.")
    ec = (
        db.query(EventContributor)
        .filter(EventContributor.id == ec_uuid, EventContributor.event_id == event.id)
        .first()
    )
    if not ec:
        raise HTTPException(status_code=404, detail="Contributor not found on this event.")
    ec.share_token_revoked_at = datetime.utcnow()
    db.commit()
    return standard_response(True, "Payment link disabled.")


# ══════════════════════════════════════════════
# SECONDARY PHONE — comms-only routing for an event contributor
# ══════════════════════════════════════════════

@router.post("/events/{event_id}/contributors/{ec_id}/secondary-phone")
def set_secondary_phone(
    event_id: str,
    ec_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Set/clear an event contributor's secondary phone + notify_target.

    Body: { secondary_phone?: str|null, notify_target: 'primary'|'secondary'|'both' }

    The secondary phone is purely a comms address — never used to map a
    Nuru user account or affect existing contributor functionality.
    """
    try:
        eid = uuid.UUID(event_id)
        ecid = uuid.UUID(ec_id)
    except ValueError:
        return standard_response(False, "Invalid ID")

    event, is_creator, cm, perms = _get_event_access(db, eid, current_user)
    if not event or (not is_creator and not (cm and perms and perms.can_manage_contributions)):
        return standard_response(False, "Event not found or access denied")

    ec = db.query(EventContributor).filter(
        EventContributor.id == ecid, EventContributor.event_id == eid,
    ).first()
    if not ec:
        return standard_response(False, "Event contributor not found")

    if "secondary_phone" in body:
        raw = (body.get("secondary_phone") or "").strip()
        if raw:
            try:
                raw = validate_phone_number(raw)
            except ValueError as e:
                return standard_response(False, str(e))
            ec.secondary_phone = raw
        else:
            ec.secondary_phone = None

    nt = (body.get("notify_target") or "").strip().lower()
    if nt:
        if nt not in ("primary", "secondary", "both"):
            return standard_response(False, "notify_target must be primary, secondary or both")
        ec.notify_target = nt

    # Sanity: 'secondary' / 'both' require a secondary phone to be set
    if ec.notify_target in ("secondary", "both") and not ec.secondary_phone:
        return standard_response(False, "Secondary phone is required for the chosen notify target")

    ec.updated_at = datetime.now(EAT)
    db.commit()
    return standard_response(True, "Notification preference updated", {
        "secondary_phone": ec.secondary_phone,
        "notify_target": ec.notify_target,
    })
