"""event_attendees: add follow_up_label for visual call/outreach hints.

Organizers tagging guests they're chasing for RSVP (e.g. "not reachable",
"call later") need a quick visual label. This is UI-only metadata — not
included in reports, and not part of any business logic.
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054700"
down_revision: Union[str, None] = "cafe27054600"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE event_attendees
            ADD COLUMN IF NOT EXISTS follow_up_label text;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE event_attendees DROP COLUMN IF EXISTS follow_up_label;
        """
    )
