"""Reliability infra models (Plan 2).

- ``JobStatus``        — one row per background job. Workers update it as
                         they progress; clients poll ``GET /jobs/{id}``.
- ``IdempotencyKey``   — guards POST replays. The first request stores the
                         response; replays read it back without touching
                         the underlying handler.
- ``DeadLetterJob``    — terminal failures. Admins can inspect/requeue.

Mirrors the SQL in alembic revision ``cafe27054700``.
"""
from __future__ import annotations

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.sql import func

from core.base import Base


class JobStatus(Base):
    __tablename__ = "job_status"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    task_name = Column(Text, nullable=False)
    celery_task_id = Column(Text, nullable=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    event_id = Column(UUID(as_uuid=True), nullable=True)
    scope = Column(Text, nullable=True)

    # queued | running | succeeded | failed | retrying | dead_lettered | cancelled
    status = Column(String(32), nullable=False, default="queued")
    progress = Column(Integer, nullable=False, default=0)
    total = Column(Integer, nullable=True)
    message = Column(Text, nullable=True)
    result = Column(JSONB, nullable=True)
    error = Column(Text, nullable=True)

    attempts = Column(Integer, nullable=False, default=0)
    max_attempts = Column(Integer, nullable=False, default=5)

    queued_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    started_at = Column(DateTime(timezone=True), nullable=True)
    finished_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class IdempotencyKey(Base):
    __tablename__ = "idempotency_keys"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    scope = Column(Text, nullable=False)
    key = Column(Text, nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=True)
    request_hash = Column(Text, nullable=True)

    # in_progress | completed | failed
    status = Column(String(32), nullable=False, default="in_progress")
    response_code = Column(Integer, nullable=True)
    response_body = Column(JSONB, nullable=True)
    job_id = Column(UUID(as_uuid=True), ForeignKey("job_status.id", ondelete="SET NULL"), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)


class DeadLetterJob(Base):
    __tablename__ = "dead_letter_jobs"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    job_id = Column(UUID(as_uuid=True), ForeignKey("job_status.id", ondelete="SET NULL"), nullable=True)
    task_name = Column(Text, nullable=False)
    payload = Column(JSONB, nullable=False, default=dict)
    error = Column(Text, nullable=True)
    traceback = Column(Text, nullable=True)
    attempts = Column(Integer, nullable=False, default=0)
    first_failed_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    last_failed_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    requeued_at = Column(DateTime(timezone=True), nullable=True)
    requeued_by = Column(UUID(as_uuid=True), nullable=True)
    resolved_at = Column(DateTime(timezone=True), nullable=True)
    resolved_by = Column(UUID(as_uuid=True), nullable=True)
    notes = Column(Text, nullable=True)
