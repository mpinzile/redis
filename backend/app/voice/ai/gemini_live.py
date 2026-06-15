"""Gemini Live realtime audio bridge (Phase 6 of nuru_voice.md).

Implements the ``AgentBridge`` contract from ``voice.realtime`` against
Google's Gemini Live API. The Live API is a bidirectional WebSocket that
accepts PCM16 input chunks and emits PCM16 output chunks plus partial
text transcripts and tool calls.

This module deliberately keeps the wire protocol minimal:

* Connect to ``wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage
  .v1beta.GenerativeService.BidiGenerateContent?key=API_KEY``.
* Send a setup frame describing the model, voice, and tools.
* Stream user audio with ``{"realtime_input": {"media_chunks": [...]}}``.
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
    lang_name = "Swahili" if (language or "sw").lower().startswith("sw") else "English"
    text = (
        f"You are the Nuru Voice Assistant calling {name} to confirm their RSVP. "
        f"Speak {lang_name}. Be polite, short, and natural. Confirm attendance, "
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
    def _setup_frame(model: str, voice: str, system_text: str, tools: list) -> dict:
        frame: dict[str, Any] = {
            "setup": {
                "model": f"models/{model}",
                "generation_config": {
                    "response_modalities": ["AUDIO"],
                    "speech_config": {
                        "voice_config": {
                            "prebuilt_voice_config": {"voice_name": voice or "Aoede"},
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
            self._ws = await websockets.connect(  # type: ignore[union-attr]
                url, max_size=4 * 1024 * 1024, ping_interval=20, ping_timeout=20,
            )
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

    # ── AgentBridge contract ───────────────────────────────────
    async def start(self, *, job: Optional[VoiceCallJob], language: str) -> None:
        if not gemini_live_available():
            logger.warning("GeminiLiveBridge requested but not available; no-op")
            await self._events.put(AgentEvent(kind="end"))
            return

        lang = (language or config.VOICE_DEFAULT_LANGUAGE or "sw").strip()
        spec = _system_builder(job, lang) or {}
        system_text = (spec.get("system_text") or "").strip()
        tools = spec.get("tools") or []
        voice_name = (config.GEMINI_VOICE_NAME or "Aoede").strip() or "Aoede"

        async with self._connect_lock:
            primary = (config.GEMINI_LIVE_MODEL or "").strip()
            fallback = (config.GEMINI_LIVE_MODEL_FALLBACK or "").strip()
            for model in [m for m in (primary, fallback) if m]:
                setup = self._setup_frame(model, voice_name, system_text, tools)
                if await self._connect(model, setup):
                    logger.info("Gemini Live connected model=%s job=%s",
                                model, getattr(job, "id", None))
                    self._reader_task = asyncio.create_task(self._read_loop())
                    return
            logger.error("Gemini Live: all models failed to connect")
            await self._events.put(AgentEvent(kind="end"))

    async def push_audio(self, pcm16: bytes, *, sample_rate: int) -> None:
        if self._ws is None or self._closed or not pcm16:
            return
        try:
            payload = base64.b64encode(pcm16).decode("ascii")
            frame = {
                "realtime_input": {
                    "media_chunks": [
                        {
                            "mime_type": f"audio/pcm;rate={sample_rate or GEMINI_INPUT_RATE}",
                            "data": payload,
                        }
                    ]
                }
            }
            await self._ws.send(json.dumps(frame))
        except Exception:  # noqa: BLE001
            logger.exception("Gemini Live push_audio failed")

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
