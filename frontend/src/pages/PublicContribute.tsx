/**
 * PublicContribute — /c/:token
 *
 * The unauthenticated landing page for non-Nuru contributors paying a
 * pledge from an SMS link. We deliberately do NOT reuse the authenticated
 * CheckoutModal here because:
 *   • Half its dependencies (currency context, payment-providers list,
 *     navigation to /wallet/receipt) require an active session.
 *   • The flow is simpler — mobile-money-only, currency dictated by the
 *     organiser, beneficiary already known on the server.
 *
 * The page polls server-side status; the contributor can also pull-to-
 * refresh (manual "Refresh" button). All currency is read from the
 * server response — never hardcoded.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { motion } from "framer-motion";
import {
  Smartphone, ShieldCheck, Loader2, RefreshCw, CheckCircle2,
  XCircle, Clock, ArrowRight, Wallet as WalletIcon, AlertCircle,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FormattedNumberInput } from "@/components/ui/formatted-number-input";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import nuruLogo from "@/assets/nuru-logo.png";
import {
  publicContributionsApi,
  isTerminalSuccess,
  type PublicContributionState,
  type PublicTransactionStatus,
} from "@/lib/api/publicContributions";

const formatMoney = (currency: string, n: number) =>
  `${currency} ${Number(n || 0).toLocaleString(undefined, { maximumFractionDigits: 0 })}`;

const friendlyStatus = (s: string | null | undefined) => {
  if (!s) return "Unknown";
  const map: Record<string, string> = {
    pending: "Waiting for confirmation",
    processing: "Awaiting your PIN",
    succeeded: "Successful",
    paid: "Successful",
    credited: "Successful",
    failed: "Failed",
    cancelled: "Cancelled",
    refunded: "Refunded",
  };
  return map[s] ?? s;
};

const StatusIcon = ({ status }: { status: string | null | undefined }) => {
  if (!status) return <Clock className="h-4 w-4 text-muted-foreground" />;
  if (isTerminalSuccess(status)) return <CheckCircle2 className="h-4 w-4 text-primary" />;
  if (status === "failed" || status === "cancelled") return <XCircle className="h-4 w-4 text-destructive" />;
  return <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />;
};

export default function PublicContribute() {
  const { token = "" } = useParams<{ token: string }>();

  const [state, setState] = useState<PublicContributionState | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Payment form state
  const [amountStr, setAmountStr] = useState<string>("");
  const [phone, setPhone] = useState<string>("");
  const [submitting, setSubmitting] = useState(false);
  const [activeTx, setActiveTx] = useState<PublicTransactionStatus | null>(null);
  const pollRef = useRef<number | null>(null);

  // ── Initial + manual refresh ──────────────────────────────────────────
  const loadState = async (silent = false) => {
    if (!token) return;
    if (!silent) setRefreshing(true);
    const res = await publicContributionsApi.getState(token);
    if (!silent) setRefreshing(false);
    if (!res.success || !res.data) {
      setErrorMsg(res.message || "This link is no longer valid.");
      setLoading(false);
      return;
    }
    setErrorMsg(null);
    setState(res.data);
    setLoading(false);
    // Default the amount to the outstanding balance the first time.
    setAmountStr((prev) =>
      prev ? prev : res.data!.balance > 0 ? String(res.data!.balance) : "",
    );
    setPhone((prev) => prev || res.data!.contributor.phone || "");
  };

  useEffect(() => { loadState(); /* eslint-disable-next-line */ }, [token]);

  // ── Auto-poll the active transaction every 3s until terminal ──────────
  useEffect(() => {
    if (!activeTx || !token) return;
    const terminal = ["succeeded", "paid", "credited", "failed", "cancelled", "refunded"];
    if (terminal.includes(activeTx.status ?? "")) return;

    pollRef.current = window.setInterval(async () => {
      const res = await publicContributionsApi.status(token, activeTx.id);
      if (res.success && res.data) {
        setActiveTx(res.data);
        if (isTerminalSuccess(res.data.status)) {
          toast.success("Payment confirmed", {
            description: `Reference ${res.data.transaction_code}`,
          });
          loadState(true); // refresh balance
        } else if (res.data.status === "failed" || res.data.status === "cancelled") {
          toast.error(res.data.failure_reason || `Payment ${res.data.status}`);
        }
      }
    }, 3000);
    return () => { if (pollRef.current) window.clearInterval(pollRef.current); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeTx?.id, activeTx?.status, token]);

  const amount = useMemo(() => Number(amountStr) || 0, [amountStr]);

  const handleSubmit = async () => {
    if (!state) return;
    if (amount <= 0) { toast.error("Enter an amount greater than zero."); return; }
    if (!phone.trim()) { toast.error("Enter your mobile money number."); return; }
    setSubmitting(true);
    const res = await publicContributionsApi.initiate(token, {
      amount,
      phone_number: phone.trim(),
    });
    setSubmitting(false);
    if (!res.success || !res.data) {
      toast.error(res.message || "Could not start the payment. Please try again.");
      return;
    }
    toast.message("Check your phone · enter your mobile money PIN to approve.");
    setActiveTx({
      id: res.data.transaction.id,
      transaction_code: res.data.transaction.transaction_code,
      status: res.data.transaction.status,
      gross_amount: res.data.transaction.gross_amount,
      currency_code: res.data.transaction.currency_code,
      failure_reason: res.data.transaction.failure_reason,
      confirmed_at: null,
      completed_at: null,
    });
  };

  const manualCheckActive = async () => {
    if (!activeTx) return;
    const res = await publicContributionsApi.status(token, activeTx.id);
    if (res.success && res.data) setActiveTx(res.data);
  };

  // ── Loading / error states ────────────────────────────────────────────
  if (loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center px-4">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (errorMsg || !state) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center px-4">
        <div className="max-w-sm text-center space-y-3">
          <div className="h-12 w-12 mx-auto rounded-full bg-destructive/10 flex items-center justify-center">
            <AlertCircle className="h-6 w-6 text-destructive" />
          </div>
          <h1 className="text-lg font-semibold text-foreground">Link unavailable</h1>
          <p className="text-sm text-muted-foreground">
            {errorMsg || "This payment link can no longer be used. Please contact the organiser to get a new one."}
          </p>
        </div>
      </div>
    );
  }

  const cur = state.currency_code;
  const pledged = state.pledge_amount;
  const paid = state.total_paid;
  const balance = state.balance;
  const progress = pledged > 0 ? Math.min(100, Math.round((paid / pledged) * 100)) : 0;
  const fullySettled = pledged > 0 && balance <= 0;

  return (
    <div className="min-h-screen bg-gradient-to-br from-primary/5 via-background to-background">
      <div className="max-w-md mx-auto px-4 py-6 space-y-5">
        {/* Brand */}
        <header className="flex items-center justify-between">
          <div className="flex items-center gap-2 min-w-0">
            <img src={nuruLogo} alt="Nuru" className="h-8 w-auto object-contain" />
            <span className="text-xs text-muted-foreground truncate">{state.host}</span>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => loadState()}
            disabled={refreshing}
            className="h-8 px-2 text-muted-foreground"
            aria-label="Refresh"
          >
            <RefreshCw className={`h-4 w-4 mr-1 ${refreshing ? "animate-spin" : ""}`} />
            Refresh
          </Button>
        </header>

        {/* Hero card */}
        <motion.section
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          className="rounded-2xl border border-border bg-card overflow-hidden shadow-sm"
        >
          {state.event.cover_image_url && (
            <img
              src={state.event.cover_image_url}
              alt={state.event.name}
              className="w-full h-32 object-cover"
            />
          )}
          <div className="p-5 space-y-4">
            <div>
              <p className="text-[11px] uppercase tracking-wider font-semibold text-muted-foreground">Contribution to</p>
              <h1 className="text-lg font-bold text-foreground leading-tight mt-0.5">{state.event.name}</h1>
              <p className="text-xs text-muted-foreground mt-1">
                Organised by {state.event.organiser_name}
              </p>
            </div>

            <div className="rounded-xl bg-muted/40 p-4 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs text-muted-foreground">Hi {state.contributor.name}, you pledged</span>
                <span className="text-sm font-semibold text-foreground tabular-nums">{formatMoney(cur, pledged)}</span>
              </div>
              <Progress value={progress} className="h-2" />
              <div className="flex items-center justify-between text-xs">
                <span className="text-muted-foreground">Paid <span className="font-medium text-foreground">{formatMoney(cur, paid)}</span></span>
                <span className={fullySettled ? "text-primary font-semibold" : "text-foreground font-semibold"}>
                  {fullySettled ? "Fully settled" : `Balance ${formatMoney(cur, balance)}`}
                </span>
              </div>
            </div>
          </div>
        </motion.section>

        {/* Active transaction tracker */}
        {activeTx && (
          <section className="rounded-2xl border border-border bg-card p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <StatusIcon status={activeTx.status} />
                <p className="text-sm font-semibold text-foreground">{friendlyStatus(activeTx.status)}</p>
              </div>
              <Badge variant="secondary" className="text-[10px]">{activeTx.transaction_code}</Badge>
            </div>
            <p className="text-xs text-muted-foreground">
              {isTerminalSuccess(activeTx.status)
                ? `Thank you! ${formatMoney(activeTx.currency_code, activeTx.gross_amount)} received.`
                : activeTx.status === "failed" || activeTx.status === "cancelled"
                  ? activeTx.failure_reason || "The payment did not go through. You can try again below."
                  : `We're waiting for confirmation from your mobile money provider. Approve the prompt on your phone, then tap Refresh.`}
            </p>
            {!isTerminalSuccess(activeTx.status) && activeTx.status !== "failed" && activeTx.status !== "cancelled" && (
              <Button
                variant="outline"
                size="sm"
                onClick={manualCheckActive}
                className="w-full"
              >
                <RefreshCw className="h-3.5 w-3.5 mr-2" />
                Check status now
              </Button>
            )}
          </section>
        )}

        {/* Pay form */}
        {!fullySettled && (!activeTx || activeTx.status === "failed" || activeTx.status === "cancelled") && (
          <motion.section
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            className="rounded-2xl border border-border bg-card p-5 space-y-4"
          >
            <div className="flex items-center gap-2">
              <div className="h-8 w-8 rounded-lg bg-primary/10 text-primary flex items-center justify-center">
                <Smartphone className="h-4 w-4" />
              </div>
              <div>
                <p className="text-sm font-semibold text-foreground">Pay with Mobile Money</p>
                <p className="text-[11px] text-muted-foreground">M-Pesa - Mixx by Yas - Airtel Money - HaloPesa</p>
              </div>
            </div>

            <div className="space-y-2">
              <Label className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Amount</Label>
              <FormattedNumberInput
                value={amountStr}
                onChange={setAmountStr}
                prefix={`${cur} `}
                placeholder={`${cur} 0`}
                className="text-xl font-bold"
              />
              {balance > 0 && (
                <p className="text-[11px] text-muted-foreground">
                  Suggested: {formatMoney(cur, balance)} (your remaining balance). You can pay more or less.
                </p>
              )}
            </div>

            <div className="space-y-2">
              <Label htmlFor="pc-phone" className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Mobile money number
              </Label>
              <Input
                id="pc-phone"
                type="tel"
                inputMode="tel"
                placeholder="07XXXXXXXX"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
              />
              <p className="text-[11px] text-muted-foreground">
                You'll receive a prompt on this number — enter your PIN to approve.
              </p>
            </div>

            <Button
              size="lg"
              className="w-full font-semibold"
              onClick={handleSubmit}
              disabled={submitting || amount <= 0 || !phone.trim()}
            >
              {submitting ? (
                <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Sending prompt…</>
              ) : (
                <>Pay {formatMoney(cur, amount || 0)} <ArrowRight className="h-4 w-4 ml-2" /></>
              )}
            </Button>

            <div className="flex items-center justify-center gap-1.5 text-[11px] text-muted-foreground pt-1">
              <ShieldCheck className="h-3.5 w-3.5" />
              <span>Secured by Nuru. Payment goes directly to the organiser.</span>
            </div>
          </motion.section>
        )}

        {/* Recent attempts */}
        {state.recent_transactions.length > 0 && (
          <section className="rounded-2xl border border-border bg-card p-4 space-y-3">
            <div className="flex items-center justify-between">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Your recent attempts</p>
              <WalletIcon className="h-3.5 w-3.5 text-muted-foreground" />
            </div>
            <ul className="space-y-2">
              {state.recent_transactions.map((tx) => (
                <li key={tx.id}>
                  <Link
                    to={`/c/${token}/r/${tx.transaction_code}`}
                    className="flex items-center justify-between text-sm rounded-lg -mx-2 px-2 py-1.5 hover:bg-muted/50 transition-colors"
                  >
                    <div className="flex items-center gap-2 min-w-0">
                      <StatusIcon status={tx.status} />
                      <div className="min-w-0">
                        <p className="font-medium text-foreground truncate">{formatMoney(tx.currency_code, tx.gross_amount)}</p>
                        <p className="text-[11px] text-muted-foreground truncate">{friendlyStatus(tx.status)} - {tx.transaction_code}</p>
                      </div>
                    </div>
                    {tx.created_at && (
                      <span className="text-[11px] text-muted-foreground whitespace-nowrap pl-2">
                        {new Date(tx.created_at).toLocaleDateString()}
                      </span>
                    )}
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        )}

        <footer className="text-center pt-2 pb-6">
          <p className="text-[11px] text-muted-foreground">
            Need help? Contact the organiser{state.contributor.phone ? "" : ""}.
          </p>
        </footer>
      </div>
    </div>
  );
}
