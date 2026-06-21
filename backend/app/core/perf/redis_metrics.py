"""
Tiny context manager so Redis call sites can opt into per-request timing
without forcing a full client wrapper today.

Usage:
    from core.perf import timed_redis
    with timed_redis():
        r.get(key)

When no PerfContext is active it is a near-zero-overhead no-op.
"""

from __future__ import annotations

import time
from contextlib import contextmanager

from .context import current


@contextmanager
def timed_redis():
    ctx = current()
    if ctx is None:
        yield
        return
    start = time.perf_counter()
    try:
        yield
    finally:
        ctx.add_redis((time.perf_counter() - start) * 1000.0)
