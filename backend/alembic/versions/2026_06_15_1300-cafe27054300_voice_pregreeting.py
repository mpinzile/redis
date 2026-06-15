"""voice_call_jobs: per-job pre-generated greeting audio.

Adds three optional columns used by the pre-greeting feature so the
recipient hears a personalised Tanzanian-Swahili greeting the instant
they pick up the call, while Gemini Live finishes its handshake in the
background.

* ``greeting_text``  — exact text rendered into audio (for logs / tests).
* ``greeting_audio`` — raw PCM16 mono bytes @ 24000 Hz from Gemini TTS.
* ``greeting_audio_mime`` — wire format (e.g. ``audio/pcm;rate=24000``).
"""
from typing import Sequence, Union
from alembic import op


revision: str = "cafe27054300"
down_revision: Union[str, None] = "cafe27054200"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE voice_call_jobs
            ADD COLUMN IF NOT EXISTS greeting_text text,
            ADD COLUMN IF NOT EXISTS greeting_audio bytea,
            ADD COLUMN IF NOT EXISTS greeting_audio_mime text;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE voice_call_jobs
            DROP COLUMN IF EXISTS greeting_audio_mime,
            DROP COLUMN IF EXISTS greeting_audio,
            DROP COLUMN IF EXISTS greeting_text;
        """
    )
