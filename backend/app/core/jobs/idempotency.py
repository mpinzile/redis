"""Idempotency-key helpers.

Usage from a FastAPI handler:

    cached = lookup_idempotent(db, scope="rsvp.update", key=hdr, user_id=uid)
    if cached and cached["status"] == "completed":
        return cached["response_body"]
    job_id = begin_idempotent(db, scope="rsvp.update", key=hdr, user_id=uid)
    # ... do (or queue) the work ...
    finish_idempotent(db, scope="rsvp.update", key=hdr, response_code=200, body=resp, job_id=job_id)
    return resp

The unique ``(scope, key)`` index serialises concurrent replays: the
second call gets an IntegrityError on insert, which we catch and turn
into a "wait for the in-progress one" answer (caller's choice).

Rows expire after 24h by default; a periodic Celery maintenance task can
``DELETE FROM idempotency_keys WHERE expires_at < NOW()``.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Optional

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

log = logging.getLogger("jobs.idempotency")


def lookup_idempotent(db: Session, *, scope: str, key: str, user_id: Optional[str] = None) -> Optional[dict]:
    row = db.execute(
        text(
            """
            SELECT id, status, response_code, response_body, job_id, created_at, expires_at
              FROM idempotency_keys
             WHERE scope = :scope AND key = :key
               AND (user_id IS NULL OR user_id = :user_id OR :user_id IS NULL)
               AND expires_at > NOW()
             LIMIT 1
            """
        ),
        {"scope": scope, "key": key, "user_id": user_id},
    ).mappings().first()
    return dict(row) if row else None


def begin_idempotent(
    db: Session,
    *,
    scope: str,
    key: str,
    user_id: Optional[str] = None,
    request_hash: Optional[str] = None,
    job_id: Optional[str] = None,
    ttl_hours: int = 24,
) -> bool:
    """Reserve the ``(scope, key)``. Returns True if we own it, False if a
    concurrent request already started it."""
    try:
        db.execute(
            text(
                """
                INSERT INTO idempotency_keys
                    (scope, key, user_id, request_hash, job_id, status, expires_at)
                VALUES
                    (:scope, :key, :user_id, :request_hash, :job_id, 'in_progress',
                     NOW() + (:ttl || ' hours')::interval)
                """
            ),
            {
                "scope": scope,
                "key": key,
                "user_id": user_id,
                "request_hash": request_hash,
                "job_id": job_id,
                "ttl": ttl_hours,
            },
        )
        return True
    except IntegrityError:
        db.rollback()
        return False


def finish_idempotent(
    db: Session,
    *,
    scope: str,
    key: str,
    response_code: int,
    body: Any,
    job_id: Optional[str] = None,
    failed: bool = False,
) -> None:
    db.execute(
        text(
            """
            UPDATE idempotency_keys
               SET status = :status,
                   response_code = :code,
                   response_body = CAST(:body AS jsonb),
                   job_id = COALESCE(:job_id, job_id),
                   updated_at = NOW()
             WHERE scope = :scope AND key = :key
            """
        ),
        {
            "status": "failed" if failed else "completed",
            "code": response_code,
            "body": json.dumps(body) if body is not None else None,
            "job_id": job_id,
            "scope": scope,
            "key": key,
        },
    )
