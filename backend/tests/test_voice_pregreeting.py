"""Pre-greeting audio tests (Phase 12 — zero pickup latency)."""
from __future__ import annotations

import os
import sys
from types import SimpleNamespace
from unittest.mock import patch

import pytest

BACKEND_APP = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "app"))
if BACKEND_APP not in sys.path:
    sys.path.insert(0, BACKEND_APP)


# ── compose_greeting_text ─────────────────────────────────────────

def _make_job(name: str = "David Mwakalinga"):
    return SimpleNamespace(
        id="job-1",
        recipient_name=name,
        campaign_id=None,
        greeting_audio=None,
        greeting_audio_mime=None,
        greeting_text=None,
    )


def test_compose_greeting_includes_addressed_name_and_persona():
    from voice.greeting_audio import compose_greeting_text, CALLER_PERSONA_NAME

    text = compose_greeting_text(_make_job("David Mwakalinga"))
    assert text.startswith("Shalom David,"), text
    assert CALLER_PERSONA_NAME in text
    assert "Nuru" in text
    # Buys handshake time without confirming RSVP.
    assert "Tafadhali subiri" in text
    assert "kuthibitisha" not in text


def test_compose_greeting_with_title():
    from voice.greeting_audio import compose_greeting_text

    text = compose_greeting_text(_make_job("Mr Frank"))
    assert "Bw. Frank" in text


def test_compose_greeting_with_event_name():
    from voice.greeting_audio import compose_greeting_text

    text = compose_greeting_text(_make_job(), event_name="Harusi ya Asha")
    assert "Harusi ya Asha" in text


def test_compose_greeting_empty_name_falls_back():
    from voice.greeting_audio import compose_greeting_text

    text = compose_greeting_text(_make_job(""))
    # Should not crash and should not say "Shalom ,"
    assert "Shalom" in text
    assert "Shalom ," not in text


# ── _parse_pcm_rate ───────────────────────────────────────────────

def test_parse_pcm_rate_handles_mime_variants():
    from voice.realtime import _parse_pcm_rate

    assert _parse_pcm_rate("audio/pcm;rate=24000") == 24_000
    assert _parse_pcm_rate("audio/pcm; rate=16000") == 16_000
    assert _parse_pcm_rate("") == 24_000  # default
    assert _parse_pcm_rate("audio/pcm") == 24_000


# ── TTS render failure path ───────────────────────────────────────

def test_render_pcm_returns_none_without_api_key(monkeypatch):
    from voice import greeting_audio
    monkeypatch.setattr(greeting_audio.config, "GEMINI_API_KEY", "", raising=False)
    assert greeting_audio._render_pcm("hello") is None


# ── Bridge skip_greeting wiring ───────────────────────────────────

@pytest.mark.asyncio
async def test_silent_bridge_accepts_skip_greeting_and_delay():
    from voice.realtime import SilentAgentBridge

    bridge = SilentAgentBridge()
    job = SimpleNamespace(id="j1")
    # Should accept the new kwargs without raising.
    await bridge.start(job=job, language="sw-TZ",
                       skip_greeting=True, initial_turn_delay_s=0.0)
    await bridge.stop()


@pytest.mark.asyncio
async def test_gemini_initial_turn_text_skips_greeting_when_pre_played():
    """When skip_greeting=True, the prompt must tell Gemini NOT to re-greet."""
    from voice.ai.gemini_live import GeminiLiveBridge

    captured: list[str] = []

    class _FakeWS:
        async def send(self, payload):
            captured.append(payload)

    bridge = GeminiLiveBridge()
    bridge._ws = _FakeWS()
    job = SimpleNamespace(id="j2", recipient_name="David", campaign_id=None)
    await bridge._send_initial_turn("sw-TZ", job, skip_greeting=True)

    assert captured, "initial turn was not sent"
    payload = captured[0]
    assert "USIRUDIE" in payload  # explicit "do not repeat" instruction
    assert "tayari imechezwa" in payload.lower() or "TAYARI imechezwa" in payload
    assert "Nakupigia kwa niaba" in payload  # continuation line

    # Sanity: without skip_greeting we DO get the standard opener.
    captured.clear()
    bridge2 = GeminiLiveBridge()
    bridge2._ws = _FakeWS()
    await bridge2._send_initial_turn("sw-TZ", job, skip_greeting=False)
    assert "Habari, napiga kutoka Nuru" in captured[0]
