"""
Per-request perf context.

A contextvar holds the active PerfContext for the duration of one ASGI
request. SQLAlchemy event listeners, Redis wrappers, and Celery enqueue
helpers all check `current()` and update the context if it is set. When
nothing is set (worker code, scripts, tests) every helper becomes a no-op.

contextvars are async-safe — each request gets its own logical copy even
under concurrent FastAPI handlers, unlike the thread-id approach used by
the older QueryCountMiddleware.
"""

from __future__ import annotations

import time
import uuid
from contextvars import ContextVar
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class PerfContext:
    request_id: str
    method: str = ""
    path: str = ""               # raw URL path; route template filled by middleware
    route: str = ""              # FastAPI route template, e.g. /events/{event_id}
    status_code: int = 0
    started_at: float = field(default_factory=time.perf_counter)

    # DB
    db_query_count: int = 0
    db_total_ms: float = 0.0
    db_slowest_ms: float = 0.0
    db_slowest_sql: str = ""

    # Redis
    redis_ops: int = 0
    redis_total_ms: float = 0.0

    # Celery
    celery_tasks_enqueued: int = 0
    celery_enqueue_ms: float = 0.0

    # External (WhatsApp / SMS / email / storage / etc.)
    external_calls: int = 0
    external_ms: float = 0.0
    external_breakdown: dict = field(default_factory=dict)  # provider -> ms

    # Response
    response_bytes: int = 0

    # Optional tags
    user_id: Optional[str] = None
    event_id: Optional[str] = None

    def add_db(self, elapsed_ms: float, sql: str) -> None:
        self.db_query_count += 1
        self.db_total_ms += elapsed_ms
        if elapsed_ms > self.db_slowest_ms:
            self.db_slowest_ms = elapsed_ms
            self.db_slowest_sql = (sql or "")[:200]

    def add_redis(self, elapsed_ms: float) -> None:
        self.redis_ops += 1
        self.redis_total_ms += elapsed_ms

    def add_external(self, provider: str, elapsed_ms: float) -> None:
        self.external_calls += 1
        self.external_ms += elapsed_ms
        self.external_breakdown[provider] = (
            self.external_breakdown.get(provider, 0.0) + elapsed_ms
        )

    def add_celery_enqueue(self, elapsed_ms: float) -> None:
        self.celery_tasks_enqueued += 1
        self.celery_enqueue_ms += elapsed_ms


_current: ContextVar[Optional[PerfContext]] = ContextVar("nuru_perf_ctx", default=None)


def current() -> Optional[PerfContext]:
    """Return the active PerfContext or None."""
    return _current.get()


def set_current(ctx: Optional[PerfContext]):
    """Bind a PerfContext to the current async/thread context. Returns a token
    suitable for `reset_current(token)`."""
    return _current.set(ctx)


def reset_current(token) -> None:
    try:
        _current.reset(token)
    except Exception:
        # Cross-context reset can happen under certain ASGI middlewares; safe
        # to ignore because the request is finishing anyway.
        pass


def new_request_id() -> str:
    return uuid.uuid4().hex
