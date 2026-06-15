"""Natural conversation handling for Nuru Voice Assistant (Phase 11).

This module is a deterministic, Gemini-independent layer that:

* classifies a recipient utterance into one of the documented intents,
* infers detected_mood / noise_detected from short Swahili-first cues,
* picks the next conversation state (state machine),
* exposes a tiny response library so the AI (and tests) can always pick
  a polite, short Swahili reply for repair / silence / noise / handoff,
* gives the Gemini Live system prompt the same vocabulary so the model
  classifies the same way out loud.

We keep this module pure (no I/O) so it can be unit-tested without a
network. ``rsvp_agent`` calls into it to enrich the system prompt and to
back the new ``log_conversation_quality`` / ``request_callback`` /
``request_whatsapp_followup`` / ``mark_human_follow_up`` tools.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional

# ──────────────────────────────────────────────────────────────────
# Vocabulary (Swahili-first, with a few common English fallbacks).
# Match on lowercased, accent-folded substrings.
# ──────────────────────────────────────────────────────────────────

CONFIRMED_PHRASES = (
    "ndio", "ndiyo", "naam", "eheh", "yes", "yeah",
    "nitakuja", "nitahudhuria", "nipo", "tupo pamoja",
    "nitafika", "nitaonekana", "nitakuwepo",
    "inshallah nitakuja", "mungu akipenda nitakuja",
    "sawa nitakuja", "tutaonana", "nitafika kabisa",
    "i will come", "i'll be there", "i'll attend",
)

DECLINED_PHRASES = (
    "sitakuja", "sitaweza", "siwezi kuja", "siwezi kuhudhuria",
    "nina safari", "nina ratiba nyingine", "niko mbali",
    "niko kazini", "sitafika", "samahani sitafika",
    "sitaweza kuhudhuria",
    "i can't make it", "i cannot attend", "i won't come",
)

MAYBE_PHRASES = (
    "bado sijajua", "sijaamua", "nitaangalia", "ngoja nione",
    "sina uhakika", "nitakujibu baadaye", "labda",
    "inawezekana", "huenda",
    "maybe", "not sure", "i'll see",
)

CALL_LATER_PHRASES = (
    "nipigie baadaye", "nipo busy", "nipo bize",
    "niko kwenye kikao", "nipo kwenye kelele",
    "sasa hivi siwezi kuongea", "sasahivi siwezi",
    "nipigie jioni", "nipigie kesho", "nipigie usiku",
    "nipigie tena", "rudi baadaye",
    "call me later", "i'm busy", "call back",
)

WRONG_NUMBER_PHRASES = (
    "umekosea namba", "umekosea nambari", "umekosea",
    "simfahamu huyo", "simfahamu huyo mtu",
    "mimi sio huyo", "mimi si huyo",
    "hii sio namba yake", "hii si namba yake",
    "hamjanipatia", "namba sio yake",
    "wrong number", "you have the wrong",
)

DID_NOT_HEAR_PHRASES = (
    "unasema", "umesema", "sikusikii", "sikusikia",
    "sikusikii vizuri", "sijasikia", "sijasikia vizuri",
    "rudia", "irudie", "sema tena", "ongea kwa sauti",
    "sikuelewi", "sikukuelewa", "sielewi",
    "what did you say", "say again", "repeat", "pardon",
)

IDENTITY_QUESTION_PHRASES = (
    "wewe ni nani", "nani anaongea", "nani huyu",
    "umenipataje", "namba yangu mmeipata wapi",
    "nani amewatuma", "unapiga kutoka wapi",
    "unatoka wapi", "wapi unapiga",
    "who is this", "who are you", "who's calling",
)

EVENT_QUESTION_PHRASES = (
    "umesema tukio gani", "ni tukio gani", "hii ni kuhusu nini",
    "ni nini hicho", "ni nini kuhusu", "ni harusi ya nani",
    "what event", "which event", "what's this about",
)

BUSY_PHRASES = (
    "nipo busy", "nipo bize", "niko bize", "niko busy",
    "nipo kwenye kikao", "niko kazini sasahivi",
    "sasahivi sio muda mzuri", "muda huu sio mzuri",
    "i'm in a meeting", "i'm at work",
)

NOISY_PHRASES = (
    "kuna kelele", "nipo barabarani", "mtandao unasumbua",
    "sauti inakatika", "sauti haisikiki",
    "network ni mbaya", "mtandao mbovu",
    "noisy", "bad signal", "you're breaking up",
)

REQUEST_WHATSAPP_PHRASES = (
    "nitumie whatsapp", "tuma ujumbe whatsapp",
    "tumia whatsapp", "ujumbe whatsapp",
    "send whatsapp", "via whatsapp", "on whatsapp",
)

HUMAN_REQUEST_PHRASES = (
    "naomba kuongea na mtu", "nipe mtu", "niunganishe na mtu",
    "naomba mratibu", "mwambie mratibu",
    "let me talk to a person", "speak to a human", "real person",
)

ANGRY_PHRASES = (
    "msinisumbue", "msinipigie tena", "achana nami", "niacheni",
    "mnanikera", "mnaudhi", "mnanichukiza",
    "stop calling me", "leave me alone", "don't call",
)

CONFUSED_PHRASES = (
    "sijaelewa", "sielewi", "sijakuelewa", "nimechanganyikiwa",
    "i don't understand", "i'm confused",
)

FRIENDLY_PHRASES = (
    "asante", "asante sana", "karibu", "salama",
    "thank you", "thanks",
)

GOODBYE_PHRASES = (
    "kwaheri", "kwa heri", "tutaonana", "tuonane baadaye",
    "naenda zangu", "nakatisha simu", "nina shughuli sasahivi",
    "asante kwaheri", "baadaye basi",
    "bye", "goodbye", "good bye", "talk later", "i have to go",
    "got to go", "gotta go",
)

# Explicit language-switch requests. The agent stays in Swahili by default
# and only flips to English when the recipient clearly asks for it.
SWITCH_TO_EN_PHRASES = (
    "speak english", "talk in english", "in english please",
    "use english", "english please", "can you speak english",
    "can you talk in english", "switch to english",
    "naomba english", "naomba kiingereza", "tumia kiingereza",
    "ongea kiingereza", "sema kiingereza", "tafadhali kiingereza",
)

SWITCH_TO_SW_PHRASES = (
    "ongea kiswahili", "sema kiswahili", "tumia kiswahili",
    "rudi kiswahili", "naomba kiswahili", "kiswahili tafadhali",
    "swahili please", "speak swahili", "in swahili",
    "switch to swahili", "back to swahili",
)


def detect_language_switch(text: Optional[str]) -> Optional[str]:
    """Return ``"en"`` / ``"sw"`` if the recipient explicitly requested a
    language switch, else ``None``. Mixed-language utterances do NOT count.
    """
    norm = _normalize(text)
    if not norm:
        return None
    # Swahili request wins ties (the agent's default language).
    if _contains_any(norm, SWITCH_TO_SW_PHRASES):
        return "sw"
    if _contains_any(norm, SWITCH_TO_EN_PHRASES):
        return "en"
    return None

# ──────────────────────────────────────────────────────────────────
# Intent + mood vocab (kept in sync with nuru_voice.md Phase 11).
# ──────────────────────────────────────────────────────────────────

INTENTS = (
    "confirmed", "declined", "maybe", "call_later", "wrong_number",
    "did_not_hear", "identity_question", "event_question", "busy",
    "noisy_environment", "request_whatsapp", "human_requested",
    "angry_or_uncomfortable", "unclear", "silence",
)

MOODS = (
    "neutral", "friendly", "confused", "busy",
    "annoyed", "angry", "uncomfortable",
)

QUALITIES = (
    "clear", "minor_clarification_needed", "noisy",
    "interrupted", "unclear", "failed",
)

STATES = (
    "greeting", "identity_clarification", "event_explanation",
    "invitation_received_check", "rsvp_question", "rsvp_confirmation",
    "callback_request", "wrong_number", "whatsapp_follow_up",
    "human_follow_up", "closing",
)

# ──────────────────────────────────────────────────────────────────
# Classification
# ──────────────────────────────────────────────────────────────────

_WS_RE = re.compile(r"\s+")


def _normalize(text: Optional[str]) -> str:
    """Lowercase, strip punctuation, collapse whitespace."""
    if not text:
        return ""
    s = text.lower()
    s = re.sub(r"[^\w\s']", " ", s, flags=re.UNICODE)
    return _WS_RE.sub(" ", s).strip()


def _contains_any(haystack: str, needles) -> bool:
    return any(n in haystack for n in needles)


@dataclass
class ClassifiedTurn:
    intent: str
    confidence: float
    mood: str
    noise_detected: bool
    next_state: str


# Priority matters: identity/event questions and "did not hear" must
# beat RSVP keywords because a user can say "wewe ni nani, nitakuja?"
# and the model should answer the identity question first.
_INTENT_ORDER = (
    ("did_not_hear", DID_NOT_HEAR_PHRASES),
    ("identity_question", IDENTITY_QUESTION_PHRASES),
    ("event_question", EVENT_QUESTION_PHRASES),
    ("wrong_number", WRONG_NUMBER_PHRASES),
    ("human_requested", HUMAN_REQUEST_PHRASES),
    ("request_whatsapp", REQUEST_WHATSAPP_PHRASES),
    ("noisy_environment", NOISY_PHRASES),
    ("angry_or_uncomfortable", ANGRY_PHRASES),
    ("call_later", CALL_LATER_PHRASES),
    ("busy", BUSY_PHRASES),
    # RSVP outcomes evaluated last (declined before confirmed so that
    # "sitakuja" wins over "nitakuja" substring overlap).
    ("declined", DECLINED_PHRASES),
    ("confirmed", CONFIRMED_PHRASES),
    ("maybe", MAYBE_PHRASES),
)


def classify(text: Optional[str]) -> ClassifiedTurn:
    """Classify a recipient utterance into one documented intent."""
    norm = _normalize(text)
    if not norm:
        return ClassifiedTurn(
            intent="silence", confidence=1.0, mood="neutral",
            noise_detected=False, next_state="rsvp_question",
        )

    detected: Optional[str] = None
    for intent, phrases in _INTENT_ORDER:
        if _contains_any(norm, phrases):
            detected = intent
            break

    if detected is None:
        detected = "unclear"

    mood = detect_mood(norm)
    noise = detected == "noisy_environment" or _contains_any(norm, NOISY_PHRASES)

    # Confidence: terminal intents we matched explicitly are high; the
    # "unclear" bucket is low so the AI knows to ask one clarifier.
    confidence = 0.4 if detected == "unclear" else 0.9

    return ClassifiedTurn(
        intent=detected,
        confidence=confidence,
        mood=mood,
        noise_detected=noise,
        next_state=next_state(detected),
    )


def detect_mood(text_norm: str) -> str:
    if not text_norm:
        return "neutral"
    if _contains_any(text_norm, ANGRY_PHRASES):
        return "angry"
    if _contains_any(text_norm, ("mnaudhi", "mnanikera", "msumbufu", "annoying")):
        return "annoyed"
    if _contains_any(text_norm, CONFUSED_PHRASES):
        return "confused"
    if _contains_any(text_norm, BUSY_PHRASES) or _contains_any(text_norm, CALL_LATER_PHRASES):
        return "busy"
    if _contains_any(text_norm, FRIENDLY_PHRASES):
        return "friendly"
    return "neutral"


def next_state(intent: str) -> str:
    """Map an intent to the next conversation state."""
    return {
        "confirmed": "closing",
        "declined": "closing",
        "maybe": "rsvp_confirmation",
        "call_later": "callback_request",
        "wrong_number": "wrong_number",
        "did_not_hear": "event_explanation",
        "identity_question": "identity_clarification",
        "event_question": "event_explanation",
        "busy": "callback_request",
        "noisy_environment": "whatsapp_follow_up",
        "request_whatsapp": "whatsapp_follow_up",
        "human_requested": "human_follow_up",
        "angry_or_uncomfortable": "closing",
        "unclear": "rsvp_confirmation",
        "silence": "rsvp_question",
    }.get(intent, "rsvp_question")


# ──────────────────────────────────────────────────────────────────
# Short Swahili response library — used by tools and tests.
# ──────────────────────────────────────────────────────────────────

def repair_line(event_name: str) -> str:
    return (
        "Samahani. Napiga kutoka Nuru kwa niaba ya mratibu wa tukio. "
        f"Ni kuhusu mwaliko wako wa tukio la {event_name}. "
        "Ningependa tu kuthibitisha kama utahudhuria."
    )


def identity_line(event_name: str) -> str:
    return (
        "Mimi ni Nuru Voice Assistant. "
        f"Napiga kwa niaba ya mratibu wa tukio la {event_name}. "
        "Namba yako ipo kwenye orodha ya wageni walioalikwa kwenye tukio hili."
    )


def confirm_clarifier(event_name: str) -> str:
    return (
        f"Ili nihifadhi vizuri, unamaanisha utahudhuria tukio la {event_name}?"
    )


def silence_prompt(n: int, event_name: str) -> str:
    if n <= 1:
        return "Halo, unanipata?"
    if n == 2:
        return f"Naomba nikurudie kwa kifupi. Je, utahudhuria tukio la {event_name}?"
    return (
        "Sawa, inaonekana muda huu haupo vizuri. "
        "Tutakutumia ujumbe kupitia WhatsApp. Asante."
    )


def noisy_line() -> str:
    return (
        "Samahani kwa hilo. Naweza kukutumia ujumbe kupitia WhatsApp "
        "au kukupigia baadaye."
    )


def callback_line() -> str:
    return "Nimekuelewa. Naweza kukupigia muda mwingine unaofaa."


def annoyed_line() -> str:
    return (
        "Samahani kwa usumbufu. Ningependa tu kuthibitisha kama utahudhuria. "
        "Ukisema ndiyo au hapana, nitahifadhi majibu yako na sitakuchukulia "
        "muda zaidi."
    )


def friendly_close() -> str:
    return "Asante sana. Tumefurahi kusikia utahudhuria. Karibu sana."


# ──────────────────────────────────────────────────────────────────
# System prompt addendum — appended to the RSVP agent prompt so Gemini
# Live uses the same vocabulary live on the call.
# ──────────────────────────────────────────────────────────────────

NATURAL_CONVERSATION_RULES_SW = """
Sheria za mazungumzo ya asili (lazima zifuatwe):

1) Usitarajie majibu ya moja kwa moja tu (ndio/hapana/labda). Watu
   wanaweza kujibu kwa njia tofauti. Tafsiri nia, kisha jibu kwa upole.

2) Ukiulizwa "wewe ni nani" au "umenipataje", jibu hivi mara moja:
   "Mimi ni Nuru Voice Assistant. Napiga kwa niaba ya mratibu wa tukio.
   Namba yako ipo kwenye orodha ya wageni walioalikwa." Kamwe usidai
   wewe ni mtu wa kweli wala usitoe jina la kibinadamu.

3) Mtu akisema 'sikusikii', 'rudia', 'unasema?', usichukulie kama jibu
   la RSVP. Rudia kwa kifupi swali la mwaliko mara moja tu. Akishindwa
   kusikia tena, tumia request_whatsapp_followup na funga kwa upole.

4) Ukikutana na kelele, mtandao mbovu au mtu yu busy, tumia
   request_callback (akitaka simu baadaye) au request_whatsapp_followup
   (akitaka WhatsApp). Usimsumbue.

5) Ukikatizwa (mtu akianza kuongea wakati unaongea), nyamaza mara moja,
   sikiliza, kisha jibu kile alichosema. Usiendelee na hotuba yako.

6) Hifadhi save_rsvp PEKEE wakati jibu liko wazi (ndio, hapana, labda,
   nipigie baadaye, namba si yake). Likiwa halieleweki, uliza swali moja
   fupi la uthibitisho: "Ili nihifadhi vizuri, unamaanisha utahudhuria?"
   Likibaki halieleweki, tumia mark_human_follow_up.

7) Mtu akionekana amekasirika au kukerwa, kuwa mfupi sana, omba radhi,
   tumia mark_opt_out akiomba asipigiwe tena.

8) Mwishoni mwa kila simu, tumia log_conversation_quality kuandika
   ubora wa mazungumzo (mood, quality, idadi ya kukatizwa, idadi ya
   ukimya, idadi ya ufafanuzi, na kiwango cha uhakika).

9) Usiseme misemo mirefu ya kirobo kama "Ninathibitisha kupokea taarifa
   zako kikamilifu." Tumia Kiswahili rahisi: "Nimekuelewa.", "Sawa,
   nimehifadhi hivyo.", "Karibu sana.", "Pole kwa usumbufu."
""".strip()


NATURAL_CONVERSATION_RULES_EN = """
Natural conversation rules (must follow):

1) Do not expect direct yes/no/maybe only. Interpret intent first, then
   reply politely. Save save_rsvp only when the answer is clear.

2) If asked who you are, answer once: "I'm the Nuru Voice Assistant
   calling on behalf of the event organiser. Your number is on the
   invited guest list." Never pretend to be a human person.

3) If the recipient says they cannot hear, repeat the question once,
   briefly. If they still cannot hear, call request_whatsapp_followup
   and end the call politely.

4) For noise / bad signal / busy recipient, use request_callback or
   request_whatsapp_followup. Don't push them.

5) On interruption: stop talking immediately, listen, then answer what
   they said. Don't keep reading the script.

6) For unclear answers, ask one short confirmation question. If still
   unclear, call mark_human_follow_up.

7) For angry / uncomfortable recipients, be very brief, apologise, and
   call mark_opt_out if they ask not to be called again.

8) At the end of every call, call log_conversation_quality with mood,
   quality, interruption_count, silence_count, clarification_count and
   final_confidence.

9) Keep replies short and human ("Got it.", "I've saved that.", "Sorry
   for the trouble.") — no robotic formal phrases.
""".strip()
