"""Register domain-specific force-sync handlers.

Imported at app startup (from ``app.main``) so the admin
``POST /admin/jobs/force-sync`` endpoint can dispatch:

    { "domain": "checkin", "args": { "event_id": "..." } }

Add new domains here as we move more endpoints onto the fast-lane pattern.
"""
from __future__ import annotations

import logging

from api.routes.admin_jobs import FORCE_SYNC_HANDLERS

log = logging.getLogger("force_sync.registry")


def _checkin_force_sync(event_id: str) -> dict:
    from tasks.checkin_persist import reconcile_event
    async_result = reconcile_event.delay(event_id)
    return {"celery_task_id": async_result.id, "event_id": event_id}


def register_all() -> None:
    FORCE_SYNC_HANDLERS["checkin"] = _checkin_force_sync
    log.info("force-sync handlers registered: %s", list(FORCE_SYNC_HANDLERS.keys()))
