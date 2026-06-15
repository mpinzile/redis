"""Nuru Voice Assistant package.

Phase 1 ships configuration, phone-number safety and timezone resolution.
Subsequent phases add: models (P2), routes (P3), Twilio (P4), realtime
WebSocket (P5), Gemini clients (P6), RSVP agent (P7), web UI (P8) and
mobile UI (P9). The package is import-safe even when env vars are missing —
``core.config.voice_is_ready()`` reports readiness without raising.
"""

from core import config as voice_config  # noqa: F401  (re-exported for convenience)

__all__ = ["voice_config"]
