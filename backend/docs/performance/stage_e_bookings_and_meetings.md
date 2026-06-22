# Stage E — Bookings & Meetings pagination

## Bookings (`GET /bookings/`, `GET /bookings/received`)

**Before**
- Loaded every booking row for the user into memory.
- Ran `build_booking_dicts` over the entire list, then filtered/searched in Python.
- Status summary and earnings computed by Python loops over the full list.
- Cost grew linearly with booking history — observed 1.2-2.4s for vendors with hundreds of bookings.

**After**
- Status summary is one grouped SQL query (`SELECT status, count(*) … GROUP BY status`).
- Earnings (received endpoint) is one `SUM(coalesce(quoted_price, proposed_price, 0))` query.
- Search pushed into SQL via outer joins on `UserService.title`, `Event.name`, and `ServiceBookingRequest.message`.
- Items are paginated at the SQL layer (`OFFSET/LIMIT`, default 20, max 100). `build_booking_dicts` only runs over the visible page.
- Response gains a `pagination` block (additive — existing clients ignoring it keep working).

Target: <200ms for typical vendor inboxes regardless of history size.

## Meetings (`GET /events/{event_id}/meetings`)

**Before**
- `list_meetings` loaded every meeting for the event with no pagination — heavy on long-running event spaces.

**After**
- SQL `COUNT` + `OFFSET/LIMIT` (default 20, max 100), newest first.
- `build_meeting_dicts` already batches participants/agenda/minutes, so the only remaining cost scales with page size.
- Adds a `pagination` block alongside the existing `data` field — additive, so the existing mobile/web list code keeps rendering.

## Rules respected
- No response-shape regressions: `bookings`, `summary`, `data` keys unchanged; only `pagination` added.
- No reads moved to Celery.
- No new background mutations; no idempotency/DLQ needed.
- Filters and search remain available; status filter still respects KPI totals because the summary query ignores the status filter.
