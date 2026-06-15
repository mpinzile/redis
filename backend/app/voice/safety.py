"""Pre-flight safety checks for outbound voice calls.

Every job MUST pass ``check_can_call`` before the Twilio (or any other)
provider client is invoked. The function returns a structured verdict so
upstream callers can log the reason and surface it on the campaign dashboard.

It intentionally does not touch the database — opt-out persistence and
per-user daily quotas live in their own modules (added in Phase 3) and are
passed in via the ``is_opted_out`` / ``user_calls_today`` callbacks.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Optional

from core import config
from utils.validation_functions import validate_phone_number
from .timezone import country_from_e164, resolve_timezone, within_calling_hours


# Common emergency / short numbers across Nuru's launch markets. Stored as
# bare digit strings; matching is done against the digits-only E.164 form
# AND against the local-format dial because emergency numbers are usually
# dialed without a country code.
EMERGENCY_NUMBERS: frozenset[str] = frozenset({
    # International
    "112", "911",
    # Tanzania
    "111", "112", "113", "114", "115",
    # Kenya
    "999",
    # UK
    "999",
    # Misc utility / short codes commonly abused
    "100", "101", "102", "108", "117", "118", "119",
})


@dataclass
class CallVerdict:
    allowed: bool
    reason: str = "ok"
    code: str = "ok"
    phone_e164: str = ""
    country: Optional[str] = None
    timezone: str = ""

    def as_dict(self) -> dict:
        return {
            "allowed": self.allowed,
            "reason": self.reason,
            "code": self.code,
            "phone_e164": self.phone_e164,
            "country": self.country,
            "timezone": self.timezone,
        }


def _is_emergency(phone_raw: str, phone_e164: str) -> bool:
    if not config.VOICE_BLOCK_EMERGENCY_NUMBERS:
        return False
    raw_digits = "".join(ch for ch in (phone_raw or "") if ch.isdigit())
    e164_digits = phone_e164.lstrip("+")
    # Match either the original dial or the last 3-4 digits of the E.164 form.
    if raw_digits in EMERGENCY_NUMBERS:
        return True
    return any(e164_digits.endswith(num) and len(e164_digits) <= len(num) + 3
               for num in EMERGENCY_NUMBERS)


def check_can_call(
    phone_raw: str,
    *,
    recipient_tz: Optional[str] = None,
    event_tz: Optional[str] = None,
    is_opted_out: Optional[Callable[[str], bool]] = None,
    user_calls_today: Optional[int] = None,
    enforce_hours: bool = True,
) -> CallVerdict:
    """Run all pre-flight safety checks.

    Returns ``CallVerdict(allowed=True)`` when every gate passes. Otherwise
    the verdict carries a stable ``code`` so the caller can branch
    (e.g. ``"emergency"``, ``"opted_out"``, ``"outside_hours"``).
    """
    # 1. Normalise phone — reuse Nuru's validator so behavior matches the
    #    rest of the platform (TZ leading-zero handling, +cc handling…).
    try:
        normalized = validate_phone_number(phone_raw)
    except ValueError as exc:
        return CallVerdict(False, str(exc), "invalid_phone", "")

    phone_e164 = f"+{normalized}"
    country = country_from_e164(phone_e164)

    # 2. Emergency-number guard.
    if _is_emergency(phone_raw, phone_e164):
        return CallVerdict(False, "Emergency numbers cannot be called",
                           "emergency", phone_e164, country, "")

    # 3. International calling rules.
    if country and country not in config.VOICE_ALLOWED_COUNTRIES:
        if not config.VOICE_ALLOW_INTERNATIONAL_CALLS or country not in config.VOICE_ALLOWED_COUNTRIES:
            return CallVerdict(
                False,
                f"Calls to {country} are not enabled on this account",
                "country_blocked", phone_e164, country, "",
            )

    # 4. Per-user daily quota.
    if (user_calls_today is not None
            and user_calls_today >= config.VOICE_MAX_CALLS_PER_USER_PER_DAY):
        return CallVerdict(False, "Daily call limit reached for this user",
                           "daily_limit", phone_e164, country, "")

    # 5. Opt-out list.
    if is_opted_out and is_opted_out(phone_e164):
        return CallVerdict(False, "Recipient has opted out of voice calls",
                           "opted_out", phone_e164, country, "")

    # 6. Calling-hour guard (resolved per recipient).
    tz_name = resolve_timezone(
        recipient_tz=recipient_tz, event_tz=event_tz, phone_e164=phone_e164,
    )
    if enforce_hours and not within_calling_hours(tz_name):
        return CallVerdict(
            False,
            f"Outside allowed calling hours "
            f"({config.VOICE_ALLOWED_START_HOUR:02d}:00-"
            f"{config.VOICE_ALLOWED_END_HOUR:02d}:00 {tz_name})",
            "outside_hours", phone_e164, country, tz_name,
        )

    return CallVerdict(True, "ok", "ok", phone_e164, country, tz_name)
