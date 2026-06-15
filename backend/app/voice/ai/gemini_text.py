"""Non-realtime Gemini text client (Phase 6 of nuru_voice.md).

Used by the RSVP agent and by post-call housekeeping for:
* short classification of intent ("confirmed" / "declined" / "maybe" / ...)
* call summaries from raw transcripts
* transcript clean-up before persistence

We hit the Generative Language REST API directly with ``httpx`` so we do
not pull in the full ``google-genai`` SDK. Two endpoints are used:

* ``models/{name}:generateContent`` — single-shot prompt → text/JSON.
* (Optional) ``models/{name}:streamGenerateContent`` — not required here.

If ``GEMINI_API_KEY`` is missing the client returns ``None`` from every
call and logs a single warning. Voice routes treat that as "AI off".
"""
from __future__ import annotations

import json
import logging
from typing import Any, Optional

import httpx

from core import config

logger = logging.getLogger("nuru.voice.gemini.text")

GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta"


def gemini_text_available() -> bool:
    return bool((config.GEMINI_API_KEY or "").strip())


class GeminiTextClient:
    """Thin wrapper around Gemini REST ``generateContent``."""

    def __init__(
        self,
        *,
        model: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout: float = 20.0,
    ) -> None:
        self.model = (model or config.GEMINI_TEXT_MODEL or "gemini-2.5-flash").strip()
        self.api_key = (api_key or config.GEMINI_API_KEY or "").strip()
        self.timeout = timeout

    # ── low-level ──────────────────────────────────────────────
    def _post(self, body: dict) -> Optional[dict]:
        if not self.api_key:
            logger.warning("GEMINI_API_KEY not set; skipping Gemini text call")
            return None
        url = f"{GEMINI_API_BASE}/models/{self.model}:generateContent?key={self.api_key}"
        try:
            with httpx.Client(timeout=self.timeout) as client:
                resp = client.post(url, json=body, headers={"Content-Type": "application/json"})
        except Exception:  # noqa: BLE001
            logger.exception("Gemini text request failed")
            return None
        if resp.status_code >= 400:
            logger.warning("Gemini text %s -> %s %s",
                           self.model, resp.status_code, resp.text[:300])
            return None
        try:
            return resp.json()
        except ValueError:
            logger.warning("Gemini text returned non-JSON body")
            return None

    @staticmethod
    def _first_text(payload: Optional[dict]) -> Optional[str]:
        if not payload:
            return None
        try:
            cands = payload.get("candidates") or []
            if not cands:
                return None
            parts = (cands[0].get("content") or {}).get("parts") or []
            chunks = [p.get("text", "") for p in parts if isinstance(p, dict)]
            text = "".join(chunks).strip()
            return text or None
        except Exception:  # noqa: BLE001
            logger.exception("Failed to parse Gemini text response")
            return None

    # ── high-level helpers ─────────────────────────────────────
    def generate(
        self,
        prompt: str,
        *,
        system: Optional[str] = None,
        temperature: float = 0.4,
        max_output_tokens: int = 512,
    ) -> Optional[str]:
        body: dict[str, Any] = {
            "contents": [
                {"role": "user", "parts": [{"text": prompt}]},
            ],
            "generationConfig": {
                "temperature": temperature,
                "maxOutputTokens": max_output_tokens,
            },
        }
        if system:
            body["systemInstruction"] = {"parts": [{"text": system}]}
        return self._first_text(self._post(body))

    def generate_json(
        self,
        prompt: str,
        *,
        system: Optional[str] = None,
        schema: Optional[dict] = None,
        temperature: float = 0.1,
        max_output_tokens: int = 512,
    ) -> Optional[dict]:
        """Ask Gemini to return JSON. Returns parsed dict or ``None``."""
        body: dict[str, Any] = {
            "contents": [
                {"role": "user", "parts": [{"text": prompt}]},
            ],
            "generationConfig": {
                "temperature": temperature,
                "maxOutputTokens": max_output_tokens,
                "responseMimeType": "application/json",
            },
        }
        if schema:
            body["generationConfig"]["responseSchema"] = schema
        if system:
            body["systemInstruction"] = {"parts": [{"text": system}]}
        text = self._first_text(self._post(body))
        if not text:
            return None
        # Strip code fences if Gemini wraps the JSON.
        cleaned = text.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.strip("`")
            if cleaned.lower().startswith("json"):
                cleaned = cleaned[4:].lstrip()
        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            logger.warning("Gemini JSON response not parseable: %s", cleaned[:200])
            return None

    # ── convenience use-cases ──────────────────────────────────
    def summarise_call(self, transcript: str, *, language: str = "sw") -> Optional[str]:
        if not transcript.strip():
            return None
        sys_prompt = (
            "You write very short, neutral summaries of phone conversations "
            "between an AI assistant and an event guest. Respond in "
            f"{'Swahili' if language.startswith('sw') else 'English'}. "
            "Keep it under 40 words."
        )
        return self.generate(transcript, system=sys_prompt, temperature=0.2,
                             max_output_tokens=200)

    def classify_rsvp(self, transcript: str, *, language: str = "sw") -> Optional[dict]:
        if not transcript.strip():
            return None
        schema = {
            "type": "object",
            "properties": {
                "outcome": {"type": "string"},
                "confidence": {"type": "number"},
                "reason": {"type": "string"},
            },
            "required": ["outcome", "confidence"],
        }
        sys_prompt = (
            "You classify the RSVP outcome of a short phone call. Allowed "
            "outcomes: confirmed, declined, maybe, call_later, wrong_number, "
            "voicemail, no_response, opted_out. Return JSON with outcome, "
            "confidence (0-1) and a one-sentence reason."
        )
        prompt = f"Transcript (language={language}):\n\n{transcript}"
        return self.generate_json(prompt, system=sys_prompt, schema=schema)
