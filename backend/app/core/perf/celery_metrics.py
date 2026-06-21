"""
Helper around Celery .delay / .apply_async that records broker round-trip
time on the active PerfContext. Drop-in replacement for `task.delay(...)`:

    from core.perf import timed_enqueue
    timed_enqueue(send_invitation_card_task, guest_id)

For .apply_async, pass kwargs explicitly:

    timed_enqueue(send_invitation_card_task, args=(guest_id,), countdown=5)
"""

from __future__ import annotations

import time
from typing import Any

from .context import current


def timed_enqueue(task: Any, *args, **kwargs):
    ctx = current()
    start = time.perf_counter()
    try:
        if args and not kwargs.get("args") and not kwargs.get("kwargs"):
            # Treat as task.delay(*args) — most common form.
            result = task.delay(*args)
        else:
            result = task.apply_async(**kwargs) if kwargs else task.apply_async()
        return result
    finally:
        if ctx is not None:
            ctx.add_celery_enqueue((time.perf_counter() - start) * 1000.0)
