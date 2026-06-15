# core/config.py
import os
from dotenv import load_dotenv

load_dotenv()

DEBUG = os.getenv("DEBUG") == "True"
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DATABASE_URL = f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}?sslmode=require"
SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = os.getenv("ALGORITHM", "HS256")
SEWMR_SMS_BASE_URL = os.getenv("SEWMR_SMS_BASE_URL", "https://api.sewmrsms.co.tz/api/v1/")
SEWMR_SMS_ACCESS_TOKEN = os.getenv("SEWMR_SMS_ACCESS_TOKEN", "")
SEWMR_SMS_DEFAULT_SENDER_ID = os.getenv("SEWMR_SMS_DEFAULT_SENDER_ID", "")
# Phone that receives a heads-up SMS for every successful payment so the ops
# team can reconcile in real time. Falls back to the founders' line if unset.
ADMIN_NOTIFY_PHONE = os.getenv("ADMIN_NOTIFY_PHONE", "255764413610")
# Public base URL of this API — used to auto-build the SasaPay callback URL
# (and any other webhook URL) when an explicit override is not provided.
# Example: https://nuruapi.nuru.tz  →  callback becomes https://nuruapi.nuru.tz/api/v1/payments/callback
API_BASE_URL = os.getenv("API_BASE_URL", "").rstrip("/")
UPLOAD_SERVICE_URL = "https://data.sewmrtechnologies.com/handle-file-uploads"
DELETE_SERVICE_URL = "https://data.sewmrtechnologies.com/delete-file.php"
MAX_IMAGE_SIZE = 5 * 1024 * 1024  # 5MB
MAX_SERVICE_IMAGES = 4
MAX_EVENT_IMAGES = 3
ALLOWED_IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "webp", "avif"}
ALLOWED_UPLOAD_EXTENSIONS = {"jpg", "jpeg", "png", "webp", "pdf", "doc", "docx", "mp4", "mov", "avi"}
MAX_KYC_FILE_SIZE = 5 * 1024 * 1024  # 5MB
MAX_FILES_PER_KYC = 3
REFRESH_TOKEN_EXPIRE_DAYS = 30  # 30 days
ACCESS_TOKEN_EXPIRE_MINUTES = 1440  # 24 hours
RESET_TOKEN_EXPIRE_MINUTES = 10
MOMENT_EXPIRY_HOURS = 24
OTP_SERVICE_SECRET = os.getenv("OTP_SERVICE_SECRET", "")
ENV = os.getenv("ENV", "development")

# Deployment mode: "vps" (Redis + Celery available) or "vercel" (serverless, no Redis/Celery)
# When set to "vercel", all caching no-ops gracefully and Celery beat/workers are not assumed.
DEPLOYMENT_MODE = os.getenv("DEPLOYMENT_MODE", "vps").lower().strip()
USE_REDIS = DEPLOYMENT_MODE != "vercel"
USE_CELERY = DEPLOYMENT_MODE != "vercel"

# LiveKit
LIVEKIT_URL = os.getenv("LIVEKIT_URL", "")
LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY", "")
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET", "")


# =========================
# NURU VOICE ASSISTANT
# =========================
# Full spec lives in nuru_voice.md. Keep every flag here so phases 2-9 read
# from one source of truth. Missing required values do NOT crash the app —
# the voice router degrades to disabled and logs a warning at first use.

def _voice_env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "y", "on")


def _voice_env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


def _voice_env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


# --- Gemini ---
# All Gemini model + voice selection is BACKEND-CONTROLLED. These values are
# never exposed to public APIs, mobile/web clients, or campaign request
# bodies. To change the speaker or model, set the env var and restart.
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_TEXT_MODEL = os.getenv("GEMINI_TEXT_MODEL", "gemini-2.5-flash")
GEMINI_LIVE_MODEL = os.getenv(
    "GEMINI_LIVE_MODEL", "gemini-3.1-flash-live-preview"
)
GEMINI_LIVE_MODEL_FALLBACK = os.getenv(
    "GEMINI_LIVE_MODEL_FALLBACK", "gemini-2.5-flash-native-audio-preview-12-2025"
)
# Non-realtime TTS model — used only for developer voice tests / fallback TTS.
# MUST NOT be used as the main realtime call model.
GEMINI_TTS_MODEL = os.getenv("GEMINI_TTS_MODEL", "gemini-3.1-flash-tts-preview")
# Reserved for future live-translation features. NOT used for normal RSVP calls
# — those speak natural Tanzanian Swahili directly.
GEMINI_LIVE_TRANSLATE_MODEL = os.getenv(
    "GEMINI_LIVE_TRANSLATE_MODEL", "gemini-3.5-live-translate-preview"
)
GEMINI_VOICE_NAME = os.getenv("GEMINI_VOICE_NAME", "Zephyr")
GEMINI_VOICE_LANGUAGE = os.getenv("GEMINI_VOICE_LANGUAGE", "sw")
GEMINI_VOICE_STYLE = os.getenv("GEMINI_VOICE_STYLE", "calm")
GEMINI_VOICE_SPEAKING_RATE = os.getenv("GEMINI_VOICE_SPEAKING_RATE", "normal")


def get_gemini_model_config() -> dict:
    """Return the backend-controlled Gemini model selection.

    Never exposed to public APIs or clients. Use this everywhere instead of
    reading the individual env vars so the source of truth stays in one place.
    """
    return {
        "text_model": GEMINI_TEXT_MODEL,
        "live_model": GEMINI_LIVE_MODEL,
        "live_model_fallback": GEMINI_LIVE_MODEL_FALLBACK,
        "tts_model": GEMINI_TTS_MODEL,
        "live_translate_model": GEMINI_LIVE_TRANSLATE_MODEL,
    }


def get_gemini_voice_config() -> dict:
    """Return the backend-controlled Gemini speaker config.

    Speaker selection controls voice SOUND only, NOT language. Smart RSVP
    calls remain Swahili-first regardless of the speaker name.
    """
    return {
        "voice_name": GEMINI_VOICE_NAME,
        "language": GEMINI_VOICE_LANGUAGE,
        "style": GEMINI_VOICE_STYLE,
        "speaking_rate": GEMINI_VOICE_SPEAKING_RATE,
    }

# --- Voice language ---
VOICE_DEFAULT_LANGUAGE = os.getenv("VOICE_DEFAULT_LANGUAGE", "sw")
VOICE_FALLBACK_LANGUAGE = os.getenv("VOICE_FALLBACK_LANGUAGE", "en")

# --- Voice agent behavior ---
VOICE_AGENT_NAME = os.getenv("VOICE_AGENT_NAME", "Nuru Voice Assistant")
VOICE_DEFAULT_PURPOSE = os.getenv("VOICE_DEFAULT_PURPOSE", "rsvp")
VOICE_MAX_CALL_SECONDS = _voice_env_int("VOICE_MAX_CALL_SECONDS", 60)
VOICE_MAX_RETRY_ATTEMPTS = _voice_env_int("VOICE_MAX_RETRY_ATTEMPTS", 1)
VOICE_MIN_RETRY_DELAY_MINUTES = _voice_env_int("VOICE_MIN_RETRY_DELAY_MINUTES", 240)
VOICE_RETRY_BACKOFF_SECONDS = _voice_env_int(
    "VOICE_RETRY_BACKOFF_SECONDS", VOICE_MIN_RETRY_DELAY_MINUTES * 60,
)

# --- Twilio ---
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_VOICE_FROM_NUMBER = os.getenv("TWILIO_VOICE_FROM_NUMBER", "")
TWILIO_VOICE_PHONE_NUMBER_SID = os.getenv("TWILIO_VOICE_PHONE_NUMBER_SID", "")
TWILIO_VOICE_WEBHOOK_URL = os.getenv(
    "TWILIO_VOICE_WEBHOOK_URL",
    "https://nuruapi.nuru.tz/api/v1/voice-calls/twilio/webhook",
)
VOICE_AI_STREAM_URL = os.getenv(
    "VOICE_AI_STREAM_URL", "wss://nuruapi.nuru.tz/api/v1/voice-calls/stream"
)
TWILIO_STATUS_CALLBACK_URL = os.getenv(
    "TWILIO_STATUS_CALLBACK_URL",
    "https://nuruapi.nuru.tz/api/v1/voice-calls/twilio/status",
)

# --- Provider selection ---
VOICE_PROVIDER = os.getenv("VOICE_PROVIDER", "twilio").lower().strip()
VOICE_AI_PROVIDER = os.getenv("VOICE_AI_PROVIDER", "gemini").lower().strip()

# --- Timezone & calling hours ---
VOICE_DEFAULT_TIMEZONE = os.getenv("VOICE_DEFAULT_TIMEZONE", "Africa/Dar_es_Salaam")
# Backward-compatible alias — older code reading VOICE_TIMEZONE keeps working.
VOICE_TIMEZONE = os.getenv("VOICE_TIMEZONE", VOICE_DEFAULT_TIMEZONE)
VOICE_USE_RECIPIENT_TIMEZONE = _voice_env_bool("VOICE_USE_RECIPIENT_TIMEZONE", True)
VOICE_USE_EVENT_TIMEZONE = _voice_env_bool("VOICE_USE_EVENT_TIMEZONE", True)
VOICE_ALLOWED_START_HOUR = _voice_env_int("VOICE_ALLOWED_START_HOUR", 8)
VOICE_ALLOWED_END_HOUR = _voice_env_int("VOICE_ALLOWED_END_HOUR", 20)

# --- Privacy / follow-up ---
VOICE_RECORD_CALLS = _voice_env_bool("VOICE_RECORD_CALLS", False)
VOICE_SAVE_TRANSCRIPTS = _voice_env_bool("VOICE_SAVE_TRANSCRIPTS", True)
VOICE_SEND_WHATSAPP_FOLLOW_UP = _voice_env_bool("VOICE_SEND_WHATSAPP_FOLLOW_UP", True)

# --- Throughput limits ---
VOICE_MAX_CALLS_PER_CAMPAIGN = _voice_env_int("VOICE_MAX_CALLS_PER_CAMPAIGN", 50)
VOICE_MAX_CALLS_PER_USER_PER_DAY = _voice_env_int("VOICE_MAX_CALLS_PER_USER_PER_DAY", 100)

# --- International / safety ---
VOICE_ALLOW_INTERNATIONAL_CALLS = _voice_env_bool("VOICE_ALLOW_INTERNATIONAL_CALLS", True)
VOICE_ALLOWED_COUNTRIES = [
    c.strip().upper()
    for c in os.getenv("VOICE_ALLOWED_COUNTRIES", "TZ,KE,UG,RW,US,GB").split(",")
    if c.strip()
]
VOICE_BLOCK_EMERGENCY_NUMBERS = _voice_env_bool("VOICE_BLOCK_EMERGENCY_NUMBERS", True)
VOICE_ENABLE_COST_ESTIMATION = _voice_env_bool("VOICE_ENABLE_COST_ESTIMATION", True)
VOICE_MAX_ESTIMATED_CAMPAIGN_COST_USD = _voice_env_float(
    "VOICE_MAX_ESTIMATED_CAMPAIGN_COST_USD", 25.0
)


def voice_missing_required() -> dict:
    """Return groups of required-but-missing env vars. Empty dict means ready."""
    missing: dict = {}
    if VOICE_AI_PROVIDER == "gemini":
        gem = [k for k in ("GEMINI_API_KEY", "GEMINI_TEXT_MODEL", "GEMINI_LIVE_MODEL")
               if not globals().get(k)]
        if gem:
            missing["gemini"] = gem
    if VOICE_PROVIDER == "twilio":
        tw = [k for k in (
            "TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_VOICE_FROM_NUMBER",
            "TWILIO_VOICE_WEBHOOK_URL", "VOICE_AI_STREAM_URL",
            "TWILIO_STATUS_CALLBACK_URL",
        ) if not globals().get(k)]
        if tw:
            missing["twilio"] = tw
    return missing


def voice_is_ready() -> bool:
    return not voice_missing_required()
