"""Voice Calls REST API — Phase 3 of nuru_voice.md.

Endpoints (all under /voice-calls):

* Campaigns
    POST   /voice-calls/campaigns                 -> create a campaign (draft)
    GET    /voice-calls/campaigns                 -> list my campaigns
    GET    /voice-calls/campaigns/{id}            -> campaign detail + counts
    PATCH  /voice-calls/campaigns/{id}            -> update fields / status
    DELETE /voice-calls/campaigns/{id}            -> delete (only when draft/cancelled)
    POST   /voice-calls/campaigns/{id}/start      -> set status=queued (worker will pick up)
    POST   /voice-calls/campaigns/{id}/pause      -> pause running campaign
    POST   /voice-calls/campaigns/{id}/cancel     -> cancel campaign

* Jobs
    POST   /voice-calls/campaigns/{id}/jobs       -> bulk add recipients
    GET    /voice-calls/campaigns/{id}/jobs       -> list jobs (paginated)
    GET    /voice-calls/jobs/{job_id}             -> job detail + recent logs
    POST   /voice-calls/jobs/{job_id}/retry       -> queue another attempt

* Logs
    GET    /voice-calls/logs/{job_id}             -> all provider attempts for a job

* Opt-outs
    GET    /voice-calls/opt-outs                  -> list opt-outs (admin / org owner view)
    POST   /voice-calls/opt-outs                  -> add a number
    DELETE /voice-calls/opt-outs/{phone}          -> remove (admin only)

The actual outbound calling (Twilio) is wired in Phase 4. These routes only
persist intent + drive status transitions, while running the safety preflight
from ``app.voice.safety`` before any phone number is accepted into a job.
"""
from __future__ import annotations

import math
import uuid
from datetime import datetime, timedelta
from typing import Optional, List, Any

from fastapi import APIRouter, Depends, HTTPException, Query, Body, Request, Form, Response, WebSocket, BackgroundTasks
from pydantic import BaseModel, Field, validator
from sqlalchemy import func as sa_func, and_, or_
from sqlalchemy.orm import Session

from core.database import get_db
from core import config
from models import (
    VoiceCampaign, VoiceCallJob, VoiceCallLog, VoiceOptOut,
    VoiceFeatureSetting, Event, User,
)
from models.admin import AdminUser
from utils.auth import get_current_user
from utils.helpers import standard_response
import jwt as _jwt
from fastapi import Request as _FastRequest
from core.config import SECRET_KEY as _SECRET_KEY, ALGORITHM as _ALGORITHM


def _decode_bearer(request: "_FastRequest") -> Optional[dict]:
    """Best-effort decode of the Authorization Bearer JWT. Returns the
    payload dict on success, or None when no/invalid token is present.
    """
    auth = request.headers.get("Authorization") or ""
    if not auth.lower().startswith("bearer "):
        return None
    token = auth.split(" ", 1)[1].strip()
    try:
        return _jwt.decode(token, _SECRET_KEY, algorithms=[_ALGORITHM])
    except Exception:  # noqa: BLE001
        return None


def _get_admin_principal(
    request: "_FastRequest",
    db: "Session",
) -> Optional[AdminUser]:
    """Return the AdminUser when the request carries a valid admin token
    (``admin_id`` claim + ``is_admin: True``). Returns ``None`` otherwise
    so callers can fall through to user-based admin detection.
    """
    payload = _decode_bearer(request)
    if not payload or not payload.get("is_admin"):
        return None
    admin_id = payload.get("admin_id")
    if not admin_id:
        return None
    admin = db.query(AdminUser).filter(AdminUser.id == admin_id).first()
    if admin and getattr(admin, "is_active", True):
        return admin
    return None


def require_voice_admin(
    request: _FastRequest,
    db: Session = Depends(get_db),
) -> AdminUser:
    """FastAPI dependency: only callers with a valid admin JWT may pass."""
    admin = _get_admin_principal(request, db)
    if not admin:
        raise HTTPException(status_code=403, detail="Admins only")
    return admin


def get_user_or_admin(
    request: _FastRequest,
    db: Session = Depends(get_db),
) -> Any:
    """Returns either an ``AdminUser`` (admin token) or a regular ``User``
    (user access token). Used by read-only endpoints that both surfaces
    need — e.g. the feature-flag status panel.
    """
    admin = _get_admin_principal(request, db)
    if admin:
        return admin
    # Fall back to regular user auth — decode the access_token JWT.
    payload = _decode_bearer(request)
    uid = payload.get("uid") if payload else None
    if uid:
        user = db.query(User).filter(User.id == uid).first()
        if user and getattr(user, "is_active", True):
            return user
    raise HTTPException(status_code=401, detail="Unauthorized")
from utils.event_owner import user_can_manage_event
from voice.safety import check_can_call
from voice import twilio_client
from voice.realtime import handle_twilio_stream


router = APIRouter(prefix="/voice-calls", tags=["Voice Calls"])


# ──────────────────────────────────────────────────────────────────
# Pydantic schemas
# ──────────────────────────────────────────────────────────────────

ALLOWED_PURPOSES = {
    "rsvp", "contribution", "verification",
    "committee", "vendor", "feedback", "general",
}
ALLOWED_CAMPAIGN_STATUSES = {
    "draft", "queued", "running", "paused", "completed", "cancelled",
}


class CampaignCreate(BaseModel):
    event_id: Optional[str] = None
    purpose: str = "rsvp"
    language: str = Field(default="sw", max_length=8)
    title: Optional[str] = Field(default=None, max_length=200)
    notes: Optional[str] = Field(default=None, max_length=4000)

    @validator("purpose")
    def _v_purpose(cls, v):
        if v not in ALLOWED_PURPOSES:
            raise ValueError(f"purpose must be one of {sorted(ALLOWED_PURPOSES)}")
        return v


class CampaignUpdate(BaseModel):
    title: Optional[str] = Field(default=None, max_length=200)
    notes: Optional[str] = Field(default=None, max_length=4000)
    language: Optional[str] = Field(default=None, max_length=8)
    purpose: Optional[str] = None
    status: Optional[str] = None

    @validator("purpose")
    def _v_purpose(cls, v):
        if v is not None and v not in ALLOWED_PURPOSES:
            raise ValueError(f"purpose must be one of {sorted(ALLOWED_PURPOSES)}")
        return v

    @validator("status")
    def _v_status(cls, v):
        if v is not None and v not in ALLOWED_CAMPAIGN_STATUSES:
            raise ValueError(f"status must be one of {sorted(ALLOWED_CAMPAIGN_STATUSES)}")
        return v


class JobRecipient(BaseModel):
    recipient_type: str = "guest"
    recipient_ref_id: Optional[str] = None
    recipient_name: str = ""
    phone: str
    language: Optional[str] = None
    timezone: Optional[str] = None
    scheduled_at: Optional[datetime] = None
    max_attempts: Optional[int] = None
    extra: Optional[dict] = None


class JobsCreate(BaseModel):
    recipients: List[JobRecipient]
    enforce_hours: bool = True


class OptOutCreate(BaseModel):
    phone: str
    reason: Optional[str] = Field(default=None, max_length=500)
    source: str = "organiser"


# ──────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────

def _uuid_or_400(value: str, field: str = "id") -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError):
        raise HTTPException(400, detail=f"Invalid {field}")


def _serialize_campaign(c: VoiceCampaign, counts: Optional[dict] = None) -> dict:
    counts = counts or {}
    return {
        "id": str(c.id),
        "event_id": str(c.event_id) if c.event_id else None,
        "owner_id": str(c.owner_id) if c.owner_id else None,
        "purpose": c.purpose,
        "language": c.language,
        "status": c.status,
        "title": c.title,
        "notes": c.notes,
        "estimated_cost_usd": float(c.estimated_cost_usd) if c.estimated_cost_usd is not None else None,
        "started_at": c.started_at.isoformat() if c.started_at else None,
        "completed_at": c.completed_at.isoformat() if c.completed_at else None,
        "created_at": c.created_at.isoformat() if c.created_at else None,
        "updated_at": c.updated_at.isoformat() if c.updated_at else None,
        "counts": counts,
    }


def _serialize_job(j: VoiceCallJob) -> dict:
    return {
        "id": str(j.id),
        "campaign_id": str(j.campaign_id),
        "recipient_type": j.recipient_type,
        "recipient_ref_id": str(j.recipient_ref_id) if j.recipient_ref_id else None,
        "recipient_name": j.recipient_name,
        "phone_e164": j.phone_e164,
        "country": j.country,
        "timezone": j.timezone,
        "language": j.language,
        "status": j.status,
        "block_reason": j.block_reason,
        "attempt": j.attempt,
        "max_attempts": j.max_attempts,
        "scheduled_at": j.scheduled_at.isoformat() if j.scheduled_at else None,
        "next_retry_at": j.next_retry_at.isoformat() if j.next_retry_at else None,
        "last_called_at": j.last_called_at.isoformat() if j.last_called_at else None,
        "ai_outcome": j.ai_outcome,
        "ai_confidence": float(j.ai_confidence) if j.ai_confidence is not None else None,
        "summary": j.summary,
        "extra": j.extra,
        "created_at": j.created_at.isoformat() if j.created_at else None,
        "updated_at": j.updated_at.isoformat() if j.updated_at else None,
    }


def _serialize_log(l: VoiceCallLog) -> dict:
    return {
        "id": str(l.id),
        "job_id": str(l.job_id),
        "provider": l.provider,
        "provider_call_sid": l.provider_call_sid,
        "status": l.status,
        "end_reason": l.end_reason,
        "started_at": l.started_at.isoformat() if l.started_at else None,
        "answered_at": l.answered_at.isoformat() if l.answered_at else None,
        "ended_at": l.ended_at.isoformat() if l.ended_at else None,
        "duration_seconds": l.duration_seconds,
        "cost_estimate_usd": float(l.cost_estimate_usd) if l.cost_estimate_usd is not None else None,
        "recording_url": l.recording_url,
        "transcript": l.transcript,
        "summary": l.summary,
        "ai_outcome": l.ai_outcome,
        "ai_confidence": float(l.ai_confidence) if l.ai_confidence is not None else None,
        "ai_tool_calls": l.ai_tool_calls,
        "error_code": l.error_code,
        "error_message": l.error_message,
        "created_at": l.created_at.isoformat() if l.created_at else None,
    }


def _serialize_opt_out(o: VoiceOptOut) -> dict:
    return {
        "id": str(o.id),
        "phone_e164": o.phone_e164,
        "reason": o.reason,
        "source": o.source,
        "added_by_user_id": str(o.added_by_user_id) if o.added_by_user_id else None,
        "created_at": o.created_at.isoformat() if o.created_at else None,
    }


def _is_admin(user: User) -> bool:
    return bool(getattr(user, "is_admin", False) or getattr(user, "is_superuser", False))


# ──────────────────────────────────────────────────────────────────
# Feature flag (admin-controlled on/off switch)
# ──────────────────────────────────────────────────────────────────

def _get_or_create_feature(db: Session) -> VoiceFeatureSetting:
    row = (
        db.query(VoiceFeatureSetting)
        .filter(VoiceFeatureSetting.singleton == "global")
        .first()
    )
    if row is None:
        row = VoiceFeatureSetting(singleton="global", enabled=True)
        db.add(row)
        try:
            db.commit()
            db.refresh(row)
        except Exception:  # noqa: BLE001
            db.rollback()
            row = (
                db.query(VoiceFeatureSetting)
                .filter(VoiceFeatureSetting.singleton == "global")
                .first()
            )
    return row


def _serialize_feature(row: VoiceFeatureSetting) -> dict:
    return {
        "enabled": bool(row.enabled),
        "disabled_message_en": row.disabled_message_en,
        "disabled_message_sw": row.disabled_message_sw,
        "updated_by_user_id": str(row.updated_by_user_id) if row.updated_by_user_id else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }


def _require_feature_enabled(db: Session) -> None:
    """Raise HTTP 503 with a polite payload when admins disabled the feature.

    Admin users are NOT exempt — disabling means the feature is offline
    for everyone, including admins (they can still toggle it back on).
    """
    row = _get_or_create_feature(db)
    if not row.enabled:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "voice_feature_disabled",
                "message": row.disabled_message_en,
                "message_sw": row.disabled_message_sw,
                "feature": "voice_calls",
            },
        )


class FeatureToggleUpdate(BaseModel):
    enabled: Optional[bool] = None
    disabled_message_en: Optional[str] = Field(default=None, max_length=1000)
    disabled_message_sw: Optional[str] = Field(default=None, max_length=1000)


@router.get("/feature-status")
def get_feature_status(
    principal: Any = Depends(get_user_or_admin),
    db: Session = Depends(get_db),
):
    """Public to any authenticated user (regular ``access_token``) OR any
    admin (``admin_token``) — used by web + mobile to render a polite
    "temporarily disabled" panel when admins have paused the feature.
    """
    row = _get_or_create_feature(db)
    return standard_response(True, "ok", _serialize_feature(row))


@router.patch("/admin/feature-status")
def update_feature_status(
    payload: FeatureToggleUpdate,
    admin: AdminUser = Depends(require_voice_admin),
    db: Session = Depends(get_db),
):
    """Admin-only toggle (requires the dedicated admin JWT issued by
    ``/admin/auth/login``). Body fields are all optional — only the ones
    provided are updated.
    """
    row = _get_or_create_feature(db)
    if payload.enabled is not None:
        row.enabled = bool(payload.enabled)
    if payload.disabled_message_en is not None:
        msg = payload.disabled_message_en.strip()
        if msg:
            row.disabled_message_en = msg
    if payload.disabled_message_sw is not None:
        msg = payload.disabled_message_sw.strip()
        if msg:
            row.disabled_message_sw = msg
    # ``updated_by_user_id`` references ``users.id``; admin users live in
    # a separate table, so we only stamp it when a regular user is the
    # author (currently unused — admin token is always used). Leaving
    # it untouched is safer than writing a non-existent user id.
    db.commit()
    db.refresh(row)
    return standard_response(
        True,
        "Voice Assistant feature " + ("enabled" if row.enabled else "disabled"),
        _serialize_feature(row),
    )


def _get_owned_campaign(
    db: Session, campaign_id: str, user: User, *, for_write: bool = True,
) -> VoiceCampaign:
    cid = _uuid_or_400(campaign_id, "campaign_id")
    c = db.query(VoiceCampaign).filter(VoiceCampaign.id == cid).first()
    if not c:
        raise HTTPException(404, detail="Campaign not found")
    if c.owner_id and c.owner_id != user.id and not _is_admin(user):
        raise HTTPException(403, detail="Not allowed")
    return c


def _job_counts(db: Session, campaign_id: uuid.UUID) -> dict:
    rows = (
        db.query(VoiceCallJob.status, sa_func.count(VoiceCallJob.id))
        .filter(VoiceCallJob.campaign_id == campaign_id)
        .group_by(VoiceCallJob.status)
        .all()
    )
    out = {"total": 0}
    for status, count in rows:
        out[status] = int(count)
        out["total"] += int(count)
    return out


def _opt_out_set(db: Session, phones: List[str]) -> set:
    if not phones:
        return set()
    rows = (
        db.query(VoiceOptOut.phone_e164)
        .filter(VoiceOptOut.phone_e164.in_(phones))
        .all()
    )
    return {r[0] for r in rows}


# ──────────────────────────────────────────────────────────────────
# Campaign endpoints
# ──────────────────────────────────────────────────────────────────

@router.post("/campaigns")
def create_campaign(
    payload: CampaignCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_feature_enabled(db)
    event_uuid = None
    if payload.event_id:
        event_uuid = _uuid_or_400(payload.event_id, "event_id")
        event = db.query(Event).filter(Event.id == event_uuid).first()
        if not event:
            raise HTTPException(404, detail="Event not found")
        if not user_can_manage_event(event, current_user) and not _is_admin(current_user):
            raise HTTPException(403, detail="Not the event owner")


    campaign = VoiceCampaign(
        event_id=event_uuid,
        owner_id=current_user.id,
        purpose=payload.purpose,
        language=payload.language or "sw",
        title=payload.title,
        notes=payload.notes,
        status="draft",
    )
    db.add(campaign)
    db.commit()
    db.refresh(campaign)
    return standard_response(True, "Campaign created", _serialize_campaign(campaign, {"total": 0}))


@router.get("/campaigns")
def list_campaigns(
    event_id: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(VoiceCampaign)
    if not _is_admin(current_user):
        q = q.filter(VoiceCampaign.owner_id == current_user.id)
    if event_id:
        q = q.filter(VoiceCampaign.event_id == _uuid_or_400(event_id, "event_id"))
    if status:
        if status not in ALLOWED_CAMPAIGN_STATUSES:
            raise HTTPException(400, detail="Invalid status")
        q = q.filter(VoiceCampaign.status == status)

    total = q.count()
    rows = (
        q.order_by(VoiceCampaign.created_at.desc())
        .offset((page - 1) * page_size).limit(page_size).all()
    )
    items = [_serialize_campaign(c, _job_counts(db, c.id)) for c in rows]
    pagination = {
        "page": page,
        "page_size": page_size,
        "total_items": total,
        "total_pages": math.ceil(total / page_size) if total else 0,
    }
    return standard_response(True, "ok", items, pagination=pagination)


@router.get("/campaigns/{campaign_id}")
def get_campaign(
    campaign_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    c = _get_owned_campaign(db, campaign_id, current_user, for_write=False)
    return standard_response(True, "ok", _serialize_campaign(c, _job_counts(db, c.id)))


@router.patch("/campaigns/{campaign_id}")
def update_campaign(
    campaign_id: str,
    payload: CampaignUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    c = _get_owned_campaign(db, campaign_id, current_user)

    if payload.title is not None:
        c.title = payload.title
    if payload.notes is not None:
        c.notes = payload.notes
    if payload.language is not None:
        c.language = payload.language
    if payload.purpose is not None:
        c.purpose = payload.purpose
    if payload.status is not None:
        c.status = payload.status
        if payload.status == "running" and not c.started_at:
            c.started_at = datetime.utcnow()
        if payload.status == "completed" and not c.completed_at:
            c.completed_at = datetime.utcnow()

    db.commit()
    db.refresh(c)
    return standard_response(True, "Campaign updated",
                             _serialize_campaign(c, _job_counts(db, c.id)))


@router.delete("/campaigns/{campaign_id}")
def delete_campaign(
    campaign_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    c = _get_owned_campaign(db, campaign_id, current_user)
    if c.status not in {"draft", "cancelled", "completed"}:
        raise HTTPException(
            400,
            detail="Cancel or complete the campaign before deleting it",
        )
    db.delete(c)
    db.commit()
    return standard_response(True, "Campaign deleted")


def _set_campaign_status(
    db: Session, campaign_id: str, current_user: User,
    new_status: str, ok_message: str,
    allowed_from: Optional[set] = None,
) -> dict:
    c = _get_owned_campaign(db, campaign_id, current_user)
    if allowed_from and c.status not in allowed_from:
        raise HTTPException(
            400,
            detail=f"Cannot move campaign from {c.status} to {new_status}",
        )
    c.status = new_status
    if new_status == "queued" and not c.started_at:
        c.started_at = datetime.utcnow()
    if new_status == "cancelled":
        c.completed_at = datetime.utcnow()
    db.commit()
    db.refresh(c)
    return standard_response(True, ok_message,
                             _serialize_campaign(c, _job_counts(db, c.id)))


@router.post("/campaigns/{campaign_id}/start")
def start_campaign(campaign_id: str,
                   background_tasks: BackgroundTasks,
                   db: Session = Depends(get_db),
                   current_user: User = Depends(get_current_user)):
    _require_feature_enabled(db)
    result = _set_campaign_status(
        db, campaign_id, current_user, "running", "Campaign started — dialing now",
        allowed_from={"draft", "queued", "paused", "completed"},
    )
    # Kick off the dispatcher in the background so the HTTP response
    # returns immediately while Twilio is being called.
    background_tasks.add_task(_dispatch_campaign_jobs, campaign_id)
    return result


_DISPATCHABLE_STATUSES = ("pending", "failed", "no_answer", "busy", "queued", "in_progress")


def _active_stale_after_seconds() -> int:
    # If Twilio status callbacks are not reaching us, jobs can remain queued
    # forever even after the recipient's phone call has ended. Treat an active
    # job as stale after the normal call window so Resume / Call again can redial.
    # Respect VOICE_MAX_CALL_SECONDS (default 120) — do NOT cap at 90s.
    return max(20, int(config.VOICE_MAX_CALL_SECONDS or 120))


def _active_attempt_is_stale(job: VoiceCallJob, now: datetime) -> bool:
    if job.status not in {"queued", "in_progress"}:
        return False
    last = job.last_called_at or job.created_at
    if last is None:
        return True
    return (now - last).total_seconds() >= _active_stale_after_seconds()


def _job_due_for_dispatch(job: VoiceCallJob, now: datetime) -> bool:
    status = (job.status or "pending").lower()
    if status == "pending":
        scheduled_ok = job.scheduled_at is None or job.scheduled_at <= now
        retry_ok = job.next_retry_at is None or job.next_retry_at <= now
        return scheduled_ok and retry_ok
    if status in {"failed", "no_answer", "busy"}:
        has_attempt_left = (job.attempt or 0) < (job.max_attempts or 1)
        retry_ok = job.next_retry_at is None or job.next_retry_at <= now
        return has_attempt_left and retry_ok
    return _active_attempt_is_stale(job, now)


def _mark_active_attempt_superseded(db: Session, job: VoiceCallJob, reason: str) -> None:
    log = (
        db.query(VoiceCallLog)
        .filter(VoiceCallLog.job_id == job.id,
                VoiceCallLog.status.in_(("queued", "initiated", "ringing", "in-progress")))
        .order_by(VoiceCallLog.created_at.desc())
        .first()
    )
    if log is not None:
        log.status = "superseded"
        log.end_reason = reason[:200]
        log.ended_at = datetime.utcnow()


def _dispatch_campaign_jobs(campaign_id: str) -> None:
    """Dial every pending job for a campaign right now.

    Runs after the HTTP response is sent (FastAPI BackgroundTasks). Every
    dispatch attempt — success, Twilio rejection, missing creds — is
    written to ``backend/app/log.txt`` via the voice file logger so the
    operator can tail it on the server.
    """
    import logging as _logging
    from core.database import SessionLocal
    log = _logging.getLogger("nuru.voice.dispatch")
    db: Session = SessionLocal()
    try:
        try:
            cid = uuid.UUID(campaign_id)
        except (TypeError, ValueError):
            log.error("dispatch: invalid campaign id %r", campaign_id)
            return
        c = db.query(VoiceCampaign).filter(VoiceCampaign.id == cid).first()
        if not c:
            log.error("dispatch: campaign %s not found", campaign_id)
            return
        if c.status not in {"queued", "running"}:
            log.info("dispatch: campaign %s is %s — skipping", campaign_id, c.status)
            return

        now = datetime.utcnow()
        candidates = (
            db.query(VoiceCallJob)
            .filter(VoiceCallJob.campaign_id == cid,
                    VoiceCallJob.status.in_(_DISPATCHABLE_STATUSES))
            .order_by(VoiceCallJob.created_at.asc())
            .all()
        )
        pending = [job for job in candidates if _job_due_for_dispatch(job, now)]
        log.info("dispatch: campaign=%s dialing %d due job(s) from %d candidate(s)",
                 campaign_id, len(pending), len(candidates))
        for job in pending:
            try:
                if _active_attempt_is_stale(job, datetime.utcnow()):
                    _mark_active_attempt_superseded(db, job, "redialled after stale active status")
                    job.status = "pending"
                    job.block_reason = None
                    job.next_retry_at = None
                    db.flush()
                opted_out = _opt_out_set(db, [job.phone_e164])
                verdict = check_can_call(
                    job.phone_e164,
                    recipient_tz=job.timezone,
                    is_opted_out=lambda p: p in opted_out,
                    # Campaign-level dialing respects calling hours.
                    enforce_hours=True,
                )
                if not verdict.allowed:
                    job.status = ("pending" if verdict.code == "outside_hours"
                                  else "blocked")
                    job.block_reason = verdict.reason
                    if verdict.code == "outside_hours":
                        job.next_retry_at = datetime.utcnow() + timedelta(
                            seconds=int(config.VOICE_RETRY_BACKOFF_SECONDS or 60),
                        )
                    db.commit()
                    log.warning("dispatch: job=%s skipped reason=%s",
                                job.id, verdict.reason)
                    continue

                # Pre-generate the personalised greeting so the recipient
                # hears speech the instant they pick up. Best-effort: any
                # failure is logged but doesn't block the call.
                try:
                    from voice.greeting_audio import ensure_for_job as _ensure_greeting
                    _gen, _gerr = _ensure_greeting(job.id)
                    if _gerr:
                        log.info("dispatch: greeting not generated job=%s reason=%s",
                                 job.id, _gerr)
                except Exception:  # noqa: BLE001
                    log.exception("dispatch: pre-greeting hook crashed job=%s", job.id)

                try:
                    result = twilio_client.place_call(
                        to_phone_e164=job.phone_e164,
                        job_id=str(job.id),
                    )
                except twilio_client.TwilioConfigError as exc:
                    db.add(VoiceCallLog(
                        job_id=job.id, provider="twilio", status="failed",
                        error_code="config", error_message=str(exc)[:500],
                    ))
                    job.status = "failed"
                    db.commit()
                    log.error("dispatch: job=%s config error: %s", job.id, exc)
                    continue
                except twilio_client.TwilioApiError as exc:
                    db.add(VoiceCallLog(
                        job_id=job.id, provider="twilio", status="failed",
                        error_code=str(exc.status), error_message=str(exc)[:500],
                    ))
                    job.status = "failed"
                    job.attempt = (job.attempt or 0) + 1
                    job.last_called_at = datetime.utcnow()
                    db.commit()
                    log.error("dispatch: job=%s twilio error [%s]: %s",
                              job.id, exc.status, exc)
                    continue

                db.add(VoiceCallLog(
                    job_id=job.id, provider="twilio",
                    provider_call_sid=result.call_sid,
                    status=result.status or "queued",
                    started_at=datetime.utcnow(),
                ))
                job.status = twilio_client.status_to_job_status(result.status or "queued")
                job.attempt = (job.attempt or 0) + 1
                job.last_called_at = datetime.utcnow()
                job.block_reason = None
                db.commit()
                log.info("dispatch: job=%s sid=%s status=%s",
                         job.id, result.call_sid, result.status)
            except Exception as exc:  # noqa: BLE001
                db.rollback()
                log.exception("dispatch: unexpected failure for job=%s: %r",
                              getattr(job, "id", "?"), exc)

        # Flip campaign to running while there are still in-flight jobs, or
        # completed when all jobs are terminal.
        remaining = (
            db.query(VoiceCallJob)
            .filter(VoiceCallJob.campaign_id == cid,
                    VoiceCallJob.status.in_(("pending", "queued", "in_progress")))
            .count()
        )
        c = db.query(VoiceCampaign).filter(VoiceCampaign.id == cid).first()
        if c and c.status != "cancelled":
            c.status = "running" if remaining else "completed"
            if c.status == "completed":
                c.completed_at = datetime.utcnow()
            db.commit()
    finally:
        db.close()



@router.post("/campaigns/{campaign_id}/pause")
def pause_campaign(campaign_id: str,
                   db: Session = Depends(get_db),
                   current_user: User = Depends(get_current_user)):
    return _set_campaign_status(
        db, campaign_id, current_user, "paused", "Campaign paused",
        allowed_from={"queued", "running"},
    )


@router.post("/campaigns/{campaign_id}/cancel")
def cancel_campaign(campaign_id: str,
                    db: Session = Depends(get_db),
                    current_user: User = Depends(get_current_user)):
    return _set_campaign_status(
        db, campaign_id, current_user, "cancelled", "Campaign cancelled",
        allowed_from={"draft", "queued", "running", "paused"},
    )


# ──────────────────────────────────────────────────────────────────
# Job endpoints
# ──────────────────────────────────────────────────────────────────

@router.post("/campaigns/{campaign_id}/jobs")
def add_jobs(
    campaign_id: str,
    payload: JobsCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_feature_enabled(db)
    if not payload.recipients:
        raise HTTPException(400, detail="At least one recipient is required")
    if len(payload.recipients) > 5000:
        raise HTTPException(400, detail="Too many recipients in one request (max 5000)")

    c = _get_owned_campaign(db, campaign_id, current_user)
    if c.status in {"completed", "cancelled"}:
        raise HTTPException(400, detail="Cannot add jobs to a finished campaign")

    # Resolve event timezone once (best-effort).
    event_tz = None
    if c.event_id:
        ev = db.query(Event).filter(Event.id == c.event_id).first()
        if ev is not None:
            event_tz = getattr(ev, "timezone", None) or getattr(ev, "tz", None)

    max_attempts_default = max(1, int(config.VOICE_MAX_RETRY_ATTEMPTS or 1) + 1)

    accepted: list[VoiceCallJob] = []
    rejected: list[dict] = []

    # Pre-fetch opt-outs for the batch in a single query.
    raw_phones = [r.phone for r in payload.recipients if r.phone]
    normalized_lookup: dict[str, str] = {}
    for r in payload.recipients:
        verdict = check_can_call(
            r.phone,
            recipient_tz=r.timezone,
            event_tz=event_tz,
            enforce_hours=False,  # final check happens at dial-time
        )
        if verdict.allowed:
            normalized_lookup[r.phone] = verdict.phone_e164
    opt_out_phones = _opt_out_set(db, list(normalized_lookup.values()))

    for recipient in payload.recipients:
        verdict = check_can_call(
            recipient.phone,
            recipient_tz=recipient.timezone,
            event_tz=event_tz,
            is_opted_out=lambda p: p in opt_out_phones,
            enforce_hours=payload.enforce_hours,
        )

        ref_uuid = None
        if recipient.recipient_ref_id:
            try:
                ref_uuid = uuid.UUID(str(recipient.recipient_ref_id))
            except (TypeError, ValueError):
                ref_uuid = None

        recipient_language = (recipient.language or "").strip() or None
        extra = dict(recipient.extra or {})
        if recipient_language:
            extra["language_source"] = "recipient_preference"

        job = VoiceCallJob(
            campaign_id=c.id,
            recipient_type=recipient.recipient_type or "guest",
            recipient_ref_id=ref_uuid,
            recipient_name=(recipient.recipient_name or "").strip()[:200],
            phone_e164=verdict.phone_e164 or recipient.phone,
            country=verdict.country,
            timezone=verdict.timezone or recipient.timezone,
            language=recipient_language,
            scheduled_at=recipient.scheduled_at,
            max_attempts=recipient.max_attempts or max_attempts_default,
            extra=extra or None,
        )

        if verdict.allowed:
            job.status = "pending"
        else:
            # Don't enqueue, but persist for visibility.
            blocked_status_map = {
                "opted_out": "opted_out",
                "emergency": "blocked",
                "country_blocked": "blocked",
                "invalid_phone": "blocked",
                "daily_limit": "blocked",
                "outside_hours": "pending",  # will retry inside window
            }
            job.status = blocked_status_map.get(verdict.code, "blocked")
            job.block_reason = verdict.reason

        db.add(job)
        accepted.append(job)
        if not verdict.allowed:
            rejected.append({
                "phone": recipient.phone,
                "code": verdict.code,
                "reason": verdict.reason,
            })

    db.commit()
    for j in accepted:
        db.refresh(j)

    serialized_jobs = [_serialize_job(j) for j in accepted]
    accepted_jobs = [s for s in serialized_jobs
                     if s["status"] in {"pending", "queued"}]
    return standard_response(
        True,
        f"Added {len(accepted)} job(s)",
        {
            "jobs": serialized_jobs,
            # Alias kept for backward-compatible mobile/web clients that read
            # `data.accepted` — only contains jobs that are actually dialable.
            "accepted": accepted_jobs,
            "rejected": rejected,
            "counts": _job_counts(db, c.id),
        },
    )


@router.get("/campaigns/{campaign_id}/jobs")
def list_jobs(
    campaign_id: str,
    status: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    c = _get_owned_campaign(db, campaign_id, current_user, for_write=False)
    q = db.query(VoiceCallJob).filter(VoiceCallJob.campaign_id == c.id)
    if status:
        q = q.filter(VoiceCallJob.status == status)
    total = q.count()
    rows = (
        q.order_by(VoiceCallJob.created_at.desc())
        .offset((page - 1) * page_size).limit(page_size).all()
    )
    pagination = {
        "page": page,
        "page_size": page_size,
        "total_items": total,
        "total_pages": math.ceil(total / page_size) if total else 0,
    }
    return standard_response(True, "ok", [_serialize_job(j) for j in rows],
                             pagination=pagination)


@router.get("/jobs/{job_id}")
def get_job(
    job_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    jid = _uuid_or_400(job_id, "job_id")
    job = db.query(VoiceCallJob).filter(VoiceCallJob.id == jid).first()
    if not job:
        raise HTTPException(404, detail="Job not found")
    _get_owned_campaign(db, str(job.campaign_id), current_user, for_write=False)
    logs = [_serialize_log(l) for l in job.logs[-10:]]
    return standard_response(True, "ok", {"job": _serialize_job(job), "logs": logs})


@router.post("/jobs/{job_id}/retry")
def retry_job(
    job_id: str,
    force: bool = Query(True, description="Skip calling-hours guard (default true so retries dial immediately)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Re-queue a job AND immediately dispatch the outbound Twilio call so
    the user receives a call right away (no waiting for a worker pass).
    """
    _require_feature_enabled(db)
    jid = _uuid_or_400(job_id, "job_id")
    job = db.query(VoiceCallJob).filter(VoiceCallJob.id == jid).first()
    if not job:
        raise HTTPException(404, detail="Job not found")
    _get_owned_campaign(db, str(job.campaign_id), current_user)

    if job.status in {"blocked", "opted_out"}:
        raise HTTPException(400, detail=f"Job is {job.status}; cannot retry")

    if job.status in {"queued", "in_progress"}:
        _mark_active_attempt_superseded(db, job, "manual retry requested")
    if job.attempt >= job.max_attempts:
        job.max_attempts = job.attempt + 1
    job.status = "pending"
    job.block_reason = None
    job.next_retry_at = None
    db.commit()
    db.refresh(job)

    # ── Dispatch the Twilio call right now (no worker round-trip). Mirrors
    #    the body of place_call_now so retries are instant for the caller.
    opted_out_phones = _opt_out_set(db, [job.phone_e164])
    verdict = check_can_call(
        job.phone_e164,
        recipient_tz=job.timezone,
        is_opted_out=lambda p: p in opted_out_phones,
        enforce_hours=not force,
    )
    if not verdict.allowed:
        job.status = "blocked" if verdict.code != "outside_hours" else "pending"
        job.block_reason = verdict.reason
        if verdict.code == "outside_hours":
            job.next_retry_at = datetime.utcnow() + timedelta(
                seconds=int(config.VOICE_RETRY_BACKOFF_SECONDS or 60),
            )
        db.commit()
        raise HTTPException(
            409,
            detail={"code": verdict.code, "message": verdict.reason},
        )

    try:
        from voice.greeting_audio import ensure_for_job as _ensure_greeting
        _ensure_greeting(job.id)
    except Exception:  # noqa: BLE001
        pass
    try:
        result = twilio_client.place_call(
            to_phone_e164=job.phone_e164,
            job_id=str(job.id),
        )
    except twilio_client.TwilioConfigError as exc:
        log = VoiceCallLog(
            job_id=job.id, provider="twilio", status="failed",
            error_code="config", error_message=str(exc)[:500],
        )
        db.add(log)
        job.status = "failed"
        db.commit()
        raise HTTPException(503, detail=str(exc))
    except twilio_client.TwilioApiError as exc:
        log = VoiceCallLog(
            job_id=job.id, provider="twilio", status="failed",
            error_code=str(exc.status), error_message=str(exc)[:500],
        )
        db.add(log)
        job.status = "failed"
        job.attempt = (job.attempt or 0) + 1
        job.last_called_at = datetime.utcnow()
        db.commit()
        raise HTTPException(502, detail=f"Twilio rejected the call: {exc}")

    log = VoiceCallLog(
        job_id=job.id,
        provider="twilio",
        provider_call_sid=result.call_sid,
        status=result.status or "queued",
        started_at=datetime.utcnow(),
    )
    db.add(log)
    job.status = twilio_client.status_to_job_status(result.status or "queued")
    job.attempt = (job.attempt or 0) + 1
    job.last_called_at = datetime.utcnow()
    job.block_reason = None
    db.commit()
    db.refresh(job)
    return standard_response(True, "Call dialing now", {
        "job": _serialize_job(job),
        "call_sid": result.call_sid,
    })



# ──────────────────────────────────────────────────────────────────
# Log endpoints
# ──────────────────────────────────────────────────────────────────

@router.get("/logs/{job_id}")
def list_logs(
    job_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    jid = _uuid_or_400(job_id, "job_id")
    job = db.query(VoiceCallJob).filter(VoiceCallJob.id == jid).first()
    if not job:
        raise HTTPException(404, detail="Job not found")
    _get_owned_campaign(db, str(job.campaign_id), current_user, for_write=False)
    rows = (
        db.query(VoiceCallLog)
        .filter(VoiceCallLog.job_id == jid)
        .order_by(VoiceCallLog.started_at.asc().nullsfirst(),
                  VoiceCallLog.created_at.asc())
        .all()
    )
    return standard_response(True, "ok", [_serialize_log(l) for l in rows])


# ──────────────────────────────────────────────────────────────────
# Admin: cross-account visibility for support / debugging
# ──────────────────────────────────────────────────────────────────

@router.get("/admin/jobs")
def admin_list_jobs(
    status: Optional[str] = Query(None),
    has_error: Optional[bool] = Query(None),
    q: Optional[str] = Query(None, description="Search by phone or recipient name"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Admin view: every voice job across every campaign + owner/campaign metadata.

    Used by /admin/voice-calls to triage failed dials, opt-outs, blocked
    numbers, and surface AI/Twilio error messages without bouncing through
    each campaign owner.
    """
    if not _is_admin(current_user):
        raise HTTPException(403, detail="Admin only")

    query = db.query(VoiceCallJob)
    if status:
        query = query.filter(VoiceCallJob.status == status)
    if q:
        like = f"%{q.strip()}%"
        query = query.filter(or_(
            VoiceCallJob.phone_e164.ilike(like),
            VoiceCallJob.recipient_name.ilike(like),
        ))

    total = query.count()
    rows = (
        query.order_by(VoiceCallJob.created_at.desc())
        .offset((page - 1) * page_size).limit(page_size).all()
    )

    job_ids = [r.id for r in rows]
    logs_by_job: dict = {}
    if job_ids:
        logs = (
            db.query(VoiceCallLog)
            .filter(VoiceCallLog.job_id.in_(job_ids))
            .order_by(VoiceCallLog.created_at.desc())
            .all()
        )
        for l in logs:
            logs_by_job.setdefault(l.job_id, []).append(l)

    # Campaign + owner enrichment in one round-trip.
    cids = {r.campaign_id for r in rows}
    campaigns = {c.id: c for c in db.query(VoiceCampaign)
                 .filter(VoiceCampaign.id.in_(cids)).all()} if cids else {}
    owner_ids = {c.owner_id for c in campaigns.values() if c.owner_id}
    owners = {u.id: u for u in db.query(User)
              .filter(User.id.in_(owner_ids)).all()} if owner_ids else {}

    items = []
    for j in rows:
        c = campaigns.get(j.campaign_id)
        owner = owners.get(c.owner_id) if c else None
        job_logs = logs_by_job.get(j.id, [])
        last_err = next((l for l in job_logs if l.error_message), None)
        if has_error is True and not last_err and not j.block_reason:
            continue
        items.append({
            "job": _serialize_job(j),
            "campaign": _serialize_campaign(c) if c else None,
            "owner": {
                "id": str(owner.id),
                "name": getattr(owner, "full_name", None) or getattr(owner, "name", None),
                "phone": getattr(owner, "phone_number", None) or getattr(owner, "phone", None),
                "email": getattr(owner, "email", None),
            } if owner else None,
            "logs": [_serialize_log(l) for l in job_logs[:5]],
            "last_error": {
                "code": last_err.error_code,
                "message": last_err.error_message,
                "at": last_err.created_at.isoformat() if last_err.created_at else None,
            } if last_err else None,
        })

    pagination = {
        "page": page, "page_size": page_size, "total_items": total,
        "total_pages": math.ceil(total / page_size) if total else 0,
    }
    return standard_response(True, "ok", items, pagination=pagination)





# ──────────────────────────────────────────────────────────────────
# Opt-out endpoints
# ──────────────────────────────────────────────────────────────────

@router.get("/opt-outs")
def list_opt_outs(
    q: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(VoiceOptOut)
    if not _is_admin(current_user):
        # Non-admins only see opt-outs they personally added.
        query = query.filter(VoiceOptOut.added_by_user_id == current_user.id)
    if q:
        like = f"%{q.strip()}%"
        query = query.filter(VoiceOptOut.phone_e164.ilike(like))
    total = query.count()
    rows = (
        query.order_by(VoiceOptOut.created_at.desc())
        .offset((page - 1) * page_size).limit(page_size).all()
    )
    pagination = {
        "page": page,
        "page_size": page_size,
        "total_items": total,
        "total_pages": math.ceil(total / page_size) if total else 0,
    }
    return standard_response(True, "ok", [_serialize_opt_out(o) for o in rows],
                             pagination=pagination)


@router.post("/opt-outs")
def add_opt_out(
    payload: OptOutCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    verdict = check_can_call(payload.phone, enforce_hours=False)
    if verdict.code == "invalid_phone":
        raise HTTPException(400, detail=verdict.reason)
    phone_e164 = verdict.phone_e164

    existing = (
        db.query(VoiceOptOut)
        .filter(VoiceOptOut.phone_e164 == phone_e164)
        .first()
    )
    if existing:
        return standard_response(True, "Already opted out", _serialize_opt_out(existing))

    row = VoiceOptOut(
        phone_e164=phone_e164,
        reason=payload.reason,
        source=payload.source or "organiser",
        added_by_user_id=current_user.id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return standard_response(True, "Opted out", _serialize_opt_out(row))


@router.delete("/opt-outs/{phone}")
def delete_opt_out(
    phone: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not _is_admin(current_user):
        raise HTTPException(403, detail="Admin only")
    verdict = check_can_call(phone, enforce_hours=False)
    if verdict.code == "invalid_phone":
        raise HTTPException(400, detail=verdict.reason)
    row = (
        db.query(VoiceOptOut)
        .filter(VoiceOptOut.phone_e164 == verdict.phone_e164)
        .first()
    )
    if not row:
        raise HTTPException(404, detail="Opt-out not found")
    db.delete(row)
    db.commit()
    return standard_response(True, "Opt-out removed")


# ──────────────────────────────────────────────────────────────────
# Twilio dial / webhook / status callback (Phase 4)
# ──────────────────────────────────────────────────────────────────

import logging as _voice_log

_TWILIO_LOG = _voice_log.getLogger("nuru.voice.twilio_route")


def _job_or_404(db: Session, job_id: str) -> VoiceCallJob:
    jid = _uuid_or_400(job_id, "job_id")
    job = db.query(VoiceCallJob).filter(VoiceCallJob.id == jid).first()
    if not job:
        raise HTTPException(404, detail="Job not found")
    return job


def _schedule_retry(job: VoiceCallJob, reason: str) -> None:
    """Schedule next_retry_at if retries remain.

    Pure helper — caller commits the session.
    """
    if (job.attempt or 0) < (job.max_attempts or 1):
        backoff = int(config.VOICE_RETRY_BACKOFF_SECONDS or 60)
        job.next_retry_at = datetime.utcnow() + timedelta(seconds=backoff)
        job.status = "pending"
        job.block_reason = f"retry scheduled: {reason}"
    else:
        job.next_retry_at = None
        # Keep the failure status verbatim (no_answer, busy, failed, ...).


@router.post("/jobs/{job_id}/place-call")
def place_call_now(
    job_id: str,
    force: bool = Query(False, description="Skip the calling-hours guard when true"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Place the outbound Twilio call for a single job immediately.

    Intended for manual one-off testing or for a worker invocation. The
    bulk campaign worker (Celery / cron) is out of scope for this phase.
    """
    _require_feature_enabled(db)
    job = _job_or_404(db, job_id)
    _get_owned_campaign(db, str(job.campaign_id), current_user)

    if job.status in {"in_progress", "queued"}:
        raise HTTPException(400, detail="Call is already active")
    if job.status in {"blocked", "opted_out"}:
        raise HTTPException(400, detail=f"Job is {job.status}; cannot dial")

    # Final dial-time safety check (re-evaluates calling hours + opt-out).
    opted_out_phones = _opt_out_set(db, [job.phone_e164])
    verdict = check_can_call(
        job.phone_e164,
        recipient_tz=job.timezone,
        is_opted_out=lambda p: p in opted_out_phones,
        enforce_hours=not force,
    )
    if not verdict.allowed:
        job.status = "blocked" if verdict.code != "outside_hours" else "pending"
        job.block_reason = verdict.reason
        if verdict.code == "outside_hours":
            job.next_retry_at = datetime.utcnow() + timedelta(
                seconds=int(config.VOICE_RETRY_BACKOFF_SECONDS or 60),
            )
        db.commit()
        # Surface a structured 409 so the client can offer "Call anyway".
        raise HTTPException(
            409,
            detail={"code": verdict.code, "message": verdict.reason},
        )

    try:
        from voice.greeting_audio import ensure_for_job as _ensure_greeting
        _ensure_greeting(job.id)
    except Exception:  # noqa: BLE001
        pass
    try:
        result = twilio_client.place_call(
            to_phone_e164=job.phone_e164,
            job_id=str(job.id),
        )
    except twilio_client.TwilioConfigError as exc:
        raise HTTPException(503, detail=str(exc))
    except twilio_client.TwilioApiError as exc:
        # Record the failure so the dashboard sees it.
        log = VoiceCallLog(
            job_id=job.id,
            provider="twilio",
            status="failed",
            error_code=str(exc.status),
            error_message=str(exc)[:500],
        )
        db.add(log)
        job.status = "failed"
        job.attempt = (job.attempt or 0) + 1
        job.last_called_at = datetime.utcnow()
        db.commit()
        raise HTTPException(502, detail="Twilio rejected the call")

    log = VoiceCallLog(
        job_id=job.id,
        provider="twilio",
        provider_call_sid=result.call_sid,
        status=result.status or "queued",
        started_at=datetime.utcnow(),
    )
    db.add(log)
    job.status = twilio_client.status_to_job_status(result.status or "queued")
    job.attempt = (job.attempt or 0) + 1
    job.last_called_at = datetime.utcnow()
    job.block_reason = None
    db.commit()
    db.refresh(job)
    return standard_response(True, "Call placed", {
        "job": _serialize_job(job),
        "call_sid": result.call_sid,
    })


# Twilio fetches this when the call is answered. Must return TwiML.
@router.api_route("/twilio/webhook", methods=["GET", "POST"])
async def twilio_webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    job_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    """Return TwiML as fast as possible. Heavy DB writes are deferred."""
    import time as _time
    _t0 = _time.perf_counter()

    form = {}
    try:
        form = dict(await request.form())
    except Exception:
        pass

    resolved_job_id = job_id or form.get("job_id")
    call_sid = form.get("CallSid") or request.query_params.get("CallSid")

    from voice.language import resolve_voice_language, to_bcp47

    # Resolve language cheaply. Default Swahili; load job only if id present.
    short_lang = "sw"
    language_source = "env_default"
    job = None
    campaign = None
    event = None
    if resolved_job_id:
        try:
            jid = uuid.UUID(str(resolved_job_id))
            job = db.query(VoiceCallJob).filter(VoiceCallJob.id == jid).first()
            if job is not None and job.campaign_id:
                campaign = db.query(VoiceCampaign).filter(
                    VoiceCampaign.id == job.campaign_id
                ).first()
                if campaign is not None and campaign.event_id:
                    event = db.query(Event).filter(Event.id == campaign.event_id).first()
            short_lang, language_source = resolve_voice_language(
                job=job, campaign=campaign, event=event,
            )
        except (TypeError, ValueError):
            job = None
            short_lang, language_source = resolve_voice_language()
    else:
        short_lang, language_source = resolve_voice_language()
    _TWILIO_LOG.info("Smart RSVP env default language: %s", config.VOICE_DEFAULT_LANGUAGE or "sw")
    _TWILIO_LOG.info("Smart RSVP resolved language source: %s", language_source)
    _TWILIO_LOG.info("Smart RSVP language selected: %s", short_lang)
    language = to_bcp47(short_lang)

    # Defer non-critical DB writes so webhook returns TwiML immediately.
    if job is not None and call_sid:
        _job_id_val = job.id

        def _link_call_sid() -> None:
            from core.database import SessionLocal as _SL
            _db = _SL()
            try:
                _log = (
                    _db.query(VoiceCallLog)
                    .filter(VoiceCallLog.job_id == _job_id_val)
                    .order_by(VoiceCallLog.created_at.desc())
                    .first()
                )
                if _log is not None and not _log.provider_call_sid:
                    _log.provider_call_sid = call_sid
                    if not _log.answered_at:
                        _log.answered_at = datetime.utcnow()
                    _db.commit()
            except Exception:
                _db.rollback()
            finally:
                _db.close()

        background_tasks.add_task(_link_call_sid)

    # Gemini speaks first via the stream — skip Twilio <Say> preroll to
    # avoid overlap and shave ~1s off perceived latency.
    xml = twilio_client.build_twiml(
        job_id=str(resolved_job_id or ""),
        greeting=None,
        language=language,
    )
    _elapsed_ms = int((_time.perf_counter() - _t0) * 1000)
    _TWILIO_LOG.info(
        "Twilio webhook job=%s call_sid=%s twiml_ms=%d has_stream=%s",
        resolved_job_id, call_sid, _elapsed_ms, "<Stream" in xml,
    )
    return Response(content=xml, media_type="application/xml")


# Twilio posts here on every status transition.
@router.api_route("/twilio/status", methods=["POST"])
async def twilio_status_callback(
    request: Request,
    job_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    try:
        form = dict(await request.form())
    except Exception:
        form = {}

    call_sid = form.get("CallSid")
    call_status = (form.get("CallStatus") or "").lower()
    duration = form.get("CallDuration") or form.get("Duration")
    recording_url = form.get("RecordingUrl")
    error_code = form.get("ErrorCode")
    error_msg = form.get("ErrorMessage")

    if not call_sid:
        return Response(status_code=204)

    log = (
        db.query(VoiceCallLog)
        .filter(VoiceCallLog.provider_call_sid == call_sid)
        .first()
    )

    # If we don't have a log yet (status fired before webhook), create one
    # via job_id query param so we never lose the event.
    if log is None and job_id:
        try:
            jid = uuid.UUID(str(job_id))
            log = VoiceCallLog(
                job_id=jid,
                provider="twilio",
                provider_call_sid=call_sid,
                status=call_status or "queued",
                started_at=datetime.utcnow(),
            )
            db.add(log)
            db.flush()
        except (TypeError, ValueError):
            log = None

    if log is None:
        _TWILIO_LOG.warning("Twilio status for unknown CallSid=%s", call_sid)
        return Response(status_code=204)

    log.status = call_status or log.status
    if duration:
        try:
            log.duration_seconds = int(duration)
        except (TypeError, ValueError):
            pass
    if recording_url:
        log.recording_url = recording_url
    if error_code:
        log.error_code = str(error_code)
    if error_msg:
        log.error_message = str(error_msg)[:500]

    if call_status == "in-progress" and not log.answered_at:
        log.answered_at = datetime.utcnow()
    if twilio_client.is_terminal_status(call_status):
        log.ended_at = datetime.utcnow()

    job = db.query(VoiceCallJob).filter(VoiceCallJob.id == log.job_id).first()
    if job is not None:
        new_job_status = twilio_client.status_to_job_status(call_status)
        job.status = new_job_status
        if call_status == "in-progress":
            job.last_called_at = datetime.utcnow()
        if call_status in {"busy", "no-answer", "failed"}:
            _schedule_retry(job, reason=call_status)
        elif call_status == "completed":
            job.next_retry_at = None
            job.block_reason = None
            if log.ai_outcome:
                job.ai_outcome = log.ai_outcome
            if log.ai_confidence is not None:
                job.ai_confidence = log.ai_confidence
            if log.summary:
                job.summary = log.summary

    db.commit()
    return Response(status_code=204)


@router.get("/twilio/health")
def twilio_health(current_user: User = Depends(get_current_user)):
    """Lightweight readiness check (no outbound call)."""
    missing: list[str] = []
    if not (config.TWILIO_ACCOUNT_SID or "").strip():
        missing.append("TWILIO_ACCOUNT_SID")
    if not (config.TWILIO_AUTH_TOKEN or "").strip():
        missing.append("TWILIO_AUTH_TOKEN")
    if not (config.TWILIO_VOICE_FROM_NUMBER or "").strip():
        missing.append("TWILIO_VOICE_FROM_NUMBER")
    return standard_response(True, "ok", {
        "ready": not missing,
        "missing": missing,
        "webhook_url": config.TWILIO_VOICE_WEBHOOK_URL,
        "status_callback_url": config.TWILIO_STATUS_CALLBACK_URL,
        "stream_url": config.VOICE_AI_STREAM_URL,
        "record_calls": bool(config.VOICE_RECORD_CALLS),
    })


# ──────────────────────────────────────────────────────────────────
# Phase 5 — Realtime audio WebSocket (Twilio Media Streams ↔ AI)
# ──────────────────────────────────────────────────────────────────

@router.websocket("/stream")
async def voice_stream(websocket: WebSocket):
    """Twilio Media Streams endpoint.

    Twilio connects here after <Connect><Stream> in the TwiML. We accept
    the socket immediately (Twilio's sub-protocol is plain JSON over text
    frames), then hand off to ``voice.realtime.handle_twilio_stream``
    which owns audio transcoding, the AI bridge, time limits, and
    transcript persistence.
    """
    await websocket.accept()
    await handle_twilio_stream(websocket)
