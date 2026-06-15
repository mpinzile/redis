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

from fastapi import APIRouter, Depends, HTTPException, Query, Body, Request, Form, Response, WebSocket
from pydantic import BaseModel, Field, validator
from sqlalchemy import func as sa_func, and_, or_
from sqlalchemy.orm import Session

from core.database import get_db
from core import config
from models import (
    VoiceCampaign, VoiceCallJob, VoiceCallLog, VoiceOptOut,
    Event, User,
)
from utils.auth import get_current_user
from utils.helpers import standard_response
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
                   db: Session = Depends(get_db),
                   current_user: User = Depends(get_current_user)):
    return _set_campaign_status(
        db, campaign_id, current_user, "queued", "Campaign queued",
        allowed_from={"draft", "paused"},
    )


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

        job = VoiceCallJob(
            campaign_id=c.id,
            recipient_type=recipient.recipient_type or "guest",
            recipient_ref_id=ref_uuid,
            recipient_name=(recipient.recipient_name or "").strip()[:200],
            phone_e164=verdict.phone_e164 or recipient.phone,
            country=verdict.country,
            timezone=verdict.timezone or recipient.timezone,
            language=recipient.language or c.language,
            scheduled_at=recipient.scheduled_at,
            max_attempts=recipient.max_attempts or max_attempts_default,
            extra=recipient.extra,
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
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    jid = _uuid_or_400(job_id, "job_id")
    job = db.query(VoiceCallJob).filter(VoiceCallJob.id == jid).first()
    if not job:
        raise HTTPException(404, detail="Job not found")
    _get_owned_campaign(db, str(job.campaign_id), current_user)

    if job.status in {"queued", "in_progress"}:
        raise HTTPException(400, detail="Job is already active")
    if job.status == "blocked":
        raise HTTPException(400, detail="Blocked jobs cannot be retried")

    # Bump max_attempts so the retry actually goes out.
    if job.attempt >= job.max_attempts:
        job.max_attempts = job.attempt + 1
    job.status = "pending"
    job.block_reason = None
    job.next_retry_at = datetime.utcnow() + timedelta(
        seconds=int(config.VOICE_RETRY_BACKOFF_SECONDS or 60),
    )
    db.commit()
    db.refresh(job)
    return standard_response(True, "Job re-queued", _serialize_job(job))


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
    """Bump attempt counter and schedule next_retry_at if retries remain.

    Pure helper — caller commits the session.
    """
    job.attempt = (job.attempt or 0) + 1
    if job.attempt < (job.max_attempts or 1):
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
    job_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    # Twilio posts form data; fall back to query string if missing.
    form = {}
    try:
        form = dict(await request.form())
    except Exception:
        pass

    resolved_job_id = job_id or form.get("job_id")
    call_sid = form.get("CallSid") or request.query_params.get("CallSid")

    greeting = None
    language = "sw-KE"
    job = None
    if resolved_job_id:
        try:
            jid = uuid.UUID(str(resolved_job_id))
            job = db.query(VoiceCallJob).filter(VoiceCallJob.id == jid).first()
        except (TypeError, ValueError):
            job = None

    if job is not None:
        # Link the CallSid to the most recent log entry for this job.
        if call_sid:
            log = (
                db.query(VoiceCallLog)
                .filter(VoiceCallLog.job_id == job.id)
                .order_by(VoiceCallLog.created_at.desc())
                .first()
            )
            if log is not None and not log.provider_call_sid:
                log.provider_call_sid = call_sid
                if not log.answered_at:
                    log.answered_at = datetime.utcnow()
                db.commit()
        # Language preference: per-job > campaign default.
        lang = (job.language or "").lower()
        if lang.startswith("en"):
            language = "en-US"
        elif lang.startswith("sw"):
            language = "sw-KE"
        # Lightweight greeting (full agent dialogue handled by Gemini Live).
        greeting = (
            "Habari. Hii ni Msaidizi wa Sauti wa Nuru. "
            f"Tunakupigia kuhusu mwaliko wako. Tafadhali tuambie kama utahudhuria."
            if language == "sw-KE"
            else "Hello, this is the Nuru Voice Assistant. "
                 "We are calling about your invitation. Please tell us if you will attend."
        )

    xml = twilio_client.build_twiml(
        job_id=str(resolved_job_id or ""),
        greeting=greeting,
        language=language,
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
