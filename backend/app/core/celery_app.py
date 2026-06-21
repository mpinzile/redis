"""
Celery Application
==================
Central Celery instance used by all background tasks.

Worker startup:
  cd backend/app
  celery -A core.celery_app worker --loglevel=info --concurrency=4

Beat (scheduler) startup:
  celery -A core.celery_app beat --loglevel=info

Combined (dev convenience):
  celery -A core.celery_app worker --beat --loglevel=info --concurrency=2
"""

import os
from celery import Celery
from celery.schedules import crontab

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
DEPLOYMENT_MODE = os.getenv("DEPLOYMENT_MODE", "vps").lower().strip()
CELERY_ENABLED = DEPLOYMENT_MODE != "vercel"

# On Vercel (or any serverless platform) Celery + Redis aren't available.
# We still construct a Celery instance so `celery_app.task` decorators don't
# break imports, but the broker is set to an in-memory dummy and tasks
# called with .delay() will fall back to direct execution.
if CELERY_ENABLED:
    _broker = REDIS_URL
    _backend = REDIS_URL
else:
    _broker = "memory://"
    _backend = "cache+memory://"

celery_app = Celery(
    "nuru",
    broker=_broker,
    backend=_backend,
    include=[
        "tasks.content_cleanup",
        "tasks.quality_scores",
        "tasks.notifications",
        "tasks.sms_dispatch",
        "tasks.payments_verify",
        "tasks.maintenance",
        "tasks.whatsapp_dispatch",
        "tasks.push_dispatch",
        "tasks.reminder_dispatch",
        "tasks.contributor_imports",
        "tasks.member_imports",
        "tasks.whatsapp_availability",
        "tasks.checkin_persist",
    ],
)

# ── Celery configuration ──
celery_app.conf.update(
    # Serialization
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="Africa/Nairobi",
    enable_utc=False,

    # Reliability
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    task_reject_on_worker_lost=True,

    # Queue routing — everything goes to the default queue so a single
    # ``celery worker`` process (the one started by nuru-celery.service)
    # picks up every task type. Previously bulk SMS + OTP tasks were
    # routed to dedicated queues (``bulk_sms``, ``auth_otp``) that no
    # worker actually subscribed to, so jobs were enqueued and silently
    # stuck in Redis forever. If/when we scale out to multiple workers
    # we can reintroduce routing — but only alongside a systemd unit
    # that consumes the extra queues.
    task_default_queue="default",
    task_routes={},

    # Result backend
    result_expires=3600,  # 1 hour

    # Rate limits (per worker)
    task_default_rate_limit="100/m",

    # Retry defaults
    task_default_retry_delay=60,
    task_max_retries=3,

    # Periodic tasks (replaces cron / daemon threads)
    beat_schedule={
        "auto-delete-removed-content": {
            "task": "tasks.content_cleanup.auto_delete_removed_content",
            "schedule": crontab(minute=0, hour="*/6"),  # Every 6 hours
        },
        "recompute-quality-scores": {
            "task": "tasks.quality_scores.recompute_quality_scores_task",
            "schedule": crontab(minute="*/30"),  # Every 30 minutes
        },
        # Re-flushes any sms_send_jobs left 'queued' (Vercel inline runs
        # that hit the time budget, or failed jobs whose 1h retry window
        # has elapsed). Cheap — uses the (status,next_retry_at) index.
        "resume-pending-sms-batches": {
            "task": "tasks.sms_dispatch.resume_pending_batches",
            "schedule": crontab(minute="*/5"),
        },
        # Re-poll the payment gateway for any stale pending mobile-money
        # transactions and promote them to paid/failed. Replaces the need
        # for an external cron pinging POST /payments/verify-pending.
        "verify-pending-payments": {
            "task": "tasks.payments_verify.verify_pending_transactions",
            "schedule": crontab(minute="*/2"),
        },
        # Free seat inventory by deleting ticket reservations that were
        # never paid for before reserved_until elapsed.
        "sweep-expired-ticket-reservations": {
            "task": "tasks.payments_verify.sweep_expired_ticket_reservations",
            "schedule": crontab(minute="*/10"),
        },
        # Deactivate moments past their expires_at so the global feed
        # filter is cheap and content_cleanup can hard-delete them after
        # 7 days.
        "expire-moments": {
            "task": "tasks.maintenance.expire_moments",
            "schedule": crontab(minute="*/15"),
        },
        # Physically delete media files for expired moments to free storage.
        "cleanup-expired-moment-assets": {
            "task": "tasks.maintenance.cleanup_expired_moment_assets",
            "schedule": crontab(minute="*/30"),
        },
        # Security: drop expired OTPs, password-reset tokens, and sessions.
        "purge-expired-auth-tokens": {
            "task": "tasks.maintenance.purge_expired_auth_tokens",
            "schedule": crontab(minute=0, hour="*"),  # hourly
        },
        # Flip stale service_delivery_otps from 'active' to 'expired' so
        # booking screens reflect the correct state without user action.
        "expire-stale-delivery-otps": {
            "task": "tasks.maintenance.expire_stale_delivery_otps",
            "schedule": crontab(minute="*/10"),
        },
        # Analytics retention — drop page_views older than 90 days.
        "prune-old-page-views": {
            "task": "tasks.maintenance.prune_old_page_views",
            "schedule": crontab(minute=30, hour=3),  # daily at 03:30 EAT
        },
        # Reliability infra — clear replay window once it's safe.
        "purge-expired-idempotency-keys": {
            "task": "tasks.maintenance.purge_expired_idempotency_keys",
            "schedule": crontab(minute=15, hour="*"),  # hourly
        },
        # Trim finished job_status rows older than 30 days (DLQ rows kept).
        "purge-old-job-status": {
            "task": "tasks.maintenance.purge_old_job_status",
            "schedule": crontab(minute=45, hour=3),  # daily 03:45 EAT
        },
        # Reminder automation scheduler — picks up due automations and
        # dispatches them to per-recipient send tasks.
        "scan-due-reminder-automations": {
            "task": "tasks.reminder_dispatch.scan_due_automations",
            "schedule": crontab(minute="*/5"),
        },
        # Check-In Fast Lane — drain every active event's Redis stream
        # into Postgres. Cheap when nothing is happening (only walks keys
        # that exist).
        "checkin-fastlane-drain": {
            "task": "tasks.checkin_persist.drain_active_events",
            "schedule": 2.0,  # every 2 seconds
        },
        # WhatsApp availability — active probing is disabled by policy.
        # Availability is learned opportunistically from real Nuru sends,
        # so no beat schedule is required here.

    },
)
