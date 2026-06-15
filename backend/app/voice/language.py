"""Voice language resolution for Smart RSVP calls.

Smart RSVP defaults to natural Tanzanian Swahili (``sw``) regardless of
locale on the device. We only switch to ``en`` if the recipient (or the
event/job/campaign) has explicitly requested English.

This is the single source of truth used by the Twilio webhook, Gemini
Live setup and the RSVP agent so we cannot accidentally start a call in
English because one layer fell back to the system locale.
"""
from __future__ import annotations

from typing import Any, Optional

from core import config


def _normalize(value: Optional[str]) -> str:
    if not value:
        return ""
    v = str(value).strip().lower()
    if v.startswith("en"):
        return "en"
    if v.startswith("sw"):
        return "sw"
    return v


def get_voice_language(
    event: Any = None,
    recipient: Any = None,
    job: Any = None,
    request: Any = None,
) -> str:
    """Return ``"sw"`` or ``"en"`` for one Smart RSVP call.

    Resolution order (first explicit hit wins):
      1. Recipient/job-level override (``recipient.language`` /
         ``job.language``) — set when the recipient previously asked us to
         continue in English.
      2. Event-level override (``event.voice_language``) — organiser pref.
      3. Per-request override on the HTTP request (``?language=``).
      4. ``VOICE_DEFAULT_LANGUAGE`` from env (defaults to ``sw``).

    The function never returns ``en`` by accident: every English answer
    must come from an *explicit* opt-in upstream.
    """
    for src in (recipient, job):
        v = _normalize(getattr(src, "language", None))
        if v in ("sw", "en"):
            return v

    v = _normalize(getattr(event, "voice_language", None))
    if v in ("sw", "en"):
        return v

    if request is not None:
        try:
            v = _normalize(request.query_params.get("language"))
            if v in ("sw", "en"):
                return v
        except Exception:  # noqa: BLE001
            pass

    default = _normalize(getattr(config, "VOICE_DEFAULT_LANGUAGE", "sw")) or "sw"
    return "sw" if default not in ("sw", "en") else default


def to_bcp47(lang: str) -> str:
    """Map our short code to a Twilio/Gemini BCP-47 tag."""
    v = _normalize(lang)
    if v == "en":
        return "en-US"
    return "sw-TZ"
