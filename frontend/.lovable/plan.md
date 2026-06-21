# Nuru Performance Program — Plan (Stages 0–2 only)

This session ships **no code**. It commits to a measurement-first program so every later optimization has real before/after numbers. Performance claims later in the program will be backed by logs from this instrumentation, not estimates.

## Guiding rules (Stage 0)

1. Postgres stays the permanent source of truth. Redis is only hot state, cache, counter, lock, or readiness layer.
2. Celery is only for work that can safely happen after the user response.
3. No response shape changes without updating web and mobile clients in the same change.
4. Every risky fast path ships behind a feature flag with a documented rollback step.
5. No "this is faster now" claim without before/after timings from the instrumentation below.
6. Reliability infra (job_status, idempotency_keys, retry/DLQ, admin retry, force-sync) is built **before** any new endpoint is moved to Celery. Only the check-in fastlane exists today.

## Stage 1 — Measurement instrumentation

### Backend (FastAPI)

Add one ASGI middleware `PerfMiddleware` that, per request, records and logs as a single structured JSON line:

- `request_id` (uuid4, also returned in `X-Request-ID`)
- `method`, `path` (route template, not raw URL), `status_code`
- `duration_ms` (monotonic)
- `db_query_count`, `db_total_ms`, `db_slowest_ms`, `db_slowest_sql` (truncated 200 chars)
- `redis_ops`, `redis_total_ms`
- `celery_enqueue_ms`, `celery_tasks_enqueued`
- `external_ms` (WhatsApp/SMS/email/storage), `external_calls`
- `response_bytes`
- `user_id`, `event_id` (extracted from path params or auth context when present)

Implementation hooks:

- DB metrics: SQLAlchemy `before_cursor_execute` / `after_cursor_execute` events on the engine, stored in a `contextvars.ContextVar` per request.
- Redis metrics: thin wrapper around the existing redis client (`timed_redis.get/set/...`) that increments contextvar counters. Existing call sites swap module import only.
- Celery metrics: wrap `task.delay` / `task.apply_async` in a helper `enqueue(task, ...)` that times the broker round-trip.
- External metrics: wrap the existing WhatsApp/SMS/email/storage clients with a `timed_external("whatsapp", ...)` context manager.

Slow-request thresholds (logged at WARNING / ERROR / CRITICAL):

```text
group        warn      error     critical
instant      700 ms    1.5 s     3 s
normal       1 s       2 s       3 s
heavy*       —         —         —   (only initial response is bounded, see Stage 2)
```

Group is resolved from a small `ENDPOINT_GROUPS: dict[route_template, "instant"|"normal"|"heavy"|"list"]` table seeded in Stage 2.

Output: stdout JSON lines, one per request. Compatible with existing log shipping. No DB writes from the middleware itself.

Rollback: remove middleware registration; SQLAlchemy/Redis/Celery wrappers are no-ops when contextvar is unset.

### Web (React)

Add `src/lib/perf.ts`:

- `markTap(action)` — captures `performance.now()` and `action` name.
- Axios/fetch interceptor records `request_start`, `response_received`, `status`, `bytes`, `X-Request-ID` echoed from backend.
- `markRendered(action)` called from the screen after state commits (via `useEffect` with the action key).
- Background refreshes use `markBgStart` / `markBgEnd` and are logged separately so they never inflate user-facing timings.

Emits one structured line per user action to `console.info` in dev and to an existing telemetry sink (if configured) in prod. Same `X-Request-ID` ties web timing to backend timing.

### Mobile (Flutter)

Add `lib/core/perf/perf_tracer.dart`:

- `PerfTracer.tap(action)` returns a `PerfSpan` with `tap_ts`.
- Dio interceptor on the shared `ApiClient` records `request_start`, `response_received`, `status`, `bytes`, captures `X-Request-ID`.
- `span.screenUpdated()` called after `setState` / provider notify.
- `span.bgStart()` / `span.bgEnd()` for background refresh, logged separately.
- Output via existing `AppLogger` as one structured line per action.

Critical screens to instrument first (no behavior changes, just tracer calls):

- Check-in scan + stats refresh
- Event detail open + tab switch
- RSVP update
- Guest list pagination
- Send invitation flow
- Notification mark-read

## Stage 2 — Endpoint classification matrix

Deliverable file: `backend/docs/performance/endpoint_matrix.md`.

For every route in `backend/app/api/routes/*.py`, one row:

| column | meaning |
|---|---|
| endpoint | `METHOD /path/template` |
| group | A instant / B fast-read / C heavy-accepted / D large-paginated |
| current_p50 / p95 / p99 | filled after instrumentation runs in staging |
| target_p95 | from group |
| current_payload_bytes / target | |
| current_query_count / target | |
| redis_needed | yes/no + key shape |
| celery_needed | yes/no + task name |
| indexes_needed | column list |
| frontend_changes | web + mobile notes |
| risk | low / medium / high |

Initial seeding (without numbers) is done from a static audit of the routes. Numbers are filled in after Stage 1 instrumentation runs against staging for at least 24 hours of real traffic.

## What this session will produce (when you say go)

Two commits, no behavior changes:

1. **Backend instrumentation** — `app/core/perf/middleware.py`, `app/core/perf/db_metrics.py`, `app/core/perf/redis_metrics.py`, `app/core/perf/celery_metrics.py`, `app/core/perf/external_metrics.py`, wiring in `app/main.py`, `ENDPOINT_GROUPS` seed.
2. **Web + mobile instrumentation** — `src/lib/perf.ts` + axios interceptor wiring; `lib/core/perf/perf_tracer.dart` + Dio interceptor + tracer calls on the six critical screens above.
3. **Docs** — `backend/docs/performance/README.md` (how to read the logs, how to query p50/p95/p99 from log aggregator, threshold table, rollback) and the empty `endpoint_matrix.md` seeded with route list and group classification.

## What this session will NOT do

- No query rewrites.
- No new indexes.
- No new Redis keys.
- No new Celery tasks.
- No reliability infra (job_status, idempotency_keys, DLQ) — that is the next plan, gated on Stage 1 data and required before Stage 6/11/16.
- No payload trimming.
- No serializer changes.

## After this lands

Run staging for 24–48h with real traffic, then I produce **Plan 2**: reliability infra (job_status, idempotency_keys, retry/DLQ, admin retry, force-sync) plus the filled-in endpoint matrix with real p95 numbers. Only after Plan 2 lands do we start moving endpoints to Celery or trimming payloads.

## Risks

- Middleware adds ~0.2–0.5 ms per request; acceptable.
- SQLAlchemy event listeners on a busy engine can be noisy in logs; mitigated by logging one summary line per request, not per query.
- Mobile tracer calls on hot paths must not allocate per build; `PerfSpan` is a const-constructible value type.

## Acceptance for this stage

- Every request in staging produces one JSON perf line with all fields populated.
- Every instrumented mobile action and web action produces one perf line with a matching `request_id`.
- Slow-request warnings fire at the documented thresholds.
- `endpoint_matrix.md` lists every route with a group assigned.
