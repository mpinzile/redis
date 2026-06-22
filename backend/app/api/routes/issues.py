# Issue Reporting Routes - /issues/...

import uuid
from datetime import datetime

import pytz
from fastapi import APIRouter, Depends, Body, Query
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import func as sa_func

from core.database import get_db
from models import Issue, IssueCategory, IssueResponse, User, Notification, IssueStatusEnum, IssuePriorityEnum, NotificationTypeEnum
from utils.auth import get_current_user
from utils.helpers import standard_response, paginate

EAT = pytz.timezone("Africa/Nairobi")
router = APIRouter(prefix="/issues", tags=["Issues"])


# ──────────────────────────────────────────────
# ISSUE CATEGORIES (public)
# ──────────────────────────────────────────────

@router.get("/categories")
def get_issue_categories(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    cats = db.query(IssueCategory).filter(IssueCategory.is_active == True).order_by(IssueCategory.display_order.asc(), IssueCategory.name.asc()).all()
    data = [{
        "id": str(c.id),
        "name": c.name,
        "description": c.description,
        "icon": c.icon,
        "display_order": c.display_order,
    } for c in cats]
    return standard_response(True, "Issue categories retrieved", data)


# ──────────────────────────────────────────────
# MY ISSUES
# ──────────────────────────────────────────────

@router.get("/")
def get_my_issues(
    page: int = 1, limit: int = 20,
    status: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Issue).options(
        joinedload(Issue.category)
    ).filter(Issue.user_id == current_user.id)

    if status:
        try:
            status_enum = IssueStatusEnum(status)
            query = query.filter(Issue.status == status_enum)
        except ValueError:
            pass

    query = query.order_by(Issue.created_at.desc(), Issue.id.desc())
    items, pagination = paginate(query, page, limit)

    # Single CASE-based aggregate replaces 4 separate COUNT queries.
    from sqlalchemy import case
    summary_row = db.query(
        sa_func.count(Issue.id).label("total"),
        sa_func.count(case((Issue.status == IssueStatusEnum.open, 1))).label("open"),
        sa_func.count(case((Issue.status == IssueStatusEnum.in_progress, 1))).label("in_progress"),
        sa_func.count(case((Issue.status == IssueStatusEnum.resolved, 1))).label("resolved"),
    ).filter(Issue.user_id == current_user.id).one()
    total = int(summary_row.total or 0)
    open_count = int(summary_row.open or 0)
    in_progress_count = int(summary_row.in_progress or 0)
    resolved_count = int(summary_row.resolved or 0)

    # Batch response counts and last-response timestamps for visible issues.
    issue_ids = [i.id for i in items]
    response_counts: dict = {}
    last_response_map: dict = {}
    if issue_ids:
        response_counts = {
            iid: int(cnt or 0) for iid, cnt in db.query(
                IssueResponse.issue_id, sa_func.count(IssueResponse.id),
            ).filter(IssueResponse.issue_id.in_(issue_ids))
            .group_by(IssueResponse.issue_id).all()
        }
        # Latest response per issue via a windowed/grouped approach: fetch the
        # max created_at per issue then look those rows up.
        latest_times = dict(
            db.query(IssueResponse.issue_id, sa_func.max(IssueResponse.created_at))
            .filter(IssueResponse.issue_id.in_(issue_ids))
            .group_by(IssueResponse.issue_id).all()
        )
        if latest_times:
            from sqlalchemy import tuple_, and_, or_
            conds = [and_(IssueResponse.issue_id == k, IssueResponse.created_at == v) for k, v in latest_times.items()]
            last_rows = db.query(IssueResponse).filter(or_(*conds)).all() if conds else []
            for r in last_rows:
                last_response_map.setdefault(r.issue_id, r)

    data = []
    for issue in items:
        last_response = last_response_map.get(issue.id)
        data.append({
            "id": str(issue.id),
            "subject": issue.subject,
            "description": issue.description,
            "status": issue.status.value if issue.status else "open",
            "priority": issue.priority.value if issue.priority else "medium",
            "category": {
                "id": str(issue.category.id),
                "name": issue.category.name,
                "icon": issue.category.icon,
            } if issue.category else None,
            "screenshot_urls": issue.screenshot_urls or [],
            "response_count": response_counts.get(issue.id, 0),
            "last_response_at": last_response.created_at.isoformat() if last_response else None,
            "last_response_is_admin": last_response.is_admin if last_response else False,
            "created_at": issue.created_at.isoformat() if issue.created_at else None,
            "updated_at": issue.updated_at.isoformat() if issue.updated_at else None,
        })

    return standard_response(True, "Issues retrieved", {
        "issues": data,
        "summary": {"total": total, "open": open_count, "in_progress": in_progress_count, "resolved": resolved_count},
    }, pagination=pagination)


# ──────────────────────────────────────────────
# SUBMIT ISSUE
# ──────────────────────────────────────────────

@router.post("/")
def create_issue(body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    category_id = (body.get("category_id") or "").strip()
    subject = (body.get("subject") or "").strip()
    description = (body.get("description") or "").strip()
    priority = (body.get("priority") or "medium").strip()
    screenshot_urls = body.get("screenshot_urls") or []

    if not category_id:
        return standard_response(False, "Issue category is required")
    if not subject:
        return standard_response(False, "Subject is required")
    if len(subject) > 200:
        return standard_response(False, "Subject must be less than 200 characters")
    if not description:
        return standard_response(False, "Description is required")
    if len(description) > 5000:
        return standard_response(False, "Description must be less than 5000 characters")

    try:
        cat_uuid = uuid.UUID(category_id)
    except ValueError:
        return standard_response(False, "Invalid category ID")

    cat = db.query(IssueCategory).filter(IssueCategory.id == cat_uuid, IssueCategory.is_active == True).first()
    if not cat:
        return standard_response(False, "Invalid issue category")

    try:
        priority_enum = IssuePriorityEnum(priority)
    except ValueError:
        priority_enum = IssuePriorityEnum.medium

    now = datetime.now(EAT)
    issue = Issue(
        id=uuid.uuid4(),
        user_id=current_user.id,
        category_id=cat_uuid,
        subject=subject,
        description=description,
        status=IssueStatusEnum.open,
        priority=priority_enum,
        screenshot_urls=screenshot_urls,
        created_at=now,
        updated_at=now,
    )
    db.add(issue)
    db.commit()

    return standard_response(True, "Issue submitted successfully", {
        "id": str(issue.id),
        "subject": issue.subject,
        "status": issue.status.value,
    })


# ──────────────────────────────────────────────
# ISSUE DETAIL
# ──────────────────────────────────────────────

@router.get("/{issue_id}")
def get_issue_detail(issue_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        iid = uuid.UUID(issue_id)
    except ValueError:
        return standard_response(False, "Invalid issue ID")

    issue = db.query(Issue).options(
        joinedload(Issue.category),
        joinedload(Issue.responses),
    ).filter(Issue.id == iid, Issue.user_id == current_user.id).first()
    if not issue:
        return standard_response(False, "Issue not found")

    responses = [{
        "id": str(r.id),
        "message": r.message,
        "is_admin": r.is_admin,
        "admin_name": r.admin_name,
        "attachments": r.attachments or [],
        "created_at": r.created_at.isoformat() if r.created_at else None,
    } for r in (issue.responses or [])]

    return standard_response(True, "Issue retrieved", {
        "id": str(issue.id),
        "subject": issue.subject,
        "description": issue.description,
        "status": issue.status.value if issue.status else "open",
        "priority": issue.priority.value if issue.priority else "medium",
        "category": {
            "id": str(issue.category.id),
            "name": issue.category.name,
            "icon": issue.category.icon,
        } if issue.category else None,
        "screenshot_urls": issue.screenshot_urls or [],
        "responses": responses,
        "created_at": issue.created_at.isoformat() if issue.created_at else None,
        "updated_at": issue.updated_at.isoformat() if issue.updated_at else None,
    })


# ──────────────────────────────────────────────
# REPLY TO ISSUE (user reply)
# ──────────────────────────────────────────────

@router.post("/{issue_id}/reply")
def reply_to_issue(issue_id: str, body: dict = Body(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        iid = uuid.UUID(issue_id)
    except ValueError:
        return standard_response(False, "Invalid issue ID")

    issue = db.query(Issue).filter(Issue.id == iid, Issue.user_id == current_user.id).first()
    if not issue:
        return standard_response(False, "Issue not found")
    if issue.status == IssueStatusEnum.closed:
        return standard_response(False, "This issue is closed. Please open a new one.")

    message = (body.get("message") or "").strip()
    if not message:
        return standard_response(False, "Message is required")
    if len(message) > 5000:
        return standard_response(False, "Message must be less than 5000 characters")

    now = datetime.now(EAT)
    response = IssueResponse(
        id=uuid.uuid4(),
        issue_id=iid,
        responder_id=current_user.id,
        is_admin=False,
        message=message,
        created_at=now,
    )
    db.add(response)

    # If resolved, reopen it
    if issue.status == IssueStatusEnum.resolved:
        issue.status = IssueStatusEnum.open
    issue.updated_at = now
    db.commit()

    return standard_response(True, "Reply sent", {"id": str(response.id)})


# ──────────────────────────────────────────────
# CLOSE ISSUE (by user)
# ──────────────────────────────────────────────

@router.put("/{issue_id}/close")
def close_issue(issue_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        iid = uuid.UUID(issue_id)
    except ValueError:
        return standard_response(False, "Invalid issue ID")

    issue = db.query(Issue).filter(Issue.id == iid, Issue.user_id == current_user.id).first()
    if not issue:
        return standard_response(False, "Issue not found")

    issue.status = IssueStatusEnum.closed
    issue.updated_at = datetime.now(EAT)
    db.commit()
    return standard_response(True, "Issue closed")
