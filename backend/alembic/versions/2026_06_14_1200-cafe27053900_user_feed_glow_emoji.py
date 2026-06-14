"""Add optional emoji column to user_feed_glows

Glows can now be any emoji (❤️ default, 😂, 🎉, 🔥, …). The column is
nullable for backward compatibility — NULL means the legacy default heart.
A partial index keeps emoji-usage analytics cheap.

Revision ID: cafe27053900
Revises: cafe27053800
"""
from alembic import op
import sqlalchemy as sa


revision = "cafe27053900"
down_revision = "cafe27053800"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_feed_glows",
        sa.Column("emoji", sa.String(length=16), nullable=True),
    )
    op.create_index(
        "idx_user_feed_glows_emoji",
        "user_feed_glows",
        ["emoji"],
        unique=False,
        postgresql_where=sa.text("emoji IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("idx_user_feed_glows_emoji", table_name="user_feed_glows")
    op.drop_column("user_feed_glows", "emoji")
