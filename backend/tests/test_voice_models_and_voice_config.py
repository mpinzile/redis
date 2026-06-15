"""Tests for backend-controlled Gemini model + speaker selection.

These guard the rules from the Smart RSVP voice spec:

* Model and speaker selection live in env-driven settings only.
* No public API surface accepts ``voice_name``, ``speaker``, ``tts_model``,
  ``live_model``, or ``speech_config`` overrides.
* The TTS model is NEVER used as the realtime call model.
* The live-translation model is NEVER used for normal RSVP calls.
* Speaker name controls voice SOUND only — language stays Swahili.
"""
from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1] / "app"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _reload_config(monkeypatch, **env):
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    from core import config as _config  # type: ignore
    return importlib.reload(_config)


# ── env loading ─────────────────────────────────────────────────────
def test_loads_gemini_text_model(monkeypatch):
    cfg = _reload_config(monkeypatch, GEMINI_TEXT_MODEL="gemini-2.5-flash")
    assert cfg.GEMINI_TEXT_MODEL == "gemini-2.5-flash"


def test_loads_gemini_live_model(monkeypatch):
    cfg = _reload_config(monkeypatch, GEMINI_LIVE_MODEL="gemini-3.1-flash-live-preview")
    assert cfg.GEMINI_LIVE_MODEL == "gemini-3.1-flash-live-preview"


def test_loads_gemini_live_model_fallback(monkeypatch):
    cfg = _reload_config(
        monkeypatch,
        GEMINI_LIVE_MODEL_FALLBACK="gemini-2.5-flash-native-audio-preview-12-2025",
    )
    assert cfg.GEMINI_LIVE_MODEL_FALLBACK == "gemini-2.5-flash-native-audio-preview-12-2025"


def test_loads_gemini_tts_model(monkeypatch):
    cfg = _reload_config(monkeypatch, GEMINI_TTS_MODEL="gemini-3.1-flash-tts-preview")
    assert cfg.GEMINI_TTS_MODEL == "gemini-3.1-flash-tts-preview"


def test_loads_gemini_live_translate_model(monkeypatch):
    cfg = _reload_config(
        monkeypatch,
        GEMINI_LIVE_TRANSLATE_MODEL="gemini-3.5-live-translate-preview",
    )
    assert cfg.GEMINI_LIVE_TRANSLATE_MODEL == "gemini-3.5-live-translate-preview"


def test_loads_gemini_voice_name(monkeypatch):
    cfg = _reload_config(monkeypatch, GEMINI_VOICE_NAME="Zephyr")
    assert cfg.GEMINI_VOICE_NAME == "Zephyr"


# ── helpers ─────────────────────────────────────────────────────────
def test_get_gemini_model_config_returns_configured_models(monkeypatch):
    cfg = _reload_config(
        monkeypatch,
        GEMINI_TEXT_MODEL="gemini-2.5-flash",
        GEMINI_LIVE_MODEL="gemini-3.1-flash-live-preview",
        GEMINI_LIVE_MODEL_FALLBACK="gemini-2.5-flash-native-audio-preview-12-2025",
        GEMINI_TTS_MODEL="gemini-3.1-flash-tts-preview",
        GEMINI_LIVE_TRANSLATE_MODEL="gemini-3.5-live-translate-preview",
    )
    out = cfg.get_gemini_model_config()
    assert out == {
        "text_model": "gemini-2.5-flash",
        "live_model": "gemini-3.1-flash-live-preview",
        "live_model_fallback": "gemini-2.5-flash-native-audio-preview-12-2025",
        "tts_model": "gemini-3.1-flash-tts-preview",
        "live_translate_model": "gemini-3.5-live-translate-preview",
    }


def test_get_gemini_voice_config_returns_configured_voice(monkeypatch):
    cfg = _reload_config(
        monkeypatch,
        GEMINI_VOICE_NAME="Zephyr",
        GEMINI_VOICE_LANGUAGE="sw",
        GEMINI_VOICE_STYLE="calm",
        GEMINI_VOICE_SPEAKING_RATE="normal",
    )
    assert cfg.get_gemini_voice_config() == {
        "voice_name": "Zephyr",
        "language": "sw",
        "style": "calm",
        "speaking_rate": "normal",
    }


def test_changing_voice_name_changes_config_without_code(monkeypatch):
    cfg = _reload_config(monkeypatch, GEMINI_VOICE_NAME="Aoede")
    assert cfg.get_gemini_voice_config()["voice_name"] == "Aoede"
    cfg = _reload_config(monkeypatch, GEMINI_VOICE_NAME="Puck")
    assert cfg.get_gemini_voice_config()["voice_name"] == "Puck"


# ── Gemini Live setup frame uses configured voice + language ────────
def test_setup_frame_passes_configured_voice_name():
    from voice.ai.gemini_live import GeminiLiveBridge  # type: ignore
    frame = GeminiLiveBridge._setup_frame(
        "gemini-3.1-flash-live-preview", "Zephyr", "sys", [], "sw",
    )
    speech = frame["setup"]["generation_config"]["speech_config"]
    assert speech["voice_config"]["prebuilt_voice_config"]["voice_name"] == "Zephyr"
    # Speaker does NOT control language — Swahili still enforced (sw-TZ).
    assert speech["language_code"] == "sw-TZ"


def test_setup_frame_zephyr_remains_swahili():
    """Voice name 'Zephyr' must not flip the output to English."""
    from voice.ai.gemini_live import GeminiLiveBridge  # type: ignore
    frame = GeminiLiveBridge._setup_frame(
        "gemini-3.1-flash-live-preview", "Zephyr", "Anza simu kwa Kiswahili.",
        [], "sw",
    )
    assert frame["setup"]["generation_config"]["speech_config"]["language_code"] == "sw-TZ"


# ── safety: TTS / translate models are NOT used for realtime RSVP ──
def test_tts_model_is_not_used_for_realtime_calls(monkeypatch):
    """The realtime bridge picks live_model + fallback, never tts/translate."""
    cfg = _reload_config(
        monkeypatch,
        GEMINI_LIVE_MODEL="gemini-3.1-flash-live-preview",
        GEMINI_LIVE_MODEL_FALLBACK="gemini-2.5-flash-native-audio-preview-12-2025",
        GEMINI_TTS_MODEL="gemini-3.1-flash-tts-preview",
        GEMINI_LIVE_TRANSLATE_MODEL="gemini-3.5-live-translate-preview",
    )
    import inspect
    from voice.ai import gemini_live as gl
    src = inspect.getsource(gl.GeminiLiveBridge.start)
    # Realtime start path must use live_model / live_model_fallback only.
    assert "live_model" in src
    assert "tts_model" not in src
    assert "live_translate_model" not in src


# ── safety: public APIs never accept model/voice overrides ─────────
def test_public_voice_apis_do_not_accept_speaker_or_model_overrides():
    """Scan voice route source for forbidden client-facing override fields."""
    route_path = ROOT / "api" / "routes" / "voice_calls.py"
    text = route_path.read_text(encoding="utf-8")
    # These are the request-body field names the spec forbids exposing.
    forbidden_request_fields = [
        '"voice_name"', "'voice_name'",
        '"speaker"', "'speaker'",
        '"tts_model"', "'tts_model'",
        '"live_model"', "'live_model'",
        '"speech_config"', "'speech_config'",
    ]
    for needle in forbidden_request_fields:
        assert needle not in text, (
            f"Public voice API must not accept {needle}; "
            "model/speaker selection is backend-only."
        )
