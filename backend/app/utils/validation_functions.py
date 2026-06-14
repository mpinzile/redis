# utils/validation_functions.py
# Contains utility functions for validating user input data such as email, phone number, and password strength

import re

def validate_email(email: str) -> bool:
    pattern = r'^[\w\.-]+@[\w\.-]+\.\w+$'
    return re.match(pattern, email) is not None


def normalize_phone_number(value) -> str:
    """
    Pre-clean a phone value before validation.

    Strips spaces, brackets, dots and hyphens. Preserves a leading '+' only;
    any '+' that appears inside the number is removed. Always returns a
    string (never None) so it's safe to pass straight into validators or
    duplicate-detection helpers.
    """
    raw = str(value if value is not None else "").strip()
    if not raw:
        return ""
    keeps_leading_plus = raw.startswith("+")
    cleaned = re.sub(r"\s+", "", raw)
    cleaned = re.sub(r"[().\-]", "", cleaned)
    cleaned = cleaned.replace("+", "")
    return f"+{cleaned}" if keeps_leading_plus else cleaned


def validate_phone_number(phone: str) -> str:
    """
    Validates and normalises any phone number into international format (without +).

    Accepts:
        - Local Tanzanian: 0653750805, 653750805
        - International with prefix: +255653750805, 255653750805
        - Any international number: +1234567890, 447911123456
        - Formatted inputs like "+1 (444) 123 4567", "255-764-432-456",
          "+44.7700.900123" — formatting characters are stripped first.

    Returns normalised number (digits only, with country code).
    Raises ValueError if invalid.
    """
    phone = normalize_phone_number(phone)

    # Remove leading +
    if phone.startswith("+"):
        phone = phone[1:]

    # Handle Tanzanian local format (starts with 0 and 10 digits)
    if phone.startswith("0") and len(phone) == 10:
        digit_after_zero = phone[1]
        if digit_after_zero in ("6", "7"):
            phone = "255" + phone[1:]
        else:
            raise ValueError("Invalid Tanzanian phone number")

    # Handle short Tanzanian number (9 digits starting with 6 or 7)
    if len(phone) == 9 and phone[0] in ("6", "7"):
        phone = "255" + phone

    # Defensive: strip an erroneous leading 0 right after the TZ country code
    # (e.g. 25507XXXXXXXX → 2557XXXXXXXX). Happens when a local-format number
    # was concatenated with the dial code on the client.
    if phone.startswith("2550") and len(phone) == 13 and phone[4] in ("6", "7"):
        phone = "255" + phone[4:]

    # Same defensive cleanup for Kenyan numbers (2540 → 254).
    if phone.startswith("2540") and len(phone) == 13 and phone[4] in ("1", "7"):
        phone = "254" + phone[4:]

    # Must be all digits
    if not phone.isdigit():
        raise ValueError("Phone number must contain only digits")

    # Minimum 7 digits (some small countries), maximum 15 (E.164 standard)
    if len(phone) < 7 or len(phone) > 15:
        raise ValueError("Phone number must be between 7 and 15 digits")

    return phone


def is_tanzanian_number(phone: str) -> bool:
    """Check if a normalised phone number is Tanzanian."""
    cleaned = phone.replace("+", "").replace(" ", "").replace("-", "")
    return cleaned.startswith("255") and len(cleaned) == 12


# Keep backward compatibility
def validate_tanzanian_phone(phone: str) -> str:
    """
    Validates and formats a Tanzanian phone number into international format (without +).
    Accepts:
        - 0653750805
        - 653750805
        - 255653750805
        - +255653750805
    Returns formatted number like: 255653750805
    Raises ValueError if invalid.
    """
    phone = phone.strip().replace(" ", "").replace("-", "")

    # Remove leading +
    if phone.startswith("+"):
        phone = phone[1:]

    # Remove leading 0 if present in local format
    if phone.startswith("0") and len(phone) == 10:
        phone = phone[1:]

    # Add country code if missing
    if phone.startswith("6") or phone.startswith("7"):
        phone = "255" + phone

    # Must now match pattern: 255 + 9 digits starting with 6 or 7
    if re.fullmatch(r"255[67]\d{8}", phone):
        return phone

    raise ValueError(
        "Invalid Tanzanian phone number. Must start with 6 or 7 after country code "
        "and contain 9 digits after the country code"
    )


def validate_password_strength(password: str) -> bool:
    """
    Strong password rules:
    - At least 8 characters
    - At least one uppercase letter
    - At least one lowercase letter
    - At least one digit
    - At least one special character
    """
    if len(password) < 8:
        return False
    if not re.search(r'[A-Z]', password):
        return False
    if not re.search(r'[a-z]', password):
        return False
    if not re.search(r'\d', password):
        return False
    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        return False
    return True

def validate_username(username: str) -> bool:
    """
    Valid usernames can only contain letters, numbers, and underscores.
    Must be between 3 and 30 characters.
    """
    if not 3 <= len(username) <= 30:
        return False
    pattern = r'^[A-Za-z0-9_]+$'
    return re.fullmatch(pattern, username) is not None


def validate_name(name: str) -> dict:
    """Proxy to name_validation module for convenience."""
    from utils.name_validation import validate_name as _validate
    return _validate(name)
