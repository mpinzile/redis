from sqlalchemy import Column, Boolean, ForeignKey, DateTime, Text, Enum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from core.base import Base
from models.enums import RSVPStatusEnum, GuestTypeEnum


# ──────────────────────────────────────────────
# Event Invitations & Attendees
# ──────────────────────────────────────────────

class EventInvitation(Base):
    __tablename__ = 'event_invitations'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'))
    guest_type = Column(Enum(GuestTypeEnum, name="guest_type_enum"), default=GuestTypeEnum.user)
    invited_user_id = Column(UUID(as_uuid=True), nullable=True)
    contributor_id = Column(UUID(as_uuid=True), ForeignKey('user_contributors.id', ondelete='SET NULL'), nullable=True)
    guest_name = Column(Text, nullable=True)
    invited_by_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    invitation_code = Column(Text, unique=True)
    rsvp_status = Column(Enum(RSVPStatusEnum, name="rsvp_status_enum"), default=RSVPStatusEnum.pending)
    invited_at = Column(DateTime, server_default=func.now())
    rsvp_at = Column(DateTime)
    notes = Column(Text)
    sent_via = Column(Text)
    sent_at = Column(DateTime)
    reminder_sent_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="invitations")
    invited_user = relationship("User", back_populates="event_invitations_received", foreign_keys=[invited_user_id], primaryjoin="EventInvitation.invited_user_id == User.id")
    invited_by_user = relationship("User", back_populates="event_invitations_sent", foreign_keys=[invited_by_user_id])
    contributor = relationship("UserContributor", foreign_keys=[contributor_id])
    attendees = relationship("EventAttendee", back_populates="invitation")


class EventAttendee(Base):
    __tablename__ = 'event_attendees'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'))
    guest_type = Column(Enum(GuestTypeEnum, name="guest_type_enum"), default=GuestTypeEnum.user)
    attendee_id = Column(UUID(as_uuid=True), nullable=True)
    contributor_id = Column(UUID(as_uuid=True), ForeignKey('user_contributors.id', ondelete='SET NULL'), nullable=True)
    guest_name = Column(Text, nullable=True)
    guest_phone = Column(Text, nullable=True)
    guest_email = Column(Text, nullable=True)
    # Optional display label used on invitation cards. Falls back to the
    # resolved full name when blank. See alembic cafe27052400.
    common_name = Column(Text, nullable=True)
    invitation_id = Column(UUID(as_uuid=True), ForeignKey('event_invitations.id', ondelete='SET NULL'))
    rsvp_status = Column(Enum(RSVPStatusEnum, name="rsvp_status_enum"), default=RSVPStatusEnum.pending)
    checked_in = Column(Boolean, default=False)
    checked_in_at = Column(DateTime)
    checked_in_by_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    checkin_session_id = Column(UUID(as_uuid=True), ForeignKey('event_checkin_sessions.id', ondelete='SET NULL'), nullable=True)
    checkin_code_id = Column(UUID(as_uuid=True), ForeignKey('event_checkin_codes.id', ondelete='SET NULL'), nullable=True)
    checkin_device_ref = Column(Text, nullable=True)
    checkin_failure_reason = Column(Text, nullable=True)
    nuru_card_id = Column(UUID(as_uuid=True), ForeignKey('nuru_cards.id', ondelete='SET NULL'))
    meal_preference = Column(Text)
    dietary_restrictions = Column(Text)
    special_requests = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="attendees")
    attendee = relationship("User", back_populates="event_attendances", foreign_keys=[attendee_id], primaryjoin="EventAttendee.attendee_id == User.id")
    contributor = relationship("UserContributor", foreign_keys=[contributor_id])
    invitation = relationship("EventInvitation", back_populates="attendees")
    nuru_card = relationship("NuruCard", back_populates="event_attendees")
    plus_ones = relationship("EventGuestPlusOne", back_populates="attendee")


class AttendeeProfile(Base):
    __tablename__ = 'attendee_profiles'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    rsvp_code = Column(Text, unique=True)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    user = relationship("User", back_populates="attendee_profile")


class EventGuestPlusOne(Base):
    __tablename__ = 'event_guest_plus_ones'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    attendee_id = Column(UUID(as_uuid=True), ForeignKey('event_attendees.id', ondelete='CASCADE'), nullable=False)
    name = Column(Text, nullable=False)
    email = Column(Text)
    phone = Column(Text)
    meal_preference = Column(Text)
    checked_in = Column(Boolean, default=False)
    checked_in_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    attendee = relationship("EventAttendee", back_populates="plus_ones")
