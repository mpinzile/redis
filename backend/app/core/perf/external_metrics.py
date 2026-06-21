"""
Context manager for outbound provider calls (WhatsApp, SMS, email, storage,
payment gateways). Adopt at call sites incrementally:

    from core.perf import timed_external
    with timed_external("whatsapp"):
        client.send_template(...)

A separate breakdown is kept per provider so the perf log shows which
upstream is dragging a request.
"""

from __future__ import annotations

import time
from contextlib import contextmanager

from .context import current


@contextmanager
def timed_external(provider: str):
    ctx = current()
    if ctx is None:
        yield
        return
    start = time.perf_counter()
    try:
        yield
    finally:
        ctx.add_external(provider, (time.perf_counter() - start) * 1000.0)
