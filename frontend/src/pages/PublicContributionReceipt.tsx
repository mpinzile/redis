/**
 * PublicContributionReceipt — /c/:token/r/:txCode
 *
 * Lets a guest (non-Nuru) contributor revisit a payment confirmation later
 * via the same magic-link they used to pay. We re-validate the token via
 * publicContributionsApi.status() to:
 *   1) prove the URL actually belongs to a payment under this token, and
 *   2) refresh the live status (a previously-pending tx may now be paid).
 *
 * No login required. All currency comes from the server (event.currency).
 */
import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { motion } from "framer-motion";
import {
  Loader2, CheckCircle2, XCircle, Clock, ShieldCheck, ArrowLeft,
  RefreshCw, AlertCircle, Receipt as ReceiptIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
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

const StatusHero = ({ status }: { status: string | null | undefined }) => {
  if (isTerminalSuccess(status)) {
    return (
      <div className="h-14 w-14 rounded-2xl bg-primary text-primary-foreground flex items-center justify-center shadow-lg shadow-primary/25">
        <CheckCircle2 className="h-7 w-7" />
      </div>
    );
  }
  if (status === "failed" || status === "cancelled") {
    return (
      <div className="h-14 w-14 rounded-2xl bg-destructive/10 text-destructive flex items-center justify-center">
        <XCircle className="h-7 w-7" />
      </div>
    );
  }
  return (
    <div className="h-14 w-14 rounded-2xl bg-muted text-muted-foreground flex items-center justify-center">
      <Clock className="h-7 w-7" />
    </div>
  );
};

export default function PublicContributionReceipt() {
  const { token = "", txCode = "" } = useParams<{ token: string; txCode: string }>();

  const [state, setState] = useState<PublicContributionState | null>(null);
  const [tx, setTx] = useState<PublicTransactionStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const load = async (silent = false) => {
    if (!token || !txCode) return;
    if (!silent) setRefreshing(true);

    // 1) Load page state — also gives us the recent_transactions list so we
    //    can find the UUID for this transaction_code.
    const stateRes = await publicContributionsApi.getState(token);
    if (!stateRes.success || !stateRes.data) {
      setErrorMsg(stateRes.message || "This receipt is no longer available.");
      setLoading(false);
      setRefreshing(false);
      return;
    }
    setState(stateRes.data);

    const match = stateRes.data.recent_transactions.find(
      (t) => t.transaction_code === txCode,
    );
    if (!match) {
      setErrorMsg("We couldn't find this payment under your link.");
      setLoading(false);
      setRefreshing(false);
      return;
    }

    // 2) Live status (re-polls the gateway server-side).
    const stRes = await publicContributionsApi.status(token, match.id);
    if (stRes.success && stRes.data) {
      setTx(stRes.data);
      setErrorMsg(null);
    } else {
      // Fall back to the snapshot embedded in state.
      setTx({
        id: match.id,
        transaction_code: match.transaction_code,
        status: match.status,
        gross_amount: match.gross_amount,
        currency_code: match.currency_code,
        failure_reason: match.failure_reason,
        confirmed_at: null,
        completed_at: null,
      });
    }
    setLoading(false);
    setRefreshing(false);
  };

  useEffect(() => { load(); /* eslint-disable-next-line */ }, [token, txCode]);

  const handleRefresh = async () => {
    await load();
    if (tx && isTerminalSuccess(tx.status)) {
      toast.success("Status is up to date");
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center px-4">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (errorMsg || !state || !tx) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center px-4">
        <div className="max-w-sm text-center space-y-3">
          <div className="h-12 w-12 mx-auto rounded-full bg-destructive/10 flex items-center justify-center">
            <AlertCircle className="h-6 w-6 text-destructive" />
          </div>
          <h1 className="text-lg font-semibold text-foreground">Receipt unavailable</h1>
          <p className="text-sm text-muted-foreground">
            {errorMsg || "This receipt link can no longer be opened. Please contact the organiser."}
          </p>
          {token && (
            <Button asChild variant="outline" size="sm">
              <Link to={`/c/${token}`}><ArrowLeft className="h-4 w-4 mr-2" />Back to payment page</Link>
            </Button>
          )}
        </div>
      </div>
    );
  }

  const success = isTerminalSuccess(tx.status);
  const failed = tx.status === "failed" || tx.status === "cancelled";
  const cur = tx.currency_code || state.currency_code;
  const dateStr = tx.confirmed_at || tx.completed_at;

  return (
    <div className="min-h-screen bg-gradient-to-br from-primary/5 via-background to-background">
      <div className="max-w-md mx-auto px-4 py-6 space-y-5">
        {/* Brand */}
        <header className="flex items-center justify-between">
          <Link to={`/c/${token}`} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground">
            <ArrowLeft className="h-4 w-4" />
            Back
          </Link>
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold text-foreground">Nuru - {state.host}</span>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleRefresh}
            disabled={refreshing}
            className="h-8 px-2 text-muted-foreground"
            aria-label="Refresh"
          >
            <RefreshCw className={`h-4 w-4 ${refreshing ? "animate-spin" : ""}`} />
          </Button>
        </header>

        {/* Receipt card */}
        <motion.section
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          className="rounded-2xl border border-border bg-card overflow-hidden shadow-sm"
        >
          <div className="px-6 pt-6 pb-5 flex flex-col items-center text-center space-y-3">
            <StatusHero status={tx.status} />
            <div>
              <p className="text-[11px] uppercase tracking-wider font-semibold text-muted-foreground">
                {success ? "Payment confirmed" : failed ? "Payment unsuccessful" : "Payment in progress"}
              </p>
              <p className="text-3xl font-bold text-foreground tabular-nums mt-1">
                {formatMoney(cur, tx.gross_amount)}
              </p>
              <p className="text-sm text-muted-foreground mt-1">{friendlyStatus(tx.status)}</p>
            </div>
          </div>

          <div className="px-6 py-4 border-t border-border space-y-3 text-sm">
            <Row label="Reference">
              <Badge variant="secondary" className="text-[11px] font-mono">{tx.transaction_code}</Badge>
            </Row>
            <Row label="Paid by">
              <span className="text-foreground">{state.contributor.name}</span>
            </Row>
            <Row label="To">
              <span className="text-foreground text-right truncate max-w-[60%]">
                {state.event.name}
              </span>
            </Row>
            <Row label="Organiser">
              <span className="text-foreground">{state.event.organiser_name}</span>
            </Row>
            {dateStr && (
              <Row label="Date">
                <span className="text-foreground">{new Date(dateStr).toLocaleString()}</span>
              </Row>
            )}
          </div>

          {failed && tx.failure_reason && (
            <div className="px-6 pb-5">
              <div className="rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-xs text-destructive">
                {tx.failure_reason}
              </div>
            </div>
          )}

          {/* Actions */}
          <div className="px-6 pb-6 pt-1 space-y-2">
            {!success && !failed && (
              <Button onClick={handleRefresh} variant="outline" className="w-full" disabled={refreshing}>
                <RefreshCw className={`h-4 w-4 mr-2 ${refreshing ? "animate-spin" : ""}`} />
                Check again
              </Button>
            )}
            {(failed || (!success && !failed)) && (
              <Button asChild className="w-full">
                <Link to={`/c/${token}`}>
                  <ReceiptIcon className="h-4 w-4 mr-2" />
                  {failed ? "Try again" : "Back to payment page"}
                </Link>
              </Button>
            )}
            {success && (
              <Button asChild variant="outline" className="w-full">
                <Link to={`/c/${token}`}>
                  <ReceiptIcon className="h-4 w-4 mr-2" />
                  View pledge & history
                </Link>
              </Button>
            )}
          </div>
        </motion.section>

        <footer className="text-center pt-1 pb-6">
          <div className="flex items-center justify-center gap-1.5 text-[11px] text-muted-foreground">
            <ShieldCheck className="h-3.5 w-3.5" />
            <span>Secured by Nuru. Bookmark this page to revisit your receipt anytime.</span>
          </div>
        </footer>
      </div>
    </div>
  );
}

const Row = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <div className="flex items-center justify-between gap-3">
    <span className="text-xs uppercase tracking-wider text-muted-foreground">{label}</span>
    <div className="text-sm">{children}</div>
  </div>
);
