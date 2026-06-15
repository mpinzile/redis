"""RSVP voice agent (Phase 7 of nuru_voice.md).

Three concerns live here:

1. ``build_rsvp_spec(job, language)`` — produces the system prompt and the
   Gemini Live tool schema for one call. Pulled in at session start by
   ``voice.ai.gemini_live`` via ``set_system_builder``.
2. ``execute_tool(job_id, name, args)`` — runs a tool call against the
   real backend (``EventInvitation``, ``EventAttendee``, ``VoiceOptOut``,
   ``VoiceCallJob``) and returns a small JSON-able dict that Gemini Live
   gets as the tool response.
3. ``install_rsvp_agent()`` — wires both into the realtime stack. Safe to
   call repeatedly.

Existing RSVP/Guest APIs are NOT touched; we update the same columns the
web/mobile UI uses (``rsvp_status``, ``rsvp_at``) via the ORM.
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime
from typing import Any, Optional

from core.database import SessionLocal
from models import (
    EventAttendee, EventInvitation, Event,
    RSVPStatusEnum,
    VoiceCallJob, VoiceCallLog, VoiceOptOut,
)
from voice.agents.conversation import (
    MOODS, QUALITIES,
    NATURAL_CONVERSATION_RULES_SW, NATURAL_CONVERSATION_RULES_EN,
)
from voice.timezone import resolve_timezone

logger = logging.getLogger("nuru.voice.rsvp_agent")


_ALLOWED_RSVP = {"confirmed", "declined", "maybe", "call_later",
                 "wrong_number", "voicemail"}


# ──────────────────────────────────────────────────────────────────
# System prompt + tool schema for Gemini Live
# ──────────────────────────────────────────────────────────────────

def _event_brief(event: Optional[Event]) -> str:
    if event is None:
        return "an upcoming event"
    name = (getattr(event, "name", None) or "the event").strip()
    starts = getattr(event, "event_date", None) or getattr(event, "start_date", None)
    when_part = ""
    if starts:
        try:
            when_part = f" on {starts.strftime('%A, %d %B %Y')}"
        except Exception:  # noqa: BLE001
            when_part = ""
    location = (getattr(event, "location", None) or "").strip()
    where_part = f" at {location}" if location else ""
    return f"{name}{when_part}{where_part}".strip()


def build_rsvp_spec(job: Optional[VoiceCallJob], language: str) -> dict:
    """Return ``{system_text, tools}`` for the Gemini Live setup frame."""
    lang = (language or "sw").lower()
    is_sw = lang.startswith("sw")
    recipient = (getattr(job, "recipient_name", None) or "").strip() or (
        "rafiki" if is_sw else "there"
    )
    event_text = "the event"
    if job is not None and job.campaign_id:
        db = SessionLocal()
        try:
            from models import VoiceCampaign  # local import to avoid cycle
            camp = db.query(VoiceCampaign).filter(
                VoiceCampaign.id == job.campaign_id
            ).first()
            if camp and camp.event_id:
                ev = db.query(Event).filter(Event.id == camp.event_id).first()
                event_text = _event_brief(ev)
        except Exception:  # noqa: BLE001
            logger.exception("Failed to load event context for job=%s", job.id)
        finally:
            db.close()

    if is_sw:
        system_text = (
            "Wewe ni Msaidizi wa Sauti wa Nuru. Unampigia "
            f"{recipient} kuhusu mwaliko wa {event_text}. "
            "Sema Kiswahili rahisi, kifupi na cha heshima. "
            "Lengo: thibitisha kama atahudhuria (ndiyo, hapana, labda). "
            "Ukijibiwa wazi, tumia tool save_rsvp na uthibitishe kwa upole. "
            "Akiomba usimpigie tena, tumia mark_opt_out. "
            "Akiomba apigiwe baadaye au yu busy, tumia request_callback. "
            "Akiomba WhatsApp au mtandao mbovu/kelele, tumia "
            "request_whatsapp_followup. Jibu likiwa halieleweki baada ya "
            "swali moja la uthibitisho, tumia mark_human_follow_up. "
            "Mwishoni mwa simu tumia log_conversation_quality. "
            "Usitoe taarifa za malipo, usidai pesa, usichukue muda mrefu.\n\n"
            + NATURAL_CONVERSATION_RULES_SW
        )
    else:
        system_text = (
            "You are the Nuru Voice Assistant. You're calling "
            f"{recipient} about their invitation to {event_text}. "
            "Speak simple, short, warm English. "
            "Goal: confirm whether they will attend (yes, no, maybe). "
            "When clearly answered, call save_rsvp and confirm politely. "
            "If they ask not to be called again, call mark_opt_out. "
            "If they're busy or ask for a later call, call request_callback. "
            "If they ask for WhatsApp or there's bad signal/noise, call "
            "request_whatsapp_followup. If still unclear after one short "
            "confirmation question, call mark_human_follow_up. "
            "At the end of every call, call log_conversation_quality. "
            "Never request payment details or extend the conversation.\n\n"
            + NATURAL_CONVERSATION_RULES_EN
        )

    # Gemini Live tools — function declarations (camelCase per the API).
    tools = [{
        "functionDeclarations": [
            {
                "name": "save_rsvp",
                "description": (
                    "Record the recipient's RSVP for this event. Call this "
                    "once you have a clear answer."
                ),
                "parameters": {
                    "type": "OBJECT",
                    "properties": {
                        "status": {
                            "type": "STRING",
                            "description": "RSVP outcome.",
                            "enum": sorted(_ALLOWED_RSVP),
                        },
                        "notes": {
                            "type": "STRING",
                            "description": "Optional short note from the caller.",
                        },
                        "confidence": {
                            "type": "NUMBER",
                            "description": "How confident you are, 0 to 1.",
                        },
                    },
                    "required": ["status"],
                },
            },
            {
                "name": "mark_opt_out",
                "description": (
                    "Add this recipient to the global do-not-call list. "
                    "Call this if they explicitly ask not to be called again."
                ),
                "parameters": {
                    "type": "OBJECT",
                    "properties": {
                        "reason": {
                            "type": "STRING",
                            "description": "Short reason in the recipient's words.",
                        },
                    },
                },
            },
            {
                "name": "escalate_to_human",
                "description": (
                    "Hand off to a human organiser when the situation is "
                    "outside your scope (complaint, confusion, sensitive issue)."
                ),
                "parameters": {
                    "type": "OBJECT",
                    "properties": {
                        "reason": {
                            "type": "STRING",
                            "description": "Why a human follow-up is needed.",
                        },
                    },
                    "required": ["reason"],
                },
            },
            {
                "name": "request_callback",
                "description": (
                    "Recipient is busy or asked to be called later. Record "
                    "their preferred time so the campaign can retry."
                ),
                "parameters": {
                    "type": "OBJECT",
                    "properties": {
                        "preferred_time": {
                            "type": "STRING",
                            "description": (
                                "Free text like 'jioni', 'kesho asubuhi', "
                                "or an ISO timestamp if given."
                            ),
                        },
                        "reason": {"type": "STRING"},
                    },
                },
            },
            {
                "name": "request_whatsapp_followup",
                "description": (
                    "Recipient asked for WhatsApp, can't hear, or is in a "
                    "noisy environment. Queue a WhatsApp follow-up."
                ),
                "parameters": {
                    "type": "OBJECT",
                    "properties": {
                        "reason": {"type": "STRING"},
                    },
                },
            },
            {
                "name": "mark_human_follow_up",
                "description": (
                    "Recipient's intent is still unclear after one short "
                    "confirmation question, or they explicitly asked for a "
                    "human. Mark the job for organiser follow-up."
                ),
                "parameters": {
                    "type": "OBJECT",
                    "properties": {
                        "reason": {
                            "type": "STRING",
                            "description": (
                                "Why human follow-up is needed (e.g. "
                                "'recipient_could_not_hear', 'no_clear_response', "
                                "'human_requested')."
                            ),
                        },
                    },
                    "required": ["reason"],
                },
            },
            {
                "name": "log_conversation_quality",
                "description": (
                    "Call this at the end of the conversation to record how "
                    "the call went. Always call this exactly once before "
                    "hanging up."
                ),
                "parameters": {
                    "type": "OBJECT",
                    "properties": {
                        "detected_mood": {
                            "type": "STRING", "enum": list(MOODS),
                        },
                        "conversation_quality": {
                            "type": "STRING", "enum": list(QUALITIES),
                        },
                        "noise_detected": {"type": "BOOLEAN"},
                        "interruption_count": {"type": "INTEGER"},
                        "silence_count": {"type": "INTEGER"},
                        "clarification_count": {"type": "INTEGER"},
                        "final_confidence": {
                            "type": "NUMBER",
                            "description": "Overall confidence 0..1.",
                        },
                    },
                },
            },
        ]
    }]

    return {"system_text": system_text, "tools": tools}


# ──────────────────────────────────────────────────────────────────
# Tool executors (sync; called via asyncio.to_thread from realtime.py)
# ──────────────────────────────────────────────────────────────────

def _resolve_status(raw: Any) -> Optional[str]:
    if not isinstance(raw, str):
        return None
    s = raw.strip().lower()
    return s if s in _ALLOWED_RSVP else None


def _to_db_enum(status: str) -> Optional[RSVPStatusEnum]:
    return {
        "confirmed": RSVPStatusEnum.confirmed,
        "declined": RSVPStatusEnum.declined,
        "maybe": RSVPStatusEnum.maybe,
    }.get(status)


def _job(db, job_id: Optional[str]) -> Optional[VoiceCallJob]:
    if not job_id:
        return None
    try:
        uuid.UUID(str(job_id))
    except (TypeError, ValueError):
        return None
    return db.query(VoiceCallJob).filter(VoiceCallJob.id == job_id).first()


def _update_guest_records(db, job: VoiceCallJob, status: str,
                          notes: Optional[str]) -> int:
    """Best-effort write to event_invitations / event_attendees.

    We match by recipient_ref_id when set, otherwise by phone tail.
    Returns the number of rows updated.
    """
    db_enum = _to_db_enum(status)
    if db_enum is None:
        return 0
    updated = 0
    ref = job.recipient_ref_id

    # Invitations
    try:
        q = db.query(EventInvitation)
        if ref:
            inv = q.filter(EventInvitation.id == ref).first()
            if inv is not None:
                inv.rsvp_status = db_enum
                inv.rsvp_at = datetime.utcnow()
                if notes:
                    inv.notes = (notes or "").strip()[:1000]
                updated += 1
    except Exception:  # noqa: BLE001
        logger.exception("Updating EventInvitation from voice tool failed")

    # Attendees
    try:
        att_q = db.query(EventAttendee)
        if ref:
            att = att_q.filter(EventAttendee.id == ref).first()
            if att is not None:
                att.rsvp_status = db_enum
                if notes:
                    att.special_requests = (notes or "").strip()[:1000]
                updated += 1
        elif job.phone_e164:
            tail = job.phone_e164.lstrip("+")[-9:]
            if tail:
                rows = att_q.filter(EventAttendee.guest_phone.ilike(f"%{tail}")).all()
                for att in rows:
                    att.rsvp_status = db_enum
                    updated += 1
    except Exception:  # noqa: BLE001
        logger.exception("Updating EventAttendee from voice tool failed")

    return updated


def _tool_save_rsvp(job_id: Optional[str], args: dict) -> dict:
    status = _resolve_status(args.get("status"))
    if not status:
        return {"ok": False, "error": "invalid_status",
                "message": "status must be one of " + ", ".join(sorted(_ALLOWED_RSVP))}
    notes = args.get("notes") if isinstance(args.get("notes"), str) else None
    confidence = args.get("confidence")
    try:
        confidence = float(confidence) if confidence is not None else None
    except (TypeError, ValueError):
        confidence = None

    db = SessionLocal()
    try:
        job = _job(db, job_id)
        updated_guests = 0
        if job is not None:
            job.ai_outcome = status
            if confidence is not None:
                job.ai_confidence = max(0.0, min(1.0, confidence))
            if notes:
                job.summary = notes.strip()[:1000]
            # Terminal states close the job; soft states schedule retry.
            if status in {"confirmed", "declined"}:
                job.status = "completed"
                job.next_retry_at = None
            elif status in {"maybe", "wrong_number"}:
                job.status = "completed"
                job.next_retry_at = None
            elif status == "call_later":
                job.status = "no_answer"
            elif status == "voicemail":
                job.status = "no_answer"
            updated_guests = _update_guest_records(db, job, status, notes)
        db.commit()
        return {
            "ok": True,
            "outcome": status,
            "confidence": confidence,
            "summary": notes or f"RSVP recorded as {status}",
            "guests_updated": updated_guests,
        }
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        logger.exception("save_rsvp failed for job=%s", job_id)
        return {"ok": False, "error": "db_error", "message": str(exc)[:200]}
    finally:
        db.close()


def _tool_mark_opt_out(job_id: Optional[str], args: dict) -> dict:
    db = SessionLocal()
    try:
        job = _job(db, job_id)
        if job is None or not job.phone_e164:
            return {"ok": False, "error": "no_phone"}
        reason = args.get("reason") if isinstance(args.get("reason"), str) else None
        existing = db.query(VoiceOptOut).filter(
            VoiceOptOut.phone_e164 == job.phone_e164
        ).first()
        if existing is None:
            db.add(VoiceOptOut(
                phone_e164=job.phone_e164,
                reason=(reason or "voice_call_request")[:200],
                source="recipient",
            ))
        job.status = "opted_out"
        job.ai_outcome = "opted_out"
        job.next_retry_at = None
        job.block_reason = "opted_out"
        if reason:
            job.summary = reason.strip()[:1000]
        db.commit()
        return {
            "ok": True,
            "outcome": "opted_out",
            "summary": reason or "Recipient asked not to be called again",
        }
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        logger.exception("mark_opt_out failed for job=%s", job_id)
        return {"ok": False, "error": "db_error", "message": str(exc)[:200]}
    finally:
        db.close()


def _tool_escalate(job_id: Optional[str], args: dict) -> dict:
    reason = args.get("reason") if isinstance(args.get("reason"), str) else "unspecified"
    db = SessionLocal()
    try:
        job = _job(db, job_id)
        if job is not None:
            job.status = "completed"
            job.ai_outcome = "escalated"
            job.summary = (reason or "Escalated to organiser")[:1000]
            job.next_retry_at = None
            db.commit()
        return {
            "ok": True,
            "outcome": "escalated",
            "summary": reason,
            "message": "Marked for organiser follow-up.",
        }
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        logger.exception("escalate_to_human failed for job=%s", job_id)
        return {"ok": False, "error": "db_error", "message": str(exc)[:200]}
    finally:
        db.close()


def _tool_request_callback(job_id: Optional[str], args: dict) -> dict:
    pref = args.get("preferred_time") if isinstance(args.get("preferred_time"), str) else None
    reason = args.get("reason") if isinstance(args.get("reason"), str) else None
    db = SessionLocal()
    try:
        job = _job(db, job_id)
        if job is not None:
            job.status = "no_answer"
            job.ai_outcome = "call_later"
            if reason or pref:
                job.summary = (
                    f"Callback requested: {pref or 'later'} ({reason or ''})"
                )[:1000]
            db.commit()
        return {
            "ok": True,
            "outcome": "call_later",
            "preferred_time": pref,
            "summary": "Callback recorded.",
        }
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        logger.exception("request_callback failed for job=%s", job_id)
        return {"ok": False, "error": "db_error", "message": str(exc)[:200]}
    finally:
        db.close()


def _tool_request_whatsapp(job_id: Optional[str], args: dict) -> dict:
    reason = args.get("reason") if isinstance(args.get("reason"), str) else None
    db = SessionLocal()
    try:
        job = _job(db, job_id)
        if job is not None:
            job.status = "completed"
            job.ai_outcome = "whatsapp_follow_up"
            job.block_reason = "whatsapp_follow_up_needed"
            job.next_retry_at = None
            if reason:
                job.summary = reason.strip()[:1000]
            db.commit()
        return {
            "ok": True,
            "outcome": "whatsapp_follow_up",
            "summary": reason or "Queued WhatsApp follow-up.",
        }
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        logger.exception("request_whatsapp_followup failed for job=%s", job_id)
        return {"ok": False, "error": "db_error", "message": str(exc)[:200]}
    finally:
        db.close()


def _tool_human_follow_up(job_id: Optional[str], args: dict) -> dict:
    reason = (
        args.get("reason") if isinstance(args.get("reason"), str) else "unclear_response"
    )
    db = SessionLocal()
    try:
        job = _job(db, job_id)
        if job is not None:
            job.status = "completed"
            job.ai_outcome = "human_follow_up_needed"
            job.block_reason = "human_follow_up"
            job.next_retry_at = None
            job.summary = (reason or "Human follow-up needed")[:1000]
            db.commit()
        # Tag the most recent log row so dashboards can surface the reason.
        log = (
            db.query(VoiceCallLog)
            .filter(VoiceCallLog.job_id == job_id)
            .order_by(VoiceCallLog.created_at.desc())
            .first()
            if job_id else None
        )
        if log is not None:
            log.human_follow_up_reason = (reason or "")[:200]
            db.commit()
        return {
            "ok": True,
            "outcome": "human_follow_up_needed",
            "summary": reason,
            "message": "Marked for human follow-up.",
        }
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        logger.exception("mark_human_follow_up failed for job=%s", job_id)
        return {"ok": False, "error": "db_error", "message": str(exc)[:200]}
    finally:
        db.close()


def _tool_log_quality(job_id: Optional[str], args: dict) -> dict:
    db = SessionLocal()
    try:
        log = (
            db.query(VoiceCallLog)
            .filter(VoiceCallLog.job_id == job_id)
            .order_by(VoiceCallLog.created_at.desc())
            .first()
            if job_id else None
        )
        if log is None:
            return {"ok": True, "note": "no_log_row_yet"}

        mood = args.get("detected_mood")
        if isinstance(mood, str) and mood in MOODS:
            log.detected_mood = mood
        quality = args.get("conversation_quality")
        if isinstance(quality, str) and quality in QUALITIES:
            log.conversation_quality = quality
        noise = args.get("noise_detected")
        if isinstance(noise, bool):
            log.noise_detected = noise
        for fld in ("interruption_count", "silence_count", "clarification_count"):
            v = args.get(fld)
            if isinstance(v, (int, float)):
                setattr(log, fld, max(0, int(v)))
        conf = args.get("final_confidence")
        try:
            if conf is not None:
                log.final_confidence = max(0.0, min(1.0, float(conf)))
        except (TypeError, ValueError):
            pass
        db.commit()
        return {"ok": True, "outcome": "quality_logged"}
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        logger.exception("log_conversation_quality failed for job=%s", job_id)
        return {"ok": False, "error": "db_error", "message": str(exc)[:200]}
    finally:
        db.close()


_TOOLS = {
    "save_rsvp": _tool_save_rsvp,
    "mark_opt_out": _tool_mark_opt_out,
    "escalate_to_human": _tool_escalate,
    "request_callback": _tool_request_callback,
    "request_whatsapp_followup": _tool_request_whatsapp,
    "mark_human_follow_up": _tool_human_follow_up,
    "log_conversation_quality": _tool_log_quality,
}


def execute_tool(job_id: Optional[str], name: str, args: dict) -> dict:
    """Dispatch a Gemini Live tool call to the matching executor."""
    fn = _TOOLS.get((name or "").strip())
    if fn is None:
        return {"ok": False, "error": "unknown_tool", "tool": name}
    safe_args = args if isinstance(args, dict) else {}
    return fn(job_id, safe_args)


# ──────────────────────────────────────────────────────────────────
# Installer — wires this agent into the Gemini Live bridge.
# ──────────────────────────────────────────────────────────────────

def install_rsvp_agent() -> None:
    """Register ``build_rsvp_spec`` as the Gemini Live system builder.

    Safe to call when Gemini is not configured (the setter is a tiny
    in-process slot; the bridge stays silent if no API key).
    """
    try:
        from voice.ai.gemini_live import set_system_builder
        set_system_builder(build_rsvp_spec)
        logger.info("RSVP voice agent installed (system prompt + tools)")
    except Exception:  # noqa: BLE001
        logger.exception("Failed to install RSVP voice agent")
