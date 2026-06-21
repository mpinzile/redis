# Plan 2 — Reliability Infrastructure

Status: **shipped, awaiting migration + first endpoint adoption**.

This document explains the contract for every "instant response, work
continues" endpoint going forward. Stages 3+ (moving endpoints onto
Celery, payload trimming) **must** use these primitives — do not invent
parallel ones.

## Tables (migration `cafe27054700`)

| Table              | Purpose                                                    |
| ------------------ | ---------------------------------------------------------- |
| `job_status`       | Canonical row per background job; clients poll for outcome |
| `idempotency_keys` | Replay guard for POSTs (24h TTL)                           |
| `dead_letter_jobs` | Append-only failures after retry exhaustion                |

Indexes are tuned for the three hot queries: "my recent jobs", "jobs by
status", "unresolved DLQ".

## Backend API surface (`backend/app/core/jobs/`)

```python
from core.jobs import (
    create_job, get_job, list_jobs_for_user,
    mark_running, mark_succeeded, mark_failed, mark_retrying, set_progress,
    begin_idempotent, finish_idempotent, lookup_idempotent,
    ReliableTask, requeue_dead_letter,
)
```

### Pattern A — endpoint enqueues, returns `job_id` immediately

```python
@router.post("/something")
def do_something(body, db, current_user):
    job_id = create_job(
        db, task_name="tasks.foo.bar",
        user_id=str(current_user.id), event_id=body.event_id,
        max_attempts=5,
    )
    db.commit()
    foo_bar.delay(job_id, body.dict())   # task = @celery_app.task(base=ReliableTask, bind=True)
    return standard_response(success=True, data={"job_id": job_id, "status": "queued"})
```

Client polls `GET /api/v1/jobs/{job_id}` (already wired) to learn the
outcome. No response-shape changes to existing endpoints required.

### Pattern B — Celery task using `ReliableTask`

```python
@celery_app.task(base=ReliableTask, bind=True, max_retries=5)
def foo_bar(self, job_id, payload):
    self.bind_job(job_id)
    try:
        # ... work, calling self.set_progress(progress=..., total=...) ...
        self.job_succeeded(result={"items": n})
    except Exception as exc:
        self.job_failed_or_retry(exc, payload={"job_id": job_id, "payload": payload})
```

`ReliableTask` does:

- exponential backoff retry (1s → 300s cap, jittered)
- `job_status` transitions on every state change
- on terminal failure: marks the job `dead_lettered` **and** writes a
  `dead_letter_jobs` row that admins can requeue.

### Pattern C — idempotent POST

```python
key = request.headers.get("Idempotency-Key")
if key:
    cached = lookup_idempotent(db, scope="contributions.create", key=key, user_id=uid)
    if cached and cached["status"] == "completed":
        return cached["response_body"]
    if not begin_idempotent(db, scope="contributions.create", key=key, user_id=uid):
        raise HTTPException(409, "Duplicate request in progress")

response = do_the_work()

if key:
    finish_idempotent(
        db, scope="contributions.create", key=key,
        response_code=200, body=response,
    )
return response
```

The unique `(scope, key)` index makes replay handling race-safe.

## HTTP routes

| Method | Path                                          | Purpose                            |
| ------ | --------------------------------------------- | ---------------------------------- |
| GET    | `/api/v1/jobs`                                | Current user's last 50 jobs        |
| GET    | `/api/v1/jobs/{id}`                           | One job (owner or admin only)      |
| GET    | `/api/v1/admin/jobs`                          | Admin list, filterable             |
| POST   | `/api/v1/admin/jobs/{id}/retry`               | Re-enqueue a single job            |
| POST   | `/api/v1/admin/jobs/{id}/cancel`              | Mark stale job cancelled           |
| GET    | `/api/v1/admin/dead-letter-jobs`              | Unresolved DLQ entries             |
| POST   | `/api/v1/admin/dead-letter-jobs/{id}/requeue` | Re-enqueue a DLQ entry             |
| POST   | `/api/v1/admin/dead-letter-jobs/{id}/resolve` | Mark DLQ entry handled (no rerun)  |
| POST   | `/api/v1/admin/jobs/force-sync`               | `{ domain, args }` Redis→PG reconcile |

`force-sync` registry (`core/jobs/force_sync_registry.py`) currently exposes:

- `checkin` — runs `tasks.checkin_persist.reconcile_event(event_id)`.

Add more domains here as we move them onto the fast-lane pattern.

## Periodic maintenance (Celery beat)

- `purge-expired-idempotency-keys` — hourly, drops rows past `expires_at`.
- `purge-old-job-status` — daily 03:45, drops finished jobs > 30d (DLQ rows kept).

## What this plan does **not** do

- Does **not** move any existing endpoint onto Celery yet — that's the
  job of Plan 3, gated on real p95 numbers from the Plan 1 instrumentation.
- Does **not** add new Redis hot-state. That's Plan 3 too.
- Does **not** alter response shapes of existing endpoints.

## Rollback

1. Stop using `create_job` / `ReliableTask` in any new endpoint.
2. Routes `jobs.py` / `admin_jobs.py` are self-contained — un-include
   them from `api/routes/__init__.py`.
3. `alembic downgrade -1` drops the three tables.
