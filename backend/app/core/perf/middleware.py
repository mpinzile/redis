"""
PerfMiddleware
==============
Emits one structured JSON line per HTTP request with timings, counters,
and tags so a log aggregator can compute p50/p95/p99, payload size, query
count, slowest query, Redis time, Celery enqueue time, and external time.

This middleware DOES NOT change any response body. It only:
  * binds a PerfContext to the request via contextvar
  * adds an `X-Request-ID` response header
  * logs one `nuru.perf` line on the way out
  * fires the existing `X-Response-Time` only if not already present (the
    existing SlowRequestLoggerMiddleware also sets it; we never overwrite)

Enable with PERF_INSTRUMENTATION=true (default ON). Disable by setting to
"false" — the middleware short-circuits to plain `call_next`.
"""

from __future__ import annotations

import json
import logging
import os
import time

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from . import db_metrics
from .context import (
    PerfContext,
    new_request_id,
    reset_current,
    set_current,
)
from .endpoint_groups import classify, thresholds

ENABLED = os.getenv("PERF_INSTRUMENTATION", "true").lower() == "true"
LOG_ALL = os.getenv("PERF_LOG_ALL", "true").lower() == "true"

log = logging.getLogger("nuru.perf.json")
if not log.handlers:
    h = logging.StreamHandler()
    h.setFormatter(logging.Formatter("%(message)s"))
    log.addHandler(h)
    log.setLevel(logging.INFO)
    log.propagate = False


def _route_template(request: Request) -> str:
    route = request.scope.get("route")
    if route is not None and getattr(route, "path", None):
        return route.path
    return request.url.path


def _extract_path_param(request: Request, key: str) -> str | None:
    val = request.path_params.get(key) if request.path_params else None
    if val is None:
        return None
    return str(val)


class PerfMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if not ENABLED:
            return await call_next(request)

        # Lazy-install SQLAlchemy listeners the first time a request lands.
        db_metrics.install()

        rid = request.headers.get("x-request-id") or new_request_id()
        ctx = PerfContext(
            request_id=rid,
            method=request.method,
            path=request.url.path,
        )
        token = set_current(ctx)
        start = time.perf_counter()

        try:
            response: Response = await call_next(request)
        except Exception:
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            ctx.status_code = 500
            ctx.route = _route_template(request)
            _emit(ctx, elapsed_ms)
            reset_current(token)
            raise

        elapsed_ms = (time.perf_counter() - start) * 1000.0
        ctx.status_code = response.status_code
        ctx.route = _route_template(request)
        ctx.event_id = _extract_path_param(request, "event_id")
        # user_id is not in path; auth dependencies could set it via the
        # context but we keep this version dependency-free.

        # Response size — fall back to Content-Length header when streaming.
        try:
            cl = response.headers.get("content-length")
            if cl and cl.isdigit():
                ctx.response_bytes = int(cl)
        except Exception:
            pass

        # Headers
        response.headers["X-Request-ID"] = rid
        if "X-Response-Time" not in response.headers:
            response.headers["X-Response-Time"] = f"{elapsed_ms:.0f}ms"

        _emit(ctx, elapsed_ms)
        reset_current(token)
        return response


def _emit(ctx: PerfContext, elapsed_ms: float) -> None:
    group = classify(ctx.route or ctx.path)
    th = thresholds(group)

    payload = {
        "evt": "req",
        "rid": ctx.request_id,
        "method": ctx.method,
        "path": ctx.path,
        "route": ctx.route,
        "status": ctx.status_code,
        "group": group,
        "dur_ms": round(elapsed_ms, 1),
        "db_n": ctx.db_query_count,
        "db_ms": round(ctx.db_total_ms, 1),
        "db_slow_ms": round(ctx.db_slowest_ms, 1),
        "redis_n": ctx.redis_ops,
        "redis_ms": round(ctx.redis_total_ms, 1),
        "celery_n": ctx.celery_tasks_enqueued,
        "celery_ms": round(ctx.celery_enqueue_ms, 1),
        "ext_n": ctx.external_calls,
        "ext_ms": round(ctx.external_ms, 1),
        "bytes": ctx.response_bytes,
        "event_id": ctx.event_id,
    }
    if ctx.db_slowest_sql:
        payload["db_slow_sql"] = ctx.db_slowest_sql
    if ctx.external_breakdown:
        payload["ext_by"] = {
            k: round(v, 1) for k, v in ctx.external_breakdown.items()
        }

    level = logging.INFO
    if elapsed_ms >= th["crit_ms"]:
        level = logging.CRITICAL
    elif elapsed_ms >= th["err_ms"]:
        level = logging.ERROR
    elif elapsed_ms >= th["warn_ms"]:
        level = logging.WARNING

    if not LOG_ALL and level == logging.INFO:
        return

    try:
        log.log(level, json.dumps(payload, separators=(",", ":"), default=str))
    except Exception:
        # Logging must never break a request.
        pass
