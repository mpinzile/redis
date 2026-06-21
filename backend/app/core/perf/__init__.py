"""
Nuru performance instrumentation.

Stage 1 of the performance program: measure first, change later.

Exposes:
- PerfMiddleware: per-request JSON perf line with timings + counters.
- timed_redis: context manager for Redis ops to feed counters.
- timed_external: context manager for outbound calls (WhatsApp/SMS/email/storage).
- timed_enqueue: helper around Celery .delay/.apply_async to capture broker time.

All helpers are *no-ops* when no request context is active, so they are safe
to use from Celery workers, scripts, or tests without polluting logs.
"""

from .context import (
    PerfContext,
    current as current_perf,
    new_request_id,
)
from .redis_metrics import timed_redis
from .external_metrics import timed_external
from .celery_metrics import timed_enqueue
from .middleware import PerfMiddleware

__all__ = [
    "PerfContext",
    "PerfMiddleware",
    "current_perf",
    "new_request_id",
    "timed_redis",
    "timed_external",
    "timed_enqueue",
]
