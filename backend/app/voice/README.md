# Nuru Voice Assistant

Swahili-first AI voice calls (Smart RSVP and beyond) powered by Twilio Programmable Voice + Gemini Live. All code lives under `backend/app/voice/` and is fully isolated from existing call/messaging features.

## Architecture

```
Organiser (Web/Mobile)
        │
        ▼
/voice-calls/* REST  ────────────►  voice_campaigns / voice_call_jobs / voice_call_logs / voice_opt_outs
        │
        ▼
POST /jobs/{id}/place-call  ────►  Twilio REST (place_call)
                                         │
                          ┌──────────────┴──────────────┐
                          ▼                              ▼
              Twilio webhook → TwiML            Status callback → updates logs + retries
                          │
                          ▼
               <Connect><Stream url=VOICE_AI_STREAM_URL/>
                          │
                          ▼
        WebSocket /voice-calls/stream  ◄──►  Gemini Live (BidiGenerateContent)
                          │
                          ▼
           RSVP agent tools (save_rsvp / mark_opt_out / escalate_to_human)
                          │
                          ▼
             EventInvitation + EventAttendee sync (existing models)
```

## Modules

| File | Purpose |
|------|---------|
| `core/config.py` (voice_*) | Env-driven settings + non-fatal startup validator (`voice_missing_required`, `voice_is_ready`). |
| `voice/safety.py` | E.164 normalization, emergency-number blocklist, country allow-list, opt-out + calling-hour checks. Returns structured `CallVerdict`. |
| `voice/timezone.py` | Country → IANA TZ map, recipient-aware `resolve_timezone`, `within_calling_hours`. |
| `voice/twilio_client.py` | httpx wrapper around Twilio REST (`place_call`, `build_twiml`, status mapping). No SDK. |
| `voice/audio.py` | mulaw 8 kHz ↔ PCM16 (16 kHz/24 kHz) with pure-Python fallback for 3.13+. |
| `voice/realtime.py` | `StreamSession` + `handle_twilio_stream` driving the Media Streams socket; pluggable `AgentBridge`. |
| `voice/ai/gemini_text.py` | Gemini REST helper (`generate`, `generate_json`, `summarise_call`, `classify_rsvp`). |
| `voice/ai/gemini_live.py` | `GeminiLiveBridge` over BidiGenerateContent WebSocket, with model fallback + `respond_to_tool_call`. |
| `voice/agents/rsvp_agent.py` | Swahili system prompt + tool schema + executors that sync RSVPInvitation / EventAttendee. |
| `api/routes/voice_calls.py` | REST surface under `/voice-calls` (campaigns, jobs, logs, opt-outs, twilio webhook + status, stream WS, place-call, health). |
| `models/voice_calls.py` | `VoiceCampaign`, `VoiceCallJob`, `VoiceCallLog`, `VoiceOptOut`. |
| `alembic/versions/2026_06_15_1100-*` | Tables + indexes (idempotent). |

## Lifecycle

1. **Create campaign** — `POST /voice-calls/campaigns` (auto `purpose=rsvp`, `language=sw`).
2. **Add recipients** — `POST /voice-calls/campaigns/{id}/jobs`. Each recipient runs through `check_can_call`; blocked numbers are still persisted with `block_reason` for transparency.
3. **Start** — `POST /voice-calls/campaigns/{id}/start` flips status to `queued`/`running`. The organiser dashboard (web + mobile) polls every 8 s.
4. **Place call** — `POST /voice-calls/jobs/{id}/place-call` calls Twilio. A `voice_call_logs` row is written immediately.
5. **Twilio webhook** — `POST /voice-calls/twilio/webhook?job_id=…` returns TwiML with a Swahili greeting and `<Connect><Stream/>` pointing at our WS.
6. **Realtime** — `wss://…/voice-calls/stream` bridges Twilio (mulaw 8k) ↔ Gemini Live (PCM16). Tool calls are executed inside `voice/agents/rsvp_agent.py` and the result is sent back to the model so it can confirm in Swahili before hanging up.
7. **Status callback** — `POST /voice-calls/twilio/status` updates the log, derives the job status, and schedules retries (`VOICE_RETRY_BACKOFF_SECONDS`) for `busy`/`no-answer`/`failed` while attempts remain.

## Frontend

- **Web** — `/voice-calls` (`src/pages/VoiceCalls.tsx`) with campaign + opt-out tabs, live job table, per-call transcript drawer.
- **Mobile** — `mobile/nuru/lib/screens/events/widgets/smart_rsvp_calls_screen.dart` — Swahili-first organiser screen embedded inside an event with dark hero card, runtime controls, and 92 %-height per-call detail sheet.

## Required secrets (production)

| Secret | Used by |
|--------|---------|
| `GEMINI_API_KEY` | `gemini_text.py`, `gemini_live.py` |
| `TWILIO_ACCOUNT_SID` | `twilio_client.py` |
| `TWILIO_AUTH_TOKEN` | `twilio_client.py` |
| `TWILIO_VOICE_FROM_NUMBER` | outbound caller ID |
| `TWILIO_VOICE_WEBHOOK_URL` | TwiML endpoint (`/voice-calls/twilio/webhook`) |
| `TWILIO_STATUS_CALLBACK_URL` | status endpoint (`/voice-calls/twilio/status`) |
| `VOICE_AI_STREAM_URL` | `wss://…/voice-calls/stream` |

Optional overrides: `GEMINI_LIVE_MODEL`, `GEMINI_LIVE_MODEL_FALLBACK`, `GEMINI_VOICE_NAME`, `VOICE_MAX_CALL_SECONDS`, `VOICE_MAX_RETRY_ATTEMPTS`, `VOICE_MIN_RETRY_DELAY_MINUTES`, `VOICE_RETRY_BACKOFF_SECONDS`, `VOICE_DEFAULT_LANGUAGE`, `VOICE_DEFAULT_TIMEZONE`, `VOICE_SAVE_TRANSCRIPTS`, `VOICE_COUNTRY_ALLOWLIST`.

Missing secrets do **not** crash the app — `voice_is_ready()` reports false and the API returns 503 from `place-call` with a clear message.

## Safety

- Emergency numbers (911, 112, 999, 117, 118, 110, …) hard-blocked.
- Country allow-list defaults to Tanzania (`TZ`); extendable via env.
- Calling hours enforced per recipient timezone (defaults to Africa/Dar_es_Salaam, 08:00–20:00 EAT).
- Global `voice_opt_outs` table — checked at both enqueue and dial time.
- `VOICE_MAX_CALL_SECONDS` auto-hangup inside the WS bridge.

## Out of scope (future)

- WhatsApp Business Calling provider.
- Africa's Talking provider.
- Per-organiser usage analytics dashboard.
- Inbound calls (recipient-initiated).
