from sqlalchemy import Column, Boolean, ForeignKey, DateTime, Integer, Numeric, Text, Enum, String, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from core.base import Base
from models.enums import EventStatusEnum, PriorityLevelEnum, TicketApprovalStatusEnum


# ──────────────────────────────────────────────
# Event Tables
# ──────────────────────────────────────────────

class EventType(Base):
    __tablename__ = 'event_types'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    name = Column(Text, nullable=False, unique=True)
    description = Column(Text)
    icon = Column(String(50))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    events = relationship("Event", back_populates="event_type")
    event_type_services = relationship("EventTypeService", back_populates="event_type")
    templates = relationship("EventTemplate", back_populates="event_type")


class Event(Base):
    __tablename__ = 'events'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    # Submitter / creator of the event row. Kept for backward compatibility
    # with the rest of the codebase that still reads ``organizer_id``.
    organizer_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    # Actual event OWNER (the person the event is for). May differ from
    # the creator when an event is created on behalf of someone else.
    # Backfilled to ``organizer_id`` for pre-feature rows.
    event_owner_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True, index=True)
    # Optional display-name override used in any owner-mentioning
    # public communication (WhatsApp/SMS/invitations/etc.). When NULL we
    # fall back to the owner user's full name.
    recognizable_event_owner_name = Column(Text, nullable=True)
    name = Column(Text, nullable=False)
    event_type_id = Column(UUID(as_uuid=True), ForeignKey('event_types.id'))
    description = Column(Text)
    start_date = Column(DateTime)
    start_time = Column(DateTime)
    end_date = Column(DateTime)
    end_time = Column(DateTime)
    expected_guests = Column(Integer)
    location = Column(Text)
    budget = Column(Numeric)
    contributions_total = Column(Numeric, default=0)
    status = Column(Enum(EventStatusEnum, name="event_status_enum"), default=EventStatusEnum.draft)
    currency_id = Column(UUID(as_uuid=True), ForeignKey('currencies.id'))
    cover_image_url = Column(Text)
    is_public = Column(Boolean, default=False)
    sells_tickets = Column(Boolean, default=False)
    ticket_approval_status = Column(Enum(TicketApprovalStatusEnum, name="ticket_approval_status_enum"), default=TicketApprovalStatusEnum.pending)
    ticket_rejection_reason = Column(Text)
    ticket_removed_reason = Column(Text)
    ticket_approved_by = Column(UUID(as_uuid=True))
    ticket_approved_at = Column(DateTime)
    ticket_removed_at = Column(DateTime)
    theme_color = Column(String(7))
    dress_code = Column(String(100))
    special_instructions = Column(Text)
    card_template_id = Column(UUID(as_uuid=True), ForeignKey('invitation_card_templates.id', ondelete='SET NULL'), nullable=True)
    # Built-in invitation template selection (renders identically across web/mobile/download)
    invitation_template_id = Column(Text, nullable=True)
    invitation_accent_color = Column(Text, nullable=True)
    invitation_sample_names = Column(JSONB, nullable=True)
    # Per-template editable copy (headline, host_line, body, footer_note, ...)
    # When NULL the chosen template renders its own defaults.
    invitation_content = Column(JSONB, nullable=True)
    # Optional fallback phone used in contributor reminder/bulk messages
    # (defaults to organiser's phone if NULL).
    reminder_contact_phone = Column(Text, nullable=True)
    # Optional free-text payment instructions for contributors. Included in
    # SMS and WhatsApp messages whenever a contribution target is set or
    # updated. When NULL we render a language-specific default.
    contribution_payment_instructions = Column(Text, nullable=True)
    # Structured "what to expect" entries shown on the public event view.
    what_to_expect = Column(JSONB, nullable=True)
    what_to_expect_notes = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        # Hot paths: list user's events newest-first, filter by status
        Index('idx_events_organizer_start', 'organizer_id', 'start_date'),
        Index('idx_events_organizer_status', 'organizer_id', 'status'),
        Index('idx_events_status_start', 'status', 'start_date'),
        # Public/discover feeds
        Index('idx_events_public_start', 'is_public', 'start_date'),
        # Ticket-approval moderation queue
        Index('idx_events_ticket_approval_status', 'ticket_approval_status'),
        # Created_at desc for chronological sweeps
        Index('idx_events_created_at', 'created_at'),
    )

    # Relationships
    organizer = relationship("User", back_populates="organized_events", foreign_keys=[organizer_id])
    event_owner = relationship("User", foreign_keys=[event_owner_user_id])
    event_type = relationship("EventType", back_populates="events")
    currency = relationship("Currency", back_populates="events")
    images = relationship("EventImage", back_populates="event")
    venue_coordinate = relationship("EventVenueCoordinate", back_populates="event", uselist=False)
    event_setting = relationship("EventSetting", back_populates="event", uselist=False)
    committee_members = relationship("EventCommitteeMember", back_populates="event")
    event_services = relationship("EventService", back_populates="event")
    contribution_targets = relationship("EventContributionTarget", back_populates="event")
    event_contributors = relationship("EventContributor", back_populates="event")
    contributions = relationship("EventContribution", back_populates="event")
    thank_you_messages = relationship("ContributionThankYouMessage", back_populates="event")
    invitations = relationship("EventInvitation", back_populates="event")
    attendees = relationship("EventAttendee", back_populates="event")
    schedule_items = relationship("EventScheduleItem", back_populates="event")
    budget_items = relationship("EventBudgetItem", back_populates="event")
    booking_requests = relationship("ServiceBookingRequest", back_populates="event")
    promoted_events = relationship("PromotedEvent", back_populates="event")
    checklist_items = relationship("EventChecklistItem", back_populates="event")
    expenses = relationship("EventExpense", back_populates="event")
    photo_libraries = relationship("ServicePhotoLibrary", back_populates="event")
    ticket_classes = relationship("EventTicketClass", back_populates="event")
    tickets = relationship("EventTicket", back_populates="event")
    card_template = relationship("InvitationCardTemplate", back_populates="events")
    meetings = relationship("EventMeeting", back_populates="event", cascade="all, delete-orphan")


class EventTypeService(Base):
    __tablename__ = 'event_type_services'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_type_id = Column(UUID(as_uuid=True), ForeignKey('event_types.id', ondelete='CASCADE'), nullable=False)
    service_type_id = Column(UUID(as_uuid=True), ForeignKey('service_types.id', ondelete='CASCADE'), nullable=False)
    priority = Column(Enum(PriorityLevelEnum, name="priority_level_enum"), nullable=False, default=PriorityLevelEnum.medium)
    is_mandatory = Column(Boolean, default=True)
    description = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event_type = relationship("EventType", back_populates="event_type_services")
    service_type = relationship("ServiceType", back_populates="event_type_services")


class EventImage(Base):
    __tablename__ = 'event_images'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'))
    image_url = Column(Text, nullable=False)
    caption = Column(Text)
    is_featured = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="images")


class EventVenueCoordinate(Base):
    __tablename__ = 'event_venue_coordinates'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False, unique=True)
    latitude = Column(Numeric, nullable=False)
    longitude = Column(Numeric, nullable=False)
    formatted_address = Column(Text)
    place_id = Column(Text)
    venue_name = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="venue_coordinate")


class EventSetting(Base):
    __tablename__ = 'event_settings'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False, unique=True)
    rsvp_enabled = Column(Boolean, default=True)
    rsvp_deadline = Column(DateTime)
    allow_plus_ones = Column(Boolean, default=False)
    max_plus_ones = Column(Integer, default=1)
    require_meal_preference = Column(Boolean, default=False)
    meal_options = Column(JSONB, server_default="'[]'::jsonb")
    contributions_enabled = Column(Boolean, default=True)
    contribution_target_amount = Column(Numeric)
    show_contribution_progress = Column(Boolean, default=True)
    allow_anonymous_contributions = Column(Boolean, default=True)
    minimum_contribution = Column(Numeric)
    checkin_enabled = Column(Boolean, default=True)
    allow_nfc_checkin = Column(Boolean, default=True)
    allow_qr_checkin = Column(Boolean, default=True)
    allow_manual_checkin = Column(Boolean, default=True)
    is_public = Column(Boolean, default=False)
    show_guest_list = Column(Boolean, default=False)
    show_committee = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="event_setting")
