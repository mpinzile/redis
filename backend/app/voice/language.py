"""Voice language resolution for Smart RSVP calls.

Smart RSVP defaults to natural Tanzanian Swahili (``sw``) regardless of
locale on the device. We only switch to ``en`` if the recipient (or the
event/job/campaign) has explicitly requested English.

This is the single source of truth used by the Twilio webhook, Gemini
Live setup and the RSVP agent so we cannot accidentally start a call in
English because one layer fell back to the system locale.
"""
from __future__ import annotations

from typing import Any, Optional, Tuple

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


def _pick_language(obj: Any, *attrs: str) -> str:
    if obj is None:
        return ""
    for attr in attrs:
        v = _normalize(getattr(obj, attr, None))
        if v in ("sw", "en"):
            return v
    return ""


def _extra_language_source(job: Any) -> str:
    try:
        extra = getattr(job, "extra", None) or {}
        if isinstance(extra, dict):
            return str(extra.get("language_source") or "").strip().lower()
    except Exception:  # noqa: BLE001
        return ""
    return ""


def resolve_voice_language(
    event: Any = None,
    recipient: Any = None,
    job: Any = None,
    campaign: Any = None,
    request: Any = None,
) -> Tuple[str, str]:
    """Return ``(language, source)`` for one Smart RSVP call.

    Resolution order (first explicit hit wins):
      1. Recipient/job-level preference — the only startup source allowed
         to select English.
      2. Campaign language, but only Swahili is honoured at call start.
      3. Event language, but only Swahili is honoured at call start.
      4. ``VOICE_DEFAULT_LANGUAGE`` from env (defaults to ``sw``).

    The function never returns ``en`` by accident: every English answer
    must come from an *explicit* opt-in upstream.
    """
    v = _pick_language(
        recipient,
        "language_preference", "voice_language_preference",
        "preferred_language", "language",
    )
    if v in ("sw", "en"):
        return v, "recipient_preference"

    v = _pick_language(job, "language_preference", "voice_language_preference")
    if v in ("sw", "en"):
        return v, "recipient_preference"

    v = _pick_language(job, "language")
    if v in ("sw", "en") and _extra_language_source(job) == "recipient_preference":
        return v, "recipient_preference"

    v = _pick_language(campaign, "language")
    if v == "sw":
        return "sw", "campaign"

    v = _pick_language(event, "language", "voice_language")
    if v == "sw":
        return "sw", "event"

    default = _normalize(getattr(config, "VOICE_DEFAULT_LANGUAGE", "sw")) or "sw"
    # VOICE_FALLBACK_LANGUAGE is intentionally ignored for call startup.
    if default == "en":
        return "sw", "env_default"
    return (default if default == "sw" else "sw"), "env_default"


def get_voice_language(
    event: Any = None,
    recipient: Any = None,
    job: Any = None,
    campaign: Any = None,
    request: Any = None,
) -> str:
    """Return ``"sw"`` or ``"en"`` for backwards-compatible callers."""
    language, _source = resolve_voice_language(
        event=event, recipient=recipient, job=job, campaign=campaign, request=request,
    )
    return language


def to_bcp47(lang: str) -> str:
    """Map our short code to a Twilio/Gemini BCP-47 tag.

    For Swahili, prefer the configured ``GEMINI_VOICE_LANGUAGE`` /
    ``VOICE_DIALECT`` env values; hardcoded ``sw-TZ`` is only the
    last-resort fallback.
    """
    from core import config as _config
    v = _normalize(lang)
    if v == "en":
        return "en-US"
    return (
        getattr(_config, "GEMINI_VOICE_LANGUAGE", None)
        or getattr(_config, "VOICE_DIALECT", None)
        or "sw-TZ"
    )
