/**
 * Mobile money phone-number validation for the supported markets (TZ, KE).
 *
 * Accepted formats:
 *   - International:  +255712345678  /  +254712345678
 *   - Local with 0:   0712345678
 *   - Bare 9-digit:   712345678
 *
 * Returns a normalized E.164 string when valid, plus a friendly message when
 * invalid. The messages are user-facing — no jargon.
 */
export interface PhoneCheck {
  ok: boolean;
  message: string;
  /** E.164 normalized phone (only when ok=true). */
  e164?: string;
}

const RULES: Record<string, { cc: string; localPrefixes: string[]; example: string }> = {
  TZ: { cc: "255", localPrefixes: ["6", "7"], example: "0712 345 678" },
  KE: { cc: "254", localPrefixes: ["1", "7"], example: "0712 345 678" },
};

/**
 * Pre-clean a phone value before validation.
 *
 * Strips spaces, brackets, dots, hyphens. Preserves a leading '+' only;
 * any '+' that appears inside the number is removed.
 */
export function normalizePhoneNumber(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  const keepsLeadingPlus = raw.startsWith("+");
  const cleaned = raw
    .replace(/\s+/g, "")
    .replace(/[().\-]/g, "")
    .replace(/\+/g, "");
  return keepsLeadingPlus ? `+${cleaned}` : cleaned;
}

export function validateMobileMoneyPhone(raw: string, country?: string | null): PhoneCheck {
  const phone = normalizePhoneNumber(raw);
  if (!phone) return { ok: false, message: "Mobile number is required" };

  const cc = (country || "").toUpperCase();
  const rule = RULES[cc];
  if (!rule) {
    // Unknown country — just require an E.164-ish shape.
    return /^\+?\d{9,15}$/.test(phone)
      ? { ok: true, message: "", e164: phone.startsWith("+") ? phone : `+${phone}` }
      : { ok: false, message: "Enter a valid mobile number." };
  }

  // Strip a leading + or 00 if present.
  let digits = phone.replace(/^\+/, "").replace(/^00/, "");

  if (digits.startsWith(rule.cc)) {
    // Already includes country code.
    digits = digits.slice(rule.cc.length);
  } else if (digits.startsWith("0")) {
    digits = digits.slice(1);
  }

  if (!/^\d{9}$/.test(digits)) {
    return {
      ok: false,
      message: `Enter a valid ${cc} mobile number (e.g. ${rule.example}).`,
    };
  }

  if (!rule.localPrefixes.some((p) => digits.startsWith(p))) {
    return {
      ok: false,
      message: `That doesn't look like a ${cc} mobile number. Try one starting with ${rule.localPrefixes.map((p) => `0${p}`).join(" or ")}.`,
    };
  }

  return { ok: true, message: "", e164: `+${rule.cc}${digits}` };
}

/**
 * Permissive international phone validator for any contact (contributors,
 * guests, members, etc.) — NOT mobile-money specific. Accepts any country's
 * number as long as the country code is present (via leading "+" or by
 * providing a bare international form). For convenience, local-format numbers
 * (leading "0") are still accepted when the active region maps to a known
 * country and the local prefix matches.
 *
 * Returns an E.164 string (with leading "+") when valid.
 */
export function validateInternationalPhone(raw: string, country?: string | null): PhoneCheck {
  const cleaned = normalizePhoneNumber(raw);
  if (!cleaned) return { ok: false, message: "Phone number is required" };

  // Reject obvious garbage early.
  if (!/^\+?\d+$/.test(cleaned)) {
    return { ok: false, message: "Phone number can only contain digits and an optional leading +." };
  }

  // Local-format shortcut for known markets (e.g. 0712345678 in TZ/KE).
  const cc = (country || "").toUpperCase();
  const rule = RULES[cc];
  if (rule && cleaned.startsWith("0") && cleaned.length === 10) {
    const local = cleaned.slice(1);
    if (rule.localPrefixes.some((p) => local.startsWith(p))) {
      return { ok: true, message: "", e164: `+${rule.cc}${local}` };
    }
  }

  // Normalise leading +/00 to plain digits, then require a country code.
  let digits = cleaned.replace(/^\+/, "").replace(/^00/, "");

  // Bare local format without country code (e.g. "0712345678") for unknown
  // regions is rejected — they must include the country code.
  if (cleaned.startsWith("0")) {
    return {
      ok: false,
      message: "Include the country code (e.g. +255, +254, +1, +44).",
    };
  }

  if (digits.length < 8 || digits.length > 15) {
    return { ok: false, message: "Enter a valid phone number with country code (e.g. +255 712 345 678)." };
  }

  return { ok: true, message: "", e164: `+${digits}` };
}
