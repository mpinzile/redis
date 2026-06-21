"""Plan 2 reliability infra: job_status, idempotency_keys, dead_letter_jobs.

Three tables that underpin every "instant response, work continues" endpoint:

- ``job_status``        — canonical row per background job. Clients poll
                          ``GET /jobs/{id}`` to learn how a queued action
                          ended. Workers write progress + result.
- ``idempotency_keys``  — one row per (scope, key). Stored result lets us
                          safely replay a POST and return the original
                          response without doing the work twice.
- ``dead_letter_jobs``  — append-only. A Celery task that has exhausted
                          its retry budget writes one row here. Admins
                          can inspect, requeue, or drop them.

Revision ID: cafe27055000
Revises: cafe27054900
"""
from alembic import op
import sqlalchemy as sa  # noqa: F401
from sqlalchemy.dialects.postgresql import JSONB, UUID  # noqa: F401


revision = "cafe27055000"
down_revision = "cafe27054900"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS job_status (
            id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            task_name       text        NOT NULL,
            celery_task_id  text        NULL,
            user_id         uuid        NULL REFERENCES users(id) ON DELETE SET NULL,
            event_id        uuid        NULL,
            scope           text        NULL,
            status          text        NOT NULL DEFAULT 'queued',
            progress        integer     NOT NULL DEFAULT 0,
            total           integer     NULL,
            message         text        NULL,
            result          jsonb       NULL,
            error           text        NULL,
            attempts        integer     NOT NULL DEFAULT 0,
            max_attempts    integer     NOT NULL DEFAULT 5,
            queued_at       timestamptz NOT NULL DEFAULT NOW(),
            started_at      timestamptz NULL,
            finished_at     timestamptz NULL,
            updated_at      timestamptz NOT NULL DEFAULT NOW(),
            CONSTRAINT job_status_status_chk CHECK (
                status IN ('queued','running','succeeded','failed','retrying','dead_lettered','cancelled')
            )
        );
        CREATE INDEX IF NOT EXISTS ix_job_status_user_created
            ON job_status (user_id, queued_at DESC);
        CREATE INDEX IF NOT EXISTS ix_job_status_status_updated
            ON job_status (status, updated_at DESC);
        CREATE INDEX IF NOT EXISTS ix_job_status_task_status
            ON job_status (task_name, status);
        """
    )

    op.execute(
        """
        CREATE TABLE IF NOT EXISTS idempotency_keys (
            id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            scope           text        NOT NULL,
            key             text        NOT NULL,
            user_id         uuid        NULL REFERENCES users(id) ON DELETE CASCADE,
            request_hash    text        NULL,
            status          text        NOT NULL DEFAULT 'in_progress',
            response_code   integer     NULL,
            response_body   jsonb       NULL,
            job_id          uuid        NULL REFERENCES job_status(id) ON DELETE SET NULL,
            created_at      timestamptz NOT NULL DEFAULT NOW(),
            updated_at      timestamptz NOT NULL DEFAULT NOW(),
            expires_at      timestamptz NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
            CONSTRAINT idempotency_keys_status_chk CHECK (
                status IN ('in_progress','completed','failed')
            )
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_idempotency_scope_key
            ON idempotency_keys (scope, key);
        CREATE INDEX IF NOT EXISTS ix_idempotency_expires
            ON idempotency_keys (expires_at);
        """
    )

    op.execute(
        """
        CREATE TABLE IF NOT EXISTS dead_letter_jobs (
            id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            job_id          uuid        NULL REFERENCES job_status(id) ON DELETE SET NULL,
            task_name       text        NOT NULL,
            payload         jsonb       NOT NULL DEFAULT '{}'::jsonb,
            error           text        NULL,
            traceback       text        NULL,
            attempts        integer     NOT NULL DEFAULT 0,
            first_failed_at timestamptz NOT NULL DEFAULT NOW(),
            last_failed_at  timestamptz NOT NULL DEFAULT NOW(),
            requeued_at     timestamptz NULL,
            requeued_by     uuid        NULL,
            resolved_at     timestamptz NULL,
            resolved_by     uuid        NULL,
            notes           text        NULL
        );
        CREATE INDEX IF NOT EXISTS ix_dlq_unresolved
            ON dead_letter_jobs (last_failed_at DESC)
            WHERE resolved_at IS NULL;
        CREATE INDEX IF NOT EXISTS ix_dlq_task_name
            ON dead_letter_jobs (task_name);
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS dead_letter_jobs;")
    op.execute("DROP TABLE IF EXISTS idempotency_keys;")
    op.execute("DROP TABLE IF EXISTS job_status;")
