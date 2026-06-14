import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Loader2, MapPin } from "lucide-react";
import { toast } from "sonner";
import { useCurrentUser } from "@/hooks/useCurrentUser";
import { useMigrationStatus } from "@/hooks/useMigrationStatus";
import { useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { showApiErrors } from "@/lib/api/showApiErrors";
import {
  REGIONS,
  RegionCode,
  regionFromHost,
  regionFromTimezone,
} from "@/lib/region/config";
import { regionFromPhone } from "@/lib/region/phonePrefix";

/**
 * Country Confirmation Modal — Phase 3 + Migration upgrade.
 *
 * Shown ONCE per logged-in user whose profile has no `country_code` yet.
 * Detection priority for legacy users:
 *   1. Backend migration country_guess (already includes phone+ip+history)
 *   2. Phone prefix on the user record (+254 → KE, +255 → TZ)
 *   3. Browser timezone / host
 *   4. TZ default
 */

type DetectSource = "phone" | "ip" | "locale" | "manual";

const detectInitial = (
  phone?: string | null
): { code: RegionCode; source: DetectSource } => {
  // Phone prefix (most reliable for our two markets).
  const fromPhone = regionFromPhone(phone);
  if (fromPhone) return { code: fromPhone, source: "phone" };

  if (typeof window !== "undefined") {
    const fromHost = regionFromHost(window.location.hostname);
    if (fromHost) return { code: fromHost.code, source: "locale" };
    try {
      const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
      const fromTz = regionFromTimezone(tz);
      if (fromTz) return { code: fromTz.code, source: "locale" };
    } catch {
      /* ignore */
    }
  }
  return { code: "TZ", source: "manual" };
};

const CountryConfirmModal = () => {
  const { data: user, userIsLoggedIn, isLoading } = useCurrentUser();
  const { status: migrationStatus } = useMigrationStatus();
  const queryClient = useQueryClient();

  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState<RegionCode>("TZ");
  const [source, setSource] = useState<DetectSource>("manual");
  const [submitting, setSubmitting] = useState(false);

  // Decide whether to open: only when logged in AND no country yet AND not loading.
  useEffect(() => {
    if (!userIsLoggedIn || isLoading || !user) return;
    if (user.country_code) return;
    // Prefer backend's richer guess (it has phone+ip+history).
    const backendGuess = migrationStatus?.country_guess;
    if (backendGuess?.code) {
      setSelected(backendGuess.code);
      setSource((backendGuess.source as DetectSource) ?? "manual");
    } else {
      const guess = detectInitial(user.phone);
      setSelected(guess.code);
      setSource(guess.source);
    }
    setOpen(true);
  }, [userIsLoggedIn, isLoading, user, migrationStatus]);

  const handleConfirm = async () => {
    if (selected === "INTL") return; // INTL is fallback-only, not user-selectable
    setSubmitting(true);
    try {
      const res = await api.profile.confirmCountry({
        country_code: selected as "TZ" | "KE",
        source,
      });
      if (!res.success) {
        showApiErrors(res, "Failed to save country");
        return;
      }
      toast.success(`You're all set for ${REGIONS[selected].name}`, {
        description: `Wallet currency: ${REGIONS[selected].code === "TZ" ? "TZS" : "KES"}`,
      });
      // Refresh user so useCurrency() flips immediately.
      await queryClient.invalidateQueries({ queryKey: ["currentUser"] });
      setOpen(false);
    } catch (err) {
      toast.error("Something went wrong. Please try again.");
    } finally {
      setSubmitting(false);
    }
  };

  if (!open) return null;

  return (
    <Dialog open={open} onOpenChange={(v) => !submitting && setOpen(v)}>
      <DialogContent className="sm:max-w-md p-0 overflow-hidden border-border">
        <AnimatePresence>
          <motion.div
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.25 }}
            className="bg-background"
          >
            {/* Hero strip */}
            <div className="bg-gradient-to-br from-primary/10 via-primary/5 to-background px-6 pt-6 pb-5">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-full bg-primary/15 flex items-center justify-center">
                  <MapPin className="h-5 w-5 text-primary" />
                </div>
                <div>
                  <h2 className="text-lg font-semibold text-foreground">
                    Confirm your country
                  </h2>
                  <p className="text-sm text-muted-foreground">
                    We'll set up your wallet in the right currency.
                  </p>
                </div>
              </div>
            </div>

            {/* Country options */}
            <div className="px-6 py-5 space-y-3">
              {(Object.values(REGIONS) as Array<typeof REGIONS[RegionCode]>).map(
                (region) => {
                  const isActive = selected === region.code;
                  const currency = region.code === "TZ" ? "TZS" : "KES";
                  return (
                    <button
                      key={region.code}
                      type="button"
                      onClick={() => { setSelected(region.code); setSource("manual"); }}
                      className={`w-full text-left rounded-xl border p-4 transition-all ${
                        isActive
                          ? "border-primary bg-primary/5 ring-2 ring-primary/30"
                          : "border-border hover:border-primary/40 hover:bg-muted/40"
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-3">
                          <span className="text-2xl leading-none">{region.flag}</span>
                          <div>
                            <p className="font-medium text-foreground">
                              {region.name}
                            </p>
                            <p className="text-xs text-muted-foreground">
                              Wallet currency - {currency}
                            </p>
                          </div>
                        </div>
                        <div
                          className={`h-4 w-4 rounded-full border-2 ${
                            isActive
                              ? "border-primary bg-primary"
                              : "border-muted-foreground/40"
                          }`}
                        />
                      </div>
                    </button>
                  );
                }
              )}
            </div>

            {/* Actions */}
            <div className="px-6 pb-6 pt-1 flex flex-col gap-2">
              <Button
                onClick={handleConfirm}
                disabled={submitting}
                className="w-full"
                size="lg"
              >
                {submitting ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Saving...
                  </>
                ) : (
                  `Continue with ${REGIONS[selected].name}`
                )}
              </Button>
              <p className="text-[11px] text-center text-muted-foreground">
                You can change this later in Settings → Payments.
              </p>
            </div>
          </motion.div>
        </AnimatePresence>
      </DialogContent>
    </Dialog>
  );
};

export default CountryConfirmModal;
