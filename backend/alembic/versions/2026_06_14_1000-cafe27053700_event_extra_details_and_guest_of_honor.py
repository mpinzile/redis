"""Event extra_details (JSONB list of {label, details}) and guest_of_honor (TEXT)

Replaces the rigid ``dress_code`` / ``special_instructions`` pair on the
event creation flow with a user-defined list of label+details pairs so
organisers can describe any extra section they want (Dress code, Parking,
Gifts, Theme, …). The legacy columns stay in place for backwards
compatibility — the UI just stops writing to them. A new ``guest_of_honor``
free-text column captures the named guest of honor when applicable.

Revision ID: cafe27053700
Revises: cafe27053600
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "cafe27053700"
down_revision = "cafe27053600"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "events",
        sa.Column("extra_details", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    )
    op.add_column(
        "events",
        sa.Column("guest_of_honor", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("events", "guest_of_honor")
    op.drop_column("events", "extra_details")
