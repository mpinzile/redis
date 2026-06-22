"""
Event Meetings API
Committee members and invited guests can schedule and join video meetings.
Uses LiveKit for WebRTC video conferencing.
Supports waiting room, co-hosts, reactions, and host controls.
"""

import uuid
import time
import json
import hmac
import hashlib
import base64
from datetime import datetime
from dateutil import parser as dtparser
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from typing import Optional, List

from core.database import get_db
from utils.auth import get_current_user, get_optional_user
from models.meetings import EventMeeting, EventMeetingParticipant, EventMeetingJoinRequest
from models.events import Event
from models.committees import EventCommitteeMember
from models.users import User
from models.enums import MeetingStatusEnum, MeetingParticipantRoleEnum, MeetingJoinRequestStatusEnum
from utils.whatsapp import wa_meeting_invitation
from utils.sms import sms_meeting_invitation
from utils.notify import notify_meeting_invitation

router = APIRouter(prefix="/events/{event_id}/meetings", tags=["meetings"])


# ── Schemas ──────────────────────────────────

class CreateMeetingRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    scheduled_at: str
    timezone: Optional[str] = "UTC"
    duration_minutes: Optional[str] = "60"
    participant_user_ids: Optional[List[str]] = []

class UpdateMeetingRequest(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    scheduled_at: Optional[str] = None
    timezone: Optional[str] = None
    duration_minutes: Optional[str] = None

class AddParticipantsRequest(BaseModel):
    user_ids: List[str]

class ReviewJoinRequestBody(BaseModel):
    action: str = Field(..., pattern="^(approve|reject)$")

class SetCoHostRequest(BaseModel):
    user_id: str
    is_co_host: bool = True


# ── Helpers ──────────────────────────────────

def _check_event_access(event_id: str, user_id: str, db: Session) -> Event:
    """Verify event exists and user has access (creator or committee member)."""
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found.")

    if str(event.organizer_id) == user_id:
        return event

    member = db.query(EventCommitteeMember).filter(
        EventCommitteeMember.event_id == event_id,
        EventCommitteeMember.user_id == user_id
    ).first()
    if not member:
        raise HTTPException(status_code=403, detail="You don't have access to this event.")
    return event


def _generate_room_id(event_id: str) -> str:
    """Generate a unique Jitsi room ID."""
    short_id = uuid.uuid4().hex[:8]
    return f"nuru-{event_id[:8]}-{short_id}"


def _generate_passcode() -> str:
    """Generate a 6-digit numeric meeting passcode."""
    import secrets
    return f"{secrets.randbelow(900000) + 100000}"


def _is_host_or_cohost(meeting: EventMeeting, user_id: str, db: Session) -> bool:
    """True if user is the meeting creator, a co-host, or the event organizer."""
    if str(meeting.created_by) == user_id:
        return True
    # Event organizer always has host-level control over meetings on their event
    event = db.query(Event).filter(Event.id == meeting.event_id).first()
    if event and str(event.organizer_id) == user_id:
        return True
    participant = db.query(EventMeetingParticipant).filter(
        EventMeetingParticipant.meeting_id == meeting.id,
        EventMeetingParticipant.user_id == user_id,
        EventMeetingParticipant.role == MeetingParticipantRoleEnum.co_host
    ).first()
    return participant is not None


def _notify_participants(meeting: EventMeeting, participants, event: Event, db: Session):
    """Send WhatsApp-first notifications to meeting participants."""
    from utils.message_templates import resolve_user_language
    from utils.datetime_format import format_event_datetime
    from utils.meeting_redirect import mint_meeting_redirect_token

    event_tz = getattr(event, "timezone", None) or "Africa/Nairobi"
    for p in participants:
        user = db.query(User).filter(User.id == p.user_id).first()
        if not user:
            continue

        phone = getattr(user, 'phone', None) or getattr(user, 'phone_number', None)
        meeting_link = f"https://nuru.tz/meet/{meeting.room_id}"
        event_name = event.name
        lang = resolve_user_language(db, p.user_id)
        scheduled_time = (
            format_event_datetime(meeting.scheduled_at, lang, event_tz)
            if meeting.scheduled_at else ""
        )

        # WhatsApp first (Meta template), then SMS fallback (catalogue body)
        wa_sent = False
        if phone:
            try:
                # Mint a per-participant redirect token so the WhatsApp
                # dynamic URL button (https://nuru.tz/m/{{1}}) resolves
                # back to the real meeting URL without exposing it in
                # the message body. Falls back to inline link via SMS
                # if minting or WhatsApp delivery fails.
                redirect_token = mint_meeting_redirect_token(
                    db,
                    target_url=meeting_link,
                    meeting_id=meeting.id,
                    user_id=p.user_id,
                )
                wa_sent = wa_meeting_invitation(
                    phone, event_name, meeting.title, scheduled_time,
                    meeting_link,
                    meeting_redirect_token=redirect_token,
                    lang=lang,
                    meta={
                        "event_id": str(event.id),
                        "event_name": event_name,
                        "recipient_type": "participant",
                        "recipient_id": str(p.user_id),
                        "recipient_name": getattr(user, "full_name", None) or getattr(user, "first_name", None),
                        "message_purpose": "meeting_invitation",
                        "source_module": "meetings",
                        "related_entity_type": "meeting",
                        "related_entity_id": str(meeting.id),
                    },
                )

            except Exception as e:
                print(f"[Meeting] WhatsApp invitation failed for {phone}: {e}")

            if not wa_sent:
                try:
                    sms_meeting_invitation(phone, event_name, meeting.title, scheduled_time, meeting_link, lang=lang)
                except Exception as e:
                    print(f"[Meeting] SMS invitation also failed for {phone}: {e}")

        # In-app notification always
        try:
            notify_meeting_invitation(str(p.user_id), event_name, meeting.title, str(meeting.id), db)
        except Exception as e:
            print(f"[Meeting] In-app notification failed for {p.user_id}: {e}")

        p.is_notified = True

    db.commit()


# ── Routes ───────────────────────────────────

@router.post("", status_code=201)
def create_meeting(event_id: str, body: CreateMeetingRequest, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Schedule a new meeting for this event."""
    user_id = str(current_user.id)
    event = _check_event_access(event_id, user_id, db)

    room_id = _generate_room_id(event_id)

    meeting = EventMeeting(
        event_id=event_id,
        created_by=user_id,
        title=body.title,
        description=body.description,
        scheduled_at=dtparser.parse(body.scheduled_at),
        timezone=body.timezone or "UTC",
        duration_minutes=body.duration_minutes or "60",
        room_id=room_id,
        passcode=_generate_passcode(),
        status=MeetingStatusEnum.scheduled,
    )
    db.add(meeting)
    db.flush()

    # Add creator as participant with creator role
    creator_participant = EventMeetingParticipant(
        meeting_id=meeting.id,
        user_id=user_id,
        invited_by=user_id,
        role=MeetingParticipantRoleEnum.creator,
    )
    db.add(creator_participant)

    # Add requested participants
    new_participants = []
    for uid in (body.participant_user_ids or []):
        if uid == user_id:
            continue
        p = EventMeetingParticipant(
            meeting_id=meeting.id,
            user_id=uid,
            invited_by=user_id,
            role=MeetingParticipantRoleEnum.participant,
        )
        db.add(p)
        new_participants.append(p)

    db.commit()
    db.refresh(meeting)

    # Notify participants (WhatsApp-first)
    _notify_participants(meeting, new_participants, event, db)

    return {
        "success": True,
        "message": "Meeting scheduled. Invitations sent to participants.",
        "data": _serialize_meeting(meeting, db)
    }


@router.get("")
def list_meetings(
    event_id: str,
    page: int = 1,
    limit: int = 20,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """List meetings for this event (paginated, newest first)."""
    user_id = str(current_user.id)
    _check_event_access(event_id, user_id, db)

    from sqlalchemy import func as sa_func
    page = max(1, int(page or 1))
    limit = max(1, min(int(limit or 20), 100))

    total = db.query(sa_func.count(EventMeeting.id)).filter(EventMeeting.event_id == event_id).scalar() or 0
    meetings = (
        db.query(EventMeeting)
        .filter(EventMeeting.event_id == event_id)
        .order_by(EventMeeting.scheduled_at.desc())
        .offset((page - 1) * limit).limit(limit).all()
    )

    from utils.batch_loaders import build_meeting_dicts
    total_pages = (total + limit - 1) // limit if limit else 1
    return {
        "success": True,
        "data": build_meeting_dicts(db, meetings),
        "pagination": {
            "page": page, "limit": limit, "total_items": int(total),
            "total_pages": total_pages, "has_next": page < total_pages, "has_previous": page > 1,
        },
    }


@router.get("/{meeting_id}")
def get_meeting(event_id: str, meeting_id: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get meeting details."""
    user_id = str(current_user.id)
    _check_event_access(event_id, user_id, db)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")

    return {"success": True, "data": _serialize_meeting(meeting, db)}


@router.put("/{meeting_id}")
def update_meeting(event_id: str, meeting_id: str, body: UpdateMeetingRequest, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Update meeting details. Only the creator can update."""
    user_id = str(current_user.id)
    _check_event_access(event_id, user_id, db)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")
    if str(meeting.created_by) != user_id:
        raise HTTPException(status_code=403, detail="Only the meeting organizer can update this meeting.")
    if meeting.status != MeetingStatusEnum.scheduled:
        raise HTTPException(status_code=400, detail="Only scheduled meetings can be edited.")

    if body.title is not None:
        meeting.title = body.title
    if body.description is not None:
        meeting.description = body.description
    if body.scheduled_at is not None:
        meeting.scheduled_at = dtparser.parse(body.scheduled_at)
    if body.duration_minutes is not None:
        meeting.duration_minutes = body.duration_minutes
    if body.timezone is not None:
        meeting.timezone = body.timezone

    db.commit()
    db.refresh(meeting)

    return {"success": True, "message": "Meeting updated.", "data": _serialize_meeting(meeting, db)}


@router.delete("/{meeting_id}")
def delete_meeting(event_id: str, meeting_id: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Cancel and delete a meeting."""
    user_id = str(current_user.id)
    event = _check_event_access(event_id, user_id, db)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")

    is_creator = str(event.organizer_id) == user_id
    is_meeting_creator = str(meeting.created_by) == user_id
    if not is_creator and not is_meeting_creator:
        raise HTTPException(status_code=403, detail="You don't have permission to cancel this meeting.")

    db.delete(meeting)
    db.commit()

    return {"success": True, "message": "Meeting cancelled."}


@router.post("/{meeting_id}/participants")
def add_participants(event_id: str, meeting_id: str, body: AddParticipantsRequest, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Add participants to a meeting and notify them."""
    user_id = str(current_user.id)
    event = _check_event_access(event_id, user_id, db)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")

    existing_ids = {str(p.user_id) for p in meeting.participants}
    new_participants = []

    for uid in body.user_ids:
        if uid in existing_ids:
            continue
        p = EventMeetingParticipant(
            meeting_id=meeting.id,
            user_id=uid,
            invited_by=user_id,
            role=MeetingParticipantRoleEnum.participant,
        )
        db.add(p)
        new_participants.append(p)

    db.commit()

    _notify_participants(meeting, new_participants, event, db)

    return {
        "success": True,
        "message": f"{len(new_participants)} participant(s) added and notified.",
        "data": _serialize_meeting(meeting, db)
    }


@router.post("/{meeting_id}/join")
def join_meeting(event_id: str, meeting_id: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """
    Join a meeting. Only invited participants can join directly.
    Non-invited users must request to join (waiting room).
    Returns join status: 'joined', 'waiting', or 'rejected'.
    """
    user_id = str(current_user.id)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")

    if meeting.status == MeetingStatusEnum.ended:
        raise HTTPException(status_code=400, detail="This meeting has ended.")

    # Check if user is already a participant (invited)
    participant = db.query(EventMeetingParticipant).filter(
        EventMeetingParticipant.meeting_id == meeting_id,
        EventMeetingParticipant.user_id == user_id
    ).first()

    if participant:
        # Already invited - let them join, prevent duplicate active sessions
        if participant.joined_at and not participant.left_at:
            return {
                "success": True,
                "data": {
                    "status": "already_joined",
                    "room_id": meeting.room_id,
                    "meeting_url": f"https://nuru.tz/meet/{meeting.room_id}",
                    "title": meeting.title,
                }
            }
        participant.joined_at = datetime.utcnow()
        participant.left_at = None

        # Auto-start meeting if scheduled
        if meeting.status == MeetingStatusEnum.scheduled:
            meeting.status = MeetingStatusEnum.in_progress

        db.commit()

        return {
            "success": True,
            "data": {
                "status": "joined",
                "room_id": meeting.room_id,
                "meeting_url": f"https://nuru.tz/meet/{meeting.room_id}",
                "title": meeting.title,
            }
        }

    # Not invited - check for existing join request
    existing_request = db.query(EventMeetingJoinRequest).filter(
        EventMeetingJoinRequest.meeting_id == meeting_id,
        EventMeetingJoinRequest.user_id == user_id,
    ).first()

    if existing_request:
        if existing_request.status == MeetingJoinRequestStatusEnum.approved:
            # Was approved - add as participant and join
            p = EventMeetingParticipant(
                meeting_id=meeting_id,
                user_id=user_id,
                role=MeetingParticipantRoleEnum.participant,
                joined_at=datetime.utcnow(),
            )
            db.add(p)
            if meeting.status == MeetingStatusEnum.scheduled:
                meeting.status = MeetingStatusEnum.in_progress
            db.commit()
            return {
                "success": True,
                "data": {
                    "status": "joined",
                    "room_id": meeting.room_id,
                    "meeting_url": f"https://nuru.tz/meet/{meeting.room_id}",
                    "title": meeting.title,
                }
            }
        elif existing_request.status == MeetingJoinRequestStatusEnum.rejected:
            return {
                "success": False,
                "message": "Your request to join was declined by the host.",
                "data": {"status": "rejected"}
            }
        else:
            # Still waiting
            return {
                "success": True,
                "message": "Your request is pending approval from the host.",
                "data": {"status": "waiting", "request_id": str(existing_request.id)}
            }

    # Create new join request (waiting room)
    join_request = EventMeetingJoinRequest(
        meeting_id=meeting_id,
        user_id=user_id,
        status=MeetingJoinRequestStatusEnum.waiting,
    )
    db.add(join_request)
    db.commit()
    db.refresh(join_request)

    return {
        "success": True,
        "message": "Your request to join has been sent. Please wait for the host to admit you.",
        "data": {"status": "waiting", "request_id": str(join_request.id)}
    }


@router.get("/{meeting_id}/join-requests")
def list_join_requests(event_id: str, meeting_id: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """List pending join requests. Only creator/co-hosts can see these."""
    user_id = str(current_user.id)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")

    if not _is_host_or_cohost(meeting, user_id, db):
        raise HTTPException(status_code=403, detail="Only hosts can view join requests.")

    requests = db.query(EventMeetingJoinRequest).filter(
        EventMeetingJoinRequest.meeting_id == meeting_id,
        EventMeetingJoinRequest.status == MeetingJoinRequestStatusEnum.waiting,
    ).all()

    result = []
    for r in requests:
        user = db.query(User).filter(User.id == r.user_id).first()
        result.append({
            "id": str(r.id),
            "user_id": str(r.user_id),
            "name": f"{user.first_name or ''} {user.last_name or ''}".strip() if user else "Unknown",
            "avatar_url": getattr(user, 'avatar_url', None) if user else None,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        })

    return {"success": True, "data": result}


@router.post("/{meeting_id}/join-requests/{request_id}")
def review_join_request(event_id: str, meeting_id: str, request_id: str, body: ReviewJoinRequestBody, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Approve or reject a join request. Only creator/co-hosts."""
    user_id = str(current_user.id)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")

    if not _is_host_or_cohost(meeting, user_id, db):
        raise HTTPException(status_code=403, detail="Only hosts can review join requests.")

    join_request = db.query(EventMeetingJoinRequest).filter(
        EventMeetingJoinRequest.id == request_id,
        EventMeetingJoinRequest.meeting_id == meeting_id,
    ).first()
    if not join_request:
        raise HTTPException(status_code=404, detail="Join request not found.")

    if join_request.status != MeetingJoinRequestStatusEnum.waiting:
        raise HTTPException(status_code=400, detail="This request has already been reviewed.")

    join_request.reviewed_by = user_id
    join_request.reviewed_at = datetime.utcnow()

    if body.action == "approve":
        join_request.status = MeetingJoinRequestStatusEnum.approved
        # Add as participant
        p = EventMeetingParticipant(
            meeting_id=meeting_id,
            user_id=str(join_request.user_id),
            invited_by=user_id,
            role=MeetingParticipantRoleEnum.participant,
        )
        db.add(p)
        db.commit()
        return {"success": True, "message": "Participant admitted.", "data": {"status": "approved"}}
    else:
        join_request.status = MeetingJoinRequestStatusEnum.rejected
        db.commit()
        return {"success": True, "message": "Join request declined.", "data": {"status": "rejected"}}


@router.post("/{meeting_id}/co-host")
def set_co_host(event_id: str, meeting_id: str, body: SetCoHostRequest, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Promote/demote a participant to co-host. Only the creator can do this."""
    user_id = str(current_user.id)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")

    if str(meeting.created_by) != user_id:
        raise HTTPException(status_code=403, detail="Only the meeting creator can assign co-hosts.")

    participant = db.query(EventMeetingParticipant).filter(
        EventMeetingParticipant.meeting_id == meeting_id,
        EventMeetingParticipant.user_id == body.user_id,
    ).first()
    if not participant:
        raise HTTPException(status_code=404, detail="Participant not found in this meeting.")

    participant.role = MeetingParticipantRoleEnum.co_host if body.is_co_host else MeetingParticipantRoleEnum.participant
    db.commit()

    return {"success": True, "message": f"Participant {'promoted to co-host' if body.is_co_host else 'demoted to participant'}."}


@router.post("/{meeting_id}/leave")
def leave_meeting(event_id: str, meeting_id: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Record that a user has left the meeting."""
    user_id = str(current_user.id)

    participant = db.query(EventMeetingParticipant).filter(
        EventMeetingParticipant.meeting_id == meeting_id,
        EventMeetingParticipant.user_id == user_id
    ).first()

    if participant:
        participant.left_at = datetime.utcnow()
        db.commit()

    return {"success": True, "message": "Left the meeting."}


@router.post("/{meeting_id}/end")
def end_meeting(event_id: str, meeting_id: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """End a meeting. Only creator or co-hosts can end it."""
    user_id = str(current_user.id)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")

    if not _is_host_or_cohost(meeting, user_id, db):
        raise HTTPException(status_code=403, detail="Only hosts can end this meeting.")

    meeting.status = MeetingStatusEnum.ended
    meeting.ended_at = datetime.utcnow()
    db.commit()

    return {"success": True, "message": "Meeting ended."}


@router.get("/{meeting_id}/join-status")
def check_join_status(event_id: str, meeting_id: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Check if user's join request has been approved (polling endpoint for waiting room)."""
    user_id = str(current_user.id)

    # Check if already a participant
    participant = db.query(EventMeetingParticipant).filter(
        EventMeetingParticipant.meeting_id == meeting_id,
        EventMeetingParticipant.user_id == user_id
    ).first()
    if participant:
        return {"success": True, "data": {"status": "approved"}}

    # Check join request
    join_request = db.query(EventMeetingJoinRequest).filter(
        EventMeetingJoinRequest.meeting_id == meeting_id,
        EventMeetingJoinRequest.user_id == user_id,
    ).order_by(EventMeetingJoinRequest.created_at.desc()).first()

    if not join_request:
        return {"success": True, "data": {"status": "none"}}

    return {"success": True, "data": {"status": join_request.status.value}}


@router.post("/{meeting_id}/token")
def get_meeting_token(event_id: str, meeting_id: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Generate a LiveKit access token for the meeting room. Only admitted participants get tokens."""
    from core.config import LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET

    user_id = str(current_user.id)

    meeting = db.query(EventMeeting).filter(
        EventMeeting.id == meeting_id,
        EventMeeting.event_id == event_id
    ).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found.")

    # Must be an admitted participant to get a token
    participant = db.query(EventMeetingParticipant).filter(
        EventMeetingParticipant.meeting_id == meeting_id,
        EventMeetingParticipant.user_id == user_id
    ).first()
    if not participant:
        raise HTTPException(status_code=403, detail="You must be admitted to this meeting to get an access token.")

    if not LIVEKIT_API_KEY or not LIVEKIT_API_SECRET or not LIVEKIT_URL:
        raise HTTPException(status_code=500, detail="LiveKit not configured.")

    # Build participant identity
    user = db.query(User).filter(User.id == current_user.id).first()
    participant_name = f"{user.first_name or ''} {user.last_name or ''}".strip() if user else "Participant"
    participant_identity = user_id

    # Determine permissions based on role
    is_host = _is_host_or_cohost(meeting, user_id, db)

    # Get avatar URL for metadata
    avatar_url = user.profile.profile_picture_url if user and hasattr(user, 'profile') and user.profile else None
    # Generate LiveKit JWT token
    token = _create_livekit_token(
        api_key=LIVEKIT_API_KEY,
        api_secret=LIVEKIT_API_SECRET,
        room_name=meeting.room_id,
        participant_identity=participant_identity,
        participant_name=participant_name,
        is_host=is_host,
        metadata=json.dumps({"avatar_url": avatar_url or ""}),
    )

    return {
        "success": True,
        "data": {
            "token": token,
            "url": LIVEKIT_URL,
            "room_name": meeting.room_id,
            "participant_name": participant_name,
            "role": participant.role.value if participant.role else "participant",
            "is_host": is_host,
        }
    }


def _create_livekit_token(api_key: str, api_secret: str, room_name: str, participant_identity: str, participant_name: str, is_host: bool = False, metadata: str = "", ttl: int = 86400) -> str:
    """Create a LiveKit access token (JWT) without external libraries."""
    now = int(time.time())

    header = {"alg": "HS256", "typ": "JWT"}
    claims = {
        "iss": api_key,
        "sub": participant_identity,
        "name": participant_name,
        "nbf": now,
        "exp": now + ttl,
        "jti": f"{participant_identity}-{now}",
        "metadata": metadata,
        "video": {
            "room": room_name,
            "roomJoin": True,
            "canPublish": True,
            "canPublishSources": ["camera", "microphone", "screen_share", "screen_share_audio"],
            "canSubscribe": True,
            "canPublishData": True,
        },
    }

    # Hosts can also admin the room (mute others, kick, etc.)
    if is_host:
        claims["video"]["roomAdmin"] = True

    def _b64url(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    h = _b64url(json.dumps(header, separators=(",", ":")).encode())
    p = _b64url(json.dumps(claims, separators=(",", ":")).encode())
    sig = hmac.new(api_secret.encode(), f"{h}.{p}".encode(), hashlib.sha256).digest()
    return f"{h}.{p}.{_b64url(sig)}"


# ── Serialization ────────────────────────────

def _serialize_meeting(meeting: EventMeeting, db: Session) -> dict:
    from datetime import timedelta
    from models.meeting_documents import MeetingAgendaItem, MeetingMinutes

    # Auto-end meetings: if scheduled time + duration has passed and no active participants
    if meeting.status in (MeetingStatusEnum.in_progress, MeetingStatusEnum.scheduled):
        try:
            duration = int(meeting.duration_minutes or 60)
            end_time = meeting.scheduled_at + timedelta(minutes=duration)
            if datetime.utcnow() > end_time:
                # Check if anyone is still in the meeting (joined but not left)
                active_count = db.query(EventMeetingParticipant).filter(
                    EventMeetingParticipant.meeting_id == meeting.id,
                    EventMeetingParticipant.joined_at.isnot(None),
                    EventMeetingParticipant.left_at.is_(None),
                ).count()
                if active_count == 0:
                    meeting.status = MeetingStatusEnum.ended
                    meeting.ended_at = end_time
                    db.commit()
        except Exception:
            pass

    participants = []
    for p in meeting.participants:
        user = db.query(User).filter(User.id == p.user_id).first()

        avatar = user.profile.profile_picture_url if user and user.profile else None

        participants.append({
            "id": str(p.id),
            "user_id": str(p.user_id),
            "name": f"{user.first_name or ''} {user.last_name or ''}".strip() if user else "Unknown",
            "avatar_url": avatar,
            "is_notified": p.is_notified,
            "joined_at": p.joined_at.isoformat() if p.joined_at else None,
            "role": p.role.value if p.role else "participant",
        })

    creator = db.query(User).filter(User.id == meeting.created_by).first()

    has_agenda = db.query(MeetingAgendaItem).filter(MeetingAgendaItem.meeting_id == meeting.id).count() > 0
    has_minutes = db.query(MeetingMinutes).filter(MeetingMinutes.meeting_id == meeting.id).first() is not None

    # Count pending join requests
    pending_requests = db.query(EventMeetingJoinRequest).filter(
        EventMeetingJoinRequest.meeting_id == meeting.id,
        EventMeetingJoinRequest.status == MeetingJoinRequestStatusEnum.waiting,
    ).count()

    return {
        "id": str(meeting.id),
        "event_id": str(meeting.event_id),
        "title": meeting.title,
        "description": meeting.description,
        "scheduled_at": meeting.scheduled_at.isoformat() if meeting.scheduled_at else None,
        "timezone": getattr(meeting, 'timezone', None) or "UTC",
        "duration_minutes": meeting.duration_minutes,
        "room_id": meeting.room_id,
        "passcode": getattr(meeting, "passcode", None),
        "meeting_url": f"https://nuru.tz/meet/{meeting.room_id}",
        "status": meeting.status.value if meeting.status else "scheduled",
        "created_by": {
            "id": str(meeting.created_by),
            "name": f"{creator.first_name or ''} {creator.last_name or ''}".strip() if creator else "Unknown",
        },
        "participants": participants,
        "participant_count": len(participants),
        "pending_requests": pending_requests,
        "has_agenda": has_agenda,
        "has_minutes": has_minutes,
        "ended_at": meeting.ended_at.isoformat() if meeting.ended_at else None,
        "created_at": meeting.created_at.isoformat() if meeting.created_at else None,
    }
