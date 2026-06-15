"""Gemini Live realtime audio bridge (Phase 6 of nuru_voice.md).

Implements the ``AgentBridge`` contract from ``voice.realtime`` against
Google's Gemini Live API. The Live API is a bidirectional WebSocket that
accepts PCM16 input chunks and emits PCM16 output chunks plus partial
text transcripts and tool calls.

This module deliberately keeps the wire protocol minimal:

* Connect to ``wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage
  .v1beta.GenerativeService.BidiGenerateContent?key=API_KEY``.
* Send a setup frame describing the model, voice, and tools.
* Stream user audio with ``{"realtime_input": {"audio": {...}}}``
  (the ``media_chunks`` field was deprecated by Gemini Live in 2025).
* Read ``serverContent`` frames and translate them into ``AgentEvent``s.

Falls back to ``GEMINI_LIVE_MODEL_FALLBACK`` if the primary model rejects
the setup. If ``GEMINI_API_KEY`` is missing we simply do not install the
bridge factory and Phase 5's ``SilentAgentBridge`` continues to be used.

The actual RSVP system prompt and tool schema live in
``voice.agents.rsvp_agent`` (Phase 7). This file only owns transport.
"""
from __future__ import annotations

import asyncio
import base64
import json
import logging
from typing import Any, AsyncIterator, Awaitable, Callable, Optional

from core import config
from models import VoiceCallJob
from voice.audio import GEMINI_INPUT_RATE, GEMINI_OUTPUT_RATE
from voice.realtime import AgentBridge, AgentEvent, register_agent_bridge_factory

logger = logging.getLogger("nuru.voice.gemini.live")

try:
    import websockets  # type: ignore
    from websockets.exceptions import ConnectionClosed  # type: ignore
    _HAVE_WEBSOCKETS = True
except Exception:  # noqa: BLE001
    websockets = None  # type: ignore
    ConnectionClosed = Exception  # type: ignore
    _HAVE_WEBSOCKETS = False


GEMINI_LIVE_BASE = (
    "wss://generativelanguage.googleapis.com/ws/"
    "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
)


# Phase 7 will overwrite this with a real (system_prompt, tools) builder.
SystemBuilder = Callable[[Optional[VoiceCallJob], str], dict]


def _default_system_builder(job: Optional[VoiceCallJob], language: str) -> dict:
    """Tiny safe default until ``voice.agents.rsvp_agent`` plugs in."""
    name = (job.recipient_name if job else None) or "rafiki"
    lang_name = "English" if (language or "sw").lower().startswith("en") else "Swahili"
    text = (
        f"You are the Nuru Voice Assistant calling {name} to confirm their RSVP. "
        "Speak natural Tanzanian Swahili by default. Do not speak English unless "
        "the recipient explicitly asks for English. "
        f"Selected call language: {lang_name}. Be polite, short, and natural. Confirm attendance, "
        "then end the call gracefully."
    )
    return {"system_text": text, "tools": []}


_system_builder: SystemBuilder = _default_system_builder


def set_system_builder(builder: SystemBuilder) -> None:
    """Hook used by Phase 7 to inject the RSVP system prompt + tool schema."""
    global _system_builder
    _system_builder = builder


def gemini_live_available() -> bool:
    return bool((config.GEMINI_API_KEY or "").strip()) and _HAVE_WEBSOCKETS


class GeminiLiveBridge(AgentBridge):
    """Realtime bridge into Gemini Live. One instance per call."""

    def __init__(self) -> None:
        self._ws = None  # type: ignore[var-annotated]
        self._events: asyncio.Queue[Optional[AgentEvent]] = asyncio.Queue()
        self._reader_task: Optional[asyncio.Task] = None
        self._closed = False
        self._connect_lock = asyncio.Lock()

    # ── helpers ────────────────────────────────────────────────
    @staticmethod
    def _setup_frame(
        model: str,
        voice: str,
        system_text: str,
        tools: list,
        language: str = "sw",
    ) -> dict:
        lang = (language or "sw").lower()
        if lang.startswith("sw"):
            language_code = "sw-TZ"
        elif lang.startswith("en"):
            language_code = "en-US"
        else:
            language_code = lang
        frame: dict[str, Any] = {
            "setup": {
                "model": f"models/{model}",
                "generation_config": {
                    "response_modalities": ["AUDIO"],
                    "speech_config": {
                        "language_code": language_code,
                        "voice_config": {
                            "prebuilt_voice_config": {"voice_name": voice or "Zephyr"},
                        },
                    },
                },
            }
        }
        if system_text:
            frame["setup"]["system_instruction"] = {
                "parts": [{"text": system_text}],
            }
        if tools:
            frame["setup"]["tools"] = tools
        return frame

    async def _connect(self, model: str, setup: dict) -> bool:
        url = f"{GEMINI_LIVE_BASE}?key={config.GEMINI_API_KEY}"
        try:
            self._ws = await asyncio.wait_for(
                websockets.connect(  # type: ignore[union-attr]
                    url, max_size=4 * 1024 * 1024,
                    ping_interval=20, ping_timeout=20,
                    open_timeout=5,
                ),
                timeout=5.0,
            )
        except asyncio.TimeoutError:
            logger.error("Gemini Live connect timed out (>5s) model=%s", model)
            return False
        except Exception:  # noqa: BLE001
            logger.exception("Gemini Live connect failed model=%s", model)
            return False
        try:
            await self._ws.send(json.dumps(setup))
        except Exception:  # noqa: BLE001
            logger.exception("Gemini Live send setup failed model=%s", model)
            await self._safe_close_ws()
            return False
        return True

    async def _safe_close_ws(self) -> None:
        ws = self._ws
        self._ws = None
        if ws is None:
            return
        try:
            await ws.close()
        except Exception:  # noqa: BLE001
            pass

    async def _send_initial_turn(self, language: str, job: Optional[VoiceCallJob]) -> None:
        """Prompt Gemini to speak first as soon as Twilio opens the stream."""
        if self._ws is None or self._closed:
            return
        is_sw = (language or "sw").lower().startswith("sw")
        raw_name = (getattr(job, "recipient_name", None) or "").strip()
        # Mirror rsvp_agent's address rules so the title/first-name lands correctly
        # in the greeting (e.g. "Mr Frank" -> "Bw. Frank"; "David Mwakalinga" -> "David").
        try:
            from voice.agents.rsvp_agent import _address_for  # local import to avoid cycle
            addressed, _ = _address_for(raw_name, is_sw=is_sw)
        except Exception:  # noqa: BLE001
            addressed = raw_name or ("mgeni" if is_sw else "the guest")
        event_name = "tukio"
        try:
            from voice.agents.rsvp_agent import _event_name_for_job  # local import to avoid cycle
            event_name = _event_name_for_job(job) or event_name
        except Exception:  # noqa: BLE001
            pass
        text = (
            f"Anza simu SASA kwa KISWAHILI CHA TANZANIA kwa sentensi hii: "
            f"'Habari, napiga kutoka Nuru kwa niaba ya mratibu wa tukio la {event_name}. "
            f"Ningependa kuthibitisha kama utahudhuria.' Kisha uliza kama amepokea mwaliko "
            f"kupitia WhatsApp au ujumbe wa kawaida. FUATA mtiririko wa "
            f"simu uliopo kwenye system_instruction (mwanzo → uthibitisho "
            f"wa mwaliko → swali la kuhudhuria → taarifa za tukio → "
            f"kufunga). Ongea kwa kasi ya kawaida ya simu ya Mtanzania "
            f"(haraka kidogo, siyo polepole), sauti ya joto na ya "
            f"kibinadamu. LUGHA: anza Kiswahili, lakini IFUATE lugha ya "
            f"mteja. Speak natural Tanzanian Swahili by default. Do not speak English unless "
            f"the recipient explicitly asks for English. Akisema 'speak English', "
            f"'sijakuelewa' / 'I don't understand' akiwa kwenye Kiingereza, BADILISHA Kiingereza "
            f"mara moja na rudia jibu lako. Akirudi Kiswahili, rudi "
            f"Kiswahili. Akisema 'kwaheri' / 'bye' / 'tutaonana', funga "
            f"mara moja: 'Asante sana, kwaheri.' Usitumie 'rafiki' kama "
            f"jina lipo, wala 'Shalom'."
            if is_sw else
            f"Start the call NOW in English. Greet {addressed} in one "
            f"short sentence, say you're calling from Nuru on behalf of "
            f"the organiser, then ask if they received the invitation on "
            f"WhatsApp or SMS. FOLLOW the call flow in the "
            f"system_instruction (opening → invitation check → attendance "
            f"→ event facts → closing). Use a brisk, natural phone pace, "
            f"warm human tone. LANGUAGE: start in English but MIRROR the "
            f"recipient — if they speak a full sentence in Swahili or say "
            f"'sijakuelewa' / 'I don't understand', switch to Swahili "
            f"immediately and repeat your last sentence. If they return "
            f"to English, switch back. End on 'bye' / 'kwaheri' with "
            f"'Thank you, goodbye.'"
        )
        try:
            await self._ws.send(json.dumps({
                "clientContent": {
                    "turns": [{"role": "user", "parts": [{"text": text}]}],
                    "turnComplete": True,
                }
            }))
            logger.info("Gemini Live initial turn sent job=%s", getattr(job, "id", None))
        except Exception:  # noqa: BLE001
            logger.exception("Gemini Live initial turn send failed job=%s", getattr(job, "id", None))

    # ── AgentBridge contract ───────────────────────────────────
    async def start(self, *, job: Optional[VoiceCallJob], language: str) -> None:
        if not gemini_live_available():
            logger.warning("GeminiLiveBridge requested but not available; no-op")
            await self._events.put(AgentEvent(kind="end"))
            return

        lang = "en-US" if (language or "").strip().lower().startswith("en") else "sw-TZ"
        # System prompt build hits the DB (event + schedule + venue). Run it
        # off the event loop so we don't stall the Twilio WS receive while
        # SQLAlchemy is rebuilding the prompt.
        spec = await asyncio.to_thread(_system_builder, job, lang) or {}
        system_text = (spec.get("system_text") or "").strip()
        tools = spec.get("tools") or []
        voice_cfg = config.get_gemini_voice_config()
        model_cfg = config.get_gemini_model_config()
        voice_name = (voice_cfg.get("voice_name") or "Zephyr").strip() or "Zephyr"

        # Backend-controlled config log (no secrets).
        logger.info(
            "Smart RSVP Gemini config: text_model=%s live_model=%s "
            "live_model_fallback=%s tts_model=%s voice=%s language=%s "
            "style=%s speaking_rate=%s",
            model_cfg["text_model"], model_cfg["live_model"],
            model_cfg["live_model_fallback"], model_cfg["tts_model"],
            voice_name, voice_cfg["language"], voice_cfg["style"],
            voice_cfg["speaking_rate"],
        )

        async with self._connect_lock:
            primary = (model_cfg["live_model"] or "").strip()
            fallback = (model_cfg["live_model_fallback"] or "").strip()
            tried: list[str] = []
            for model in [m for m in (primary, fallback) if m]:
                tried.append(model)
                setup = self._setup_frame(model, voice_name, system_text, tools, lang)
                if await self._connect(model, setup):
                    logger.info("Gemini Live connected model=%s voice=%s job=%s",
                                model, voice_name, getattr(job, "id", None))
                    self._reader_task = asyncio.create_task(self._read_loop())
                    await self._send_initial_turn(lang, job)
                    return
            logger.error(
                "Gemini Live: all models failed to connect (tried=%s). "
                "Check GEMINI_LIVE_MODEL / GEMINI_LIVE_MODEL_FALLBACK env vars.",
                tried,
            )
            await self._events.put(AgentEvent(kind="end"))

    async def push_audio(self, pcm16: bytes, *, sample_rate: int) -> None:
        # Skip work cheaply if the bridge is closed or the socket is gone.
        if self._ws is None or self._closed or not pcm16:
            return
        try:
            payload = base64.b64encode(pcm16).decode("ascii")
            # Gemini Live v1beta (Sept 2025+) replaced
            # `realtime_input.media_chunks[...]` with a single
            # `realtime_input.audio { data, mime_type }` field. Sending the
            # deprecated shape causes Gemini to close the WebSocket with:
            #   "realtime_input.media_chunks is deprecated. Use audio,
            #    video, or text instead."
            frame = {
                "realtime_input": {
                    "audio": {
                        "mime_type": f"audio/pcm;rate={sample_rate or GEMINI_INPUT_RATE}",
                        "data": payload,
                    }
                }
            }
            await self._ws.send(json.dumps(frame))
        except ConnectionClosed:
            # Gemini hung up — stop forwarding audio and surface a single
            # "ai stream failed" end event instead of spamming the log.
            if not self._closed:
                logger.warning("Gemini Live WebSocket closed; stopping audio forwarding")
                self._closed = True
                await self._safe_close_ws()
                await self._events.put(AgentEvent(
                    kind="transcript", role="system",
                    text="ai stream failed: gemini websocket closed",
                ))
                await self._events.put(AgentEvent(kind="end"))
        except Exception:  # noqa: BLE001
            # Mark closed on the first unexpected send failure so we don't
            # log the same traceback for every subsequent 20ms frame.
            if not self._closed:
                logger.exception("Gemini Live push_audio failed; stopping forwarding")
                self._closed = True
                await self._safe_close_ws()
                await self._events.put(AgentEvent(kind="end"))

    async def stop(self) -> None:
        if self._closed:
            return
        self._closed = True
        await self._safe_close_ws()
        if self._reader_task is not None:
            self._reader_task.cancel()
            try:
                await self._reader_task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
        await self._events.put(AgentEvent(kind="end"))

    async def respond_to_tool_call(
        self, *, call_id: Optional[str], name: str, response: dict,
    ) -> None:
        if self._ws is None or self._closed:
            return
        fn_resp: dict[str, Any] = {"name": name or "", "response": response or {}}
        if call_id:
            fn_resp["id"] = call_id
        try:
            await self._ws.send(json.dumps({
                "toolResponse": {"functionResponses": [fn_resp]},
            }))
        except Exception:  # noqa: BLE001
            logger.exception("Gemini Live tool response send failed")

    async def events(self) -> AsyncIterator[AgentEvent]:  # type: ignore[override]
        while True:
            evt = await self._events.get()
            if evt is None:
                return
            yield evt
            if evt.kind == "end":
                return

    # ── read pump ─────────────────────────────────────────────
    async def _read_loop(self) -> None:
        ws = self._ws
        if ws is None:
            return
        try:
            async for raw in ws:
                if self._closed:
                    break
                try:
                    msg = json.loads(raw)
                except Exception:  # noqa: BLE001
                    continue
                await self._handle_server_frame(msg)
        except ConnectionClosed:
            pass
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            logger.exception("Gemini Live read loop crashed")
        finally:
            await self._events.put(AgentEvent(kind="end"))

    async def _handle_server_frame(self, msg: dict) -> None:
        # Tool calls — executed by realtime.py against backend services.
        tool_call = msg.get("toolCall") or msg.get("tool_call")
        if tool_call:
            for fn in tool_call.get("functionCalls") or tool_call.get("function_calls") or []:
                name = fn.get("name") or ""
                args = fn.get("args") or {}
                call_id = fn.get("id") or fn.get("callId") or fn.get("call_id")
                await self._events.put(AgentEvent(
                    kind="tool_call", tool_name=name, tool_args=args,
                    tool_call_id=call_id,
                ))
            return

        sc = msg.get("serverContent") or msg.get("server_content") or {}
        if not sc:
            return

        # Partial / completed model turn — extract audio + text.
        model_turn = sc.get("modelTurn") or sc.get("model_turn") or {}
        for part in model_turn.get("parts") or []:
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                try:
                    pcm = base64.b64decode(inline["data"])
                except Exception:  # noqa: BLE001
                    pcm = b""
                if pcm:
                    await self._events.put(AgentEvent(
                        kind="audio", audio_pcm16=pcm,
                        sample_rate=GEMINI_OUTPUT_RATE,
                    ))
            text = part.get("text")
            if text:
                await self._events.put(AgentEvent(
                    kind="transcript", role="assistant", text=text,
                ))

        # User-side transcript (input transcription).
        in_tx = sc.get("inputTranscription") or sc.get("input_transcription")
        if in_tx and in_tx.get("text"):
            await self._events.put(AgentEvent(
                kind="transcript", role="user", text=in_tx["text"],
            ))

        out_tx = sc.get("outputTranscription") or sc.get("output_transcription")
        if out_tx and out_tx.get("text"):
            await self._events.put(AgentEvent(
                kind="transcript", role="assistant", text=out_tx["text"],
            ))

        if sc.get("turnComplete") or sc.get("turn_complete"):
            # Nothing to do — Twilio keeps the audio channel open.
            return


def install() -> bool:
    """Install ``GeminiLiveBridge`` as the realtime AgentBridge factory.

    Safe to call repeatedly. Returns ``True`` when the bridge was actually
    installed (i.e. API key present and ``websockets`` available).
    """
    if not gemini_live_available():
        logger.info("Gemini Live not available (missing API key or websockets); "
                    "keeping SilentAgentBridge")
        return False
    register_agent_bridge_factory(GeminiLiveBridge)
    return True
