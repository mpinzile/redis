"""Timezone resolution for outbound voice calls.

Resolution order (per nuru_voice.md §9 + §13):
    1. Explicit recipient timezone (when ``VOICE_USE_RECIPIENT_TIMEZONE`` is on).
    2. Event timezone (when ``VOICE_USE_EVENT_TIMEZONE`` is on).
    3. Country-code → timezone heuristic from the E.164 phone number.
    4. ``VOICE_DEFAULT_TIMEZONE`` (defaults to Africa/Dar_es_Salaam).

Only standard library is used (``zoneinfo``) so the helper has no extra deps.
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional

try:
    from zoneinfo import ZoneInfo  # py>=3.9
except Exception:  # pragma: no cover
    ZoneInfo = None  # type: ignore[assignment]

from core import config


# Minimal, deterministic country → IANA TZ mapping for the markets Nuru
# actually serves today. Falls through to the default for anything else.
_COUNTRY_TZ: dict[str, str] = {
    "TZ": "Africa/Dar_es_Salaam",
    "KE": "Africa/Nairobi",
    "UG": "Africa/Kampala",
    "RW": "Africa/Kigali",
    "BI": "Africa/Bujumbura",
    "ET": "Africa/Addis_Ababa",
    "ZA": "Africa/Johannesburg",
    "NG": "Africa/Lagos",
    "GB": "Europe/London",
    "US": "America/New_York",
    "CA": "America/Toronto",
    "AE": "Asia/Dubai",
    "IN": "Asia/Kolkata",
    "DE": "Europe/Berlin",
    "FR": "Europe/Paris",
}


# Crude E.164 dial-code → ISO-3166 mapping for the same set above. Phone-
# number-to-country is a hard problem; we deliberately keep this list short
# and let unknown numbers fall back to the default timezone.
_DIAL_TO_COUNTRY: list[tuple[str, str]] = [
    ("255", "TZ"),
    ("254", "KE"),
    ("256", "UG"),
    ("250", "RW"),
    ("257", "BI"),
    ("251", "ET"),
    ("27", "ZA"),
    ("234", "NG"),
    ("44", "GB"),
    ("971", "AE"),
    ("91", "IN"),
    ("49", "DE"),
    ("33", "FR"),
    ("1", "US"),  # also CA — close enough for call-hour purposes
]


def country_from_e164(phone_e164: str) -> Optional[str]:
    digits = (phone_e164 or "").lstrip("+")
    if not digits.isdigit():
        return None
    for dial, country in _DIAL_TO_COUNTRY:
        if digits.startswith(dial):
            return country
    return None


def resolve_timezone(
    *,
    recipient_tz: Optional[str] = None,
    event_tz: Optional[str] = None,
    phone_e164: Optional[str] = None,
) -> str:
    """Return the IANA timezone string to use when calling this recipient."""
    if config.VOICE_USE_RECIPIENT_TIMEZONE and recipient_tz:
        return recipient_tz
    if config.VOICE_USE_EVENT_TIMEZONE and event_tz:
        return event_tz
    if phone_e164:
        country = country_from_e164(phone_e164)
        if country and country in _COUNTRY_TZ:
            return _COUNTRY_TZ[country]
    return config.VOICE_DEFAULT_TIMEZONE


def now_in(tz_name: str) -> datetime:
    if ZoneInfo is None:  # pragma: no cover - py<3.9
        return datetime.utcnow()
    try:
        return datetime.now(ZoneInfo(tz_name))
    except Exception:
        return datetime.now(ZoneInfo(config.VOICE_DEFAULT_TIMEZONE))


def within_calling_hours(tz_name: str, *, now: Optional[datetime] = None) -> bool:
    """True when the resolved local time is within ``[start, end)`` hours."""
    local = now or now_in(tz_name)
    return config.VOICE_ALLOWED_START_HOUR <= local.hour < config.VOICE_ALLOWED_END_HOUR
