# Nuru Voice AI Assistant

## 1. Overview

Nuru can support voice based AI conversations where the system initiates a call to a guest, contributor, committee member, vendor, or event organiser, then speaks naturally, listens to the response, understands the answer, and updates Nuru automatically.

This must be built as a controlled Voice AI Agent connected to Nuru’s backend, not as a normal mobile phone call placed directly from the user’s device.

The core idea is:

```text
Nuru starts the call
User answers
AI speaks naturally
AI listens
AI asks questions
AI understands the answer
AI saves the result in Nuru
```

This feature turns Nuru from an event management app into a real event assistant that follows up with people automatically.

Nuru can call local and international users. The system must therefore support timezone aware call scheduling. Tanzania can be the default timezone, but it must not be treated as the only timezone.

Production implementation must support secure credentials, call limits, opt out rules, timezone resolution, international calling controls, provider status updates, call transcripts, audit logs, and human fallback.

---

# 2. Main Use Cases

## 2.1 RSVP Confirmation

Nuru can call invited guests and ask whether they will attend an event.

Example:

```text
Habari, tunapiga kutoka Nuru kwa niaba ya mratibu wa tukio la Send Off ya Melody.
Je, umepokea mwaliko wako?
Je, utahudhuria?
```

The AI then saves the response as:

```text
confirmed
declined
maybe
no answer
wrong number
call later
```

## 2.2 Contribution Reminders

Nuru can call contributors who pledged or were invited to contribute.

Example:

```text
Tunapiga kutoka Nuru kuhusu mchango wa tukio la harusi ya Joseph na Ashura.
Uliahidi kuchangia shilingi elfu hamsini.
Ungependa kulipa sasa, baadaye, au ukumbushwe muda mwingine?
```

The system can then update:

```text
pledge still active
payment promised
reminder requested
declined
wrong number
human follow up needed
```

## 2.3 Guest Verification

Nuru can call guests to confirm identity or invitation details before the event.

Example:

```text
Tafadhali thibitisha kama wewe ni Asha John aliyealikwa kwenye tukio la Joseph na Ashura Wedding.
```

## 2.4 Committee Follow Up

Nuru can call committee members and ask for progress updates.

Example:

```text
Ulikabidhiwa jukumu la ukumbi.
Je, kazi imekamilika, inaendelea, au kuna changamoto yoyote?
```

The AI can save:

```text
completed
in progress
needs help
not started
human follow up needed
```

## 2.5 Vendor Booking Confirmation

Nuru can call vendors after a booking request or payment.

Example:

```text
Mteja amekuchagua kwa huduma ya mapambo kwenye tukio la Send Off.
Je, unathibitisha kupokea booking hii?
```

The AI can update vendor status:

```text
accepted
declined
needs more details
unreachable
human follow up needed
```

## 2.6 Event Feedback

After an event, Nuru can call attendees and ask for feedback.

Example:

```text
Asante kwa kuhudhuria tukio.
Kwa kifupi, tukio lilikuwaje?
```

The AI can save:

```text
positive feedback
negative feedback
neutral feedback
complaint
suggestion
human follow up needed
```

---

# 3. Recommended Product Name

The main feature should be called:

```text
Nuru Voice Assistant
```

For RSVP specific calling, use:

```text
Smart RSVP Calls
```

Other possible names:

```text
Msaidizi wa Sauti
Nuru Call Follow Up
Auto RSVP Caller
Voice Follow Up
```

Recommended final naming:

```text
Main feature: Nuru Voice Assistant
RSVP feature: Smart RSVP Calls
```

---

# 4. Production Starting Point

The first production release should focus on:

```text
Smart RSVP Calls
```

Reason:

RSVP has clear value, short conversations, simple answers, and direct event impact.

The first production release should do this:

```text
Call invited guests with pending RSVP
Ask if they received the invitation
Ask if they will attend
Save RSVP answer
Send WhatsApp follow up if needed
Show call result in Nuru dashboard
Respect call limits
Respect timezone rules
Respect opt out rules
Escalate unclear cases to human follow up
```

This gives Nuru immediate business value while keeping the first production release controlled and reliable.

---

# 5. Recommended Development Phases

## Phase 1: Production Backend Foundation

Build the production backend foundation first.

This phase should include:

```text
Environment configuration
Credential validation
Database tables
Campaign APIs
Call logs
Timezone resolution
Calling hour guard
Call limits
Opt out rules
Twilio provider client
Gemini text client
Gemini Live client
Webhook endpoints
Status callback endpoints
Realtime audio WebSocket
```

## Phase 2: In App AI Voice Assistant

Build a voice assistant inside the Nuru mobile app.

Example flow:

```text
User opens Nuru
User taps “Nuru Voice Assistant”
Assistant asks what the user wants to do
User speaks
Assistant helps create event, add guests, prepare invitation text, or check RSVP
```

Possible actions:

```text
Create event
Add guest
Prepare invitation message
Generate event budget
Check ticket sales
Check RSVP status
Create checklist items
```

Recommended stack:

```text
Flutter app
Audio recording or streaming
Nuru backend
Gemini Live API or another realtime voice AI engine
```

## Phase 3: Outbound RSVP Calls

Add production outgoing calls.

Example:

```text
Organizer opens event
Organizer goes to RSVP
Organizer selects pending guests
Organizer starts Smart RSVP Calls
Nuru calls guests
AI asks RSVP questions
Nuru saves answers
```

This phase should support:

```text
Swahili first
Short calls
Clear event context
Call status tracking
WhatsApp follow up
Call retry rules
Opt out support
Timezone aware calling
International number support
Cost controls
Human fallback
```

## Phase 4: Full AI Call Campaigns

Later, Nuru can support large call campaigns.

Example:

```text
Call 500 guests
Ask RSVP
Collect answers
Detect wrong numbers
Schedule callbacks
Escalate unclear answers to human
Send final report to organizer
```

This phase should include:

```text
Campaign dashboard
Bulk calling
Call scheduling
Human escalation
Transcript review
AI confidence score
Call summaries
Advanced analytics
International calling rules
Country based cost estimate
Recipient timezone detection
Provider failure handling
```

---

# 6. High Level Architecture

The recommended architecture is:

```text
Nuru Mobile or Web
   ↓
Nuru Backend
   ↓
Voice Provider
   ↓
Phone call to recipient
   ↓
Realtime audio stream
   ↓
AI Voice Engine
   ↓
Nuru Backend tools
   ↓
Database updates
```

Expanded version:

```text
Organizer starts voice campaign
Nuru backend creates call jobs
Celery queues calls
Voice provider places calls
Recipient answers
Voice provider streams audio to Nuru backend
Nuru backend connects call to AI voice engine
AI speaks and listens
AI calls backend tools
Nuru saves result
Dashboard updates
```

---

# 7. Recommended Technical Stack

## 7.1 Backend

Use the existing Nuru backend style:

```text
FastAPI
PostgreSQL
Redis
Celery
WebSocket endpoint for realtime call audio
```

## 7.2 Voice Provider

Start with:

```text
Twilio Voice
```

Why:

```text
Good documentation
Supports outbound calls
Supports realtime audio streaming
Supports status callbacks
Supports international calling where account permissions and country rules allow it
Works well for production voice automation
```

Production requirements:

```text
Use a dedicated production Twilio voice capable number
Use a fully upgraded Twilio account
Enable required international permissions
Configure production billing
Configure webhook URLs
Configure status callback URLs
Monitor call usage and cost
Block emergency numbers
Block unsupported countries where needed
```

Also evaluate:

```text
Africa's Talking Voice
```

Why:

```text
Africa focused
May be better for Tanzania and regional pricing
Better local market fit
Useful as a future provider option
```

Later consider:

```text
WhatsApp Business Calling API
```

Why:

```text
Users already trust WhatsApp
Better answer rate than unknown phone numbers
Works well with existing Nuru WhatsApp flow
```

## 7.3 AI Voice Engine

Recommended first option:

```text
Gemini Live API
```

Use Gemini Live for realtime voice conversation.

Use Gemini text model for normal backend AI tasks such as:

```text
RSVP classification
Call summaries
Transcript cleanup
Script generation
Human follow up extraction
Language detection
Sentiment detection
```

The production system should separate realtime voice tasks from normal text tasks to reduce cost, improve reliability, and keep call handling predictable.

---

# 8. Environment Variables

The developer agent must use environment variables for all AI, voice provider, model, call limit, webhook, timezone, and safety settings.

Do not hardcode API keys, model names, Twilio credentials, call limits, webhook URLs, language settings, timezone settings, or safety settings inside the codebase.

Use the following variables.

```env
# =========================
# GOOGLE GEMINI
# =========================

# Full Google AI Studio API key.
# Required when VOICE_AI_PROVIDER="gemini".
GEMINI_API_KEY="your_real_google_ai_studio_api_key"

# Text model for normal backend AI tasks.
# Use this for RSVP classification, summaries, script generation, and non realtime logic.
GEMINI_TEXT_MODEL="gemini-2.5-flash"

# Realtime voice model for spoken conversation.
# Use this for live voice interaction if Gemini Live API is selected.
GEMINI_LIVE_MODEL="gemini-2.5-flash-native-audio-preview-12-2025"

# Optional fallback live model.
# Use this only if the primary live model is unavailable or fails.
GEMINI_LIVE_MODEL_FALLBACK="gemini-2.5-flash-native-audio-preview-09-2025"

# Optional voice name.
# Keep default unless the selected Gemini Live setup supports named voices.
GEMINI_VOICE_NAME="default"


# =========================
# VOICE LANGUAGE SETTINGS
# =========================

# Default call language.
# sw means Swahili.
VOICE_DEFAULT_LANGUAGE="sw"

# Fallback language if the recipient asks for English or Swahili fails.
VOICE_FALLBACK_LANGUAGE="en"


# =========================
# VOICE AGENT BEHAVIOR
# =========================

# Public name used by the AI during calls.
VOICE_AGENT_NAME="Nuru Voice Assistant"

# Default call purpose for the first production release.
VOICE_DEFAULT_PURPOSE="rsvp"

# Maximum allowed duration for one AI call.
# Production calls should remain short to control cost and avoid awkward conversations.
VOICE_MAX_CALL_SECONDS=60

# Maximum retry attempts after a failed or unanswered call.
VOICE_MAX_RETRY_ATTEMPTS=1

# Minimum delay before retrying a call.
# 240 minutes equals 4 hours.
VOICE_MIN_RETRY_DELAY_MINUTES=240


# =========================
# TWILIO VOICE
# =========================

# Twilio Account SID from Twilio Console.
# Required when VOICE_PROVIDER="twilio".
TWILIO_ACCOUNT_SID="your_real_twilio_account_sid"

# Twilio Auth Token from Twilio Console.
# Required when VOICE_PROVIDER="twilio".
TWILIO_AUTH_TOKEN="your_real_twilio_auth_token"

# Twilio voice capable phone number.
# This is the production number Nuru uses to call recipients.
TWILIO_VOICE_FROM_NUMBER="+1xxxxxxxxxx"

# Optional Twilio phone number SID.
# Not required for basic outbound calling, but useful when managing multiple Twilio numbers.
TWILIO_VOICE_PHONE_NUMBER_SID=""

# Public HTTPS webhook where Twilio asks Nuru for call instructions.
# This endpoint should return valid TwiML.
TWILIO_VOICE_WEBHOOK_URL="https://nuruapi.nuru.tz/api/v1/voice-calls/twilio/webhook"

# Public WSS endpoint for realtime call audio streaming.
# Twilio Media Streams should connect to this URL.
VOICE_AI_STREAM_URL="wss://nuruapi.nuru.tz/api/v1/voice-calls/stream"

# Public HTTPS status callback endpoint.
# Twilio sends call lifecycle updates here.
TWILIO_STATUS_CALLBACK_URL="https://nuruapi.nuru.tz/api/v1/voice-calls/twilio/status"


# =========================
# NURU VOICE PROVIDER SETTINGS
# =========================

# Voice call provider.
VOICE_PROVIDER="twilio"

# AI provider.
VOICE_AI_PROVIDER="gemini"


# =========================
# CALL SAFETY AND TIMEZONE SETTINGS
# =========================

# Default timezone used when recipient timezone, event timezone, and organizer timezone are unavailable.
# Tanzania is the default fallback because Nuru starts from Tanzania, but Nuru can still call international users.
VOICE_DEFAULT_TIMEZONE="Africa/Dar_es_Salaam"

# If true, use the recipient timezone when available.
# This prevents calling international guests at bad local hours.
VOICE_USE_RECIPIENT_TIMEZONE=true

# If true, use the event timezone when recipient timezone is unavailable.
VOICE_USE_EVENT_TIMEZONE=true

# Earliest allowed calling hour in the resolved timezone.
VOICE_ALLOWED_START_HOUR=8

# Latest allowed calling hour in the resolved timezone.
VOICE_ALLOWED_END_HOUR=20

# Backward compatible alias.
# Existing code that already reads VOICE_TIMEZONE should map it to VOICE_DEFAULT_TIMEZONE.
# New code should use VOICE_DEFAULT_TIMEZONE.
VOICE_TIMEZONE="Africa/Dar_es_Salaam"

# Whether to record calls.
# Keep false unless legal, consent, and privacy requirements are fully handled.
VOICE_RECORD_CALLS=false

# Whether to save transcripts.
VOICE_SAVE_TRANSCRIPTS=true

# Whether to send WhatsApp follow up after calls.
VOICE_SEND_WHATSAPP_FOLLOW_UP=true

# Maximum recipients in one campaign.
VOICE_MAX_CALLS_PER_CAMPAIGN=50

# Maximum calls one organizer can start per day.
VOICE_MAX_CALLS_PER_USER_PER_DAY=100


# =========================
# INTERNATIONAL CALLING AND PROVIDER SAFETY
# =========================

# If false, calls outside the default country list must be blocked.
VOICE_ALLOW_INTERNATIONAL_CALLS=true

# Comma separated country codes allowed for outbound calls.
# Example: TZ,KE,UG,RW,US,GB
VOICE_ALLOWED_COUNTRIES="TZ,KE,UG,RW,US,GB"

# If true, block known emergency numbers.
VOICE_BLOCK_EMERGENCY_NUMBERS=true

# If true, show or store estimated call cost before starting a campaign where pricing data is available.
VOICE_ENABLE_COST_ESTIMATION=true

# Optional maximum estimated cost per campaign.
VOICE_MAX_ESTIMATED_CAMPAIGN_COST_USD=25
```

---

# 9. Required Backend Configuration Rules

The developer agent must load these values from the backend settings layer.

Recommended settings object names:

```python
GEMINI_API_KEY
GEMINI_TEXT_MODEL
GEMINI_LIVE_MODEL
GEMINI_LIVE_MODEL_FALLBACK
GEMINI_VOICE_NAME

VOICE_DEFAULT_LANGUAGE
VOICE_FALLBACK_LANGUAGE
VOICE_AGENT_NAME
VOICE_DEFAULT_PURPOSE
VOICE_MAX_CALL_SECONDS
VOICE_MAX_RETRY_ATTEMPTS
VOICE_MIN_RETRY_DELAY_MINUTES

TWILIO_ACCOUNT_SID
TWILIO_AUTH_TOKEN
TWILIO_VOICE_FROM_NUMBER
TWILIO_VOICE_PHONE_NUMBER_SID
TWILIO_VOICE_WEBHOOK_URL
VOICE_AI_STREAM_URL
TWILIO_STATUS_CALLBACK_URL

VOICE_PROVIDER
VOICE_AI_PROVIDER

VOICE_DEFAULT_TIMEZONE
VOICE_USE_RECIPIENT_TIMEZONE
VOICE_USE_EVENT_TIMEZONE
VOICE_ALLOWED_START_HOUR
VOICE_ALLOWED_END_HOUR
VOICE_TIMEZONE

VOICE_RECORD_CALLS
VOICE_SAVE_TRANSCRIPTS
VOICE_SEND_WHATSAPP_FOLLOW_UP
VOICE_MAX_CALLS_PER_CAMPAIGN
VOICE_MAX_CALLS_PER_USER_PER_DAY

VOICE_ALLOW_INTERNATIONAL_CALLS
VOICE_ALLOWED_COUNTRIES
VOICE_BLOCK_EMERGENCY_NUMBERS
VOICE_ENABLE_COST_ESTIMATION
VOICE_MAX_ESTIMATED_CAMPAIGN_COST_USD
```

The backend must fail clearly during startup or first usage if required values are missing.

Required for Gemini:

```text
GEMINI_API_KEY
GEMINI_TEXT_MODEL
GEMINI_LIVE_MODEL
```

Required for Twilio:

```text
TWILIO_ACCOUNT_SID
TWILIO_AUTH_TOKEN
TWILIO_VOICE_FROM_NUMBER
TWILIO_VOICE_WEBHOOK_URL
VOICE_AI_STREAM_URL
TWILIO_STATUS_CALLBACK_URL
```

Required for safety and timezone:

```text
VOICE_DEFAULT_TIMEZONE
VOICE_USE_RECIPIENT_TIMEZONE
VOICE_USE_EVENT_TIMEZONE
VOICE_ALLOWED_START_HOUR
VOICE_ALLOWED_END_HOUR
VOICE_MAX_CALL_SECONDS
VOICE_MAX_CALLS_PER_CAMPAIGN
VOICE_MAX_CALLS_PER_USER_PER_DAY
VOICE_BLOCK_EMERGENCY_NUMBERS
```

Backward compatibility rule:

```text
If older code uses VOICE_TIMEZONE, it must behave the same as VOICE_DEFAULT_TIMEZONE.
New code should prefer VOICE_DEFAULT_TIMEZONE.
```

---

# 10. Model Usage Rules

Use the models as follows.

## 10.1 GEMINI_TEXT_MODEL

Use this for normal backend AI tasks:

```text
RSVP answer classification
Call summary generation
Transcript cleanup
Script generation
Human follow up reason extraction
Language detection
Sentiment detection
```

Default:

```env
GEMINI_TEXT_MODEL="gemini-2.5-flash"
```

## 10.2 GEMINI_LIVE_MODEL

Use this for realtime spoken calls.

Default:

```env
GEMINI_LIVE_MODEL="gemini-2.5-flash-native-audio-preview-12-2025"
```

This model is for live voice interaction where Nuru receives audio from the call provider and sends AI speech back into the call.

## 10.3 GEMINI_LIVE_MODEL_FALLBACK

Use this only when the primary live model fails.

Default:

```env
GEMINI_LIVE_MODEL_FALLBACK="gemini-2.5-flash-native-audio-preview-09-2025"
```

Do not use the live voice model for simple text tasks. It is more expensive and unnecessary for backend classification and summaries.

---

# 11. Twilio URL Rules

The developer agent must not confuse these URLs.

## 11.1 TWILIO_VOICE_WEBHOOK_URL

This is the HTTPS endpoint Twilio calls when starting or controlling a call.

Example:

```env
TWILIO_VOICE_WEBHOOK_URL="https://nuruapi.nuru.tz/api/v1/voice-calls/twilio/webhook"
```

This endpoint should return TwiML.

It should tell Twilio to connect the call audio to the stream URL.

## 11.2 VOICE_AI_STREAM_URL

This is the WSS endpoint used for realtime audio streaming.

Example:

```env
VOICE_AI_STREAM_URL="wss://nuruapi.nuru.tz/api/v1/voice-calls/stream"
```

This endpoint should handle Twilio Media Stream WebSocket messages.

It should connect the call audio to the selected AI live voice model.

## 11.3 TWILIO_STATUS_CALLBACK_URL

This is the HTTPS endpoint Twilio uses to send call status updates.

Example:

```env
TWILIO_STATUS_CALLBACK_URL="https://nuruapi.nuru.tz/api/v1/voice-calls/twilio/status"
```

It should update call log statuses such as:

```text
queued
ringing
answered
in_progress
completed
busy
failed
no_answer
cancelled
```

---

# 12. Security Rules for Environment Variables

The developer agent must follow these rules.

```text
Never commit real API keys to Git.
Never expose GEMINI_API_KEY in Flutter.
Never expose TWILIO_AUTH_TOKEN in Flutter.
Never expose secrets in frontend JavaScript.
Never print secrets in logs.
Never return secrets from any API endpoint.
Use separate keys for development and production.
Rotate any key that is accidentally exposed.
```

The mobile app and web frontend must call Nuru backend APIs only.

They must never call Gemini or Twilio directly with secret credentials.

Correct flow:

```text
Nuru Mobile or Web
   ↓
Nuru Backend
   ↓
Gemini or Twilio
```

Wrong flow:

```text
Nuru Mobile or Web
   ↓
Gemini or Twilio directly using secret keys
```

---

# 13. Example Backend Settings Class

The developer agent can implement settings like this.

```python
from pydantic_settings import BaseSettings


class VoiceAISettings(BaseSettings):
    GEMINI_API_KEY: str | None = None
    GEMINI_TEXT_MODEL: str = "gemini-2.5-flash"
    GEMINI_LIVE_MODEL: str = "gemini-2.5-flash-native-audio-preview-12-2025"
    GEMINI_LIVE_MODEL_FALLBACK: str = "gemini-2.5-flash-native-audio-preview-09-2025"
    GEMINI_VOICE_NAME: str = "default"

    VOICE_DEFAULT_LANGUAGE: str = "sw"
    VOICE_FALLBACK_LANGUAGE: str = "en"
    VOICE_AGENT_NAME: str = "Nuru Voice Assistant"
    VOICE_DEFAULT_PURPOSE: str = "rsvp"
    VOICE_MAX_CALL_SECONDS: int = 60
    VOICE_MAX_RETRY_ATTEMPTS: int = 1
    VOICE_MIN_RETRY_DELAY_MINUTES: int = 240

    TWILIO_ACCOUNT_SID: str | None = None
    TWILIO_AUTH_TOKEN: str | None = None
    TWILIO_VOICE_FROM_NUMBER: str | None = None
    TWILIO_VOICE_PHONE_NUMBER_SID: str | None = None
    TWILIO_VOICE_WEBHOOK_URL: str | None = None
    VOICE_AI_STREAM_URL: str | None = None
    TWILIO_STATUS_CALLBACK_URL: str | None = None

    VOICE_PROVIDER: str = "twilio"
    VOICE_AI_PROVIDER: str = "gemini"

    VOICE_DEFAULT_TIMEZONE: str = "Africa/Dar_es_Salaam"
    VOICE_USE_RECIPIENT_TIMEZONE: bool = True
    VOICE_USE_EVENT_TIMEZONE: bool = True
    VOICE_ALLOWED_START_HOUR: int = 8
    VOICE_ALLOWED_END_HOUR: int = 20

    # Backward compatible alias.
    # New code should use VOICE_DEFAULT_TIMEZONE.
    VOICE_TIMEZONE: str | None = None

    VOICE_RECORD_CALLS: bool = False
    VOICE_SAVE_TRANSCRIPTS: bool = True
    VOICE_SEND_WHATSAPP_FOLLOW_UP: bool = True

    VOICE_MAX_CALLS_PER_CAMPAIGN: int = 50
    VOICE_MAX_CALLS_PER_USER_PER_DAY: int = 100

    VOICE_ALLOW_INTERNATIONAL_CALLS: bool = True
    VOICE_ALLOWED_COUNTRIES: str = "TZ,KE,UG,RW,US,GB"
    VOICE_BLOCK_EMERGENCY_NUMBERS: bool = True
    VOICE_ENABLE_COST_ESTIMATION: bool = True
    VOICE_MAX_ESTIMATED_CAMPAIGN_COST_USD: float = 25.0

    class Config:
        env_file = ".env"
        extra = "ignore"

    @property
    def resolved_default_timezone(self) -> str:
        return self.VOICE_DEFAULT_TIMEZONE or self.VOICE_TIMEZONE or "Africa/Dar_es_Salaam"

    @property
    def allowed_country_list(self) -> list[str]:
        return [
            code.strip().upper()
            for code in self.VOICE_ALLOWED_COUNTRIES.split(",")
            if code.strip()
        ]


voice_ai_settings = VoiceAISettings()
```

---

# 14. Startup Validation

The backend should validate configuration before starting voice campaigns.

Example:

```python
def validate_voice_ai_config() -> None:
    missing = []

    if voice_ai_settings.VOICE_AI_PROVIDER == "gemini":
        if not voice_ai_settings.GEMINI_API_KEY:
            missing.append("GEMINI_API_KEY")
        if not voice_ai_settings.GEMINI_TEXT_MODEL:
            missing.append("GEMINI_TEXT_MODEL")
        if not voice_ai_settings.GEMINI_LIVE_MODEL:
            missing.append("GEMINI_LIVE_MODEL")

    if voice_ai_settings.VOICE_PROVIDER == "twilio":
        if not voice_ai_settings.TWILIO_ACCOUNT_SID:
            missing.append("TWILIO_ACCOUNT_SID")
        if not voice_ai_settings.TWILIO_AUTH_TOKEN:
            missing.append("TWILIO_AUTH_TOKEN")
        if not voice_ai_settings.TWILIO_VOICE_FROM_NUMBER:
            missing.append("TWILIO_VOICE_FROM_NUMBER")
        if not voice_ai_settings.TWILIO_VOICE_WEBHOOK_URL:
            missing.append("TWILIO_VOICE_WEBHOOK_URL")
        if not voice_ai_settings.VOICE_AI_STREAM_URL:
            missing.append("VOICE_AI_STREAM_URL")
        if not voice_ai_settings.TWILIO_STATUS_CALLBACK_URL:
            missing.append("TWILIO_STATUS_CALLBACK_URL")

    if not voice_ai_settings.resolved_default_timezone:
        missing.append("VOICE_DEFAULT_TIMEZONE")

    if voice_ai_settings.VOICE_ALLOWED_START_HOUR >= voice_ai_settings.VOICE_ALLOWED_END_HOUR:
        missing.append("VOICE_ALLOWED_START_HOUR / VOICE_ALLOWED_END_HOUR invalid range")

    if voice_ai_settings.VOICE_MAX_CALL_SECONDS <= 0:
        missing.append("VOICE_MAX_CALL_SECONDS")

    if voice_ai_settings.VOICE_MAX_CALLS_PER_CAMPAIGN <= 0:
        missing.append("VOICE_MAX_CALLS_PER_CAMPAIGN")

    if voice_ai_settings.VOICE_MAX_CALLS_PER_USER_PER_DAY <= 0:
        missing.append("VOICE_MAX_CALLS_PER_USER_PER_DAY")

    if not voice_ai_settings.allowed_country_list:
        missing.append("VOICE_ALLOWED_COUNTRIES")

    if voice_ai_settings.VOICE_MAX_ESTIMATED_CAMPAIGN_COST_USD <= 0:
        missing.append("VOICE_MAX_ESTIMATED_CAMPAIGN_COST_USD")

    if missing:
        raise RuntimeError(
            "Voice AI configuration is incomplete or invalid: "
            + ", ".join(missing)
        )
```

The backend should call this before creating a campaign or starting a call.

---

# 15. Timezone Resolution Rules

Nuru can call international users. Calling hours must be checked using the best available timezone, not always Tanzania time.

The backend must resolve the timezone in this order:

```text
1. Recipient timezone, if VOICE_USE_RECIPIENT_TIMEZONE=true and recipient timezone exists
2. Event timezone, if VOICE_USE_EVENT_TIMEZONE=true and event timezone exists
3. Organizer timezone, if organizer timezone exists
4. VOICE_DEFAULT_TIMEZONE
5. VOICE_TIMEZONE, only as a backward compatible alias
6. Africa/Dar_es_Salaam as final hard fallback
```

Recommended helper:

```python
def resolve_call_timezone(
    recipient_timezone: str | None = None,
    event_timezone: str | None = None,
    organizer_timezone: str | None = None,
) -> str:
    if (
        voice_ai_settings.VOICE_USE_RECIPIENT_TIMEZONE
        and recipient_timezone
    ):
        return recipient_timezone

    if (
        voice_ai_settings.VOICE_USE_EVENT_TIMEZONE
        and event_timezone
    ):
        return event_timezone

    if organizer_timezone:
        return organizer_timezone

    return voice_ai_settings.resolved_default_timezone
```

Allowed calling hours must be checked against the resolved timezone.

Example:

```python
from datetime import datetime
from zoneinfo import ZoneInfo


def is_within_allowed_calling_hours(timezone_name: str) -> bool:
    now = datetime.now(ZoneInfo(timezone_name))
    current_hour = now.hour

    return (
        voice_ai_settings.VOICE_ALLOWED_START_HOUR
        <= current_hour
        < voice_ai_settings.VOICE_ALLOWED_END_HOUR
    )
```

No outbound call should start if the resolved local time is outside the allowed call window.

---

# 16. International Calling Rules

Production calling must support international numbers safely.

The backend must require phone numbers in E.164 format.

Examples:

```text
+255712345678
+254712345678
+14155552671
+447700900123
```

Invalid examples:

```text
0712345678
712345678
00255712345678
12345
```

The backend must normalize and validate numbers before creating call jobs.

Required checks:

```text
Number must be in E.164 format
Country must be allowed in VOICE_ALLOWED_COUNTRIES
Emergency numbers must be blocked
Recipient must not be opted out
Recipient must be linked to a real event or allowed Nuru workflow
Organizer must not exceed daily call limit
Campaign must not exceed campaign call limit
Estimated campaign cost must not exceed configured maximum when cost estimation is enabled
```

Emergency numbers must be blocked before calling.

Recommended blocked numbers:

```text
911
112
999
000
110
118
119
999999
```

If the number is blocked, save status:

```text
blocked_emergency_number
```

If the country is not allowed, save status:

```text
blocked_country_not_allowed
```

If cost is too high, save status:

```text
blocked_cost_limit
```

---

# 17. Agent Implementation Rules

The developer agent must obey the following implementation rules.

```text
Use VOICE_PROVIDER to decide which call provider integration to use.
Use VOICE_AI_PROVIDER to decide which AI provider integration to use.
Use GEMINI_TEXT_MODEL for text tasks.
Use GEMINI_LIVE_MODEL for realtime voice.
Use GEMINI_LIVE_MODEL_FALLBACK only when the main live model fails.
Use VOICE_DEFAULT_LANGUAGE as the default call language.
Use VOICE_MAX_CALL_SECONDS to end long calls.
Use VOICE_MAX_RETRY_ATTEMPTS before scheduling retries.
Use VOICE_MIN_RETRY_DELAY_MINUTES before retrying.
Use VOICE_DEFAULT_TIMEZONE as the default fallback timezone.
Use VOICE_USE_RECIPIENT_TIMEZONE to decide whether recipient timezone can control calling hours.
Use VOICE_USE_EVENT_TIMEZONE to decide whether event timezone can control calling hours.
Use VOICE_ALLOWED_START_HOUR and VOICE_ALLOWED_END_HOUR before placing calls.
Use VOICE_TIMEZONE only as a backward compatible alias.
Use VOICE_RECORD_CALLS before enabling recordings.
Use VOICE_SAVE_TRANSCRIPTS before saving transcripts.
Use VOICE_SEND_WHATSAPP_FOLLOW_UP before sending follow up messages.
Use VOICE_MAX_CALLS_PER_CAMPAIGN to limit campaign size.
Use VOICE_MAX_CALLS_PER_USER_PER_DAY to prevent abuse.
Use VOICE_ALLOW_INTERNATIONAL_CALLS before allowing calls outside the default country.
Use VOICE_ALLOWED_COUNTRIES to restrict outbound countries.
Use VOICE_BLOCK_EMERGENCY_NUMBERS before placing any call.
Use VOICE_ENABLE_COST_ESTIMATION when calculating expected campaign cost.
Use VOICE_MAX_ESTIMATED_CAMPAIGN_COST_USD to block expensive campaigns.
```

No voice call should be started if the current time is outside the allowed calling window for the resolved timezone.

No voice call should exceed the configured maximum duration.

No campaign should exceed the configured maximum campaign size.

No organizer should exceed the configured daily call limit.

No call should be placed to emergency numbers.

No call should be placed to blocked countries.

No call should start if the estimated campaign cost exceeds the configured limit.

---

# 18. Updated Production Stack

For the production release, use:

```text
Voice provider: Twilio Voice
Production phone number: Dedicated Twilio voice capable number
Realtime audio: Twilio Media Streams
AI voice: Gemini Live API
Realtime model: gemini-2.5-flash-native-audio-preview-12-2025
Text model: gemini-2.5-flash
Backend: FastAPI
Queue: Celery
Cache and broker: Redis
Database: PostgreSQL
Default language: Swahili
Default purpose: RSVP
Maximum call duration: 60 seconds
Default timezone: Africa/Dar_es_Salaam
Timezone behavior: recipient timezone first, event timezone second, organizer timezone third, default timezone last
```

The first production readiness test should prove this:

```text
Nuru backend starts a Twilio call using the configured production voice number.
The recipient answers.
Twilio streams audio to Nuru WebSocket.
Nuru connects the stream to Gemini Live.
The AI speaks in Swahili.
The recipient replies yes, no, maybe, call later, or wrong number.
The backend saves the RSVP result.
The backend stores call status updates.
The backend stores transcript if enabled.
The backend sends WhatsApp follow up if enabled.
The call ends politely.
```

---

# 19. Voice AI Call Flow

## 19.1 Basic RSVP Call Flow

```text
1. Nuru starts call.
2. Guest answers.
3. AI introduces itself.
4. AI mentions event name and organizer.
5. AI asks if the guest received the invitation.
6. AI asks if the guest will attend.
7. AI handles yes, no, maybe, wrong number, or call later.
8. AI saves RSVP result.
9. AI sends WhatsApp follow up if needed.
10. AI ends the call politely.
```

## 19.2 Example Swahili Script

```text
Habari, napiga kutoka Nuru kwa niaba ya mratibu wa tukio la Joseph na Ashura Wedding.

Tumekutumia mwaliko wa tukio hili.

Je, umeupokea?

[Listen]

Asante. Ningependa kufahamu kama utahudhuria tukio hili.

Utahudhuria?

[Listen]

Asante sana. Nimehifadhi majibu yako kwenye Nuru.

Kama utahitaji kuona mwaliko tena, tutakutumia kupitia WhatsApp.

Karibu sana.
```

## 19.3 If Guest Says Yes

```text
Asante sana. Nimekuweka kama utahudhuria.
Karibu sana kwenye tukio.
```

System action:

```text
save_rsvp_status(guest_id, "confirmed")
```

## 19.4 If Guest Says No

```text
Asante kwa kutujulisha.
Nimehifadhi kuwa hutaweza kuhudhuria.
```

System action:

```text
save_rsvp_status(guest_id, "declined")
```

## 19.5 If Guest Says Maybe

```text
Sawa, nimehifadhi kuwa bado hujathibitisha moja kwa moja.
Tunaweza kukukumbusha tena baadaye.
```

System action:

```text
save_rsvp_status(guest_id, "maybe")
```

## 19.6 If Guest Says They Did Not Receive Invitation

```text
Pole kwa hilo. Tutakutumia mwaliko kupitia WhatsApp au ujumbe mfupi muda si mrefu.
```

System action:

```text
send_invitation_link(guest_id)
mark_invitation_not_received(guest_id)
```

## 19.7 If Guest Says Wrong Number

```text
Samahani kwa usumbufu.
Tutarekebisha taarifa hii.
Asante.
```

System action:

```text
mark_wrong_number(guest_id)
```

## 19.8 If Guest Asks To Be Called Later

```text
Sawa. Tutakupigia muda mwingine unaofaa.
Asante.
```

System action:

```text
schedule_callback(guest_id, preferred_time)
```

When scheduling a callback, the backend must use the resolved timezone for that recipient.

---

# 20. AI Agent Rules

The AI must not be allowed to speak freely without boundaries.

It needs a controlled system instruction.

## 20.1 Core Rules

```text
Always say you are calling from Nuru.
Always mention the organizer or event name.
Never pretend to be a human.
Never invent event details.
Never promise anything not stored in Nuru.
Keep the call short.
Ask one question at a time.
Confirm important answers.
Save results only after clear confirmation.
Escalate unclear cases to human follow up.
Respect local calling hours.
Do not continue long conversations beyond the configured call duration.
Do not discuss unrelated topics.
Do not give legal, financial, or medical advice.
Do not collect sensitive information unrelated to the event.
```

## 20.2 Example AI System Instruction

```text
You are Nuru Voice Assistant.

You call guests on behalf of event organizers to confirm RSVP, send reminders, and collect simple event related answers.

You must speak natural Tanzanian Swahili unless the recipient requests English.

You must be polite, short, and clear.

You must not pretend to be a human.

You must clearly say you are calling from Nuru.

You must only use event information provided by the backend.

Your current task is to confirm RSVP for the event.

Ask if the guest received the invitation.

Then ask if the guest will attend.

Classify the answer as confirmed, declined, maybe, wrong number, call later, or unclear.

When you are confident, call the correct backend tool.

If the person sounds angry, confused, asks many unrelated questions, or requests a human, mark human follow up needed.

If the person asks to be called later, save callback request and end politely.

Do not ask for sensitive information.

Do not discuss topics outside the event.

End the call politely.
```

---

# 21. Backend Tools for AI

The AI should interact with Nuru using backend tools.

Recommended tools:

```text
save_rsvp_status(guest_id, status)
send_invitation_link(guest_id)
schedule_callback(guest_id, preferred_time)
mark_wrong_number(guest_id)
mark_no_answer(guest_id)
mark_human_follow_up_needed(guest_id, reason)
save_call_summary(call_id, summary)
save_transcript(call_id, transcript)
send_whatsapp_follow_up(guest_id, message_type)
resolve_call_timezone(guest_id, event_id, organizer_id)
```

Example tool call:

```json
{
  "tool": "save_rsvp_status",
  "guest_id": "guest_123",
  "status": "confirmed",
  "confidence": 0.94
}
```

---

# 22. Call Statuses

Each call should have a clear status.

Recommended statuses:

```text
queued
calling
ringing
answered
in_progress
completed
no_answer
busy
failed
cancelled
wrong_number
call_later
human_needed
blocked_outside_calling_hours
blocked_campaign_limit
blocked_daily_limit
blocked_opt_out
blocked_emergency_number
blocked_country_not_allowed
blocked_cost_limit
provider_rejected
```

RSVP result statuses:

```text
pending
confirmed
declined
maybe
checked_in
```

AI specific result statuses:

```text
clear_answer
unclear_answer
interrupted
language_issue
angry_recipient
human_requested
```

---

# 23. Dashboard Requirements

The organizer should see voice call progress clearly.

## 23.1 Campaign Summary

Show:

```text
Total selected guests
Calls queued
Calls completed
Confirmed
Declined
Maybe
No answer
Wrong number
Human follow up needed
Blocked outside calling hours
Blocked by country rule
Blocked by cost limit
Provider rejected
```

Example:

```text
34 guests selected
12 confirmed
3 declined
5 no answer
2 wrong numbers
1 needs human follow up
2 blocked outside calling hours
1 provider rejected
8 still pending
```

## 23.2 Guest Level View

For each guest, show:

```text
Guest name
Phone number
Call status
RSVP answer
AI summary
Last call time
Duration
Confidence score
Follow up action
Resolved timezone
Local call time
Provider call ID
Error message if failed
```

## 23.3 Call Detail Modal

The call detail page should show:

```text
Call status
Call timeline
Transcript
AI summary
Recording if allowed
Backend actions taken
Errors if any
Retry button
Mark manually button
Resolved timezone
Local call time
Provider call ID
```

---

# 24. Database Design

## 24.1 voice_call_campaigns

Purpose:

Stores a group of calls started by an organizer.

Fields:

```text
id
event_id
created_by_user_id
campaign_type
title
language
status
total_recipients
completed_count
failed_count
blocked_count
estimated_cost
actual_cost
currency
started_at
completed_at
created_at
updated_at
```

Recommended campaign types:

```text
rsvp
contribution_reminder
committee_follow_up
vendor_confirmation
event_feedback
```

## 24.2 voice_call_logs

Purpose:

Stores each individual call.

Fields:

```text
id
campaign_id
event_id
recipient_type
recipient_id
recipient_name
phone
phone_country
call_provider
provider_call_id
purpose
status
started_at
answered_at
ended_at
duration_seconds
resolved_timezone
local_call_time
ai_summary
final_intent
rsvp_status
confidence_score
recording_url
transcript_url
estimated_cost
actual_cost
currency
error_code
error_message
created_by_user_id
created_at
updated_at
```

Recommended recipient types:

```text
guest
contributor
committee_member
vendor
organizer
nuru_user
```

## 24.3 voice_call_transcripts

Purpose:

Stores call transcript messages.

Fields:

```text
id
call_log_id
speaker
message
language
timestamp_seconds
created_at
```

Recommended speakers:

```text
ai
recipient
system
```

## 24.4 voice_call_events

Purpose:

Stores technical events during the call.

Fields:

```text
id
call_log_id
event_type
payload
created_at
```

Example event types:

```text
call_queued
call_blocked_outside_calling_hours
call_started
call_answered
audio_stream_started
ai_spoke
recipient_spoke
tool_called
rsvp_saved
call_ended
call_failed
provider_status_received
```

## 24.5 voice_opt_outs

Purpose:

Stores people who should not be called again.

Fields:

```text
id
phone
recipient_name
event_id
reason
created_at
created_by_user_id
```

## 24.6 voice_agent_scripts

Purpose:

Stores reusable scripts and instructions for different call types.

Fields:

```text
id
name
purpose
language
system_prompt
opening_message
fallback_message
closing_message
is_active
created_at
updated_at
```

---

# 25. API Endpoints

## 25.1 Start RSVP Voice Campaign

```text
POST /api/v1/events/{event_id}/voice-calls/rsvp/start
```

Request:

```json
{
  "guest_ids": ["guest_1", "guest_2"],
  "language": "sw",
  "max_attempts": 1,
  "send_whatsapp_follow_up": true
}
```

Response:

```json
{
  "campaign_id": "campaign_123",
  "status": "queued",
  "total_recipients": 2
}
```

## 25.2 List Voice Campaigns

```text
GET /api/v1/events/{event_id}/voice-calls/campaigns
```

## 25.3 Get Campaign Detail

```text
GET /api/v1/voice-calls/campaigns/{campaign_id}
```

## 25.4 Get Call Logs

```text
GET /api/v1/events/{event_id}/voice-calls/logs
```

## 25.5 Get Single Call Detail

```text
GET /api/v1/voice-calls/logs/{call_log_id}
```

## 25.6 Retry Failed Call

```text
POST /api/v1/voice-calls/logs/{call_log_id}/retry
```

## 25.7 Mark Human Follow Up Done

```text
POST /api/v1/voice-calls/logs/{call_log_id}/human-follow-up/complete
```

## 25.8 Twilio Voice Webhook

```text
POST /api/v1/voice-calls/twilio/webhook
```

This endpoint receives Twilio call control requests and returns TwiML.

It should tell Twilio to connect the call to the realtime audio stream.

## 25.9 Twilio Status Callback

```text
POST /api/v1/voice-calls/twilio/status
```

This endpoint receives Twilio call status updates and updates call logs.

## 25.10 Realtime Audio WebSocket

```text
WS /api/v1/voice-calls/stream
```

This endpoint receives realtime audio from the call provider and connects it to the AI voice engine.

---

# 26. Backend Processing Flow

## 26.1 Campaign Creation

```text
1. Organizer selects guests.
2. Backend validates event ownership.
3. Backend validates phone numbers.
4. Backend checks country rules.
5. Backend blocks emergency numbers.
6. Backend checks opt out list.
7. Backend resolves timezone for each recipient.
8. Backend checks allowed calling hours for each resolved timezone.
9. Backend checks campaign size limit.
10. Backend checks organizer daily call limit.
11. Backend estimates campaign cost if enabled.
12. Backend validates voice AI configuration.
13. Backend creates voice_call_campaign.
14. Backend creates voice_call_logs.
15. Backend queues allowed call jobs in Celery.
16. Backend marks blocked calls with clear blocked statuses.
```

## 26.2 Call Job

```text
1. Celery picks a call job.
2. Backend checks retry limit.
3. Backend validates phone number again.
4. Backend resolves timezone again.
5. Backend checks allowed calling hours again.
6. Backend starts outbound call through provider.
7. Provider calls recipient.
8. Provider sends call events to status callback.
9. Provider streams audio to WebSocket.
10. Backend connects audio stream to AI.
11. AI speaks and listens.
12. AI calls backend tools.
13. Backend updates database.
14. Call ends.
```

## 26.3 After Call

```text
1. Save final transcript if VOICE_SAVE_TRANSCRIPTS=true.
2. Save AI summary.
3. Save RSVP result if captured.
4. Save provider call status.
5. Save actual duration.
6. Save actual cost if available.
7. Send WhatsApp follow up if enabled.
8. Update campaign totals.
9. Show result in dashboard.
```

---

# 27. Mobile App Flow

## 27.1 Organizer Flow

```text
Open Nuru mobile app
Open event
Go to RSVP or Guests tab
Tap Smart RSVP Calls
Select pending guests
Choose language
Preview script
Review estimated cost if available
Start calls
View live progress
Open call result details
```

## 27.2 Mobile UI Sections

### Smart RSVP Calls Landing

Show:

```text
Pending guests
Confirmed guests
Declined guests
No answer
Start Smart Calls button
```

### Guest Selection

Show:

```text
Guest name
Phone number
Current RSVP status
Resolved timezone if known
Checkbox
```

### Script Preview

Show:

```text
Language
Opening message
Main question
Closing message
Calling hours
Timezone rule
Estimated cost if available
```

### Live Progress

Show:

```text
Campaign status
Progress bar
Confirmed count
Declined count
No answer count
Human follow up count
Blocked outside calling hours count
Failed provider count
```

### Call Result Page

Show:

```text
Guest name
Final RSVP
Call summary
Transcript
Retry button
Manual update button
Resolved timezone
Local call time
Provider call status
```

---

# 28. Web Dashboard Flow

The web dashboard should support the same feature, but with more detailed controls.

Recommended sections:

```text
Voice Campaigns
Smart RSVP Calls
Call Logs
Transcripts
Opt Out List
Voice Scripts
Settings
Timezone and Calling Rules
Provider Settings
Cost Controls
```

Admin and organizer should see:

```text
Campaign name
Event name
Started by
Started time
Total calls
Success rate
Average duration
Failed calls
Blocked calls
Estimated cost
Actual cost
Timezone rule used
Provider status
```

---

# 29. Consent, Privacy, and Safety Rules

This feature must be handled carefully.

## 29.1 Required Rules

```text
Only call contacts linked to a real event.
Show organizer name or event name during the call.
Do not call random uploaded numbers without context.
Do not call at night.
Limit call attempts.
Allow opt out.
Respect wrong number responses.
Never pretend the AI is a real human.
Keep transcripts protected.
Avoid recording unless legally and clearly allowed.
Respect recipient local timezone where possible.
Block emergency numbers.
Block unsupported countries.
```

## 29.2 Recommended Calling Hours

Default allowed calling hours:

```text
Allowed: 08:00 to 20:00
Avoid: before 08:00
Avoid: after 20:00
```

These values must be controlled by:

```env
VOICE_DEFAULT_TIMEZONE="Africa/Dar_es_Salaam"
VOICE_USE_RECIPIENT_TIMEZONE=true
VOICE_USE_EVENT_TIMEZONE=true
VOICE_ALLOWED_START_HOUR=8
VOICE_ALLOWED_END_HOUR=20
```

Timezone behavior:

```text
Tanzania timezone is the default fallback.
Recipient timezone should be used first when known.
Event timezone should be used second when known.
Organizer timezone can be used third when known.
Default timezone should be used only when better timezone data is missing.
```

## 29.3 Call Attempt Limits

Recommended:

```text
Maximum 1 call attempt by default
Maximum 2 attempts if organizer enables retry
Minimum 4 hours between retry attempts
No retry after guest declines
No retry after opt out
No retry after wrong number
```

These values must be controlled by:

```env
VOICE_MAX_RETRY_ATTEMPTS=1
VOICE_MIN_RETRY_DELAY_MINUTES=240
```

## 29.4 AI Disclosure

The AI should say:

```text
Napiga kutoka Nuru kwa niaba ya mratibu wa tukio.
```

Avoid pretending:

```text
Mimi ni Happyphania.
```

Unless the product clearly defines Happyphania as a Nuru AI voice assistant and the user is not misled.

---

# 30. Error Handling

The system should handle these cases:

```text
Call not answered
Phone busy
Invalid phone number
Provider failure
AI connection failure
Audio stream failure
Unclear answer
User hangs up
User asks for human
User speaks unsupported language
Wrong number
Angry recipient
Outside allowed calling hours
Missing recipient timezone
Invalid timezone
International call blocked by provider
Country not allowed by Nuru settings
Emergency number blocked
Campaign cost too high
```

Recommended fallback actions:

```text
Send WhatsApp message
Mark no answer
Mark human follow up needed
Retry later
Stop calling this number
Notify organizer
Block call until allowed local time
Ask organizer to update guest phone number
Ask organizer to contact guest manually
```

---

# 31. Cost Control

Voice AI can become expensive if not controlled.

Use these rules:

```text
Keep RSVP calls under 60 seconds.
End the call after result is captured.
Do not allow long open ended conversations in the first production release.
Limit campaign size.
Show estimated cost before starting campaign.
Set daily call limits.
Set per organizer call limits.
Show international call cost warning when possible.
Block campaigns above configured cost limit.
```

Recommended production limits for first release:

```text
Maximum 50 calls per campaign
Maximum 1 minute per call
Maximum 1 retry
Swahili first
RSVP first
```

These values must be controlled by:

```env
VOICE_MAX_CALL_SECONDS=60
VOICE_MAX_CALLS_PER_CAMPAIGN=50
VOICE_MAX_CALLS_PER_USER_PER_DAY=100
VOICE_ENABLE_COST_ESTIMATION=true
VOICE_MAX_ESTIMATED_CAMPAIGN_COST_USD=25
```

---

# 32. First Production Release Scope

The first production release should include:

```text
Smart RSVP Calls
Swahili language
Outbound calls
Pending guests
One event at a time
Call status tracking
RSVP saving
WhatsApp follow up
Basic transcript
Basic AI summary
Timezone aware calling
Production Twilio voice number
International calling controls
Emergency number blocking
Cost control
No advanced analytics
No open ended conversations
```

Do not include in the first production release:

```text
Contribution calls
Vendor calls
Committee calls
Event feedback calls
Multiple AI personas
Advanced voice cloning
Long conversations
Complex language switching
Payment collection during call
Large international campaigns before pricing checks
```

---

# 33. Production Success Criteria

The production release is successful if:

```text
Organizer can select pending guests.
Nuru can call them.
Guest can answer naturally in Swahili.
AI can understand yes, no, maybe, call later, wrong number.
Nuru can save RSVP correctly.
Organizer can view results.
WhatsApp follow up can be sent.
No spam behavior happens.
Calls respect allowed local time.
International calls respect country rules.
Emergency numbers are blocked.
Call status updates are saved.
Provider errors are visible to admin.
```

Target accuracy:

```text
At least 90 percent correct RSVP classification on clear answers.
All unclear answers should go to human follow up.
```

---

# 34. Example Final User Experience

Organizer opens event:

```text
Joseph and Ashura Wedding
```

Nuru shows:

```text
47 invited guests
21 confirmed
4 declined
22 pending
```

Organizer taps:

```text
Smart RSVP Calls
```

Nuru shows:

```text
22 pending guests will be called.
Language: Swahili
Estimated duration: 15 to 25 minutes total
Calling window: 08:00 to 20:00 local time
Timezone rule: recipient timezone first, event timezone second, default timezone last
Estimated cost: shown if available
```

Organizer starts campaign.

Nuru calls guests.

After campaign:

```text
12 confirmed
3 declined
2 maybe
4 no answer
1 wrong number
2 blocked outside calling hours
```

Organizer opens details:

```text
Asha John
Status: Confirmed
Call duration: 38 seconds
Resolved timezone: Africa/Dar_es_Salaam
Local call time: 14:32
AI summary: Asha confirmed she will attend and asked to receive the invitation again on WhatsApp.
Action taken: RSVP updated and invitation resent.
```

---

# 35. Development Priority

Recommended build order:

```text
1. Database tables
2. Backend settings and environment validation
3. Phone number validation
4. Emergency number blocking
5. Country rule validation
6. Timezone resolution helper
7. Allowed calling hours guard
8. Cost estimation guard
9. Backend campaign APIs
10. Twilio call provider integration
11. Twilio webhook and status callback
12. Realtime audio stream WebSocket
13. Gemini text client
14. Gemini Live voice client
15. AI agent prompt and tools
16. RSVP saving tool
17. Call logs dashboard
18. Mobile Smart RSVP Calls UI
19. WhatsApp follow up
20. Retry and opt out rules
21. Cost and abuse limits
22. International calling and pricing checks
```

---

# 36. Final Recommendation

Nuru should build this feature as a controlled production system.

The first production release should be:

```text
Nuru Voice Assistant
Smart RSVP Calls
Swahili
Short calls
Pending guests only
Clear RSVP saving
WhatsApp follow up
Human fallback for unclear answers
Timezone aware calling
Production Twilio voice number
International calling controls
Emergency number blocking
Cost control
```

This creates real value immediately.

The strongest business value is not that AI can talk.

The strongest business value is that Nuru can collect real event answers automatically and update the event system without the organizer calling everyone manually.

That is a serious advantage for Nuru.
