"""Safety net: ensure check-in audit columns exist on event_tickets / event_attendees.

The columns were originally introduced by revision ``cafe27054500``
(``event_checkin_team``). This migration re-applies the column adds
idempotently so production deployments that landed on an earlier head
cannot end up with ORM models that reference missing columns. It is a
no-op when the columns are already present.
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054800"
down_revision: Union[str, None] = "cafe27054700"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE event_tickets
            ADD COLUMN IF NOT EXISTS checked_in_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_session_id uuid REFERENCES event_checkin_sessions(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_code_id uuid REFERENCES event_checkin_codes(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_device_ref text,
            ADD COLUMN IF NOT EXISTS checkin_failure_reason text;

        ALTER TABLE event_attendees
            ADD COLUMN IF NOT EXISTS checked_in_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_session_id uuid REFERENCES event_checkin_sessions(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_code_id uuid REFERENCES event_checkin_codes(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_device_ref text,
            ADD COLUMN IF NOT EXISTS checkin_failure_reason text;
        """
    )


def downgrade() -> None:
    # No-op: the canonical owner of these columns is cafe27054500.
    pass
