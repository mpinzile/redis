"""Persistent file logger for voice / 3rd-party integration errors.

Writes a rotating ``log.txt`` next to the backend app folder so the
operator can tail it on the server (``backend/app/log.txt``).

Captures (with full HTTP status + response body):

* Twilio auth / API failures  ->  logger ``nuru.voice.twilio``
* Gemini auth / API failures  ->  logger ``nuru.voice.gemini.*``
* Generic call dispatch errors ->  logger ``nuru.voice.dispatch``

Idempotent: calling :func:`setup_voice_file_logging` more than once is a
no-op so it is safe to import from both ``main.py`` startup and from
ad-hoc scripts.
"""
from __future__ import annotations

import logging
import os
from logging.handlers import RotatingFileHandler
from pathlib import Path

_INSTALLED = False
_LOG_PATH = Path(__file__).resolve().parent.parent / "log.txt"

# Loggers we want mirrored to log.txt. Anything published under these
# names (or their children) is captured by the file handler.
_TARGET_LOGGERS = (
    "nuru.voice.twilio",
    "nuru.voice.twilio_route",
    "nuru.voice.gemini",
    "nuru.voice.gemini.text",
    "nuru.voice.gemini.live",
    "nuru.voice.dispatch",
    "nuru.voice.realtime",
    "nuru.voice.rsvp_agent",
)


class _SafeFormatter(logging.Formatter):
    """Never let formatter errors swallow log records."""

    def format(self, record: logging.LogRecord) -> str:  # noqa: D401
        try:
            return super().format(record)
        except Exception as exc:  # pragma: no cover - defensive
            return f"{record.levelname} {record.name}: <format error: {exc}> {record.getMessage()}"


def setup_voice_file_logging() -> Path:
    """Attach a rotating file handler to the voice loggers.

    Returns the resolved path of the log file (creates parent dir if
    missing). Repeated calls are no-ops.
    """
    global _INSTALLED
    if _INSTALLED:
        return _LOG_PATH

    try:
        _LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        # Best-effort: if filesystem is read-only just skip — stdout still works.
        return _LOG_PATH

    handler = RotatingFileHandler(
        _LOG_PATH,
        maxBytes=5 * 1024 * 1024,   # 5 MB per file
        backupCount=3,              # keep log.txt.1 .. log.txt.3
        encoding="utf-8",
        delay=True,
    )
    handler.setLevel(logging.INFO)
    handler.setFormatter(_SafeFormatter(
        fmt="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    ))
    # Tag the handler so we can detect duplicates if this gets called twice
    # across forked workers.
    handler.set_name("nuru-voice-file")

    for name in _TARGET_LOGGERS:
        lg = logging.getLogger(name)
        lg.setLevel(min(lg.level or logging.INFO, logging.INFO))
        # Avoid duplicate handlers if a worker re-imports this module.
        if not any(getattr(h, "name", None) == "nuru-voice-file" for h in lg.handlers):
            lg.addHandler(handler)
        lg.propagate = True

    _INSTALLED = True
    return _LOG_PATH


def log_path() -> Path:
    return _LOG_PATH


def log_integration_error(
    *,
    integration: str,
    operation: str,
    status: int | None = None,
    body: str | None = None,
    extra: dict | None = None,
    exc: BaseException | None = None,
) -> None:
    """Structured one-liner for 3rd-party failures.

    Always emits under ``nuru.voice.dispatch`` so it appears in log.txt
    regardless of which client raised it.
    """
    logger = logging.getLogger("nuru.voice.dispatch")
    parts = [f"integration={integration}", f"op={operation}"]
    if status is not None:
        parts.append(f"status={status}")
    if extra:
        for k, v in extra.items():
            parts.append(f"{k}={v}")
    if body:
        # Truncate to keep log lines manageable.
        snippet = body.strip().replace("\n", " ")
        if len(snippet) > 600:
            snippet = snippet[:600] + "…"
        parts.append(f'body="{snippet}"')
    msg = " ".join(parts)
    if exc is not None:
        logger.error("%s exc=%r", msg, exc, exc_info=True)
    else:
        logger.error(msg)
