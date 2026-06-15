"""Voice Assistant feature flag (admin-controlled kill switch).

Single-row table (``voice_feature_settings``). When ``enabled`` is False
the backend rejects every new outbound call/campaign action with HTTP
503 and a polite message, which web and mobile surface to the user.
"""
from __future__ import annotations

from sqlalchemy import Column, Boolean, Text, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from core.base import Base


class VoiceFeatureSetting(Base):
    """Global on/off switch for the Nuru Voice Assistant.

    Only one row is ever expected (enforced via the ``singleton`` column).
    Admins toggle it from the admin Voice Calls page.
    """
    __tablename__ = "voice_feature_settings"

    id = Column(UUID(as_uuid=True), primary_key=True,
                server_default=func.gen_random_uuid())
    # Always the literal string "global" so a UNIQUE index keeps the
    # table to a single row regardless of how many writes happen.
    singleton = Column(Text, nullable=False, unique=True,
                       server_default="global")

    enabled = Column(Boolean, nullable=False, server_default="true")

    # Polite, user-facing messages shown on web + mobile when disabled.
    # Two languages so we can show Swahili first to TZ users.
    disabled_message_en = Column(
        Text,
        nullable=False,
        server_default=(
            "Smart RSVP Calls are temporarily unavailable. "
            "The Nuru team has paused this feature for maintenance and "
            "will bring it back online shortly. Thank you for your patience."
        ),
    )
    disabled_message_sw = Column(
        Text,
        nullable=False,
        server_default=(
            "Huduma ya Simu Mahiri za RSVP imesimamishwa kwa muda. "
            "Timu ya Nuru inafanya matengenezo na itarudisha huduma hii "
            "hivi karibuni. Asante kwa uvumilivu wako."
        ),
    )

    updated_by_user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at = Column(DateTime, nullable=False, server_default=func.now())
    updated_at = Column(DateTime, nullable=False, server_default=func.now(),
                        onupdate=func.now())
