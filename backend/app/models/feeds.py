from sqlalchemy import Column, Boolean, ForeignKey, DateTime, Integer, Text, Enum, UniqueConstraint, Numeric, Index, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from core.base import Base
from models.enums import FeedVisibilityEnum, EventShareDurationEnum


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
    post_type = Column(Text, default='post')  # 'post' or 'event_share'
    shared_event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='SET NULL'))
    share_duration = Column(Enum(EventShareDurationEnum, name="event_share_duration_enum"))
    share_expires_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # High-value composite indexes for feed ranking & timeline queries.
    # `(is_active, created_at)` accelerates the global candidate scan;
    # `(user_id, is_active, created_at)` accelerates per-user listings used by
    # /posts/me and the followed-users branch of candidate generation.
    __table_args__ = (
        Index('idx_user_feeds_active_created', 'is_active', 'created_at'),
        Index('idx_user_feeds_user_active_created', 'user_id', 'is_active', 'created_at'),
        Index('idx_user_feeds_visibility_created', 'visibility', 'created_at'),
        Index('idx_user_feeds_shared_event', 'shared_event_id'),
    )

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
    media_type = Column(Text, default='image')  # 'image' or 'video'
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
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    feed = relationship("UserFeed", back_populates="comments")
    user = relationship("User", back_populates="feed_comments")
    parent_comment = relationship("UserFeedComment", back_populates="replies", remote_side="UserFeedComment.id")
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
