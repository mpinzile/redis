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

import hashlib
import logging
import re
import uuid
from datetime import datetime
from typing import Any, Optional, Tuple

from core.database import SessionLocal
from models import (
    EventAttendee, EventInvitation, Event,
    EventScheduleItem, EventVenueCoordinate,
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
# Address / greeting helpers
# ──────────────────────────────────────────────────────────────────

# Titles we should preserve verbatim with the LAST name (e.g. "Mr Frank" → "Bw. Frank").
# Keys are normalised (lowercase, no dots). Values are (sw_title, en_title).
_TITLE_MAP = {
    "mr":    ("Bw.",   "Mr."),
    "mister":("Bw.",   "Mr."),
    "bw":    ("Bw.",   "Mr."),
    "bwana": ("Bwana", "Mr."),
    "mrs":   ("Bi.",   "Mrs."),
    "ms":    ("Bi.",   "Ms."),
    "miss":  ("Bi.",   "Miss"),
    "bi":    ("Bi.",   "Ms."),
    "dr":    ("Dkt.",  "Dr."),
    "doctor":("Dkt.",  "Dr."),
    "dkt":   ("Dkt.",  "Dr."),
    "prof":  ("Prof.", "Prof."),
    "professor":("Prof.","Prof."),
    "mzee":  ("Mzee",  "Mzee"),
    "mama":  ("Mama",  "Mama"),
    "baba":  ("Baba",  "Baba"),
    "shekh": ("Shekh", "Sheikh"),
    "sheikh":("Shekh", "Sheikh"),
    # Religious / professional titles common in Tanzania
    "mchungaji": ("Mchungaji", "Pastor"),
    "pst":       ("Mchungaji", "Pastor"),
    "pastor":    ("Mchungaji", "Pastor"),
    "mwinjilisti": ("Mwinjilisti", "Evangelist"),
    "evangelist":  ("Mwinjilisti", "Evangelist"),
    "askofu":  ("Askofu", "Bishop"),
    "bishop":  ("Askofu", "Bishop"),
    "padri":   ("Padri",  "Father"),
    "father":  ("Padri",  "Father"),
    "ustadhi": ("Ustadhi", "Ustadh"),
    "ustadh":  ("Ustadhi", "Ustadh"),
    "mwalimu": ("Mwalimu", "Teacher"),
    "mw":      ("Mwalimu", "Teacher"),
    "eng":     ("Mhandisi", "Eng."),
    "engineer":("Mhandisi", "Eng."),
    "mhandisi":("Mhandisi", "Eng."),
    "hon":     ("Mh.",  "Hon."),
    "mh":      ("Mh.",  "Hon."),
}

# Rotating Swahili greetings — natural Tanzanian speech, not "Shalom".
_SW_GREETINGS = (
    "Habari", "Habari za leo", "Habari za asubuhi", "Habari yako",
    "Salama", "Hujambo", "Mambo vipi",
)
_EN_GREETINGS = ("Hello", "Hi", "Good day", "Good morning")


# Tanzania is permanently on EAT (UTC+3, no DST). We compute the time-of-day
# greeting from the server clock converted to EAT so it matches what the
# recipient is actually experiencing locally.
def time_of_day_greeting(*, is_sw: bool) -> str:
    """Return a natural time-of-day opener for the current EAT hour.

    Buckets mirror ``mobile/.../home_right_drawer.dart`` so the voice
    assistant and the mobile UI greet at the same boundaries:
      05-11  -> morning   (Habari ya asubuhi / Good morning)
      12-16  -> afternoon (Habari ya mchana  / Good afternoon)
      17-20  -> evening   (Habari ya jioni   / Good evening)
      else   -> night     (Habari ya usiku   / Good evening — late)
    """
    from datetime import datetime, timezone, timedelta
    eat = timezone(timedelta(hours=3))
    hour = datetime.now(tz=eat).hour
    if 5 <= hour < 12:
        return "Habari ya asubuhi" if is_sw else "Good morning"
    if 12 <= hour < 17:
        return "Habari ya mchana" if is_sw else "Good afternoon"
    if 17 <= hour < 21:
        return "Habari ya jioni" if is_sw else "Good evening"
    return "Habari ya usiku" if is_sw else "Good evening"




def _address_for(recipient_name: str, *, is_sw: bool) -> Tuple[str, str]:
    """Return ``(addressed_name, vocative)``.

    ``addressed_name`` is what the AI should say after the greeting:
      - "Mr Frank"  → "Bw. Frank" (sw) / "Mr. Frank" (en)  — keep the title
      - "David Mwakalinga" → "David" — first name only
      - "" / falsy → "rafiki" (sw) / "there" (en)

    ``vocative`` is the same string but safe to drop inside a longer sentence
    (currently identical; kept for future tweaks).
    """
    raw = (recipient_name or "").strip()
    if not raw:
        fallback = "rafiki" if is_sw else "there"
        return fallback, fallback

    # Split on whitespace; drop empty bits.
    parts = [p for p in re.split(r"\s+", raw) if p]
    if not parts:
        fallback = "rafiki" if is_sw else "there"
        return fallback, fallback

    # Title detection: first token, stripped of trailing dot.
    head = parts[0].rstrip(".").lower()
    if head in _TITLE_MAP and len(parts) >= 2:
        title_sw, title_en = _TITLE_MAP[head]
        # Use the LAST remaining token as the surname (handles "Mr John Frank" → "Bw. Frank").
        surname = parts[-1]
        title = title_sw if is_sw else title_en
        addr = f"{title} {surname}"
        return addr, addr

    # No title — use first name only, properly cased.
    first = parts[0]
    # Keep original casing if it already has lowercase letters (e.g. "deCarlo"),
    # otherwise title-case a SHOUTED name like "DAVID".
    if first.isupper() or first.islower():
        first = first.capitalize()
    return first, first


def _pick_greeting(job: Optional[VoiceCallJob], greetings: tuple) -> str:
    """Deterministic per-job rotation so retries don't keep switching greetings."""
    seed_src = ""
    if job is not None:
        seed_src = str(getattr(job, "id", "") or getattr(job, "phone_e164", "") or "")
    if not seed_src:
        seed_src = datetime.utcnow().strftime("%Y%m%d%H")
    idx = int(hashlib.md5(seed_src.encode("utf-8")).hexdigest(), 16) % len(greetings)
    return greetings[idx]



# ──────────────────────────────────────────────────────────────────
# System prompt + tool schema for Gemini Live
# ──────────────────────────────────────────────────────────────────

def _fmt_date_sw(dt: datetime) -> str:
    months = ["Januari","Februari","Machi","Aprili","Mei","Juni",
              "Julai","Agosti","Septemba","Oktoba","Novemba","Desemba"]
    try:
        return f"tarehe {dt.day} {months[dt.month-1]} {dt.year}"
    except Exception:
        return dt.strftime("%d/%m/%Y")


def _fmt_time_sw(dt: datetime) -> str:
    try:
        return dt.strftime("saa %H:%M")
    except Exception:
        return ""


def _event_facts(event: Optional[Event], db, *, is_sw: bool = True) -> dict:
    """Pre-load every detail the agent might be asked about during a call.

    Returned keys are always present (empty string if unknown) so the prompt
    template stays simple. Schedule items (ibada, mapokezi, chakula, ...) are
    summarised into one human-readable string per item.
    """
    facts = {
        "name": "", "type": "", "date": "", "time": "", "end": "",
        "venue": "", "address": "", "guest_of_honor": "",
        "dress_code": "", "special_instructions": "",
        "description": "", "schedule": "", "extra": "",
    }
    if event is None:
        return facts
    facts["name"] = (getattr(event, "name", None) or "").strip()
    try:
        et = getattr(event, "event_type", None)
        if et is not None:
            facts["type"] = (getattr(et, "name", None) or "").strip()
    except Exception:
        pass
    sd = getattr(event, "start_date", None)
    st = getattr(event, "start_time", None)
    ed = getattr(event, "end_date", None) or getattr(event, "end_time", None)
    if sd:
        facts["date"] = _fmt_date_sw(sd) if is_sw else sd.strftime("%A, %d %B %Y")
    if st:
        facts["time"] = _fmt_time_sw(st) if is_sw else st.strftime("%H:%M")
    if ed:
        try:
            facts["end"] = ed.strftime("%H:%M")
        except Exception:
            pass
    location = (getattr(event, "location", None) or "").strip()
    venue_name = ""
    address = ""
    try:
        vc = getattr(event, "venue_coordinate", None)
        if vc is not None:
            venue_name = (getattr(vc, "venue_name", None) or "").strip()
            address = (getattr(vc, "formatted_address", None) or "").strip()
    except Exception:
        pass
    facts["venue"] = venue_name or location
    facts["address"] = address or location
    facts["guest_of_honor"] = (getattr(event, "guest_of_honor", None) or "").strip()
    facts["dress_code"] = (getattr(event, "dress_code", None) or "").strip()
    facts["special_instructions"] = (
        getattr(event, "special_instructions", None) or "").strip()
    desc = (getattr(event, "description", None) or "").strip()
    if desc:
        facts["description"] = desc[:400]

    # Schedule items (ibada, mapokezi, chakula, etc.).
    try:
        if db is not None and getattr(event, "id", None):
            items = (
                db.query(EventScheduleItem)
                .filter(EventScheduleItem.event_id == event.id)
                .order_by(EventScheduleItem.start_time.asc().nullslast(),
                          EventScheduleItem.display_order.asc())
                .limit(8)
                .all()
            )
            lines = []
            for it in items:
                title = (getattr(it, "title", None) or "").strip()
                if not title:
                    continue
                t = getattr(it, "start_time", None)
                tpart = (t.strftime("%H:%M") if t else "")
                loc = (getattr(it, "location", None) or "").strip()
                bits = [b for b in (tpart, title, loc) if b]
                lines.append(" - ".join(bits))
            if lines:
                facts["schedule"] = "; ".join(lines)
    except Exception:
        logger.exception("Failed to load schedule for event=%s",
                         getattr(event, "id", None))

    # Extra details JSON ([{label, details}, ...]).
    try:
        extras = getattr(event, "extra_details", None) or []
        if isinstance(extras, list):
            pairs = []
            for row in extras[:6]:
                if isinstance(row, dict):
                    lbl = (row.get("label") or "").strip()
                    det = (row.get("details") or row.get("value") or "").strip()
                    if lbl and det:
                        pairs.append(f"{lbl}: {det}")
            if pairs:
                facts["extra"] = "; ".join(pairs)
    except Exception:
        pass
    return facts


def _event_brief(event: Optional[Event], *, is_sw: bool = True) -> str:
    """Backwards-compatible one-liner used in older log strings/tests."""
    if event is None:
        return "tukio lijalo" if is_sw else "an upcoming event"
    name = (getattr(event, "name", None) or "").strip()
    if not name:
        return "tukio lijalo" if is_sw else "an upcoming event"
    starts = getattr(event, "start_date", None)
    parts = [name]
    if starts:
        try:
            parts.append(
                _fmt_date_sw(starts) if is_sw
                else starts.strftime("%A, %d %B %Y")
            )
        except Exception:
            pass
    location = (getattr(event, "location", None) or "").strip()
    if location:
        parts.append(("eneo la " if is_sw else "at ") + location)
    return " ".join(parts).strip()


def _event_name_for_job(job: Optional[VoiceCallJob]) -> str:
    """Return the event name for a live-call greeting, or a safe Swahili fallback."""
    if job is None or not getattr(job, "campaign_id", None):
        return "tukio"
    db = SessionLocal()
    try:
        from models import VoiceCampaign  # local import to avoid cycle
        camp = db.query(VoiceCampaign).filter(
            VoiceCampaign.id == job.campaign_id
        ).first()
        if camp is not None and camp.event_id:
            ev = db.query(Event).filter(Event.id == camp.event_id).first()
            name = (getattr(ev, "name", None) or "").strip() if ev is not None else ""
            return name or "tukio"
    except Exception:  # noqa: BLE001
        logger.exception("Failed to load event name for job=%s", getattr(job, "id", None))
    finally:
        db.close()
    return "tukio"



def build_rsvp_spec(job: Optional[VoiceCallJob], language: str) -> dict:
    """Return ``{system_text, tools}`` for the Gemini Live setup frame."""
    lang = (language or "sw").lower()
    is_sw = not lang.startswith("en")  # default to Swahili unless explicitly English
    raw_name = (getattr(job, "recipient_name", None) or "").strip()
    addressed, _ = _address_for(raw_name, is_sw=is_sw)
    recipient = addressed  # used throughout the prompt
    greeting_sw = _pick_greeting(job, _SW_GREETINGS)
    greeting_en = _pick_greeting(job, _EN_GREETINGS)
    event_text = "tukio lijalo" if is_sw else "an upcoming event"
    has_event_name = False
    event_name_only = "tukio lijalo" if is_sw else "the event"
    facts: dict = _event_facts(None, None, is_sw=is_sw)
    if job is not None and job.campaign_id:
        db = SessionLocal()
        try:
            from models import VoiceCampaign  # local import to avoid cycle
            camp = db.query(VoiceCampaign).filter(
                VoiceCampaign.id == job.campaign_id
            ).first()
            if camp and camp.event_id:
                ev = db.query(Event).filter(Event.id == camp.event_id).first()
                event_text = _event_brief(ev, is_sw=is_sw)
                facts = _event_facts(ev, db, is_sw=is_sw)
                if facts.get("name"):
                    event_name_only = facts["name"]
                    has_event_name = True
        except Exception:  # noqa: BLE001
            logger.exception("Failed to load event context for job=%s", job.id)
        finally:
            db.close()

    # Build a compact "facts sheet" the model can quote from. Only include
    # keys that have a value so we don't tell the model "venue: (unknown)"
    # and have it invent something.
    def _fact_block(labels: dict) -> str:
        rows = []
        for key, label in labels.items():
            val = (facts.get(key) or "").strip()
            if val:
                rows.append(f"- {label}: {val}")
        return "\n".join(rows) if rows else (
            "- (hakuna taarifa zaidi)" if is_sw else "- (no extra details)"
        )

    if is_sw:
        facts_block = _fact_block({
            "name": "Jina la tukio",
            "type": "Aina ya tukio",
            "date": "Tarehe",
            "time": "Muda wa kuanza",
            "end": "Muda wa kumaliza",
            "venue": "Eneo / ukumbi",
            "address": "Anwani",
            "guest_of_honor": "Mgeni rasmi",
            "dress_code": "Mavazi",
            "special_instructions": "Maelekezo maalum",
            "schedule": "Ratiba (ibada, mapokezi, chakula, n.k.)",
            "extra": "Maelezo mengine",
            "description": "Maelezo mafupi",
        })
    else:
        facts_block = _fact_block({
            "name": "Event name",
            "type": "Event type",
            "date": "Date",
            "time": "Start time",
            "end": "End time",
            "venue": "Venue",
            "address": "Address",
            "guest_of_honor": "Guest of honor",
            "dress_code": "Dress code",
            "special_instructions": "Special instructions",
            "schedule": "Programme (service, reception, meal, etc.)",
            "extra": "Other details",
            "description": "Short description",
        })

    tod_sw = time_of_day_greeting(is_sw=True)
    tod_en = time_of_day_greeting(is_sw=False)
    if is_sw:
        opening_event = event_name_only if has_event_name else "tukio"
        opening = (
            f"{tod_sw} {recipient}, mambo vipi? Napiga kutoka Nuru kwa "
            f"niaba ya mratibu wa tukio la {opening_event}. Ningependa "
            f"kuthibitisha kama utahudhuria."
        )

        system_text = (
            "KANUNI YA KWANZA — SIKILIZA KABLA YA KUSEMA: Baada ya KILA "
            "swali, NYAMAZA na subiri mteja amalize kujibu. USIFUATE "
            "skripti kipofu. Jibu lako linalofuata LAZIMA lihusiane na "
            "kile mteja KAMESEMA, siyo na kile ulichotarajia aseme. "
            "Akikataa, USIENDELEE na hatua zinazofuata za skripti kana "
            "kwamba amekubali.\n\n"
            "KANUNI YA TAARIFA ZA TUKIO: USITAJE tarehe, muda, eneo, "
            "ratiba, mavazi, mgeni rasmi WALA maelezo mengine yoyote ya "
            "tukio ISIPOKUWA: (a) mteja ametamka WAZI atahudhuria, AU "
            "(b) mteja AMEULIZA taarifa hiyo moja kwa moja. Akikataa au "
            "akiwa hana uhakika, USITAJE taarifa hizo kabisa — funga kwa "
            "heshima tu.\n\n"
            "LUGHA (KIOO CHA MTEJA): Anza KISWAHILI CHA TANZANIA. "
            "Lugha yako lazima IFUATE lugha ya mteja kila wakati: \n"
            "  • Mteja akiongea Kiingereza kwa sentensi nzima, badilisha "
            "    Kiingereza mara moja kuanzia jibu lako linalofuata.\n"
            "  • Akirudi Kiswahili, rudi Kiswahili mara moja.\n"
            "  • Akisema 'sijakuelewa', 'I don't understand', 'sema kwa "
            "    lugha yangu', 'speak my language' au akirudia kwa lugha "
            "    tofauti, BADILISHA mara moja kwenda lugha aliyoitumia mara "
            "    ya mwisho na rudia jibu lako kwa kifupi katika lugha hiyo.\n"
            "  • Akichanganya maneno machache tu (mfano: anasema Kiswahili "
            "    na neno moja la Kiingereza), endelea lugha kuu.\n"
            "Usitumie misemo ya kiroboti kama 'Processing', 'Your response "
            "has been saved'. Tumia: 'Sawa.', 'Nimekuelewa.', 'Asante.', "
            "'Halo, unanipata?', 'Samahani, narudia kwa kifupi.'\n\n"
            "MTINDO WA KUONGEA: Sauti ya kawaida (siyo ya kirobo), joto, "
            "ya kibinadamu. Ongea kwa kasi ya kawaida ya simu ya Mtanzania "
            "(haraka kidogo, siyo polepole). Sentensi fupi. Pumzika baada "
            "ya swali. Usisome kama notisi.\n\n"
            f"Wewe ni Msaidizi wa Sauti wa Nuru. KAMWE usidai wewe ni mtu "
            f"wa kweli. Unampigia {recipient} kuhusu mwaliko wa {event_text}.\n\n"
            "TAARIFA ZA TUKIO (tumia hizi PEKEE — usibuni jambo lolote; "
            "na zitaje TU mteja akihudhuria au akiuliza):\n"
            f"{facts_block}\n\n"

            "MTIRIRIKO WA SIMU (fuata mpangilio huu):\n"
            "\n"
            "1) MWANZO (sentensi moja, fupi):\n"
            f"   \"{opening}\"\n"
            "\n"
            "2) UTHIBITISHO WA MWALIKO:\n"
            "   Uliza: \"Tumekutumia mwaliko kupitia WhatsApp na ujumbe wa "
            "   kawaida. Je, umeupokea?\"\n"
            "\n"
            "3) AKISEMA 'NDIO, NIMEUPOKEA':\n"
            "   Jibu: \"Asante sana. Ningependa kuthibitisha kama "
            "   utahudhuria.\" Kisha nenda hatua ya 5.\n"
            "\n"
            "4) AKISEMA 'HAPANA, SIJAPOKEA' (au 'sina card', 'sijaona', "
            "   'hakuna ujumbe', 'sijatumiwa'):\n"
            "   WEKA invitation_received=false ndani ya akili yako kwa "
            "   simu yote. Jibu MARA MOJA: \"Pole sana kwa hilo. "
            "   Tutakutumia tena mwaliko muda mfupi ujao kupitia WhatsApp "
            "   au ujumbe wa kawaida. Kabla hatujamaliza, ningependa "
            "   kuthibitisha kama utaweza kuhudhuria.\" KISHA tumia "
            "   request_whatsapp_followup. KAMWE BAADA YA HAPA usiseme "
            "   'angalia kadi yako', 'rejea kwenye kadi yako', 'soma "
            "   mwaliko uliotumiwa' — mteja KASHASEMA hajaupokea. "
            "   Nenda hatua ya 5.\n"
            "\n"
            "5) ANAJIBU KUHUSU KUHUDHURIA:\n"
            "\n"
            "   a) Akisema 'NDIO, NITAHUDHURIA' (au 'nitakuja', 'nitafika', "
            "      'nipo', 'Inshallah nitakuja'):\n"
            "      Sema: \"Asante sana, na karibu sana.\" Kisha taja "
            "      taarifa muhimu kutoka TAARIFA ZA TUKIO kwa sentensi "
            "      fupi fupi: tarehe, kisha ibada (muda + eneo), kisha "
            "      mapokezi/sherehe (muda + eneo) ikiwa zipo kwenye "
            "      ratiba. Kisha sema: \"Tunafurahi kukukaribisha. "
            "      Asante sana kwa muda wako.\" Tumia "
            "      save_rsvp(status=confirmed, confidence=0.9) na nenda "
            "      hatua ya 6.\n"
            "\n"
            "   b) Akisema 'HAPANA, SITAHUDHURIA' (au 'sitakuja', "
            "      'siwezi', 'nina safari'):\n"
            "      Sema: \"Asante kwa kutujulisha. Tunakushukuru kwa muda "
            "      wako, na tunakutakia kila la heri.\" Tumia "
            "      save_rsvp(status=declined, confidence=0.9) na nenda "
            "      hatua ya 6.\n"
            "\n"
            "   c) Akisema 'BADO SIJAJUA' / 'SINA UHAKIKA' / 'NITAANGALIA':\n"
            "      Sema (BILA kutaja kadi ikiwa invitation_received=false): "
            "      \"Sawa, hakuna tatizo. Tutashukuru kupata majibu yako "
            "      mapema kadri iwezekanavyo.\" Tumia save_rsvp(status=maybe, "
            "      confidence=0.8) na nenda hatua ya 6.\n"
            "\n"
            "   d) Akiwa BUSY / KIKAONI / KELELE / 'NIPIGIE BAADAYE' / "
            "      'NIPIGIE KESHO':\n"
            "      USIMSUKUMIZE RSVP. Sema kwa upole: \"Nimekuelewa. "
            "      Naweza kukupigia baadaye muda unaokufaa.\" Akitoa "
            "      muda mahususi, sema: \"Sawa, nitahifadhi ukumbusho wa "
            "      kukupigia [muda]. Asante.\" Tumia request_callback "
            "      (preferred_time ikiwa imetolewa). USITUMIE save_rsvp.\n"
            "\n"
            "6) MWISHO WA SIMU:\n"
            "   Sema: \"Asante sana kwa muda wako. Nakutakia siku njema.\" "
            "   Kisha tumia log_conversation_quality. USIENDELEE kuongea.\n"
            "\n"
            "MASWALI YA TUKIO — LAZIMA UJIBU MOJA KWA MOJA kutoka "
            "TAARIFA ZA TUKIO kabla ya kurudi RSVP:\n"
            "  • \"Tukio litafanyika tarehe ngapi?\" / \"Ni lini?\" / "
            "    \"Tarehe gani?\" → \"Tukio litafanyika [Tarehe].\"\n"
            "  • \"Saa ngapi?\" / \"Litaanza saa ngapi?\" → \"Litaanza "
            "    [Muda wa kuanza].\"\n"
            "  • \"Wapi?\" / \"Eneo gani?\" / \"Ukumbi gani?\" → "
            "    \"Litafanyika [Eneo / ukumbi].\"\n"
            "  • \"Nani ameandaa?\" / \"Mgeni rasmi ni nani?\" → tumia "
            "    Mgeni rasmi kutoka TAARIFA.\n"
            "  Jibu kwa SENTENSI MOJA, kisha rudi kwa upole: \"Je, kwa "
            "  muda huo utaweza kuhudhuria?\"\n"
            "  Taarifa IKIWA HAIPO kwenye TAARIFA ZA TUKIO, sema: "
            "  \"Samahani, sina taarifa hiyo hapa kwenye mfumo kwa sasa. "
            "  Naweza kumjulisha mratibu akufuatilie.\" KAMWE USIBUNI.\n"
            "\n"
            "SHERIA ZA USAHIHI WA RSVP (MUHIMU SANA):\n"
            "- Hifadhi save_rsvp PEKEE pale jibu liko WAZI kabisa na "
            "  confidence >= 0.7. Vinginevyo uliza ufafanuzi mara MOJA: "
            f"  \"Ili nihifadhi vizuri, unamaanisha utahudhuria tukio la {event_name_only}?\". "
            "  Likibaki halieleweki, tumia mark_human_follow_up — "
            "  USITUMIE save_rsvp.\n"
            "- Mteja akiwa busy au amesema 'nipigie baadaye', USITUMIE "
            "  save_rsvp. Tumia request_callback PEKEE.\n"
            "- KAMWE usiseme 'angalia kadi yako' au 'rejea kwenye "
            "  mwaliko' ikiwa mteja KASHASEMA hajaupokea.\n"
            "- Akiuliza wewe ni nani, sema: \"Mimi ni Msaidizi wa Sauti "
            f"  wa Nuru. Napiga kwa niaba ya mratibu wa tukio la {event_name_only}. "
            "  Namba yako ipo kwenye orodha ya wageni walioalikwa.\"\n"
            "- Akisema 'sikusikii' / 'rudia', omba radhi na rudia kwa "
            "  kifupi. Akishindwa tena, tumia request_whatsapp_followup.\n"
            "- Akiomba usimpigie tena, tumia mark_opt_out kwa heshima.\n"
            "- Akisema 'kwaheri' / 'bye' / 'tutaonana' / 'naenda' AU "
            "  kimya kabisa baada ya majaribio 2 — funga simu mara moja: "
            "  \"Asante sana, kwaheri.\" + log_conversation_quality.\n"
            "- Usitoe taarifa za malipo wala kiasi cha mchango.\n"
            "- KILA SIMU LAZIMA iishie na log_conversation_quality.\n\n"
            + NATURAL_CONVERSATION_RULES_SW
        )
    else:
        opening = (
            f"{tod_en} {recipient}, how are you today? I'm calling from "
            f"Nuru on behalf of the organiser of {event_name_only}. I'd "
            f"like to confirm whether you'll attend."
        )
        system_text = (
            "FIRST RULE — LISTEN BEFORE YOU SPEAK: After every question, "
            "STOP and wait for the recipient to finish their reply. Do "
            "NOT follow the script blindly. Your next response MUST react "
            "to what they actually said, not what you expected. If they "
            "decline, do NOT continue down the script as if they accepted.\n\n"
            "EVENT-DETAILS RULE: Do NOT mention the date, time, venue, "
            "programme, dress code, guest of honour, or ANY other event "
            "detail unless: (a) the recipient has CLEARLY confirmed they "
            "will attend, OR (b) the recipient explicitly asked for that "
            "detail. If they decline or are unsure, do NOT share any of "
            "those details — just close warmly.\n\n"
            "LANGUAGE (MIRROR THE RECIPIENT): Start in English. From then "
            "on your language must FOLLOW the recipient: \n"
            "  • If they speak a full sentence in Swahili, switch to "
            "    Swahili immediately on your very next reply.\n"
            "  • If they return to English, switch back immediately.\n"
            "  • If they say 'I don't understand', 'sijakuelewa', 'speak "
            "    my language', 'sema kwa lugha yangu', or repeat in a "
            "    different language — switch to the language they last "
            "    used and briefly repeat your last sentence in it.\n"
            "  • Small loanwords don't count — only switch on a full "
            "    sentence in the other language.\n\n"
            "TONE & PACE: Natural human voice, warm. Brisk natural phone "
            "pace, not slow. Short sentences. Pause after a question.\n\n"
            "You are the Nuru Voice Assistant. Never claim to be a real "
            f"person. You're calling {recipient} about their invitation to "
            f"{event_text}.\n\n"
            "EVENT FACTS (use ONLY these — never invent details; only "
            "share them if attendance is confirmed or the recipient "
            "asked):\n"
            f"{facts_block}\n\n"

            "CALL FLOW (follow in order):\n"
            "\n"
            f"1) OPENING (one short sentence): \"{opening}\"\n"
            "\n"
            "2) INVITATION CHECK: Ask: \"We've sent you the invitation "
            "   via WhatsApp and SMS. Did you receive it?\"\n"
            "\n"
            "3) IF 'YES, RECEIVED': Say: \"Thank you. I'd like to confirm "
            "   whether you'll attend.\" Then go to step 5.\n"
            "\n"
            "4) IF 'NO, NOT RECEIVED': Say: \"I'm sorry about that. We'll "
            "   resend it shortly via WhatsApp or SMS. In the meantime, "
            "   I'd still like to confirm whether you plan to attend.\" "
            "   Then go to step 5. (Also call request_whatsapp_followup "
            "   before ending.)\n"
            "\n"
            "5) ATTENDANCE ANSWER:\n"
            "   a) YES: \"Thank you, you're most welcome.\" Then share the "
            "      key facts in short sentences (date, then service time "
            "      + venue, then reception time + venue) from EVENT FACTS "
            "      if present. End that block with: \"We look forward to "
            "      hosting you. Thank you for your time.\" Then call "
            "      save_rsvp(status=confirmed) and go to step 6.\n"
            "   b) NO: \"Thank you for letting us know. We appreciate "
            "      your time and wish you all the best.\" Then call "
            "      save_rsvp(status=declined) and go to step 6.\n"
            "   c) NOT SURE: \"That's fine. You can confirm later via the "
            "      WhatsApp invitation or the SMS. We'd appreciate hearing "
            "      back as soon as you can.\" Then save_rsvp(status=maybe) "
            "      and go to step 6.\n"
            "\n"
            "6) CLOSING: \"Thank you for your time. Have a great day.\" "
            "   Then call log_conversation_quality. Do NOT keep talking.\n"
            "\n"
            "EXTRA RULES:\n"
            "- For event detail questions, answer in ONE short sentence "
            "  from EVENT FACTS, then return to the current step.\n"
            "- If a detail is missing: \"I don't have that exact detail "
            "  right now — I'll have the organiser send it on WhatsApp.\" "
            "  Never invent an answer.\n"
            "- If asked who you are: \"I'm the Nuru Voice Assistant, "
            f"  calling on behalf of the organiser of {event_name_only}. "
            "  Your number is on the invited guest list.\"\n"
            "- 'Can't hear' / 'repeat' — apologise and repeat briefly. "
            "  Twice failed → request_whatsapp_followup.\n"
            "- Busy / noisy → request_callback or request_whatsapp_followup.\n"
            "- 'Don't call again' → mark_opt_out.\n"
            "- 'Bye' / 'goodbye' / 'talk later' / 'I have to go' OR silence "
            "  after 2 prompts → close with \"Thank you, goodbye.\" + "
            "  log_conversation_quality.\n"
            "- Still unclear after ONE clarifier "
            f"  (\"Just to confirm — you mean you'll attend {event_name_only}?\") "
            "  → mark_human_follow_up.\n"
            "- Never request payment details.\n"
            "- EVERY call MUST end with log_conversation_quality.\n\n"
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
        # SAFETY GATE: never persist a guess. Low confidence or 'maybe'
        # without strong confidence becomes human follow-up instead of
        # silently flipping the guest's RSVP in the dashboard.
        min_conf = 0.7 if status in {"confirmed", "declined"} else 0.6
        if status in {"confirmed", "declined", "maybe"} and (
            confidence is None or confidence < min_conf
        ):
            if job is not None:
                job.status = "completed"
                job.ai_outcome = "human_follow_up_needed"
                job.block_reason = "low_confidence_rsvp"
                job.next_retry_at = None
                job.summary = (
                    f"Low-confidence {status} (conf={confidence}); "
                    f"deferred to organiser follow-up. {(notes or '')[:500]}"
                )[:1000]
                db.commit()
            return {
                "ok": True,
                "outcome": "human_follow_up_needed",
                "confidence": confidence,
                "summary": "Answer unclear — flagged for human follow-up "
                           "instead of writing RSVP.",
                "guests_updated": 0,
            }
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
