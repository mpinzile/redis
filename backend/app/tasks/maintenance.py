"""
Task: Routine maintenance / housekeeping
========================================
A bag of small, idempotent jobs that keep tables tidy and security tight.
All jobs are safe to run repeatedly and bail out cleanly if their target
table is empty.

Jobs:

* expire_moments
    Sets ``is_active = False`` on ``user_moments`` whose ``expires_at`` has
    passed. Pairs with the existing 7-day ``content_cleanup`` task that
    hard-deletes inactive content with no appeal.

* purge_expired_auth_tokens
    Deletes rows from ``user_verification_otps``, ``password_reset_tokens``,
    and ``user_sessions`` whose ``expires_at`` is in the past. Reduces
    table bloat and shrinks the attack surface for stolen tokens.

* expire_stale_delivery_otps
    Flips ``service_delivery_otps.status`` from ``active`` to ``expired``
    once ``expires_at`` has passed so the booking UI shows the right state
    without waiting for the next user-triggered query.

* prune_old_page_views
    Deletes ``page_views`` older than 90 days — pure analytics, no business
    impact, but the table grows fast.
"""
from datetime import datetime, timedelta

from sqlalchemy import text

from core.celery_app import celery_app
from core.database import SessionLocal


# ─────────────────────────────────────────────
# Moments
# ─────────────────────────────────────────────
@celery_app.task(
    name="tasks.maintenance.expire_moments",
    bind=True,
    max_retries=2,
    default_retry_delay=120,
)
def expire_moments(self):
    from models.moments import UserMoment

    db = SessionLocal()
    try:
        now = datetime.utcnow()
        updated = (
            db.query(UserMoment)
            .filter(UserMoment.is_active == True, UserMoment.expires_at <= now)
            .update({UserMoment.is_active: False}, synchronize_session=False)
        )
        db.commit()
        return {"deactivated_moments": int(updated)}
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()


# ─────────────────────────────────────────────
# Storage cleanup — physically delete expired glimpse/moment assets
# ─────────────────────────────────────────────
@celery_app.task(
    name="tasks.maintenance.cleanup_expired_moment_assets",
    bind=True,
    max_retries=2,
    default_retry_delay=300,
)
def cleanup_expired_moment_assets(self, batch_size: int = 100):
    """For every expired moment whose media file has not yet been removed
    from the upload server, POST to the delete-file.php endpoint and mark
    the row as cleaned. The DB row is kept (analytics + appeals) but the
    underlying image/video bytes are freed."""
    from models.moments import UserMoment
    from utils.helpers import delete_storage_file_sync

    db = SessionLocal()
    deleted = 0
    failed = 0
    try:
        now = datetime.utcnow()
        candidates = (
            db.query(UserMoment)
            .filter(
                UserMoment.expires_at <= now,
                UserMoment.media_deleted_at.is_(None),
                UserMoment.media_url.isnot(None),
                UserMoment.media_url != "",
            )
            .limit(batch_size)
            .all()
        )
        for m in candidates:
            url = (m.media_url or "").strip()
            # Skip the "text:#hex" sentinel — there is no file to remove.
            if not url or url.startswith("text:"):
                m.media_deleted_at = now
                m.is_active = False
                continue
            ok = delete_storage_file_sync(url)
            # Best-effort: also try to delete the thumbnail if any.
            if m.thumbnail_url:
                delete_storage_file_sync(m.thumbnail_url)
            if ok:
                m.media_url = ""
                m.thumbnail_url = None
                m.media_deleted_at = now
                m.is_active = False
                deleted += 1
            else:
                failed += 1
        db.commit()
        return {"deleted": deleted, "failed": failed, "scanned": len(candidates)}
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()


# ─────────────────────────────────────────────
# Auth tokens (security hygiene)
# ─────────────────────────────────────────────
@celery_app.task(
    name="tasks.maintenance.purge_expired_auth_tokens",
    bind=True,
    max_retries=2,
    default_retry_delay=300,
)
def purge_expired_auth_tokens(self):
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        otp = db.execute(
            text("DELETE FROM user_verification_otps WHERE expires_at < :now"),
            {"now": now},
        ).rowcount or 0
        prt = db.execute(
            text("DELETE FROM password_reset_tokens WHERE expires_at < :now"),
            {"now": now},
        ).rowcount or 0
        ses = db.execute(
            text("DELETE FROM user_sessions WHERE expires_at < :now"),
            {"now": now},
        ).rowcount or 0
        db.commit()
        return {
            "verification_otps": int(otp),
            "password_reset_tokens": int(prt),
            "user_sessions": int(ses),
        }
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()


# ─────────────────────────────────────────────
# Service delivery OTPs
# ─────────────────────────────────────────────
@celery_app.task(
    name="tasks.maintenance.expire_stale_delivery_otps",
    bind=True,
    max_retries=2,
    default_retry_delay=120,
)
def expire_stale_delivery_otps(self):
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        result = db.execute(
            text(
                """
                UPDATE service_delivery_otps
                   SET status = 'expired'
                 WHERE status = 'active'
                   AND expires_at IS NOT NULL
                   AND expires_at < :now
                """
            ),
            {"now": now},
        )
        db.commit()
        return {"expired_delivery_otps": int(result.rowcount or 0)}
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()


# ─────────────────────────────────────────────
# Analytics retention
# ─────────────────────────────────────────────
@celery_app.task(
    name="tasks.maintenance.prune_old_page_views",
    bind=True,
    max_retries=1,
    default_retry_delay=600,
)
def prune_old_page_views(self, retention_days: int = 90):
    db = SessionLocal()
    try:
        cutoff = datetime.utcnow() - timedelta(days=retention_days)
        result = db.execute(
            text("DELETE FROM page_views WHERE created_at < :cutoff"),
            {"cutoff": cutoff},
        )
        db.commit()
        return {"deleted_page_views": int(result.rowcount or 0),
                "retention_days": retention_days}
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()


# ─────────────────────────────────────────────
# Reliability infra: expire idempotency keys & old job rows
# ─────────────────────────────────────────────
@celery_app.task(
    name="tasks.maintenance.purge_expired_idempotency_keys",
    bind=True,
    max_retries=1,
    default_retry_delay=600,
)
def purge_expired_idempotency_keys(self):
    """Drop ``idempotency_keys`` rows whose 24h replay window has passed."""
    db = SessionLocal()
    try:
        result = db.execute(text("DELETE FROM idempotency_keys WHERE expires_at < NOW()"))
        db.commit()
        return {"deleted_idempotency_keys": int(result.rowcount or 0)}
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()


@celery_app.task(
    name="tasks.maintenance.purge_old_job_status",
    bind=True,
    max_retries=1,
    default_retry_delay=600,
)
def purge_old_job_status(self, retention_days: int = 30):
    """Trim ``job_status`` rows that finished more than ``retention_days`` ago.

    Dead-lettered rows are preserved (admin may still want to inspect them).
    """
    db = SessionLocal()
    try:
        cutoff = datetime.utcnow() - timedelta(days=retention_days)
        result = db.execute(
            text(
                """
                DELETE FROM job_status
                 WHERE finished_at IS NOT NULL
                   AND finished_at < :cutoff
                   AND status <> 'dead_lettered'
                """
            ),
            {"cutoff": cutoff},
        )
        db.commit()
        return {"deleted_job_status_rows": int(result.rowcount or 0)}
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()
