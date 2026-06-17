"""event_checkin_codes: store plain code so we can re-share with newly added team members.

The hash is still used for redemption matching; the plain value is only
read server-side when we need to deliver the code via WhatsApp/SMS to a
team member that was just added by the organizer.
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054600"
down_revision: Union[str, None] = "cafe27054500"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE event_checkin_codes
            ADD COLUMN IF NOT EXISTS code_plain text;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE event_checkin_codes DROP COLUMN IF EXISTS code_plain;
        """
    )
