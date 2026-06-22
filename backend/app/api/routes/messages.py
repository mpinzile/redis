# Messages Routes - /messages/...
# Handles messaging/conversations between users

import uuid
from datetime import datetime

import pytz
from fastapi import APIRouter, Depends, Body
from sqlalchemy import func as sa_func, or_, and_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from core.database import get_db
from models import Conversation, Message, User, UserProfile, UserService, UserServiceImage, ConversationTypeEnum, CallLog, ConversationHide
from utils.auth import get_current_user
from utils.helpers import standard_response

EAT = pytz.timezone("Africa/Nairobi")
router = APIRouter(prefix="/messages", tags=["Messages"])


def _conversation_dict(db, conv, current_user_id):
    """Build conversation summary with other participant info."""
    other_id = conv.user_two_id if str(conv.user_one_id) == str(current_user_id) else conv.user_one_id
    other = db.query(User).filter(User.id == other_id).first()
    profile = db.query(UserProfile).filter(UserProfile.user_id == other_id).first() if other else None

    last_msg = db.query(Message).filter(Message.conversation_id == conv.id).order_by(Message.created_at.desc()).first()
    unread = db.query(sa_func.count(Message.id)).filter(
        Message.conversation_id == conv.id,
        Message.sender_id != current_user_id,
        Message.is_read == False
    ).scalar() or 0

    # If this is a service conversation, include service info
    service_info = None
    if conv.service_id:
        svc = db.query(UserService).filter(UserService.id == conv.service_id).first()
        if svc:
            # Get featured or first image for the service
            svc_image = None
            for img in svc.images:
                if img.is_featured:
                    svc_image = img.image_url
                    break
            if not svc_image and svc.images:
                svc_image = svc.images[0].image_url
            service_info = {
                "id": str(svc.id),
                "title": svc.title,
                "image": svc_image,
                "provider_id": str(svc.user_id),
            }

    # Determine display: service owner sees customer; customer sees service branding
    participant_name = f"{other.first_name} {other.last_name}" if other else None
    participant_avatar = profile.profile_picture_url if profile else None

    is_service_owner = service_info and str(service_info["provider_id"]) == str(current_user_id)
    if service_info and not is_service_owner:
        # Customer perspective → show service branding
        display_name = service_info["title"]
        display_avatar = service_info["image"]
    else:
        # Service owner or regular chat → show the other person
        display_name = participant_name
        display_avatar = participant_avatar

    return {
        "id": str(conv.id),
        "type": conv.type.value if conv.type else "user_to_user",
        "participant": {
            "id": str(other.id) if other else None,
            "name": display_name,
            "avatar": display_avatar,
        },
        "service": service_info,
        "last_message": {
            "content": last_msg.message_text if last_msg else None,
            "sent_at": last_msg.created_at.isoformat() if last_msg else None,
            "is_mine": str(last_msg.sender_id) == str(current_user_id) if last_msg else False,
        } if last_msg else None,
        "unread_count": unread,
        "is_active": conv.is_active,
        "updated_at": conv.updated_at.isoformat() if conv.updated_at else None,
    }


@router.get("/unread/count")
def get_unread_count(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Returns total unread message count across all conversations."""
    conv_ids = [
        r[0] for r in db.query(Conversation.id).filter(
            or_(Conversation.user_one_id == current_user.id, Conversation.user_two_id == current_user.id)
        ).all()
    ]
    if not conv_ids:
        return standard_response(True, "Unread count retrieved", {"count": 0})

    count = db.query(sa_func.count(Message.id)).filter(
        Message.conversation_id.in_(conv_ids),
        Message.sender_id != current_user.id,
        Message.is_read == False
    ).scalar() or 0
    return standard_response(True, "Unread count retrieved", {"count": count})


@router.get("/")
def get_conversations(
    search: str = None,
    page: int = 1,
    limit: int = 30,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Returns conversations for the current user (paginated, newest first).

    Optional ``?search=`` pushes the filter into SQL by matching the other
    participant's first/last/username/email — avoids loading every conversation
    and filtering in Python.
    """
    from utils.batch_loaders import build_conversation_dicts
    from sqlalchemy import and_

    page = max(1, int(page or 1))
    limit = max(1, min(int(limit or 30), 100))
    offset = (page - 1) * limit

    base_filter = and_(
        or_(Conversation.user_one_id == current_user.id, Conversation.user_two_id == current_user.id),
        Conversation.is_active == True,
    )
    query = db.query(Conversation).filter(base_filter)

    if search and search.strip():
        term = f"%{search.strip().lower()}%"
        # Join to the *other* participant via a conditional ID expression.
        from sqlalchemy import case as sa_case, func as sa_func
        other_id_expr = sa_case(
            (Conversation.user_one_id == current_user.id, Conversation.user_two_id),
            else_=Conversation.user_one_id,
        )
        query = query.join(User, User.id == other_id_expr).filter(
            or_(
                sa_func.lower(sa_func.coalesce(User.first_name, "")).like(term),
                sa_func.lower(sa_func.coalesce(User.last_name, "")).like(term),
                sa_func.lower(sa_func.coalesce(User.username, "")).like(term),
                sa_func.lower(sa_func.coalesce(User.email, "")).like(term),
            )
        )

    query = query.order_by(Conversation.updated_at.desc())
    convs = query.offset(offset).limit(limit).all()

    # Apply hide filter on the visible page only.
    if convs:
        conv_ids = [c.id for c in convs]
        hides = {
            str(h.conversation_id): h.hidden_at
            for h in db.query(ConversationHide).filter(
                ConversationHide.user_id == current_user.id,
                ConversationHide.conversation_id.in_(conv_ids),
            ).all()
        }
        if hides:
            convs = [
                c for c in convs
                if str(c.id) not in hides or (c.updated_at and c.updated_at > hides[str(c.id)])
            ]

    data = build_conversation_dicts(db, convs, current_user.id)
    return standard_response(True, "Conversations retrieved successfully", data)


# ── Static /start route MUST come before /{conversation_id} to avoid route conflict ──

@router.post("/start")
def start_conversation(body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Starts a new conversation with another user, or returns existing one.
    If service_id is provided, creates/finds a service-specific conversation."""
    recipient_id = body.get("recipient_id")
    service_id_str = body.get("service_id")
    service_title = body.get("service_title")
    service_image = body.get("service_image")
    if not recipient_id:
        return standard_response(False, "Recipient ID is required")

    try:
        rid = uuid.UUID(recipient_id)
    except ValueError:
        return standard_response(False, "Invalid recipient ID")

    if str(rid) == str(current_user.id):
        return standard_response(False, "You cannot start a conversation with yourself")

    recipient = db.query(User).filter(User.id == rid).first()
    if not recipient:
        return standard_response(False, "Recipient not found")

    # Resolve optional service_id
    sid = None
    if service_id_str:
        try:
            sid = uuid.UUID(service_id_str)
        except ValueError:
            pass
        svc = db.query(UserService).filter(UserService.id == sid, UserService.user_id == rid).first() if sid else None
        if not svc:
            return standard_response(False, "Service not found for this vendor")
        if service_title and service_title != svc.title:
            return standard_response(False, "Service title does not match")
        if service_image:
            service_images = [img.image_url for img in svc.images]
            if service_image not in service_images:
                return standard_response(False, "Service image does not match")

    # Look for an existing conversation – if service_id provided, match it specifically
    if sid:
        existing = db.query(Conversation).filter(
            or_(
                and_(Conversation.user_one_id == current_user.id, Conversation.user_two_id == rid),
                and_(Conversation.user_one_id == rid, Conversation.user_two_id == current_user.id),
            ),
            Conversation.service_id == sid,
        ).first()
    else:
        existing = db.query(Conversation).filter(
            or_(
                and_(Conversation.user_one_id == current_user.id, Conversation.user_two_id == rid),
                and_(Conversation.user_one_id == rid, Conversation.user_two_id == current_user.id),
            ),
            Conversation.service_id.is_(None),
        ).first()

    if existing:
        from utils.batch_loaders import build_conversation_dicts
        return standard_response(True, "Conversation already exists", build_conversation_dicts(db, [existing], current_user.id)[0])

    conv_type = ConversationTypeEnum.user_to_service if sid else ConversationTypeEnum.user_to_user
    conv = Conversation(
        user_one_id=current_user.id,
        user_two_id=rid,
        type=conv_type,
        service_id=sid,
    )
    db.add(conv)

    initial_message = body.get("message", "").strip()
    if initial_message:
        db.flush()
        msg = Message(conversation_id=conv.id, sender_id=current_user.id, message_text=initial_message, is_read=False)
        db.add(msg)

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        # Unique constraint hit – find the existing conversation (check both user orderings)
        existing = db.query(Conversation).filter(
            or_(
                and_(Conversation.user_one_id == current_user.id, Conversation.user_two_id == rid),
                and_(Conversation.user_one_id == rid, Conversation.user_two_id == current_user.id),
            ),
        ).first()
        if existing:
            from utils.batch_loaders import build_conversation_dicts
            return standard_response(True, "Conversation already exists", build_conversation_dicts(db, [existing], current_user.id)[0])
        return standard_response(False, "Could not start conversation")

    db.refresh(conv)
    from utils.batch_loaders import build_conversation_dicts
    return standard_response(True, "Conversation started successfully", build_conversation_dicts(db, [conv], current_user.id)[0])


# ── Dynamic /{conversation_id} routes ──

@router.get("/{conversation_id}")
def get_messages(conversation_id: str, page: int = 1, limit: int = 50, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Returns paginated messages for a conversation."""
    try:
        cid = uuid.UUID(conversation_id)
    except ValueError:
        return standard_response(False, "Invalid conversation ID")

    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if not conv:
        return standard_response(False, "Conversation not found")

    if str(conv.user_one_id) != str(current_user.id) and str(conv.user_two_id) != str(current_user.id):
        return standard_response(False, "You are not a participant in this conversation")

    messages = db.query(Message).filter(Message.conversation_id == cid).order_by(Message.created_at.desc()).offset((page - 1) * limit).limit(limit).all()

    data = [{
        "id": str(m.id),
        "content": m.message_text,
        "sender_id": str(m.sender_id),
        "is_mine": str(m.sender_id) == str(current_user.id),
        "is_read": m.is_read,
        "reply_to_id": str(m.reply_to_id) if m.reply_to_id else None,
        # Reply snapshot — survives even if original message is deleted/edited.
        "reply_snapshot": ({
            "text": m.reply_snapshot_text,
            "sender": m.reply_snapshot_sender,
        } if (getattr(m, "reply_snapshot_text", None) or getattr(m, "reply_snapshot_sender", None)) else None),
        # Transport-framing version. NULL/'plain' for legacy rows so old
        # clients keep rendering them as plain text (backward compatible).
        "encryption_version": getattr(m, "encryption_version", None) or "plain",
        "attachments": m.attachments or [],
        "created_at": m.created_at.isoformat() if m.created_at else None,
    } for m in reversed(messages)]

    # Include call logs inline so the client renders them in a single
    # round-trip — avoids the "messages first, calls second" flicker.
    call_rows = db.query(CallLog).filter(CallLog.conversation_id == cid).order_by(CallLog.started_at.desc()).limit(50).all()
    calls = []
    for c in call_rows:
        direction = "outgoing" if str(c.caller_id) == str(current_user.id) else "incoming"
        calls.append({
            "id": str(c.id),
            "_type": "call_log",
            "conversation_id": str(c.conversation_id),
            "kind": c.kind,
            "status": c.status,
            "direction": direction,
            "caller_id": str(c.caller_id),
            "callee_id": str(c.callee_id),
            "started_at": c.started_at.isoformat() if c.started_at else None,
            "answered_at": c.answered_at.isoformat() if c.answered_at else None,
            "ended_at": c.ended_at.isoformat() if c.ended_at else None,
            "duration_seconds": c.duration_seconds or 0,
            "created_at": c.started_at.isoformat() if c.started_at else None,
        })

    return standard_response(True, "Messages retrieved successfully", {
        "messages": data,
        "calls": calls,
        "is_encrypted": bool(getattr(conv, "is_encrypted", False)),
    })


@router.post("/{conversation_id}")
def send_message(conversation_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Sends a message in an existing conversation.

    Body fields:
      * ``content`` — text body (required if no attachments)
      * ``attachments`` — list of uploaded file URLs (or {url,...} dicts)
      * ``reply_to_id`` — UUID of the message being quoted
      * ``encryption_version`` — 'plain' (default) or 'v1' (transport-framed)
    """
    try:
        cid = uuid.UUID(conversation_id)
    except ValueError:
        return standard_response(False, "Invalid conversation ID")

    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if not conv:
        return standard_response(False, "Conversation not found")

    if str(conv.user_one_id) != str(current_user.id) and str(conv.user_two_id) != str(current_user.id):
        return standard_response(False, "You are not a participant in this conversation")

    content = (body.get("content") or "").strip()
    attachments = body.get("attachments") or []
    if not content and not attachments:
        return standard_response(False, "Message content or attachment is required")

    # Resolve reply target → snapshot the original at send-time.
    reply_to_uuid = None
    snapshot_text = None
    snapshot_sender = None
    raw_reply = body.get("reply_to_id")
    if raw_reply:
        try:
            reply_to_uuid = uuid.UUID(str(raw_reply))
        except (ValueError, TypeError):
            reply_to_uuid = None
        if reply_to_uuid:
            original = db.query(Message).filter(
                Message.id == reply_to_uuid,
                Message.conversation_id == cid,
            ).first()
            if original:
                snap = (original.message_text or "").strip()
                snapshot_text = snap[:280]  # keep preview short
                sender_user = db.query(User).filter(User.id == original.sender_id).first()
                if sender_user:
                    snapshot_sender = f"{sender_user.first_name or ''} {sender_user.last_name or ''}".strip() or "Unknown"
            else:
                reply_to_uuid = None  # silently drop invalid reply target

    enc_version = (body.get("encryption_version") or "").strip().lower() or None
    if enc_version not in (None, "plain", "v1"):
        enc_version = None

    now = datetime.now(EAT)
    msg = Message(
        conversation_id=cid,
        sender_id=current_user.id,
        message_text=content,
        is_read=False,
        reply_to_id=reply_to_uuid,
        attachments=attachments or None,
        encryption_version=enc_version,
        reply_snapshot_text=snapshot_text,
        reply_snapshot_sender=snapshot_sender,
    )
    db.add(msg)
    conv.updated_at = now
    db.commit()
    db.refresh(msg)

    # ── Push notification fan-out to the other participant ─────────────
    try:
        recipient_id = conv.user_two_id if str(conv.user_one_id) == str(current_user.id) else conv.user_one_id
        if recipient_id and str(recipient_id) != str(current_user.id):
            from utils.fcm import send_push_async
            sender_name = f"{current_user.first_name or ''} {current_user.last_name or ''}".strip() or "Someone"
            sender_profile = db.query(UserProfile).filter(UserProfile.user_id == current_user.id).first()
            sender_avatar = sender_profile.profile_picture_url if sender_profile else None
            preview = content if content else (
                "📷 Photo" if any(str(a).lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".gif")) or
                                  (isinstance(a, dict) and str(a.get("url", "")).lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".gif")))
                                  for a in (attachments or [])) else "📎 Attachment"
            )
            send_push_async(
                db, recipient_id,
                title=sender_name,
                body=preview[:140],
                data={
                    "type": "message",
                    "conversation_id": str(conv.id),
                    "message_id": str(msg.id),
                    "sender_id": str(current_user.id),
                    "sender_name": sender_name,
                    "sender_avatar": sender_avatar or "",
                },
                high_priority=True,
                collapse_key=f"conv:{conv.id}",
                image=sender_avatar or None,
            )
    except Exception as _e:
        print(f"[messages] push fan-out skipped: {_e}")

    return standard_response(True, "Message sent successfully", {
        "id": str(msg.id),
        "content": msg.message_text,
        "attachments": msg.attachments or [],
        "reply_to_id": str(msg.reply_to_id) if msg.reply_to_id else None,
        "reply_snapshot": ({
            "text": msg.reply_snapshot_text,
            "sender": msg.reply_snapshot_sender,
        } if (msg.reply_snapshot_text or msg.reply_snapshot_sender) else None),
        "encryption_version": msg.encryption_version or "plain",
        "sent_at": msg.created_at.isoformat() if msg.created_at else now.isoformat(),
    })


@router.put("/{conversation_id}/read")
def mark_as_read(conversation_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Marks all messages from the other participant as read."""
    try:
        cid = uuid.UUID(conversation_id)
    except ValueError:
        return standard_response(False, "Invalid conversation ID")

    db.query(Message).filter(
        Message.conversation_id == cid,
        Message.sender_id != current_user.id,
        Message.is_read == False
    ).update({"is_read": True}, synchronize_session=False)
    db.commit()
    return standard_response(True, "Messages marked as read")


@router.delete("/{conversation_id}/messages/{message_id}")
def delete_message(conversation_id: str, message_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Soft-deletes a message sent by the current user."""
    try:
        mid = uuid.UUID(message_id)
    except ValueError:
        return standard_response(False, "Invalid message ID")

    msg = db.query(Message).filter(Message.id == mid, Message.sender_id == current_user.id).first()
    if not msg:
        return standard_response(False, "Message not found or not yours")

    msg.message_text = "[Message deleted]"
    db.commit()
    return standard_response(True, "Message deleted successfully")


@router.post("/{conversation_id}/archive")
def archive_conversation(conversation_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Deactivates a conversation."""
    try:
        cid = uuid.UUID(conversation_id)
    except ValueError:
        return standard_response(False, "Invalid conversation ID")

    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if conv:
        conv.is_active = False
        db.commit()
    return standard_response(True, "Conversation archived")


@router.post("/{conversation_id}/unarchive")
def unarchive_conversation(conversation_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Re-activates an archived conversation."""
    try:
        cid = uuid.UUID(conversation_id)
    except ValueError:
        return standard_response(False, "Invalid conversation ID")

    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if conv:
        conv.is_active = True
        db.commit()
    return standard_response(True, "Conversation unarchived")


@router.delete("/{conversation_id}")
def hide_conversation(conversation_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Per-user soft delete: hides this conversation from the caller's inbox.

    The other participant still sees it. The chat reappears for the caller
    if a new message arrives after the hide timestamp.
    """
    try:
        cid = uuid.UUID(conversation_id)
    except ValueError:
        return standard_response(False, "Invalid conversation ID")

    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if not conv:
        return standard_response(False, "Conversation not found")
    if str(conv.user_one_id) != str(current_user.id) and str(conv.user_two_id) != str(current_user.id):
        return standard_response(False, "You are not a participant in this conversation")

    now = datetime.now(EAT).replace(tzinfo=None)
    existing = db.query(ConversationHide).filter(
        ConversationHide.conversation_id == cid,
        ConversationHide.user_id == current_user.id,
    ).first()
    if existing:
        existing.hidden_at = now
    else:
        db.add(ConversationHide(conversation_id=cid, user_id=current_user.id, hidden_at=now))

    # Mark all unread messages as read for this user so the inbox badge clears.
    db.query(Message).filter(
        Message.conversation_id == cid,
        Message.sender_id != current_user.id,
        Message.is_read == False,
    ).update({"is_read": True}, synchronize_session=False)
    db.commit()
    return standard_response(True, "Conversation removed")
