# Endpoint Performance Matrix (Stage 2 seed)

This file is **seeded by route module** with a default classification
group. Per-endpoint refinement happens after Stage 1 instrumentation has
24h of staging traffic, when we can fill `p50`, `p95`, `p99`, `bytes`,
`db_n` from real data instead of guesses.

Groups:

- **A — instant**: p95 ≤ 700ms. Single indexed write, small payload, no
  joins. Background work after response.
- **B — fast read**: p95 ≤ 1s. Indexed read, optional cache, lean
  serializer, paginated.
- **C — heavy accepted**: initial response ≤ 1s, real work in Celery.
- **D — list**: large paginated read; first page < 1s, cursor pagination.

## Default group per route module

| Module | Default group | Notes |
|---|---|---|
| `auth.py` | B | Login/signup; OTP flows must hit B p95. |
| `users.py` | B | Profile reads. Writes are A. |
| `account_setup.py` | B | |
| `account_deletion.py` | C | Deletion fan-out belongs in Celery. |
| `change_password.py` | A | |
| `profile.py` | B | |
| `settings.py` | A | Toggles. |
| `notifications.py` | D | List is D; mark-read is A. |
| `references.py` | B | Cache-friendly. |
| `events.py` | B / C | Detail B, create C (background setup). |
| `user_events.py` | B | |
| `event_groups.py` | B | |
| `event_sponsors.py` | B | |
| `event_invitation_templates.py` | B | |
| `event_checkin_team.py` | B | |
| `event_cards.py` | C | Card sending is heavy; queue. |
| `checkin_fast.py` | A | Already on fastlane pattern. |
| `scan_resolve.py` | A | |
| `rsvp.py` | A | |
| `ticketing.py` | B / C | List B, purchase C (idempotent reservation). |
| `ticket_reservations.py` | A | Atomic reservation. |
| `ticket_offline_claims.py` | A | |
| `nuru_cards.py` | C | Card render is Celery. |
| `card_templates.py` | B | |
| `templates.py` | B | |
| `messages.py` | D | Log list is D; send is C. |
| `whatsapp_admin.py` | C | Broadcast is heavy. |
| `whatsapp_logs.py` | D | Indexed by status + event. |
| `calls.py` | C | Schedule call returns immediately; worker dials. |
| `voice_calls.py` | C | |
| `reminder_automations.py` | C | Triggers fan-out via Celery. |
| `user_contributors.py` | B / C | List B, import C. |
| `public_contributions.py` | A | RSVP-equivalent path. |
| `expenses.py` | B | |
| `bookings.py` | B | |
| `services.py` | D | Public list. |
| `user_services.py` | B | |
| `agreements.py` | B | |
| `support.py` | B | |
| `contact.py` | A | |
| `payments.py` | C | Webhook drives final status. |
| `payment_profiles.py` | B | |
| `received_payments.py` | B | |
| `wallet.py` | B | |
| `withdrawals.py` | C | |
| `escrow.py` | B | |
| `offline_payments.py` | A | |
| `delivery_otp.py` | A | |
| `posts.py` | D | Like/comment are A. |
| `moments.py` | D | Glow/spark are A. |
| `social.py` | B | |
| `communities.py` | B / D | List D, write B. |
| `circles.py` | B | |
| `combined.py` | B | Cross-cutting reads — audit for fat payloads. |
| `meetings.py` | B | |
| `meeting_documents.py` | B | |
| `meeting_og.py` | B | OG cache target. |
| `meeting_redirect.py` | A | |
| `migration.py` | C | |
| `uploads.py` | C | Upload returns immediately, parsing in Celery. |
| `issues.py` | B | |
| `analytics.py` | C | Precompute; reads from cache. |
| `admin*.py` | varies | Admin-only; not on user critical path. |

## Per-endpoint refinement (TODO after Stage 1 data)

For each row above, after staging data lands:

| endpoint | group | p50 | p95 | p99 | bytes | db_n | redis_needed | celery_needed | indexes_needed | risk |
|---|---|---|---|---|---|---|---|---|---|---|

Filled by running the log aggregator query in
`backend/docs/performance/README.md` per `route`, then writing the
optimization plan in **Plan 2**.

## Explicit overrides already wired

See `backend/app/core/perf/endpoint_groups.py — ENDPOINT_GROUPS`.
That dict is the source of truth for log severity thresholds. Add
entries as endpoints get reclassified.
