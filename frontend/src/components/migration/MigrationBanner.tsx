/**
 * MigrationBanner — Phase 2 contextual nudge.
 *
 * Drop into the top of any monetized page (events dashboard, services
 * dashboard, wallet, ticket sales) to remind legacy users they need to
 * complete payment setup. The copy is contextual via the `surface` prop.
 *
 * Appearance hardens with phase:
 *   • soft     — soft primary tint, dismissable per session
 *   • nudge    — amber accent, dismissable per session
 *   • restrict — destructive accent, NOT dismissable
 */
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { AlertCircle, ArrowRight, X, Wallet as WalletIcon } from "lucide-react";
import { useMigrationStatus } from "@/hooks/useMigrationStatus";
import { cn } from "@/lib/utils";

export type MigrationSurface =
  | "events" | "services" | "wallet" | "tickets" | "bookings" | "generic";

const COPY: Record<MigrationSurface, { headline: string; sub: string }> = {
  events:   { headline: "Your events can receive payouts after payment setup.",
              sub: "Complete setup so contributions and ticket sales reach you instantly." },
  services: { headline: "Complete payment setup to continue receiving bookings and earnings.",
              sub: "New bookings will pause until your payout details are saved." },
  wallet:   { headline: "Activate your wallet by completing payment setup.",
              sub: "Your balance, withdrawals, and history live here once setup is done." },
  tickets:  { headline: "Payment setup required to continue ticket sales settlements.",
              sub: "We'll release ticket revenue to your wallet as soon as you're set up." },
  bookings: { headline: "Set up payments to confirm new paid bookings.",
              sub: "Customers can still browse · but checkouts pause until you're ready." },
  generic:  { headline: "Complete your payment setup to keep earning.",
              sub: "Takes about a minute. Mobile money or bank · your choice." },
};

interface Props {
  surface: MigrationSurface;
  className?: string;
}

const MigrationBanner = ({ surface, className }: Props) => {
  const navigate = useNavigate();
  const { needsSetup, phase } = useMigrationStatus();
  const [hidden, setHidden] = useState(false);

  if (!needsSetup || hidden) return null;

  const copy = COPY[surface];
  const isRestrict = phase === "restrict";
  const isNudge = phase === "nudge";

  const tone = isRestrict
    ? "from-destructive/15 via-destructive/5 to-background border-destructive/30 text-foreground"
    : isNudge
    ? "from-amber-500/15 via-amber-500/5 to-background border-amber-500/30 text-foreground"
    : "from-primary/10 via-primary/5 to-background border-primary/25 text-foreground";

  const iconTone = isRestrict ? "text-destructive" : isNudge ? "text-amber-600 dark:text-amber-400" : "text-primary";

  return (
    <div
      role="status"
      className={cn(
        "relative rounded-xl border bg-gradient-to-r p-4 sm:p-5 mb-4 shadow-sm",
        tone,
        className
      )}
    >
      <div className="flex items-start gap-3">
        <div className={cn("h-9 w-9 shrink-0 rounded-lg bg-background/80 backdrop-blur flex items-center justify-center", iconTone)}>
          {isRestrict ? <AlertCircle className="h-5 w-5" /> : <WalletIcon className="h-5 w-5" />}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold leading-snug">{copy.headline}</p>
          <p className="text-xs text-muted-foreground mt-1 leading-relaxed">{copy.sub}</p>
          <div className="mt-3 flex items-center gap-2">
            <button
              onClick={() => navigate("/settings/payments")}
              className={cn(
                "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors",
                isRestrict
                  ? "bg-destructive text-destructive-foreground hover:bg-destructive/90"
                  : "bg-primary text-primary-foreground hover:bg-primary/90"
              )}
            >
              Setup now <ArrowRight className="h-3.5 w-3.5" />
            </button>
            {!isRestrict && (
              <button
                onClick={() => setHidden(true)}
                className="text-xs text-muted-foreground hover:text-foreground px-2 py-1.5"
              >
                Not now
              </button>
            )}
          </div>
        </div>
        {!isRestrict && (
          <button
            onClick={() => setHidden(true)}
            aria-label="Dismiss"
            className="text-muted-foreground hover:text-foreground"
          >
            <X className="h-4 w-4" />
          </button>
        )}
      </div>
    </div>
  );
};

export default MigrationBanner;
