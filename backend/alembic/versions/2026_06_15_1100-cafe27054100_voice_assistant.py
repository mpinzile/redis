"""voice assistant tables (campaigns, jobs, logs, opt-outs)

Revision ID: cafe27054100
Revises: cafe27054000
Create Date: 2026-06-15 11:00:00

Adds the four tables that back Nuru Voice Assistant / Smart RSVP Calls
(see nuru_voice.md Phase 2). All names are prefixed ``voice_`` to keep
them clearly separate from the existing ``call_logs`` table used by the
1:1 LiveKit calls feature.
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054100"
down_revision: Union[str, None] = "cafe27054000"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS voice_campaigns (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            event_id uuid REFERENCES events(id) ON DELETE CASCADE,
            owner_id uuid REFERENCES users(id) ON DELETE SET NULL,
            purpose text NOT NULL DEFAULT 'rsvp',
            language text NOT NULL DEFAULT 'sw',
            status text NOT NULL DEFAULT 'draft',
            title text,
            notes text,
            estimated_cost_usd numeric(10,4),
            started_at timestamp,
            completed_at timestamp,
            created_at timestamp NOT NULL DEFAULT now(),
            updated_at timestamp NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS idx_voice_campaigns_event
            ON voice_campaigns(event_id);
        CREATE INDEX IF NOT EXISTS idx_voice_campaigns_owner_status
            ON voice_campaigns(owner_id, status);

        CREATE TABLE IF NOT EXISTS voice_call_jobs (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            campaign_id uuid NOT NULL REFERENCES voice_campaigns(id) ON DELETE CASCADE,
            recipient_type text NOT NULL DEFAULT 'guest',
            recipient_ref_id uuid,
            recipient_name text NOT NULL DEFAULT '',
            phone_e164 text NOT NULL,
            country text,
            timezone text,
            language text,
            status text NOT NULL DEFAULT 'pending',
            block_reason text,
            attempt integer NOT NULL DEFAULT 0,
            max_attempts integer NOT NULL DEFAULT 1,
            scheduled_at timestamp,
            next_retry_at timestamp,
            last_called_at timestamp,
            ai_outcome text,
            ai_confidence numeric(4,3),
            summary text,
            extra jsonb,
            created_at timestamp NOT NULL DEFAULT now(),
            updated_at timestamp NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS idx_voice_call_jobs_campaign_status
            ON voice_call_jobs(campaign_id, status);
        CREATE INDEX IF NOT EXISTS idx_voice_call_jobs_phone
            ON voice_call_jobs(phone_e164);
        CREATE INDEX IF NOT EXISTS idx_voice_call_jobs_next_retry
            ON voice_call_jobs(next_retry_at);

        CREATE TABLE IF NOT EXISTS voice_call_logs (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            job_id uuid NOT NULL REFERENCES voice_call_jobs(id) ON DELETE CASCADE,
            provider text NOT NULL DEFAULT 'twilio',
            provider_call_sid text UNIQUE,
            status text NOT NULL DEFAULT 'queued',
            end_reason text,
            started_at timestamp,
            answered_at timestamp,
            ended_at timestamp,
            duration_seconds integer NOT NULL DEFAULT 0,
            cost_estimate_usd numeric(10,4),
            recording_url text,
            transcript text,
            summary text,
            ai_outcome text,
            ai_confidence numeric(4,3),
            ai_tool_calls jsonb,
            error_code text,
            error_message text,
            created_at timestamp NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS idx_voice_call_logs_job
            ON voice_call_logs(job_id);
        CREATE INDEX IF NOT EXISTS idx_voice_call_logs_provider_sid
            ON voice_call_logs(provider, provider_call_sid);

        CREATE TABLE IF NOT EXISTS voice_opt_outs (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            phone_e164 text NOT NULL,
            reason text,
            source text NOT NULL DEFAULT 'recipient',
            added_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            created_at timestamp NOT NULL DEFAULT now(),
            CONSTRAINT uq_voice_opt_outs_phone UNIQUE (phone_e164)
        );
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP TABLE IF EXISTS voice_opt_outs;
        DROP TABLE IF EXISTS voice_call_logs;
        DROP TABLE IF EXISTS voice_call_jobs;
        DROP TABLE IF EXISTS voice_campaigns;
        """
    )
