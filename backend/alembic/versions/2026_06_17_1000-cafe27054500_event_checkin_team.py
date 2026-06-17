"""event_checkin_team: dedicated authorization for guest & ticket check-in.

Adds three new tables and extends the existing attendee table with
audit columns so every check-in records who performed it and under
which redeemed access session.

Tables:
- event_checkin_codes: hashed access codes per event (one active at a time)
- event_checkin_team: Nuru users explicitly authorized to scan for an event
- event_checkin_sessions: active redeemed sessions (the "logged-in scanner")

Attendee additions:
- checked_in_by_user_id, checkin_session_id, checkin_code_id, checkin_device_ref,
  checkin_failure_reason
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054500"
down_revision: Union[str, None] = "cafe27054400"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS event_checkin_codes (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            event_id uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
            code_hash text NOT NULL,
            code_prefix text NOT NULL,
            status text NOT NULL DEFAULT 'active',
            created_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            revoked_at timestamp,
            expires_at timestamp,
            created_at timestamp NOT NULL DEFAULT now(),
            updated_at timestamp NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS ix_checkin_codes_event ON event_checkin_codes(event_id);
        CREATE UNIQUE INDEX IF NOT EXISTS ux_checkin_codes_one_active
            ON event_checkin_codes(event_id) WHERE status = 'active';

        CREATE TABLE IF NOT EXISTS event_checkin_team (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            event_id uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            added_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            status text NOT NULL DEFAULT 'active',
            removed_at timestamp,
            created_at timestamp NOT NULL DEFAULT now(),
            updated_at timestamp NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS ix_checkin_team_event ON event_checkin_team(event_id);
        CREATE UNIQUE INDEX IF NOT EXISTS ux_checkin_team_active_member
            ON event_checkin_team(event_id, user_id) WHERE status = 'active';

        CREATE TABLE IF NOT EXISTS event_checkin_sessions (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            event_id uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
            code_id uuid REFERENCES event_checkin_codes(id) ON DELETE SET NULL,
            user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            device_label text,
            session_token text NOT NULL UNIQUE,
            status text NOT NULL DEFAULT 'active',
            started_at timestamp NOT NULL DEFAULT now(),
            last_seen_at timestamp NOT NULL DEFAULT now(),
            ended_at timestamp,
            created_at timestamp NOT NULL DEFAULT now(),
            updated_at timestamp NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS ix_checkin_sessions_event ON event_checkin_sessions(event_id);
        CREATE INDEX IF NOT EXISTS ix_checkin_sessions_user ON event_checkin_sessions(user_id);

        ALTER TABLE event_attendees
            ADD COLUMN IF NOT EXISTS checked_in_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_session_id uuid REFERENCES event_checkin_sessions(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_code_id uuid REFERENCES event_checkin_codes(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_device_ref text,
            ADD COLUMN IF NOT EXISTS checkin_failure_reason text;

        ALTER TABLE event_tickets
            ADD COLUMN IF NOT EXISTS checked_in_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_session_id uuid REFERENCES event_checkin_sessions(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_code_id uuid REFERENCES event_checkin_codes(id) ON DELETE SET NULL,
            ADD COLUMN IF NOT EXISTS checkin_device_ref text,
            ADD COLUMN IF NOT EXISTS checkin_failure_reason text;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE event_tickets
            DROP COLUMN IF EXISTS checkin_failure_reason,
            DROP COLUMN IF EXISTS checkin_device_ref,
            DROP COLUMN IF EXISTS checkin_code_id,
            DROP COLUMN IF EXISTS checkin_session_id,
            DROP COLUMN IF EXISTS checked_in_by_user_id;
        ALTER TABLE event_attendees
            DROP COLUMN IF EXISTS checkin_failure_reason,
            DROP COLUMN IF EXISTS checkin_device_ref,
            DROP COLUMN IF EXISTS checkin_code_id,
            DROP COLUMN IF EXISTS checkin_session_id,
            DROP COLUMN IF EXISTS checked_in_by_user_id;
        DROP TABLE IF EXISTS event_checkin_sessions;
        DROP TABLE IF EXISTS event_checkin_team;
        DROP TABLE IF EXISTS event_checkin_codes;
        """
    )

