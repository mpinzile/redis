# Posts Routes - /posts/...
# Handles social feed posts, interactions (glow, echo, spark), comments

import os
import uuid
from datetime import datetime
from typing import List, Optional

import httpx
import pytz
from fastapi import APIRouter, Depends, File, Form, UploadFile, Body, Request
from sqlalchemy import func as sa_func
from sqlalchemy.orm import Session

from core.config import UPLOAD_SERVICE_URL
from core.database import get_db
from models import (
    UserFeed, UserFeedImage, UserFeedGlow, UserFeedEcho,
    UserFeedSpark, UserFeedComment, UserFeedCommentGlow,
    UserFeedPinned, UserFeedSaved, User, UserProfile, UserCircle, FeedVisibilityEnum,
    ContentAppeal, AppealStatusEnum, AppealContentTypeEnum,
    Event, EventShareDurationEnum,
)
from utils.auth import get_current_user
from utils.helpers import standard_response, paginate


def _visible_feed_query(db, current_user_id):
    """Return a query for active posts visible to current_user.
    Public posts: everyone sees them.
    Circle posts: only the author OR users who are IN the author's circle can see them.
    i.e. if author X set post to 'circle', current_user sees it only if X added current_user to X's circle.
    """
    from sqlalchemy import or_, and_
    # Find all users who have added current_user to THEIR circle
    try:
        authors_who_include_me = db.query(UserCircle.user_id).filter(
            UserCircle.circle_member_id == current_user_id
        )
        author_ids = [r[0] for r in authors_who_include_me.all()]
    except Exception:
        db.rollback()
        author_ids = []
    query = db.query(UserFeed).filter(UserFeed.is_active == True)
    if author_ids:
        query = query.filter(
            or_(
                UserFeed.visibility == FeedVisibilityEnum.public,
                UserFeed.visibility.is_(None),
                UserFeed.user_id == current_user_id,
                and_(
                    UserFeed.visibility == FeedVisibilityEnum.circle,
                    UserFeed.user_id.in_(author_ids),
                ),
            )
        )
    else:
        query = query.filter(
            or_(
                UserFeed.visibility == FeedVisibilityEnum.public,
                UserFeed.visibility.is_(None),
                UserFeed.user_id == current_user_id,
            )
        )
    return query

EAT = pytz.timezone("Africa/Nairobi")
router = APIRouter(prefix="/posts", tags=["Posts/Feed"])


def _user_dict(db, user_id):
    """Build a compact user dict for embedding in comments/replies."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        return None
    p = db.query(UserProfile).filter(UserProfile.user_id == user_id).first()
    return {
        "id": str(u.id),
        "name": f"{u.first_name} {u.last_name}",
        "username": u.username,
        "avatar": p.profile_picture_url if p else None,
        "is_identity_verified": u.is_identity_verified or False,
    }


def _comment_dict(db, comment, current_user_id=None, include_replies_preview=True):
    """Build a full comment dict with glow status and optional replies preview."""
    author = _user_dict(db, comment.user_id)
    glow_count = db.query(sa_func.count(UserFeedCommentGlow.id)).filter(
        UserFeedCommentGlow.comment_id == comment.id
    ).scalar() or 0
    reply_count = db.query(sa_func.count(UserFeedComment.id)).filter(
        UserFeedComment.parent_comment_id == comment.id,
        UserFeedComment.is_active == True,
    ).scalar() or 0

    has_glowed = False
    if current_user_id:
        has_glowed = db.query(UserFeedCommentGlow).filter(
            UserFeedCommentGlow.comment_id == comment.id,
            UserFeedCommentGlow.user_id == current_user_id,
        ).first() is not None

    result = {
        "id": str(comment.id),
        "content": comment.content,
        "author": author,
        "glow_count": glow_count,
        "reply_count": reply_count,
        "has_glowed": has_glowed,
        "is_edited": comment.is_edited or False,
        "is_pinned": comment.is_pinned or False,
        "parent_id": str(comment.parent_comment_id) if comment.parent_comment_id else None,
        "created_at": comment.created_at.isoformat() if comment.created_at else None,
        "updated_at": comment.updated_at.isoformat() if comment.updated_at else None,
    }

    # Include a preview of first 2 replies for top-level comments
    if include_replies_preview and not comment.parent_comment_id:
        replies = db.query(UserFeedComment).filter(
            UserFeedComment.parent_comment_id == comment.id,
            UserFeedComment.is_active == True,
        ).order_by(UserFeedComment.created_at.asc()).limit(2).all()
        result["replies_preview"] = [
            _comment_dict(db, r, current_user_id, include_replies_preview=False)
            for r in replies
        ]

    return result


def _post_dict(db, post, current_user_id=None):
    """Single-post serializer (kept for single-item endpoints like create/update).
    For list endpoints, use build_post_dicts() from utils.batch_loaders instead."""
    from utils.batch_loaders import build_post_dicts
    results = build_post_dicts(db, [post], current_user_id)
    return results[0] if results else {}



# ──────────────────────────────────────────────
# MY POSTS — must be before /{post_id} wildcard
# ──────────────────────────────────────────────

@router.get("/me")
def get_my_posts(page: int = 1, limit: int = 30, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Get current user's own posts (all visibility levels)."""
    page = max(1, page)
    limit = max(1, min(limit, 50))
    query = db.query(UserFeed).filter(UserFeed.user_id == current_user.id, UserFeed.is_active == True).order_by(UserFeed.created_at.desc())
    from utils.batch_loaders import build_post_dicts
    items, pagination = paginate(query, page, limit)
    return standard_response(True, "Your posts retrieved", {"posts": build_post_dicts(db, items, current_user.id), "pagination": pagination})


# ──────────────────────────────────────────────
# MY REMOVED POSTS — must be before /{post_id} wildcard
# ──────────────────────────────────────────────

@router.get("/my-removed")
def get_my_removed_posts(
    page: int = 1, limit: int = 20,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Returns posts removed by an admin so the user can view removal reason and appeal."""
    page = max(1, int(page or 1)); limit = max(1, min(int(limit or 20), 100))
    posts = (
        db.query(UserFeed)
        .filter(UserFeed.user_id == current_user.id, UserFeed.is_active == False)
        .order_by(UserFeed.updated_at.desc())
        .offset((page - 1) * limit).limit(limit).all()
    )
    if not posts:
        return standard_response(True, "Removed posts retrieved", [])

    post_ids = [p.id for p in posts]

    # Batch all the per-post lookups in 5 queries total (down from ~7 × N).
    appeals_map = {
        a.content_id: a for a in db.query(ContentAppeal).filter(
            ContentAppeal.user_id == current_user.id,
            ContentAppeal.content_id.in_(post_ids),
            ContentAppeal.content_type == AppealContentTypeEnum.post,
        ).all()
    }
    images_map: dict = {}
    for img in db.query(UserFeedImage).filter(UserFeedImage.feed_id.in_(post_ids)).all():
        images_map.setdefault(img.feed_id, []).append(img)
    glow_counts = {
        fid: int(c or 0) for fid, c in db.query(
            UserFeedGlow.feed_id, sa_func.count(UserFeedGlow.id)
        ).filter(UserFeedGlow.feed_id.in_(post_ids)).group_by(UserFeedGlow.feed_id).all()
    }
    echo_counts = {
        fid: int(c or 0) for fid, c in db.query(
            UserFeedEcho.feed_id, sa_func.count(UserFeedEcho.id)
        ).filter(UserFeedEcho.feed_id.in_(post_ids)).group_by(UserFeedEcho.feed_id).all()
    }
    comment_counts = {
        fid: int(c or 0) for fid, c in db.query(
            UserFeedComment.feed_id, sa_func.count(UserFeedComment.id)
        ).filter(UserFeedComment.feed_id.in_(post_ids), UserFeedComment.is_active == True)
         .group_by(UserFeedComment.feed_id).all()
    }
    # Author is always the current user — one lookup.
    user = current_user
    profile = db.query(UserProfile).filter(UserProfile.user_id == user.id).first()

    data = []
    for p in posts:
        appeal = appeals_map.get(p.id)
        images = images_map.get(p.id, [])
        data.append({
            "id": str(p.id),
            "content": p.content,
            "images": [{"url": img.image_url, "media_type": getattr(img, 'media_type', None) or 'image'} for img in images],
            "location": p.location,
            "visibility": p.visibility.value if p.visibility else "public",
            "glow_count": glow_counts.get(p.id, 0),
            "echo_count": echo_counts.get(p.id, 0),
            "comment_count": comment_counts.get(p.id, 0),
            "removal_reason": getattr(p, "removal_reason", None),
            "removed_at": p.updated_at.isoformat() if p.updated_at else None,
            "created_at": p.created_at.isoformat() if p.created_at else None,
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
    return standard_response(True, "Removed posts retrieved", data)


@router.get("/saved")
def get_saved_posts(page: int = 1, limit: int = 20, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    query = (
        db.query(UserFeed)
        .join(UserFeedSaved, UserFeedSaved.feed_id == UserFeed.id)
        .filter(UserFeedSaved.user_id == current_user.id, UserFeed.is_active == True)
        .order_by(UserFeedSaved.created_at.desc())
    )
    from utils.batch_loaders import build_post_dicts
    items, pagination = paginate(query, page, limit)
    posts = build_post_dicts(db, items, current_user.id)
    for p in posts:
        p["is_saved"] = True
    return standard_response(True, "Saved posts retrieved", {"saved_posts": posts, "pagination": pagination})


@router.get("/feed")
def get_feed(
    page: int = 1,
    limit: int = 20,
    mode: str = "ranked",  # "ranked" or "chronological"
    session_id: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Intelligent ranked feed with Redis caching (TTL 2 min).
    """
    from core.redis import cache_get, cache_set, CacheKeys

    uid = str(current_user.id)
    cache_key = CacheKeys.for_feed(uid, page, limit, mode)
    cached = cache_get(cache_key)
    if cached is not None:
        return standard_response(True, "Feed retrieved", cached)

    if mode == "chronological":
        query = _visible_feed_query(db, current_user.id).order_by(UserFeed.created_at.desc())
        items, pagination = paginate(query, page, limit)
        from utils.batch_loaders import build_post_dicts
        result = {
            "posts": build_post_dicts(db, items, current_user.id),
            "pagination": pagination,
            "feed_mode": "chronological",
        }
        cache_set(cache_key, result, ttl_seconds=30)
        return standard_response(True, "Feed retrieved", result)

    # ── Ranked Feed ──
    try:
        from services.feed_ranking import (
            generate_ranked_feed, get_cold_start_feed,
            UserInteractionLog,
        )

        interaction_count = db.query(sa_func.count(UserInteractionLog.id)).filter(
            UserInteractionLog.user_id == current_user.id
        ).scalar() or 0

        # Cold-start until the user has produced enough signals for the
        # ranker to actually personalise. Once over the threshold we
        # always use the ranked path.
        if interaction_count < 10:
            posts, pagination = get_cold_start_feed(
                db, current_user.id, page, limit, session_id
            )
        else:
            posts, pagination = generate_ranked_feed(
                db, current_user.id, page, limit, session_id
            )

        from utils.batch_loaders import build_post_dicts
        result = {
            "posts": build_post_dicts(db, posts, current_user.id),
            "pagination": pagination,
            "feed_mode": "ranked" if interaction_count >= 10 else "cold_start",
        }
        # Short TTL so newly logged interactions surface within seconds.
        # Hard cache invalidation also runs in log_interaction(), this is
        # belt-and-suspenders for view-only sessions.
        cache_set(cache_key, result, ttl_seconds=30)
        return standard_response(True, "Feed retrieved", result)

    except Exception as e:
        import traceback
        traceback.print_exc()
        from utils.batch_loaders import build_post_dicts
        query = _visible_feed_query(db, current_user.id).order_by(UserFeed.created_at.desc())
        items, pagination = paginate(query, page, limit)
        result = {
            "posts": build_post_dicts(db, items, current_user.id),
            "pagination": pagination,
            "feed_mode": "chronological_fallback",
        }
        cache_set(cache_key, result, ttl_seconds=30)
        return standard_response(True, "Feed retrieved", result)


@router.get("/explore")
def get_explore(page: int = 1, limit: int = 20, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    query = _visible_feed_query(db, current_user.id).order_by(UserFeed.created_at.desc())
    from utils.batch_loaders import build_post_dicts
    items, pagination = paginate(query, page, limit)
    return standard_response(True, "Explore posts retrieved", {"posts": build_post_dicts(db, items, current_user.id), "pagination": pagination})


@router.get("/user/{user_id}")
def get_user_posts(user_id: str, page: int = 1, limit: int = 20, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        uid = uuid.UUID(user_id)
    except ValueError:
        return standard_response(False, "Invalid user ID")
    from sqlalchemy import or_, and_
    query = db.query(UserFeed).filter(UserFeed.user_id == uid, UserFeed.is_active == True)
    # If viewing someone else's profile, filter out circle posts unless they added you to their circle
    if str(uid) != str(current_user.id):
        is_in_circle = db.query(UserCircle).filter(
            UserCircle.user_id == uid,
            UserCircle.circle_member_id == current_user.id,
        ).first()
        if is_in_circle:
            # Can see public + circle posts
            pass
        else:
            # Can only see public posts
            query = query.filter(
                or_(
                    UserFeed.visibility == FeedVisibilityEnum.public,
                    UserFeed.visibility.is_(None),
                )
            )
    query = query.order_by(UserFeed.created_at.desc())
    from utils.batch_loaders import build_post_dicts
    items, pagination = paginate(query, page, limit)
    return standard_response(True, "User posts retrieved", {"posts": build_post_dicts(db, items, current_user.id), "pagination": pagination})

@router.get("/public/trending")
def get_public_trending_posts(limit: int = 12, db: Session = Depends(get_db)):
    """Public endpoint - trending posts with Redis cache (TTL 5 min)."""
    from core.redis import cache_get, cache_set, CacheKeys
    from sqlalchemy import or_, desc
    from utils.batch_loaders import build_post_dicts

    limit = min(limit, 50)

    cache_key = CacheKeys.for_trending(limit)
    cached = cache_get(cache_key)
    if cached is not None:
        return standard_response(True, "Trending moments", cached)

    has_image_subq = (
        db.query(UserFeedImage.feed_id)
        .filter(UserFeedImage.feed_id == UserFeed.id)
        .exists()
    )

    top_posts = (
        db.query(UserFeed)
        .filter(
            UserFeed.is_active == True,
            or_(
                UserFeed.visibility == FeedVisibilityEnum.public,
                UserFeed.visibility.is_(None),
            ),
            has_image_subq,
        )
        .order_by(
            desc(
                (UserFeed.glow_count * 2) + (UserFeed.echo_count * 3) + (UserFeed.spark_count)
            ),
            desc(UserFeed.created_at),
        )
        .limit(limit)
        .all()
    )

    if not top_posts:
        return standard_response(True, "No public moments", [])

    result = build_post_dicts(db, top_posts)
    cache_set(cache_key, result, ttl_seconds=300)  # 5 min TTL
    return standard_response(True, "Trending moments", result)


@router.get("/{post_id}/public")
def get_post_public(post_id: str, db: Session = Depends(get_db)):
    """Public endpoint - returns post data without auth for public posts only."""
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    post = db.query(UserFeed).filter(UserFeed.id == pid, UserFeed.is_active == True).first()
    if not post:
        return standard_response(False, "Post not found")
    # Only allow public posts
    if post.visibility and post.visibility != FeedVisibilityEnum.public:
        return standard_response(False, "This post is private")
    return standard_response(True, "Post retrieved", _post_dict(db, post))


@router.get("/{post_id}")
def get_post(post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    post = db.query(UserFeed).filter(UserFeed.id == pid).first()
    if not post:
        return standard_response(False, "Post not found")
    # Enforce circle visibility: only author or circle members can see circle posts
    if post.visibility == FeedVisibilityEnum.circle and str(post.user_id) != str(current_user.id):
        is_in_circle = db.query(UserCircle).filter(
            UserCircle.user_id == post.user_id,
            UserCircle.circle_member_id == current_user.id,
        ).first()
        if not is_in_circle:
            return standard_response(False, "This post is private")
    return standard_response(True, "Post retrieved", _post_dict(db, post, current_user.id))


@router.post("/")
async def create_post(
    content: Optional[str] = Form(None), location: Optional[str] = Form(None),
    visibility: Optional[str] = Form("public"),
    post_type: Optional[str] = Form("post"),
    event_id: Optional[str] = Form(None),
    expires_at: Optional[str] = Form(None),
    images: Optional[List[UploadFile]] = File(None),
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    is_event_share = post_type and post_type.strip() == "event_share"

    if not content and not images and not is_event_share:
        return standard_response(False, "Content or images are required")

    if is_event_share and not event_id:
        return standard_response(False, "Event ID is required for event shares")

    now = datetime.now(EAT)
    post = UserFeed(id=uuid.uuid4(), user_id=current_user.id, content=content.strip() if content else None, is_active=True, created_at=now, updated_at=now)
    if location:
        post.location = location.strip()
    if visibility and visibility.strip() in ("public", "circle"):
        post.visibility = FeedVisibilityEnum(visibility.strip())
    else:
        post.visibility = FeedVisibilityEnum.public

    # Handle event share
    if is_event_share:
        post.post_type = "event_share"
        try:
            post.shared_event_id = uuid.UUID(event_id.strip())
        except (ValueError, AttributeError):
            return standard_response(False, "Invalid event ID")
        # Set expiration
        if expires_at:
            try:
                post.share_expires_at = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
                post.share_duration = EventShareDurationEnum.timed
            except (ValueError, TypeError):
                pass
        else:
            post.share_duration = EventShareDurationEnum.lifetime

    db.add(post)
    db.flush()

    if images:
        for file in images:
            if not file or not file.filename:
                continue
            file_content = await file.read()
            _, ext = os.path.splitext(file.filename)
            unique_name = f"{uuid.uuid4().hex}{ext}"
            async with httpx.AsyncClient() as client:
                try:
                    resp = await client.post(UPLOAD_SERVICE_URL, data={"target_path": f"nuru/uploads/posts/{post.id}/"}, files={"file": (unique_name, file_content, file.content_type)}, timeout=20)
                    result = resp.json()
                    if result.get("success"):
                        mt = 'video' if (file.content_type or '').startswith('video') else 'image'
                        db.add(UserFeedImage(id=uuid.uuid4(), feed_id=post.id, image_url=result["data"]["url"], media_type=mt, created_at=now))
                except Exception:
                    pass

    db.commit()
    from core.redis import invalidate_user_feed, invalidate_trending
    invalidate_user_feed(str(current_user.id))
    invalidate_trending()
    return standard_response(True, "Post created successfully", _post_dict(db, post, current_user.id))


@router.put("/{post_id}")
def update_post(post_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    post = db.query(UserFeed).filter(UserFeed.id == pid, UserFeed.user_id == current_user.id).first()
    if not post:
        return standard_response(False, "Post not found")
    if "content" in body:
        post.content = body["content"]
    if "visibility" in body and body["visibility"] in ("public", "circle"):
        post.visibility = FeedVisibilityEnum(body["visibility"])
    post.updated_at = datetime.now(EAT)
    db.commit()
    from core.redis import invalidate_user_feed
    invalidate_user_feed(str(current_user.id))
    return standard_response(True, "Post updated successfully", _post_dict(db, post, current_user.id))


@router.delete("/{post_id}")
def delete_post(post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    post = db.query(UserFeed).filter(UserFeed.id == pid, UserFeed.user_id == current_user.id).first()
    if not post:
        return standard_response(False, "Post not found")
    post.is_active = False
    db.commit()
    from core.redis import invalidate_user_feed, invalidate_trending
    invalidate_user_feed(str(current_user.id))
    invalidate_trending()
    return standard_response(True, "Post deleted successfully")


# Glow
@router.post("/{post_id}/glow")
async def glow_post(post_id: str, request: Request, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    # Optional emoji body. Tolerate empty/missing body for backward compat.
    emoji: str | None = None
    try:
        body = await request.json()
        if isinstance(body, dict):
            raw = body.get("emoji")
            if isinstance(raw, str):
                raw = raw.strip()
                if raw and len(raw) <= 16:
                    emoji = raw
    except Exception:
        emoji = None

    existing = db.query(UserFeedGlow).filter(UserFeedGlow.feed_id == pid, UserFeedGlow.user_id == current_user.id).first()
    if not existing:
        db.add(UserFeedGlow(id=uuid.uuid4(), feed_id=pid, user_id=current_user.id, emoji=emoji, created_at=datetime.now(EAT)))
        db.commit()
    elif emoji is not None and getattr(existing, "emoji", None) != emoji:
        existing.emoji = emoji
        db.commit()
    glow_count = db.query(sa_func.count(UserFeedGlow.id)).filter(UserFeedGlow.feed_id == pid).scalar() or 0
    try:
        from core.redis import invalidate_user_feed
        invalidate_user_feed(str(current_user.id))
    except Exception:
        pass
    return standard_response(True, "Post glowed", {
        "has_glowed": True,
        "glow_count": glow_count,
        "glow_emoji": emoji or (existing.emoji if existing else None),
    })


@router.delete("/{post_id}/glow")
def unglow_post(post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    g = db.query(UserFeedGlow).filter(UserFeedGlow.feed_id == pid, UserFeedGlow.user_id == current_user.id).first()
    if g:
        db.delete(g)
        db.commit()
    glow_count = db.query(sa_func.count(UserFeedGlow.id)).filter(UserFeedGlow.feed_id == pid).scalar() or 0
    try:
        from core.redis import invalidate_user_feed
        invalidate_user_feed(str(current_user.id))
    except Exception:
        pass
    return standard_response(True, "Glow removed", {"has_glowed": False, "glow_count": glow_count})


# Echo
@router.post("/{post_id}/echo")
def echo_post(post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    existing = db.query(UserFeedEcho).filter(UserFeedEcho.feed_id == pid, UserFeedEcho.user_id == current_user.id).first()
    if existing:
        return standard_response(True, "Already echoed")
    db.add(UserFeedEcho(id=uuid.uuid4(), feed_id=pid, user_id=current_user.id, created_at=datetime.now(EAT)))
    db.commit()
    return standard_response(True, "Post echoed")


@router.delete("/{post_id}/echo")
def unecho_post(post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    e = db.query(UserFeedEcho).filter(UserFeedEcho.feed_id == pid, UserFeedEcho.user_id == current_user.id).first()
    if e:
        db.delete(e)
        db.commit()
    return standard_response(True, "Echo removed")


# Spark
@router.post("/{post_id}/spark")
def spark_post(post_id: str, body: dict = Body(default={}), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    db.add(UserFeedSpark(id=uuid.uuid4(), feed_id=pid, user_id=current_user.id, platform=body.get("platform", "link"), created_at=datetime.now(EAT)))
    db.commit()
    return standard_response(True, "Post shared")


# ──────────────────────────────────────────────
# Comments (Echoes) - Threaded
# ──────────────────────────────────────────────

@router.get("/{post_id}/comments")
def get_comments(
    post_id: str, page: int = 1, limit: int = 20,
    sort: str = "newest", parent_id: Optional[str] = None,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")

    query = db.query(UserFeedComment).filter(
        UserFeedComment.feed_id == pid,
        UserFeedComment.is_active == True,
    )

    # If parent_id is provided, get replies to that comment
    if parent_id:
        try:
            parent_uuid = uuid.UUID(parent_id)
        except ValueError:
            return standard_response(False, "Invalid parent comment ID")
        query = query.filter(UserFeedComment.parent_comment_id == parent_uuid)
    else:
        # Get only top-level comments (no parent)
        query = query.filter(UserFeedComment.parent_comment_id.is_(None))

    # Sorting
    if sort == "oldest":
        query = query.order_by(UserFeedComment.created_at.asc())
    elif sort == "popular":
        query = query.order_by(UserFeedComment.glow_count.desc(), UserFeedComment.created_at.desc())
    else:  # newest
        query = query.order_by(UserFeedComment.created_at.desc())

    from utils.batch_loaders import build_comment_dicts
    items, pagination = paginate(query, page, limit)
    data = build_comment_dicts(db, items, current_user.id)
    return standard_response(True, "Comments retrieved", {"comments": data, "pagination": pagination})


@router.get("/{post_id}/comments/{comment_id}/replies")
def get_comment_replies(
    post_id: str, comment_id: str, page: int = 1, limit: int = 20,
    db: Session = Depends(get_db), current_user: User = Depends(get_current_user),
):
    """Get all replies to a specific comment."""
    try:
        cid = uuid.UUID(comment_id)
    except ValueError:
        return standard_response(False, "Invalid comment ID")

    query = db.query(UserFeedComment).filter(
        UserFeedComment.parent_comment_id == cid,
        UserFeedComment.is_active == True,
    ).order_by(UserFeedComment.created_at.asc())

    from utils.batch_loaders import build_comment_dicts
    items, pagination = paginate(query, page, limit)
    data = build_comment_dicts(db, items, current_user.id, include_replies_preview=False)
    return standard_response(True, "Replies retrieved", {"comments": data, "pagination": pagination})


@router.post("/{post_id}/comments")
def create_comment(post_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    content = body.get("content", "").strip()
    if not content:
        return standard_response(False, "Comment content is required")

    now = datetime.now(EAT)
    comment = UserFeedComment(
        id=uuid.uuid4(), feed_id=pid, user_id=current_user.id,
        content=content, is_active=True, created_at=now, updated_at=now,
    )

    # Handle reply to another comment
    parent_id = body.get("parent_id")
    if parent_id:
        try:
            parent_uuid = uuid.UUID(parent_id)
            # Verify parent comment exists
            parent = db.query(UserFeedComment).filter(
                UserFeedComment.id == parent_uuid,
                UserFeedComment.is_active == True,
            ).first()
            if parent:
                comment.parent_comment_id = parent_uuid
                # Update parent reply count
                parent.reply_count = (parent.reply_count or 0) + 1
        except ValueError:
            pass

    db.add(comment)
    db.commit()
    return standard_response(True, "Comment posted", _comment_dict(db, comment, current_user.id, include_replies_preview=False))


@router.put("/{post_id}/comments/{comment_id}")
def update_comment(post_id: str, comment_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(comment_id)
    except ValueError:
        return standard_response(False, "Invalid comment ID")
    c = db.query(UserFeedComment).filter(UserFeedComment.id == cid, UserFeedComment.user_id == current_user.id).first()
    if not c:
        return standard_response(False, "Comment not found")
    if "content" in body:
        c.content = body["content"]
        c.is_edited = True
    c.updated_at = datetime.now(EAT)
    db.commit()
    return standard_response(True, "Comment updated", _comment_dict(db, c, current_user.id, include_replies_preview=False))


@router.delete("/{post_id}/comments/{comment_id}")
def delete_comment(post_id: str, comment_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(comment_id)
    except ValueError:
        return standard_response(False, "Invalid comment ID")
    c = db.query(UserFeedComment).filter(UserFeedComment.id == cid, UserFeedComment.user_id == current_user.id).first()
    if not c:
        return standard_response(False, "Comment not found")
    c.is_active = False
    # Cascade soft-delete all child replies recursively
    def soft_delete_children(parent_id):
        children = db.query(UserFeedComment).filter(
            UserFeedComment.parent_comment_id == parent_id,
            UserFeedComment.is_active == True,
        ).all()
        for child in children:
            child.is_active = False
            soft_delete_children(child.id)
    soft_delete_children(c.id)
    # Decrement parent reply count if this is a reply
    if c.parent_comment_id:
        parent = db.query(UserFeedComment).filter(UserFeedComment.id == c.parent_comment_id).first()
        if parent and parent.reply_count and parent.reply_count > 0:
            parent.reply_count -= 1
    db.commit()
    return standard_response(True, "Comment deleted")


@router.post("/{post_id}/comments/{comment_id}/glow")
def glow_comment(post_id: str, comment_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(comment_id)
    except ValueError:
        return standard_response(False, "Invalid comment ID")
    existing = db.query(UserFeedCommentGlow).filter(UserFeedCommentGlow.comment_id == cid, UserFeedCommentGlow.user_id == current_user.id).first()
    if not existing:
        db.add(UserFeedCommentGlow(id=uuid.uuid4(), comment_id=cid, user_id=current_user.id, created_at=datetime.now(EAT)))
        # Update cached glow count
        comment = db.query(UserFeedComment).filter(UserFeedComment.id == cid).first()
        if comment:
            comment.glow_count = (comment.glow_count or 0) + 1
        db.commit()
    return standard_response(True, "Comment glowed")


@router.delete("/{post_id}/comments/{comment_id}/glow")
def unglow_comment(post_id: str, comment_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(comment_id)
    except ValueError:
        return standard_response(False, "Invalid comment ID")
    g = db.query(UserFeedCommentGlow).filter(UserFeedCommentGlow.comment_id == cid, UserFeedCommentGlow.user_id == current_user.id).first()
    if g:
        db.delete(g)
        # Update cached glow count
        comment = db.query(UserFeedComment).filter(UserFeedComment.id == cid).first()
        if comment and comment.glow_count and comment.glow_count > 0:
            comment.glow_count -= 1
        db.commit()
    return standard_response(True, "Comment glow removed")


# Save/Pin/Report
@router.post("/{post_id}/save")
def save_post(post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    existing = db.query(UserFeedSaved).filter(UserFeedSaved.feed_id == pid, UserFeedSaved.user_id == current_user.id).first()
    if not existing:
        db.add(UserFeedSaved(id=uuid.uuid4(), feed_id=pid, user_id=current_user.id, created_at=datetime.now(EAT)))
        db.commit()
    return standard_response(True, "Post saved")

@router.delete("/{post_id}/save")
def unsave_post(post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    s = db.query(UserFeedSaved).filter(UserFeedSaved.feed_id == pid, UserFeedSaved.user_id == current_user.id).first()
    if s:
        db.delete(s)
        db.commit()
    return standard_response(True, "Post unsaved")

@router.post("/{post_id}/pin")
def pin_post(post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    existing = db.query(UserFeedPinned).filter(UserFeedPinned.feed_id == pid, UserFeedPinned.user_id == current_user.id).first()
    if not existing:
        db.add(UserFeedPinned(id=uuid.uuid4(), feed_id=pid, user_id=current_user.id, created_at=datetime.now(EAT)))
        db.commit()
    return standard_response(True, "Post pinned")

@router.delete("/{post_id}/pin")
def unpin_post(post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    p = db.query(UserFeedPinned).filter(UserFeedPinned.feed_id == pid, UserFeedPinned.user_id == current_user.id).first()
    if p:
        db.delete(p)
        db.commit()
    return standard_response(True, "Post unpinned")

@router.post("/{post_id}/report")
def report_post(post_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return standard_response(True, "Post reported. Our team will review it shortly.")


# ──────────────────────────────────────────────
# CONTENT APPEALS
# ──────────────────────────────────────────────

@router.post("/{post_id}/appeal")
def submit_post_appeal(
    post_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """User appeals the removal of their own post."""
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")

    post = db.query(UserFeed).filter(UserFeed.id == pid, UserFeed.user_id == current_user.id).first()
    if not post:
        return standard_response(False, "Post not found or not yours")
    if post.is_active:
        return standard_response(False, "Post is not removed — no appeal needed")

    reason = (body.get("reason") or "").strip()
    if not reason or len(reason) < 10:
        return standard_response(False, "Please provide a reason (at least 10 characters)")

    # Check for existing appeal
    existing = db.query(ContentAppeal).filter(
        ContentAppeal.user_id == current_user.id,
        ContentAppeal.content_id == pid,
        ContentAppeal.content_type == AppealContentTypeEnum.post,
    ).first()
    if existing:
        return standard_response(False, "You have already submitted an appeal for this post")

    appeal = ContentAppeal(
        id=uuid.uuid4(),
        user_id=current_user.id,
        content_id=pid,
        content_type=AppealContentTypeEnum.post,
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



# ──────────────────────────────────────────────
# FEED INTERACTION TRACKING
# ──────────────────────────────────────────────

@router.post("/feed/interactions")
def log_feed_interaction(
    data: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Log user interactions with feed content for ranking improvement.

    Request body:
    {
        "post_id": "uuid",
        "interaction_type": "view|dwell|glow|comment|echo|spark|save|click_image|click_profile|hide|report|expand",
        "dwell_time_ms": 5000,          // optional, for dwell events
        "session_id": "abc123",         // optional, groups interactions per session
        "device_type": "mobile"         // optional: mobile|desktop|tablet
    }

    Batch variant:
    {
        "interactions": [
            {"post_id": "uuid", "interaction_type": "view", "dwell_time_ms": 1200},
            {"post_id": "uuid", "interaction_type": "glow"}
        ],
        "session_id": "abc123",
        "device_type": "mobile"
    }
    """
    try:
        from services.feed_ranking import log_interaction

        # Support batch interactions
        interactions = data.get("interactions")
        if interactions and isinstance(interactions, list):
            session_id = data.get("session_id")
            device_type = data.get("device_type")
            logged = 0
            for item in interactions[:50]:  # Max 50 per batch
                try:
                    post_id = uuid.UUID(item.get("post_id", ""))
                except (ValueError, TypeError):
                    continue
                success = log_interaction(
                    db, current_user.id, post_id,
                    item.get("interaction_type", "view"),
                    item.get("dwell_time_ms"),
                    session_id, device_type,
                )
                if success:
                    logged += 1
            return standard_response(True, f"{logged} interactions logged")

        # Single interaction
        try:
            post_id = uuid.UUID(data.get("post_id", ""))
        except (ValueError, TypeError):
            return standard_response(False, "Invalid post_id")

        success = log_interaction(
            db, current_user.id, post_id,
            data.get("interaction_type", "view"),
            data.get("dwell_time_ms"),
            data.get("session_id"),
            data.get("device_type"),
        )

        if success:
            return standard_response(True, "Interaction logged")
        return standard_response(False, "Invalid interaction type")

    except Exception as e:
        import traceback
        traceback.print_exc()
        return standard_response(False, "Failed to log interaction")


@router.get("/feed/interests")
def get_user_interests(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Returns the current user's computed interest profile.
    Useful for transparency/debugging feed personalization.
    """
    from models.feed_ranking import UserInterestProfile
    profile = db.query(UserInterestProfile).filter(
        UserInterestProfile.user_id == current_user.id
    ).first()

    if not profile:
        from services.feed_ranking import DEFAULT_INTEREST_VECTOR
        return standard_response(True, "Default interests (no history)", {
            "interest_vector": DEFAULT_INTEREST_VECTOR,
            "engagement_stats": {},
            "is_default": True,
        })

    return standard_response(True, "Interest profile retrieved", {
        "interest_vector": profile.interest_vector,
        "engagement_stats": profile.engagement_stats,
        "last_computed_at": profile.last_computed_at.isoformat() if profile.last_computed_at else None,
        "is_default": False,
    })

