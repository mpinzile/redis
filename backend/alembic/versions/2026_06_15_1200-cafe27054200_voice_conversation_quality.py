"""voice_call_logs: conversation quality fields (Phase 11)

Revision ID: cafe27054200
Revises: cafe27054100
Create Date: 2026-06-15 12:00:00

Adds optional fields used by the Natural Conversation Handling layer
(see nuru_voice.md Phase 11). All columns are nullable so existing rows
remain valid and existing code paths do not need to change.
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054200"
down_revision: Union[str, None] = "cafe27054100"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE voice_call_logs
            ADD COLUMN IF NOT EXISTS conversation_quality text,
            ADD COLUMN IF NOT EXISTS detected_mood text,
            ADD COLUMN IF NOT EXISTS noise_detected boolean,
            ADD COLUMN IF NOT EXISTS interruption_count integer NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS silence_count integer NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS clarification_count integer NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS final_confidence numeric(4,3),
            ADD COLUMN IF NOT EXISTS human_follow_up_reason text;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE voice_call_logs
            DROP COLUMN IF EXISTS human_follow_up_reason,
            DROP COLUMN IF EXISTS final_confidence,
            DROP COLUMN IF EXISTS clarification_count,
            DROP COLUMN IF EXISTS silence_count,
            DROP COLUMN IF EXISTS interruption_count,
            DROP COLUMN IF EXISTS noise_detected,
            DROP COLUMN IF EXISTS detected_mood,
            DROP COLUMN IF EXISTS conversation_quality;
        """
    )
