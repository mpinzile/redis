"""
SQLAlchemy event listeners that feed per-request DB counters.

These listeners are always safe to register: when no PerfContext is bound
to the current async/thread context (Celery worker, script, test) they are
a no-op. We install them lazily from PerfMiddleware so importing the perf
package alone does not touch the engine.
"""

from __future__ import annotations

import time
import threading
from sqlalchemy import event

from .context import current

_installed = False
_lock = threading.Lock()


def install() -> None:
    """Register before/after cursor execute listeners exactly once."""
    global _installed
    with _lock:
        if _installed:
            return
        try:
            from core.database import engine  # local import to avoid cycles
        except Exception:
            return

        @event.listens_for(engine, "before_cursor_execute")
        def _before(conn, cursor, statement, parameters, context, executemany):
            ctx = current()
            if ctx is None:
                return
            conn.info["_nuru_perf_start"] = time.perf_counter()

        @event.listens_for(engine, "after_cursor_execute")
        def _after(conn, cursor, statement, parameters, context, executemany):
            ctx = current()
            if ctx is None:
                return
            start = conn.info.pop("_nuru_perf_start", None)
            if start is None:
                return
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            ctx.add_db(elapsed_ms, statement or "")

        _installed = True
