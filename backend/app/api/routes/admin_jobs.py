"""Admin endpoints for reliability infra.

- GET    /admin/jobs                      — list recent jobs (filterable)
- POST   /admin/jobs/{id}/retry           — re-run the task for a job row
- POST   /admin/jobs/{id}/cancel          — mark a stale job cancelled
- GET    /admin/dead-letter-jobs          — list unresolved DLQ entries
- POST   /admin/dead-letter-jobs/{id}/requeue   — re-enqueue
- POST   /admin/dead-letter-jobs/{id}/resolve   — mark handled (no requeue)
- POST   /admin/jobs/force-sync           — generic Redis→Postgres reconcile
                                            hook; per-domain handlers register
                                            themselves in FORCE_SYNC_HANDLERS.
"""
from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from core.database import get_db
from core.jobs import requeue_dead_letter
from core.celery_app import celery_app
from models.admin import AdminUser
from utils.helpers import standard_response
from .admin import require_admin

log = logging.getLogger("admin.jobs")

router = APIRouter(prefix="/admin", tags=["admin-jobs"])

# Domain modules register handlers here at import-time:
#   FORCE_SYNC_HANDLERS["checkin"] = lambda event_id: ...
FORCE_SYNC_HANDLERS: dict[str, callable] = {}


# ── jobs ─────────────────────────────────────────────────────────────
@router.get("/jobs")
def list_jobs(
    status: Optional[str] = Query(default=None),
    task_name: Optional[str] = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin),
):
    clauses = ["1=1"]
    params: dict = {"limit": limit}
    if status:
        clauses.append("status = :status")
        params["status"] = status
    if task_name:
        clauses.append("task_name = :task_name")
        params["task_name"] = task_name
    rows = db.execute(
        text(
            f"""
            SELECT id, task_name, user_id, event_id, status, progress, total,
                   attempts, max_attempts, error, queued_at, started_at,
                   finished_at, updated_at
              FROM job_status
             WHERE {' AND '.join(clauses)}
             ORDER BY queued_at DESC
             LIMIT :limit
            """
        ),
        params,
    ).mappings().all()
    return standard_response(success=True, data=[{**r, "id": str(r["id"])} for r in rows])


@router.post("/jobs/{job_id}/retry")
def retry_job(
    job_id: str,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin),
):
    row = db.execute(
        text("SELECT id, task_name, status FROM job_status WHERE id = :id"),
        {"id": job_id},
    ).mappings().first()
    if not row:
        raise HTTPException(status_code=404, detail="Job not found")
    task = celery_app.tasks.get(row["task_name"])
    if not task:
        raise HTTPException(status_code=400, detail=f"Unknown task: {row['task_name']}")
    db.execute(
        text(
            """
            UPDATE job_status
               SET status = 'queued', error = NULL, finished_at = NULL,
                   progress = 0, message = 'manual retry', updated_at = NOW()
             WHERE id = :id
            """
        ),
        {"id": job_id},
    )
    db.commit()
    async_result = task.apply_async(args=[str(row["id"])])
    return standard_response(success=True, data={"job_id": str(row["id"]), "celery_task_id": async_result.id})


@router.post("/jobs/{job_id}/cancel")
def cancel_job(
    job_id: str,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin),
):
    db.execute(
        text(
            """
            UPDATE job_status
               SET status = 'cancelled', finished_at = NOW(), updated_at = NOW()
             WHERE id = :id AND status IN ('queued','retrying','running')
            """
        ),
        {"id": job_id},
    )
    db.commit()
    return standard_response(success=True, data={"job_id": job_id, "status": "cancelled"})


# ── dead-letter queue ────────────────────────────────────────────────
@router.get("/dead-letter-jobs")
def list_dlq(
    task_name: Optional[str] = Query(default=None),
    include_resolved: bool = Query(default=False),
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin),
):
    clauses = ["1=1"]
    params: dict = {"limit": limit}
    if not include_resolved:
        clauses.append("resolved_at IS NULL AND requeued_at IS NULL")
    if task_name:
        clauses.append("task_name = :task_name")
        params["task_name"] = task_name
    rows = db.execute(
        text(
            f"""
            SELECT id, job_id, task_name, payload, error, attempts,
                   first_failed_at, last_failed_at, requeued_at, resolved_at, notes
              FROM dead_letter_jobs
             WHERE {' AND '.join(clauses)}
             ORDER BY last_failed_at DESC
             LIMIT :limit
            """
        ),
        params,
    ).mappings().all()
    return standard_response(
        success=True,
        data=[{**r, "id": str(r["id"]), "job_id": str(r["job_id"]) if r["job_id"] else None} for r in rows],
    )


@router.post("/dead-letter-jobs/{dlq_id}/requeue")
def requeue(
    dlq_id: str,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin),
):
    celery_task_id = requeue_dead_letter(db, dlq_id, by_admin_id=str(admin.id))
    if not celery_task_id:
        raise HTTPException(status_code=400, detail="DLQ entry missing, already requeued, or task unknown")
    return standard_response(success=True, data={"dlq_id": dlq_id, "celery_task_id": celery_task_id})


@router.post("/dead-letter-jobs/{dlq_id}/resolve")
def resolve(
    dlq_id: str,
    body: dict = Body(default={}),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_admin),
):
    db.execute(
        text(
            """
            UPDATE dead_letter_jobs
               SET resolved_at = NOW(), resolved_by = :by, notes = :notes
             WHERE id = :id AND resolved_at IS NULL
            """
        ),
        {"by": str(admin.id), "notes": (body or {}).get("notes"), "id": dlq_id},
    )
    db.commit()
    return standard_response(success=True, data={"dlq_id": dlq_id, "status": "resolved"})


# ── generic force-sync hook ──────────────────────────────────────────
@router.post("/jobs/force-sync")
def force_sync(
    body: dict = Body(...),
    admin: AdminUser = Depends(require_admin),
):
    """Trigger a domain-specific Redis→Postgres reconcile.

    Body: ``{ "domain": "checkin", "args": { "event_id": "..." } }``.
    Domain modules register themselves into ``FORCE_SYNC_HANDLERS`` at
    import time; we keep the registry small and explicit rather than
    auto-discovering.
    """
    domain = (body or {}).get("domain")
    args = (body or {}).get("args") or {}
    if not domain or domain not in FORCE_SYNC_HANDLERS:
        raise HTTPException(status_code=400, detail=f"Unknown force-sync domain: {domain}")
    try:
        result = FORCE_SYNC_HANDLERS[domain](**args)
    except TypeError as exc:
        raise HTTPException(status_code=400, detail=f"Bad args for {domain}: {exc}")
    return standard_response(success=True, data={"domain": domain, "result": result})
