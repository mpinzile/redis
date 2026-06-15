"""Tests for Swahili-first Smart RSVP voice behaviour."""
from __future__ import annotations

import os
import sys
import types

# Ensure backend/app is importable when running pytest from repo root.
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "app"))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


def _stub(name: str, **attrs):
    mod = types.ModuleType(name)
    for k, v in attrs.items():
        setattr(mod, k, v)
    sys.modules[name] = mod
    return mod


# Stub the heavy backend imports the agent module pulls in. We only test
# pure, deterministic helpers — no DB, no Gemini, no Twilio.
_cfg = types.ModuleType("config_stub")
_cfg.VOICE_DEFAULT_LANGUAGE = "sw"
_cfg.VOICE_FALLBACK_LANGUAGE = "en"
_cfg.VOICE_AI_STREAM_URL = ""
_stub("core", config=_cfg)
sys.modules["core.config"] = _cfg
_stub("core.database", SessionLocal=lambda: None)

_stub(
    "models",
    EventAttendee=object,
    EventInvitation=object,
    Event=object,
    RSVPStatusEnum=object,
    VoiceCallJob=object,
    VoiceCallLog=object,
    VoiceOptOut=object,
)
_stub("voice.timezone", resolve_timezone=lambda *a, **k: "Africa/Dar_es_Salaam")

from voice.agents import conversation  # noqa: E402
from voice.agents.rsvp_agent import build_rsvp_spec  # noqa: E402

try:
    from voice.twilio_client import build_twiml  # noqa: E402
except Exception:  # pragma: no cover - httpx not installed in test sandbox
    build_twiml = None



def test_default_opening_is_swahili():
    spec = build_rsvp_spec(job=None, language="sw")
    text = spec["system_text"]
    assert "Habari, napiga kutoka Nuru" in text
    assert "Ningependa kuthibitisha kama utahudhuria" in text
    # Must explicitly forbid English by default.
    assert "KISWAHILI" in text
    assert "Usitumie Kiingereza" in text


def test_unknown_language_defaults_to_swahili():
    # Empty / unknown language must NOT silently fall back to English.
    spec = build_rsvp_spec(job=None, language="")
    assert "KISWAHILI" in spec["system_text"]


def test_explicit_english_switches_language():
    spec = build_rsvp_spec(job=None, language="en")
    text = spec["system_text"]
    assert "Nuru Voice Assistant" in text
    assert "Speak simple, short, warm English" in text


def test_identity_question_classifies_correctly():
    assert conversation.classify("wewe ni nani?").intent == "identity_question"
    assert conversation.classify("nani amewatuma?").intent == "identity_question"


def test_hearing_problem_classifies_correctly():
    for phrase in ("sikusikii vizuri", "rudia tafadhali", "unasema?"):
        assert conversation.classify(phrase).intent == "did_not_hear"


def test_confirmed_phrases_classify():
    for phrase in (
        "ndio nitakuja",
        "nitahudhuria kabisa",
        "Mungu akipenda nitakuja",
        "Inshallah nitakuja",
    ):
        assert conversation.classify(phrase).intent == "confirmed"


def test_declined_phrases_classify():
    for phrase in ("sitakuja", "nina safari", "niko mbali", "samahani sitafika"):
        assert conversation.classify(phrase).intent == "declined"


def test_maybe_phrases_classify():
    for phrase in ("bado sijajua", "labda", "ngoja nione", "sina uhakika"):
        assert conversation.classify(phrase).intent == "maybe"


def test_call_later_phrases_classify():
    for phrase in ("nipigie baadaye", "nipigie jioni", "niko kwenye kikao"):
        assert conversation.classify(phrase).intent in {"call_later", "busy"}


def test_wrong_number_phrases_classify():
    for phrase in ("umekosea namba", "mimi sio huyo", "hii sio namba yake"):
        assert conversation.classify(phrase).intent == "wrong_number"


def test_unclear_answer_has_low_confidence():
    result = conversation.classify("hmm sijui vile")
    assert result.intent == "unclear"
    assert result.confidence < 0.5  # tools must NOT save_rsvp on low confidence


def test_twiml_fallback_is_swahili():
    if build_twiml is None:
        return  # httpx unavailable in CI sandbox
    os.environ.pop("VOICE_AI_STREAM_URL", None)
    from core import config
    config.VOICE_AI_STREAM_URL = ""  # type: ignore[attr-defined]
    xml = build_twiml(job_id="job-1", greeting=None, language="sw-TZ")
    assert "Samahani, kuna changamoto" in xml
    assert "WhatsApp" in xml
    assert 'language="sw-TZ"' in xml

