/**
 * MigrationWelcomeModal — Phase 1 of the legacy-user upgrade flow.
 *
 * A premium, dismissable welcome that appears once per session for users who
 * registered before the new Payment Profile / Wallet system. Highlights what
 * they unlock by completing setup and surfaces a personalised summary of the
 * monetized content already on their account.
 *
 * During the "nudge" phase the copy gets firmer. During "restrict" phase it
 * becomes non-dismissable (no Remind Me Later) and the secondary action
 * routes them straight to Settings → Payments.
 */
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import {
  ShieldCheck, Wallet as WalletIcon, ArrowRight,
} from "lucide-react";
import NewBadgeIcon from "@/assets/icons/new-badge.svg";
import { useMigrationStatus } from "@/hooks/useMigrationStatus";

const MigrationWelcomeModal = () => {
  const navigate = useNavigate();
  const { status, phase, shouldShowWelcome, dismissWelcome } = useMigrationStatus();
  const [forceClosed, setForceClosed] = useState(false);

  if (!shouldShowWelcome || !status || forceClosed) return null;

  const isRestrict = phase === "restrict";
  const summary = status.monetized_summary;
  const hasContent = status.has_monetized_content;
  const totalItems =
    summary.events + summary.services + summary.ticketed_events +
    summary.contributions + summary.bookings;

  const handleSetup = () => {
    dismissWelcome();
    setForceClosed(true);
    navigate("/settings/payments");
  };

  const handleLater = () => {
    if (isRestrict) return;
    dismissWelcome();
    setForceClosed(true);
  };

  return (
    <Dialog
      open
      onOpenChange={(v) => { if (!v && !isRestrict) { dismissWelcome(); setForceClosed(true); } }}
    >
      <DialogContent
        className="sm:max-w-lg p-0 overflow-hidden border-border"
        onInteractOutside={(e) => { if (isRestrict) e.preventDefault(); }}
        onEscapeKeyDown={(e) => { if (isRestrict) e.preventDefault(); }}
      >
        <AnimatePresence>
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.28 }}
            className="bg-background"
          >
            {/* Hero */}
            <div className="relative px-6 pt-7 pb-6 bg-gradient-to-br from-primary/15 via-primary/5 to-background">
              {/* "New" badge — placed on the left so the dialog's close (×) on the right doesn't overlap it. */}
              <div className="absolute top-4 left-4">
                <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-semibold uppercase tracking-wider bg-primary/15 text-primary">
                  <img src={NewBadgeIcon} alt="" className="h-3 w-3 [filter:brightness(0)_saturate(100%)] dark:invert" aria-hidden />
                  New
                </span>
              </div>
              <div className="h-12 w-12 rounded-2xl bg-primary text-primary-foreground flex items-center justify-center shadow-lg shadow-primary/25 mb-4 mt-6">
                <WalletIcon className="h-6 w-6" />
              </div>
              <h2 className="text-xl font-bold text-foreground tracking-tight">
                {isRestrict
                  ? "Action required: complete payment setup"
                  : "Secure Payments Upgrade"}
              </h2>
              <p className="text-sm text-muted-foreground mt-1.5 leading-relaxed">
                {isRestrict
                  ? "To keep accepting payments and access your wallet, please complete payment setup now."
                  : "To help you receive earnings faster, manage withdrawals, and access your Nuru wallet, please complete your payment setup."}
              </p>
            </div>

            {/* Personalised summary */}
            {hasContent && (
              <div className="px-6 py-4 border-b border-border bg-muted/30">
                <p className="text-[11px] uppercase tracking-wider font-semibold text-muted-foreground mb-2">
                  On your account
                </p>
                <div className="flex flex-wrap gap-1.5">
                  {summary.events > 0 && <Chip>{summary.events} event{summary.events > 1 ? "s" : ""}</Chip>}
                  {summary.ticketed_events > 0 && <Chip>{summary.ticketed_events} ticketed</Chip>}
                  {summary.services > 0 && <Chip>{summary.services} service{summary.services > 1 ? "s" : ""}</Chip>}
                  {summary.contributions > 0 && <Chip>{summary.contributions} contribution{summary.contributions > 1 ? "s" : ""} received</Chip>}
                  {summary.bookings > 0 && <Chip>{summary.bookings} booking{summary.bookings > 1 ? "s" : ""}</Chip>}
                </div>
                {status.has_pending_balance && status.pending_balance && (
                  <p className="text-xs text-foreground mt-3">
                    <span className="font-semibold">Pending balance:</span>{" "}
                    {status.pending_balance.currency} {status.pending_balance.amount.toLocaleString()} — payable once setup is complete.
                  </p>
                )}
              </div>
            )}

            {/* Benefits */}
            <div className="px-6 py-5 space-y-3">
              <Benefit icon={<WalletIcon className="h-4 w-4" />} text={`Activate your wallet - ${totalItems > 0 ? "all your earnings flow here" : "ready for your first sale"}`} />
              <Benefit icon={<ArrowRight className="h-4 w-4" />} text="Withdraw to mobile money or bank in minutes" />
              <Benefit icon={<ShieldCheck className="h-4 w-4" />} text="Bank-grade security & full transaction history" />
            </div>

            {/* Actions */}
            <div className="px-6 pb-6 pt-1 flex flex-col gap-2">
              <Button onClick={handleSetup} size="lg" className="w-full font-semibold">
                Setup now
                <ArrowRight className="h-4 w-4 ml-2" />
              </Button>
              {!isRestrict && (
                <Button onClick={handleLater} variant="ghost" size="sm" className="w-full text-muted-foreground">
                  Remind me later
                </Button>
              )}
              {isRestrict && (
                <p className="text-[11px] text-center text-muted-foreground pt-1">
                  This is required to continue using monetized features.
                </p>
              )}
            </div>
          </motion.div>
        </AnimatePresence>
      </DialogContent>
    </Dialog>
  );
};

const Chip = ({ children }: { children: React.ReactNode }) => (
  <span className="inline-flex items-center px-2 py-0.5 rounded-md text-[11px] font-medium bg-background border border-border text-foreground">
    {children}
  </span>
);

const Benefit = ({ icon, text }: { icon: React.ReactNode; text: string }) => (
  <div className="flex items-start gap-2.5">
    <div className="h-7 w-7 shrink-0 rounded-lg bg-primary/10 text-primary flex items-center justify-center">
      {icon}
    </div>
    <p className="text-sm text-foreground leading-relaxed pt-0.5">{text}</p>
  </div>
);

export default MigrationWelcomeModal;
