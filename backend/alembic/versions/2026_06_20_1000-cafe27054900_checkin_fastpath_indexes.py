"""Fast-path indexes for live event check-in.

Adds narrow / partial indexes used by the optimized check-in endpoints.
The QR + manual check-in path must hit indexed lookups only — sequential
scans are not acceptable at the gate. All statements are IF NOT EXISTS so
the migration is safe to re-run.

Targets:
  - event_tickets(event_id, ticket_code)         -> QR lookup by code
  - event_attendees(event_id, invitation_id)      -> invitation -> attendee
  - event_invitations(event_id, invitation_code)  -> invitation by code
  - partial: event_tickets WHERE checked_in=false -> pending-only fast path
  - partial: event_attendees WHERE checked_in=false
  - event_tickets(event_id, checked_in_at DESC)   -> recent scans
  - event_attendees(event_id, checked_in_at DESC)
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054900"
down_revision: Union[str, None] = "cafe27054800"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


STATEMENTS = [
    # Direct lookup keys for the fast-path scanner.
    "CREATE INDEX IF NOT EXISTS idx_event_tickets_event_code ON event_tickets (event_id, ticket_code)",
    "CREATE INDEX IF NOT EXISTS idx_event_attendees_event_invitation ON event_attendees (event_id, invitation_id)",
    "CREATE INDEX IF NOT EXISTS idx_event_invitations_event_code ON event_invitations (event_id, invitation_code)",

    # Partial indexes restricted to rows that are still scannable. These
    # stay tiny even on huge events, so the planner picks them for the
    # pending-only counts and the atomic UPDATE ... WHERE checked_in=false.
    "CREATE INDEX IF NOT EXISTS idx_event_tickets_pending ON event_tickets (event_id) WHERE checked_in = false",
    "CREATE INDEX IF NOT EXISTS idx_event_attendees_pending ON event_attendees (event_id) WHERE checked_in = false",

    # Recent-scan ordering for the scanner header.
    "CREATE INDEX IF NOT EXISTS idx_event_tickets_event_checked_at ON event_tickets (event_id, checked_in_at DESC) WHERE checked_in = true",
    "CREATE INDEX IF NOT EXISTS idx_event_attendees_event_checked_at ON event_attendees (event_id, checked_in_at DESC) WHERE checked_in = true",
]


def upgrade() -> None:
    for stmt in STATEMENTS:
        op.execute(stmt)
    op.execute("ANALYZE event_tickets")
    op.execute("ANALYZE event_attendees")
    op.execute("ANALYZE event_invitations")


def downgrade() -> None:
    for name in (
        "idx_event_tickets_event_code",
        "idx_event_attendees_event_invitation",
        "idx_event_invitations_event_code",
        "idx_event_tickets_pending",
        "idx_event_attendees_pending",
        "idx_event_tickets_event_checked_at",
        "idx_event_attendees_event_checked_at",
    ):
        op.execute(f"DROP INDEX IF EXISTS {name}")
