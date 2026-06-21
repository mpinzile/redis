from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.cors import CORSMiddleware

from api.routes import all_routers
from api.routes.card_templates import router as card_templates_router
from core.config import ENV
from utils.voice_logging import setup_voice_file_logging

# Install the rotating file logger that captures Twilio / Gemini /
# dispatch errors to backend/app/log.txt as early as possible so worker
# fork order doesn't matter.
setup_voice_file_logging()


app = FastAPI(
    title="Nuru API",
    version="1.0.0",
    docs_url=None if ENV == "production" else "/docs",
    redoc_url=None if ENV == "production" else "/redoc",
    openapi_url=None if ENV == "production" else "/openapi.json",
)

API_PREFIX = "/api/v1"

# ------------------------------------------------------------------
# Middleware stack (order matters: outermost runs first)
# ------------------------------------------------------------------

# 1. CORS (must be outermost for preflight handling)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://192.168.100.7:8080",
        "https://app.nuru.tz",
        "https://www.nuru.tz",
        "https://nuru.tz",
        "https://workspace.nuru.tz",
        "http://app.nuru.tz",
        "https://nuru.ke",
        "https://www.nuru.ke",
        "http://nuru.ke",
    ],
    allow_origin_regex=r"https://.*\.lovable\.app",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 2. GZip compression for all responses > 500 bytes
app.add_middleware(GZipMiddleware, minimum_size=500)

# 3. Redis-based rate limiting (replaces broken in-memory RateLimitMiddleware)
from middleware.rate_limit import RedisRateLimitMiddleware
app.add_middleware(
    RedisRateLimitMiddleware,
    max_requests=3000,        # increase capacity
    window_seconds=60,       # keep same window
    exclude_paths={
        "/health",
        "/docs",
        "/openapi.json",
        "/redoc",
        "/api/v1/admin",    # VERY IMPORTANT
    },
)

# 4. Auth-endpoint specific tighter rate limiting
from middleware.rate_limit import RedisAuthRateLimitMiddleware
app.add_middleware(
    RedisAuthRateLimitMiddleware,
    max_requests=30,        # auth: 30 req/min per IP (raised from 10 for shared NAT)
    window_seconds=60,
)

# 5. Security headers (lightweight, always runs)
from middleware.security import SecurityHeadersMiddleware
app.add_middleware(SecurityHeadersMiddleware)

# 5b. WhatsApp log sender attribution — binds every wa_message_logs row
#     created during a request to the authenticated user who triggered it.
from middleware.wa_log_context import WaLogContextMiddleware
app.add_middleware(WaLogContextMiddleware)

# 6. Query logging & per-request DB stats (dev/staging diagnostics)
from middleware.query_logger import QueryCountMiddleware, ENABLED as QUERY_LOG_ON
if QUERY_LOG_ON:
    app.add_middleware(QueryCountMiddleware)

# 7. Slow request logger — logs any request > SLOW_REQUEST_THRESHOLD_MS (default 500ms)
from middleware.slow_request_logger import SlowRequestLoggerMiddleware
app.add_middleware(SlowRequestLoggerMiddleware)

# 8. Perf instrumentation — Stage 1 of the performance program.
#    Innermost middleware: emits one JSON line per request with timing,
#    query count, slowest query, Redis/Celery/external timings, payload
#    size. Adds X-Request-ID header. Does NOT change response bodies.
#    Disable with PERF_INSTRUMENTATION=false.
from core.perf import PerfMiddleware
app.add_middleware(PerfMiddleware)

# ------------------------------------------------------------------
# Routes
# ------------------------------------------------------------------
@app.get("/")
def root():
    return {"message": "Welcome to Nuru API"}

for router in all_routers:
    app.include_router(router, prefix=API_PREFIX)

# Admin monitoring (separate mount for clarity)
from api.routes.admin_monitoring import router as admin_monitoring_router
app.include_router(admin_monitoring_router, prefix=API_PREFIX)

from api.routes.admin_whatsapp_availability import router as admin_wa_avail_router
app.include_router(admin_wa_avail_router, prefix=API_PREFIX)

# Ensure card-templates routes are always mounted (safety fallback)
registered_paths = {route.path for route in app.router.routes}
if f"{API_PREFIX}/card-templates" not in registered_paths:
    app.include_router(card_templates_router, prefix=API_PREFIX)

# ------------------------------------------------------------------
# Error handling
# ------------------------------------------------------------------
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    # Preserve the explicit error_code we set in some routes via exc.detail
    # being a dict; otherwise wrap the string detail in the standard shape.
    detail = exc.detail
    if isinstance(detail, dict):
        body = {"success": False, "data": None, **detail}
    else:
        body = {"success": False, "message": detail, "data": None}
    return JSONResponse(status_code=exc.status_code, content=body)


# ------------------------------------------------------------------
# Catch-all error handlers
# ------------------------------------------------------------------
# Without these, an unhandled exception or upstream timeout reaches the proxy
# (Vercel/nginx) which returns an HTML error page. The mobile client then
# can't parse a JSON body and surfaces its generic "Unable to connect — check
# your internet" fallback, which is misleading because the device is fine —
# the *server* failed. Returning structured JSON with an explicit error_code
# lets the client distinguish "request failed" from "no network".
import asyncio  # noqa: E402


@app.exception_handler(asyncio.TimeoutError)
async def asyncio_timeout_handler(request: Request, exc: asyncio.TimeoutError):
    return JSONResponse(
        status_code=504,
        content={
            "success": False,
            "error_code": "UPSTREAM_TIMEOUT",
            "message": "Request took too long. Please try again in a moment.",
            "data": None,
        },
    )


@app.exception_handler(TimeoutError)
async def timeout_handler(request: Request, exc: TimeoutError):
    return JSONResponse(
        status_code=504,
        content={
            "success": False,
            "error_code": "UPSTREAM_TIMEOUT",
            "message": "Request took too long. Please try again in a moment.",
            "data": None,
        },
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    # Log the real error server-side; never leak the trace to the client.
    import traceback
    print(f"[unhandled] {request.method} {request.url.path}: {exc!r}")
    traceback.print_exc()
    return JSONResponse(
        status_code=500,
        content={
            "success": False,
            "error_code": "REQUEST_FAILED",
            "message": "Request failed. Please try again.",
            "data": None,
        },
    )


# ------------------------------------------------------------------
# Startup
# ------------------------------------------------------------------
@app.on_event("startup")
def startup_checks():
    import os
    deployment_mode = os.getenv("DEPLOYMENT_MODE", "vps").lower().strip()
    print(f"[startup] Deployment mode: {deployment_mode}")

    if deployment_mode == "vercel":
        print("[startup] Vercel mode — Redis & Celery disabled, caching no-ops")
        return

    from core.redis import redis_available
    if redis_available():
        print("[startup] Redis connected ✓ — caching + rate limiting active")
    else:
        print("[startup] Redis unavailable — caching disabled, rate limiting falls open")
    print("[startup] Background tasks handled by Celery workers (not in-process threads)")
    print("[startup] Run:  celery -A core.celery_app worker --beat --loglevel=info")

    # Register force-sync domain handlers (admin POST /admin/jobs/force-sync).
    try:
        from core.jobs.force_sync_registry import register_all as _register_force_sync
        _register_force_sync()
    except Exception as exc:  # noqa: BLE001
        print(f"[startup] force-sync registry failed: {exc!r}")

    # Voice Assistant — install Gemini Live realtime bridge if configured.
    # Safe no-op when GEMINI_API_KEY is missing (Phase 5 SilentAgentBridge stays).
    try:
        from voice.ai import install as install_voice_bridge
        if install_voice_bridge():
            print("[startup] Voice Assistant: Gemini Live bridge installed ✓")
        else:
            print("[startup] Voice Assistant: Gemini Live not configured — silent bridge active")
    except Exception as exc:  # noqa: BLE001
        print(f"[startup] Voice Assistant bridge install failed: {exc!r}")


# ------------------------------------------------------------------
# Health endpoint
# ------------------------------------------------------------------
@app.get("/health")
def health():
    from core.redis import redis_available
    return {
        "status": "ok",
        "redis": redis_available(),
    }
