# Stage F — Deep Scan: Read-Path N+1 & Aggregate Sweeps

This stage executes the highest-ROI fixes from the deep audit. No response
shapes change. No background work moved. No mutations touched. Every change is
a read-path optimisation.

## Endpoints fixed

### `moments.py`
- `_moment_dict` rewritten as a thin wrapper over a new
  `_build_moment_dicts()` batch builder. Per-moment 4-query pattern (User,
  UserProfile, viewer count, has_seen) → at most 4 batched queries regardless
  of input size.
- `GET /moments/` (`get_moments_feed`): grouped feed reuses the pre-loaded
  user/profile maps; per-author User + UserProfile lookups eliminated.
- `GET /moments/trending`, `GET /moments/public/trending`: now route through
  the batch builder.
- `GET /moments/me`, `GET /moments/user/{id}`: added `page` / `limit`
  (default 30, max 100); batch builder replaces N+1 list comprehension.
- `GET /moments/my-removed`: paginated; per-moment 3-query fan-out collapsed
  into 2 batched queries (appeals + viewer counts), author resolved once.

### `ticketing.py`
- `GET /ticketing/events/{event_id}/ticket-classes` and `GET
  /ticketing/my-events/{event_id}/ticket-classes`: sold / reserved /
  pending quantities now collected via 2-3 GROUP BY queries up front
  instead of 2-3 per ticket class inside the loop.
- `GET /ticketing/my-tickets`: page-level batch loads for Event,
  EventTicketClass, organizer User + UserProfile, and a single fallback
  EventImage lookup for cover images. Eliminates ~4 queries per visible
  ticket row.
- `GET /ticketing/events/{event_id}/tickets`: page-level batch load of
  EventTicketClass replaces 1-per-row lookup.
- `GET /ticketing/my-upcoming-tickets`: rewritten as a single JOIN query
  with SQL-side `Event.start_date >= today` filter and `LIMIT 10`,
  replacing an unbounded fetch + Python date filter + per-ticket Event
  and EventTicketClass queries.

### `issues.py`
- `GET /issues/`: 4 separate status COUNT queries → one CASE-based
  aggregate. Per-issue response count + last-response queries → batched
  via GROUP BY plus a single follow-up `OR`-keyed lookup.

### `expenses.py`
- `_expense_summary()`: full-table load + Python sum/category loop
  replaced by `SUM + COUNT` and `GROUP BY category` queries.

### `event_sponsors.py`
- `GET /user-events/{event_id}/sponsors`: 4 Python loops over sponsor
  rows collapsed into one CASE-based aggregate query for the summary
  block (total / accepted / pending / declined / contribution_total).

### `messages.py`
- `GET /messages/`: added `page` / `limit` (default 30) and pushed
  `search` into SQL via a join on the other participant. No more
  full-conversation load + Python filter on power-user accounts.
  `ConversationHide` lookup now scoped to the visible page only.

### `communities.py`
- `GET /communities/recommended`: full table scan + Python sort replaced
  with SQL `ORDER BY` over `CASE`-based interest_match / verified boosts +
  `member_count` / `created_at`, with proper `OFFSET / LIMIT` and a
  filtered `COUNT(*)` for pagination.
- `GET /communities/my`: two separate queries + Python union replaced
  with a single `OR (created_by = me OR id IN member_subquery)` query.

### `posts.py`
- `GET /posts/my-removed`: added `page` / `limit`; per-post 7-query fan-out
  (appeal, images, glow/echo/comment counts, author) replaced with 5
  batched queries (GROUP BY on counts, `IN` lookups for appeals/images)
  and a single author resolution (always current_user).

## Rules respected
- No response-shape changes (additive only where pagination was already
  expected by clients).
- No reads moved to Celery, no new background mutations.
- No schema migrations; no destructive changes.
- All edits are read-path; mutation endpoints untouched.

## Expected impact
- `/moments/` feed: ~800 queries on heavy accounts → ≤6.
- `/ticketing/my-tickets`: 4× page-size queries → ~6 queries total.
- `/ticketing/my-upcoming-tickets`: unbounded scan → single LIMIT-10 join.
- `/issues/`: (4 + 2×page) queries → 3 queries.
- `/messages/`: unbounded conversation load → paginated SQL.
- `/communities/recommended`: full table scan + Python sort → SQL ORDER BY + LIMIT.
- `/expenses` summary: full table load → 2 aggregates.
