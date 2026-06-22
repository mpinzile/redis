# Plan 3 Stage C — WhatsApp logs + contributions summary

Targets:

| Endpoint / hot path                                  | Before                                                 | After (target) |
| ---------------------------------------------------- | ------------------------------------------------------ | -------------- |
| `GET /whatsapp/logs` (list, non-admin)               | Seq scan on `wa_message_logs` for every page load — `_scope_to_user` added `normalized_phone ILIKE '%last9'` which the existing index cannot serve, and the OR branch on `Event.owner_id` *raised* and silently dropped the event-scope clause via the bare `except`. | Equality-only scope (uses `ix_wa_message_logs_normalized_phone` + `ix_wa_message_logs_recipient_phone`); event scope now actually fires via the correct `organizer_id` column. |
| `GET /whatsapp/logs/stats`                           | GROUP BY status over the user's full log set every call (200-700ms on big mailboxes), polled by the dashboard. | Cached per (user, filter set) for 30s, busted on delete/restore. |
| `GET /user-events/{event_id}/contributions` summary  | 4 extra queries on every page change (`SUM(amount)`, target lookup, settings lookup, currency code). | Summary block cached per event for 30s, busted on every contribution mutation and on gateway payment confirmation. |

## What changed

### 1. WhatsApp log scoping — bug fix + index-friendly query
File: `backend/app/api/routes/whatsapp_logs.py::_scope_to_user`

- Dropped the trailing `normalized_phone.ilike("%last9")` and
  `recipient_phone.ilike("%last9")` conditions. They forced a seq scan
  on every dashboard request because PostgreSQL cannot use a btree
  index for a leading-wildcard `LIKE`. The remaining equality matches on
  the same columns still catch every real delivery (phones stored in
  `wa_message_logs` are always normalized at insert time).
- Replaced `Event.owner_id` (does not exist) with `Event.organizer_id`.
  The previous code raised inside the `try` and the bare `except`
  silently swallowed the entire "events I organize" branch — organizers
  were seeing only messages they personally triggered.

### 2. WhatsApp stats — per-user Redis cache (30s)
File: `backend/app/api/routes/whatsapp_logs.py::stats`

- New cache key `wa:stats:{user_id}:{filter_hash}` (TTL 30s). The hash
  covers every query parameter so toggling a status filter or date
  range still produces a correct payload.
- New helper `core.redis.invalidate_wa_log_stats(user_id)` (SCAN +
  DELETE `wa:stats:{user_id}:*`).
- Hooked into `DELETE /whatsapp/logs/{id}`, `POST /bulk-delete`, and
  `POST /{id}/restore` so the stat tiles refresh immediately after the
  user removes/restores rows.

### 3. Contributions summary — per-event Redis cache (30s)
File: `backend/app/api/routes/user_events.py::get_contributions`

- New cache key `ev:{event_id}:contrib_summary` (TTL 30s) wraps
  `{total_amount, target_amount, progress_percentage, currency}` — the
  block that drove three extra queries on every paginated request.
- `total_contributors` stays outside the cache because it tracks the
  list `total` exactly and is already a cheap `COUNT(*)` on the existing
  `idx_event_contributions_event_contributed` index.
- New helper `core.redis.invalidate_event_contrib_summary(event_id)`
  and a thin `_bust_contrib_summary` wrapper inside `user_events.py`.
- Invalidation wired into:
  - `POST /user-events/{event_id}/contributions`
  - `PUT  /user-events/{event_id}/contributions/{contribution_id}`
  - `DELETE /user-events/{event_id}/contributions/{contribution_id}`
  - Gateway payment confirmation in
    `routes/payments.py` (both the "existing row flips to confirmed"
    and "fresh contribution row inserted" paths). Without this the
    dashboard total would lag the bank by up to 30s after a successful
    mobile-money push.

## Verification

1. No migration required.
2. Restart API + Celery worker.
3. WhatsApp logs:
   - Open `/whatsapp/logs` as a non-admin organizer with a few
     hundred entries → `perf.request` for `GET /whatsapp/logs` should
     drop from "Seq Scan" plan to an Index Scan / Bitmap Or; expect
     `elapsed_ms` to fall 3-10× depending on table size.
   - Hit `GET /whatsapp/logs/stats` twice in a row — second call
     within 30s should log `db_count=0` (served from Redis).
   - Delete a log → next stats call should hit the DB once and then
     cache again.
4. Contributions tab:
   - Open an event's contributions tab and paginate. First page hits
     the DB for the summary; subsequent pages within 30s log
     `db_count` lower by 3-4 queries.
   - Record a contribution / trigger a mobile-money callback → the
     `total_amount` updates on the next request, no 30s wait.

## Out of scope this stage
- Moving WhatsApp resend into a separate ReliableTask flow — already
  fans out to Celery via `_send_whatsapp`, which Stage A's
  `checkin_fastlane` improvements have made reliable enough that
  resends finish under the existing budget.
- Meetings list pagination — current event scope is small (single
  event), already cheap.
- `POST /events` creation — large, multi-table writer; will get its own
  stage once we have a baseline timing log to measure against.
