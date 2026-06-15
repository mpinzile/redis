"""Realtime Twilio Media Streams ↔ AI bridge (Phase 5 of nuru_voice.md).

This module owns the WebSocket lifecycle for one in-progress call. Twilio
connects to our ``/voice-calls/stream`` endpoint, and we:

1. Receive Twilio Media Streams JSON frames (``connected``, ``start``,
   ``media``, ``mark``, ``stop``).
2. Look up the matching ``VoiceCallJob`` via the ``job_id`` custom
   parameter we set in the TwiML.
3. Forward inbound audio to an ``AgentBridge`` (Gemini Live in Phase 6;
   silent stub here so Phase 5 can ship and be tested in isolation).
4. Stream the AI's audio back to Twilio, again as base64 mulaw frames.
5. Enforce ``VOICE_MAX_CALL_SECONDS`` and persist transcripts when
   ``VOICE_SAVE_TRANSCRIPTS`` is on.

Nothing here touches existing call/messaging code paths — it is a green-
field module under the ``voice`` package.
"""
from __future__ import annotations

import asyncio
import json
import logging
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, AsyncIterator, Awaitable, Callable, Optional

from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from core import config
from core.database import SessionLocal
from models import VoiceCallJob, VoiceCallLog
from voice.audio import (
    GEMINI_INPUT_RATE,
    GEMINI_OUTPUT_RATE,
    mulaw_b64_to_pcm16,
    pcm16_to_mulaw_b64,
)

logger = logging.getLogger("nuru.voice.realtime")


# ──────────────────────────────────────────────────────────────────
# Agent bridge contract (Phase 6 will provide a Gemini implementation)
# ──────────────────────────────────────────────────────────────────

@dataclass
class AgentEvent:
    """One thing the AI wants to emit back to the caller."""
    kind: str  # 'audio' | 'transcript' | 'tool_call' | 'end'
    audio_pcm16: Optional[bytes] = None
    text: Optional[str] = None
    role: Optional[str] = None  # 'user' | 'assistant'
    tool_call_id: Optional[str] = None
    tool_name: Optional[str] = None
    tool_args: Optional[dict] = None
    sample_rate: int = GEMINI_OUTPUT_RATE


class AgentBridge:
    """Abstract bridge to whatever realtime AI provider we use.

    Phase 5 ships with ``SilentAgentBridge`` (does nothing, useful for
    end-to-end smoke tests). Phase 6 swaps in ``GeminiLiveBridge`` and
    Phase 7 attaches the RSVP system prompt + tool executor.
    """

    async def start(self, *, job: VoiceCallJob, language: str) -> None:  # pragma: no cover
        raise NotImplementedError

    async def push_audio(self, pcm16: bytes, *, sample_rate: int) -> None:  # pragma: no cover
        raise NotImplementedError

    async def signal_end_of_user_speech(self) -> None:  # pragma: no cover - optional
        return None

    async def respond_to_tool_call(
        self, *, call_id: Optional[str], name: str, response: dict,
    ) -> None:  # pragma: no cover - optional
        return None

    async def stop(self) -> None:  # pragma: no cover
        raise NotImplementedError

    def events(self) -> AsyncIterator[AgentEvent]:  # pragma: no cover
        raise NotImplementedError


class SilentAgentBridge(AgentBridge):
    """No-op bridge used until Gemini Live wiring lands in Phase 6."""

    def __init__(self) -> None:
        self._queue: asyncio.Queue[Optional[AgentEvent]] = asyncio.Queue()
        self._started = False

    async def start(self, *, job: VoiceCallJob, language: str) -> None:
        self._started = True
        logger.info("SilentAgentBridge started for job=%s lang=%s", job.id, language)

    async def push_audio(self, pcm16: bytes, *, sample_rate: int) -> None:
        # Silently drop inbound audio. A real bridge forwards to Gemini.
        return None

    async def stop(self) -> None:
        if self._started:
            await self._queue.put(AgentEvent(kind="end"))
            self._started = False

    async def events(self) -> AsyncIterator[AgentEvent]:  # type: ignore[override]
        while True:
            evt = await self._queue.get()
            if evt is None:
                return
            yield evt
            if evt.kind == "end":
                return


# Hook point so Phase 6 can swap in Gemini without touching this file.
AgentBridgeFactory = Callable[[], AgentBridge]
_bridge_factory: AgentBridgeFactory = SilentAgentBridge


def register_agent_bridge_factory(factory: AgentBridgeFactory) -> None:
    """Phase 6 calls this to register the real Gemini Live bridge."""
    global _bridge_factory
    _bridge_factory = factory
    logger.info("Voice agent bridge factory registered: %s", factory.__name__)


def _new_bridge() -> AgentBridge:
    return _bridge_factory()


# ──────────────────────────────────────────────────────────────────
# Twilio Media Streams session
# ──────────────────────────────────────────────────────────────────

@dataclass
class StreamSession:
    websocket: WebSocket
    job_id: Optional[str] = None
    stream_sid: Optional[str] = None
    call_sid: Optional[str] = None
    language: str = "sw-KE"
    started_at: datetime = field(default_factory=datetime.utcnow)
    transcript_user: list[str] = field(default_factory=list)
    transcript_assistant: list[str] = field(default_factory=list)
    tool_calls: list[dict] = field(default_factory=list)
    ai_outcome: Optional[str] = None
    ai_confidence: Optional[float] = None
    summary: Optional[str] = None
    # Phase 11 — natural conversation quality counters
    interruption_count: int = 0
    silence_count: int = 0
    clarification_count: int = 0
    noise_detected: Optional[bool] = None
    detected_mood: Optional[str] = None
    conversation_quality: Optional[str] = None
    final_confidence: Optional[float] = None
    human_follow_up_reason: Optional[str] = None
    # transient: was the AI mid-utterance when the user started talking?
    assistant_speaking: bool = False

    def add_user_text(self, text: str) -> None:
        if not text:
            return
        self.transcript_user.append(text)
        # Barge-in: user speech arrived while assistant was speaking.
        if self.assistant_speaking:
            self.interruption_count += 1
            self.assistant_speaking = False
        # Cheap heuristic backstop for noise/clarification cues, in case
        # the AI never calls log_conversation_quality.
        try:
            from voice.agents.conversation import classify
            turn = classify(text)
            if turn.noise_detected:
                self.noise_detected = True
            if turn.intent in ("did_not_hear", "unclear"):
                self.clarification_count += 1
            if self.detected_mood in (None, "neutral") and turn.mood != "neutral":
                self.detected_mood = turn.mood
        except Exception:  # noqa: BLE001
            pass

    def add_assistant_text(self, text: str) -> None:
        if text:
            self.transcript_assistant.append(text)
            self.assistant_speaking = True

    def add_tool_call(self, name: str, args: dict) -> None:
        self.tool_calls.append({"name": name, "args": args,
                                "at": datetime.utcnow().isoformat()})

    def full_transcript(self) -> str:
        lines: list[str] = []
        if self.transcript_user:
            lines.append("USER: " + " ".join(self.transcript_user))
        if self.transcript_assistant:
            lines.append("ASSISTANT: " + " ".join(self.transcript_assistant))
        return "\n".join(lines).strip()


async def _send_media(ws: WebSocket, stream_sid: str, payload_b64: str) -> None:
    if not stream_sid or not payload_b64:
        return
    await ws.send_text(json.dumps({
        "event": "media",
        "streamSid": stream_sid,
        "media": {"payload": payload_b64},
    }))


async def _send_mark(ws: WebSocket, stream_sid: str, name: str) -> None:
    if not stream_sid:
        return
    await ws.send_text(json.dumps({
        "event": "mark",
        "streamSid": stream_sid,
        "mark": {"name": name},
    }))


async def _persist_session(session: StreamSession) -> None:
    """Update the latest VoiceCallLog row for this job with transcript + outcome."""
    if not session.job_id:
        return
    if not (config.VOICE_SAVE_TRANSCRIPTS or session.ai_outcome
            or session.summary or session.tool_calls):
        return
    db: Session = SessionLocal()
    try:
        log = (
            db.query(VoiceCallLog)
            .filter(VoiceCallLog.job_id == session.job_id)
            .order_by(VoiceCallLog.created_at.desc())
            .first()
        )
        if log is None:
            return
        if config.VOICE_SAVE_TRANSCRIPTS:
            transcript = session.full_transcript()
            if transcript:
                log.transcript = transcript
        if session.summary:
            log.summary = session.summary
        if session.ai_outcome:
            log.ai_outcome = session.ai_outcome
        if session.ai_confidence is not None:
            log.ai_confidence = session.ai_confidence
        if session.tool_calls:
            log.ai_tool_calls = session.tool_calls
        # Phase 11 — conversation quality backstop
        if session.detected_mood is not None:
            log.detected_mood = session.detected_mood
        if session.conversation_quality is not None:
            log.conversation_quality = session.conversation_quality
        if session.noise_detected is not None:
            log.noise_detected = session.noise_detected
        if session.interruption_count:
            log.interruption_count = session.interruption_count
        if session.silence_count:
            log.silence_count = session.silence_count
        if session.clarification_count:
            log.clarification_count = session.clarification_count
        if session.final_confidence is not None:
            log.final_confidence = session.final_confidence
        if session.human_follow_up_reason:
            log.human_follow_up_reason = session.human_follow_up_reason[:200]
        db.commit()
    except Exception:  # noqa: BLE001
        db.rollback()
        logger.exception("Failed to persist voice stream session for job=%s",
                         session.job_id)
    finally:
        db.close()


async def _pump_agent_events(
    session: StreamSession,
    bridge: AgentBridge,
    stop_event: asyncio.Event,
) -> None:
    """Forward audio/transcripts from the AI back to Twilio."""
    try:
        events = bridge.events()
        async for evt in events:  # type: ignore[union-attr]
            if stop_event.is_set():
                break
            if evt.kind == "audio" and evt.audio_pcm16:
                payload = pcm16_to_mulaw_b64(evt.audio_pcm16,
                                             source_rate=evt.sample_rate)
                await _send_media(session.websocket, session.stream_sid or "", payload)
            elif evt.kind == "transcript" and evt.text:
                if evt.role == "user":
                    session.add_user_text(evt.text)
                else:
                    session.add_assistant_text(evt.text)
            elif evt.kind == "tool_call":
                session.add_tool_call(evt.tool_name or "", evt.tool_args or {})
                # Execute the tool against backend services and ship the
                # result back to the model so the conversation can continue.
                try:
                    from voice.agents.rsvp_agent import execute_tool
                    result = await asyncio.to_thread(
                        execute_tool,
                        session.job_id, evt.tool_name or "", evt.tool_args or {},
                    )
                except Exception as exc:  # noqa: BLE001
                    logger.exception("Voice tool %s failed for job=%s",
                                     evt.tool_name, session.job_id)
                    result = {"ok": False, "error": str(exc)[:200]}
                # Persist outcome on the session so the post-call writer picks it up.
                if isinstance(result, dict):
                    outcome = result.get("outcome")
                    if isinstance(outcome, str):
                        session.ai_outcome = outcome
                    conf = result.get("confidence")
                    if isinstance(conf, (int, float)):
                        session.ai_confidence = float(conf)
                    summary = result.get("summary")
                    if isinstance(summary, str):
                        session.summary = summary
                try:
                    await bridge.respond_to_tool_call(
                        call_id=evt.tool_call_id,
                        name=evt.tool_name or "",
                        response=result if isinstance(result, dict) else {"ok": True},
                    )
                except Exception:  # noqa: BLE001
                    logger.exception("Sending tool response back to bridge failed")
            elif evt.kind == "end":
                break
    except asyncio.CancelledError:
        raise
    except Exception:  # noqa: BLE001
        logger.exception("Agent event pump crashed for job=%s", session.job_id)


def _resolve_job(job_id: Optional[str]) -> Optional[VoiceCallJob]:
    if not job_id:
        return None
    try:
        uuid.UUID(str(job_id))
    except (TypeError, ValueError):
        return None
    db: Session = SessionLocal()
    try:
        return db.query(VoiceCallJob).filter(VoiceCallJob.id == job_id).first()
    finally:
        db.close()


async def handle_twilio_stream(ws: WebSocket) -> None:
    """Main entry point for the FastAPI WebSocket route.

    The route accepts the socket; we own the rest of the lifecycle.
    """
    session = StreamSession(websocket=ws)
    bridge = _new_bridge()
    stop_event = asyncio.Event()
    pump_task: Optional[asyncio.Task] = None
    started = False
    max_seconds = max(15, int(config.VOICE_MAX_CALL_SECONDS or 60))
    deadline = asyncio.get_event_loop().time() + max_seconds

    try:
        while True:
            now = asyncio.get_event_loop().time()
            remaining = deadline - now
            if remaining <= 0:
                logger.info("Voice call exceeded VOICE_MAX_CALL_SECONDS, closing")
                break
            try:
                msg = await asyncio.wait_for(ws.receive_text(), timeout=remaining)
            except asyncio.TimeoutError:
                break
            except WebSocketDisconnect:
                break

            try:
                frame = json.loads(msg)
            except json.JSONDecodeError:
                continue
            event = frame.get("event")

            if event == "connected":
                continue

            if event == "start":
                start = frame.get("start") or {}
                session.stream_sid = frame.get("streamSid") or start.get("streamSid")
                session.call_sid = start.get("callSid")
                params = start.get("customParameters") or {}
                session.job_id = params.get("job_id") or session.job_id
                session.language = params.get("language") or session.language
                job = _resolve_job(session.job_id)
                await bridge.start(job=job, language=session.language)  # type: ignore[arg-type]
                pump_task = asyncio.create_task(
                    _pump_agent_events(session, bridge, stop_event)
                )
                started = True
                continue

            if event == "media" and started:
                payload = (frame.get("media") or {}).get("payload") or ""
                pcm = mulaw_b64_to_pcm16(payload, target_rate=GEMINI_INPUT_RATE)
                if pcm:
                    await bridge.push_audio(pcm, sample_rate=GEMINI_INPUT_RATE)
                continue

            if event == "mark":
                continue

            if event == "stop":
                break

    except WebSocketDisconnect:
        logger.info("Twilio stream disconnected job=%s", session.job_id)
    except Exception:  # noqa: BLE001
        logger.exception("Voice stream handler crashed job=%s", session.job_id)
    finally:
        stop_event.set()
        try:
            await bridge.stop()
        except Exception:  # noqa: BLE001
            logger.exception("Bridge stop failed for job=%s", session.job_id)
        if pump_task is not None:
            pump_task.cancel()
            try:
                await pump_task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
        try:
            await _persist_session(session)
        except Exception:  # noqa: BLE001
            logger.exception("Persist session failed job=%s", session.job_id)
        try:
            await ws.close()
        except Exception:  # noqa: BLE001
            pass
