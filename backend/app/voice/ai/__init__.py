"""Voice AI client subpackage (Phase 6 of nuru_voice.md).

Two clients live here:

* ``gemini_text`` — non-realtime text generation (summaries, classification,
  transcript cleanup). Used by the RSVP agent in Phase 7 and by post-call
  housekeeping.
* ``gemini_live`` — realtime audio session bridging the Twilio call to
  Gemini Live. Plugs into the ``AgentBridge`` slot exposed by
  ``voice.realtime``.

Both are import-safe even when ``GEMINI_API_KEY`` is missing — they simply
report ``available() == False`` and the voice routes degrade to the silent
bridge that Phase 5 ships with.
"""
from voice.ai.gemini_text import GeminiTextClient, gemini_text_available
from voice.ai.gemini_live import (
    GeminiLiveBridge, gemini_live_available, install as _install_live,
)


def install() -> bool:
    """Install the Gemini Live bridge and attach the RSVP agent spec.

    Safe to call repeatedly. Returns ``True`` when the realtime bridge
    was installed; the RSVP system-builder is always attached because it
    is a no-op when Gemini is not configured.
    """
    try:
        from voice.agents import install_rsvp_agent
        install_rsvp_agent()
    except Exception:  # noqa: BLE001
        pass
    return _install_live()


__all__ = [
    "GeminiTextClient",
    "gemini_text_available",
    "GeminiLiveBridge",
    "gemini_live_available",
    "install",
]
