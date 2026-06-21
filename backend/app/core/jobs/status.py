"""``job_status`` CRUD helpers.

All writes are short, single-row UPDATEs so they're safe to call from
inside a Celery task's hot loop or from a FastAPI request handler that
wants to record the enqueue itself.

Callers manage their own ``Session``. We do NOT open a session here so the
caller controls transaction boundaries (e.g. the request handler may want
the job row to commit even if the rest of the unit of work rolls back).
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime
from typing import Any, Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

log = logging.getLogger("jobs.status")


def create_job(
    db: Session,
    *,
    task_name: str,
    user_id: Optional[str] = None,
    event_id: Optional[str] = None,
    scope: Optional[str] = None,
    total: Optional[int] = None,
    max_attempts: int = 5,
    celery_task_id: Optional[str] = None,
) -> str:
    """Insert a queued row and return its ``id`` as a string."""
    row = db.execute(
        text(
            """
            INSERT INTO job_status
                (task_name, user_id, event_id, scope, total, max_attempts, celery_task_id, status)
            VALUES
                (:task_name, :user_id, :event_id, :scope, :total, :max_attempts, :celery_task_id, 'queued')
            RETURNING id
            """
        ),
        {
            "task_name": task_name,
            "user_id": user_id,
            "event_id": event_id,
            "scope": scope,
            "total": total,
            "max_attempts": max_attempts,
            "celery_task_id": celery_task_id,
        },
    ).first()
    return str(row[0])


def _update(db: Session, job_id: str, **fields: Any) -> None:
    if not fields:
        return
    sets = ", ".join(f"{k} = :{k}" for k in fields)
    fields["job_id"] = job_id
    db.execute(text(f"UPDATE job_status SET {sets}, updated_at = NOW() WHERE id = :job_id"), fields)


def mark_running(db: Session, job_id: str, *, celery_task_id: Optional[str] = None) -> None:
    fields: dict = {"status": "running", "started_at": datetime.utcnow()}
    if celery_task_id:
        fields["celery_task_id"] = celery_task_id
    _update(db, job_id, **fields)


def mark_succeeded(db: Session, job_id: str, *, result: Optional[dict] = None, message: Optional[str] = None) -> None:
    import json
    _update(
        db,
        job_id,
        status="succeeded",
        finished_at=datetime.utcnow(),
        progress=100,
        result=(json.dumps(result) if result is not None else None),
        message=message,
        error=None,
    )


def mark_failed(db: Session, job_id: str, *, error: str, message: Optional[str] = None) -> None:
    _update(
        db,
        job_id,
        status="failed",
        finished_at=datetime.utcnow(),
        error=error[:4000],
        message=message,
    )


def mark_retrying(db: Session, job_id: str, *, error: str, attempts: int) -> None:
    _update(db, job_id, status="retrying", error=error[:4000], attempts=attempts)


def set_progress(db: Session, job_id: str, *, progress: int, total: Optional[int] = None, message: Optional[str] = None) -> None:
    fields: dict = {"progress": max(0, min(progress, 100))}
    if total is not None:
        fields["total"] = total
    if message is not None:
        fields["message"] = message
    _update(db, job_id, **fields)


def get_job(db: Session, job_id: str) -> Optional[dict]:
    try:
        uuid.UUID(job_id)
    except (ValueError, TypeError):
        return None
    row = db.execute(
        text(
            """
            SELECT id, task_name, user_id, event_id, scope, status, progress, total,
                   message, result, error, attempts, max_attempts,
                   queued_at, started_at, finished_at, updated_at
              FROM job_status
             WHERE id = :id
            """
        ),
        {"id": job_id},
    ).mappings().first()
    return dict(row) if row else None


def list_jobs_for_user(db: Session, user_id: str, *, limit: int = 50) -> list[dict]:
    rows = db.execute(
        text(
            """
            SELECT id, task_name, status, progress, total, message, error,
                   queued_at, started_at, finished_at, updated_at
              FROM job_status
             WHERE user_id = :uid
             ORDER BY queued_at DESC
             LIMIT :limit
            """
        ),
        {"uid": user_id, "limit": limit},
    ).mappings().all()
    return [dict(r) for r in rows]
