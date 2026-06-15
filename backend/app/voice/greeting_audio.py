"""Pre-generated personalised call greeting (Phase 12).

Eliminates the dead-air gap at call pickup. When Twilio answers a call,
our realtime stream immediately plays a short Tanzanian-Swahili greeting
that names the recipient ("Shalom Bw. David, habari ya leo. Mambo vipi?
Naitwa Happyphania, napiga kutoka Nuru kuhusu mwaliko wako. Tafadhali
subiri kidogo nikuunganishe."), buying the ~3 seconds Gemini Live needs
to finish its WebSocket handshake.

The audio is rendered with Gemini TTS (``GEMINI_TTS_MODEL``) using the
same speaker the live call uses (``GEMINI_VOICE_NAME`` — currently
Sulafat), wrapped in raw PCM16 mono @ 24 000 Hz, and stored on the
``voice_call_jobs`` row. ``voice.realtime`` reads those bytes and pipes
them into the existing Twilio Media Stream as the very first outbound
chunks of the call.

Failure is non-fatal: if Gemini TTS is unreachable, the columns stay
``NULL`` and the call proceeds with the legacy "Gemini speaks first"
behaviour. Nothing else in the voice pipeline depends on this.
"""
from __future__ import annotations

import base64
import logging
from typing import Optional, Tuple
from uuid import UUID

import httpx

from core import config
from core.database import SessionLocal
from models import VoiceCallJob, VoiceCampaign, Event

logger = logging.getLogger("nuru.voice.greeting_audio")

# PCM16 mono @ 24 000 Hz is what Gemini TTS returns by default.
GREETING_SAMPLE_RATE = 24_000
GREETING_MIME = f"audio/pcm;rate={GREETING_SAMPLE_RATE}"

# Caller persona — kept in code (not env) so the recipient always hears the
# same human name regardless of which speaker config is active.
CALLER_PERSONA_NAME = "Nuru Voice Assistant"

_TTS_ENDPOINT = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)


# ──────────────────────────────────────────────────────────────────
# Text composition
# ──────────────────────────────────────────────────────────────────

def _addressed_name(raw_name: str) -> str:
    """Return the polite Swahili form of the recipient's name.

    Reuses the title/first-name rules from ``rsvp_agent._address_for`` so
    "Mr Frank" becomes "Bw. Frank" and "David Mwakalinga" becomes "David".
    Empty input falls back to a generic respectful address.
    """
    try:
        from voice.agents.rsvp_agent import _address_for  # local import to avoid cycle
        addressed, _ = _address_for(raw_name or "", is_sw=True)
        return addressed
    except Exception:  # noqa: BLE001
        clean = (raw_name or "").strip()
        return clean.split()[0] if clean else "mgeni"


def _event_name(job: VoiceCallJob, db) -> Optional[str]:
    if not job.campaign_id:
        return None
    try:
        camp = db.query(VoiceCampaign).filter(VoiceCampaign.id == job.campaign_id).first()
        if camp is None or not camp.event_id:
            return None
        ev = db.query(Event).filter(Event.id == camp.event_id).first()
        name = (getattr(ev, "name", None) or "").strip() if ev is not None else ""
        return name or None
    except Exception:  # noqa: BLE001
        logger.exception("greeting_audio: failed to load event name job=%s", job.id)
        return None


def compose_greeting_text(job: VoiceCallJob, *, event_name: Optional[str] = None) -> str:
    """Return the personalised Swahili greeting that will be rendered to audio.

    Opens with a time-of-day salutation computed in EAT (UTC+3, Tanzania
    local time) so a 7am call says "Habari ya asubuhi" and a 9pm call
    says "Habari ya usiku" — matches the recipient's local feel.
    Always names the recipient (with title when present) so they hear
    their name within the first second of the call.
    """
    name = _addressed_name(getattr(job, "recipient_name", "") or "")
    try:
        from voice.agents.rsvp_agent import time_of_day_greeting  # local import to avoid cycle
        tod = time_of_day_greeting(is_sw=True)
    except Exception:  # noqa: BLE001
        tod = "Habari"
    if event_name:
        return (
            f"{tod} {name}, mambo vipi? "
            f"Naitwa {CALLER_PERSONA_NAME}, napiga kutoka Nuru kuhusu "
            f"mwaliko wako wa tukio la {event_name}. "
            f"Tafadhali subiri kidogo nikuunganishe."
        )
    return (
        f"{tod} {name}, mambo vipi? "
        f"Naitwa {CALLER_PERSONA_NAME}, napiga kutoka Nuru kuhusu mwaliko wako. "
        f"Tafadhali subiri kidogo nikuunganishe."
    )



# ──────────────────────────────────────────────────────────────────
# Gemini TTS call
# ──────────────────────────────────────────────────────────────────

def _render_pcm(text: str, *, timeout: float = 8.0) -> Optional[bytes]:
    """Render ``text`` to PCM16 mono @ 24 kHz via Gemini TTS.

    Returns the decoded byte string, or ``None`` if anything goes wrong
    (missing API key, network error, unexpected response shape). The
    caller is expected to treat ``None`` as "no pre-greeting, continue".
    """
    api_key = (config.GEMINI_API_KEY or "").strip()
    if not api_key:
        logger.warning("greeting_audio: GEMINI_API_KEY missing, skipping TTS")
        return None

    voice_cfg = config.get_gemini_voice_config()
    model_cfg = config.get_gemini_model_config()
    voice_name = (voice_cfg.get("voice_name") or "Sulafat").strip() or "Sulafat"
    tts_model = (model_cfg.get("tts_model") or "").strip()
    if not tts_model:
        logger.warning("greeting_audio: GEMINI_TTS_MODEL missing, skipping TTS")
        return None

    language_code = (
        getattr(config, "GEMINI_VOICE_LANGUAGE", None)
        or getattr(config, "VOICE_DIALECT", None)
        or "sw-TZ"
    )
    url = _TTS_ENDPOINT.format(model=tts_model) + f"?key={api_key}"
    body = {
        "contents": [{"parts": [{"text": text}]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
                "languageCode": language_code,
                "voiceConfig": {
                    "prebuiltVoiceConfig": {"voiceName": voice_name},
                },
            },
        },
    }

    try:
        with httpx.Client(timeout=timeout) as client:
            resp = client.post(url, json=body)
    except httpx.HTTPError as exc:
        logger.warning("greeting_audio: network error during TTS: %r", exc)
        return None

    if resp.status_code >= 400:
        logger.warning(
            "greeting_audio: TTS HTTP %s body=%s",
            resp.status_code, resp.text[:300],
        )
        return None

    try:
        data = resp.json()
        parts = (
            data.get("candidates", [{}])[0]
            .get("content", {})
            .get("parts", [])
        )
        for part in parts:
            inline = part.get("inlineData") or part.get("inline_data") or {}
            payload = inline.get("data")
            if payload:
                return base64.b64decode(payload)
    except Exception:  # noqa: BLE001
        logger.exception("greeting_audio: failed to decode TTS response")
        return None

    logger.warning("greeting_audio: TTS response had no audio part")
    return None


# ──────────────────────────────────────────────────────────────────
# Public entry point used by the dispatcher
# ──────────────────────────────────────────────────────────────────

def ensure_for_job(job_id: str | UUID) -> Tuple[bool, Optional[str]]:
    """Generate + persist the pre-greeting audio for ``job_id`` if needed.

    Idempotent: if the job already has ``greeting_audio`` stored we skip
    regeneration. Returns ``(generated, error_message)`` for logging /
    tests; never raises so the dispatch loop is unaffected by TTS issues.
    """
    db = SessionLocal()
    try:
        job = db.query(VoiceCallJob).filter(VoiceCallJob.id == str(job_id)).first()
        if job is None:
            return False, "job_not_found"
        if job.greeting_audio:
            return False, None  # already generated, nothing to do

        event_name = _event_name(job, db)
        text = compose_greeting_text(job, event_name=event_name)
        pcm = _render_pcm(text)
        if not pcm:
            return False, "tts_failed_or_disabled"

        job.greeting_text = text
        job.greeting_audio = pcm
        job.greeting_audio_mime = GREETING_MIME
        db.commit()
        logger.info(
            "greeting_audio: stored bytes=%d text_len=%d job=%s",
            len(pcm), len(text), job.id,
        )
        return True, None
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        logger.exception("greeting_audio: ensure_for_job crashed job=%s", job_id)
        return False, str(exc)[:200]
    finally:
        db.close()
