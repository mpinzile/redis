"""Reliability infra (Plan 2) — public surface.

The web/mobile clients only need two concepts:

1.  Enqueue: ``create_job(...)`` produces a ``job_id`` you can hand back in
    the immediate HTTP response.
2.  Poll:    ``GET /jobs/{id}`` returns the row maintained by the worker.

Workers use ``ReliableTask`` as their Celery base class. It:

- writes ``job_status`` transitions (queued → running → succeeded/failed)
- retries with exponential backoff up to ``max_attempts``
- on terminal failure, writes a ``dead_letter_jobs`` row so the work is
  visible and re-runnable from the admin console.

Idempotency is opt-in via ``with_idempotency(scope, key, user_id)``.
"""
from .status import (
    create_job,
    get_job,
    list_jobs_for_user,
    mark_running,
    mark_succeeded,
    mark_failed,
    mark_retrying,
    set_progress,
)
from .idempotency import begin_idempotent, finish_idempotent, lookup_idempotent
from .base_task import ReliableTask, requeue_dead_letter

__all__ = [
    "create_job",
    "get_job",
    "list_jobs_for_user",
    "mark_running",
    "mark_succeeded",
    "mark_failed",
    "mark_retrying",
    "set_progress",
    "begin_idempotent",
    "finish_idempotent",
    "lookup_idempotent",
    "ReliableTask",
    "requeue_dead_letter",
]
