# Stage D — Scanner header stats correctness

## Bug
`GET /user-events/{event_id}/scan/stats` rendered **Total Guests = 0 /
Checked In = 0 / Pending = 0** even after a real check-in.

Root cause: `_scan_event_aggregates` filtered the guest total to
`rsvp_status IN (confirmed, checked_in)`. Guests added via SMS/WhatsApp
invites start with `rsvp_status = pending`, so they were excluded from
both `total` and (because `checked_db` keys off `checked_in=True` only)
they appeared as zero while the scanner clearly had records.

Ticketed events were correct because tickets always carry an
approved/confirmed order before they can be scanned.

## Fix
`_scan_event_aggregates` (guests branch) now counts **every attendee row
for the event** — matching the Guests tab `summary.total` — and layers
in Redis-staged check-ins exactly as before. Ticket branch unchanged.

## Verification
1. Create guest event, add an invited (pending RSVP) guest.
2. Open Check-In Mode — header now shows `Total 1 / Checked 0 / Pending 1`.
3. Scan the guest — header flips to `Total 1 / Checked 1 / Pending 0`
   instantly via the Redis-staged layer, and stays correct after the
   fastlane drain persists to Postgres.
4. For a ticketed event with one approved 2-seat order: header shows
   `Total 2 / Checked 0 / Pending 2`, then `Checked 2 / Pending 0`
   after the scan.

No response shape change — same `{ mode, labels, total, checked_in,
pending }` payload, so mobile and web read it unchanged.
