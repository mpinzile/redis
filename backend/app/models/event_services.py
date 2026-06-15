from sqlalchemy import Column, Boolean, ForeignKey, DateTime, Numeric, Text, Enum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from core.base import Base
from models.enums import EventServiceStatusEnum, PaymentStatusEnum, PaymentMethodEnum


# ──────────────────────────────────────────────
# Event Services & Payments
# ──────────────────────────────────────────────

class EventService(Base):
    __tablename__ = 'event_services'

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id', ondelete='CASCADE'), nullable=False)
    service_id = Column(UUID(as_uuid=True), ForeignKey('service_types.id', ondelete='CASCADE'), nullable=True)
    provider_user_service_id = Column(UUID(as_uuid=True), ForeignKey('user_services.id', ondelete='SET NULL'))
    provider_user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    agreed_price = Column(Numeric)
    is_payment_settled = Column(Boolean, default=False, nullable=False)
    service_status = Column(Enum(EventServiceStatusEnum, name="event_service_status_enum"), default=EventServiceStatusEnum.pending, nullable=False)
    notes = Column(Text)
    assigned_at = Column(DateTime)
    # Manual (off-platform) vendor support — used when planners record a vendor
    # that is not yet on Nuru. For manual rows, provider_user_service_id /
    # provider_user_id stay NULL and the manual_vendor_* fields describe the vendor.
    is_manual = Column(Boolean, default=False, nullable=False)
    manual_vendor_name = Column(Text)
    manual_vendor_phone = Column(Text)
    manual_vendor_email = Column(Text)
    manual_vendor_category_id = Column(UUID(as_uuid=True), ForeignKey('service_categories.id', ondelete='SET NULL'))
    manual_vendor_notes = Column(Text)
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
