"""Helpers for the reminder-automation feature.

Pure functions:
* validate_body — enforces WhatsApp template rules (no leading/trailing
  variable, required placeholders preserved).
* render_body — substitutes placeholders into the editable body.
* render_full_message — wraps the rendered body with the template's
  protected prefix/suffix to produce the actual outbound text.
* compute_next_run_at — schedule math in the organiser's timezone.
* resolve_recipients — returns the list of (recipient_type, recipient_id,
  name, phone) tuples for a given automation. Honours the
  "incomplete contributors only" rule for pledge_remind.
"""
from __future__ import annotations

import re
from datetime import date, datetime, time, timedelta, timezone as dt_tz
from typing import Iterable

import pytz
from sqlalchemy import and_, func as sa_func
from sqlalchemy.orm import Session

UTC = dt_tz.utc
PLACEHOLDER_RE = re.compile(r"\{\{\s*([a-zA-Z0-9_]+)\s*\}\}")
LEADING_VAR_RE = re.compile(r"^\s*\{\{")
TRAILING_VAR_RE = re.compile(r"\}\}\s*$")


# ── validation ─────────────────────────────────────────────────────────

class TemplateValidationError(ValueError):
    pass


def validate_body(body: str, required_placeholders: list[str] | None) -> None:
    """Raise TemplateValidationError if WhatsApp rules are violated."""
    if not body or not body.strip():
        raise TemplateValidationError("Message body is required.")

    # The organiser-editable body itself must not start/end with {{var}}.
    # The template's protected_prefix/suffix already guarantee the final
    # outbound message is wrapped in fixed text, but we enforce this on
    # the raw body too so previews look correct.
    if LEADING_VAR_RE.search(body):
        raise TemplateValidationError(
            "Message cannot start with a placeholder. Add some text before it."
        )
    if TRAILING_VAR_RE.search(body):
        raise TemplateValidationError(
            "Message cannot end with a placeholder. Add some text after it."
        )

    if required_placeholders:
        present = set(PLACEHOLDER_RE.findall(body))
        missing = [p for p in required_placeholders if p not in present]
        if missing:
            raise TemplateValidationError(
                "Required placeholders missing: " + ", ".join(
                    "{{" + m + "}}" for m in missing)
            )


# ── rendering ──────────────────────────────────────────────────────────

def render_body(body: str, params: dict[str, str]) -> str:
    """Substitute {{name}} placeholders. Unknown ones are left blank."""
    def _sub(m: re.Match) -> str:
        key = m.group(1)
        return str(params.get(key, "")).strip()
    return PLACEHOLDER_RE.sub(_sub, body or "").strip()


def _with_positional_aliases(template, params: dict[str, str]) -> dict[str, str]:
    """Add WhatsApp positional aliases for stored template bodies.

    Meta templates use {{1}}, {{2}}, … while the application resolves named
    values at dispatch time. Keeping both lets previews/SMS fallbacks render
    correctly without requiring organisers to type system-filled placeholders.
    """
    merged = dict(params or {})
    atype = getattr(template, "automation_type", "") if template is not None else ""
    if atype == "fundraise_attend":
        aliases = {"1": "recipient_name", "2": "body"}
    elif atype == "pledge_remind":
        aliases = {
            "1": "recipient_name", "2": "event_name", "3": "event_datetime",
            "4": "pledge_amount", "5": "balance", "6": "pay_link",
        }
    elif atype == "guest_remind":
        aliases = {
            "1": "recipient_name", "2": "event_name",
            "3": "event_datetime", "4": "event_venue",
        }
    else:
        aliases = {}
    for position, name in aliases.items():
        if position not in merged and name in merged:
            merged[position] = merged.get(name, "")
    return merged


def render_full_message(template, body_override: str | None,
                        params: dict[str, str]) -> str:
    """Final outbound text: protected_prefix + rendered body + protected_suffix."""
    params = _with_positional_aliases(template, params)
    body = body_override if body_override is not None else template.body_default
    rendered = render_body(body, params)
    parts = []
    if template.protected_prefix:
        parts.append(render_body(template.protected_prefix, params))
    if rendered:
        parts.append(rendered)
    if template.protected_suffix:
        parts.append(render_body(template.protected_suffix, params))
    return "\n".join(p for p in parts if p)


# ── presentation helpers ───────────────────────────────────────────────

_SW_MONTHS = [
    "Januari", "Februari", "Machi", "Aprili", "Mei", "Juni",
    "Julai", "Agosti", "Septemba", "Oktoba", "Novemba", "Desemba",
]

# Monday=0 ... Sunday=6
_SW_WEEKDAYS = [
    "Jumatatu", "Jumanne", "Jumatano", "Alhamisi",
    "Ijumaa", "Jumamosi", "Jumapili",
]


def format_event_datetime(dt: date | datetime | None, tz_name: str | None,
                          lang: str | None) -> str:
    """Format an event datetime in the organiser timezone, including time.

    English: ``Thursday, 16 May 2026 at 16:30``
    Swahili: ``Alhamisi, 16 Mei 2026 saa 16:30``
    """
    if dt is None:
        return ""
    aware = _aware(dt)
    try:
        local = aware.astimezone(_safe_tz(tz_name))
    except Exception:
        local = aware
    day = local.day
    year = local.year
    time_str = local.strftime("%H:%M")
    if (lang or "en").lower() == "sw":
        weekday = _SW_WEEKDAYS[local.weekday()]
        month = _SW_MONTHS[local.month - 1]
        return f"{weekday}, {day} {month} {year} saa {time_str}"
    weekday = local.strftime("%A")
    month = local.strftime("%B")
    return f"{weekday}, {day} {month} {year} at {time_str}"


def format_money(amount: float | int | None, currency_code: str | None) -> str:
    """``TZS 50,000`` style — used inside reminder messages."""
    try:
        n = float(amount or 0)
    except Exception:
        n = 0.0
    if n == int(n):
        body = f"{int(n):,}"
    else:
        body = f"{n:,.2f}"
    code = (currency_code or "TZS").upper()
    return f"{code} {body}"


# ── schedule math ──────────────────────────────────────────────────────

def _safe_tz(name: str | None):
    try:
        return pytz.timezone(name or "Africa/Nairobi")
    except Exception:
        return pytz.timezone("Africa/Nairobi")


def _aware(dt: date | datetime | None) -> datetime | None:
    if dt is None:
        return None
    if isinstance(dt, date) and not isinstance(dt, datetime):
        dt = datetime.combine(dt, time.min, tzinfo=UTC)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt


def compute_next_run_at(
    automation,
    event,
    last_run_at: datetime | None = None,
    now: datetime | None = None,
) -> datetime | None:
    """Return the next datetime (UTC, tz-aware) at which the automation
    should fire. ``None`` means: don't schedule again.
    """
    now = (now or datetime.now(UTC)).astimezone(UTC)
    tz = _safe_tz(automation.timezone)

    kind = automation.schedule_kind
    if kind == "now":
        # Send-now automations are dispatched inline by the API; nothing
        # for the scheduler to pick up.
        return None

    if kind == "datetime":
        sched = _aware(automation.schedule_at)
        if not sched:
            return None
        if sched > now:
            return sched
        # If the organiser creates/enables a one-off reminder after its
        # scheduled time, dispatch it on the next scheduler tick instead of
        # leaving it enabled with no run forever. Once it has run, do not repeat.
        return now if last_run_at is None else None

    # The remaining kinds need an event start anchor.
    event_start = _aware(getattr(event, "start_date", None))
    if not event_start:
        return None

    if kind == "days_before":
        days = max(0, int(automation.days_before or 0))
        target = event_start - timedelta(days=days)
        if target > now:
            return target
        return now if last_run_at is None else None

    if kind == "hours_before":
        hours = max(0, int(automation.hours_before or 0))
        target = event_start - timedelta(hours=hours)
        if target > now:
            return target
        return now if last_run_at is None else None

    if kind == "repeat":
        interval = max(1, int(automation.repeat_interval_hours or 24))
        anchor = _aware(last_run_at) or now
        target = anchor + timedelta(hours=interval)
        if target <= event_start:
            return target
        return None

    return None


# ── recipient resolution ───────────────────────────────────────────────

def resolve_recipients(db: Session, automation, event) -> list[dict]:
    """Return [{recipient_type, recipient_id, name, phone}] for an automation."""
    from models import (
        EventContributor, UserContributor, EventContribution,
        EventAttendee, User,
    )

    rtype = automation.automation_type
    rows: list[dict] = []

    if rtype in ("fundraise_attend", "pledge_remind"):
        q = (
            db.query(EventContributor, UserContributor)
            .join(UserContributor,
                  UserContributor.id == EventContributor.contributor_id)
            .filter(EventContributor.event_id == event.id)
        )

        if rtype == "pledge_remind":
            # Only contributors whose pledged > paid.
            paid_subq = (
                db.query(
                    EventContribution.event_contributor_id.label("ecid"),
                    sa_func.coalesce(sa_func.sum(EventContribution.amount), 0)
                        .label("paid"),
                )
                .group_by(EventContribution.event_contributor_id)
                .subquery()
            )
            q = q.outerjoin(paid_subq,
                            paid_subq.c.ecid == EventContributor.id)
            q = q.filter(
                and_(
                    EventContributor.pledge_amount.isnot(None),
                    EventContributor.pledge_amount > 0,
                    sa_func.coalesce(EventContributor.pledge_amount, 0)
                        > sa_func.coalesce(paid_subq.c.paid, 0),
                )
            )

        for ec, uc in q.all():
            phone = (uc.phone or "").strip() or None
            if not phone:
                continue
            # Per-event override wins: same global contributor can appear under
            # different display names on different events of the same organiser.
            event_name = (getattr(ec, "display_name", None) or "").strip() or uc.name
            rows.append({
                "recipient_type": "contributor",
                "recipient_id": ec.id,
                "name": event_name,
                "phone": phone,
            })

    elif rtype == "guest_remind":
        # Resolve phones across all three guest_type variants on the
        # event_attendees table:
        #   - guest_type=user        → join User.phone via attendee_id
        #   - guest_type=contributor → join UserContributor.phone via contributor_id
        #   - guest_type=guest       → use guest_phone/guest_name directly
        attendees = (
            db.query(EventAttendee)
            .filter(EventAttendee.event_id == event.id)
            .all()
        )

        # Batch fetch users + contributors to avoid N+1.
        user_ids = [a.attendee_id for a in attendees if a.attendee_id]
        contrib_ids = [a.contributor_id for a in attendees if a.contributor_id]
        users_by_id = {}
        if user_ids:
            for u in db.query(User).filter(User.id.in_(user_ids)).all():
                users_by_id[u.id] = u
        contribs_by_id = {}
        if contrib_ids:
            for c in (
                db.query(UserContributor)
                .filter(UserContributor.id.in_(contrib_ids))
                .all()
            ):
                contribs_by_id[c.id] = c

        for a in attendees:
            gtype = getattr(a, "guest_type", None)
            gtype_val = gtype.value if hasattr(gtype, "value") else (gtype or "guest")

            phone = None
            name = a.guest_name or None

            if gtype_val == "user" and a.attendee_id:
                u = users_by_id.get(a.attendee_id)
                if u:
                    phone = (u.phone or "").strip() or None
                    if not name:
                        full = " ".join(filter(None, [
                            getattr(u, "first_name", None),
                            getattr(u, "last_name", None),
                        ])).strip()
                        name = full or None
            elif gtype_val == "contributor" and a.contributor_id:
                c = contribs_by_id.get(a.contributor_id)
                if c:
                    phone = (c.phone or "").strip() or None
                    if not name:
                        name = c.name

            # Always allow guest_phone override / fallback for plain guests.
            if not phone:
                phone = (getattr(a, "guest_phone", None) or "").strip() or None

            if not phone:
                continue
            rows.append({
                "recipient_type": "guest",
                "recipient_id": a.id,
                "name": name or "Guest",
                "phone": phone,
            })

    return rows
