"""User-facing job progress endpoint.

Clients that received a ``job_id`` from any "instant accept, background
work" endpoint poll here to learn the outcome.

    GET /jobs/{job_id}     — owner or admin only
    GET /jobs              — current user's recent jobs (last 50)

Response shape is deliberately small and stable across task types so the
mobile / web clients can render a single progress UI for everything.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from core.database import get_db
from core.jobs import get_job, list_jobs_for_user
from models import User
from utils.auth import get_current_user
from utils.helpers import standard_response

router = APIRouter(prefix="/jobs", tags=["jobs"])


def _serialize(row: dict) -> dict:
    return {
        "id": str(row["id"]),
        "task_name": row.get("task_name"),
        "status": row.get("status"),
        "progress": row.get("progress") or 0,
        "total": row.get("total"),
        "message": row.get("message"),
        "result": row.get("result"),
        "error": row.get("error"),
        "attempts": row.get("attempts"),
        "max_attempts": row.get("max_attempts"),
        "queued_at": row.get("queued_at").isoformat() if row.get("queued_at") else None,
        "started_at": row.get("started_at").isoformat() if row.get("started_at") else None,
        "finished_at": row.get("finished_at").isoformat() if row.get("finished_at") else None,
        "updated_at": row.get("updated_at").isoformat() if row.get("updated_at") else None,
    }


@router.get("/{job_id}")
def get_job_status(
    job_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    job = get_job(db, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    owner = job.get("user_id")
    if owner is not None and str(owner) != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not allowed")
    return standard_response(success=True, data=_serialize(job))


@router.get("")
def list_my_jobs(
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    limit = max(1, min(limit, 200))
    rows = list_jobs_for_user(db, str(current_user.id), limit=limit)
    return standard_response(success=True, data=[_serialize(r) for r in rows])
