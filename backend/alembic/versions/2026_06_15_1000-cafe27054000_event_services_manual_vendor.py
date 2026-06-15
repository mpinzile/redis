"""event_services manual vendor support

Revision ID: cafe27054000
Revises: cafe27053900
Create Date: 2026-06-15 10:00:00
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054000"
down_revision: Union[str, None] = "cafe27053900"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE event_services
            ADD COLUMN IF NOT EXISTS is_manual boolean NOT NULL DEFAULT false,
            ADD COLUMN IF NOT EXISTS manual_vendor_name text,
            ADD COLUMN IF NOT EXISTS manual_vendor_phone text,
            ADD COLUMN IF NOT EXISTS manual_vendor_email text,
            ADD COLUMN IF NOT EXISTS manual_vendor_category_id uuid REFERENCES service_categories(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS manual_vendor_notes text;
        """
    )
    # service_id was NOT NULL; manual vendors don't have a registered service_type.
    op.execute("ALTER TABLE event_services ALTER COLUMN service_id DROP NOT NULL;")
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_event_services_event_manual "
        "ON event_services(event_id, is_manual);"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_event_services_event_manual;")
    op.execute(
        """
        ALTER TABLE event_services
            DROP COLUMN IF EXISTS manual_vendor_notes,
            DROP COLUMN IF EXISTS manual_vendor_category_id,
            DROP COLUMN IF EXISTS manual_vendor_email,
            DROP COLUMN IF EXISTS manual_vendor_phone,
            DROP COLUMN IF EXISTS manual_vendor_name,
            DROP COLUMN IF EXISTS is_manual;
        """
    )
