# Plan 3 Stage A — fastlane drain + first two slow endpoints

Live signal driving this stage (post-restart perf logs):

| Endpoint / task                              | Before          | Notes                                                    |
| -------------------------------------------- | --------------- | -------------------------------------------------------- |
| Celery `checkin-fastlane-drain`              | ~4s per tick, every 2s (overlapping) | `xreadgroup block=0` → socket timeout, no lock          |
| `GET /api/v1/user-events/invited`            | ~4518ms         | N+1 (`EventInvitation` per attendee), in-memory paging  |
| `GET /api/v1/payments/pending`               | 867–910ms       | No composite index for (payer, status, created_at)      |

After-deploy targets (verify via `perf.*` log lines):

| Endpoint / task                              | Target          |
| -------------------------------------------- | --------------- |
| `checkin-fastlane-drain` (idle / no events)  | < 20ms, no overlap, no socket-timeout warnings |
| `checkin-fastlane-drain` (active event)      | < 200ms per tick |
| `GET /user-events/invited`                   | < 400ms p95     |
| `GET /payments/pending`                      | < 100ms p95     |

## What changed

### 1. Celery fastlane drainer
- `services/checkin_fastlane.read_stream` default is now `block_ms=None`
  (non-blocking). Passing `0` still works but is documented as "block
  forever — do not use from beat".
- `tasks/checkin_persist.drain_event` passes `block_ms=None`.
- `drain_active_events` now wraps the whole tick in a Redis lock
  (`fastlane:drain:lock`, TTL 30s, `SET NX EX`). Overlapping ticks exit
  cleanly with `{"skipped": "locked"}`.
- Beat schedule moved from 2s → 5s. With the lock + non-blocking reads
  this is purely about reducing churn; latency is still bounded by the
  Redis stream itself.
- Timeout exceptions from `xreadgroup` no longer log at WARN.

### 2. `/user-events/invited`
- Replaced "load every invitation + attendee for the user → paginate in
  Python → per-row EventInvitation lookup" with:
  - A single UNION subquery over `event_invitations` and
    `event_attendees` grouped by `event_id`, paginated at SQL level.
  - One batched `EventInvitation` query for the paged slice.
  - One batched `EventAttendee` query (already existed).
  - One batched fill-in query for invitation rows referenced by
    `attendee.invitation_id`.
- Response shape unchanged; web + mobile clients untouched.
- Existing indexes `idx_ei_invited_user_created` and
  `idx_ea_attendee_created` cover the new union scans.

### 3. `/payments/pending`
- Added Alembic migration `cafe27055100` creating
  `idx_transactions_payer_status_created (payer_user_id, status, created_at)`
  with `CREATE INDEX CONCURRENTLY` to avoid table locks. Run:
  `alembic upgrade head` then `ANALYZE transactions;`.
- No code changes — query plan picks up the index automatically.

## Verification on staging

1. `alembic upgrade head` — applies `cafe27055100`.
2. Restart API + Celery beat + worker.
3. Drive the three flows:
   - Open the My Events / Invited tab → `perf.request` log for
     `GET /user-events/invited` should show `elapsed_ms < 400` and
     `db_count` < ~12 (was 30+ for users with many invites).
   - Open any page that polls `GET /payments/pending` → `elapsed_ms < 100`.
   - Tail Celery: `journalctl -u nuru-celery -f` — no more "Timeout
     reading from socket" warnings; `drain_active_events` ticks complete
     in < 20ms when idle.
4. Compare p50/p95/p99 from the perf log aggregator over a 1h window
   before vs. after.

## Out of scope this stage
- Other `/user-events/*` endpoints (next stage, after we see fresh
  numbers).
- Moving anything to Celery — read endpoints stay synchronous per the
  reliability rules.
