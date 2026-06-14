from sqlalchemy import Column, Boolean, ForeignKey, DateTime, Numeric, Text, Enum, UniqueConstraint, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from core.base import Base
from models.enums import PaymentMethodEnum, ContributionStatusEnum


# ──────────────────────────────────────────────
# Contributors & Contributions
# ──────────────────────────────────────────────

class UserContributor(Base):
    __tablename__ = 'user_contributors'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    # When the contributor is itself a registered Nuru user, link them so they
    # can see this contribution in their "My Contributions" tab and self-pay.
    contributor_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True, index=True)
    name = Column(Text, nullable=False)
    # Optional human-friendly label used on invitation cards (e.g.
    # "Mr & Mrs Mpinzile"). Falls back to ``name`` when empty.
    common_name = Column(Text, nullable=True)
    email = Column(Text)
    phone = Column(Text)
    notes = Column(Text)
    # Default secondary contact + notification routing (comms-only). These act
    # as defaults when the contributor is added to an event; the per-event
    # EventContributor row keeps its own override. secondary_phone is NEVER
    # used to map a Nuru user account or for any other feature.
    secondary_phone = Column(Text)
    notify_target = Column(Text, nullable=False, server_default='primary')
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint('user_id', 'phone', name='uq_user_contributor_phone'),
    )

    # Relationships
    user = relationship("User", foreign_keys=[user_id], back_populates="contributors")
    contributor_user = relationship("User", foreign_keys=[contributor_user_id])
    event_contributors = relationship("EventContributor", back_populates="contributor")


class EventContributionTarget(Base):
    __tablename__ = 'event_contribution_targets'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    target_amount = Column(Numeric, nullable=False)
    description = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="contribution_targets")


class EventContributor(Base):
    __tablename__ = 'event_contributors'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    contributor_id = Column(UUID(as_uuid=True), ForeignKey('user_contributors.id', ondelete='CASCADE'), nullable=False)
    # Event-specific override for the contributor's display name. Falls back
    # to the global ``user_contributors.name`` when NULL. Letting an event
    # show "Mama John" without renaming the global address-book entry is the
    # whole reason this column exists.
    display_name = Column(Text, nullable=True)
    pledge_amount = Column(Numeric, default=0)
    notes = Column(Text)
    # Optional secondary phone for this contributor on this event, with a
    # routing preference. NEVER used for nuru-user mapping — comms only.
    secondary_phone = Column(Text, nullable=True)
    notify_target = Column(Text, nullable=False, server_default="primary")  # primary|secondary|both
    # Guest payment link: lets a non-Nuru contributor pay via a public URL.
    # Plain token never lives in DB — only the SHA-256 hash. The plain value
    # is returned ONCE on generation and embedded in the SMS link.
    share_token_hash = Column(Text, nullable=True, index=True)
    # Plain token persisted so "Share payment link" can return the same URL
    # repeatedly without rotating the SMS/WhatsApp link each time. Token is
    # already public (it lives in messages), so storing it carries no extra
    # exposure beyond what we already disclose to the contributor.
    share_token_plain = Column(Text, nullable=True)
    share_token_created_at = Column(DateTime, nullable=True)
    share_token_expires_at = Column(DateTime, nullable=True)
    share_token_revoked_at = Column(DateTime, nullable=True)
    share_link_last_opened_at = Column(DateTime, nullable=True)
    share_link_sms_last_sent_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint('event_id', 'contributor_id', name='uq_event_contributor'),
    )

    # Relationships
    event = relationship("Event", back_populates="event_contributors")
    contributor = relationship("UserContributor", back_populates="event_contributors")
    contributions = relationship("EventContribution", back_populates="event_contributor")


class EventContribution(Base):
    __tablename__ = 'event_contributions'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    event_contributor_id = Column(UUID(as_uuid=True), ForeignKey('event_contributors.id', ondelete='CASCADE'), nullable=False)
    contributor_name = Column(Text, nullable=False)
    contributor_contact = Column(JSONB)
    amount = Column(Numeric, nullable=False)
    payment_method = Column(Enum(PaymentMethodEnum, name="payment_method_enum"))
    transaction_ref = Column(Text)
    recorded_by = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    # Offline-claim audit fields — populated when a payer declares
    # 'I already paid via another method'. organiser reviews & approves.
    payment_channel = Column(Text, nullable=True)              # mobile_money | bank
    provider_name = Column(Text, nullable=True)                # free-text fallback (e.g. "Other")
    provider_id = Column(UUID(as_uuid=True), ForeignKey('payment_providers.id', ondelete='SET NULL'), nullable=True)
    payer_account = Column(Text, nullable=True)                # phone/account paid from
    receipt_image_url = Column(Text, nullable=True)
    claim_submitted_at = Column(DateTime, nullable=True)
    claim_reviewed_at = Column(DateTime, nullable=True)
    claim_reviewed_by = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    claim_rejection_reason = Column(Text, nullable=True)
    confirmation_status = Column(Enum(ContributionStatusEnum, name="contribution_status_enum"), default=ContributionStatusEnum.confirmed)
    confirmed_at = Column(DateTime, nullable=True)
    contributed_at = Column(DateTime, server_default=func.now())
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        # Lists / totals per event ordered by date
        Index('idx_event_contributions_event_contributed', 'event_id', 'contributed_at'),
        # Per-contributor history
        Index('idx_event_contributions_contributor_date', 'event_contributor_id', 'contributed_at'),
        # Recorder audit trail
        Index('idx_event_contributions_recorder', 'recorded_by'),
    )

    # Relationships
    event = relationship("Event", back_populates="contributions")
    event_contributor = relationship("EventContributor", back_populates="contributions")
    recorder = relationship("User", foreign_keys=[recorded_by])
    thank_you_message = relationship("ContributionThankYouMessage", back_populates="contribution", uselist=False)


class ContributionThankYouMessage(Base):
    __tablename__ = 'contribution_thank_you_messages'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    contribution_id = Column(UUID(as_uuid=True), ForeignKey('event_contributions.id', ondelete='CASCADE'), nullable=False, unique=True)
    message = Column(Text, nullable=False)
    sent_via = Column(Text)
    sent_at = Column(DateTime)
    is_sent = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="thank_you_messages")
    contribution = relationship("EventContribution", back_populates="thank_you_message")