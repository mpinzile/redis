"""
Task: Reminder automation dispatcher
====================================
* run_automation(automation_id, trigger)
    - creates a run row + per-recipient rows (UNIQUE prevents dupes)
    - fans out one send_one task per recipient

* send_one(recipient_row_id)
    - tries WhatsApp first via existing utils.whatsapp._send_whatsapp_sync
    - on failure (provider rejected or 24h window expired etc.) falls back
      to SMS via utils.sms._send_sync
    - updates the recipient row with status/channel/error

* scan_due_automations()
    - Beat-driven every 5 minutes
    - Picks up enabled automations whose next_run_at <= now and dispatches
    - Recomputes next_run_at after each fire (handles 'repeat')
"""
from __future__ import annotations

from datetime import datetime, timezone as dt_tz
from sqlalchemy import and_, func as sa_func

from core.celery_app import celery_app
from core.database import SessionLocal

UTC = dt_tz.utc


# ──────────────────────────────────────────────────────────────────────
# Per-recipient send
# ──────────────────────────────────────────────────────────────────────

@celery_app.task(
    name="tasks.reminder_dispatch.send_one",
    bind=True,
    max_retries=3,
    default_retry_delay=60,
    rate_limit="200/m",
)
def send_one(self, recipient_id: str):
    from models import (
        EventReminderRecipient, EventReminderRun,
        EventReminderAutomation, Event, EventContributor, EventContribution,
        Currency,
    )
    from sqlalchemy import func as sa_func
    from utils.whatsapp import _send_whatsapp_sync
    from utils.sms import _send_sync as _sms_send_sync
    from utils.reminder_helpers import format_event_datetime, format_money
    from services.share_links import issue_share_token, build_share_url

    db = SessionLocal()
    try:
        rec = (
            db.query(EventReminderRecipient)
            .filter(EventReminderRecipient.id == recipient_id)
            .first()
        )
        if rec is None or rec.status not in ("pending",):
            return {"ok": False, "reason": "missing_or_done"}

        run = (
            db.query(EventReminderRun)
            .filter(EventReminderRun.id == rec.run_id)
            .first()
        )
        message = (rec.message or run.body_snapshot or "").strip()
        phone = (rec.phone or "").strip()

        if not phone:
            rec.status = "skipped"
            rec.channel = "skipped"
            rec.error = "missing_phone"
            rec.attempts = (rec.attempts or 0) + 1
            run.skipped_count = (run.skipped_count or 0) + 1
            _maybe_finish(run, db)
            db.commit()
            return {"ok": False, "skipped": True}

        rec.attempts = (rec.attempts or 0) + 1

        # Resolve automation + event context for template-based sending.
        automation = db.query(EventReminderAutomation).filter(
            EventReminderAutomation.id == run.automation_id).first()
        wa_template = (automation.template.whatsapp_template_name
                       if automation and automation.template else None)
        lang = (automation.language if automation else "en") or "en"

        # Attribute every WA log row this task produces to the event owner so
        # the rows appear on the user-scoped /whatsapp-logs page (mirrors what
        # invitations / cards / contributor imports do).
        try:
            event_for_ctx = db.query(Event).filter(Event.id == run.event_id).first()
            owner_id_ctx = None
            event_name_ctx = None
            if event_for_ctx is not None:
                try:
                    from utils.event_owner import event_owner_id
                    owner_id_ctx = event_owner_id(event_for_ctx) or str(
                        getattr(event_for_ctx, "organizer_id", "") or "")
                except Exception:
                    owner_id_ctx = str(getattr(event_for_ctx, "organizer_id", "") or "")
                event_name_ctx = getattr(event_for_ctx, "name", None)
            from utils.wa_logging import set_wa_log_context
            set_wa_log_context(
                user_id=(str(owner_id_ctx) if owner_id_ctx else None),
                event_id=str(run.event_id) if run.event_id else None,
                event_name=event_name_ctx,
                purpose="event_reminder",
                source_module="reminder_dispatch",
                recipient_type=("contributor"
                                if getattr(automation, "automation_type", "") == "pledge_remind"
                                else "guest"),
            )

        except Exception as _e:
            print(f"[reminder] wa_log_context skipped: {_e}")


        wa_ok = False
        wa_action = None
        wa_params: dict = {}

        if wa_template and automation:
            # Build structured params per automation type.
            event = db.query(Event).filter(
                Event.id == run.event_id).first()
            tz_name = automation.timezone or "Africa/Nairobi"
            event_dt_str = format_event_datetime(
                getattr(event, "start_date", None), tz_name, lang) if event else ""
            event_name = (event.name if event and event.name
                          else "your event")

            atype = automation.automation_type
            if atype == "fundraise_attend":
                wa_action = "fundraise_attend"
                wa_params = {
                    "lang": lang,
                    "recipient_name": rec.name or "Friend",
                    "body": (automation.body_override
                             or (automation.template.body_default
                                 if automation.template else "")),
                }
            elif atype == "guest_remind":
                venue_text = ""
                vc = getattr(event, "venue_coordinate", None) if event else None
                if vc:
                    venue_text = (
                        getattr(vc, "venue_name", None)
                        or getattr(vc, "formatted_address", None) or "")
                if event and not venue_text:
                    venue_text = getattr(event, "location", "") or ""
                wa_action = "guest_remind"
                wa_params = {
                    "lang": lang,
                    "recipient_name": rec.name or "Friend",
                    "event_name": event_name,
                    "event_datetime": event_dt_str or "TBA",
                    "event_venue": venue_text or "TBA",
                }
            elif atype == "pledge_remind":
                # Resolve currency, pledge / balance, fresh share token.
                currency_code = "TZS"
                if event and getattr(event, "currency_id", None):
                    cur = db.query(Currency).filter(
                        Currency.id == event.currency_id).first()
                    if cur and cur.code:
                        currency_code = cur.code.strip()

                ec = (
                    db.query(EventContributor)
                    .filter(EventContributor.id == rec.recipient_id)
                    .first()
                )
                pledge = float(ec.pledge_amount or 0) if ec else 0.0
                paid = 0.0
                if ec:
                    paid = float(
                        db.query(sa_func.coalesce(
                            sa_func.sum(EventContribution.amount), 0))
                        .filter(EventContribution.event_contributor_id == ec.id)
                        .scalar() or 0
                    )
                balance = max(0.0, pledge - paid)
                pay_token = ""
                if ec:
                    try:
                        pay_token = issue_share_token(db, ec)
                        # Commit token row so URL is valid even if send fails.
                        db.commit()
                    except Exception as e:
                        print(f"[reminder] token issue failed: {e}")
                        db.rollback()

                wa_action = "pledge_remind"
                wa_params = {
                    "lang": lang,
                    "recipient_name": rec.name or "Friend",
                    "event_name": event_name,
                    "event_datetime": event_dt_str or "TBA",
                    "pledge_amount": format_money(pledge, currency_code),
                    "balance": format_money(balance, currency_code),
                    "pay_token": pay_token or "—",
                }

            if wa_action:
                try:
                    wa_ok = bool(_send_whatsapp_sync(
                        wa_action, phone, wa_params))
                except Exception as e:
                    rec.error = f"wa_tpl:{e}"
                    wa_ok = False

        # Fallback: plain text WhatsApp (24h window only).
        if not wa_ok and message:
            try:
                wa_ok = bool(_send_whatsapp_sync(
                    "text", phone, {"message": message}))
            except Exception as e:
                rec.error = f"wa_text:{e}"
                wa_ok = False

        if wa_ok:
            rec.channel = "whatsapp"
            rec.status = "sent"
            rec.sent_at = datetime.now(UTC)
            rec.error = None
            run.sent_count = (run.sent_count or 0) + 1
            _maybe_finish(run, db)
            db.commit()
            return {"ok": True, "channel": "whatsapp"}

        # SMS fallback (uses rendered text).
        if not message:
            rec.status = "skipped"
            rec.channel = "skipped"
            rec.error = "missing_message"
            run.skipped_count = (run.skipped_count or 0) + 1
            _maybe_finish(run, db)
            db.commit()
            return {"ok": False, "skipped": True}

        try:
            _sms_send_sync(phone, message)
            rec.channel = "sms"
            rec.status = "sent"
            rec.sent_at = datetime.now(UTC)
            rec.error = None
            run.sent_count = (run.sent_count or 0) + 1
            _maybe_finish(run, db)
            db.commit()
            return {"ok": True, "channel": "sms"}
        except Exception as e:
            rec.status = "failed"
            rec.error = f"sms:{e}"
            run.failed_count = (run.failed_count or 0) + 1
            _maybe_finish(run, db)
            db.commit()
            try:
                raise self.retry(exc=e)
            except Exception:
                return {"ok": False, "error": str(e)}
    except Exception as exc:
        try:
            db.rollback()
        except Exception:
            pass
        raise self.retry(exc=exc)
    finally:
        db.close()


def _maybe_finish(run, db):
    """Mark the run completed once every recipient has a terminal status."""
    from models import EventReminderRecipient
    pending = (
        db.query(EventReminderRecipient)
        .filter(
            EventReminderRecipient.run_id == run.id,
            EventReminderRecipient.status == "pending",
        )
        .count()
    )
    if pending <= 1:  # we're processing the last one
        run.status = "completed"
        run.finished_at = datetime.now(UTC)


def _refresh_run_totals(db, run):
    """Recompute run counters/status from recipient rows.

    This repairs stale runs left pending/running when a worker is restarted,
    a child task is retried, or an older deployment queued a task that was not
    registered by the currently-running worker.
    """
    from models import EventReminderRecipient

    counts = dict(
        db.query(EventReminderRecipient.status, sa_func.count(EventReminderRecipient.id))
        .filter(EventReminderRecipient.run_id == run.id)
        .group_by(EventReminderRecipient.status)
        .all()
    )
    run.total_recipients = sum(int(v or 0) for v in counts.values())
    run.sent_count = int(counts.get("sent", 0) or 0)
    run.failed_count = int(counts.get("failed", 0) or 0)
    run.skipped_count = int(counts.get("skipped", 0) or 0)
    pending = int(counts.get("pending", 0) or 0)
    if run.total_recipients == 0 and run.status in ("pending", "running"):
        run.status = "completed"
        run.finished_at = run.finished_at or datetime.now(UTC)
    elif pending == 0 and run.total_recipients > 0:
        run.status = "completed"
        run.finished_at = run.finished_at or datetime.now(UTC)
    elif pending > 0 and run.status == "pending":
        run.status = "running"


# ──────────────────────────────────────────────────────────────────────
# Whole-automation run
# ──────────────────────────────────────────────────────────────────────

@celery_app.task(
    name="tasks.reminder_dispatch.run_automation",
    bind=True,
    max_retries=2,
    default_retry_delay=120,
)
def run_automation(self, automation_id: str, trigger: str = "scheduled",
                   run_id: str | None = None, send_inline: bool = False):
    """Create a run + recipients and fan out send_one tasks.

    If ``run_id`` is provided we reuse that run (used by ``send-now`` so the
    API can return its id immediately). Otherwise we create a new pending run.
    """
    from models import (
        EventReminderAutomation, EventReminderRun, EventReminderRecipient,
        Event, EventContributor, EventContribution, Currency,
    )
    from sqlalchemy import func as sa_func
    from utils.reminder_helpers import (
        resolve_recipients, render_full_message, compute_next_run_at,
        format_event_datetime, format_money,
    )
    from services.share_links import (
        issue_share_token, build_share_url,
    )

    db = SessionLocal()
    try:
        started_at = datetime.now(UTC)
        automation = (
            db.query(EventReminderAutomation)
            .filter(EventReminderAutomation.id == automation_id)
            .first()
        )
        if not automation:
            return {"ok": False, "reason": "not_found"}

        event = db.query(Event).filter(Event.id == automation.event_id).first()
        if not event:
            return {"ok": False, "reason": "event_missing"}

        lang = (automation.language or "en").lower()
        tz_name = automation.timezone or "Africa/Nairobi"

        # Resolve currency code once for the event.
        currency_code = "TZS"
        if getattr(event, "currency_id", None):
            cur = db.query(Currency).filter(
                Currency.id == event.currency_id).first()
            if cur and cur.code:
                currency_code = cur.code.strip()

        # Resolve venue text — prefer the structured venue_coordinate
        # then fall back to the free-form event.location.
        venue_text = ""
        vc = getattr(event, "venue_coordinate", None)
        if vc:
            venue_text = (
                getattr(vc, "venue_name", None)
                or getattr(vc, "formatted_address", None)
                or ""
            )
        if not venue_text:
            venue_text = getattr(event, "location", "") or ""

        event_dt_str = format_event_datetime(
            getattr(event, "start_date", None), tz_name, lang)

        # Snapshot params for the run-level body_snapshot (audit/preview).
        snapshot_params = {
            "event_name": event.name or "your event",
            "event_date": event_dt_str,
            "event_datetime": event_dt_str,
            "event_venue": venue_text or "the venue",
            "pledge_amount": "",
            "balance": "",
            "pay_link": "",
            "event_link": "",
            "body": automation.body_override or "",
        }
        body_snapshot = render_full_message(
            automation.template,
            automation.body_override,
            snapshot_params,
        )

        # Reuse or create the run row.
        if run_id:
            run = db.query(EventReminderRun).filter(
                EventReminderRun.id == run_id).first()
        else:
            run = EventReminderRun(
                automation_id=automation.id,
                event_id=event.id,
                trigger=trigger,
                status="running",
                body_snapshot=body_snapshot,
            )
            db.add(run)
            db.flush()

        if not run:
            return {"ok": False, "reason": "run_missing"}

        run.body_snapshot = body_snapshot
        run.status = "running"
        run.error = None
        run.started_at = run.started_at or started_at

        # Resolve recipients and insert idempotently.
        recipients = resolve_recipients(db, automation, event)
        inserted = 0
        existing = 0
        for r in recipients:
            already_exists = db.query(EventReminderRecipient.id).filter(
                EventReminderRecipient.run_id == run.id,
                EventReminderRecipient.recipient_type == r["recipient_type"],
                EventReminderRecipient.recipient_id == r["recipient_id"],
            ).first()
            if already_exists:
                existing += 1
                continue

            # Per-recipient parameters.
            params = dict(snapshot_params)
            params["recipient_name"] = r["name"] or ""

            # Pledge / balance / dynamic pay link for pledge_remind.
            if automation.automation_type == "pledge_remind":
                ec = (
                    db.query(EventContributor)
                    .filter(EventContributor.id == r["recipient_id"])
                    .first()
                )
                if ec is not None:
                    pledge = float(ec.pledge_amount or 0)
                    paid = float(
                        db.query(sa_func.coalesce(
                            sa_func.sum(EventContribution.amount), 0))
                        .filter(EventContribution.event_contributor_id == ec.id)
                        .scalar() or 0
                    )
                    balance = max(0.0, pledge - paid)
                    # Issue a fresh share token + dynamic URL.
                    plain = issue_share_token(db, ec)
                    pay_url = build_share_url(currency_code, plain)
                    params["pledge_amount"] = format_money(pledge, currency_code)
                    params["balance"] = format_money(balance, currency_code)
                    params["pay_link"] = pay_url
                    params["event_link"] = pay_url

            rendered = render_full_message(
                automation.template,
                automation.body_override,
                params,
            )

            rec_row = EventReminderRecipient(
                run_id=run.id,
                recipient_type=r["recipient_type"],
                recipient_id=r["recipient_id"],
                name=r["name"],
                phone=r["phone"],
                status="pending",
                message=rendered,
            )
            db.add(rec_row)
            db.flush()
            inserted += 1

        run.total_recipients = inserted + existing
        if run.total_recipients == 0:
            run.status = "completed"
            run.finished_at = datetime.now(UTC)

        # Update automation pointers.
        automation.last_run_at = datetime.now(UTC)
        automation.next_run_at = compute_next_run_at(
            automation, event, last_run_at=automation.last_run_at)

        db.commit()

        # Fan out per-recipient tasks (commit first so workers see them).
        if inserted > 0:
            rec_ids = [
                str(x.id) for x in db.query(EventReminderRecipient.id)
                .filter(EventReminderRecipient.run_id == run.id,
                        EventReminderRecipient.status == "pending")
                .all()
            ]
            for rid in rec_ids:
                try:
                    if send_inline:
                        send_one.run(rid)
                    else:
                        send_one.delay(rid)
                except Exception as e:
                    print(f"[reminder] failed to enqueue {rid}: {e}")

        return {"ok": True, "run_id": str(run.id), "recipients": run.total_recipients}
    except Exception as exc:
        try:
            db.rollback()
            if run_id:
                failed_run = db.query(EventReminderRun).filter(
                    EventReminderRun.id == run_id).first()
                if failed_run:
                    failed_run.status = "failed"
                    failed_run.error = str(exc)[:1000]
                    failed_run.finished_at = datetime.now(UTC)
                    db.commit()
        except Exception:
            pass
        raise self.retry(exc=exc)
    finally:
        db.close()


# ──────────────────────────────────────────────────────────────────────
# Beat: scan for due automations
# ──────────────────────────────────────────────────────────────────────

@celery_app.task(name="tasks.reminder_dispatch.scan_due_automations")
def scan_due_automations():
    """Pick up enabled automations whose ``next_run_at <= now()``."""
    from models import EventReminderAutomation, Event
    from models.enums import EventStatusEnum

    db = SessionLocal()
    try:
        now = datetime.now(UTC)
        # Skip cancelled / completed events — only active ones get reminders.
        active_states = [
            EventStatusEnum.draft,
            EventStatusEnum.confirmed,
            EventStatusEnum.published,
        ]
        rows = (
            db.query(EventReminderAutomation)
            .join(Event, Event.id == EventReminderAutomation.event_id)
            .filter(
                and_(
                    EventReminderAutomation.enabled.is_(True),
                    EventReminderAutomation.next_run_at.isnot(None),
                    EventReminderAutomation.next_run_at <= now,
                    Event.status.in_(active_states),
                )
            )
            .limit(100)
            .all()
        )

        dispatched = 0
        for a in rows:
            # Move next_run_at forward immediately so the same run isn't
            # dispatched twice if the worker is slow.
            a.next_run_at = None
            db.commit()
            try:
                run_automation.run(str(a.id), "scheduled", None, True)
                dispatched += 1
            except Exception as e:
                print(f"[reminder] failed to dispatch {a.id}: {e}")

        return {"dispatched": dispatched}
    finally:
        db.close()


# ──────────────────────────────────────────────────────────────────────
# Resend failed recipients of a previous run
# ──────────────────────────────────────────────────────────────────────

@celery_app.task(name="tasks.reminder_dispatch.resend_failed")
def resend_failed(run_id: str):
    from models import EventReminderRecipient, EventReminderRun
    db = SessionLocal()
    try:
        run = db.query(EventReminderRun).filter(
            EventReminderRun.id == run_id).first()
        if not run:
            return {"ok": False, "reason": "missing"}

        # Reset failed rows to pending and re-enqueue.
        failed = db.query(EventReminderRecipient).filter(
            EventReminderRecipient.run_id == run.id,
            EventReminderRecipient.status == "failed",
        ).all()
        for r in failed:
            r.status = "pending"
            r.error = None
        run.failed_count = max(0, (run.failed_count or 0) - len(failed))
        run.status = "running"
        run.finished_at = None
        db.commit()

        for r in failed:
            try:
                send_one.delay(str(r.id))
            except Exception as e:
                print(f"[reminder] resend enqueue failed {r.id}: {e}")
        return {"ok": True, "resent": len(failed)}
    finally:
        db.close()
