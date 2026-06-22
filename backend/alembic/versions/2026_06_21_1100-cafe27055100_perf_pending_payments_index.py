"""Perf: composite index for /payments/pending hot path.

The endpoint filters by ``payer_user_id = X AND status IN (pending, processing)
AND created_at BETWEEN <window>``. The pre-existing single-column index
``ix_transaction_payer`` matched the user filter but forced Postgres to
re-check status + created_at for every transaction the user has ever made,
which on hot users (organizers running events) was costing 800-900ms per
request. A composite (payer_user_id, status, created_at) is order-of-
magnitude faster and supports the ORDER BY ASC directly.

Created as CONCURRENTLY to avoid table locks on production.
"""
from __future__ import annotations

from alembic import op


revision = "cafe27055100"
down_revision = "cafe27055000"
branch_labels = None
depends_on = None


# CONCURRENTLY indexes cannot run inside a transaction block.
def upgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute(
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS "
            "idx_transactions_payer_status_created "
            "ON transactions (payer_user_id, status, created_at)"
        )


def downgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute(
            "DROP INDEX CONCURRENTLY IF EXISTS idx_transactions_payer_status_created"
        )
