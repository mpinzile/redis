/**
 * humanize.ts — turn backend/technical phrases into clear, friendly text
 * for end users. We never want users to see words like "admin", "gateway",
 * "STK push", "escrow", "beneficiary", "settlement", etc.
 *
 * Used everywhere ledger entries, transaction descriptions, failure reasons
 * or status messages from the backend are rendered to end users.
 */

const REPLACEMENTS: Array<[RegExp, string]> = [
  // Withdrawals & approvals
  [/withdrawal hold for pending admin approval/gi, "Withdrawal on hold · being reviewed by Nuru"],
  [/pending admin approval/gi, "being reviewed by Nuru"],
  [/admin approval/gi, "Nuru review"],
  [/awaiting admin/gi, "awaiting Nuru review"],
  [/pending approval by admin/gi, "being reviewed by Nuru"],
  [/by an administrator/gi, "by Nuru"],
  [/by administrator/gi, "by Nuru"],
  [/administrator/gi, "Nuru team"],
  [/\badmin\b/gi, "Nuru"],

  // Payment internals
  [/stk push/gi, "mobile money prompt"],
  [/stk_push/gi, "mobile money prompt"],
  [/payment gateway/gi, "payment partner"],
  [/the gateway/gi, "the payment partner"],
  [/gateway error/gi, "payment partner error"],
  [/gateway/gi, "payment partner"],
  [/beneficiary/gi, "recipient"],
  [/payout profile/gi, "payout method"],
  [/escrow hold/gi, "secure hold"],
  [/escrowed/gi, "securely held"],
  [/in escrow/gi, "safely held"],
  [/escrow/gi, "secure hold"],
  [/settlement/gi, "payout"],
  [/commission snapshot/gi, "service fee"],
  [/idempotency/gi, "duplicate-safe"],

  // Status verbs that look technical
  [/credited to wallet/gi, "added to your wallet"],
  [/debited from wallet/gi, "deducted from your wallet"],

  // Snake/kebab-case fallbacks (e.g. raw enum values)
  [/wallet_topup/gi, "Wallet top-up"],
  [/service_booking/gi, "Service booking"],
  [/event_contribution/gi, "Event contribution"],
  [/event_ticket/gi, "Event ticket"],
];

/**
 * Make a backend string safe to show to a user.
 * Returns the input untouched if it's empty/null.
 */
export const humanize = (input: string | null | undefined): string => {
  if (!input) return "";
  let out = String(input);
  for (const [pattern, replacement] of REPLACEMENTS) {
    out = out.replace(pattern, replacement);
  }
  // Capitalise the first letter for nicer presentation.
  return out.charAt(0).toUpperCase() + out.slice(1);
};

/** Convenience: humanize OR show a fallback. */
export const humanizeOr = (input: string | null | undefined, fallback: string): string =>
  input ? humanize(input) : fallback;
