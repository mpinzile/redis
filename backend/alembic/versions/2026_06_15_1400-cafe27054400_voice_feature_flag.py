"""voice_feature_settings: admin-controlled on/off switch.

Single-row table that lets Nuru administrators temporarily disable the
Smart RSVP / Voice Assistant feature for everyone. When disabled the
backend rejects new campaign actions with HTTP 503 + a polite message,
which the web and mobile clients surface to the user.
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054400"
down_revision: Union[str, None] = "cafe27054300"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS voice_feature_settings (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            singleton text NOT NULL DEFAULT 'global',
            enabled boolean NOT NULL DEFAULT true,
            disabled_message_en text NOT NULL DEFAULT
                'Smart RSVP Calls are temporarily unavailable. The Nuru team has paused this feature for maintenance and will bring it back online shortly. Thank you for your patience.',
            disabled_message_sw text NOT NULL DEFAULT
                'Huduma ya Simu Mahiri za RSVP imesimamishwa kwa muda. Timu ya Nuru inafanya matengenezo na itarudisha huduma hii hivi karibuni. Asante kwa uvumilivu wako.',
            updated_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            created_at timestamp NOT NULL DEFAULT now(),
            updated_at timestamp NOT NULL DEFAULT now(),
            CONSTRAINT uq_voice_feature_settings_singleton UNIQUE (singleton)
        );

        -- Seed the singleton row (enabled by default).
        INSERT INTO voice_feature_settings (singleton, enabled)
        VALUES ('global', true)
        ON CONFLICT (singleton) DO NOTHING;
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS voice_feature_settings;")
