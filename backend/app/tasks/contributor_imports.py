"""Celery task that processes a queued contributor import job.

Mirrors the inline logic that used to live in
``POST /events/{event_id}/contributors/bulk`` so behaviour stays
identical, with the difference that work happens in the background and
the HTTP request returns immediately with a ``job_id``.
"""
from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Dict, List

import pytz
from sqlalchemy import func as sa_func


from core.celery_app import celery_app
from core.database import SessionLocal
from models import (
    ContributorImportJob,
    Event,
    EventContributor,
    User,
    UserContributor,
)
from utils.helpers import format_phone_display
from utils.validation_functions import validate_phone_number


EAT = pytz.timezone("Africa/Dar_es_Salaam")


def _currency_code(db, event: Event) -> str:
    try:
        from models import Currency
        if event.currency_id:
            cur = db.query(Currency).filter(Currency.id == event.currency_id).first()
            if cur and cur.code:
                return cur.code
    except Exception:
        pass
    return "TZS"


def _phone_key(phone: str | None) -> str:
    digits = "".join(ch for ch in str(phone or "") if ch.isdigit())
    return digits[-9:] if len(digits) >= 9 else digits


def _phone_key_expr(column):
    return sa_func.right(sa_func.regexp_replace(column, r"[^0-9]", "", "g"), 9)


def _find_event_contributor_by_phone(db, event_id, phone: str):
    key = _phone_key(phone)
    if not key:
        return None
    return (
        db.query(EventContributor)
        .join(UserContributor, EventContributor.contributor_id == UserContributor.id)
        .filter(
            EventContributor.event_id == event_id,
            UserContributor.phone.isnot(None),
            _phone_key_expr(UserContributor.phone) == key,
        )
        .order_by(EventContributor.created_at.asc(), EventContributor.id.asc())
        .first()
    )


def _find_event_contributor_by_name_without_phone(db, event_id, name: str):
    return (
        db.query(EventContributor)
        .join(UserContributor, EventContributor.contributor_id == UserContributor.id)
        .filter(
            EventContributor.event_id == event_id,
            sa_func.lower(UserContributor.name) == name.lower(),
            (UserContributor.phone.is_(None) | (sa_func.trim(UserContributor.phone) == "")),
        )
        .order_by(EventContributor.created_at.asc(), EventContributor.id.asc())
        .first()
    )


def _find_address_book_contributor_by_phone(db, owner_id, phone: str):
    key = _phone_key(phone)
    if not key:
        return None
    contributor = (
        db.query(UserContributor)
        .filter(UserContributor.user_id == owner_id, UserContributor.phone == phone)
        .first()
    )
    if contributor:
        return contributor
    return (
        db.query(UserContributor)
        .filter(
            UserContributor.user_id == owner_id,
            UserContributor.phone.isnot(None),
            _phone_key_expr(UserContributor.phone) == key,
        )
        .order_by(UserContributor.created_at.asc(), UserContributor.id.asc())
        .first()
    )


@celery_app.task(name="contributors.process_import_job", bind=True, max_retries=2)
def process_contributor_import_job(self, job_id: str) -> Dict[str, Any]:
    db = SessionLocal()
    try:
        job: ContributorImportJob | None = (
            db.query(ContributorImportJob)
            .filter(ContributorImportJob.id == uuid.UUID(str(job_id)))
            .first()
        )
        if not job:
            return {"ok": False, "error": "job-not-found"}
        if job.status not in ("queued", "failed"):
            # Already processing or finished - idempotent no-op.
            return {"ok": True, "status": job.status}

        event = db.query(Event).filter(Event.id == job.event_id).first()
        if not event:
            job.status = "failed"
            job.error_message = "Event not found"
            job.finished_at = datetime.utcnow()
            db.commit()
            return {"ok": False, "error": "event-not-found"}

        rows: List[Dict[str, Any]] = list(job.payload.get("contributors") or [])
        send_sms = bool(job.send_sms)
        mode = (job.mode or "targets").strip()

        job.status = "processing"
        job.started_at = datetime.utcnow()
        job.total_rows = len(rows)
        job.processed_rows = 0
        job.successful_rows = 0
        job.failed_rows = 0
        job.errors = []
        db.commit()

        now = datetime.now(EAT)
        currency = _currency_code(db, event)
        from utils.event_owner import event_owner_id
        owner_id = uuid.UUID(event_owner_id(event) or str(event.organizer_id))
        organizer = db.query(User).filter(User.id == event.organizer_id).first()
        organizer_phone = (
            format_phone_display(organizer.phone) if organizer and organizer.phone else None
        )

        errors: List[Dict[str, Any]] = []
        success_count = 0
        failure_count = 0
        notifications: List[Dict[str, Any]] = []
        wa_phones: set[str] = set()

        for idx, row in enumerate(rows):
            row_num = idx + 1
            try:
                name = (row.get("name") or "").strip()
                phone_raw = (row.get("phone") or "").strip()
                amount = float(row.get("amount") or 0)

                if not name:
                    errors.append({"row": row_num, "message": "Name is required"})
                    failure_count += 1
                    continue
                phone = None
                if phone_raw:
                    try:
                        phone = validate_phone_number(phone_raw)
                        wa_phones.add(phone)
                    except ValueError:
                        errors.append({
                            "row": row_num,
                            "message": f"Invalid phone for {name}: {phone_raw}",
                        })
                        failure_count += 1
                        continue

                ec = _find_event_contributor_by_phone(db, event.id, phone) if phone else None
                if not ec and not phone:
                    ec = _find_event_contributor_by_name_without_phone(db, event.id, name)

                # Upsert UserContributor without deleting anything. Phone is
                # authoritative when present; rows without a phone are recorded
                # as new/no-phone contributors unless the same no-phone name is
                # already linked to this event.
                contributor = ec.contributor if ec and ec.contributor else None
                if not contributor and phone:
                    contributor = _find_address_book_contributor_by_phone(db, owner_id, phone)
                if not contributor:
                    contributor = UserContributor(
                        id=uuid.uuid4(),
                        user_id=owner_id,
                        name=name,
                        phone=phone,
                        created_at=now,
                        updated_at=now,
                    )
                    db.add(contributor)
                    db.flush()
                else:
                    # Never overwrite the global ``name`` — per-event names
                    # live on EventContributor.display_name. We only backfill
                    # the global phone so subsequent uploads stay in sync.
                    if phone and contributor.phone != phone:
                        clash = (
                            db.query(UserContributor.id)
                            .filter(
                                UserContributor.user_id == owner_id,
                                UserContributor.phone == phone,
                                UserContributor.id != contributor.id,
                            )
                            .first()
                        )
                        if not clash:
                            contributor.phone = phone
                            contributor.updated_at = now

                if not ec:
                    ec = (
                        db.query(EventContributor)
                        .filter(
                            EventContributor.event_id == event.id,
                            EventContributor.contributor_id == contributor.id,
                        )
                        .first()
                    )

                # Resolve per-event display name. NULL when it would just
                # duplicate the global name so explicit overrides remain
                # distinguishable.
                desired_display = name if (name and name != contributor.name) else None

                if mode == "targets":
                    if ec:
                        # Update display_name if the uploaded row carries a
                        # different name than what this event currently shows.
                        current_effective = (ec.display_name or contributor.name or "").strip()
                        if name and name != current_effective:
                            ec.display_name = desired_display
                        old_pledge = float(ec.pledge_amount or 0)
                        ec.pledge_amount = amount
                        ec.updated_at = now
                        if send_sms and amount > 0 and amount != old_pledge:
                            ec.contributor = contributor
                            notifications.append({
                                "event_contributor": ec,
                                "contributor_name": (ec.display_name or contributor.name),
                                "amount": amount,
                                "old_pledge": old_pledge,
                                "kind": "updated" if old_pledge > 0 and amount > old_pledge else "set",
                            })
                    else:
                        ec = EventContributor(
                            id=uuid.uuid4(),
                            event_id=event.id,
                            contributor_id=contributor.id,
                            display_name=desired_display,
                            pledge_amount=amount,
                            secondary_phone=getattr(contributor, "secondary_phone", None),
                            notify_target=getattr(contributor, "notify_target", None) or "primary",
                            created_at=now,
                            updated_at=now,
                        )
                        db.add(ec)
                        db.flush()
                        if send_sms and amount > 0:
                            ec.contributor = contributor
                            notifications.append({
                                "event_contributor": ec,
                                "contributor_name": (ec.display_name or contributor.name),
                                "amount": amount,
                                "old_pledge": 0,
                                "kind": "set",
                            })
                else:
                    if not ec:
                        ec = EventContributor(
                            id=uuid.uuid4(),
                            event_id=event.id,
                            contributor_id=contributor.id,
                            display_name=desired_display,
                            pledge_amount=0,
                            secondary_phone=getattr(contributor, "secondary_phone", None),
                            notify_target=getattr(contributor, "notify_target", None) or "primary",
                            created_at=now,
                            updated_at=now,
                        )
                        db.add(ec)
                        db.flush()
                    else:
                        current_effective = (ec.display_name or contributor.name or "").strip()
                        if name and name != current_effective:
                            ec.display_name = desired_display
                            ec.updated_at = now
                    # Contribution recording delegates to existing helpers
                    # to keep semantics aligned with the inline path.
                    if amount > 0:
                        try:
                            from models import EventContribution, PaymentMethodEnum, ContributionStatusEnum
                            pm = None
                            if job.payment_method:
                                try:
                                    pm = PaymentMethodEnum(job.payment_method)
                                except Exception:
                                    pm = None
                            total_paid_before = sum(float(c.amount or 0) for c in getattr(ec, "contributions", []) or [])
                            db.add(EventContribution(
                                id=uuid.uuid4(),
                                event_id=event.id,
                                event_contributor_id=ec.id,
                                contributor_name=(ec.display_name or contributor.name),
                                amount=amount,
                                payment_method=pm,
                                confirmation_status=ContributionStatusEnum.confirmed,
                                confirmed_at=now,
                                contributed_at=now,
                                created_at=now,
                                updated_at=now,
                            ))
                            if send_sms:
                                ec.contributor = contributor
                                notifications.append({
                                    "event_contributor": ec,
                                    "contributor_name": (ec.display_name or contributor.name),
                                    "amount": amount,
                                    "total_paid": total_paid_before + amount,
                                    "pledge": float(ec.pledge_amount or 0),
                                    "kind": "recorded",
                                })
                        except Exception as e:
                            errors.append({"row": row_num, "message": f"Payment record failed: {e}"})
                            failure_count += 1
                            continue

                success_count += 1
            except Exception as e:  # pragma: no cover
                errors.append({"row": row_num, "message": str(e)})
                failure_count += 1
            finally:
                # Periodic progress checkpoint
                if (idx + 1) % 25 == 0:
                    job.processed_rows = idx + 1
                    job.successful_rows = success_count
                    job.failed_rows = failure_count
                    job.errors = errors
                    db.commit()

        db.commit()

        if notifications:
            try:
                from utils.offline_claims import contributor_notify_phones
                from utils.payment_instructions import resolve_payment_instructions
                from utils.sms import sms_contribution_recorded, sms_contribution_target_set, sms_contribution_target_updated
                from utils.whatsapp import wa_contribution_recorded, wa_contribution_target_set, wa_contribution_target_updated
                try:
                    from utils.wa_logging import set_wa_log_context
                    set_wa_log_context(event_id=str(event.id), event_name=event.name,
                                       source_module="contributor_imports", purpose="contribution_target",
                                       recipient_type="contributor")
                except Exception: pass
                pay_instr = resolve_payment_instructions(event)
                for item in notifications:
                    ec = item["event_contributor"]
                    recipients = contributor_notify_phones(ec)
                    for ph in recipients:
                        try:
                            if item["kind"] == "updated":
                                wa_contribution_target_updated(
                                    ph,
                                    item["contributor_name"],
                                    event.name,
                                    increase=(item["amount"] - item["old_pledge"]),
                                    total_target=item["amount"],
                                    currency=currency,
                                    organizer_phone=organizer_phone,
                                    payment_instructions=pay_instr,
                                )
                            elif item["kind"] == "recorded":
                                wa_contribution_recorded(
                                    ph,
                                    item["contributor_name"],
                                    event.name,
                                    item["amount"],
                                    item["pledge"],
                                    item["total_paid"],
                                    currency,
                                    organizer_phone=organizer_phone,
                                )
                            else:
                                wa_contribution_target_set(
                                    ph,
                                    item["contributor_name"],
                                    event.name,
                                    item["amount"],
                                    0,
                                    currency,
                                    organizer_phone=organizer_phone,
                                    payment_instructions=pay_instr,
                                )
                        except Exception as e:
                            print(f"[bulk_import] WhatsApp notify failed: {e}")
                        try:
                            if item["kind"] == "updated":
                                sms_contribution_target_updated(
                                    ph,
                                    item["contributor_name"],
                                    event.name,
                                    increase=(item["amount"] - item["old_pledge"]),
                                    total_target=item["amount"],
                                    currency=currency,
                                    organizer_phone=organizer_phone,
                                    payment_instructions=pay_instr,
                                )
                            elif item["kind"] == "recorded":
                                sms_contribution_recorded(
                                    ph,
                                    item["contributor_name"],
                                    event.name,
                                    item["amount"],
                                    item["pledge"],
                                    item["total_paid"],
                                    currency,
                                    organizer_phone=organizer_phone,
                                )
                            else:
                                sms_contribution_target_set(
                                    ph,
                                    item["contributor_name"],
                                    event.name,
                                    item["amount"],
                                    0,
                                    currency,
                                    organizer_phone=organizer_phone,
                                    payment_instructions=pay_instr,
                                )
                        except Exception as e:
                            print(f"[bulk_import] SMS notify failed: {e}")
            except Exception as e:
                print(f"[bulk_import] notification setup failed: {e}")

        job.processed_rows = len(rows)
        job.successful_rows = success_count
        job.failed_rows = failure_count
        job.errors = errors
        job.finished_at = datetime.utcnow()
        if failure_count == 0:
            job.status = "completed"
        elif success_count == 0:
            job.status = "failed"
            job.error_message = "All rows failed"
        else:
            job.status = "partially_completed"
        db.commit()


        # Best-effort: queue WhatsApp availability checks for every unique
        # phone discovered. Never blocks the import — failures are swallowed.
        try:
            from tasks.whatsapp_availability import enqueue_phones
            if wa_phones:
                enqueue_phones(list(wa_phones))
        except Exception:
            pass

        return {
            "ok": True,
            "status": job.status,
            "total": len(rows),
            "successful": success_count,
            "failed": failure_count,
        }
    except Exception as e:  # pragma: no cover
        try:
            db.rollback()
            job = (
                db.query(ContributorImportJob)
                .filter(ContributorImportJob.id == uuid.UUID(str(job_id)))
                .first()
            )
            if job:
                job.status = "failed"
                job.error_message = str(e)[:1000]
                job.finished_at = datetime.utcnow()
                db.commit()
        except Exception:
            pass
        raise
    finally:
        db.close()
