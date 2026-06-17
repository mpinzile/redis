from sqlalchemy import Column, Boolean, ForeignKey, DateTime, Integer, Numeric, Text, Enum, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from core.base import Base
from models.enums import TicketStatusEnum, TicketOrderStatusEnum, PaymentMethodEnum, PaymentStatusEnum


# ──────────────────────────────────────────────
# Event Ticketing Tables
# ──────────────────────────────────────────────

class EventTicketClass(Base):
    """Defines a ticket tier/class for an event (e.g. VIP, Regular, Early Bird)."""
    __tablename__ = 'event_ticket_classes'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    name = Column(Text, nullable=False)
    description = Column(Text)
    price = Column(Numeric(12, 2), nullable=False)
    quantity = Column(Integer, nullable=False)
    sold = Column(Integer, default=0)
    status = Column(Enum(TicketStatusEnum, name="ticket_status_enum"), default=TicketStatusEnum.available)
    display_order = Column(Integer, default=0)
    sale_start_date = Column(DateTime)
    sale_end_date = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    event = relationship("Event", back_populates="ticket_classes")
    tickets = relationship("EventTicket", back_populates="ticket_class")


class EventTicket(Base):
    """Individual ticket purchased by a user for a specific ticket class."""
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
    checked_in_by_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    checkin_session_id = Column(UUID(as_uuid=True), ForeignKey('event_checkin_sessions.id', ondelete='SET NULL'), nullable=True)
    checkin_code_id = Column(UUID(as_uuid=True), ForeignKey('event_checkin_codes.id', ondelete='SET NULL'), nullable=True)
    checkin_device_ref = Column(Text, nullable=True)
    checkin_failure_reason = Column(Text, nullable=True)
    buyer_name = Column(Text)
    buyer_phone = Column(Text)
    buyer_email = Column(Text)
    # Set only while status == 'reserved'. Sweep job hard-deletes any row
    # with reserved_until < now() so inventory frees up automatically.
    reserved_until = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    ticket_class = relationship("EventTicketClass", back_populates="tickets")
    event = relationship("Event", back_populates="tickets")
    buyer = relationship("User", foreign_keys=[buyer_user_id])
    checked_in_by = relationship("User", foreign_keys=[checked_in_by_user_id])
