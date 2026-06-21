"""``ReliableTask`` — Celery base with status writes, retry, and DLQ.

Workers subclass it (or use ``@celery_app.task(base=ReliableTask, ...)``)
and call ``self.bind_job(job_id)`` once they begin work. The base then
handles:

- transitioning ``job_status`` to ``running`` on start
- exponential-backoff retry up to ``max_attempts`` (default 5)
- writing ``succeeded`` / ``failed`` / ``retrying`` states
- on terminal failure, inserting a ``dead_letter_jobs`` row so the work
  is visible to admins and can be requeued.

Example:

    @celery_app.task(base=ReliableTask, bind=True, max_retries=5)
    def send_invitation(self, job_id, invitation_id):
        self.bind_job(job_id)
        try:
            do_work(invitation_id)
            self.job_succeeded(result={"invitation_id": invitation_id})
        except Exception as exc:
            self.job_failed_or_retry(exc, payload={"invitation_id": invitation_id})

The base never opens nested transactions; each helper commits a tiny
single-row write so a long task body doesn't keep a DB connection open.
"""
from __future__ import annotations

import json
import logging
import traceback as tb_mod
from typing import Any, Optional

from celery import Task

from core.database import SessionLocal
from . import status as job_status

log = logging.getLogger("jobs.base_task")


class ReliableTask(Task):
    autoretry_for = (Exception,)
    retry_backoff = True            # 1s, 2s, 4s, 8s, ...
    retry_backoff_max = 300         # cap at 5 min
    retry_jitter = True
    max_retries = 5
    acks_late = True

    def __init__(self) -> None:
        super().__init__()
        self._job_id: Optional[str] = None

    # ── job lifecycle ─────────────────────────────────────────────────
    def bind_job(self, job_id: Optional[str]) -> None:
        self._job_id = job_id
        if not job_id:
            return
        db = SessionLocal()
        try:
            job_status.mark_running(db, job_id, celery_task_id=self.request.id)
            db.commit()
        except Exception:
            db.rollback()
            log.exception("ReliableTask.bind_job failed job_id=%s", job_id)
        finally:
            db.close()

    def set_progress(self, *, progress: int, total: Optional[int] = None, message: Optional[str] = None) -> None:
        if not self._job_id:
            return
        db = SessionLocal()
        try:
            job_status.set_progress(db, self._job_id, progress=progress, total=total, message=message)
            db.commit()
        except Exception:
            db.rollback()
        finally:
            db.close()

    def job_succeeded(self, *, result: Optional[dict] = None, message: Optional[str] = None) -> None:
        if not self._job_id:
            return
        db = SessionLocal()
        try:
            job_status.mark_succeeded(db, self._job_id, result=result, message=message)
            db.commit()
        except Exception:
            db.rollback()
            log.exception("ReliableTask.job_succeeded failed job_id=%s", self._job_id)
        finally:
            db.close()

    def job_failed_or_retry(self, exc: BaseException, *, payload: Optional[dict] = None) -> None:
        """Mark retrying + raise self.retry(); on final attempt write DLQ + fail.

        Call this from the except-block of your task. It will re-raise via
        ``self.retry`` until retries are exhausted, at which point it writes
        the ``job_status.failed`` row and a ``dead_letter_jobs`` row.
        """
        attempts = (self.request.retries or 0) + 1
        is_final = attempts >= (self.max_retries or 0) + 1
        err_text = f"{type(exc).__name__}: {exc}"
        tb_text = "".join(tb_mod.format_exception(type(exc), exc, exc.__traceback__))[-8000:]

        if self._job_id and not is_final:
            db = SessionLocal()
            try:
                job_status.mark_retrying(db, self._job_id, error=err_text, attempts=attempts)
                db.commit()
            except Exception:
                db.rollback()
            finally:
                db.close()

        if is_final:
            self._write_terminal_failure(err_text, tb_text, attempts, payload or {})
            return  # do NOT retry past the budget
        raise self.retry(exc=exc)

    def _write_terminal_failure(self, error: str, traceback: str, attempts: int, payload: dict) -> None:
        from sqlalchemy import text
        db = SessionLocal()
        try:
            if self._job_id:
                job_status.mark_failed(db, self._job_id, error=error, message="dead-lettered")
                db.execute(
                    text(
                        """
                        UPDATE job_status SET status = 'dead_lettered', attempts = :a
                         WHERE id = :id
                        """
                    ),
                    {"a": attempts, "id": self._job_id},
                )
            db.execute(
                text(
                    """
                    INSERT INTO dead_letter_jobs
                        (job_id, task_name, payload, error, traceback, attempts)
                    VALUES
                        (:job_id, :task_name, CAST(:payload AS jsonb), :error, :tb, :attempts)
                    """
                ),
                {
                    "job_id": self._job_id,
                    "task_name": self.name,
                    "payload": json.dumps(payload, default=str),
                    "error": error[:4000],
                    "tb": traceback,
                    "attempts": attempts,
                },
            )
            db.commit()
            log.error("DLQ task=%s job_id=%s attempts=%d err=%s", self.name, self._job_id, attempts, error)
        except Exception:
            db.rollback()
            log.exception("Failed to write DLQ entry for task=%s", self.name)
        finally:
            db.close()


def requeue_dead_letter(db, dlq_id: str, *, by_admin_id: Optional[str] = None) -> Optional[str]:
    """Re-enqueue a DLQ row by sending its payload back to its original task.

    Returns the new Celery task id, or None if the entry / task is missing.
    The DLQ row is marked ``requeued_at = NOW()`` so it's no longer pending.
    """
    from sqlalchemy import text
    from core.celery_app import celery_app

    row = db.execute(
        text(
            """
            SELECT id, job_id, task_name, payload
              FROM dead_letter_jobs
             WHERE id = :id AND requeued_at IS NULL AND resolved_at IS NULL
            """
        ),
        {"id": dlq_id},
    ).mappings().first()
    if not row:
        return None

    task = celery_app.tasks.get(row["task_name"])
    if not task:
        log.error("requeue_dead_letter: unknown task %s", row["task_name"])
        return None

    payload = row["payload"] or {}
    # Reset job_status if present so the worker can transition it again.
    if row["job_id"]:
        db.execute(
            text(
                """
                UPDATE job_status
                   SET status = 'queued', error = NULL, finished_at = NULL,
                       progress = 0, message = 'requeued from DLQ', updated_at = NOW()
                 WHERE id = :id
                """
            ),
            {"id": row["job_id"]},
        )

    kwargs = payload if isinstance(payload, dict) else {}
    # Convention: tasks that participate in DLQ accept job_id as first arg.
    args = []
    if row["job_id"] and "job_id" not in kwargs:
        args = [str(row["job_id"])]

    async_result = task.apply_async(args=args, kwargs=kwargs)

    db.execute(
        text(
            """
            UPDATE dead_letter_jobs
               SET requeued_at = NOW(), requeued_by = :by
             WHERE id = :id
            """
        ),
        {"by": by_admin_id, "id": dlq_id},
    )
    db.commit()
    return async_result.id
