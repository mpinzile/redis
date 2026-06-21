"""
Endpoint classification table used by PerfMiddleware to pick warn/error
thresholds and tag logs.

Keys are FastAPI route templates (e.g. "/events/{event_id}/checkin/scan").
Values are one of:
    "instant"  -> p95 700ms,  warn 700, err 1500, crit 3000
    "normal"   -> p95 1s,     warn 1000, err 2000, crit 3000
    "heavy"    -> heavy-accepted; only initial response is bounded
    "list"     -> large paginated read; first page < 1s

If a route is not listed the default is "normal".

This table is seeded module-by-module and intentionally coarse. Stage 2 of
the performance program fills in per-endpoint detail after 24h of staging
data lands.
"""

from __future__ import annotations

GROUPS = {
    "instant": {"warn_ms": 700, "err_ms": 1500, "crit_ms": 3000},
    "normal":  {"warn_ms": 1000, "err_ms": 2000, "crit_ms": 3000},
    "heavy":   {"warn_ms": 1000, "err_ms": 2000, "crit_ms": 5000},
    "list":    {"warn_ms": 1000, "err_ms": 2000, "crit_ms": 3000},
}

# Seeded explicit overrides. Add to this list as endpoints get classified.
ENDPOINT_GROUPS: dict[str, str] = {
    # ── instant ──
    "/api/v1/checkin/scan": "instant",
    "/api/v1/events/{event_id}/checkin/scan": "instant",
    "/api/v1/events/{event_id}/checkin/stats": "instant",
    "/api/v1/notifications/{notification_id}/read": "instant",
    "/api/v1/notifications/read-all": "instant",
    "/api/v1/rsvp/{token}": "instant",
    "/api/v1/posts/{post_id}/like": "instant",
    "/api/v1/moments/{moment_id}/glow": "instant",
    # ── heavy (must move to Celery later) ──
    "/api/v1/event-cards/send": "heavy",
    "/api/v1/event-cards/send-batch": "heavy",
    "/api/v1/user-contributors/import": "heavy",
    "/api/v1/uploads/import-guests": "heavy",
    "/api/v1/whatsapp-admin/broadcast": "heavy",
    "/api/v1/messages/bulk": "heavy",
    "/api/v1/reports/generate": "heavy",
    # ── list ──
    "/api/v1/events/{event_id}/guests": "list",
    "/api/v1/events/{event_id}/tickets": "list",
    "/api/v1/whatsapp-logs": "list",
    "/api/v1/moments": "list",
    "/api/v1/notifications": "list",
    "/api/v1/messages": "list",
}


def classify(route_template: str) -> str:
    return ENDPOINT_GROUPS.get(route_template, "normal")


def thresholds(group: str) -> dict:
    return GROUPS.get(group, GROUPS["normal"])
