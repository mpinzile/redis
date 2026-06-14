"""Add per-event display_name override on event_contributors

A contributor record is global to a Nuru user (identified by phone), but
the *display name* shown inside an event must be event-specific. Adding
the same phone to Event A as "Mama John" and to Event B as "John Doe"
should NOT mutate the global address-book name.

This migration adds a nullable ``display_name`` column and backfills it
with the current global ``user_contributors.name`` so existing rows keep
rendering identically until an organiser edits them per event.

Revision ID: cafe27053800
Revises: cafe27053700
"""
from alembic import op
import sqlalchemy as sa


revision = "cafe27053800"
down_revision = "cafe27053700"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "event_contributors",
        sa.Column("display_name", sa.Text(), nullable=True),
    )
    # Backfill from the current global contributor name so nothing visibly
    # changes until an organiser explicitly overrides a name per event.
    op.execute(
        """
        UPDATE event_contributors ec
        SET display_name = uc.name
        FROM user_contributors uc
        WHERE ec.contributor_id = uc.id
          AND ec.display_name IS NULL
          AND uc.name IS NOT NULL
        """
    )


def downgrade() -> None:
    op.drop_column("event_contributors", "display_name")
