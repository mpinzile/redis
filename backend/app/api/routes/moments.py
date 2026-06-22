# Moments Routes - /moments/...
# Handles stories/moments: CRUD, viewing, highlights

import os
import uuid
from datetime import datetime, timedelta
from typing import List, Optional

import httpx
import pytz
from fastapi import APIRouter, Depends, File, Form, UploadFile, Body
from sqlalchemy.orm import Session

from core.config import UPLOAD_SERVICE_URL
from core.database import get_db
from models import (
    UserMoment, UserMomentSticker, UserMomentViewer,
    UserMomentHighlight, UserMomentHighlightItem, User, UserProfile,
    UserCircle, UserFollower,
    ContentAppeal, AppealStatusEnum, AppealContentTypeEnum,
    MomentContentTypeEnum,
)
from utils.auth import get_current_user, get_optional_user

from utils.helpers import standard_response

EAT = pytz.timezone("Africa/Nairobi")
router = APIRouter(prefix="/moments", tags=["Moments/Stories"])


def _moment_content_type(value):
    if hasattr(value, "value"):
        return value.value
    raw = str(value or "image")
    return raw.split(".")[-1]


def _moment_dict(db, m, current_user_id=None):
    # Single-moment convenience wrapper around the batch builder. Kept so the
    # /moments/{id} detail endpoints continue working without changes.
    out = _build_moment_dicts(db, [m], current_user_id=current_user_id)
    return out[0] if out else None


def _build_moment_dicts(db, moments, current_user_id=None, _users_map=None, _profiles_map=None):
    """Batch-load all author/viewer/has_seen data for a collection of moments.

    Replaces a per-moment 4-query pattern (User, UserProfile, viewer count,
    has_seen) with at most 4 batched queries regardless of input size.
    """
    if not moments:
        return []
    from sqlalchemy import func as sa_func
    moment_ids = [m.id for m in moments]
    user_ids = list({m.user_id for m in moments})

    users_map = _users_map if _users_map is not None else {
        u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()
    }
    profiles_map = _profiles_map if _profiles_map is not None else {
        p.user_id: p for p in db.query(UserProfile).filter(UserProfile.user_id.in_(user_ids)).all()
    }

    # Viewer count per moment, excluding the author (matches legacy semantics).
    viewer_rows = (
        db.query(UserMomentViewer.moment_id, sa_func.count(UserMomentViewer.id))
        .join(UserMoment, UserMoment.id == UserMomentViewer.moment_id)
        .filter(
            UserMomentViewer.moment_id.in_(moment_ids),
            UserMomentViewer.viewer_id != UserMoment.user_id,
        )
        .group_by(UserMomentViewer.moment_id)
        .all()
    )
    viewer_counts = {mid: int(cnt or 0) for mid, cnt in viewer_rows}

    seen_ids = set()
    if current_user_id:
        seen_ids = {
            row[0] for row in db.query(UserMomentViewer.moment_id).filter(
                UserMomentViewer.moment_id.in_(moment_ids),
                UserMomentViewer.viewer_id == current_user_id,
            ).all()
        }

    out = []
    for m in moments:
        user = users_map.get(m.user_id)
        profile = profiles_map.get(m.user_id)
        ct = _moment_content_type(m.content_type)
        media_url = m.media_url
        background_color = None
        if isinstance(media_url, str) and media_url.startswith("text:"):
            ct = "text"
            background_color = media_url[5:] or None
            media_url = None
        out.append({
            "id": str(m.id),
            "author": {
                "id": str(user.id),
                "name": f"{user.first_name} {user.last_name}",
                "avatar": profile.profile_picture_url if profile else None,
                "is_verified": user.is_identity_verified or False,
            } if user else None,
            "caption": m.caption,
            "content_type": ct,
            "media_url": media_url,
            "thumbnail_url": getattr(m, "thumbnail_url", None),
            "background_color": background_color,
            "location": getattr(m, "location", None),
            "viewer_count": viewer_counts.get(m.id, 0),
            "has_seen": m.id in seen_ids,
            "is_active": m.is_active,
            "expires_at": m.expires_at.isoformat() if m.expires_at else None,
            "created_at": m.created_at.isoformat() if m.created_at else None,
        })
    return out



# ──────────────────────────────────────────────
# MY REMOVED MOMENTS — must be before /{moment_id} wildcard
# ──────────────────────────────────────────────

@router.get("/my-removed")
def get_my_removed_moments(
    page: int = 1, limit: int = 30,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Returns moments removed by an admin so the user can view removal reason and appeal."""
    from sqlalchemy import func as sa_func
    page = max(1, int(page or 1)); limit = max(1, min(int(limit or 30), 100))

    moments = (
        db.query(UserMoment)
        .filter(UserMoment.user_id == current_user.id, UserMoment.is_active == False)
        .order_by(UserMoment.created_at.desc())
        .offset((page - 1) * limit).limit(limit).all()
    )
    if not moments:
        return standard_response(True, "Removed moments retrieved", [])

    moment_ids = [m.id for m in moments]
    # Batch: appeals, viewer counts, single author (always current_user).
    appeals_map = {
        a.content_id: a for a in db.query(ContentAppeal).filter(
            ContentAppeal.user_id == current_user.id,
            ContentAppeal.content_id.in_(moment_ids),
            ContentAppeal.content_type == AppealContentTypeEnum.moment,
        ).all()
    }
    viewer_counts = {
        mid: int(cnt or 0) for mid, cnt in db.query(
            UserMomentViewer.moment_id, sa_func.count(UserMomentViewer.id),
        ).filter(UserMomentViewer.moment_id.in_(moment_ids)).group_by(UserMomentViewer.moment_id).all()
    }
    user = current_user
    profile = db.query(UserProfile).filter(UserProfile.user_id == user.id).first()

    data = []
    for m in moments:
        appeal = appeals_map.get(m.id)
        data.append({
            "id": str(m.id),
            "caption": m.caption,
            "media_url": m.media_url,
            "content_type": m.content_type.value if hasattr(m.content_type, "value") else str(m.content_type),
            "location": getattr(m, "location", None),
            "viewer_count": viewer_counts.get(m.id, 0),
            "removal_reason": getattr(m, "removal_reason", None),
            "removed_at": (m.updated_at.isoformat() if getattr(m, "updated_at", None) else (m.created_at.isoformat() if m.created_at else None)),
            "created_at": m.created_at.isoformat() if m.created_at else None,
            "author": {
                "id": str(user.id),
                "name": f"{user.first_name} {user.last_name}",
                "username": user.username,
                "avatar": profile.profile_picture_url if profile else None,
            },
            "appeal": {
                "id": str(appeal.id),
                "status": appeal.status.value,
                "admin_notes": appeal.admin_notes,
                "created_at": appeal.created_at.isoformat() if appeal.created_at else None,
            } if appeal else None,
        })
    return standard_response(True, "Removed moments retrieved", data)


# ──────────────────────────────────────────────
# PUBLIC TRENDING — glimpses for landing page
# ──────────────────────────────────────────────

@router.get("/public/trending")
def get_public_trending_moments(limit: int = 12, db: Session = Depends(get_db)):
    """Public endpoint: truly trending active moments (glimpses) ranked by view
    count. Only items with at least one viewer are returned. No auth required."""
    from sqlalchemy import func, desc
    limit = max(1, min(limit, 50))
    now = datetime.now(EAT)
    view_count = func.count(UserMomentViewer.id).label("vc")
    rows = (
        db.query(UserMoment, view_count)
        .outerjoin(UserMomentViewer, UserMomentViewer.moment_id == UserMoment.id)
        .filter(UserMoment.is_active == True, UserMoment.expires_at > now)
        .group_by(UserMoment.id)
        .having(view_count > 0)
        .order_by(desc("vc"), UserMoment.created_at.desc())
        .limit(limit)
        .all()
    )
    moments = [r[0] for r in rows]
    return standard_response(True, "Trending moments", _build_moment_dicts(db, moments))


# Authenticated trending: same ranking as public/trending but restricted to
# authors the viewer follows OR has in their accepted circle (plus self). The
# mobile app uses this so users never see glimpses from strangers.
@router.get("/trending")
def get_trending_moments(
    limit: int = 12,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from sqlalchemy import func, desc
    limit = max(1, min(limit, 50))
    now = datetime.now(EAT)

    following_ids = {
        r.following_id for r in db.query(UserFollower.following_id).filter(
            UserFollower.follower_id == current_user.id
        ).all()
    }
    circle_ids = {
        r.circle_member_id for r in db.query(UserCircle.circle_member_id).filter(
            UserCircle.user_id == current_user.id,
            UserCircle.status == 'accepted',
        ).all()
    }
    allowed_author_ids = following_ids | circle_ids | {current_user.id}
    if not allowed_author_ids:
        return standard_response(True, "Trending moments", [])

    view_count = func.count(UserMomentViewer.id).label("vc")
    rows = (
        db.query(UserMoment, view_count)
        .outerjoin(UserMomentViewer, UserMomentViewer.moment_id == UserMoment.id)
        .filter(
            UserMoment.is_active == True,
            UserMoment.expires_at > now,
            UserMoment.user_id.in_(allowed_author_ids),
        )
        .group_by(UserMoment.id)
        .order_by(desc("vc"), UserMoment.created_at.desc())
        .limit(limit)
        .all()
    )
    moments = [r[0] for r in rows]
    return standard_response(
        True,
        "Trending moments",
        _build_moment_dicts(db, moments, current_user_id=current_user.id),
    )



@router.get("/")
def get_moments_feed(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Returns active moments grouped by author.

    Visibility: only authors that the current user follows OR has in their
    accepted circle, plus the current user's own moments.
    """
    now = datetime.now(EAT)

    # People I follow
    following_ids = {
        r.following_id for r in db.query(UserFollower.following_id).filter(
            UserFollower.follower_id == current_user.id
        ).all()
    }
    # People in my circle (accepted)
    circle_ids = {
        r.circle_member_id for r in db.query(UserCircle.circle_member_id).filter(
            UserCircle.user_id == current_user.id,
            UserCircle.status == 'accepted',
        ).all()
    }
    allowed_author_ids = following_ids | circle_ids | {current_user.id}
    if not allowed_author_ids:
        return standard_response(True, "Moments feed retrieved", [])

    moments = db.query(UserMoment).filter(
        UserMoment.is_active == True,
        UserMoment.expires_at > now,
        UserMoment.user_id.in_(allowed_author_ids),
    ).order_by(UserMoment.created_at.desc()).limit(200).all()

    # Pre-build all moment dicts in a single batch (≤4 queries total),
    # reusing the user/profile maps for the feed header below.
    author_ids = list({m.user_id for m in moments})
    users_map = {u.id: u for u in db.query(User).filter(User.id.in_(author_ids)).all()} if author_ids else {}
    profiles_map = {
        p.user_id: p for p in db.query(UserProfile).filter(UserProfile.user_id.in_(author_ids)).all()
    } if author_ids else {}
    moment_dicts = _build_moment_dicts(
        db, moments, current_user_id=current_user.id,
        _users_map=users_map, _profiles_map=profiles_map,
    )

    # Group by user, latest first per user.
    user_moments: dict[str, list[dict]] = {}
    for d in moment_dicts:
        author = d.get("author") or {}
        uid = author.get("id")
        if not uid:
            continue
        user_moments.setdefault(uid, []).append(d)

    feed = []
    for uid, items in user_moments.items():
        try:
            uuid_uid = uuid.UUID(uid)
        except ValueError:
            continue
        user = users_map.get(uuid_uid)
        profile = profiles_map.get(uuid_uid)
        items = sorted(items, key=lambda item: item["created_at"] or "")
        latest_created_at = items[-1]["created_at"] if items else None
        all_seen = all(item["has_seen"] for item in items)
        feed.append({
            "user": {
                "id": uid,
                "name": f"{user.first_name} {user.last_name}" if user else None,
                "avatar": profile.profile_picture_url if profile else None,
                "is_self": uid == str(current_user.id),
                "is_verified": bool(user.is_identity_verified) if user else False,
                "is_identity_verified": bool(user.is_identity_verified) if user else False,
            },
            "moments": items,
            "all_seen": all_seen,
            "latest_created_at": latest_created_at,
        })

    # Self first, then others by latest moment desc.
    self_entries = [f for f in feed if f["user"]["is_self"]]
    other_entries = sorted(
        [f for f in feed if not f["user"]["is_self"]],
        key=lambda f: f["latest_created_at"] or "",
        reverse=True,
    )
    feed = self_entries + other_entries

    return standard_response(True, "Moments feed retrieved", feed)


@router.get("/me")
def get_my_moments(
    page: int = 1, limit: int = 30,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    page = max(1, int(page or 1)); limit = max(1, min(int(limit or 30), 100))
    moments = (
        db.query(UserMoment)
        .filter(UserMoment.user_id == current_user.id, UserMoment.is_active == True)
        .order_by(UserMoment.created_at.desc())
        .offset((page - 1) * limit).limit(limit).all()
    )
    return standard_response(True, "Your moments retrieved", _build_moment_dicts(db, moments, current_user_id=current_user.id))


@router.get("/user/{user_id}")
def get_user_moments(
    user_id: str,
    page: int = 1, limit: int = 30,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    try:
        uid = uuid.UUID(user_id)
    except ValueError:
        return standard_response(False, "Invalid user ID")
    page = max(1, int(page or 1)); limit = max(1, min(int(limit or 30), 100))
    now = datetime.now(EAT)
    moments = (
        db.query(UserMoment)
        .filter(UserMoment.user_id == uid, UserMoment.is_active == True, UserMoment.expires_at > now)
        .order_by(UserMoment.created_at.asc())
        .offset((page - 1) * limit).limit(limit).all()
    )
    return standard_response(True, "User moments retrieved", _build_moment_dicts(db, moments, current_user_id=current_user.id))


@router.post("/")
async def create_moment(
    content: Optional[str] = Form(None), location: Optional[str] = Form(None),
    media: Optional[UploadFile] = File(None), duration_hours: int = Form(24),
    content_type: Optional[str] = Form("image"),
    background_color: Optional[str] = Form(None),
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    now = datetime.now(EAT)
    media_url = None
    thumbnail_url = None

    media_content_type = (content_type or "image").lower()
    if media_content_type not in {"image", "video", "text"}:
        media_content_type = "image"
    if media and media.filename:
        file_ext = os.path.splitext(media.filename)[1].lower()
        if file_ext in ('.mp4', '.mov', '.webm', '.avi', '.mkv'):
            media_content_type = "video"
        elif media_content_type == "text":
            # If a file is uploaded, treat as image
            media_content_type = "image"

        file_content = await media.read()
        _, ext = os.path.splitext(media.filename)
        unique_name = f"{uuid.uuid4().hex}{ext}"
        # Videos take longer to upload — use a generous timeout and surface
        # any failure to the client so the composer can show a real error
        # instead of a silent "Request failed".
        upload_timeout = 180.0 if media_content_type == "video" else 60.0
        try:
            async with httpx.AsyncClient(timeout=upload_timeout) as client:
                resp = await client.post(
                    UPLOAD_SERVICE_URL,
                    data={"target_path": f"nuru/uploads/moments/{current_user.id}/"},
                    files={"file": (unique_name, file_content, media.content_type)},
                )
            result = resp.json()
            if result.get("success"):
                media_url = result["data"]["url"]
                thumbnail_url = result["data"].get("thumbnail_url")
            else:
                return standard_response(False, result.get("message") or "Upload failed")
        except httpx.TimeoutException:
            return standard_response(False, "Upload timed out — please try again on a stronger connection")
        except Exception as exc:  # noqa: BLE001
            return standard_response(False, f"Upload failed: {exc}")

    # Validate text moments
    if media_content_type == "text":
        if not content or not content.strip():
            return standard_response(False, "Text moment requires content")
        # Encode background color into media_url field as a marker (e.g. "text:#RRGGBB")
        media_url = f"text:{background_color or '#0F172A'}"

    moment = UserMoment(
        id=uuid.uuid4(), user_id=current_user.id,
        caption=content.strip() if content else None,
        content_type=MomentContentTypeEnum(media_content_type),
        media_url=media_url or "",
        thumbnail_url=thumbnail_url,
        is_active=True,
        expires_at=now + timedelta(hours=duration_hours),
        created_at=now,
    )
    if hasattr(moment, "location") and location:
        moment.location = location.strip()
    db.add(moment)
    db.commit()

    return standard_response(True, "Moment created successfully", _moment_dict(db, moment, current_user.id))

@router.get("/{moment_id}")
def get_single_moment(
    moment_id: str,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_user),
):
    """Single-moment fetch used by /moment/:id deep links. Auth-optional;
    returns the moment if it is active and not expired."""
    try:
        mid = uuid.UUID(moment_id)
    except ValueError:
        return standard_response(False, "Invalid moment ID")
    m = db.query(UserMoment).filter(UserMoment.id == mid).first()
    if not m or not m.is_active:
        return standard_response(False, "Moment not found")
    if m.expires_at and m.expires_at < datetime.now(EAT).replace(tzinfo=None):
        return standard_response(False, "Moment has expired")
    return standard_response(
        True,
        "Moment retrieved",
        _moment_dict(db, m, current_user.id if current_user else None),
    )



@router.delete("/{moment_id}")
def delete_moment(moment_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        mid = uuid.UUID(moment_id)
    except ValueError:
        return standard_response(False, "Invalid moment ID")
    m = db.query(UserMoment).filter(UserMoment.id == mid, UserMoment.user_id == current_user.id).first()
    if not m:
        return standard_response(False, "Moment not found")
    m.is_active = False
    db.commit()
    return standard_response(True, "Moment deleted")


@router.post("/{moment_id}/seen")
def mark_moment_seen(moment_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        mid = uuid.UUID(moment_id)
    except ValueError:
        return standard_response(False, "Invalid moment ID")
    m = db.query(UserMoment).filter(UserMoment.id == mid).first()
    if not m:
        return standard_response(False, "Moment not found")
    # Don't record the author as a viewer of their own glimpse.
    if m.user_id == current_user.id:
        return standard_response(True, "Author view skipped")
    existing = db.query(UserMomentViewer).filter(UserMomentViewer.moment_id == mid, UserMomentViewer.viewer_id == current_user.id).first()
    if not existing:
        db.add(UserMomentViewer(id=uuid.uuid4(), moment_id=mid, viewer_id=current_user.id, viewed_at=datetime.now(EAT)))
        db.commit()
    return standard_response(True, "Moment marked as seen")


@router.get("/{moment_id}/viewers")
def get_moment_viewers(moment_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        mid = uuid.UUID(moment_id)
    except ValueError:
        return standard_response(False, "Invalid moment ID")
    m = db.query(UserMoment).filter(UserMoment.id == mid).first()
    if not m:
        return standard_response(False, "Moment not found")
    # Exclude the author from the viewer list (WhatsApp-style).
    viewers = db.query(UserMomentViewer).filter(
        UserMomentViewer.moment_id == mid,
        UserMomentViewer.viewer_id != m.user_id,
    ).order_by(UserMomentViewer.viewed_at.desc()).all()
    data = []
    for v in viewers:
        u = db.query(User).filter(User.id == v.viewer_id).first()
        p = db.query(UserProfile).filter(UserProfile.user_id == v.viewer_id).first() if u else None
        data.append({"id": str(v.viewer_id), "name": f"{u.first_name} {u.last_name}" if u else None, "avatar": p.profile_picture_url if p else None, "viewed_at": v.viewed_at.isoformat() if v.viewed_at else None})
    return standard_response(True, "Viewers retrieved", data)


@router.post("/{moment_id}/react")
def react_to_moment(moment_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return standard_response(True, "Reaction recorded")


@router.post("/{moment_id}/reply")
def reply_to_moment(moment_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return standard_response(True, "Reply sent")


@router.post("/{moment_id}/stickers/{sticker_id}/vote")
def vote_on_poll(moment_id: str, sticker_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return standard_response(True, "Vote recorded")


# ──────────────────────────────────────────────
# HIGHLIGHTS
# ──────────────────────────────────────────────
@router.get("/highlights")
def get_my_highlights(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    highlights = db.query(UserMomentHighlight).filter(UserMomentHighlight.user_id == current_user.id).order_by(UserMomentHighlight.created_at.desc()).all()
    data = [{"id": str(h.id), "title": h.title, "cover_image": h.cover_image_url if hasattr(h, "cover_image_url") else None, "moment_count": db.query(UserMomentHighlightItem).filter(UserMomentHighlightItem.highlight_id == h.id).count()} for h in highlights]
    return standard_response(True, "Highlights retrieved", data)


@router.get("/highlights/user/{user_id}")
def get_user_highlights(user_id: str, db: Session = Depends(get_db)):
    try:
        uid = uuid.UUID(user_id)
    except ValueError:
        return standard_response(False, "Invalid user ID")
    highlights = db.query(UserMomentHighlight).filter(UserMomentHighlight.user_id == uid).all()
    return standard_response(True, "User highlights retrieved", [{"id": str(h.id), "title": h.title} for h in highlights])


@router.post("/highlights")
def create_highlight(body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    now = datetime.now(EAT)
    h = UserMomentHighlight(id=uuid.uuid4(), user_id=current_user.id, title=body.get("title", ""), created_at=now, updated_at=now)
    db.add(h)
    db.commit()
    return standard_response(True, "Highlight created", {"id": str(h.id)})


@router.put("/highlights/{highlight_id}")
def update_highlight(highlight_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        hid = uuid.UUID(highlight_id)
    except ValueError:
        return standard_response(False, "Invalid highlight ID")
    h = db.query(UserMomentHighlight).filter(UserMomentHighlight.id == hid, UserMomentHighlight.user_id == current_user.id).first()
    if not h:
        return standard_response(False, "Highlight not found")
    if "title" in body: h.title = body["title"]
    h.updated_at = datetime.now(EAT)
    db.commit()
    return standard_response(True, "Highlight updated")


@router.delete("/highlights/{highlight_id}")
def delete_highlight(highlight_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        hid = uuid.UUID(highlight_id)
    except ValueError:
        return standard_response(False, "Invalid highlight ID")
    h = db.query(UserMomentHighlight).filter(UserMomentHighlight.id == hid, UserMomentHighlight.user_id == current_user.id).first()
    if not h:
        return standard_response(False, "Highlight not found")
    db.delete(h)
    db.commit()
    return standard_response(True, "Highlight deleted")


@router.post("/highlights/{highlight_id}/moments")
def add_moment_to_highlight(highlight_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        hid = uuid.UUID(highlight_id)
        mid = uuid.UUID(body.get("moment_id", ""))
    except ValueError:
        return standard_response(False, "Invalid ID")

    # Pre-insertion duplicate check
    existing = db.query(UserMomentHighlightItem).filter(
        UserMomentHighlightItem.highlight_id == hid,
        UserMomentHighlightItem.moment_id == mid,
    ).first()
    if existing:
        return standard_response(False, "This moment is already in the highlight")

    db.add(UserMomentHighlightItem(id=uuid.uuid4(), highlight_id=hid, moment_id=mid, created_at=datetime.now(EAT)))
    db.commit()
    return standard_response(True, "Moment added to highlight")


@router.delete("/highlights/{highlight_id}/moments/{moment_id}")
def remove_moment_from_highlight(highlight_id: str, moment_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        hid = uuid.UUID(highlight_id)
        mid = uuid.UUID(moment_id)
    except ValueError:
        return standard_response(False, "Invalid ID")
    item = db.query(UserMomentHighlightItem).filter(UserMomentHighlightItem.highlight_id == hid, UserMomentHighlightItem.moment_id == mid).first()
    if item:
        db.delete(item)
        db.commit()
    return standard_response(True, "Moment removed from highlight")


# ──────────────────────────────────────────────
# CONTENT APPEALS
# ──────────────────────────────────────────────

@router.post("/{moment_id}/appeal")
def submit_moment_appeal(
    moment_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """User appeals the removal of their own moment."""
    try:
        mid = uuid.UUID(moment_id)
    except ValueError:
        return standard_response(False, "Invalid moment ID")

    moment = db.query(UserMoment).filter(UserMoment.id == mid, UserMoment.user_id == current_user.id).first()
    if not moment:
        return standard_response(False, "Moment not found or not yours")
    if moment.is_active:
        return standard_response(False, "Moment is not removed — no appeal needed")

    reason = (body.get("reason") or "").strip()
    if not reason or len(reason) < 10:
        return standard_response(False, "Please provide a reason (at least 10 characters)")

    existing = db.query(ContentAppeal).filter(
        ContentAppeal.user_id == current_user.id,
        ContentAppeal.content_id == mid,
        ContentAppeal.content_type == AppealContentTypeEnum.moment,
    ).first()
    if existing:
        return standard_response(False, "You have already submitted an appeal for this moment")

    appeal = ContentAppeal(
        id=uuid.uuid4(),
        user_id=current_user.id,
        content_id=mid,
        content_type=AppealContentTypeEnum.moment,
        appeal_reason=reason,
        status=AppealStatusEnum.pending,
        created_at=datetime.now(EAT),
        updated_at=datetime.now(EAT),
    )
    db.add(appeal)
    db.commit()
    return standard_response(True, "Appeal submitted successfully", {
        "id": str(appeal.id),
        "status": appeal.status.value,
    })


