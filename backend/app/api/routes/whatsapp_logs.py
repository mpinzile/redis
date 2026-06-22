"""
WhatsApp Logs — user-facing dashboard endpoints
================================================
Every outbound WhatsApp attempt Nuru makes is recorded in
``wa_message_logs``. These endpoints power the "WhatsApp Logs" page
on the user dashboard so silent delivery failures become visible.

User scope (non-admin):
  • messages they triggered (user_id == me), OR
  • messages delivered to their own phone (OTP / receipts), OR
  • messages tied to an event they own/co-organize.

Admins see everything (incl. soft-deleted with ?with_deleted=1).
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Body
from sqlalchemy import desc, func, or_, and_
from sqlalchemy.orm import Session

from core.database import get_db
from models import User
from models.events import Event
from models.wa_message_log import WAMessageLog
from utils.auth import get_current_user
from utils.helpers import standard_response, paginate

router = APIRouter(prefix="/whatsapp/logs", tags=["WhatsApp Logs"])


def _is_admin(user: User) -> bool:
    return bool(getattr(user, "is_admin", False) or getattr(user, "is_superuser", False))


def _scope_to_user(query, db: Session, current_user: User):
    """Limit WhatsApp logs to messages the current user is allowed to see.

    Admins bypass scoping (handled by the caller).
    Non-admins see:
      • messages they triggered (user_id == me), OR
      • messages delivered TO their own normalized phone, OR
      • messages tied to events they organize.
    """
    conds = [WAMessageLog.user_id == current_user.id]

    def _normalize_for_match(raw: str) -> str | None:
        try:
            from utils.whatsapp import _normalize_phone as _np
            v = _np(raw or "")
        except Exception:
            v = (raw or "").strip()
        return v or None

    own_norm = _normalize_for_match(getattr(current_user, "phone", None) or "")
    if own_norm:
        # Equality matches use the existing indexes on
        # ix_wa_message_logs_normalized_phone / _recipient_phone. We no
        # longer add a trailing ILIKE("%last9") on those columns — that
        # disabled the index and forced a sequential scan for every
        # dashboard page load.
        conds.append(WAMessageLog.normalized_phone == own_norm)
        conds.append(WAMessageLog.recipient_phone == own_norm)

    # Events the user organizes (column is `organizer_id`, not `owner_id`).
    # NB: the previous version referenced Event.owner_id which raises and
    # silently swallowed the whole event-scope branch, so organizers were
    # missing messages tied to events they did not personally trigger.
    try:
        own_event_ids = [
            e.id for e in db.query(Event.id).filter(Event.organizer_id == current_user.id).all()
        ]
        if own_event_ids:
            conds.append(WAMessageLog.event_id.in_(own_event_ids))
    except Exception:
        pass

    return query.filter(or_(*conds))



_RETRYABLE_STATUSES = {"failed", "rejected", "unknown"}


def _serialize(row: WAMessageLog, *, detail: bool = False) -> dict:
    data = {
        "id": str(row.id),
        "recipient_phone": row.recipient_phone,
        "recipient_name": row.recipient_name,
        "normalized_phone": row.normalized_phone,
        "user_id": str(row.user_id) if row.user_id else None,
        "event_id": str(row.event_id) if row.event_id else None,
        "event_name_snapshot": row.event_name_snapshot,
        "recipient_type": row.recipient_type,
        "recipient_id": str(row.recipient_id) if row.recipient_id else None,
        "message_purpose": row.message_purpose,
        "source_module": row.source_module,
        "related_entity_type": row.related_entity_type,
        "related_entity_id": str(row.related_entity_id) if row.related_entity_id else None,
        "whatsapp_available": row.whatsapp_available,
        "category": row.category,
        "action": row.action,
        "template_name": row.template_name,
        "message_type": row.message_type,
        "language": row.language,
        "direction": row.direction,
        "summary": row.summary,
        "media_url": row.media_url,
        "media_type": row.media_type,
        "provider": row.provider,
        "provider_message_id": row.provider_message_id,
        "status": row.status,
        "error_code": row.error_code,
        "error_message": row.error_message,
        "error_title": row.error_title,
        "fbtrace_id": row.fbtrace_id,
        "failure_reason": row.failure_reason,
        "retry_count": row.retry_count or 0,
        "parent_log_id": str(row.parent_log_id) if row.parent_log_id else None,
        "fallback_channel": row.fallback_channel,
        "fallback_attempted": bool(row.fallback_attempted),
        "fallback_status": row.fallback_status,
        "fallback_provider": row.fallback_provider,
        "fallback_message_id": row.fallback_message_id,
        "fallback_error": row.fallback_error,
        "fallback_sent_at": row.fallback_sent_at.isoformat() if row.fallback_sent_at else None,
        "queued_at": row.queued_at.isoformat() if row.queued_at else None,
        "sent_at": row.sent_at.isoformat() if row.sent_at else None,
        "delivered_at": row.delivered_at.isoformat() if row.delivered_at else None,
        "read_at": row.read_at.isoformat() if row.read_at else None,
        "failed_at": row.failed_at.isoformat() if row.failed_at else None,
        "last_status_at": row.last_status_at.isoformat() if row.last_status_at else None,
        "deleted_at": row.deleted_at.isoformat() if row.deleted_at else None,
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        "retryable": (row.status in _RETRYABLE_STATUSES) and not row.deleted_at,
    }
    if detail:
        data["request_payload"] = row.request_payload
        data["response_payload"] = row.response_payload
        data["webhook_payload"] = row.webhook_payload
        data["error_details"] = row.error_details
    return data


def _phone_last9(phone: str) -> str:
    digits = "".join(c for c in (phone or "") if c.isdigit())
    return digits[-9:] if len(digits) >= 9 else digits


def _apply_filters(query, *,
                   status, category, message_type, template_name, event_id,
                   recipient, q, date_from, date_to, message_purpose,
                   recipient_type, whatsapp_available, source_module,
                   error_code, fallback_status):
    if status:
        statuses = [s.strip() for s in status.split(",") if s.strip()]
        if statuses:
            query = query.filter(WAMessageLog.status.in_(statuses))
    if category:
        cats = [c.strip() for c in category.split(",") if c.strip()]
        if cats:
            query = query.filter(WAMessageLog.category.in_(cats))
    if message_type:
        query = query.filter(WAMessageLog.message_type == message_type)
    if template_name:
        query = query.filter(WAMessageLog.template_name.ilike(f"%{template_name}%"))
    if event_id:
        try:
            query = query.filter(WAMessageLog.event_id == uuid.UUID(event_id))
        except ValueError:
            raise HTTPException(400, "Invalid event_id")
    if message_purpose:
        purposes = [p.strip() for p in message_purpose.split(",") if p.strip()]
        if purposes:
            query = query.filter(WAMessageLog.message_purpose.in_(purposes))
    if recipient_type:
        rts = [t.strip() for t in recipient_type.split(",") if t.strip()]
        if rts:
            query = query.filter(WAMessageLog.recipient_type.in_(rts))
    if source_module:
        query = query.filter(WAMessageLog.source_module == source_module)
    if error_code:
        query = query.filter(WAMessageLog.error_code == error_code)
    if fallback_status:
        if fallback_status == "attempted":
            query = query.filter(WAMessageLog.fallback_attempted.is_(True))
        elif fallback_status == "none":
            query = query.filter(or_(WAMessageLog.fallback_attempted.is_(False),
                                     WAMessageLog.fallback_attempted.is_(None)))
        else:
            query = query.filter(WAMessageLog.fallback_status == fallback_status)
    if whatsapp_available is not None and whatsapp_available != "":
        if whatsapp_available == "true":
            query = query.filter(WAMessageLog.whatsapp_available.is_(True))
        elif whatsapp_available == "false":
            query = query.filter(WAMessageLog.whatsapp_available.is_(False))
        elif whatsapp_available == "unknown":
            query = query.filter(WAMessageLog.whatsapp_available.is_(None))
    if recipient:
        last9 = _phone_last9(recipient)
        if last9:
            query = query.filter(or_(
                WAMessageLog.recipient_phone.ilike(f"%{last9}"),
                WAMessageLog.normalized_phone.ilike(f"%{last9}"),
                WAMessageLog.recipient_name.ilike(f"%{recipient}%"),
            ))
        else:
            query = query.filter(or_(
                WAMessageLog.recipient_phone.ilike(f"%{recipient}%"),
                WAMessageLog.recipient_name.ilike(f"%{recipient}%"),
            ))
    if q:
        like = f"%{q}%"
        query = query.filter(or_(
            WAMessageLog.summary.ilike(like),
            WAMessageLog.action.ilike(like),
            WAMessageLog.template_name.ilike(like),
            WAMessageLog.error_message.ilike(like),
            WAMessageLog.failure_reason.ilike(like),
            WAMessageLog.recipient_name.ilike(like),
            WAMessageLog.event_name_snapshot.ilike(like),
        ))
    if date_from:
        try:
            query = query.filter(WAMessageLog.created_at >= datetime.fromisoformat(date_from))
        except ValueError:
            raise HTTPException(400, "Invalid date_from (use ISO 8601)")
    if date_to:
        try:
            query = query.filter(WAMessageLog.created_at <= datetime.fromisoformat(date_to))
        except ValueError:
            raise HTTPException(400, "Invalid date_to (use ISO 8601)")
    return query


@router.get("")
def list_logs(
    page: int = Query(1, ge=1),
    limit: int = Query(30, ge=1, le=200),
    status: Optional[str] = None,
    category: Optional[str] = None,
    message_type: Optional[str] = None,
    template_name: Optional[str] = None,
    event_id: Optional[str] = None,
    recipient: Optional[str] = None,
    q: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    message_purpose: Optional[str] = None,
    recipient_type: Optional[str] = None,
    whatsapp_available: Optional[str] = None,
    source_module: Optional[str] = None,
    error_code: Optional[str] = None,
    fallback_status: Optional[str] = None,
    with_deleted: int = Query(0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    base = db.query(WAMessageLog)
    if not _is_admin(current_user):
        base = _scope_to_user(base, db, current_user)
    # Soft delete: hide unless admin opts in
    if not (_is_admin(current_user) and with_deleted):
        base = base.filter(WAMessageLog.deleted_at.is_(None))

    base = _apply_filters(
        base,
        status=status, category=category, message_type=message_type,
        template_name=template_name, event_id=event_id, recipient=recipient,
        q=q, date_from=date_from, date_to=date_to,
        message_purpose=message_purpose, recipient_type=recipient_type,
        whatsapp_available=whatsapp_available, source_module=source_module,
        error_code=error_code, fallback_status=fallback_status,
    )

    base = base.order_by(desc(WAMessageLog.created_at), desc(WAMessageLog.id))
    items, pagination = paginate(base, page, limit)
    data = [_serialize(r) for r in items]
    return standard_response(True, "WhatsApp logs retrieved", data, pagination=pagination)


@router.get("/stats")
def stats(
    days: int = Query(7, ge=1, le=90),
    status: Optional[str] = None,
    category: Optional[str] = None,
    message_type: Optional[str] = None,
    template_name: Optional[str] = None,
    event_id: Optional[str] = None,
    recipient: Optional[str] = None,
    q: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    message_purpose: Optional[str] = None,
    recipient_type: Optional[str] = None,
    whatsapp_available: Optional[str] = None,
    source_module: Optional[str] = None,
    error_code: Optional[str] = None,
    fallback_status: Optional[str] = None,
    with_deleted: int = Query(0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Cache per (user, filter set, days). Tiles refresh every 30s in the
    # UI; the GROUP BY status scan over wa_message_logs is expensive on
    # large tables so we serve it from Redis where possible.
    from core.redis import cache_get, cache_set, CacheKeys
    import hashlib
    filter_payload = "|".join(str(x or "") for x in [
        days, status, category, message_type, template_name, event_id,
        recipient, q, date_from, date_to, message_purpose, recipient_type,
        whatsapp_available, source_module, error_code, fallback_status,
        with_deleted, _is_admin(current_user),
    ])
    fhash = hashlib.md5(filter_payload.encode()).hexdigest()[:16]
    cache_key = CacheKeys.for_wa_log_stats(str(current_user.id), fhash)
    cached = cache_get(cache_key)
    if cached is not None:
        return standard_response(True, "Stats", cached)

    since = datetime.utcnow() - timedelta(days=days)
    base = db.query(WAMessageLog.status, func.count(WAMessageLog.id))
    if not _is_admin(current_user):
        base = _scope_to_user(base, db, current_user)
    if not (_is_admin(current_user) and with_deleted):
        base = base.filter(WAMessageLog.deleted_at.is_(None))
    # Apply the same filters as list_logs so the dashboard stat tiles
    # always reflect what the user is currently viewing.
    base = _apply_filters(
        base,
        status=status, category=category, message_type=message_type,
        template_name=template_name, event_id=event_id, recipient=recipient,
        q=q, date_from=date_from, date_to=date_to,
        message_purpose=message_purpose, recipient_type=recipient_type,
        whatsapp_available=whatsapp_available, source_module=source_module,
        error_code=error_code, fallback_status=fallback_status,
    )
    # Apply the time window only when no explicit date filter is set so a
    # date range from the user takes precedence over the default lookback.
    if not date_from and not date_to:
        base = base.filter(WAMessageLog.created_at >= since)
    rows = base.group_by(WAMessageLog.status).all()
    counts = {s: int(c) for s, c in rows}
    total = sum(counts.values())
    counts["total"] = total
    cache_set(cache_key, counts, ttl_seconds=30)
    return standard_response(True, "Stats", counts)




@router.get("/events")
def list_events_with_logs(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Distinct (event_id, event_name_snapshot) pairs the user can filter by."""
    base = db.query(WAMessageLog.event_id, WAMessageLog.event_name_snapshot)
    if not _is_admin(current_user):
        base = _scope_to_user(base, db, current_user)
    base = base.filter(
        WAMessageLog.event_id.isnot(None),
        WAMessageLog.deleted_at.is_(None),
    ).distinct().limit(500)
    out = []
    seen = set()
    for eid, name in base.all():
        sid = str(eid)
        if sid in seen:
            continue
        seen.add(sid)
        out.append({"event_id": sid, "event_name": name or "—"})
    out.sort(key=lambda r: (r["event_name"] or "").lower())
    return standard_response(True, "Events with WhatsApp logs", out)


@router.get("/purposes")
def list_purposes(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    base = db.query(WAMessageLog.message_purpose).filter(
        WAMessageLog.message_purpose.isnot(None),
        WAMessageLog.deleted_at.is_(None),
    )
    if not _is_admin(current_user):
        base = _scope_to_user(base, db, current_user)
    purposes = sorted({r[0] for r in base.distinct().limit(200).all() if r[0]})
    return standard_response(True, "Message purposes", purposes)


@router.get("/{log_id}")
def get_log(
    log_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        lid = uuid.UUID(log_id)
    except ValueError:
        raise HTTPException(400, "Invalid log id")
    base = db.query(WAMessageLog)
    if not _is_admin(current_user):
        base = _scope_to_user(base, db, current_user)
    row = base.filter(WAMessageLog.id == lid).first()
    if not row:
        raise HTTPException(404, "Log not found")

    history = (
        db.query(WAMessageLog)
          .filter(or_(
              WAMessageLog.parent_log_id == lid,
              WAMessageLog.id == (row.parent_log_id or lid),
              WAMessageLog.parent_log_id == (row.parent_log_id or lid),
          ))
          .order_by(WAMessageLog.created_at.asc())
          .all()
    )

    data = _serialize(row, detail=True)
    data["history"] = [_serialize(h) for h in history if str(h.id) != str(row.id)]
    return standard_response(True, "Log detail", data)


@router.delete("/{log_id}")
def delete_log(
    log_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Soft-delete a WhatsApp log entry. Audit history is preserved —
    only admins can view/restore deleted rows."""
    try:
        lid = uuid.UUID(log_id)
    except ValueError:
        raise HTTPException(400, "Invalid log id")
    base = db.query(WAMessageLog)
    if not _is_admin(current_user):
        base = _scope_to_user(base, db, current_user)
    row = base.filter(WAMessageLog.id == lid).first()
    if not row:
        raise HTTPException(404, "Log not found")
    if row.deleted_at:
        return standard_response(True, "Already deleted", _serialize(row))
    row.deleted_at = datetime.utcnow()
    row.deleted_by_user_id = current_user.id
    db.commit()
    try:
        from core.redis import invalidate_wa_log_stats
        invalidate_wa_log_stats(str(current_user.id))
    except Exception:
        pass
    return standard_response(True, "Log deleted", _serialize(row))


@router.post("/bulk-delete")
def bulk_delete_logs(
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    raw_ids = body.get("ids") or []
    if not isinstance(raw_ids, list) or not raw_ids:
        raise HTTPException(400, "ids[] required")
    ids: list[uuid.UUID] = []
    for v in raw_ids:
        try:
            ids.append(uuid.UUID(str(v)))
        except Exception:
            continue
    if not ids:
        raise HTTPException(400, "no valid ids")
    base = db.query(WAMessageLog).filter(WAMessageLog.id.in_(ids))
    if not _is_admin(current_user):
        base = _scope_to_user(base, db, current_user)
    rows = base.all()
    now = datetime.utcnow()
    for r in rows:
        if not r.deleted_at:
            r.deleted_at = now
            r.deleted_by_user_id = current_user.id
    db.commit()
    try:
        from core.redis import invalidate_wa_log_stats
        invalidate_wa_log_stats(str(current_user.id))
    except Exception:
        pass
    return standard_response(True, f"Deleted {len(rows)} log(s)", {"deleted": len(rows)})


@router.post("/{log_id}/restore")
def restore_log(
    log_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Restore a soft-deleted log. Admins only."""
    if not _is_admin(current_user):
        raise HTTPException(403, "Admins only")
    try:
        lid = uuid.UUID(log_id)
    except ValueError:
        raise HTTPException(400, "Invalid log id")
    row = db.query(WAMessageLog).filter(WAMessageLog.id == lid).first()
    if not row:
        raise HTTPException(404, "Log not found")
    row.deleted_at = None
    row.deleted_by_user_id = None
    db.commit()
    try:
        from core.redis import invalidate_wa_log_stats
        invalidate_wa_log_stats(str(current_user.id))
    except Exception:
        pass
    return standard_response(True, "Log restored", _serialize(row))


@router.post("/{log_id}/resend")
def resend_log(
    log_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Safely retry a failed/rejected message."""
    try:
        lid = uuid.UUID(log_id)
    except ValueError:
        raise HTTPException(400, "Invalid log id")
    base = db.query(WAMessageLog)
    if not _is_admin(current_user):
        base = _scope_to_user(base, db, current_user)
    row = base.filter(WAMessageLog.id == lid).first()
    if not row:
        raise HTTPException(404, "Log not found")
    if row.deleted_at:
        raise HTTPException(400, "Log is deleted")
    if row.status not in _RETRYABLE_STATUSES:
        raise HTTPException(400, f"Cannot resend a message in status '{row.status}'")
    if not row.action:
        raise HTTPException(400, "Original action is missing — cannot resend")

    req = row.request_payload or {}
    if isinstance(req, dict) and "params" in req:
        params = req.get("params") or {}
    else:
        params = req if isinstance(req, dict) else {}

    from utils.wa_logging import log_attempt
    new_id = log_attempt(
        action=row.action,
        phone=row.recipient_phone,
        params=params,
        parent_log_id=str(row.id),
        retry_count=(row.retry_count or 0) + 1,
        meta={
            "event_id": str(row.event_id) if row.event_id else None,
            "event_name": row.event_name_snapshot,
            "recipient_type": row.recipient_type,
            "recipient_id": str(row.recipient_id) if row.recipient_id else None,
            "recipient_name": row.recipient_name,
            "message_purpose": row.message_purpose,
            "source_module": row.source_module,
            "related_entity_type": row.related_entity_type,
            "related_entity_id": str(row.related_entity_id) if row.related_entity_id else None,
        },
    )
    if not new_id:
        raise HTTPException(500, "Failed to create retry log row")

    from utils.whatsapp import _send_whatsapp
    _send_whatsapp(row.action, row.recipient_phone, params, log_id=new_id)

    new_row = db.query(WAMessageLog).filter(WAMessageLog.id == new_id).first()
    return standard_response(True, "Resend queued", _serialize(new_row) if new_row else {"id": new_id})


@router.post("/bulk-resend")
def bulk_resend_logs(
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Queue a resend for many logs at once.

    Each retry is enqueued via the existing WhatsApp send pipeline, which
    fans out to Celery workers in production (so resending 100 messages
    runs in parallel, not serially). A fresh ``wa_message_logs`` row is
    created per retry and linked back to the original via
    ``parent_log_id`` for audit history.

    Body: ``{ "ids": ["uuid", ...] }``.
    Response: ``{ queued, skipped, failures: [{id, reason}] }``.
    """
    raw_ids = body.get("ids") or []
    if not isinstance(raw_ids, list) or not raw_ids:
        raise HTTPException(400, "ids[] required")
    if len(raw_ids) > 500:
        raise HTTPException(400, "Too many ids in one batch (max 500)")

    ids: list[uuid.UUID] = []
    for v in raw_ids:
        try:
            ids.append(uuid.UUID(str(v)))
        except Exception:
            continue
    if not ids:
        raise HTTPException(400, "no valid ids")

    base = db.query(WAMessageLog).filter(WAMessageLog.id.in_(ids))
    if not _is_admin(current_user):
        base = _scope_to_user(base, db, current_user)
    rows = base.all()

    queued = 0
    skipped = 0
    failures: list[dict] = []

    from utils.wa_logging import log_attempt
    from utils.whatsapp import _send_whatsapp

    for row in rows:
        if row.deleted_at:
            skipped += 1
            failures.append({"id": str(row.id), "reason": "deleted"})
            continue
        if row.status not in _RETRYABLE_STATUSES:
            skipped += 1
            failures.append({"id": str(row.id), "reason": f"status '{row.status}' not retryable"})
            continue
        if not row.action:
            skipped += 1
            failures.append({"id": str(row.id), "reason": "missing action"})
            continue

        req = row.request_payload or {}
        params = req.get("params") if (isinstance(req, dict) and "params" in req) else (req if isinstance(req, dict) else {})

        try:
            new_id = log_attempt(
                action=row.action,
                phone=row.recipient_phone,
                params=params or {},
                parent_log_id=str(row.id),
                retry_count=(row.retry_count or 0) + 1,
                meta={
                    "event_id": str(row.event_id) if row.event_id else None,
                    "event_name": row.event_name_snapshot,
                    "recipient_type": row.recipient_type,
                    "recipient_id": str(row.recipient_id) if row.recipient_id else None,
                    "recipient_name": row.recipient_name,
                    "message_purpose": row.message_purpose,
                    "source_module": row.source_module,
                    "related_entity_type": row.related_entity_type,
                    "related_entity_id": str(row.related_entity_id) if row.related_entity_id else None,
                },
            )
            if not new_id:
                raise RuntimeError("could not create retry log row")
            # Fans out to Celery (one task per recipient → parallel workers).
            _send_whatsapp(row.action, row.recipient_phone, params or {}, log_id=new_id)
            queued += 1
        except Exception as e:  # noqa: BLE001
            skipped += 1
            failures.append({"id": str(row.id), "reason": str(e)[:200]})

    return standard_response(
        True,
        f"Queued {queued} resend(s)" + (f", skipped {skipped}" if skipped else ""),
        {"queued": queued, "skipped": skipped, "failures": failures},
    )
