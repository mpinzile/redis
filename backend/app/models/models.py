from sqlalchemy import Column, Boolean, ForeignKey, DateTime, Integer, Numeric, Text, Enum, UniqueConstraint, String, CheckConstraint, Float, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from core.base import Base
from models.enums import (
    EventStatusEnum,
    PaymentStatusEnum,
    PaymentMethodEnum,
    RSVPStatusEnum,
    VerificationStatusEnum,
    OTPVerificationTypeEnum,
    ConversationTypeEnum,
    EventServiceStatusEnum,
    ServiceAvailabilityEnum,
    NotificationTypeEnum,
    UploadFileTypeEnum,
    PriorityLevelEnum,
    SocialProviderEnum,
    MomentContentTypeEnum,
    MomentPrivacyEnum,
    StickerTypeEnum,
    CardOrderStatusEnum,
    CardTypeEnum,
    ContributionStatusEnum,
    ChatSessionStatusEnum,
    FeedVisibilityEnum,
    GuestTypeEnum,
    ChecklistItemStatusEnum,
    AppealStatusEnum,
    AppealContentTypeEnum,
    PhotoLibraryPrivacyEnum,
    TicketStatusEnum,
    TicketOrderStatusEnum,
    EventShareDurationEnum,
    ServiceMediaTypeEnum,
    BusinessPhoneStatusEnum,
    IssueStatusEnum,
    IssuePriorityEnum,
    TicketApprovalStatusEnum,
)

from models.page_views import PageView  # noqa: F401


# ──────────────────────────────────────────────
# Reference / Lookup Tables
# ──────────────────────────────────────────────

class Currency(Base):
    __tablename__ = 'currencies'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    code = Column(String(3), nullable=False, unique=True)
    name = Column(Text, nullable=False)
    symbol = Column(Text, nullable=False)
    decimal_places = Column(Integer, default=2)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    countries = relationship("Country", back_populates="currency")
    events = relationship("Event", back_populates="currency")
    nuru_card_orders = relationship("NuruCardOrder", back_populates="currency")


class Country(Base):
    __tablename__ = 'countries'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    code = Column(String(2), nullable=False, unique=True)
    name = Column(Text, nullable=False)
    phone_code = Column(Text, nullable=False)
    currency_id = Column(UUID(as_uuid=True), ForeignKey('currencies.id'))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    currency = relationship("Currency", back_populates="countries")
    user_profiles = relationship("UserProfile", back_populates="country")
    nuru_card_orders = relationship("NuruCardOrder", back_populates="delivery_country")


class ServiceCategory(Base):
    __tablename__ = 'service_categories'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    name = Column(Text, nullable=False, unique=True)
    description = Column(Text)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    service_types = relationship("ServiceType", back_populates="category")
    user_services = relationship("UserService", back_populates="category")


class KYCRequirement(Base):
    __tablename__ = 'kyc_requirements'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    name = Column(Text, nullable=False, unique=True)
    description = Column(Text)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    service_kyc_mappings = relationship("ServiceKYCMapping", back_populates="kyc_requirement")
    verification_files = relationship("UserServiceVerificationFile", back_populates="kyc_requirement")
    kyc_statuses = relationship("UserServiceKYCStatus", back_populates="kyc_requirement")


class ServiceType(Base):
    __tablename__ = 'service_types'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    name = Column(Text, nullable=False, unique=True)
    description = Column(Text)
    requires_kyc = Column(Boolean, default=False)
    category_id = Column(UUID(as_uuid=True), ForeignKey('service_categories.id'))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    category = relationship("ServiceCategory", back_populates="service_types")
    service_kyc_mappings = relationship("ServiceKYCMapping", back_populates="service_type")
    event_type_services = relationship("EventTypeService", back_populates="service_type")
    event_services = relationship("EventService", back_populates="service_type")
    user_services = relationship("UserService", back_populates="service_type")


class ServiceKYCMapping(Base):
    __tablename__ = 'service_kyc_mapping'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    service_type_id = Column(UUID(as_uuid=True), ForeignKey('service_types.id', ondelete='CASCADE'))
    kyc_requirement_id = Column(UUID(as_uuid=True), ForeignKey('kyc_requirements.id', ondelete='CASCADE'))
    is_mandatory = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    service_type = relationship("ServiceType", back_populates="service_kyc_mappings")
    kyc_requirement = relationship("KYCRequirement", back_populates="service_kyc_mappings")


class IdentityDocumentRequirement(Base):
    __tablename__ = 'identity_document_requirements'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    name = Column(Text, nullable=False, unique=True)
    description = Column(Text)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user_identity_verifications = relationship("UserIdentityVerification", back_populates="document_type")


# ──────────────────────────────────────────────
# User Tables
# ──────────────────────────────────────────────

class User(Base):
    __tablename__ = 'users'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    first_name = Column(Text, nullable=False)
    last_name = Column(Text, nullable=False)
    username = Column(Text, unique=True)
    email = Column(Text, unique=True)
    phone = Column(Text)
    password_hash = Column(Text)
    is_active = Column(Boolean, default=True)
    is_suspended = Column(Boolean, default=False)
    suspension_reason = Column(Text)
    is_identity_verified = Column(Boolean, default=False)
    is_phone_verified = Column(Boolean, default=False)
    is_email_verified = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # One-to-one relationships
    profile = relationship("UserProfile", back_populates="user", uselist=False)
    privacy_setting = relationship("UserPrivacySetting", back_populates="user", uselist=False)
    two_factor_secret = relationship("UserTwoFactorSecret", back_populates="user", uselist=False)
    settings = relationship("UserSetting", back_populates="user", uselist=False)
    attendee_profile = relationship("AttendeeProfile", back_populates="user", uselist=False)

    # One-to-many relationships
    identity_verifications = relationship("UserIdentityVerification", back_populates="user")
    verification_otps = relationship("UserVerificationOTP", back_populates="user")
    social_accounts = relationship("UserSocialAccount", back_populates="user")
    activity_logs = relationship("UserActivityLog", back_populates="user")
    sessions = relationship("UserSession", back_populates="user")
    password_reset_tokens = relationship("PasswordResetToken", back_populates="user")
    user_achievements = relationship("UserAchievement", back_populates="user")
    name_validation_flags = relationship("NameValidationFlag", back_populates="user")
    nuru_cards = relationship("NuruCard", back_populates="user")
    nuru_card_orders = relationship("NuruCardOrder", back_populates="user")
    community_memberships = relationship("CommunityMember", back_populates="user")
    feeds = relationship("UserFeed", back_populates="user")
    feed_glows = relationship("UserFeedGlow", back_populates="user")
    feed_echoes = relationship("UserFeedEcho", back_populates="user")
    feed_comments = relationship("UserFeedComment", back_populates="user")
    feed_comment_glows = relationship("UserFeedCommentGlow", back_populates="user")
    feed_pinned = relationship("UserFeedPinned", back_populates="user")
    feed_saved = relationship("UserFeedSaved", back_populates="user")
    moments = relationship("UserMoment", back_populates="user")
    moment_views = relationship("UserMomentViewer", back_populates="viewer")
    moment_highlights = relationship("UserMomentHighlight", back_populates="user")
    user_services = relationship("UserService", back_populates="user")
    service_ratings = relationship("UserServiceRating", back_populates="user")
    organized_events = relationship("Event", back_populates="organizer")
    contributors = relationship("UserContributor", foreign_keys="UserContributor.user_id", back_populates="user")
    support_tickets = relationship("SupportTicket", back_populates="user")
    notifications = relationship("Notification", back_populates="recipient")
    booking_requests = relationship("ServiceBookingRequest", back_populates="requester")
    file_uploads = relationship("FileUpload", back_populates="user")

    # Self-referential / multi-FK relationships
    blocks_made = relationship("UserBlock", back_populates="blocker", foreign_keys="[UserBlock.blocker_id]")
    blocks_received = relationship("UserBlock", back_populates="blocked", foreign_keys="[UserBlock.blocked_id]")
    circles = relationship("UserCircle", back_populates="user", foreign_keys="[UserCircle.user_id]")
    circle_memberships = relationship("UserCircle", back_populates="circle_member", foreign_keys="[UserCircle.circle_member_id]")
    followers = relationship("UserFollower", back_populates="following", foreign_keys="[UserFollower.following_id]")
    following = relationship("UserFollower", back_populates="follower", foreign_keys="[UserFollower.follower_id]")
    created_communities = relationship("Community", back_populates="creator")
    feed_sparks = relationship("UserFeedSpark", back_populates="shared_by_user")
    service_verifications_submitted = relationship("UserServiceVerification", back_populates="submitted_by_user")
    event_committee_memberships = relationship("EventCommitteeMember", back_populates="user", foreign_keys="[EventCommitteeMember.user_id]")
    event_committee_assignments = relationship("EventCommitteeMember", back_populates="assigner", foreign_keys="[EventCommitteeMember.assigned_by]")
    event_services_as_provider = relationship("EventService", back_populates="provider_user")
    event_service_payments_received = relationship("EventServicePayment", back_populates="provider_user")
    event_invitations_received = relationship("EventInvitation", back_populates="invited_user", foreign_keys="[EventInvitation.invited_user_id]", primaryjoin="User.id == EventInvitation.invited_user_id")
    event_invitations_sent = relationship("EventInvitation", back_populates="invited_by_user", foreign_keys="[EventInvitation.invited_by_user_id]")
    event_attendances = relationship("EventAttendee", back_populates="attendee", foreign_keys="[EventAttendee.attendee_id]", primaryjoin="User.id == EventAttendee.attendee_id")
    conversations_as_one = relationship("Conversation", back_populates="user_one", foreign_keys="[Conversation.user_one_id]")
    conversations_as_two = relationship("Conversation", back_populates="user_two", foreign_keys="[Conversation.user_two_id]")
    sent_messages = relationship("Message", back_populates="sender")
    support_messages = relationship("SupportMessage", back_populates="sender")
    live_chat_sessions_as_user = relationship("LiveChatSession", back_populates="user", foreign_keys="[LiveChatSession.user_id]")
    live_chat_sessions_as_agent = relationship("LiveChatSession", back_populates="agent", foreign_keys="[LiveChatSession.agent_id]")
    live_chat_messages = relationship("LiveChatMessage", back_populates="sender")
    service_review_helpfuls = relationship("ServiceReviewHelpful", back_populates="user")
    recorded_expenses = relationship("EventExpense", back_populates="recorder", foreign_keys="[EventExpense.recorded_by]")
    issues = relationship("Issue", back_populates="user")


class UserProfile(Base):
    __tablename__ = 'user_profiles'

    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id'), primary_key=True)
    bio = Column(Text)
    profile_picture_url = Column(Text)
    social_links = Column(JSONB)
    country_id = Column(UUID(as_uuid=True), ForeignKey('countries.id'))
    website_url = Column(Text)
    location = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="profile")
    country = relationship("Country", back_populates="user_profiles")


class UserIdentityVerification(Base):
    __tablename__ = 'user_identity_verifications'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    document_type_id = Column(UUID(as_uuid=True), ForeignKey('identity_document_requirements.id'))
    document_number = Column(Text, nullable=False)
    document_file_url = Column(Text)
    verification_status = Column(Enum(VerificationStatusEnum, name="verification_status_enum"), default=VerificationStatusEnum.pending)
    remarks = Column(Text)
    verified_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="identity_verifications")
    document_type = relationship("IdentityDocumentRequirement", back_populates="user_identity_verifications")


class UserVerificationOTP(Base):
    __tablename__ = 'user_verification_otps'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    otp_code = Column(Text, nullable=False)
    verification_type = Column(Enum(OTPVerificationTypeEnum, name="otp_verification_type_enum"), nullable=False)
    is_used = Column(Boolean, default=False)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="verification_otps")


class UserBlock(Base):
    __tablename__ = 'user_blocks'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    blocker_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    blocked_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    reason = Column(Text)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('blocker_id', 'blocked_id', name='uq_user_blocks'),
    )

    # Relationships
    blocker = relationship("User", back_populates="blocks_made", foreign_keys=[blocker_id])
    blocked = relationship("User", back_populates="blocks_received", foreign_keys=[blocked_id])


class UserSocialAccount(Base):
    __tablename__ = 'user_social_accounts'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    provider = Column(Enum(SocialProviderEnum, name="social_provider_enum"), nullable=False)
    provider_user_id = Column(Text, nullable=False)
    provider_email = Column(Text)
    provider_name = Column(Text)
    provider_avatar_url = Column(Text)
    access_token = Column(Text)
    refresh_token = Column(Text)
    token_expires_at = Column(DateTime)
    is_active = Column(Boolean, default=True)
    connected_at = Column(DateTime, server_default=func.now())
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint('user_id', 'provider', name='uq_user_social_provider'),
        UniqueConstraint('provider', 'provider_user_id', name='uq_provider_user'),
    )

    # Relationships
    user = relationship("User", back_populates="social_accounts")


class UserTwoFactorSecret(Base):
    __tablename__ = 'user_two_factor_secrets'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False, unique=True)
    secret_key = Column(Text, nullable=False)
    backup_codes = Column(JSONB, server_default="'[]'::jsonb")
    is_enabled = Column(Boolean, default=False)
    verified_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="two_factor_secret")


class UserPrivacySetting(Base):
    __tablename__ = 'user_privacy_settings'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False, unique=True)
    profile_visibility = Column(Text, server_default='public')
    show_online_status = Column(Boolean, default=True)
    allow_tagging = Column(Boolean, default=True)
    allow_mentions = Column(Boolean, default=True)
    show_activity_status = Column(Boolean, default=True)
    allow_message_requests = Column(Boolean, default=True)
    hide_from_search = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="privacy_setting")


class UserCircle(Base):
    __tablename__ = 'user_circles'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    circle_member_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    mutual_friends_count = Column(Integer, default=0)
    status = Column(String(20), nullable=False, default='pending')
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint('user_id', 'circle_member_id', name='uq_user_circle'),
    )

    # Relationships
    user = relationship("User", back_populates="circles", foreign_keys=[user_id])
    circle_member = relationship("User", back_populates="circle_memberships", foreign_keys=[circle_member_id])


class UserFollower(Base):
    __tablename__ = 'user_followers'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    follower_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    following_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('follower_id', 'following_id', name='uq_user_follower'),
    )

    # Relationships
    follower = relationship("User", back_populates="following", foreign_keys=[follower_id])
    following = relationship("User", back_populates="followers", foreign_keys=[following_id])


class UserSetting(Base):
    __tablename__ = 'user_settings'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), unique=True)
    email_notifications = Column(Boolean, default=True)
    push_notifications = Column(Boolean, default=True)
    glows_echoes_notifications = Column(Boolean, default=True)
    event_invitation_notifications = Column(Boolean, default=True)
    follower_notifications = Column(Boolean, default=True)
    message_notifications = Column(Boolean, default=True)
    profile_visibility = Column(Boolean, default=True)
    private_profile = Column(Boolean, default=False)
    two_factor_enabled = Column(Boolean, default=False)
    dark_mode = Column(Boolean, default=False)
    language = Column(Text, default='en')
    timezone = Column(Text, default='UTC')
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="settings")


class UserActivityLog(Base):
    __tablename__ = 'user_activity_logs'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    activity_type = Column(Text, nullable=False)
    entity_type = Column(Text)
    entity_id = Column(UUID(as_uuid=True))
    ip_address = Column(Text)
    user_agent = Column(Text)
    extra_data = Column(JSONB)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    user = relationship("User", back_populates="activity_logs")


class UserSession(Base):
    __tablename__ = 'user_sessions'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    token_hash = Column(Text, nullable=False)
    device_info = Column(JSONB)
    ip_address = Column(Text)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="sessions")


class PasswordResetToken(Base):
    __tablename__ = 'password_reset_tokens'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    token_hash = Column(Text, nullable=False, unique=True)
    expires_at = Column(DateTime, nullable=False)
    is_used = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    user = relationship("User", back_populates="password_reset_tokens")


class Achievement(Base):
    __tablename__ = 'achievements'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    name = Column(Text, nullable=False, unique=True)
    description = Column(Text)
    icon = Column(Text)
    criteria = Column(JSONB)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    user_achievements = relationship("UserAchievement", back_populates="achievement")


class UserAchievement(Base):
    __tablename__ = 'user_achievements'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    achievement_id = Column(UUID(as_uuid=True), ForeignKey('achievements.id', ondelete='CASCADE'))
    earned_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('user_id', 'achievement_id', name='uq_user_achievement'),
    )

    # Relationships
    user = relationship("User", back_populates="user_achievements")
    achievement = relationship("Achievement", back_populates="user_achievements")


class NameValidationFlag(Base):
    __tablename__ = 'name_validation_flags'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    flagged_first_name = Column(Text)
    flagged_last_name = Column(Text)
    flag_reason = Column(Text, nullable=False)
    is_resolved = Column(Boolean, default=False)
    resolved_by = Column(Text)
    resolved_at = Column(DateTime)
    admin_notified = Column(Boolean, default=False)
    user_notified = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="name_validation_flags")



# Nuru Cards
# ──────────────────────────────────────────────

class NuruCard(Base):
    __tablename__ = 'nuru_cards'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    card_number = Column(String(20), unique=True, nullable=False)
    is_active = Column(Boolean, default=True)
    issued_at = Column(DateTime, server_default=func.now())
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="nuru_cards")
    event_attendees = relationship("EventAttendee", back_populates="nuru_card")


class NuruCardOrder(Base):
    __tablename__ = 'nuru_card_orders'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    card_type = Column(Enum(CardTypeEnum, name="card_type_enum"), default=CardTypeEnum.standard)
    quantity = Column(Integer, default=1)
    delivery_name = Column(Text, nullable=False)
    delivery_phone = Column(Text, nullable=False)
    delivery_address = Column(Text, nullable=False)
    delivery_city = Column(Text, nullable=False)
    delivery_country_id = Column(UUID(as_uuid=True), ForeignKey('countries.id'))
    delivery_postal_code = Column(Text)
    delivery_instructions = Column(Text)
    status = Column(Enum(CardOrderStatusEnum, name="card_order_status_enum"), default=CardOrderStatusEnum.pending)
    tracking_number = Column(Text)
    shipped_at = Column(DateTime)
    delivered_at = Column(DateTime)
    amount = Column(Numeric, nullable=False)
    currency_id = Column(UUID(as_uuid=True), ForeignKey('currencies.id'))
    payment_status = Column(Enum(PaymentStatusEnum, name="payment_status_enum"), default=PaymentStatusEnum.pending)
    payment_ref = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="nuru_card_orders")
    delivery_country = relationship("Country", back_populates="nuru_card_orders")
    currency = relationship("Currency", back_populates="nuru_card_orders")


# ──────────────────────────────────────────────
# Community Tables
# ──────────────────────────────────────────────

class Community(Base):
    __tablename__ = 'communities'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    name = Column(Text, nullable=False)
    description = Column(Text)
    cover_image_url = Column(Text)
    is_public = Column(Boolean, default=True)
    member_count = Column(Integer, default=0)
    created_by = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    creator = relationship("User", back_populates="created_communities")
    members = relationship("CommunityMember", back_populates="community")
    posts = relationship("CommunityPost", back_populates="community")


class CommunityMember(Base):
    __tablename__ = 'community_members'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    community_id = Column(UUID(as_uuid=True), ForeignKey('communities.id', ondelete='CASCADE'))
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    role = Column(Text, default='member')
    joined_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('community_id', 'user_id', name='uq_community_member'),
    )

    # Relationships
    community = relationship("Community", back_populates="members")
    user = relationship("User", back_populates="community_memberships")


class CommunityPost(Base):
    __tablename__ = 'community_posts'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    community_id = Column(UUID(as_uuid=True), ForeignKey('communities.id', ondelete='CASCADE'), nullable=False)
    author_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    content = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    community = relationship("Community", back_populates="posts")
    author = relationship("User")
    images = relationship("CommunityPostImage", back_populates="community_post", foreign_keys="CommunityPostImage.post_id")
    glows = relationship("CommunityPostGlow", back_populates="community_post", foreign_keys="CommunityPostGlow.post_id")


class CommunityPostImage(Base):
    __tablename__ = 'community_post_images'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    post_id = Column(UUID(as_uuid=True), ForeignKey('community_posts.id', ondelete='CASCADE'), nullable=False)
    image_url = Column(Text, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    community_post = relationship("CommunityPost", back_populates="images")


class CommunityPostGlow(Base):
    __tablename__ = 'community_post_glows'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    post_id = Column(UUID(as_uuid=True), ForeignKey('community_posts.id', ondelete='CASCADE'), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('post_id', 'user_id', name='uq_community_post_glow'),
    )

    # Relationships
    community_post = relationship("CommunityPost", back_populates="glows")
    user = relationship("User")


# ──────────────────────────────────────────────
# Feed Tables
# ──────────────────────────────────────────────

class UserFeed(Base):
    __tablename__ = 'user_feeds'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    title = Column(Text)
    content = Column(Text)
    location = Column(Text)
    is_public = Column(Boolean, default=True)
    allow_echo = Column(Boolean, default=True)
    is_active = Column(Boolean, default=True)
    removal_reason = Column(Text)
    visibility = Column(Enum(FeedVisibilityEnum, name="feed_visibility_enum"), default=FeedVisibilityEnum.public)
    glow_count = Column(Integer, default=0)
    echo_count = Column(Integer, default=0)
    spark_count = Column(Integer, default=0)
    video_url = Column(Text)
    video_thumbnail_url = Column(Text)
    # Event share fields
    post_type = Column(Text, default='post')
    shared_event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='SET NULL'))
    share_duration = Column(Enum(EventShareDurationEnum, name="event_share_duration_enum"))
    share_expires_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="feeds")
    images = relationship("UserFeedImage", back_populates="feed")
    glows = relationship("UserFeedGlow", back_populates="feed")
    echoes = relationship("UserFeedEcho", back_populates="feed")
    sparks = relationship("UserFeedSpark", back_populates="feed")
    comments = relationship("UserFeedComment", back_populates="feed")
    pinned_by = relationship("UserFeedPinned", back_populates="feed")
    saved_by = relationship("UserFeedSaved", back_populates="feed")
    shared_event = relationship("Event")


class UserFeedImage(Base):
    __tablename__ = 'user_feed_images'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    feed_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'))
    image_url = Column(Text, nullable=False)
    description = Column(Text)
    is_featured = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    feed = relationship("UserFeed", back_populates="images")


class UserFeedGlow(Base):
    __tablename__ = 'user_feed_glows'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    feed_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'))
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    # Optional reaction emoji. NULL = legacy/default heart.
    emoji = Column(String(16), nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    feed = relationship("UserFeed", back_populates="glows")
    user = relationship("User", back_populates="feed_glows")


class UserFeedEcho(Base):
    __tablename__ = 'user_feed_echoes'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    feed_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'))
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    feed = relationship("UserFeed", back_populates="echoes")
    user = relationship("User", back_populates="feed_echoes")


class UserFeedSpark(Base):
    __tablename__ = 'user_feed_sparks'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    feed_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'))
    shared_by_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id'))
    platform = Column(Text, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    feed = relationship("UserFeed", back_populates="sparks")
    shared_by_user = relationship("User", back_populates="feed_sparks")


class UserFeedComment(Base):
    __tablename__ = 'user_feed_comments'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    feed_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    parent_comment_id = Column(UUID(as_uuid=True), ForeignKey('user_feed_comments.id', ondelete='CASCADE'))
    content = Column(Text, nullable=False)
    glow_count = Column(Integer, default=0)
    reply_count = Column(Integer, default=0)
    is_edited = Column(Boolean, default=False)
    is_pinned = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    feed = relationship("UserFeed", back_populates="comments")
    user = relationship("User", back_populates="feed_comments")
    parent_comment = relationship("UserFeedComment", back_populates="replies", remote_side=[id])
    replies = relationship("UserFeedComment", back_populates="parent_comment")
    comment_glows = relationship("UserFeedCommentGlow", back_populates="comment")


class UserFeedCommentGlow(Base):
    __tablename__ = 'user_feed_comment_glows'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    comment_id = Column(UUID(as_uuid=True), ForeignKey('user_feed_comments.id', ondelete='CASCADE'), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('comment_id', 'user_id', name='uq_comment_glow'),
    )

    # Relationships
    comment = relationship("UserFeedComment", back_populates="comment_glows")
    user = relationship("User", back_populates="feed_comment_glows")


class UserFeedPinned(Base):
    __tablename__ = 'user_feed_pinned'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    feed_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'), nullable=False)
    display_order = Column(Integer, default=0)
    pinned_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('user_id', 'feed_id', name='uq_feed_pinned'),
    )

    # Relationships
    user = relationship("User", back_populates="feed_pinned")
    feed = relationship("UserFeed", back_populates="pinned_by")


class UserFeedSaved(Base):
    __tablename__ = 'user_feed_saved'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    feed_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'), nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('user_id', 'feed_id', name='uq_feed_saved'),
    )

    # Relationships
    user = relationship("User", back_populates="feed_saved")
    feed = relationship("UserFeed", back_populates="saved_by")


# ──────────────────────────────────────────────
# Moments Tables
# ──────────────────────────────────────────────

class UserMoment(Base):
    __tablename__ = 'user_moments'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    content_type = Column(Enum(MomentContentTypeEnum, name="moment_content_type_enum"), nullable=False)
    media_url = Column(Text, nullable=False)
    thumbnail_url = Column(Text)
    caption = Column(Text)
    location = Column(Text)
    privacy = Column(Enum(MomentPrivacyEnum, name="moment_privacy_enum"), default=MomentPrivacyEnum.everyone)
    view_count = Column(Integer, default=0)
    reply_count = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)
    removal_reason = Column(Text)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    user = relationship("User", back_populates="moments")
    stickers = relationship("UserMomentSticker", back_populates="moment")
    viewers = relationship("UserMomentViewer", back_populates="moment")
    highlight_items = relationship("UserMomentHighlightItem", back_populates="moment")


class UserMomentSticker(Base):
    __tablename__ = 'user_moment_stickers'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    moment_id = Column(UUID(as_uuid=True), ForeignKey('user_moments.id', ondelete='CASCADE'), nullable=False)
    sticker_type = Column(Enum(StickerTypeEnum, name="sticker_type_enum"), nullable=False)
    position_x = Column(Numeric, nullable=False)
    position_y = Column(Numeric, nullable=False)
    rotation = Column(Numeric, default=0)
    scale = Column(Numeric, default=1)
    data = Column(JSONB, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    moment = relationship("UserMoment", back_populates="stickers")


class UserMomentViewer(Base):
    __tablename__ = 'user_moment_viewers'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    moment_id = Column(UUID(as_uuid=True), ForeignKey('user_moments.id', ondelete='CASCADE'), nullable=False)
    viewer_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    viewed_at = Column(DateTime, server_default=func.now())
    reaction = Column(Text)
    reacted_at = Column(DateTime)

    __table_args__ = (
        UniqueConstraint('moment_id', 'viewer_id', name='uq_moment_viewer'),
    )

    # Relationships
    moment = relationship("UserMoment", back_populates="viewers")
    viewer = relationship("User", back_populates="moment_views")


class UserMomentHighlight(Base):
    __tablename__ = 'user_moment_highlights'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    title = Column(Text, nullable=False)
    cover_image_url = Column(Text)
    display_order = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="moment_highlights")
    items = relationship("UserMomentHighlightItem", back_populates="highlight")


class UserMomentHighlightItem(Base):
    __tablename__ = 'user_moment_highlight_items'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    highlight_id = Column(UUID(as_uuid=True), ForeignKey('user_moment_highlights.id', ondelete='CASCADE'), nullable=False)
    moment_id = Column(UUID(as_uuid=True), ForeignKey('user_moments.id', ondelete='CASCADE'), nullable=False)
    display_order = Column(Integer, default=0)
    added_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('highlight_id', 'moment_id', name='uq_highlight_moment'),
    )

    # Relationships
    highlight = relationship("UserMomentHighlight", back_populates="items")
    moment = relationship("UserMoment", back_populates="highlight_items")


# ──────────────────────────────────────────────
# User Services Tables
# ──────────────────────────────────────────────

class UserService(Base):
    __tablename__ = 'user_services'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    category_id = Column(UUID(as_uuid=True), ForeignKey('service_categories.id', ondelete='SET NULL'))
    service_type_id = Column(UUID(as_uuid=True), ForeignKey('service_types.id', ondelete='SET NULL'))
    title = Column(Text, nullable=False)
    description = Column(Text)
    min_price = Column(Numeric)
    max_price = Column(Numeric)
    availability = Column(Enum(ServiceAvailabilityEnum, name="service_availability_enum"), default=ServiceAvailabilityEnum.available)
    verification_status = Column(Enum(VerificationStatusEnum, name="verification_status_enum"), default=VerificationStatusEnum.pending)
    verification_progress = Column(Integer, default=0)
    is_verified = Column(Boolean, default=False)
    location = Column(Text)
    latitude = Column(Numeric)
    longitude = Column(Numeric)
    formatted_address = Column(Text)
    business_phone_id = Column(UUID(as_uuid=True), ForeignKey('service_business_phones.id', ondelete='SET NULL'))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="user_services")
    category = relationship("ServiceCategory", back_populates="user_services")
    service_type = relationship("ServiceType", back_populates="user_services")
    images = relationship("UserServiceImage", back_populates="user_service")
    packages = relationship("ServicePackage", back_populates="user_service")
    ratings = relationship("UserServiceRating", back_populates="user_service")
    verifications = relationship("UserServiceVerification", back_populates="user_service")
    kyc_statuses = relationship("UserServiceKYCStatus", back_populates="user_service")
    event_services = relationship("EventService", back_populates="provider_user_service")
    conversations = relationship("Conversation", back_populates="service")
    booking_requests = relationship("ServiceBookingRequest", back_populates="user_service")
    photo_libraries = relationship("ServicePhotoLibrary", back_populates="user_service")
    intro_media = relationship("ServiceIntroMedia", back_populates="user_service")
    business_phone = relationship("ServiceBusinessPhone", back_populates="services")
    budget_items = relationship("EventBudgetItem", back_populates="vendor", foreign_keys="[EventBudgetItem.vendor_id]")
    expense_items = relationship("EventExpense", back_populates="vendor", foreign_keys="[EventExpense.vendor_id]")


class UserServiceImage(Base):
    __tablename__ = 'user_service_images'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='CASCADE'))
    image_url = Column(Text, nullable=False)
    description = Column(Text)
    is_featured = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user_service = relationship("UserService", back_populates="images")


class ServicePackage(Base):
    __tablename__ = 'service_packages'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='CASCADE'), nullable=False)
    name = Column(Text, nullable=False)
    price = Column(Numeric, nullable=False)
    description = Column(Text)
    features = Column(JSONB)
    display_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user_service = relationship("UserService", back_populates="packages")
    booking_requests = relationship("ServiceBookingRequest", back_populates="package")


class UserServiceRating(Base):
    __tablename__ = 'user_service_ratings'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='CASCADE'))
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    rating = Column(Integer, nullable=False)
    review = Column(Text)
    helpful_count = Column(Integer, default=0)
    not_helpful_count = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint('rating >= 1 AND rating <= 5', name='ck_rating_range'),
    )

    # Relationships
    user_service = relationship("UserService", back_populates="ratings")
    user = relationship("User", back_populates="service_ratings")
    photos = relationship("ServiceReviewPhoto", back_populates="rating")
    helpfuls = relationship("ServiceReviewHelpful", back_populates="rating")


class UserServiceVerification(Base):
    __tablename__ = 'user_service_verifications'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='CASCADE'))
    submitted_by_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    verification_status = Column(Enum(VerificationStatusEnum, name="verification_status_enum"), default=VerificationStatusEnum.pending)
    remarks = Column(Text)
    verified_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user_service = relationship("UserService", back_populates="verifications")
    submitted_by_user = relationship("User", back_populates="service_verifications_submitted")
    files = relationship("UserServiceVerificationFile", back_populates="verification")
    kyc_statuses = relationship("UserServiceKYCStatus", back_populates="verification")


class UserServiceVerificationFile(Base):
    __tablename__ = 'user_service_verification_files'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    verification_id = Column(UUID(as_uuid=True), ForeignKey('user_service_verifications.id', ondelete='CASCADE'))
    kyc_requirement_id = Column(UUID(as_uuid=True), ForeignKey('kyc_requirements.id', ondelete='CASCADE'))
    file_url = Column(Text, nullable=False)
    file_type = Column(Enum(UploadFileTypeEnum, name="upload_file_type_enum"))
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    verification = relationship("UserServiceVerification", back_populates="files")
    kyc_requirement = relationship("KYCRequirement", back_populates="verification_files")


class UserServiceKYCStatus(Base):
    __tablename__ = 'user_service_kyc_status'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='CASCADE'), nullable=False)
    kyc_requirement_id = Column(UUID(as_uuid=True), ForeignKey('kyc_requirements.id', ondelete='CASCADE'), nullable=False)
    verification_id = Column(UUID(as_uuid=True), ForeignKey('user_service_verifications.id', ondelete='CASCADE'), nullable=False)
    status = Column(Enum(VerificationStatusEnum, name="verification_status_enum"), nullable=False, default=VerificationStatusEnum.pending)
    remarks = Column(Text)
    reviewed_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user_service = relationship("UserService", back_populates="kyc_statuses")
    kyc_requirement = relationship("KYCRequirement", back_populates="kyc_statuses")
    verification = relationship("UserServiceVerification", back_populates="kyc_statuses")


class ServiceReviewPhoto(Base):
    __tablename__ = 'service_review_photos'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    rating_id = Column(UUID(as_uuid=True), ForeignKey('user_service_ratings.id', ondelete='CASCADE'), nullable=False)
    image_url = Column(Text, nullable=False)
    caption = Column(Text)
    display_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    rating = relationship("UserServiceRating", back_populates="photos")


class ServiceReviewHelpful(Base):
    __tablename__ = 'service_review_helpful'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    rating_id = Column(UUID(as_uuid=True), ForeignKey('user_service_ratings.id', ondelete='CASCADE'), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    is_helpful = Column(Boolean, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        UniqueConstraint('rating_id', 'user_id', name='uq_review_helpful'),
    )

    # Relationships
    rating = relationship("UserServiceRating", back_populates="helpfuls")
    user = relationship("User", back_populates="service_review_helpfuls")


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
    organizer_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
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
    what_to_expect = Column(JSONB, nullable=True)
    what_to_expect_notes = Column(Text, nullable=True)
    # Optional fallback phone used in contributor reminder/bulk messages.
    reminder_contact_phone = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    organizer = relationship("User", back_populates="organized_events")
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


# ──────────────────────────────────────────────
# Committee Tables
# ──────────────────────────────────────────────

class CommitteeRole(Base):
    __tablename__ = 'committee_roles'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    role_name = Column(Text, nullable=False, unique=True)
    description = Column(Text, nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    committee_members = relationship("EventCommitteeMember", back_populates="role")


class EventCommitteeMember(Base):
    __tablename__ = 'event_committee_members'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'))
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    role_id = Column(UUID(as_uuid=True), ForeignKey('committee_roles.id', ondelete='SET NULL'))
    assigned_by = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    assigned_at = Column(DateTime, server_default=func.now())
    status = Column(Text, nullable=False, server_default="active")  # active | suspended | pending
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="committee_members")
    user = relationship("User", back_populates="event_committee_memberships", foreign_keys=[user_id])
    role = relationship("CommitteeRole", back_populates="committee_members")
    assigner = relationship("User", back_populates="event_committee_assignments", foreign_keys=[assigned_by])
    permission = relationship("CommitteePermission", back_populates="committee_member", uselist=False)


class CommitteePermission(Base):
    __tablename__ = 'committee_permissions'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    committee_member_id = Column(UUID(as_uuid=True), ForeignKey('event_committee_members.id', ondelete='CASCADE'), nullable=False, unique=True)
    can_view_guests = Column(Boolean, default=True)
    can_manage_guests = Column(Boolean, default=False)
    can_send_invitations = Column(Boolean, default=False)
    can_check_in_guests = Column(Boolean, default=False)
    can_view_budget = Column(Boolean, default=False)
    can_manage_budget = Column(Boolean, default=False)
    can_view_contributions = Column(Boolean, default=False)
    can_manage_contributions = Column(Boolean, default=False)
    can_view_vendors = Column(Boolean, default=True)
    can_manage_vendors = Column(Boolean, default=False)
    can_approve_bookings = Column(Boolean, default=False)
    can_edit_event = Column(Boolean, default=False)
    can_manage_committee = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    committee_member = relationship("EventCommitteeMember", back_populates="permission")


# ──────────────────────────────────────────────
# Event Services & Payments
# ──────────────────────────────────────────────

class EventService(Base):
    __tablename__ = 'event_services'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    service_id = Column(UUID(as_uuid=True), ForeignKey('service_types.id', ondelete='CASCADE'), nullable=False)
    provider_user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='SET NULL'))
    provider_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    agreed_price = Column(Numeric)
    is_payment_settled = Column(Boolean, default=False, nullable=False)
    service_status = Column(Enum(EventServiceStatusEnum, name="event_service_status_enum"), default=EventServiceStatusEnum.pending, nullable=False)
    notes = Column(Text)
    assigned_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now(), nullable=False)

    # Relationships
    event = relationship("Event", back_populates="event_services")
    service_type = relationship("ServiceType", back_populates="event_services")
    provider_user_service = relationship("UserService", back_populates="event_services")
    provider_user = relationship("User", back_populates="event_services_as_provider")
    payments = relationship("EventServicePayment", back_populates="event_service")


class EventServicePayment(Base):
    __tablename__ = 'event_service_payments'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_service_id = Column(UUID(as_uuid=True), ForeignKey('event_services.id', ondelete='CASCADE'))
    provider_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    amount = Column(Numeric, nullable=False)
    status = Column(Enum(PaymentStatusEnum, name="payment_status_enum"), default=PaymentStatusEnum.pending)
    payment_date = Column(DateTime, server_default=func.now())
    method = Column(Enum(PaymentMethodEnum, name="payment_method_enum"), nullable=False)
    transaction_ref = Column(Text)
    provider_transaction_ref = Column(Text)

    # Relationships
    event_service = relationship("EventService", back_populates="payments")
    provider_user = relationship("User", back_populates="event_service_payments_received")


# ──────────────────────────────────────────────
# Contributors & Contributions
# ──────────────────────────────────────────────

class UserContributor(Base):
    __tablename__ = 'user_contributors'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    # Link to a registered Nuru user when the contributor has an account, so
    # they can see this contribution in their "My Contributions" tab.
    contributor_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True, index=True)
    name = Column(Text, nullable=False)
    email = Column(Text)
    phone = Column(Text)
    notes = Column(Text)
    # Default secondary contact + notification routing (comms-only). Acts as
    # the default when the contributor is added to an event; the per-event
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
    pledge_amount = Column(Numeric, default=0)
    notes = Column(Text)
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
    confirmation_status = Column(Enum(ContributionStatusEnum, name="contribution_status_enum"), default=ContributionStatusEnum.confirmed)
    confirmed_at = Column(DateTime, nullable=True)
    contributed_at = Column(DateTime, server_default=func.now())
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

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
    invitation_id = Column(UUID(as_uuid=True), ForeignKey('event_invitations.id', ondelete='SET NULL'))
    rsvp_status = Column(Enum(RSVPStatusEnum, name="rsvp_status_enum"), default=RSVPStatusEnum.pending)
    checked_in = Column(Boolean, default=False)
    checked_in_at = Column(DateTime)
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


# ──────────────────────────────────────────────
# Event Schedule & Budget
# ──────────────────────────────────────────────

class EventScheduleItem(Base):
    __tablename__ = 'event_schedule_items'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    title = Column(Text, nullable=False)
    description = Column(Text)
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime)
    location = Column(Text)
    display_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="schedule_items")


class EventBudgetItem(Base):
    __tablename__ = 'event_budget_items'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    category = Column(Text, nullable=False)
    item_name = Column(Text, nullable=False)
    estimated_cost = Column(Numeric)
    actual_cost = Column(Numeric)
    vendor_name = Column(Text)
    vendor_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='SET NULL'), nullable=True)
    status = Column(Text, default='pending')
    notes = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="budget_items")
    vendor = relationship("UserService", back_populates="budget_items", foreign_keys=[vendor_id])


# ──────────────────────────────────────────────
# Messaging Tables
# ──────────────────────────────────────────────

class Conversation(Base):
    __tablename__ = 'conversations'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    type = Column(Enum(ConversationTypeEnum, name="conversation_type_enum"), nullable=False)
    user_one_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    user_two_id = Column(UUID(as_uuid=True), ForeignKey('users.id'))
    service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id'))
    last_read_at = Column(DateTime)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user_one = relationship("User", back_populates="conversations_as_one", foreign_keys=[user_one_id])
    user_two = relationship("User", back_populates="conversations_as_two", foreign_keys=[user_two_id])
    service = relationship("UserService", back_populates="conversations")
    messages = relationship("Message", back_populates="conversation")


class Message(Base):
    __tablename__ = 'messages'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    conversation_id = Column(UUID(as_uuid=True), ForeignKey('conversations.id', ondelete='CASCADE'))
    sender_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    message_text = Column(Text, nullable=False)
    attachments = Column(JSONB, server_default="'[]'::jsonb")
    is_read = Column(Boolean, default=False)
    reply_to_id = Column(UUID(as_uuid=True), ForeignKey('messages.id'))
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    conversation = relationship("Conversation", back_populates="messages")
    sender = relationship("User", back_populates="sent_messages")
    reply_to = relationship("Message", back_populates="replies", remote_side=[id])
    replies = relationship("Message", back_populates="reply_to")


# ──────────────────────────────────────────────
# Support Tables
# ──────────────────────────────────────────────

class SupportTicket(Base):
    __tablename__ = 'support_tickets'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    subject = Column(Text)
    status = Column(Text, default='open')
    priority = Column(Enum(PriorityLevelEnum, name="priority_level_enum"), default=PriorityLevelEnum.medium)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="support_tickets")
    messages = relationship("SupportMessage", back_populates="ticket")
    live_chat_sessions = relationship("LiveChatSession", back_populates="ticket")


class SupportMessage(Base):
    __tablename__ = 'support_messages'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    ticket_id = Column(UUID(as_uuid=True), ForeignKey('support_tickets.id', ondelete='CASCADE'))
    sender_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    is_agent = Column(Boolean, default=False)
    message_text = Column(Text, nullable=False)
    attachments = Column(JSONB, server_default="'[]'::jsonb")
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    ticket = relationship("SupportTicket", back_populates="messages")
    sender = relationship("User", back_populates="support_messages")


class FAQ(Base):
    __tablename__ = 'faqs'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    question = Column(Text, nullable=False)
    answer = Column(Text, nullable=False)
    category = Column(Text)
    display_order = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)
    helpful_count = Column(Integer, default=0)
    not_helpful_count = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class LiveChatSession(Base):
    __tablename__ = 'live_chat_sessions'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    agent_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    ticket_id = Column(UUID(as_uuid=True), ForeignKey('support_tickets.id', ondelete='SET NULL'))
    status = Column(Enum(ChatSessionStatusEnum, name="chat_session_status_enum"), default=ChatSessionStatusEnum.waiting)
    started_at = Column(DateTime)
    ended_at = Column(DateTime)
    wait_time_seconds = Column(Integer)
    duration_seconds = Column(Integer)
    rating = Column(Integer)
    feedback = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint('rating >= 1 AND rating <= 5', name='ck_chat_rating_range'),
    )

    # Relationships
    user = relationship("User", back_populates="live_chat_sessions_as_user", foreign_keys=[user_id])
    agent = relationship("User", back_populates="live_chat_sessions_as_agent", foreign_keys=[agent_id])
    ticket = relationship("SupportTicket", back_populates="live_chat_sessions")
    chat_messages = relationship("LiveChatMessage", back_populates="session")


class LiveChatMessage(Base):
    __tablename__ = 'live_chat_messages'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    session_id = Column(UUID(as_uuid=True), ForeignKey('live_chat_sessions.id', ondelete='CASCADE'), nullable=False)
    sender_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    is_agent = Column(Boolean, default=False)
    is_system = Column(Boolean, default=False)
    message_text = Column(Text, nullable=False)
    attachments = Column(JSONB, server_default="'[]'::jsonb")
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    session = relationship("LiveChatSession", back_populates="chat_messages")
    sender = relationship("User", back_populates="live_chat_messages")


# ──────────────────────────────────────────────
# Notifications
# ──────────────────────────────────────────────

class Notification(Base):
    __tablename__ = 'notifications'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    recipient_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    sender_ids = Column(JSONB)
    type = Column(Enum(NotificationTypeEnum, name="notification_type_enum"), nullable=False)
    reference_id = Column(UUID(as_uuid=True))
    reference_type = Column(Text)
    message_template = Column(Text, nullable=False)
    message_data = Column(JSONB, server_default="'{}'::jsonb")
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    recipient = relationship("User", back_populates="notifications")


# ──────────────────────────────────────────────
# Booking Requests
# ──────────────────────────────────────────────

class ServiceBookingRequest(Base):
    __tablename__ = 'service_booking_requests'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='CASCADE'))
    requester_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='SET NULL'))
    package_id = Column(UUID(as_uuid=True), ForeignKey('service_packages.id'))
    message = Column(Text)
    proposed_price = Column(Numeric)
    quoted_price = Column(Numeric)
    deposit_required = Column(Numeric)
    deposit_paid = Column(Boolean, default=False)
    vendor_notes = Column(Text)
    status = Column(Text, default='pending')
    responded_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    user_service = relationship("UserService", back_populates="booking_requests")
    requester = relationship("User", back_populates="booking_requests")
    event = relationship("Event", back_populates="booking_requests")
    package = relationship("ServicePackage", back_populates="booking_requests")


# ──────────────────────────────────────────────
# Promotions
# ──────────────────────────────────────────────

class Promotion(Base):
    __tablename__ = 'promotions'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    title = Column(Text, nullable=False)
    description = Column(Text)
    image_url = Column(Text)
    cta_text = Column(Text)
    cta_url = Column(Text)
    is_active = Column(Boolean, default=True)
    start_date = Column(DateTime)
    end_date = Column(DateTime)
    impressions = Column(Integer, default=0)
    clicks = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class PromotedEvent(Base):
    __tablename__ = 'promoted_events'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'))
    boost_level = Column(Text, default='standard')
    start_date = Column(DateTime)
    end_date = Column(DateTime)
    impressions = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    event = relationship("Event", back_populates="promoted_events")


# ──────────────────────────────────────────────
# File Uploads
# ──────────────────────────────────────────────

class FileUpload(Base):
    __tablename__ = 'file_uploads'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'))
    file_url = Column(Text, nullable=False)
    file_type = Column(Enum(UploadFileTypeEnum, name="upload_file_type_enum"))
    file_size = Column(Integer)
    original_name = Column(Text)
    entity_type = Column(Text)
    entity_id = Column(UUID(as_uuid=True))
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    user = relationship("User", back_populates="file_uploads")


# ──────────────────────────────────────────────
# Event Templates & Checklists
# ──────────────────────────────────────────────

class EventTemplate(Base):
    __tablename__ = 'event_templates'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_type_id = Column(UUID(as_uuid=True), ForeignKey('event_types.id', ondelete='CASCADE'), nullable=False)
    name = Column(Text, nullable=False)
    description = Column(Text)
    estimated_budget_min = Column(Numeric)
    estimated_budget_max = Column(Numeric)
    estimated_timeline_days = Column(Integer)
    guest_range_min = Column(Integer)
    guest_range_max = Column(Integer)
    tips = Column(JSONB, server_default="'[]'::jsonb")
    is_active = Column(Boolean, default=True)
    display_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event_type = relationship("EventType", back_populates="templates")
    tasks = relationship("EventTemplateTask", back_populates="template", cascade="all, delete-orphan")


class EventTemplateTask(Base):
    __tablename__ = 'event_template_tasks'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    template_id = Column(UUID(as_uuid=True), ForeignKey('event_templates.id', ondelete='CASCADE'), nullable=False)
    title = Column(Text, nullable=False)
    description = Column(Text)
    category = Column(Text, default='general')
    priority = Column(Enum(PriorityLevelEnum, name="priority_level_enum"), default=PriorityLevelEnum.medium)
    days_before_event = Column(Integer)
    display_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    template = relationship("EventTemplate", back_populates="tasks")
    checklist_items = relationship("EventChecklistItem", back_populates="template_task")


class EventChecklistItem(Base):
    __tablename__ = 'event_checklist_items'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    template_task_id = Column(UUID(as_uuid=True), ForeignKey('event_template_tasks.id', ondelete='SET NULL'), nullable=True)
    title = Column(Text, nullable=False)
    description = Column(Text)
    category = Column(Text, default='general')
    priority = Column(Enum(PriorityLevelEnum, name="priority_level_enum"), default=PriorityLevelEnum.medium)
    status = Column(Enum(ChecklistItemStatusEnum, name="checklist_item_status_enum"), default=ChecklistItemStatusEnum.pending)
    due_date = Column(DateTime)
    assigned_to = Column(UUID(as_uuid=True), nullable=True)
    assigned_name = Column(Text)
    display_order = Column(Integer, default=0)
    completed_at = Column(DateTime)
    completed_by = Column(UUID(as_uuid=True), nullable=True)
    notes = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="checklist_items")
    template_task = relationship("EventTemplateTask", back_populates="checklist_items")


# ──────────────────────────────────────────────
# Content Appeals
# ──────────────────────────────────────────────

class ContentAppeal(Base):
    """
    Allows users to appeal the removal of their posts or moments by an admin.
    One appeal per content item — duplicate appeals are blocked by the unique constraint.
    """
    __tablename__ = 'content_appeals'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    content_id = Column(UUID(as_uuid=True), nullable=False)
    content_type = Column(Enum(AppealContentTypeEnum, name="appeal_content_type_enum"), nullable=False)
    appeal_reason = Column(Text, nullable=False)
    status = Column(Enum(AppealStatusEnum, name="appeal_status_enum"), default=AppealStatusEnum.pending, nullable=False)
    admin_notes = Column(Text)
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey('admin_users.id', ondelete='SET NULL'))
    reviewed_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint('user_id', 'content_id', 'content_type', name='uq_content_appeal'),
    )

    # Relationships
    user = relationship("User", back_populates="content_appeals")


# ──────────────────────────────────────────────
# Photo Libraries (Photography service providers)
# ──────────────────────────────────────────────

class ServicePhotoLibrary(Base):
    """
    A photo library created by a photography service provider for a specific event.
    One library per service per event. Storage capped at 200MB per service.
    """
    __tablename__ = 'service_photo_libraries'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='CASCADE'), nullable=False)
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    name = Column(Text, nullable=False)              # auto-generated from event name
    description = Column(Text)
    privacy = Column(Enum(PhotoLibraryPrivacyEnum, name="photo_library_privacy_enum"), nullable=False, default=PhotoLibraryPrivacyEnum.event_creator_only)
    share_token = Column(Text, unique=True, nullable=False)  # used for public share links
    photo_count = Column(Integer, default=0)
    total_size_bytes = Column(Integer, default=0)    # tracked cumulatively (BigInteger stored as Integer for compat)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint('user_service_id', 'event_id', name='uq_service_event_library'),
    )

    # Relationships
    user_service = relationship("UserService", back_populates="photo_libraries")
    event = relationship("Event", back_populates="photo_libraries")
    photos = relationship("ServicePhotoLibraryImage", back_populates="library", cascade="all, delete-orphan")


class ServicePhotoLibraryImage(Base):
    """
    A single image inside a ServicePhotoLibrary.
    Max 10MB per image enforced at the API layer.
    """
    __tablename__ = 'service_photo_library_images'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    library_id = Column(UUID(as_uuid=True), ForeignKey('service_photo_libraries.id', ondelete='CASCADE'), nullable=False)
    image_url = Column(Text, nullable=False)
    original_name = Column(Text)
    file_size_bytes = Column(Integer, default=0)
    width = Column(Integer)
    height = Column(Integer)
    caption = Column(Text)
    display_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    library = relationship("ServicePhotoLibrary", back_populates="photos")


# ──────────────────────────────────────────────
# Feed Ranking & Recommendation
# ──────────────────────────────────────────────

class UserInteractionLog(Base):
    """Logs every user interaction with feed content for ranking signals."""
    __tablename__ = 'user_interaction_logs'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    post_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'), nullable=False)
    interaction_type = Column(Text, nullable=False)
    dwell_time_ms = Column(Integer)
    session_id = Column(Text)
    device_type = Column(Text)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        Index('idx_interaction_user_post', 'user_id', 'post_id'),
        Index('idx_interaction_user_type', 'user_id', 'interaction_type'),
        Index('idx_interaction_created', 'created_at'),
    )


class UserInterestProfile(Base):
    """Per-user interest vectors updated after each interaction."""
    __tablename__ = 'user_interest_profiles'

    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)
    interest_vector = Column(JSONB, server_default="'{}'::jsonb")
    engagement_stats = Column(JSONB, server_default="'{}'::jsonb")
    negative_signals = Column(JSONB, server_default="'{}'::jsonb")
    last_computed_at = Column(DateTime, server_default=func.now())
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class AuthorAffinityScore(Base):
    """Precomputed relationship strength between viewer and author."""
    __tablename__ = 'author_affinity_scores'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    viewer_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    author_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    interaction_count = Column(Integer, default=0)
    weighted_score = Column(Float, default=0.0)
    is_following = Column(Boolean, default=False)
    shared_events_count = Column(Integer, default=0)
    is_circle_member = Column(Boolean, default=False)
    last_interaction_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index('idx_affinity_viewer_author', 'viewer_id', 'author_id', unique=True),
        Index('idx_affinity_viewer', 'viewer_id'),
    )


class PostQualityScore(Base):
    """Cached quality score for each post, recomputed periodically."""
    __tablename__ = 'post_quality_scores'

    post_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'), primary_key=True)
    engagement_velocity = Column(Float, default=0.0)
    content_richness = Column(Float, default=0.0)
    author_credibility = Column(Float, default=0.5)
    moderation_flag = Column(Boolean, default=False)
    spam_probability = Column(Float, default=0.0)
    category = Column(Text, default='general')
    final_quality_score = Column(Float, default=0.5)
    total_engagements = Column(Integer, default=0)
    engagement_rate = Column(Float, default=0.0)
    impression_count = Column(Integer, default=0)
    last_computed_at = Column(DateTime, server_default=func.now())
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class FeedImpression(Base):
    """Tracks which posts were shown to which users and in what position."""
    __tablename__ = 'feed_impressions'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    post_id = Column(UUID(as_uuid=True), ForeignKey('user_feeds.id', ondelete='CASCADE'), nullable=False)
    position = Column(Integer)
    session_id = Column(Text)
    was_engaged = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        Index('idx_impression_user_session', 'user_id', 'session_id'),
        Index('idx_impression_post', 'post_id'),
        Index('idx_impression_created', 'created_at'),
    )


# ──────────────────────────────────────────────
# Ticketing Tables
# ──────────────────────────────────────────────

class EventTicketClass(Base):
    __tablename__ = 'event_ticket_classes'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    name = Column(Text, nullable=False)
    description = Column(Text)
    price = Column(Numeric(12, 2), nullable=False)
    currency_id = Column(UUID(as_uuid=True), ForeignKey('currencies.id'))
    quantity = Column(Integer, nullable=False)
    sold = Column(Integer, default=0)
    status = Column(Enum(TicketStatusEnum, name="ticket_status_enum"), default=TicketStatusEnum.available)
    display_order = Column(Integer, default=0)
    sale_start_date = Column(DateTime)
    sale_end_date = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    event = relationship("Event", back_populates="ticket_classes")
    currency = relationship("Currency")
    tickets = relationship("EventTicket", back_populates="ticket_class")


class EventTicket(Base):
    __tablename__ = 'event_tickets'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    ticket_class_id = Column(UUID(as_uuid=True), ForeignKey('event_ticket_classes.id', ondelete='CASCADE'), nullable=False)
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    buyer_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    ticket_code = Column(Text, unique=True, nullable=False)
    quantity = Column(Integer, default=1)
    total_amount = Column(Numeric(12, 2), nullable=False)
    payment_method = Column(Enum(PaymentMethodEnum, name="payment_method_enum"))
    payment_status = Column(Enum(PaymentStatusEnum, name="payment_status_enum"), default=PaymentStatusEnum.pending)
    payment_ref = Column(Text)
    status = Column(Enum(TicketOrderStatusEnum, name="ticket_order_status_enum"), default=TicketOrderStatusEnum.pending)
    checked_in = Column(Boolean, default=False)
    checked_in_at = Column(DateTime)
    buyer_name = Column(Text)
    buyer_phone = Column(Text)
    buyer_email = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    ticket_class = relationship("EventTicketClass", back_populates="tickets")
    event = relationship("Event", back_populates="tickets")
    buyer = relationship("User")


# ──────────────────────────────────────────────
# Service Intro Media
# ──────────────────────────────────────────────

class ServiceIntroMedia(Base):
    __tablename__ = 'service_intro_media'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='CASCADE'), nullable=False)
    media_type = Column(Enum(ServiceMediaTypeEnum, name="service_media_type_enum"), nullable=False)
    media_url = Column(Text, nullable=False)
    thumbnail_url = Column(Text)
    duration_seconds = Column(Integer)
    title = Column(Text)
    display_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user_service = relationship("UserService", back_populates="intro_media")


# ──────────────────────────────────────────────
# Service Business Phones
# ──────────────────────────────────────────────

class ServiceBusinessPhone(Base):
    __tablename__ = 'service_business_phones'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    phone_number = Column(Text, nullable=False)
    verification_status = Column(Enum(BusinessPhoneStatusEnum, name="business_phone_status_enum"), default=BusinessPhoneStatusEnum.pending)
    otp_code = Column(Text, nullable=True)
    otp_expires_at = Column(DateTime, nullable=True)
    verified_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint('user_id', 'phone_number', name='uq_user_business_phone'),
    )

    user = relationship("User")
    services = relationship("UserService", back_populates="business_phone")