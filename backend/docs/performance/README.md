# Nuru Performance Instrumentation — Stage 1

Measurement first. No optimization in this stage. The goal is one
structured JSON perf line per request, plus matching client lines, so we
can compute real p50/p95/p99 instead of guessing.

## What was added

### Backend (`backend/app/core/perf/`)

- `PerfMiddleware` — innermost ASGI middleware. Generates a `request_id`
  (or reuses `X-Request-ID` from the client), binds a `PerfContext` to a
  contextvar for the request, and logs one JSON line under the
  `nuru.perf.json` logger when the response is finished.
- `db_metrics.install()` — registers SQLAlchemy `before/after_cursor_execute`
  listeners that update the active `PerfContext`. No-op when no context
  is bound (so Celery workers, scripts, and tests are unaffected).
- `timed_redis()` — context manager. Wrap Redis call sites that you care
  about; counts ops + total ms onto the request context.
- `timed_external(provider)` — context manager. Wrap outbound provider
  calls (WhatsApp/SMS/email/storage/payments) with the provider name; a
  per-provider breakdown ends up in the perf line as `ext_by`.
- `timed_enqueue(task, *args, **kwargs)` — replacement for
  `task.delay(...)` / `task.apply_async(...)` that records broker round-trip
  time and task count.

### Web (`src/lib/perf.ts`)

- `markTap(action)` / `markRendered(action)` — bracket a user-visible
  action; `rendered` emits `waited_ms` from tap to commit.
- `markBgStart` / `markBgEnd` — background refreshes, logged
  separately so they never inflate user-facing timings.
- `installFetchTracer()` — called once from `src/main.tsx`; wraps
  `window.fetch` and emits a `fetch` line with method, path, status,
  bytes, duration, and `rid` (the backend `X-Request-ID`).

Lines go to `console.info` and to a `nuru:perf` `CustomEvent` for any
future telemetry sink. Disable with `localStorage.NURU_PERF = "off"`.

### Mobile (`mobile/nuru/lib/core/perf/perf_tracer.dart`)

- `PerfTracer.tap(action)` returns a `PerfSpan`. Call `span.screenUpdated()`
  after the state notify / `setState`.
- `PerfTracer.bgStart(action)` / `span.bgEnd()` for background refresh.
- `tracedHttp(...)` — generic HTTP wrapper used by `ApiBase`. Every
  GET/POST/PUT/PATCH/DELETE through `ApiBase` now emits one `fetch`
  line with method, endpoint, status, bytes, duration, and `rid`.

Lines go through `dart:developer` log under name `nuru.perf`. Disable by
setting `PerfTracer.enabled = false` at app boot.

## What did NOT change

- No response bodies. The only new response header is `X-Request-ID`
  (and the existing `X-Response-Time` is preserved when present).
- No database queries, no new indexes, no new Redis keys, no new Celery
  tasks.
- Existing `SlowRequestLoggerMiddleware` and `QueryCountMiddleware`
  remain in place; the new perf middleware sits inside them.

## Reading the logs

Every backend perf line looks like (one line in stdout):

```json
{"evt":"req","rid":"…","method":"POST","path":"/api/v1/events/abc/checkin/scan","route":"/api/v1/events/{event_id}/checkin/scan","status":200,"group":"instant","dur_ms":142.3,"db_n":2,"db_ms":7.1,"db_slow_ms":4.4,"redis_n":3,"redis_ms":1.2,"celery_n":1,"celery_ms":1.0,"ext_n":0,"ext_ms":0.0,"bytes":248,"event_id":"abc"}
```

Web/mobile `fetch` lines carry the same `rid`, so joining is direct.

### Querying p50 / p95 / p99

In a log aggregator (Loki/Elastic/Datadog), parse JSON, filter
`evt=req`, group by `route`, aggregate `dur_ms`:

```
percentile(dur_ms, 0.5) as p50
percentile(dur_ms, 0.95) as p95
percentile(dur_ms, 0.99) as p99
count()
avg(db_n) as avg_queries
avg(bytes) as avg_bytes
```

### Slow-request thresholds

Group is set in `endpoint_groups.py`. Default is `normal`. Log level is
escalated automatically:

| group   | warn | error | critical |
| ------- | ---- | ----- | -------- |
| instant | 700  | 1500  | 3000     |
| normal  | 1000 | 2000  | 3000     |
| list    | 1000 | 2000  | 3000     |
| heavy   | 1000 | 2000  | 5000     |

(All values in ms.)

## Rollback

Set `PERF_INSTRUMENTATION=false` in the environment and restart. The
middleware short-circuits; SQLAlchemy listeners no-op because no context
is bound. To remove entirely, delete the `app.add_middleware(PerfMiddleware)`
line in `backend/app/main.py`.

Web: set `localStorage.NURU_PERF = "off"`.

Mobile: set `PerfTracer.enabled = false` in `main.dart` before
`runApp`.

## Next plan

This is Stage 1 (measurement) and the safety rules from Stage 0. After
24–48h of staging data lands, Plan 2 will deliver:

1. The reliability foundation — `job_status` table, `idempotency_keys`
   table, retry helper with DLQ, admin retry endpoint, force-sync
   endpoint. Required before *any* endpoint moves to Celery beyond the
   existing check-in fastlane.
2. The endpoint matrix (`endpoint_matrix.md`) filled in with real
   p50/p95/p99, query counts, payload bytes from production data.

Only after Plan 2 lands do we start moving endpoints to Celery, trimming
payloads, or adding indexes.
