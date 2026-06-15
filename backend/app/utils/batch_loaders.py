"""
Batch Loading Utilities
=======================
Eliminates N+1 query patterns by pre-loading related data for collections
of posts, comments, events, and notifications in bulk.

Instead of: 1 query per post × 7 tables × 20 posts = 140 queries
Now:         7 batch queries total regardless of page size
"""

from collections import defaultdict
from typing import List, Optional, Set, Dict, Any
from uuid import UUID

from sqlalchemy import func as sa_func
from sqlalchemy.orm import Session

from models import (
    User, UserProfile, UserFeed, UserFeedImage, UserFeedGlow, UserFeedEcho,
    UserFeedSpark, UserFeedComment, UserFeedCommentGlow, UserFeedPinned,
    UserFeedSaved, Event, EventImage, EventType, EventVenueCoordinate,
    EventSetting, EventAttendee, Notification,
    EventCommitteeMember, EventService, EventContribution,
    EventContributionTarget, Currency, RSVPStatusEnum,
    ServiceBookingRequest, UserService, UserServiceImage, ServiceCategory,
    ServiceType, EventExpense, CommitteeRole, CommitteePermission,
    UserContributor, EventContributor, EventInvitation, EventGuestPlusOne,
    ContributionStatusEnum, EventTicketClass, EventTicket, TicketOrderStatusEnum,
)
from models.meetings import EventMeeting, EventMeetingParticipant, EventMeetingJoinRequest
from models.meeting_documents import MeetingAgendaItem, MeetingMinutes
from models.enums import MeetingStatusEnum, MeetingJoinRequestStatusEnum


# ─────────────────────────────────────────────────────────
# User + Profile batch loader
# ─────────────────────────────────────────────────────────

def batch_load_users(db: Session, user_ids: Set[UUID]) -> Dict[str, Dict]:
    """Load users + profiles for a set of user IDs. Returns {str(user_id): dict}."""
    if not user_ids:
        return {}

    uid_list = list(user_ids)
    users = db.query(User).filter(User.id.in_(uid_list)).all()
    profiles = db.query(UserProfile).filter(UserProfile.user_id.in_(uid_list)).all()

    profile_map = {str(p.user_id): p for p in profiles}
    result = {}
    for u in users:
        uid = str(u.id)
        p = profile_map.get(uid)
        result[uid] = {
            "id": uid,
            "name": f"{u.first_name} {u.last_name}",
            "first_name": u.first_name,
            "last_name": u.last_name,
            "username": u.username,
            "avatar": p.profile_picture_url if p else None,
            "is_verified": u.is_identity_verified or False,
            "is_identity_verified": u.is_identity_verified or False,
        }
    return result


# ─────────────────────────────────────────────────────────
# Post batch loaders
# ─────────────────────────────────────────────────────────

def batch_load_post_images(db: Session, post_ids: List[UUID]) -> Dict[str, list]:
    """Returns {str(post_id): [image_dicts]}."""
    if not post_ids:
        return {}
    images = db.query(UserFeedImage).filter(UserFeedImage.feed_id.in_(post_ids)).all()
    result = defaultdict(list)
    for img in images:
        result[str(img.feed_id)].append({
            "url": img.image_url,
            "media_type": getattr(img, 'media_type', None) or 'image',
        })
    return dict(result)


def batch_load_post_counts(db: Session, post_ids: List[UUID]) -> Dict[str, Dict[str, int]]:
    """
    Returns {str(post_id): {glow_count, echo_count, spark_count, comment_count}}.
    4 grouped COUNT queries instead of 4×N individual queries.
    """
    if not post_ids:
        return {}

    result = {str(pid): {"glow_count": 0, "echo_count": 0, "spark_count": 0, "comment_count": 0} for pid in post_ids}

    # Glows
    for pid, cnt in db.query(UserFeedGlow.feed_id, sa_func.count(UserFeedGlow.id)).filter(
        UserFeedGlow.feed_id.in_(post_ids)
    ).group_by(UserFeedGlow.feed_id).all():
        result[str(pid)]["glow_count"] = cnt

    # Echoes
    for pid, cnt in db.query(UserFeedEcho.feed_id, sa_func.count(UserFeedEcho.id)).filter(
        UserFeedEcho.feed_id.in_(post_ids)
    ).group_by(UserFeedEcho.feed_id).all():
        result[str(pid)]["echo_count"] = cnt

    # Sparks
    for pid, cnt in db.query(UserFeedSpark.feed_id, sa_func.count(UserFeedSpark.id)).filter(
        UserFeedSpark.feed_id.in_(post_ids)
    ).group_by(UserFeedSpark.feed_id).all():
        result[str(pid)]["spark_count"] = cnt

    # Comments (active only)
    for pid, cnt in db.query(UserFeedComment.feed_id, sa_func.count(UserFeedComment.id)).filter(
        UserFeedComment.feed_id.in_(post_ids),
        UserFeedComment.is_active == True,
    ).group_by(UserFeedComment.feed_id).all():
        result[str(pid)]["comment_count"] = cnt

    return result


def batch_load_user_interactions(
    db: Session, post_ids: List[UUID], current_user_id: UUID
) -> Dict[str, Dict[str, bool]]:
    """
    Returns {str(post_id): {has_glowed, has_echoed, has_saved, is_pinned}}.
    4 queries instead of 4×N.
    """
    if not post_ids or not current_user_id:
        return {}

    result = {str(pid): {"has_glowed": False, "has_echoed": False, "has_saved": False, "is_pinned": False, "glow_emoji": None} for pid in post_ids}

    glow_rows = db.query(UserFeedGlow.feed_id, UserFeedGlow.emoji).filter(
        UserFeedGlow.feed_id.in_(post_ids), UserFeedGlow.user_id == current_user_id
    ).all()
    glowed_ids = {str(r[0]) for r in glow_rows}
    glow_emoji_map = {str(r[0]): r[1] for r in glow_rows}

    echoed_ids = {str(r[0]) for r in db.query(UserFeedEcho.feed_id).filter(
        UserFeedEcho.feed_id.in_(post_ids), UserFeedEcho.user_id == current_user_id
    ).all()}

    saved_ids = {str(r[0]) for r in db.query(UserFeedSaved.feed_id).filter(
        UserFeedSaved.feed_id.in_(post_ids), UserFeedSaved.user_id == current_user_id
    ).all()}

    pinned_ids = {str(r[0]) for r in db.query(UserFeedPinned.feed_id).filter(
        UserFeedPinned.feed_id.in_(post_ids)
    ).all()}

    for pid_str in result:
        result[pid_str]["has_glowed"] = pid_str in glowed_ids
        result[pid_str]["has_echoed"] = pid_str in echoed_ids
        result[pid_str]["has_saved"] = pid_str in saved_ids
        result[pid_str]["is_pinned"] = pid_str in pinned_ids
        result[pid_str]["glow_emoji"] = glow_emoji_map.get(pid_str)

    return result


def batch_load_shared_events(db: Session, event_ids: List[UUID]) -> Dict[str, Dict]:
    """Pre-load shared event data for event_share posts."""
    if not event_ids:
        return {}
    events = db.query(Event).filter(Event.id.in_(event_ids)).all()
    event_images = db.query(EventImage).filter(EventImage.event_id.in_(event_ids)).all()

    img_map = defaultdict(list)
    for img in event_images:
        img_map[str(img.event_id)].append(img.image_url)

    result = {}
    for event in events:
        eid = str(event.id)
        cover = event.cover_image_url
        gallery = img_map.get(eid, [])
        if cover and cover not in gallery:
            gallery.insert(0, cover)
        result[eid] = {
            "id": eid,
            "title": event.name,
            "description": event.description,
            "start_date": event.start_date.isoformat() if event.start_date else None,
            "end_date": event.end_date.isoformat() if event.end_date else None,
            "start_time": event.start_time.strftime("%H:%M") if event.start_time else None,
            "location": event.location,
            "cover_image": cover,
            "images": gallery,
            "event_type": event.event_type.name if event.event_type else None,
            "sells_tickets": getattr(event, 'sells_tickets', False) or False,
            "is_public": getattr(event, 'is_public', False) or False,
            "expected_guests": event.expected_guests,
            "dress_code": event.dress_code,
        }
    return result


# ─────────────────────────────────────────────────────────
# Build post dicts from pre-loaded batch data
# ─────────────────────────────────────────────────────────

def build_post_dicts(
    db: Session,
    posts: List[UserFeed],
    current_user_id: Optional[UUID] = None,
) -> List[Dict]:
    """
    Converts a list of UserFeed objects to API response dicts using
    batch loading. Total queries: ~11 regardless of list size.
    """
    if not posts:
        return []

    post_ids = [p.id for p in posts]
    author_ids = {p.user_id for p in posts}

    # Batch load all related data in parallel-style (sequential but batched)
    users_map = batch_load_users(db, author_ids)
    images_map = batch_load_post_images(db, post_ids)
    counts_map = batch_load_post_counts(db, post_ids)
    interactions_map = (
        batch_load_user_interactions(db, post_ids, current_user_id)
        if current_user_id else {}
    )

    # Load shared events for event_share posts
    shared_event_ids = [
        p.shared_event_id for p in posts
        if p.post_type == "event_share" and p.shared_event_id
    ]
    shared_events_map = batch_load_shared_events(db, shared_event_ids) if shared_event_ids else {}

    result = []
    for post in posts:
        pid_str = str(post.id)
        uid_str = str(post.user_id)
        user_info = users_map.get(uid_str, {})
        counts = counts_map.get(pid_str, {})
        interactions = interactions_map.get(pid_str, {})

        post_dict = {
            "id": pid_str,
            "author": {
                "id": user_info.get("id"),
                "name": user_info.get("name"),
                "username": user_info.get("username"),
                "avatar": user_info.get("avatar"),
                "is_verified": user_info.get("is_verified", False),
            },
            "content": post.content,
            "images": images_map.get(pid_str, []),
            "location": post.location,
            "visibility": post.visibility.value if post.visibility else "public",
            "post_type": post.post_type or "post",
            "glow_count": counts.get("glow_count", 0),
            "echo_count": counts.get("echo_count", 0),
            "spark_count": counts.get("spark_count", 0),
            "comment_count": counts.get("comment_count", 0),
            "has_glowed": interactions.get("has_glowed", False),
            "glow_emoji": interactions.get("glow_emoji"),
            "has_echoed": interactions.get("has_echoed", False),
            "has_saved": interactions.get("has_saved", False),
            "is_pinned": interactions.get("is_pinned", False),
            "created_at": post.created_at.isoformat() if post.created_at else None,
        }

        # Shared event data
        if post.post_type == "event_share" and post.shared_event_id:
            event_data = shared_events_map.get(str(post.shared_event_id))
            if event_data:
                post_dict["shared_event"] = event_data
                post_dict["share_expires_at"] = post.share_expires_at.isoformat() if post.share_expires_at else None

        result.append(post_dict)

    return result


# ─────────────────────────────────────────────────────────
# Comment batch loaders
# ─────────────────────────────────────────────────────────

def batch_load_comment_counts(db: Session, comment_ids: List[UUID]) -> Dict[str, Dict]:
    """Returns {str(comment_id): {glow_count, reply_count}}."""
    if not comment_ids:
        return {}

    result = {str(cid): {"glow_count": 0, "reply_count": 0} for cid in comment_ids}

    for cid, cnt in db.query(UserFeedCommentGlow.comment_id, sa_func.count(UserFeedCommentGlow.id)).filter(
        UserFeedCommentGlow.comment_id.in_(comment_ids)
    ).group_by(UserFeedCommentGlow.comment_id).all():
        result[str(cid)]["glow_count"] = cnt

    for cid, cnt in db.query(UserFeedComment.parent_comment_id, sa_func.count(UserFeedComment.id)).filter(
        UserFeedComment.parent_comment_id.in_(comment_ids),
        UserFeedComment.is_active == True,
    ).group_by(UserFeedComment.parent_comment_id).all():
        result[str(cid)]["reply_count"] = cnt

    return result


def batch_load_comment_glowed(db: Session, comment_ids: List[UUID], user_id: UUID) -> Set[str]:
    """Returns set of str(comment_id) that user has glowed."""
    if not comment_ids or not user_id:
        return set()
    return {str(r[0]) for r in db.query(UserFeedCommentGlow.comment_id).filter(
        UserFeedCommentGlow.comment_id.in_(comment_ids),
        UserFeedCommentGlow.user_id == user_id,
    ).all()}


def build_comment_dicts(
    db: Session,
    comments: List,
    current_user_id: Optional[UUID] = None,
    include_replies_preview: bool = True,
) -> List[Dict]:
    """Batch-build comment dicts. ~5 queries total instead of 5×N."""
    if not comments:
        return []

    comment_ids = [c.id for c in comments]
    author_ids = {c.user_id for c in comments}

    users_map = batch_load_users(db, author_ids)
    counts_map = batch_load_comment_counts(db, comment_ids)
    glowed_set = batch_load_comment_glowed(db, comment_ids, current_user_id) if current_user_id else set()

    # Pre-load reply previews for top-level comments
    replies_map = {}
    if include_replies_preview:
        top_level_ids = [c.id for c in comments if not c.parent_comment_id]
        if top_level_ids:
            # Get first 2 replies per top-level comment using a window function approach
            # Simpler: just get all replies for these parents, limit in Python
            all_replies = (
                db.query(UserFeedComment)
                .filter(
                    UserFeedComment.parent_comment_id.in_(top_level_ids),
                    UserFeedComment.is_active == True,
                )
                .order_by(UserFeedComment.parent_comment_id, UserFeedComment.created_at.asc())
                .all()
            )
            # Group and take first 2
            grouped = defaultdict(list)
            for r in all_replies:
                pid = str(r.parent_comment_id)
                if len(grouped[pid]) < 2:
                    grouped[pid].append(r)

            # Build reply dicts (without further nesting)
            all_reply_objects = [r for replies in grouped.values() for r in replies]
            if all_reply_objects:
                reply_dicts = build_comment_dicts(db, all_reply_objects, current_user_id, include_replies_preview=False)
                reply_dict_map = {d["id"]: d for d in reply_dicts}
                for pid_str, replies in grouped.items():
                    replies_map[pid_str] = [reply_dict_map[str(r.id)] for r in replies if str(r.id) in reply_dict_map]

    result = []
    for comment in comments:
        cid = str(comment.id)
        uid = str(comment.user_id)
        author = users_map.get(uid)
        counts = counts_map.get(cid, {})

        d = {
            "id": cid,
            "content": comment.content,
            "author": author,
            "glow_count": counts.get("glow_count", 0),
            "reply_count": counts.get("reply_count", 0),
            "has_glowed": cid in glowed_set,
            "is_edited": comment.is_edited or False,
            "is_pinned": comment.is_pinned or False,
            "parent_id": str(comment.parent_comment_id) if comment.parent_comment_id else None,
            "created_at": comment.created_at.isoformat() if comment.created_at else None,
            "updated_at": comment.updated_at.isoformat() if comment.updated_at else None,
        }

        if include_replies_preview and not comment.parent_comment_id:
            d["replies_preview"] = replies_map.get(cid, [])

        result.append(d)

    return result


# ─────────────────────────────────────────────────────────
# Event batch loaders
# ─────────────────────────────────────────────────────────

def build_public_event_dicts(db: Session, events: List[Event]) -> List[Dict]:
    """Batch-build public event summary dicts. ~6 queries instead of 6×N."""
    if not events:
        return []

    event_ids = [e.id for e in events]
    organizer_ids = {e.organizer_id for e in events if e.organizer_id}
    event_type_ids = {e.event_type_id for e in events if e.event_type_id}

    # Batch load event types
    event_types = {}
    if event_type_ids:
        for et in db.query(EventType).filter(EventType.id.in_(list(event_type_ids))).all():
            event_types[str(et.id)] = {"id": str(et.id), "name": et.name, "icon": et.icon}

    # Batch load venue coordinates
    venues = {}
    for vc in db.query(EventVenueCoordinate).filter(EventVenueCoordinate.event_id.in_(event_ids)).all():
        venues[str(vc.event_id)] = vc

    # Settings are not used in the search/list payload, skip the query
    # to keep this path light and fast.

    # Batch load images
    images_map = defaultdict(list)
    for img in db.query(EventImage).filter(EventImage.event_id.in_(event_ids)).order_by(
        EventImage.is_featured.desc(), EventImage.created_at.asc()
    ).all():
        images_map[str(img.event_id)].append({"id": str(img.id), "image_url": img.image_url, "is_featured": img.is_featured})

    # Batch load guest counts
    guest_counts = {}
    for eid, cnt in db.query(EventAttendee.event_id, sa_func.count(EventAttendee.id)).filter(
        EventAttendee.event_id.in_(event_ids)
    ).group_by(EventAttendee.event_id).all():
        guest_counts[str(eid)] = cnt

    # Batch load organizers
    organizers = batch_load_users(db, organizer_ids)

    result = []
    for event in events:
        eid = str(event.id)
        images_list = images_map.get(eid, [])
        cover = event.cover_image_url
        if not cover:
            for img in images_list:
                if img["is_featured"]:
                    cover = img["image_url"]
                    break
            if not cover and images_list:
                cover = images_list[0]["image_url"]

        vc = venues.get(eid)
        org = organizers.get(str(event.organizer_id), {})
        et_id = str(event.event_type_id) if event.event_type_id else None
        et = event_types.get(et_id) if et_id else None

        result.append({
            "id": eid,
            "title": event.name,
            "description": event.description,
            "event_type": et,
            "start_date": event.start_date.isoformat() if event.start_date else None,
            "start_time": event.start_time.strftime("%H:%M") if event.start_time else None,
            "end_date": event.end_date.isoformat() if event.end_date else None,
            "location": event.location,
            "venue": vc.venue_name if vc else None,
            "venue_address": vc.formatted_address if vc else None,
            "cover_image": cover,
            "images": images_list,
            "theme_color": event.theme_color,
            "dress_code": event.dress_code,
            "special_instructions": event.special_instructions,
            "guest_count": guest_counts.get(eid, 0),
            "organizer": {"name": org.get("name")},
            "sells_tickets": event.sells_tickets or False,
            "status": "published" if (event.status.value if hasattr(event.status, "value") else event.status) == "confirmed" else (event.status.value if hasattr(event.status, "value") else event.status),
            "created_at": event.created_at.isoformat() if event.created_at else None,
        })

    return result


# ─────────────────────────────────────────────────────────
# Notification batch loader
# ─────────────────────────────────────────────────────────

def build_notification_dicts(db: Session, notifications: list) -> List[Dict]:
    """Batch-build notification dicts. 2 queries instead of 2×N."""
    if not notifications:
        return []

    # Collect all sender IDs
    sender_ids = set()
    for n in notifications:
        if n.sender_ids and len(n.sender_ids) > 0:
            try:
                from uuid import UUID as _UUID
                sender_ids.add(_UUID(n.sender_ids[0]))
            except (ValueError, IndexError):
                pass

    users_map = batch_load_users(db, sender_ids) if sender_ids else {}

    result = []
    for n in notifications:
        sender_info = None
        if n.sender_ids and len(n.sender_ids) > 0:
            sid = n.sender_ids[0]
            u = users_map.get(sid)
            if u:
                sender_info = {
                    "id": u["id"],
                    "first_name": u["first_name"],
                    "last_name": u["last_name"],
                    "username": u.get("username"),
                    "avatar": u.get("avatar"),
                }

        result.append({
            "id": str(n.id),
            "type": n.type.value if n.type else None,
            "message": n.message_template,
            "data": n.message_data,
            "is_read": n.is_read,
            "reference_id": str(n.reference_id) if n.reference_id else None,
            "reference_type": n.reference_type,
            "actor": sender_info,
            "created_at": n.created_at.isoformat() if n.created_at else None,
        })

    return result


# ─────────────────────────────────────────────────────────
# Event summary batch loader (replaces _event_summary N+1)
# ─────────────────────────────────────────────────────────

def batch_load_event_context(db: Session, event_ids: List[UUID]) -> Dict[str, Dict[str, Any]]:
    """
    Pre-load all per-event context needed by _event_summary in a handful of
    grouped queries instead of 8 queries per event.

    Returns: {str(event_id): {event_type, settings, vc, committee_count,
              service_count, images, contribution_target, contribution_target_obj,
              guest_counts, contribution_summary}}
    """
    if not event_ids:
        return {}

    eid_list = list(event_ids)
    eid_strs = [str(e) for e in eid_list]
    base = {s: {
        "event_type": None, "settings": None, "vc": None,
        "committee_count": 0, "service_count": 0, "images": [],
        "contribution_target": 0.0, "contribution_target_obj": None,
        "guest_counts": {"guest_count": 0, "confirmed_guest_count": 0,
                          "pending_guest_count": 0, "declined_guest_count": 0,
                          "maybe_guest_count": 0, "checked_in_count": 0},
        "contribution_summary": {"contribution_total": 0.0, "contribution_count": 0},
        "tickets_sold": 0, "tickets_capacity": 0,
        "invitations_sent": 0, "invitations_total": 0,
    } for s in eid_strs}

    # Pull events to obtain event_type_ids in one query (caller already has them but cheap)
    events = db.query(Event.id, Event.event_type_id).filter(Event.id.in_(eid_list)).all()
    et_ids = {e.event_type_id for e in events if e.event_type_id}
    et_map: Dict[str, EventType] = {}
    if et_ids:
        for et in db.query(EventType).filter(EventType.id.in_(list(et_ids))).all():
            et_map[str(et.id)] = et
    for e in events:
        if e.event_type_id:
            base[str(e.id)]["event_type"] = et_map.get(str(e.event_type_id))

    # Settings
    for s in db.query(EventSetting).filter(EventSetting.event_id.in_(eid_list)).all():
        base[str(s.event_id)]["settings"] = s

    # Venue coords
    for vc in db.query(EventVenueCoordinate).filter(EventVenueCoordinate.event_id.in_(eid_list)).all():
        base[str(vc.event_id)]["vc"] = vc

    # Committee count
    for eid, cnt in db.query(EventCommitteeMember.event_id, sa_func.count(EventCommitteeMember.id)).filter(
        EventCommitteeMember.event_id.in_(eid_list)
    ).group_by(EventCommitteeMember.event_id).all():
        base[str(eid)]["committee_count"] = cnt

    # Service count
    for eid, cnt in db.query(EventService.event_id, sa_func.count(EventService.id)).filter(
        EventService.event_id.in_(eid_list)
    ).group_by(EventService.event_id).all():
        base[str(eid)]["service_count"] = cnt

    # Images
    images_by_event: Dict[str, List[Dict]] = defaultdict(list)
    for img in db.query(EventImage).filter(EventImage.event_id.in_(eid_list)).order_by(
        EventImage.is_featured.desc(), EventImage.created_at.asc()
    ).all():
        images_by_event[str(img.event_id)].append({
            "id": str(img.id), "image_url": img.image_url, "caption": img.caption,
            "is_featured": img.is_featured,
            "created_at": img.created_at.isoformat() if img.created_at else None,
        })
    for k, v in images_by_event.items():
        base[k]["images"] = v

    # Contribution targets
    for ct in db.query(EventContributionTarget).filter(EventContributionTarget.event_id.in_(eid_list)).all():
        base[str(ct.event_id)]["contribution_target_obj"] = ct
        base[str(ct.event_id)]["contribution_target"] = float(ct.target_amount or 0)
    # Settings.contribution_target_amount overrides if present
    for k, v in base.items():
        s = v["settings"]
        if s and getattr(s, "contribution_target_amount", None):
            v["contribution_target"] = float(s.contribution_target_amount)

    # Guest counts (rsvp_status grouped)
    for eid, status, cnt in db.query(
        EventAttendee.event_id, EventAttendee.rsvp_status, sa_func.count(EventAttendee.id)
    ).filter(EventAttendee.event_id.in_(eid_list)).group_by(
        EventAttendee.event_id, EventAttendee.rsvp_status
    ).all():
        key = status.value if hasattr(status, "value") else status
        gc = base[str(eid)]["guest_counts"]
        gc["guest_count"] += cnt
        if key == "confirmed":
            gc["confirmed_guest_count"] = cnt
        elif key == "pending":
            gc["pending_guest_count"] = cnt
        elif key == "declined":
            gc["declined_guest_count"] = cnt
        elif key == "maybe":
            gc["maybe_guest_count"] = cnt

    # Checked in
    for eid, cnt in db.query(
        EventAttendee.event_id, sa_func.count(EventAttendee.id)
    ).filter(EventAttendee.event_id.in_(eid_list), EventAttendee.checked_in == True).group_by(
        EventAttendee.event_id
    ).all():
        base[str(eid)]["guest_counts"]["checked_in_count"] = cnt

    # Contribution summary (confirmed only)
    for eid, total, cnt in db.query(
        EventContribution.event_id,
        sa_func.coalesce(sa_func.sum(EventContribution.amount), 0),
        sa_func.count(EventContribution.id),
    ).filter(
        EventContribution.event_id.in_(eid_list),
        EventContribution.confirmation_status == "confirmed",
    ).group_by(EventContribution.event_id).all():
        base[str(eid)]["contribution_summary"] = {
            "contribution_total": float(total),
            "contribution_count": cnt,
        }

    # Ticket capacity per event (sum of ticket class quantity)
    for eid, cap in db.query(
        EventTicketClass.event_id,
        sa_func.coalesce(sa_func.sum(EventTicketClass.quantity), 0),
    ).filter(EventTicketClass.event_id.in_(eid_list)).group_by(EventTicketClass.event_id).all():
        base[str(eid)]["tickets_capacity"] = int(cap or 0)

    # Tickets sold per event (confirmed/approved orders only)
    for eid, sold in db.query(
        EventTicket.event_id,
        sa_func.coalesce(sa_func.sum(EventTicket.quantity), 0),
    ).filter(
        EventTicket.event_id.in_(eid_list),
        EventTicket.status.in_([TicketOrderStatusEnum.confirmed, TicketOrderStatusEnum.approved]),
    ).group_by(EventTicket.event_id).all():
        base[str(eid)]["tickets_sold"] = int(sold or 0)

    # Total invitations per event
    for eid, total_inv in db.query(
        EventInvitation.event_id,
        sa_func.count(EventInvitation.id),
    ).filter(EventInvitation.event_id.in_(eid_list)).group_by(EventInvitation.event_id).all():
        base[str(eid)]["invitations_total"] = int(total_inv or 0)

    # Sent invitations per event — every invitation record represents one sent
    # invite (sent_at is unreliable when delivery happens via in-app routes),
    # so we count all rows for the event.
    for eid, sent_inv in db.query(
        EventInvitation.event_id,
        sa_func.count(EventInvitation.id),
    ).filter(
        EventInvitation.event_id.in_(eid_list),
    ).group_by(EventInvitation.event_id).all():
        base[str(eid)]["invitations_sent"] = int(sent_inv or 0)

    return base


def batch_load_currency_codes(db: Session, currency_ids: Set[UUID]) -> Dict[str, Optional[str]]:
    """Batch lookup of currency code by id."""
    if not currency_ids:
        return {}
    out: Dict[str, Optional[str]] = {}
    for c in db.query(Currency).filter(Currency.id.in_(list(currency_ids))).all():
        out[str(c.id)] = c.code.strip() if c.code else None
    return out


def build_event_summaries(db: Session, events: List[Event]) -> List[Dict]:
    """
    Batched equivalent of _event_summary for a list of events.
    Total queries: ~10 regardless of event count (vs 8 per event before).
    """
    if not events:
        return []

    event_ids = [e.id for e in events]
    ctx = batch_load_event_context(db, event_ids)
    currency_ids = {e.currency_id for e in events if e.currency_id}
    currency_map = batch_load_currency_codes(db, currency_ids)

    result = []
    for event in events:
        eid = str(event.id)
        c = ctx[eid]
        et = c["event_type"]
        vc = c["vc"]
        s = c["settings"]
        ct_obj = c["contribution_target_obj"]
        images = c["images"]
        gc = c["guest_counts"]
        cs = c["contribution_summary"]

        cover = event.cover_image_url
        if not cover:
            for img in images:
                if img.get("is_featured"):
                    cover = img["image_url"]; break
            if not cover and images:
                cover = images[0]["image_url"]

        result.append({
            "id": eid, "user_id": str(event.organizer_id), "title": event.name,
            "description": event.description,
            "event_type_id": str(event.event_type_id) if event.event_type_id else None,
            "event_type": {"id": str(et.id), "name": et.name, "icon": et.icon} if et else None,
            "start_date": event.start_date.isoformat() if event.start_date else None,
            "start_time": event.start_time.strftime("%H:%M") if event.start_time else None,
            "end_date": event.end_date.isoformat() if event.end_date else None,
            "end_time": event.end_time.strftime("%H:%M") if event.end_time else None,
            "location": event.location,
            "venue": vc.venue_name if vc else None,
            "venue_address": vc.formatted_address if vc else None,
            "venue_coordinates": {"latitude": float(vc.latitude), "longitude": float(vc.longitude)} if vc and vc.latitude else None,
            "cover_image": cover, "images": images,
            "theme_color": event.theme_color, "is_public": event.is_public,
            "sells_tickets": event.sells_tickets or False,
            "ticket_approval_status": event.ticket_approval_status.value if event.ticket_approval_status and hasattr(event.ticket_approval_status, 'value') else "pending",
            "ticket_rejection_reason": event.ticket_rejection_reason,
            "ticket_removed_reason": event.ticket_removed_reason,
            "status": event.status.value if hasattr(event.status, "value") else event.status,
            "budget": float(event.budget) if event.budget else None,
            "currency": currency_map.get(str(event.currency_id)) if event.currency_id else None,
            "dress_code": event.dress_code, "special_instructions": event.special_instructions,
            "extra_details": getattr(event, "extra_details", None),
            "guest_of_honor": getattr(event, "guest_of_honor", None),
            "what_to_expect": event.what_to_expect,
            "what_to_expect_notes": event.what_to_expect_notes,
            "reminder_contact_phone": event.reminder_contact_phone,
            "contribution_payment_instructions": event.contribution_payment_instructions,
            "invitation_template_id": event.invitation_template_id,
            "invitation_accent_color": event.invitation_accent_color,
            "invitation_sample_names": event.invitation_sample_names,
            "invitation_content": event.invitation_content,
            "rsvp_deadline": s.rsvp_deadline.isoformat() if s and s.rsvp_deadline else None,
            "contribution_enabled": s.contributions_enabled if s else False,
            "contribution_target": c["contribution_target"],
            "contribution_description": ct_obj.description if ct_obj else None,
            "expected_guests": event.expected_guests,
            **gc, **cs,
            "tickets_sold": c["tickets_sold"],
            "tickets_capacity": c["tickets_capacity"],
            "invitations_sent": c["invitations_sent"],
            "invitations_total": c["invitations_total"],
            "committee_count": c["committee_count"], "service_booking_count": c["service_count"],
            "created_at": event.created_at.isoformat() if event.created_at else None,
            "updated_at": event.updated_at.isoformat() if event.updated_at else None,
        })

    return result


# ─────────────────────────────────────────────────────────
# Booking batch loader (eliminates N+1 in bookings list)
# ─────────────────────────────────────────────────────────

def _user_avatar_from_profile(profile) -> Optional[str]:
    return profile.profile_picture_url if profile else None


def build_booking_dicts(db: Session, bookings: List[ServiceBookingRequest]) -> List[Dict]:
    """
    Bulk-loads service / requester / vendor / event for a list of bookings.
    Replaces 4 per-booking queries (services, requesters, vendors, events) with 4 grouped queries.
    """
    if not bookings:
        return []

    service_ids = {b.user_service_id for b in bookings if b.user_service_id}
    requester_ids = {b.requester_user_id for b in bookings if b.requester_user_id}
    event_ids = {b.event_id for b in bookings if b.event_id}

    services = db.query(UserService).filter(UserService.id.in_(list(service_ids))).all() if service_ids else []
    service_map = {s.id: s for s in services}

    # Vendor IDs derive from services
    vendor_ids = {s.user_id for s in services if s.user_id}
    user_ids = list(requester_ids | vendor_ids)
    users = db.query(User).filter(User.id.in_(user_ids)).all() if user_ids else []
    user_map = {u.id: u for u in users}

    profiles = db.query(UserProfile).filter(UserProfile.user_id.in_(user_ids)).all() if user_ids else []
    profile_map = {p.user_id: p for p in profiles}

    # Service primary images (featured first)
    img_map: Dict = defaultdict(list)
    if service_ids:
        imgs = db.query(UserServiceImage).filter(UserServiceImage.user_service_id.in_(list(service_ids))).all()
        for im in imgs:
            img_map[im.user_service_id].append(im)
    primary_image: Dict = {}
    for sid, lst in img_map.items():
        featured = next((i for i in lst if getattr(i, "is_featured", False)), None)
        chosen = featured or (lst[0] if lst else None)
        primary_image[sid] = chosen.image_url if chosen else None

    # Service categories
    cat_ids = {s.category_id for s in services if getattr(s, "category_id", None)}
    cat_map = {}
    if cat_ids:
        cats = db.query(ServiceCategory).filter(ServiceCategory.id.in_(list(cat_ids))).all()
        cat_map = {c.id: c for c in cats}

    # Events
    events = db.query(Event).filter(Event.id.in_(list(event_ids))).all() if event_ids else []
    event_map = {e.id: e for e in events}

    def _user_dict(u, p):
        if not u:
            return None
        return {
            "id": str(u.id),
            "name": f"{u.first_name} {u.last_name}",
            "avatar": _user_avatar_from_profile(p),
            "phone": u.phone,
            "email": u.email,
        }

    out: List[Dict] = []
    for b in bookings:
        service = service_map.get(b.user_service_id) if b.user_service_id else None
        requester = user_map.get(b.requester_user_id) if b.requester_user_id else None
        vendor = user_map.get(service.user_id) if service and service.user_id else None
        event = event_map.get(b.event_id) if b.event_id else None

        service_dict = None
        if service:
            cat = cat_map.get(getattr(service, "category_id", None))
            service_dict = {
                "id": str(service.id),
                "title": service.title,
                "primary_image": primary_image.get(service.id) or getattr(service, "cover_image_url", None),
                "category": cat.name if cat else None,
            }

        event_dict = None
        if event:
            event_date_str = event.start_date.isoformat() if event.start_date and hasattr(event.start_date, "isoformat") else (str(event.start_date) if event.start_date else None)
            event_dict = {
                "id": str(event.id),
                "name": event.name,
                "title": event.name,
                "date": event_date_str,
                "start_date": event_date_str,
                "start_time": event.start_time.strftime("%H:%M") if event.start_time else None,
                "end_time": event.end_time.strftime("%H:%M") if getattr(event, "end_time", None) else None,
                "location": event.location,
                "venue": getattr(event, "venue", None),
                "guest_count": getattr(event, "expected_guests", None),
                "image": getattr(event, "cover_image_url", None),
                "cover_image": getattr(event, "cover_image_url", None),
            }

        out.append({
            "id": str(b.id),
            "service": service_dict,
            "client": _user_dict(requester, profile_map.get(b.requester_user_id) if requester else None),
            "provider": _user_dict(vendor, profile_map.get(vendor.id) if vendor else None),
            "event": event_dict,
            "event_name": event.name if event else None,
            "event_date": event_dict["date"] if event_dict else None,
            "event_type": None,
            "location": event.location if event else None,
            "venue": getattr(event, "venue", None) if event else None,
            "guest_count": getattr(event, "expected_guests", None) if event else None,
            "status": b.status if isinstance(b.status, str) else (b.status.value if hasattr(b.status, "value") else b.status),
            "message": b.message,
            "proposed_price": float(b.proposed_price) if b.proposed_price else None,
            "quoted_price": float(b.quoted_price) if b.quoted_price else None,
            "deposit_required": float(b.deposit_required) if b.deposit_required else None,
            "deposit_paid": b.deposit_paid,
            "vendor_notes": b.vendor_notes,
            "created_at": b.created_at.isoformat() if b.created_at else None,
            "updated_at": b.updated_at.isoformat() if b.updated_at else None,
        })
    return out


# ─────────────────────────────────────────────────────────
# Messages / Conversations batch loader
# ─────────────────────────────────────────────────────────

def build_conversation_dicts(db: Session, conversations: list, current_user_id) -> List[Dict]:
    """
    Batch-load other-participant users/profiles, last messages, unread counts,
    and service info for a list of conversations.
    Replaces ~5 per-conversation queries with ~6 grouped queries.
    """
    from models import Conversation, Message, UserService, UserServiceImage
    from sqlalchemy import case

    if not conversations:
        return []

    cur = str(current_user_id)
    conv_ids = [c.id for c in conversations]

    # Other participant per conversation
    other_ids = set()
    for c in conversations:
        oid = c.user_two_id if str(c.user_one_id) == cur else c.user_one_id
        if oid:
            other_ids.add(oid)

    users = db.query(User).filter(User.id.in_(list(other_ids))).all() if other_ids else []
    user_map = {u.id: u for u in users}
    profiles = db.query(UserProfile).filter(UserProfile.user_id.in_(list(other_ids))).all() if other_ids else []
    profile_map = {p.user_id: p for p in profiles}

    # Last + previous (second-most-recent) message per conversation.
    # We fetch the two newest messages per conversation in a single windowed
    # query so the conversations list can render two preview lines per card
    # (matches the design). Falls back gracefully when only one message exists.
    last_msg_map: Dict = {}
    prev_msg_map: Dict = {}
    if conv_ids:
        from sqlalchemy import desc
        # Use ROW_NUMBER() window so we can pull the top 2 messages per conv in
        # one round-trip rather than N+1 per-conv queries.
        rn = sa_func.row_number().over(
            partition_by=Message.conversation_id,
            order_by=desc(Message.created_at),
        ).label("rn")
        sub = db.query(Message, rn).filter(
            Message.conversation_id.in_(conv_ids)
        ).subquery()
        rows = db.query(Message).join(
            sub, Message.id == sub.c.id
        ).filter(sub.c.rn <= 2).all()
        # Group by conversation, ordered newest → oldest
        grouped: Dict = defaultdict(list)
        for m in rows:
            grouped[m.conversation_id].append(m)
        for cid, msgs in grouped.items():
            msgs.sort(key=lambda x: x.created_at, reverse=True)
            if msgs:
                last_msg_map[cid] = msgs[0]
            if len(msgs) > 1:
                prev_msg_map[cid] = msgs[1]

    # Unread counts (other sender, unread) grouped per conversation
    unread_map: Dict = {}
    if conv_ids:
        rows = db.query(
            Message.conversation_id,
            sa_func.count(Message.id)
        ).filter(
            Message.conversation_id.in_(conv_ids),
            Message.sender_id != current_user_id,
            Message.is_read == False,
        ).group_by(Message.conversation_id).all()
        unread_map = {cid: int(cnt) for cid, cnt in rows}

    # Service info bulk
    service_ids = {c.service_id for c in conversations if c.service_id}
    service_map: Dict = {}
    service_image_map: Dict = {}
    if service_ids:
        services = db.query(UserService).filter(UserService.id.in_(list(service_ids))).all()
        service_map = {s.id: s for s in services}
        imgs = db.query(UserServiceImage).filter(UserServiceImage.user_service_id.in_(list(service_ids))).all()
        for im in imgs:
            cur_img = service_image_map.get(im.user_service_id)
            if cur_img is None or (getattr(im, "is_featured", False) and not getattr(cur_img, "is_featured", False)):
                service_image_map[im.user_service_id] = im

    out: List[Dict] = []
    for conv in conversations:
        other_id = conv.user_two_id if str(conv.user_one_id) == cur else conv.user_one_id
        other = user_map.get(other_id) if other_id else None
        profile = profile_map.get(other_id) if other_id else None
        last_msg = last_msg_map.get(conv.id)
        prev_msg = prev_msg_map.get(conv.id)
        unread = unread_map.get(conv.id, 0)

        service_info = None
        if conv.service_id:
            svc = service_map.get(conv.service_id)
            if svc:
                im = service_image_map.get(conv.service_id)
                service_info = {
                    "id": str(svc.id),
                    "title": svc.title,
                    "image": im.image_url if im else None,
                    "provider_id": str(svc.user_id),
                    "is_verified": bool(getattr(svc, "is_verified", False)),
                }

        participant_name = f"{other.first_name} {other.last_name}" if other else None
        participant_avatar = profile.profile_picture_url if profile else None

        is_service_owner = service_info and str(service_info["provider_id"]) == cur
        if service_info and not is_service_owner:
            display_name = service_info["title"]
            display_avatar = service_info["image"]
        else:
            display_name = participant_name
            display_avatar = participant_avatar

        out.append({
            "id": str(conv.id),
            "type": conv.type.value if conv.type else "user_to_user",
            "participant": {
                "id": str(other.id) if other else None,
                "name": display_name,
                "avatar": display_avatar,
                "is_verified": bool(getattr(other, "is_identity_verified", False)) if other else False,
            },
            "service": service_info,
            "last_message": {
                "content": last_msg.message_text if last_msg else None,
                "sent_at": last_msg.created_at.isoformat() if last_msg else None,
                "is_mine": str(last_msg.sender_id) == cur if last_msg else False,
            } if last_msg else None,
            # Second-most-recent message — surfaced so the conversations list
            # can render two preview lines (matches the WhatsApp-style design).
            "previous_message": {
                "content": prev_msg.message_text if prev_msg else None,
                "sent_at": prev_msg.created_at.isoformat() if prev_msg else None,
                "is_mine": str(prev_msg.sender_id) == cur if prev_msg else False,
            } if prev_msg else None,
            "unread_count": unread,
            "is_active": conv.is_active,
            # Surface encryption flag so the chat UI can show/hide the banner.
            # Defaults to False on legacy rows for backward compatibility.
            "is_encrypted": bool(getattr(conv, "is_encrypted", False)),
            "updated_at": conv.updated_at.isoformat() if conv.updated_at else None,
        })
    return out


# ─────────────────────────────────────────────────────────
# Communities batch loaders
# ─────────────────────────────────────────────────────────

def build_community_dicts(db: Session, communities: list, current_user_id) -> List[Dict]:
    """Batch-load membership flags for a list of communities."""
    from models import Community, CommunityMember
    if not communities:
        return []

    cur = str(current_user_id) if current_user_id else None
    community_ids = [c.id for c in communities]

    member_ids: Set = set()
    if cur:
        rows = db.query(CommunityMember.community_id).filter(
            CommunityMember.community_id.in_(community_ids),
            CommunityMember.user_id == current_user_id,
        ).all()
        member_ids = {r[0] for r in rows}

    out: List[Dict] = []
    for c in communities:
        is_creator = bool(cur and c.created_by and str(c.created_by) == cur)
        is_member = (c.id in member_ids) or is_creator
        out.append({
            "id": str(c.id),
            "name": c.name,
            "description": c.description,
            "tagline": getattr(c, "tagline", None),
            "category": getattr(c, "category", None),
            "image": c.cover_image_url,
            "cover_image": c.cover_image_url,
            "is_public": c.is_public,
            "is_verified": bool(getattr(c, "is_verified", False)),
            "member_count": c.member_count or 0,
            "online_count": 0,
            "is_creator": is_creator or is_member,
            "is_member": is_member,
            "created_at": c.created_at.isoformat() if c.created_at else None,
        })
    return out


def build_community_member_dicts(db: Session, memberships: list) -> List[Dict]:
    """Batch-load user/profile for a paginated list of memberships."""
    if not memberships:
        return []
    user_ids = list({m.user_id for m in memberships if m.user_id})
    users = db.query(User).filter(User.id.in_(user_ids)).all() if user_ids else []
    user_map = {u.id: u for u in users}
    profiles = db.query(UserProfile).filter(UserProfile.user_id.in_(user_ids)).all() if user_ids else []
    profile_map = {p.user_id: p for p in profiles}

    out: List[Dict] = []
    for m in memberships:
        u = user_map.get(m.user_id)
        if not u:
            continue
        p = profile_map.get(m.user_id)
        out.append({
            "id": str(u.id),
            "first_name": u.first_name,
            "last_name": u.last_name,
            "name": f"{u.first_name or ''} {u.last_name or ''}".strip(),
            "username": getattr(u, "username", None),
            "avatar": p.profile_picture_url if p else None,
            "is_verified": bool(getattr(u, "is_identity_verified", False)),
            "role": m.role,
            "joined_at": m.joined_at.isoformat() if m.joined_at else None,
        })
    return out


def build_community_post_dicts(db: Session, posts: list, current_user_id) -> List[Dict]:
    """Batch-load authors, images, glow/save/comment/share counts for posts."""
    from models import CommunityPost, CommunityPostImage, CommunityPostGlow, CommunityPostComment, CommunityPostSave, CommunityPostShare
    if not posts:
        return []

    post_ids = [p.id for p in posts]
    author_ids = list({p.author_id for p in posts if p.author_id})

    users = db.query(User).filter(User.id.in_(author_ids)).all() if author_ids else []
    user_map = {u.id: u for u in users}
    profiles = db.query(UserProfile).filter(UserProfile.user_id.in_(author_ids)).all() if author_ids else []
    profile_map = {p.user_id: p for p in profiles}

    img_map: Dict = defaultdict(list)
    if post_ids:
        for im in db.query(CommunityPostImage).filter(CommunityPostImage.post_id.in_(post_ids)).all():
            img_map[im.post_id].append(im)

    def _count_map(model):
        if not post_ids:
            return {}
        rows = db.query(model.post_id, sa_func.count(model.id)).filter(
            model.post_id.in_(post_ids)
        ).group_by(model.post_id).all()
        return {pid: int(cnt) for pid, cnt in rows}

    glow_count_map = _count_map(CommunityPostGlow)
    comment_count_map = _count_map(CommunityPostComment)
    share_count_map = _count_map(CommunityPostShare)

    def _user_set(model):
        if not (post_ids and current_user_id):
            return set()
        rows = db.query(model.post_id).filter(
            model.post_id.in_(post_ids),
            model.user_id == current_user_id,
        ).all()
        return {r[0] for r in rows}

    has_glowed_set = _user_set(CommunityPostGlow)
    has_saved_set = _user_set(CommunityPostSave)

    out: List[Dict] = []
    for cp in posts:
        u = user_map.get(cp.author_id)
        p = profile_map.get(cp.author_id) if cp.author_id else None
        out.append({
            "id": str(cp.id),
            "author": {
                "id": str(u.id) if u else None,
                "first_name": u.first_name if u else None,
                "last_name": u.last_name if u else None,
                "name": f"{u.first_name} {u.last_name}".strip() if u else None,
                "avatar": p.profile_picture_url if p else None,
                "is_verified": bool(getattr(u, "is_identity_verified", False)) if u else False,
            },
            "content": cp.content,
            "images": [
                {"url": im.image_url, "media_type": getattr(im, "media_type", None) or "image"}
                for im in img_map.get(cp.id, [])
            ],
            "glow_count": glow_count_map.get(cp.id, 0),
            "comment_count": comment_count_map.get(cp.id, 0),
            "share_count": share_count_map.get(cp.id, 0),
            "has_glowed": cp.id in has_glowed_set,
            "has_saved": cp.id in has_saved_set,
            "edited_at": cp.edited_at.isoformat() if getattr(cp, "edited_at", None) else None,
            "created_at": cp.created_at.isoformat() if cp.created_at else None,
        })
    return out


# ─────────────────────────────────────────────────────────
# Circles batch loaders
# ─────────────────────────────────────────────────────────

def build_circle_member_dicts(db: Session, entries: list) -> List[Dict]:
    """Batch-load member user/profile for accepted circle entries."""
    if not entries:
        return []
    user_ids = list({e.circle_member_id for e in entries if e.circle_member_id})
    users = db.query(User).filter(User.id.in_(user_ids)).all() if user_ids else []
    user_map = {u.id: u for u in users}
    profiles = db.query(UserProfile).filter(UserProfile.user_id.in_(user_ids)).all() if user_ids else []
    profile_map = {p.user_id: p for p in profiles}

    out: List[Dict] = []
    for e in entries:
        member = user_map.get(e.circle_member_id)
        if not member:
            continue
        profile = profile_map.get(e.circle_member_id)
        out.append({
            "id": str(member.id),
            "first_name": member.first_name,
            "last_name": member.last_name,
            "username": member.username,
            "avatar": profile.profile_picture_url if profile else None,
            "mutual_count": e.mutual_friends_count or 0,
            "status": e.status or "accepted",
            "added_at": e.created_at.isoformat() if e.created_at else None,
        })
    return out


def build_circle_request_dicts(db: Session, entries: list) -> List[Dict]:
    """Batch-load requester user/profile for incoming circle requests."""
    if not entries:
        return []
    user_ids = list({e.user_id for e in entries if e.user_id})
    users = db.query(User).filter(User.id.in_(user_ids)).all() if user_ids else []
    user_map = {u.id: u for u in users}
    profiles = db.query(UserProfile).filter(UserProfile.user_id.in_(user_ids)).all() if user_ids else []
    profile_map = {p.user_id: p for p in profiles}

    out: List[Dict] = []
    for e in entries:
        requester = user_map.get(e.user_id)
        if not requester:
            continue
        profile = profile_map.get(e.user_id)
        out.append({
            "request_id": str(e.id),
            "id": str(requester.id),
            "first_name": requester.first_name,
            "last_name": requester.last_name,
            "username": requester.username,
            "avatar": profile.profile_picture_url if profile else None,
            "mutual_count": e.mutual_friends_count or 0,
            "requested_at": e.created_at.isoformat() if e.created_at else None,
        })
    return out


# ─────────────────────────────────────────────────────────
# Meetings batch loaders
# ─────────────────────────────────────────────────────────

def build_meeting_dicts(db: Session, meetings: List[EventMeeting]) -> List[Dict]:
    """Bulk-build meeting dicts. Eliminates N+1 over participants/creator/agenda/minutes/requests."""
    if not meetings:
        return []

    meeting_ids = [m.id for m in meetings]

    # Auto-end expired meetings (single pass — no per-meeting commit)
    from datetime import datetime, timedelta
    now = datetime.utcnow()
    expired_ids = []
    for m in meetings:
        if m.status in (MeetingStatusEnum.in_progress, MeetingStatusEnum.scheduled):
            try:
                duration = int(m.duration_minutes or 60)
                end_time = m.scheduled_at + timedelta(minutes=duration)
                if now > end_time:
                    expired_ids.append((m, end_time))
            except Exception:
                pass

    if expired_ids:
        # Active counts in one grouped query
        active_counts = dict(
            db.query(EventMeetingParticipant.meeting_id, sa_func.count(EventMeetingParticipant.id))
            .filter(
                EventMeetingParticipant.meeting_id.in_([m.id for m, _ in expired_ids]),
                EventMeetingParticipant.joined_at.isnot(None),
                EventMeetingParticipant.left_at.is_(None),
            ).group_by(EventMeetingParticipant.meeting_id).all()
        )
        changed = False
        for m, end_time in expired_ids:
            if active_counts.get(m.id, 0) == 0:
                m.status = MeetingStatusEnum.ended
                m.ended_at = end_time
                changed = True
        if changed:
            try:
                db.commit()
            except Exception:
                db.rollback()

    # Bulk-load participants
    participants = (
        db.query(EventMeetingParticipant)
        .filter(EventMeetingParticipant.meeting_id.in_(meeting_ids)).all()
    )
    parts_by_mtg: Dict[Any, List[EventMeetingParticipant]] = defaultdict(list)
    for p in participants:
        parts_by_mtg[p.meeting_id].append(p)

    # Collect all user ids (creators + participants)
    user_ids: Set = set()
    for m in meetings:
        if m.created_by:
            user_ids.add(m.created_by)
    for p in participants:
        if p.user_id:
            user_ids.add(p.user_id)

    users_map = {u.id: u for u in db.query(User).filter(User.id.in_(list(user_ids))).all()} if user_ids else {}
    profiles_map = {
        p.user_id: p for p in db.query(UserProfile).filter(UserProfile.user_id.in_(list(user_ids))).all()
    } if user_ids else {}

    # Bulk-load agenda/minutes/pending request counts
    agenda_counts = dict(
        db.query(MeetingAgendaItem.meeting_id, sa_func.count(MeetingAgendaItem.id))
        .filter(MeetingAgendaItem.meeting_id.in_(meeting_ids))
        .group_by(MeetingAgendaItem.meeting_id).all()
    )
    minutes_ids = {
        r[0] for r in db.query(MeetingMinutes.meeting_id)
        .filter(MeetingMinutes.meeting_id.in_(meeting_ids)).all()
    }
    pending_counts = dict(
        db.query(EventMeetingJoinRequest.meeting_id, sa_func.count(EventMeetingJoinRequest.id))
        .filter(
            EventMeetingJoinRequest.meeting_id.in_(meeting_ids),
            EventMeetingJoinRequest.status == MeetingJoinRequestStatusEnum.waiting,
        ).group_by(EventMeetingJoinRequest.meeting_id).all()
    )

    out: List[Dict] = []
    for m in meetings:
        parts_list = []
        for p in parts_by_mtg.get(m.id, []):
            user = users_map.get(p.user_id)
            profile = profiles_map.get(p.user_id)
            avatar = profile.profile_picture_url if profile else None
            parts_list.append({
                "id": str(p.id),
                "user_id": str(p.user_id),
                "name": f"{user.first_name or ''} {user.last_name or ''}".strip() if user else "Unknown",
                "avatar_url": avatar,
                "is_notified": p.is_notified,
                "joined_at": p.joined_at.isoformat() if p.joined_at else None,
                "role": p.role.value if p.role else "participant",
            })

        creator = users_map.get(m.created_by)
        out.append({
            "id": str(m.id),
            "event_id": str(m.event_id),
            "title": m.title,
            "description": m.description,
            "scheduled_at": m.scheduled_at.isoformat() if m.scheduled_at else None,
            "timezone": getattr(m, "timezone", None) or "UTC",
            "duration_minutes": m.duration_minutes,
            "room_id": m.room_id,
            "meeting_url": f"https://nuru.tz/meet/{m.room_id}",
            "status": m.status.value if m.status else "scheduled",
            "created_by": {
                "id": str(m.created_by),
                "name": f"{creator.first_name or ''} {creator.last_name or ''}".strip() if creator else "Unknown",
            },
            "participants": parts_list,
            "participant_count": len(parts_list),
            "pending_requests": pending_counts.get(m.id, 0),
            "has_agenda": agenda_counts.get(m.id, 0) > 0,
            "has_minutes": m.id in minutes_ids,
            "ended_at": m.ended_at.isoformat() if m.ended_at else None,
            "created_at": m.created_at.isoformat() if m.created_at else None,
        })
    return out


# ─────────────────────────────────────────────────────────
# Expenses batch loader
# ─────────────────────────────────────────────────────────

def build_expense_dicts(db: Session, expenses: List[EventExpense]) -> List[Dict]:
    """Bulk-build expense dicts. Eliminates N+1 over recorder + vendor + category."""
    if not expenses:
        return []

    recorder_ids = {e.recorded_by for e in expenses if e.recorded_by}
    vendor_ids = {e.vendor_id for e in expenses if e.vendor_id}

    recorders = {u.id: u for u in db.query(User).filter(User.id.in_(list(recorder_ids))).all()} if recorder_ids else {}
    vendors_map: Dict = {}
    if vendor_ids:
        vendors = (
            db.query(UserService)
            .filter(UserService.id.in_(list(vendor_ids))).all()
        )
        cat_ids = {v.category_id for v in vendors if getattr(v, "category_id", None)}
        cat_map = {c.id: c for c in db.query(ServiceCategory).filter(ServiceCategory.id.in_(list(cat_ids))).all()} if cat_ids else {}
        for v in vendors:
            cat = cat_map.get(getattr(v, "category_id", None))
            vendors_map[v.id] = {
                "id": str(v.id),
                "title": v.title,
                "category_name": cat.name if cat else None,
                "location": v.location,
                "is_verified": v.is_verified,
            }

    out: List[Dict] = []
    for e in expenses:
        rec = recorders.get(e.recorded_by) if e.recorded_by else None
        out.append({
            "id": str(e.id),
            "event_id": str(e.event_id),
            "category": e.category,
            "description": e.description,
            "amount": float(e.amount) if e.amount else 0,
            "payment_method": e.payment_method,
            "payment_reference": e.payment_reference,
            "vendor_name": e.vendor_name,
            "vendor_id": str(e.vendor_id) if e.vendor_id else None,
            "vendor": vendors_map.get(e.vendor_id) if e.vendor_id else None,
            "receipt_url": e.receipt_url,
            "expense_date": e.expense_date.isoformat() if e.expense_date else None,
            "notes": e.notes,
            "recorded_by_id": str(e.recorded_by) if e.recorded_by else None,
            "recorded_by_name": f"{rec.first_name} {rec.last_name}" if rec else None,
            "created_at": e.created_at.isoformat() if e.created_at else None,
            "updated_at": e.updated_at.isoformat() if e.updated_at else None,
        })
    return out


# ─────────────────────────────────────────────────────────
# Committee members + Event services batch loaders
# ─────────────────────────────────────────────────────────

def build_committee_member_dicts(
    db: Session,
    members: List[EventCommitteeMember],
    permission_map: Dict[str, str],
) -> List[Dict]:
    """Bulk-build committee member dicts. Eliminates N+1 over user/profile/role/perms/assigner."""
    if not members:
        return []

    user_ids = {m.user_id for m in members if m.user_id}
    assigner_ids = {m.assigned_by for m in members if m.assigned_by}
    role_ids = {m.role_id for m in members if m.role_id}
    member_ids = [m.id for m in members]

    all_user_ids = user_ids | assigner_ids
    users = {u.id: u for u in db.query(User).filter(User.id.in_(list(all_user_ids))).all()} if all_user_ids else {}
    profiles = {p.user_id: p for p in db.query(UserProfile).filter(UserProfile.user_id.in_(list(user_ids))).all()} if user_ids else {}
    roles = {r.id: r for r in db.query(CommitteeRole).filter(CommitteeRole.id.in_(list(role_ids))).all()} if role_ids else {}
    perms = {
        p.committee_member_id: p for p in
        db.query(CommitteePermission).filter(CommitteePermission.committee_member_id.in_(member_ids)).all()
    }

    out: List[Dict] = []
    for cm in members:
        member_user = users.get(cm.user_id) if cm.user_id else None
        profile = profiles.get(cm.user_id) if cm.user_id else None
        role = roles.get(cm.role_id) if cm.role_id else None
        perm = perms.get(cm.id)
        assigned_user = users.get(cm.assigned_by) if cm.assigned_by else None

        permissions_list = []
        if perm:
            for api_name, db_field in permission_map.items():
                if getattr(perm, db_field, False):
                    permissions_list.append(api_name)

        out.append({
            "id": str(cm.id),
            "event_id": str(cm.event_id),
            "user_id": str(cm.user_id) if cm.user_id else None,
            "name": f"{member_user.first_name} {member_user.last_name}" if member_user else "Invited Member",
            "email": member_user.email if member_user else (cm.invited_email if hasattr(cm, "invited_email") else None),
            "phone": member_user.phone if member_user else None,
            "avatar": profile.profile_picture_url if profile else None,
            "role": role.role_name if role else None,
            "role_description": role.description if role else None,
            "permissions": permissions_list,
            "status": "active" if cm.user_id else "invited",
            "assigned_by": {"id": str(assigned_user.id), "name": f"{assigned_user.first_name} {assigned_user.last_name}"} if assigned_user else None,
            "assigned_at": cm.assigned_at.isoformat() if cm.assigned_at else None,
            "created_at": cm.created_at.isoformat() if cm.created_at else None,
        })
    return out


def build_event_service_dicts(
    db: Session,
    services: List[EventService],
    currency_code: Optional[str],
) -> List[Dict]:
    """Bulk-build event service dicts. Eliminates N+1 over service_type/provider/images."""
    if not services:
        return []

    svc_type_ids = {s.service_id for s in services if s.service_id}
    provider_svc_ids = {s.provider_user_service_id for s in services if s.provider_user_service_id}
    provider_user_ids = {s.provider_user_id for s in services if s.provider_user_id}
    manual_cat_ids = {getattr(s, "manual_vendor_category_id", None) for s in services if getattr(s, "manual_vendor_category_id", None)}

    svc_types = {t.id: t for t in db.query(ServiceType).filter(ServiceType.id.in_(list(svc_type_ids))).all()} if svc_type_ids else {}
    cat_ids = {t.category_id for t in svc_types.values() if getattr(t, "category_id", None)} | manual_cat_ids
    cat_map = {c.id: c for c in db.query(ServiceCategory).filter(ServiceCategory.id.in_(list(cat_ids))).all()} if cat_ids else {}

    provider_svcs = {s.id: s for s in db.query(UserService).filter(UserService.id.in_(list(provider_svc_ids))).all()} if provider_svc_ids else {}
    provider_users = {u.id: u for u in db.query(User).filter(User.id.in_(list(provider_user_ids))).all()} if provider_user_ids else {}

    images_map: Dict[Any, str] = {}
    if provider_svc_ids:
        imgs = (
            db.query(UserServiceImage)
            .filter(UserServiceImage.user_service_id.in_(list(provider_svc_ids)))
            .order_by(UserServiceImage.is_featured.desc()).all()
        )
        for img in imgs:
            if img.user_service_id not in images_map:
                images_map[img.user_service_id] = img.image_url

    out: List[Dict] = []
    for es in services:
        svc_type = svc_types.get(es.service_id)
        provider_svc = provider_svcs.get(es.provider_user_service_id) if es.provider_user_service_id else None
        provider_user = provider_users.get(es.provider_user_id) if es.provider_user_id else None
        cat = cat_map.get(getattr(svc_type, "category_id", None)) if svc_type else None
        manual_cat = cat_map.get(getattr(es, "manual_vendor_category_id", None)) if getattr(es, "manual_vendor_category_id", None) else None
        is_manual = bool(getattr(es, "is_manual", False))

        title = (
            es.manual_vendor_name if is_manual else
            (provider_svc.title if provider_svc else (svc_type.name if svc_type else None))
        )
        category_name = (
            (manual_cat.name if manual_cat else None) if is_manual else
            (cat.name if cat else None)
        )
        provider_name = (
            es.manual_vendor_name if is_manual else
            (f"{provider_user.first_name} {provider_user.last_name}" if provider_user else None)
        )

        out.append({
            "id": str(es.id),
            "event_id": str(es.event_id),
            "service_id": str(es.service_id) if es.service_id else None,
            "provider_user_id": str(es.provider_user_id) if es.provider_user_id else None,
            "provider_user_service_id": str(es.provider_user_service_id) if es.provider_user_service_id else None,
            "is_manual": is_manual,
            "manual_vendor_name": getattr(es, "manual_vendor_name", None),
            "manual_vendor_phone": getattr(es, "manual_vendor_phone", None),
            "manual_vendor_email": getattr(es, "manual_vendor_email", None),
            "manual_vendor_category_id": str(es.manual_vendor_category_id) if getattr(es, "manual_vendor_category_id", None) else None,
            "manual_vendor_notes": getattr(es, "manual_vendor_notes", None),
            "service": {
                "title": title,
                "category": category_name,
                "provider_name": provider_name,
                "image": images_map.get(es.provider_user_service_id) if es.provider_user_service_id else None,
                "verification_status": (provider_svc.verification_status.value if provider_svc and hasattr(provider_svc.verification_status, "value") else (str(provider_svc.verification_status) if provider_svc and provider_svc.verification_status else "unverified")),
                "verified": provider_svc.is_verified if provider_svc else False,
            },
            "quoted_price": float(es.agreed_price) if es.agreed_price else None,
            "currency": currency_code,
            "status": es.service_status.value if hasattr(es.service_status, "value") else es.service_status,
            "notes": es.notes,
            "created_at": es.created_at.isoformat() if es.created_at else None,
        })
    return out


# ─────────────────────────────────────────────────────────
# EventContribution batch loaders (pending + recorded lists)
# ─────────────────────────────────────────────────────────

def build_pending_contribution_dicts(
    db: Session,
    contributions: list,
    *,
    include_status: bool = False,
    include_audit: bool = True,
) -> List[Dict]:
    """
    Bulk-build dicts for EventContribution rows (pending or recorded lists).
    Replaces N+1 queries: 1 EventContributor + 1 UserContributor + 1 User per row.
    Now: 3 batched queries total regardless of list size.

    When ``include_audit`` is True (default — for organiser/auditor views), the
    extra offline-claim fields (channel, provider, payer account, receipt URL)
    are included. Set to False for committee members without audit permission
    to avoid leaking the full payer trail.
    """
    if not contributions:
        return []

    ec_ids = {c.event_contributor_id for c in contributions if c.event_contributor_id}
    recorder_ids = {c.recorded_by for c in contributions if c.recorded_by}
    reviewer_ids = {c.claim_reviewed_by for c in contributions if getattr(c, "claim_reviewed_by", None)}

    # Bulk-load EventContributors and their UserContributors
    ec_map: Dict[Any, EventContributor] = {}
    contributor_ids: Set = set()
    if ec_ids:
        for ec in db.query(EventContributor).filter(EventContributor.id.in_(list(ec_ids))).all():
            ec_map[ec.id] = ec
            if ec.contributor_id:
                contributor_ids.add(ec.contributor_id)

    contributor_map: Dict[Any, UserContributor] = {}
    if contributor_ids:
        for uc in db.query(UserContributor).filter(UserContributor.id.in_(list(contributor_ids))).all():
            contributor_map[uc.id] = uc

    # Bulk-load recorder + reviewer users (single query)
    user_map: Dict[Any, User] = {}
    all_user_ids = recorder_ids | reviewer_ids
    if all_user_ids:
        for u in db.query(User).filter(User.id.in_(list(all_user_ids))).all():
            user_map[u.id] = u

    out: List[Dict] = []
    for c in contributions:
        ec = ec_map.get(c.event_contributor_id)
        contributor = contributor_map.get(ec.contributor_id) if ec and ec.contributor_id else None
        recorder = user_map.get(c.recorded_by) if c.recorded_by else None
        reviewer = user_map.get(c.claim_reviewed_by) if getattr(c, "claim_reviewed_by", None) else None

        # Prefer per-event display name override when set so the same global
        # contributor can show as different names on different events.
        event_display = (getattr(ec, "display_name", None) or "").strip() if ec else None
        resolved_name = event_display or (contributor.name if contributor else c.contributor_name)
        item = {
            "id": str(c.id),
            "contributor_name": resolved_name,
            "contributor_phone": contributor.phone if contributor else None,
            "amount": float(c.amount) if c.amount is not None else 0.0,
            "payment_method": c.payment_method.value if c.payment_method else None,
            "transaction_ref": c.transaction_ref,
            "created_at": c.created_at.isoformat() if c.created_at else None,
        }
        if include_status:
            item["confirmation_status"] = c.confirmation_status.value if c.confirmation_status else "confirmed"
            item["confirmed_at"] = c.confirmed_at.isoformat() if c.confirmed_at else None
        else:
            item["recorded_by"] = f"{recorder.first_name} {recorder.last_name}" if recorder else None

        # Offline-claim audit trail. Gated by include_audit so committee
        # members without audit permission don't see payer account / receipt.
        if include_audit:
            item["payment_channel"] = getattr(c, "payment_channel", None)
            item["provider_name"] = getattr(c, "provider_name", None)
            item["provider_id"] = str(c.provider_id) if getattr(c, "provider_id", None) else None
            item["payer_account"] = getattr(c, "payer_account", None)
            item["receipt_image_url"] = getattr(c, "receipt_image_url", None)
            item["claim_submitted_at"] = c.claim_submitted_at.isoformat() if getattr(c, "claim_submitted_at", None) else None
            item["claim_reviewed_at"] = c.claim_reviewed_at.isoformat() if getattr(c, "claim_reviewed_at", None) else None
            item["claim_reviewed_by"] = f"{reviewer.first_name} {reviewer.last_name}" if reviewer else None
            item["claim_rejection_reason"] = getattr(c, "claim_rejection_reason", None)
        out.append(item)

    return out


# ─────────────────────────────────────────────────────────
# EventAttendee (guest list) batch loader
# ─────────────────────────────────────────────────────────

def build_event_attendee_dicts(db: Session, attendees: list) -> List[Dict]:
    """
    Bulk-build attendee dicts for the guest list endpoint.
    Replaces 4 queries per attendee with 5 batched queries total.
    """
    if not attendees:
        return []

    att_ids = [a.id for a in attendees]
    user_ids = {a.attendee_id for a in attendees if a.attendee_id}
    contributor_ids = {a.contributor_id for a in attendees if a.contributor_id}
    invitation_ids = {a.invitation_id for a in attendees if a.invitation_id}

    # Bulk users + profiles
    user_map: Dict[Any, User] = {}
    profile_map: Dict[Any, UserProfile] = {}
    if user_ids:
        for u in db.query(User).filter(User.id.in_(list(user_ids))).all():
            user_map[u.id] = u
        for p in db.query(UserProfile).filter(UserProfile.user_id.in_(list(user_ids))).all():
            profile_map[p.user_id] = p

    # Bulk contributors
    contributor_map: Dict[Any, UserContributor] = {}
    if contributor_ids:
        for uc in db.query(UserContributor).filter(UserContributor.id.in_(list(contributor_ids))).all():
            contributor_map[uc.id] = uc

    # Bulk invitations
    inv_map: Dict[Any, EventInvitation] = {}
    if invitation_ids:
        for inv in db.query(EventInvitation).filter(EventInvitation.id.in_(list(invitation_ids))).all():
            inv_map[inv.id] = inv

    # Bulk plus-ones — one query for all attendees
    plus_ones_map: Dict[Any, list] = defaultdict(list)
    if att_ids:
        for po in db.query(EventGuestPlusOne).filter(EventGuestPlusOne.attendee_id.in_(att_ids)).all():
            plus_ones_map[po.attendee_id].append(po)

    out: List[Dict] = []
    for att in attendees:
        guest_type = att.guest_type.value if hasattr(att.guest_type, "value") else (att.guest_type or "user")

        name = email = phone = avatar = None
        if guest_type == "contributor":
            contributor = contributor_map.get(att.contributor_id) if att.contributor_id else None
            if contributor:
                name = contributor.name
                email = contributor.email
                phone = contributor.phone
            else:
                name = att.guest_name
                email = att.guest_email
                phone = att.guest_phone
        else:
            u = user_map.get(att.attendee_id) if att.attendee_id else None
            if u:
                name = f"{u.first_name} {u.last_name}"
                email = u.email
                phone = u.phone
                p = profile_map.get(u.id)
                avatar = p.profile_picture_url if p else None
            else:
                name = att.guest_name

        invitation = inv_map.get(att.invitation_id) if att.invitation_id else None
        plus_ones = plus_ones_map.get(att.id, [])

        # QR payload mirrors backend resolution in event_cards.send:
        # prefer the invitation_code, otherwise fall back to attendee.id.
        # Returned so the card editor's browser-side renderer can bake the
        # exact same QR into each invitation card PNG it pre-renders.
        qr_payload = (invitation.invitation_code if invitation and invitation.invitation_code else str(att.id))

        out.append({
            "id": str(att.id),
            "event_id": str(att.event_id),
            "guest_type": guest_type,
            "name": name, "avatar": avatar,
            "common_name": getattr(att, "common_name", None),
            "email": email, "phone": phone,
            "rsvp_status": att.rsvp_status.value if hasattr(att.rsvp_status, "value") else att.rsvp_status,
            "dietary_requirements": att.dietary_restrictions,
            "meal_preference": att.meal_preference,
            "special_requests": att.special_requests,
            "plus_ones": len(plus_ones),
            "plus_one_names": [po.name for po in plus_ones],
            "notes": invitation.notes if invitation else None,
            "invitation_sent": invitation.sent_at is not None if invitation else False,
            "invitation_sent_at": invitation.sent_at.isoformat() if invitation and invitation.sent_at else None,
            "invitation_method": invitation.sent_via if invitation else None,
            "checked_in": att.checked_in,
            "checked_in_at": att.checked_in_at.isoformat() if att.checked_in_at else None,
            "created_at": att.created_at.isoformat() if att.created_at else None,
            "qr_payload": qr_payload,
        })

    return out

