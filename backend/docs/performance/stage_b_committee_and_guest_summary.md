# Plan 3 Stage B — committee pagination + guest-tab summary cache

Continuation of Stage A. Same rules: no Celery for reads, response shapes
unchanged, no client coordination required.

## Targets (before → after)

| Endpoint / hot path                                | Before                                   | After (target) |
| -------------------------------------------------- | ---------------------------------------- | -------------- |
| `GET /user-events/committee`                       | Loads **every** membership into Python, then paginates. ~600-1500ms for users in many events. | <150ms p95 — SQL `COUNT` + `LIMIT/OFFSET`. |
| `GET /user-events/{event_id}/guests` (summary)     | 3 aggregate queries on every call (status counts, checked-in, invitations_sent). 200-450ms even when nothing changed. | <50ms p95 on cache hit; recomputed at most every 30s, busted on guest mutation. |
| Polling load on guests tab                         | Every poll re-ran the 3 aggregates.       | Aggregates run once per 30s or on mutation. |

## What changed

### 1. `/user-events/committee` — SQL-level pagination
- Replaced "fetch all memberships → slice in Python" with
  `COUNT(*)` + `LIMIT/OFFSET`, then batch-load events, roles, permissions
  for the paged slice only.
- Existing index `idx_ecm_user_created (user_id, created_at DESC)` covers
  both the count and the paged query.
- Response shape unchanged.

### 2. `/user-events/{event_id}/guests` — cached summary
- New cache key `ev:{event_id}:guest_summary` (TTL 30s) wraps the
  per-event status counts + checked-in + invitations_sent block.
- The summary is invariant across `page`, `limit`, `rsvp_status`, and
  `search`, so a single key per event is correct and reused by every
  paginated request.
- Per-page data (`guests`, `pagination`) is **not** cached — pagination
  filters (`rsvp_status`, `search`) still execute fresh against the DB.

### 3. Cache invalidation
- New helper `core.redis.invalidate_event_guest_summary(event_id)`.
- Called from every guest-mutation path so the cached summary is fresh
  immediately, not on the next 30s tick:
  - `POST /user-events/{event_id}/guests` (single + contributor variant)
  - `POST /user-events/{event_id}/guests/bulk`
  - `POST /user-events/{event_id}/guests/from-contributors`
  - `PUT  /user-events/{event_id}/guests/{guest_id}`
  - `DELETE /user-events/{event_id}/guests/{guest_id}`
  - `DELETE /user-events/{event_id}/guests/bulk`
  - `POST /user-events/{event_id}/guests/{guest_id}/checkin`
  - `POST /user-events/{event_id}/guests/checkin-qr`
  - `POST /user-events/{event_id}/guests/{guest_id}/undo-checkin`
  - Public RSVP commit paths in `routes/rsvp.py`
  - Background drainer `tasks/checkin_persist.drain_event` after a
    successful ack — so QR check-ins routed through the Redis fastlane
    bust the cache as soon as their writes land in Postgres.

## Verification

1. No migration required — pure code + cache change.
2. Restart API + Celery worker + Celery beat.
3. Open the **Committee** tab as a user with ≥20 memberships:
   - `perf.request` log for `GET /user-events/committee` should show
     `elapsed_ms < 150` and `db_count` ≤ 6 (was 1 + N for the full
     scan).
4. Open the **Guests** tab on a busy event, then refresh / paginate:
   - First call: `perf.request` shows the usual ~3 aggregate queries.
   - Subsequent calls within 30s: `db_count` drops by 3, `elapsed_ms`
     drops by ~150-300ms.
5. Add / remove / RSVP a guest, then immediately refresh the Guests
   tab — summary numbers update on the next request (cache was
   invalidated synchronously inside the mutation handler).
6. Drive a QR scan through the fastlane (`POST /guests/checkin-qr`) and
   confirm the cached "checked_in" count moves within one drain tick
   (~5s) rather than waiting 30s.

## Out of scope this stage
- `/user-events/` (organizing tab) — already cheap thanks to existing
  composite indexes; leave alone until perf logs say otherwise.
- Event detail (`GET /user-events/{event_id}`) — already cached for 60s
  in essential mode.
- WhatsApp logs, contributions, ticketing — next stage, after fresh
  numbers from production.
