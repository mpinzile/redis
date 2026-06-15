"""Twilio outbound voice client for the Nuru Voice Assistant (Phase 4).

We talk to Twilio's REST API directly with ``httpx`` and HTTP Basic auth so
we don't pull in the full ``twilio`` SDK. Only two operations are needed:

* ``place_call(job)`` — POST /Calls.json with our webhook + status callback.
* ``build_twiml(job)`` — returns the XML that Twilio fetches when the call
  is answered. It bridges the call into our realtime WebSocket via
  ``<Connect><Stream>``.

Both are isolated from the rest of the platform; nothing imports them other
than the voice routes added in Phase 3/4.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Optional
from urllib.parse import quote_plus
from xml.sax.saxutils import escape as xml_escape

import httpx

from core import config

logger = logging.getLogger("nuru.voice.twilio")

TWILIO_API_BASE = "https://api.twilio.com/2010-04-01"


class TwilioConfigError(RuntimeError):
    """Raised when Twilio credentials are missing at call-time."""


class TwilioApiError(RuntimeError):
    """Raised when Twilio returns a non-2xx response."""

    def __init__(self, status: int, body: str):
        super().__init__(f"Twilio API error [{status}]: {body[:500]}")
        self.status = status
        self.body = body


@dataclass
class PlaceCallResult:
    call_sid: str
    status: str
    raw: dict


def _require_credentials() -> tuple[str, str, str]:
    sid = (config.TWILIO_ACCOUNT_SID or "").strip()
    token = (config.TWILIO_AUTH_TOKEN or "").strip()
    frm = (config.TWILIO_VOICE_FROM_NUMBER or "").strip()
    if not sid or not token or not frm:
        raise TwilioConfigError(
            "Twilio credentials not configured (need TWILIO_ACCOUNT_SID, "
            "TWILIO_AUTH_TOKEN, TWILIO_VOICE_FROM_NUMBER)."
        )
    return sid, token, frm


def place_call(
    *,
    to_phone_e164: str,
    job_id: str,
    record: Optional[bool] = None,
    timeout: int = 25,
) -> PlaceCallResult:
    """Initiate an outbound call. Returns Twilio's CallSid + initial status."""
    sid, token, frm = _require_credentials()

    webhook = config.TWILIO_VOICE_WEBHOOK_URL.rstrip("/")
    status_cb = config.TWILIO_STATUS_CALLBACK_URL.rstrip("/")
    record_calls = (
        record if record is not None else bool(config.VOICE_RECORD_CALLS)
    )

    form = {
        "To": to_phone_e164,
        "From": frm,
        # Pass job_id as a query param so the webhook can correlate.
        "Url": f"{webhook}?job_id={quote_plus(str(job_id))}",
        "Method": "POST",
        "StatusCallback": f"{status_cb}?job_id={quote_plus(str(job_id))}",
        "StatusCallbackMethod": "POST",
        "StatusCallbackEvent": "initiated ringing answered completed",
        "Timeout": str(max(5, int(config.VOICE_MAX_CALL_SECONDS or 60))),
        "Record": "true" if record_calls else "false",
        "MachineDetection": "Enable",
    }

    url = f"{TWILIO_API_BASE}/Accounts/{sid}/Calls.json"
    with httpx.Client(timeout=timeout) as client:
        resp = client.post(url, data=form, auth=(sid, token))

    if resp.status_code >= 400:
        logger.warning("Twilio place_call failed: %s %s", resp.status_code, resp.text[:300])
        raise TwilioApiError(resp.status_code, resp.text)

    data = resp.json()
    return PlaceCallResult(
        call_sid=data.get("sid", ""),
        status=data.get("status", "queued"),
        raw=data,
    )


def build_twiml(
    *,
    job_id: str,
    greeting: Optional[str] = None,
    language: str = "sw-KE",
) -> str:
    """Build the TwiML that bridges the answered call into our AI stream.

    The greeting is rendered with Twilio's built-in TTS so the recipient
    hears something the instant they pick up, even if Gemini takes a moment
    to spin up. The ``<Connect><Stream>`` block then hands raw mulaw audio
    to our realtime WebSocket (Phase 5).
    """
    stream_url = (config.VOICE_AI_STREAM_URL or "").strip()
    if not stream_url:
        # Fallback: just speak the greeting and hang up gracefully.
        spoken = xml_escape(greeting or "Habari. Asante kwa kupokea simu hii.")
        return (
            '<?xml version="1.0" encoding="UTF-8"?>'
            f'<Response><Say language="{xml_escape(language)}">{spoken}</Say></Response>'
        )

    greeting_text = xml_escape(
        greeting or "Habari. Hii ni Msaidizi wa Sauti wa Nuru."
    )
    safe_lang = xml_escape(language)
    safe_job = xml_escape(str(job_id))

    return (
        '<?xml version="1.0" encoding="UTF-8"?>'
        "<Response>"
        f'<Say language="{safe_lang}">{greeting_text}</Say>'
        "<Connect>"
        f'<Stream url="{xml_escape(stream_url)}">'
        f'<Parameter name="job_id" value="{safe_job}"/>'
        f'<Parameter name="language" value="{safe_lang}"/>'
        "</Stream>"
        "</Connect>"
        "</Response>"
    )


def is_terminal_status(status: str) -> bool:
    return (status or "").lower() in {
        "completed", "busy", "failed", "no-answer", "canceled",
    }


def status_to_job_status(twilio_status: str) -> str:
    """Map Twilio's call status vocabulary to our VoiceCallJob.status values."""
    s = (twilio_status or "").lower()
    if s in {"queued", "initiated"}:
        return "queued"
    if s in {"ringing", "in-progress"}:
        return "in_progress"
    if s == "completed":
        return "completed"
    if s == "busy":
        return "busy"
    if s == "no-answer":
        return "no_answer"
    if s in {"failed", "canceled"}:
        return "failed"
    return s or "pending"
