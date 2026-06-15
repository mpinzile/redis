"""ORM models for the Nuru Voice Assistant (Phase 2 of nuru_voice.md).

Four tables, all isolated from existing call/messaging models so they do
not interfere with the 1:1 LiveKit calls in ``models/calls.py``:

* ``voice_campaigns``   — one row per organiser-initiated batch.
* ``voice_call_jobs``   — one row per recipient inside a campaign.
* ``voice_call_logs``   — one row per provider call attempt (Twilio CallSid).
* ``voice_opt_outs``    — global do-not-call list, keyed by E.164.

Status / purpose / outcome fields use plain ``Text`` (not Postgres enums)
so we can extend the vocabulary later without an enum migration.
"""
from __future__ import annotations

from sqlalchemy import (
    Boolean, Column, Integer, Text, DateTime, ForeignKey, Index, UniqueConstraint, Numeric,
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from core.base import Base


class VoiceCampaign(Base):
    """One organiser-initiated batch of voice calls."""
    __tablename__ = "voice_campaigns"

    id = Column(UUID(as_uuid=True), primary_key=True,
                server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True),
                      ForeignKey("events.id", ondelete="CASCADE"), nullable=True)
    owner_id = Column(UUID(as_uuid=True),
                      ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    # 'rsvp' | 'contribution' | 'verification' | 'committee' | 'vendor' | 'feedback'
    purpose = Column(Text, nullable=False, server_default="rsvp")
    language = Column(Text, nullable=False, server_default="sw")
    # 'draft' | 'queued' | 'running' | 'paused' | 'completed' | 'cancelled'
    status = Column(Text, nullable=False, server_default="draft")

    title = Column(Text, nullable=True)
    notes = Column(Text, nullable=True)
    estimated_cost_usd = Column(Numeric(10, 4), nullable=True)

    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, nullable=False, server_default=func.now())
    updated_at = Column(DateTime, nullable=False, server_default=func.now(),
                        onupdate=func.now())

    __table_args__ = (
        Index("idx_voice_campaigns_event", "event_id"),
        Index("idx_voice_campaigns_owner_status", "owner_id", "status"),
    )

    jobs = relationship(
        "VoiceCallJob", back_populates="campaign",
        cascade="all, delete-orphan", lazy="selectin",
    )


class VoiceCallJob(Base):
    """One recipient inside a campaign. May trigger multiple call attempts."""
    __tablename__ = "voice_call_jobs"

    id = Column(UUID(as_uuid=True), primary_key=True,
                server_default=func.gen_random_uuid())
    campaign_id = Column(UUID(as_uuid=True),
                         ForeignKey("voice_campaigns.id", ondelete="CASCADE"),
                         nullable=False)

    # Recipient context. Free-form so we can target guests, contributors,
    # committee members, vendors or anyone else with a phone number.
    recipient_type = Column(Text, nullable=False, server_default="guest")
    recipient_ref_id = Column(UUID(as_uuid=True), nullable=True)
    recipient_name = Column(Text, nullable=False, server_default="")
    phone_e164 = Column(Text, nullable=False)
    country = Column(Text, nullable=True)
    timezone = Column(Text, nullable=True)
    language = Column(Text, nullable=True)

    # 'pending' | 'queued' | 'in_progress' | 'completed' | 'failed' |
    # 'no_answer' | 'busy' | 'opted_out' | 'blocked' | 'cancelled'
    status = Column(Text, nullable=False, server_default="pending")
    block_reason = Column(Text, nullable=True)

    attempt = Column(Integer, nullable=False, server_default="0")
    max_attempts = Column(Integer, nullable=False, server_default="1")

    scheduled_at = Column(DateTime, nullable=True)
    next_retry_at = Column(DateTime, nullable=True)
    last_called_at = Column(DateTime, nullable=True)

    # Latest AI outcome — duplicated from voice_call_logs for fast list views.
    ai_outcome = Column(Text, nullable=True)
    ai_confidence = Column(Numeric(4, 3), nullable=True)
    summary = Column(Text, nullable=True)

    extra = Column(JSONB, nullable=True)

    created_at = Column(DateTime, nullable=False, server_default=func.now())
    updated_at = Column(DateTime, nullable=False, server_default=func.now(),
                        onupdate=func.now())

    __table_args__ = (
        Index("idx_voice_call_jobs_campaign_status", "campaign_id", "status"),
        Index("idx_voice_call_jobs_phone", "phone_e164"),
        Index("idx_voice_call_jobs_next_retry", "next_retry_at"),
    )

    campaign = relationship("VoiceCampaign", back_populates="jobs")
    logs = relationship(
        "VoiceCallLog", back_populates="job",
        cascade="all, delete-orphan", lazy="selectin",
        order_by="VoiceCallLog.started_at",
    )


class VoiceCallLog(Base):
    """One row per provider call attempt (Twilio CallSid or equivalent)."""
    __tablename__ = "voice_call_logs"

    id = Column(UUID(as_uuid=True), primary_key=True,
                server_default=func.gen_random_uuid())
    job_id = Column(UUID(as_uuid=True),
                    ForeignKey("voice_call_jobs.id", ondelete="CASCADE"),
                    nullable=False)

    provider = Column(Text, nullable=False, server_default="twilio")
    provider_call_sid = Column(Text, nullable=True, unique=True)

    # Twilio lifecycle: queued | ringing | in-progress | completed | busy |
    # failed | no-answer | canceled. We store the raw provider value.
    status = Column(Text, nullable=False, server_default="queued")
    end_reason = Column(Text, nullable=True)

    started_at = Column(DateTime, nullable=True)
    answered_at = Column(DateTime, nullable=True)
    ended_at = Column(DateTime, nullable=True)
    duration_seconds = Column(Integer, nullable=False, server_default="0")

    cost_estimate_usd = Column(Numeric(10, 4), nullable=True)
    recording_url = Column(Text, nullable=True)

    transcript = Column(Text, nullable=True)
    summary = Column(Text, nullable=True)
    ai_outcome = Column(Text, nullable=True)
    ai_confidence = Column(Numeric(4, 3), nullable=True)
    ai_tool_calls = Column(JSONB, nullable=True)

    # Phase 11 — natural conversation quality (all optional)
    conversation_quality = Column(Text, nullable=True)
    detected_mood = Column(Text, nullable=True)
    noise_detected = Column(Boolean, nullable=True)
    interruption_count = Column(Integer, nullable=False, server_default="0")
    silence_count = Column(Integer, nullable=False, server_default="0")
    clarification_count = Column(Integer, nullable=False, server_default="0")
    final_confidence = Column(Numeric(4, 3), nullable=True)
    human_follow_up_reason = Column(Text, nullable=True)

    error_code = Column(Text, nullable=True)
    error_message = Column(Text, nullable=True)

    created_at = Column(DateTime, nullable=False, server_default=func.now())

    __table_args__ = (
        Index("idx_voice_call_logs_job", "job_id"),
        Index("idx_voice_call_logs_provider_sid", "provider", "provider_call_sid"),
    )

    job = relationship("VoiceCallJob", back_populates="logs")


class VoiceOptOut(Base):
    """Global do-not-call list. One row per E.164 number."""
    __tablename__ = "voice_opt_outs"

    id = Column(UUID(as_uuid=True), primary_key=True,
                server_default=func.gen_random_uuid())
    phone_e164 = Column(Text, nullable=False)
    reason = Column(Text, nullable=True)
    # Who triggered the opt-out: 'recipient' | 'organiser' | 'admin' | 'system'.
    source = Column(Text, nullable=False, server_default="recipient")
    added_by_user_id = Column(UUID(as_uuid=True),
                              ForeignKey("users.id", ondelete="SET NULL"),
                              nullable=True)

    created_at = Column(DateTime, nullable=False, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("phone_e164", name="uq_voice_opt_outs_phone"),
    )
