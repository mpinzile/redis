"""Check-In Team models: dedicated authorization for guest/ticket scanning."""
from sqlalchemy import Column, ForeignKey, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.base import Base


class EventCheckinCode(Base):
    __tablename__ = "event_checkin_codes"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False, index=True)
    code_hash = Column(Text, nullable=False)
    code_prefix = Column(Text, nullable=False)
    # Plain value is retained server-side so the organizer can re-share the
    # active access code with newly added team members via WhatsApp/SMS
    # without having to rotate it. Never returned in list responses.
    code_plain = Column(Text, nullable=True)
    status = Column(Text, nullable=False, default="active")  # active | revoked | expired
    created_by_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"))
    revoked_at = Column(DateTime)
    expires_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class EventCheckinTeamMember(Base):
    __tablename__ = "event_checkin_team"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    added_by_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"))
    status = Column(Text, nullable=False, default="active")  # active | removed
    removed_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class EventCheckinSession(Base):
    __tablename__ = "event_checkin_sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False, index=True)
    code_id = Column(UUID(as_uuid=True), ForeignKey("event_checkin_codes.id", ondelete="SET NULL"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"))
    device_label = Column(Text)
    session_token = Column(Text, nullable=False, unique=True)
    status = Column(Text, nullable=False, default="active")  # active | ended | revoked
    started_at = Column(DateTime, server_default=func.now())
    last_seen_at = Column(DateTime, server_default=func.now())
    ended_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
