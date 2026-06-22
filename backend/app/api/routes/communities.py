# Communities Routes - /communities/...
# Manages community groups

import os
import uuid
from datetime import datetime
from typing import List, Optional

import httpx
import pytz
from fastapi import APIRouter, Depends, Body, File, Form, UploadFile
from sqlalchemy.orm import Session
from sqlalchemy import func as sa_func

from core.database import get_db
from models import Community, CommunityMember, CommunityPost, CommunityPostImage, CommunityPostGlow, CommunityPostComment, CommunityPostSave, CommunityPostShare, CommunityMute, User, UserProfile, UserFeed, UserFeedImage
from utils.auth import get_current_user
from utils.helpers import standard_response, paginate

EAT = pytz.timezone("Africa/Nairobi")
router = APIRouter(prefix="/communities", tags=["Communities"])


def _community_dict(db, c, current_user_id=None):
    is_member = False
    is_creator = str(c.created_by) == str(current_user_id) if c.created_by and current_user_id else False
    if current_user_id:
        is_member = db.query(CommunityMember).filter(
            CommunityMember.community_id == c.id,
            CommunityMember.user_id == current_user_id
        ).first() is not None

    return {
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
        "is_creator": is_creator or is_member,  # creators are always members
        "is_member": is_member or is_creator,
        "created_at": c.created_at.isoformat() if c.created_at else None,
    }


@router.get("/")
def get_communities(page: int = 1, limit: int = 20, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    from utils.batch_loaders import build_community_dicts
    query = db.query(Community).order_by(Community.created_at.desc())
    items, pagination = paginate(query, page, limit)
    data = build_community_dicts(db, items, current_user.id)
    return standard_response(True, "Communities retrieved", data, pagination=pagination)


@router.get("/my")
def get_my_communities(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    from utils.batch_loaders import build_community_dicts
    from sqlalchemy import or_
    # Single round-trip: communities the user created OR is a member of.
    member_ids_subq = db.query(CommunityMember.community_id).filter(
        CommunityMember.user_id == current_user.id
    ).subquery()
    communities = (
        db.query(Community)
        .filter(or_(Community.created_by == current_user.id, Community.id.in_(member_ids_subq)))
        .order_by(Community.created_at.desc())
        .all()
    )
    data = build_community_dicts(db, communities, current_user.id)
    return standard_response(True, "My communities retrieved", data)


@router.get("/recommended")
def get_recommended_communities(
    page: int = 1,
    limit: int = 20,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return communities the user is NOT already in, ranked by relevance.

    Ranking favours:
      • category matches against the user's onboarding interests
      • verified communities
      • member count (popularity)
    """
    from utils.batch_loaders import build_community_dicts

    # 1. Communities to exclude — the user already belongs to or created.
    member_rows = db.query(CommunityMember.community_id).filter(
        CommunityMember.user_id == current_user.id
    ).all()
    member_ids = {row[0] for row in member_rows}
    created_rows = db.query(Community.id).filter(Community.created_by == current_user.id).all()
    member_ids.update(row[0] for row in created_rows)

    # 2. Pull the user's interests for category-based boosting.
    profile = db.query(UserProfile).filter(UserProfile.user_id == current_user.id).first()
    interests = set()
    if profile and isinstance(profile.interests, list):
        interests = {str(s).strip().lower() for s in profile.interests if s}

    # 3. Candidate set — public communities the user is not already in.
    #    Push ranking and pagination into SQL: a candidate cap keeps memory
    #    bounded even on very large communities tables, and an interest match
    #    boost is computed via a CASE expression so the DB can ORDER BY it.
    from sqlalchemy import case as sa_case, func as sa_func, desc

    q = db.query(Community).filter(Community.is_public.is_(True))
    if member_ids:
        q = q.filter(~Community.id.in_(member_ids))

    # Interest-match boost — 1 when the community category matches any
    # onboarding interest (lower-cased exact match), 0 otherwise. Substring
    # matching is still applied as a Python re-rank below for the visible
    # page only (cheap because it's at most `safe_limit` rows).
    if interests:
        interest_boost = sa_case(
            (sa_func.lower(sa_func.coalesce(Community.category, "")).in_(list(interests)), 1),
            else_=0,
        )
    else:
        interest_boost = sa_case(else_=0)

    verified_boost = sa_case((Community.is_verified.is_(True), 1), else_=0)

    safe_limit = max(1, min(limit, 50))
    safe_page = max(1, page)
    offset = (safe_page - 1) * safe_limit

    # Use a fast count() on the filtered query for accurate pagination.
    total = q.count()

    page_items = (
        q.order_by(
            desc(interest_boost),
            desc(verified_boost),
            Community.member_count.desc(),
            Community.created_at.desc(),
        )
        .offset(offset)
        .limit(safe_limit)
        .all()
    )

    pagination = {
        "page": safe_page,
        "limit": safe_limit,
        "total": total,
        "pages": (total + safe_limit - 1) // safe_limit if total else 0,
    }
    data = build_community_dicts(db, page_items, current_user.id)
    return standard_response(True, "Recommended communities", data, pagination=pagination)


@router.post("/")
async def create_community(
    name: str = Form(...),
    description: Optional[str] = Form(None),
    tagline: Optional[str] = Form(None),
    category: Optional[str] = Form(None),
    is_public: Optional[bool] = Form(True),
    cover_image: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    name = name.strip()
    if not name:
        return standard_response(False, "Community name is required")

    now = datetime.now(EAT)
    cover_image_url = None

    # Upload cover image if provided
    if cover_image and cover_image.filename and cover_image.size and cover_image.size > 0:
        from core.config import UPLOAD_SERVICE_URL
        file_content = await cover_image.read()
        _, ext = os.path.splitext(cover_image.filename)
        unique_name = f"{uuid.uuid4().hex}{ext}"
        async with httpx.AsyncClient() as client:
            try:
                resp = await client.post(UPLOAD_SERVICE_URL, data={"target_path": "nuru/uploads/communities/covers/"}, files={"file": (unique_name, file_content, cover_image.content_type)}, timeout=20)
                result = resp.json()
                if result.get("success"):
                    cover_image_url = result["data"]["url"]
            except Exception:
                pass

    community = Community(
        id=uuid.uuid4(),
        name=name,
        description=description.strip() if description else None,
        tagline=tagline.strip() if tagline else None,
        category=category.strip() if category else None,
        cover_image_url=cover_image_url,
        is_public=is_public if is_public is not None else True,
        member_count=1,
        created_by=current_user.id,
        created_at=now,
        updated_at=now,
    )
    db.add(community)

    # Add creator as member with admin role
    membership = CommunityMember(
        id=uuid.uuid4(),
        community_id=community.id,
        user_id=current_user.id,
        role="admin",
        joined_at=now,
    )
    db.add(membership)
    db.commit()
    db.refresh(community)

    return standard_response(True, "Community created", _community_dict(db, community, current_user.id))


@router.get("/{community_id}")
def get_community(community_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid community ID")

    c = db.query(Community).filter(Community.id == cid).first()
    if not c:
        return standard_response(False, "Community not found")

    return standard_response(True, "Community retrieved", {**_community_dict(db, c, current_user.id), "created_by": str(c.created_by) if c.created_by else None})


@router.put("/{community_id}/cover")
async def update_community_cover(
    community_id: str,
    cover_image: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update community cover image (admin only)."""
    try:
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid community ID")

    c = db.query(Community).filter(Community.id == cid).first()
    if not c:
        return standard_response(False, "Community not found")

    # Check admin
    member = db.query(CommunityMember).filter(
        CommunityMember.community_id == cid,
        CommunityMember.user_id == current_user.id,
        CommunityMember.role == "admin"
    ).first()
    if not member and str(c.created_by) != str(current_user.id):
        return standard_response(False, "Only admins can update the cover image")

    from core.config import UPLOAD_SERVICE_URL
    from utils.helpers import delete_storage_file
    old_cover_url = c.cover_image_url  # capture before replacement
    file_content = await cover_image.read()
    _, ext = os.path.splitext(cover_image.filename)
    unique_name = f"{uuid.uuid4().hex}{ext}"
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(UPLOAD_SERVICE_URL, data={"target_path": "nuru/uploads/communities/covers/"}, files={"file": (unique_name, file_content, cover_image.content_type)}, timeout=20)
            result = resp.json()
            if result.get("success"):
                c.cover_image_url = result["data"]["url"]
                c.updated_at = datetime.now(EAT)
                db.commit()
                # Unlink old cover image (best-effort)
                if old_cover_url:
                    await delete_storage_file(old_cover_url)
                return standard_response(True, "Cover image updated", {"image": c.cover_image_url})
        except Exception:
            pass

    return standard_response(False, "Failed to upload cover image")


@router.post("/{community_id}/join")
def join_community(community_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid community ID")

    c = db.query(Community).filter(Community.id == cid).first()
    if not c:
        return standard_response(False, "Community not found")

    existing = db.query(CommunityMember).filter(
        CommunityMember.community_id == cid,
        CommunityMember.user_id == current_user.id
    ).first()
    if existing:
        return standard_response(False, "Already a member")

    membership = CommunityMember(
        id=uuid.uuid4(),
        community_id=cid,
        user_id=current_user.id,
        role="member",
        joined_at=datetime.now(EAT),
    )
    db.add(membership)
    c.member_count = (c.member_count or 0) + 1
    db.commit()

    return standard_response(True, "Joined community", {"joined": True, "member_count": c.member_count})


@router.post("/{community_id}/leave")
def leave_community(community_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid community ID")

    c = db.query(Community).filter(Community.id == cid).first()
    if not c:
        return standard_response(False, "Community not found")

    if str(c.created_by) == str(current_user.id):
        return standard_response(False, "Creator cannot leave the community")

    membership = db.query(CommunityMember).filter(
        CommunityMember.community_id == cid,
        CommunityMember.user_id == current_user.id
    ).first()
    if not membership:
        return standard_response(False, "Not a member")

    db.delete(membership)
    c.member_count = max((c.member_count or 1) - 1, 0)
    db.commit()

    return standard_response(True, "Left community", {"left": True, "member_count": c.member_count})


@router.get("/{community_id}/members")
def get_community_members(community_id: str, page: int = 1, limit: int = 20, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid community ID")

    from utils.batch_loaders import build_community_member_dicts
    query = db.query(CommunityMember).filter(CommunityMember.community_id == cid).order_by(CommunityMember.joined_at.desc())
    items, pagination = paginate(query, page, limit)
    members = build_community_member_dicts(db, items)

    return standard_response(True, "Members retrieved", {"members": members}, pagination=pagination, wrap_items=False)


@router.post("/{community_id}/members")
def add_community_member(community_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Creator adds a member to the community."""
    try:
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid community ID")

    c = db.query(Community).filter(Community.id == cid).first()
    if not c:
        return standard_response(False, "Community not found")

    if str(c.created_by) != str(current_user.id):
        return standard_response(False, "Only the community creator can add members")

    user_id = body.get("user_id")
    if not user_id:
        return standard_response(False, "user_id is required")

    try:
        uid = uuid.UUID(user_id)
    except ValueError:
        return standard_response(False, "Invalid user ID")

    existing = db.query(CommunityMember).filter(
        CommunityMember.community_id == cid,
        CommunityMember.user_id == uid
    ).first()
    if existing:
        return standard_response(False, "User is already a member")

    membership = CommunityMember(
        id=uuid.uuid4(),
        community_id=cid,
        user_id=uid,
        role="member",
        joined_at=datetime.now(EAT),
    )
    db.add(membership)
    c.member_count = (c.member_count or 0) + 1
    db.commit()

    return standard_response(True, "Member added", {"member_count": c.member_count})


@router.delete("/{community_id}/members/{user_id}")
def remove_community_member(community_id: str, user_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Creator removes a member from the community."""
    try:
        cid = uuid.UUID(community_id)
        uid = uuid.UUID(user_id)
    except ValueError:
        return standard_response(False, "Invalid ID")

    c = db.query(Community).filter(Community.id == cid).first()
    if not c:
        return standard_response(False, "Community not found")

    if str(c.created_by) != str(current_user.id):
        return standard_response(False, "Only the community creator can remove members")

    if str(uid) == str(current_user.id):
        return standard_response(False, "Cannot remove yourself")

    membership = db.query(CommunityMember).filter(
        CommunityMember.community_id == cid,
        CommunityMember.user_id == uid
    ).first()
    if not membership:
        return standard_response(False, "User is not a member")

    db.delete(membership)
    c.member_count = max((c.member_count or 1) - 1, 0)
    db.commit()

    return standard_response(True, "Member removed", {"member_count": c.member_count})


@router.get("/{community_id}/posts")
def get_community_posts(community_id: str, page: int = 1, limit: int = 20, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Get community posts created by the community creator."""
    try:
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid community ID")

    c = db.query(Community).filter(Community.id == cid).first()
    if not c:
        return standard_response(False, "Community not found")

    query = db.query(CommunityPost).filter(
        CommunityPost.community_id == cid,
    ).order_by(CommunityPost.created_at.desc())

    items, pagination_data = paginate(query, page, limit)

    from utils.batch_loaders import build_community_post_dicts
    posts = build_community_post_dicts(db, items, current_user.id if current_user else None)

    return standard_response(True, "Community posts retrieved", {"posts": posts}, pagination=pagination_data, wrap_items=False)


@router.post("/{community_id}/posts")
async def create_community_post(
    community_id: str,
    content: Optional[str] = Form(None),
    images: Optional[List[UploadFile]] = File(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Community members can post content."""
    try:
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid community ID")

    c = db.query(Community).filter(Community.id == cid).first()
    if not c:
        return standard_response(False, "Community not found")

    is_creator = str(c.created_by) == str(current_user.id)
    is_member = db.query(CommunityMember).filter(
        CommunityMember.community_id == cid,
        CommunityMember.user_id == current_user.id,
    ).first() is not None
    if not (is_creator or is_member):
        return standard_response(False, "Only community members can post")

    # Filter out empty file entries
    valid_images = []
    if images:
        for f in images:
            if f and f.filename and f.size and f.size > 0:
                valid_images.append(f)

    if not content and not valid_images:
        return standard_response(False, "Content or images are required")

    now = datetime.now(EAT)
    cp = CommunityPost(
        id=uuid.uuid4(),
        community_id=cid,
        author_id=current_user.id,
        content=content.strip() if content else None,
        created_at=now,
        updated_at=now,
    )
    db.add(cp)
    db.flush()

    if valid_images:
        from core.config import UPLOAD_SERVICE_URL
        for file in valid_images:
            file_content = await file.read()
            _, ext = os.path.splitext(file.filename)
            unique_name = f"{uuid.uuid4().hex}{ext}"
            async with httpx.AsyncClient() as client:
                try:
                    resp = await client.post(UPLOAD_SERVICE_URL, data={"target_path": f"nuru/uploads/communities/{cid}/"}, files={"file": (unique_name, file_content, file.content_type)}, timeout=20)
                    result = resp.json()
                    if result.get("success"):
                        db.add(CommunityPostImage(id=uuid.uuid4(), post_id=cp.id, image_url=result["data"]["url"], created_at=now))
                except Exception:
                    pass

    db.commit()
    return standard_response(True, "Post created", {"id": str(cp.id)})


@router.post("/{community_id}/posts/{post_id}/glow")
def glow_community_post(community_id: str, post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")

    existing = db.query(CommunityPostGlow).filter(
        CommunityPostGlow.post_id == pid,
        CommunityPostGlow.user_id == current_user.id
    ).first()
    if existing:
        return standard_response(True, "Already glowed")

    db.add(CommunityPostGlow(id=uuid.uuid4(), post_id=pid, user_id=current_user.id, created_at=datetime.now(EAT)))
    db.commit()
    return standard_response(True, "Post glowed")


@router.delete("/{community_id}/posts/{post_id}/glow")
def unglow_community_post(community_id: str, post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")

    g = db.query(CommunityPostGlow).filter(
        CommunityPostGlow.post_id == pid,
        CommunityPostGlow.user_id == current_user.id
    ).first()
    if g:
        db.delete(g)
        db.commit()
    return standard_response(True, "Glow removed")


# ─────────────────────────────────────────────────────────
# Edit / delete community post
# ─────────────────────────────────────────────────────────

@router.put("/{community_id}/posts/{post_id}")
def update_community_post(community_id: str, post_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    cp = db.query(CommunityPost).filter(CommunityPost.id == pid).first()
    if not cp:
        return standard_response(False, "Post not found")
    if str(cp.author_id) != str(current_user.id):
        return standard_response(False, "Not allowed")
    new_content = (body.get("content") or "").strip()
    if not new_content:
        return standard_response(False, "Content is required")
    cp.content = new_content
    cp.edited_at = datetime.now(EAT)
    cp.updated_at = datetime.now(EAT)
    db.commit()
    return standard_response(True, "Post updated", {"id": str(cp.id), "content": cp.content})


@router.delete("/{community_id}/posts/{post_id}")
def delete_community_post(community_id: str, post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid ID")
    cp = db.query(CommunityPost).filter(CommunityPost.id == pid).first()
    if not cp:
        return standard_response(False, "Post not found")
    c = db.query(Community).filter(Community.id == cid).first()
    is_admin = c and str(c.created_by) == str(current_user.id)
    if str(cp.author_id) != str(current_user.id) and not is_admin:
        return standard_response(False, "Not allowed")
    db.delete(cp)
    db.commit()
    return standard_response(True, "Post deleted")


# ─────────────────────────────────────────────────────────
# Comments
# ─────────────────────────────────────────────────────────

def _comment_dict(c, user_map, profile_map):
    u = user_map.get(c.user_id)
    p = profile_map.get(c.user_id) if u else None
    return {
        "id": str(c.id),
        "content": c.content,
        "parent_id": str(c.parent_id) if c.parent_id else None,
        "created_at": c.created_at.isoformat() if c.created_at else None,
        "user": {
            "id": str(u.id) if u else None,
            "name": (f"{u.first_name or ''} {u.last_name or ''}").strip() if u else None,
            "first_name": u.first_name if u else None,
            "last_name": u.last_name if u else None,
            "avatar": p.profile_picture_url if p else None,
            "is_verified": bool(getattr(u, "is_identity_verified", False)) if u else False,
        },
    }


@router.get("/{community_id}/posts/{post_id}/comments")
def list_community_post_comments(community_id: str, post_id: str, page: int = 1, limit: int = 50, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    query = db.query(CommunityPostComment).filter(CommunityPostComment.post_id == pid).order_by(CommunityPostComment.created_at.asc())
    items, pagination = paginate(query, page, limit)
    user_ids = list({i.user_id for i in items})
    users = db.query(User).filter(User.id.in_(user_ids)).all() if user_ids else []
    user_map = {u.id: u for u in users}
    profiles = db.query(UserProfile).filter(UserProfile.user_id.in_(user_ids)).all() if user_ids else []
    profile_map = {p.user_id: p for p in profiles}
    data = [_comment_dict(c, user_map, profile_map) for c in items]
    return standard_response(True, "Comments retrieved", {"comments": data}, pagination=pagination, wrap_items=False)


@router.post("/{community_id}/posts/{post_id}/comments")
def add_community_post_comment(community_id: str, post_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid ID")
    content = (body.get("content") or "").strip()
    if not content:
        return standard_response(False, "Content is required")
    is_member = db.query(CommunityMember).filter(
        CommunityMember.community_id == cid, CommunityMember.user_id == current_user.id
    ).first() is not None
    c = db.query(Community).filter(Community.id == cid).first()
    if not c:
        return standard_response(False, "Community not found")
    if not (is_member or str(c.created_by) == str(current_user.id)):
        return standard_response(False, "Join the community to comment")
    parent_id_raw = body.get("parent_id")
    parent_uuid = None
    if parent_id_raw:
        try:
            parent_uuid = uuid.UUID(parent_id_raw)
        except ValueError:
            parent_uuid = None
    comment = CommunityPostComment(
        id=uuid.uuid4(), post_id=pid, user_id=current_user.id, content=content,
        parent_id=parent_uuid, created_at=datetime.now(EAT), updated_at=datetime.now(EAT),
    )
    db.add(comment)
    db.commit()
    db.refresh(comment)
    user_map = {current_user.id: current_user}
    p = db.query(UserProfile).filter(UserProfile.user_id == current_user.id).first()
    profile_map = {current_user.id: p} if p else {}
    return standard_response(True, "Comment added", _comment_dict(comment, user_map, profile_map))


@router.delete("/{community_id}/posts/{post_id}/comments/{comment_id}")
def delete_community_post_comment(community_id: str, post_id: str, comment_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cmid = uuid.UUID(comment_id)
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid ID")
    cm = db.query(CommunityPostComment).filter(CommunityPostComment.id == cmid).first()
    if not cm:
        return standard_response(False, "Comment not found")
    c = db.query(Community).filter(Community.id == cid).first()
    is_admin = c and str(c.created_by) == str(current_user.id)
    if str(cm.user_id) != str(current_user.id) and not is_admin:
        return standard_response(False, "Not allowed")
    db.delete(cm)
    db.commit()
    return standard_response(True, "Comment deleted")


# ─────────────────────────────────────────────────────────
# Save / Share / Mute
# ─────────────────────────────────────────────────────────

@router.post("/{community_id}/posts/{post_id}/save")
def save_community_post(community_id: str, post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    existing = db.query(CommunityPostSave).filter(CommunityPostSave.post_id == pid, CommunityPostSave.user_id == current_user.id).first()
    if existing:
        return standard_response(True, "Already saved")
    db.add(CommunityPostSave(id=uuid.uuid4(), post_id=pid, user_id=current_user.id, created_at=datetime.now(EAT)))
    db.commit()
    return standard_response(True, "Saved")


@router.delete("/{community_id}/posts/{post_id}/save")
def unsave_community_post(community_id: str, post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    s = db.query(CommunityPostSave).filter(CommunityPostSave.post_id == pid, CommunityPostSave.user_id == current_user.id).first()
    if s:
        db.delete(s)
        db.commit()
    return standard_response(True, "Unsaved")


@router.post("/{community_id}/posts/{post_id}/share")
def share_community_post(community_id: str, post_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        pid = uuid.UUID(post_id)
    except ValueError:
        return standard_response(False, "Invalid post ID")
    db.add(CommunityPostShare(id=uuid.uuid4(), post_id=pid, user_id=current_user.id, created_at=datetime.now(EAT)))
    db.commit()
    cnt = db.query(sa_func.count(CommunityPostShare.id)).filter(CommunityPostShare.post_id == pid).scalar() or 0
    return standard_response(True, "Shared", {"share_count": int(cnt)})


@router.post("/{community_id}/mute")
def mute_community(community_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        cid = uuid.UUID(community_id)
    except ValueError:
        return standard_response(False, "Invalid community ID")
    existing = db.query(CommunityMute).filter(CommunityMute.community_id == cid, CommunityMute.user_id == current_user.id).first()
    if existing:
        db.delete(existing)
        db.commit()
        return standard_response(True, "Unmuted", {"muted": False})
    db.add(CommunityMute(id=uuid.uuid4(), community_id=cid, user_id=current_user.id, created_at=datetime.now(EAT)))
    db.commit()
    return standard_response(True, "Muted", {"muted": True})
