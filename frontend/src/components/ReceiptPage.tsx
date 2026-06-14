/**
 * ReceiptPage — premium printable receipt for a single transaction.
 *
 *  Route: /wallet/receipt/:transaction_code
 *
 *  Uses the SAME pattern as Contribution Report & Expense Report:
 *  generate branded HTML via `generateReceiptHtml` and preview/print/PDF
 *  through `ReportPreviewDialog`. This keeps the experience identical on
 *  web and mobile.
 */
import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { motion } from "framer-motion";
import {
  ChevronLeft, Printer, RefreshCw, Share2, CheckCircle2, XCircle,
  Clock, ShieldCheck, Loader2, Wallet, Smartphone, Building2,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { QRCodeSVG } from "qrcode.react";
import { api } from "@/lib/api";
import { useCurrency } from "@/hooks/useCurrency";
import { useWorkspaceMeta } from "@/hooks/useWorkspaceMeta";
import nuruLogo from "@/assets/nuru-logo.png";
import ReportPreviewDialog from "@/components/ReportPreviewDialog";
import { generateReceiptHtml } from "@/utils/generatePdf";
import { humanize } from "@/lib/humanize";
import { formatLocalDateTime } from "@/utils/formatLocalDateTime";
import { getActiveHost } from "@/lib/region/host";
import type { Transaction, TransactionStatus } from "@/lib/api/payments-types";

const ReceiptPage = () => {
  const { transaction_code } = useParams<{ transaction_code: string }>();
  const navigate = useNavigate();
  const { format } = useCurrency();
  const [previewOpen, setPreviewOpen] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  useWorkspaceMeta({
    title: transaction_code ? `Receipt ${transaction_code}` : "Receipt",
    description: "Nuru transaction receipt · secure, verifiable, printable.",
  });

  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ["receipt", transaction_code],
    enabled: !!transaction_code,
    queryFn: async () => {
      const res = await api.payments.getStatus(transaction_code!);
      if (!res.success || !res.data) throw new Error(res.message || "Receipt not found");
      return res.data;
    },
  });

  const handleRefresh = async () => {
    if (refreshing) return;
    setRefreshing(true);
    try {
      const res = await refetch();
      const tx = res.data;
      if (tx) {
        if (["failed", "cancelled"].includes(tx.status)) {
          toast.error(`Payment ${tx.status}`, {
            description: humanize(tx.failure_reason) || "No reason was given. Please contact support.",
          });
        } else {
          toast.success(`Status: ${tx.status}`);
        }
      }
    } catch {
      toast.error("Could not refresh status");
    } finally {
      setRefreshing(false);
    }
  };

  const handleShare = async () => {
    // Share the public, non-authenticated receipt link so recipients can open
    // it without a Nuru account.
    const host = getActiveHost();
    const url = `https://${host}/shared/receipt/${transaction_code}`;
    if (navigator.share) {
      try {
        await navigator.share({ title: `Nuru receipt ${transaction_code}`, url });
        return;
      } catch { /* user cancelled */ }
    }
    try {
      await navigator.clipboard.writeText(url);
      toast.success("Public receipt link copied");
    } catch {
      toast.error("Could not copy the link");
    }
  };

  const openPreview = () => setPreviewOpen(true);

  const receiptHtml = data ? generateReceiptHtml(data) : "";

  if (isLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-8 w-40" />
        <Card><CardContent className="p-6 md:p-8 space-y-4">
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-32 w-full" />
          <Skeleton className="h-24 w-full" />
        </CardContent></Card>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="space-y-6">
        <div className="flex items-center gap-2">
          <h1 className="flex-1 min-w-0 text-xl md:text-2xl font-semibold">Receipt</h1>
          <Button
            variant="ghost"
            size="icon"
            className="flex-shrink-0"
            onClick={() => navigate(-1)}
            aria-label="Back"
          >
            <ChevronLeft className="w-5 h-5" />
          </Button>
        </div>
        <Card><CardContent className="py-16 text-center">
          <XCircle className="w-12 h-12 text-destructive mx-auto mb-3" />
          <h2 className="font-semibold text-foreground">Receipt not found</h2>
          <p className="text-sm text-muted-foreground mt-1">
            We could not load this transaction. It may have been removed.
          </p>
        </CardContent></Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header — matches Settings/Contribution-report pattern */}
      <div className="flex items-center gap-2">
        <h1 className="flex-1 min-w-0 text-xl md:text-2xl font-semibold truncate">
          Receipt - <span className="font-mono text-base">{data.transaction_code}</span>
        </h1>
        <Button
          variant="ghost"
          size="icon"
          className="flex-shrink-0"
          onClick={() => navigate(-1)}
          aria-label="Back"
        >
          <ChevronLeft className="w-5 h-5" />
        </Button>
      </div>

      {/* Action toolbar */}
      <div className="flex flex-wrap items-center gap-2">
        <Button variant="outline" size="sm" onClick={handleRefresh} disabled={refreshing} className="gap-2">
          {refreshing ? <Loader2 className="w-4 h-4 animate-spin" /> : <RefreshCw className="w-4 h-4" />}
          <span>Refresh status</span>
        </Button>
        <Button variant="outline" size="sm" onClick={handleShare} className="gap-2">
          <Share2 className="w-4 h-4" />
          <span className="hidden sm:inline">Share</span>
        </Button>
        <Button size="sm" onClick={openPreview} className="gap-2 ml-auto">
          <Printer className="w-4 h-4" />
          <span>Preview / Print</span>
        </Button>
      </div>

      {/* Failure banner — show a friendly version of the failure reason */}
      {["failed", "cancelled"].includes(data.status) && data.failure_reason && (
        <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 flex items-start gap-3">
          <XCircle className="w-5 h-5 text-destructive shrink-0 mt-0.5" />
          <div className="min-w-0 flex-1">
            <p className="text-sm font-semibold text-destructive">Why this payment {data.status}</p>
            <p className="text-sm text-destructive/90 mt-0.5 break-words">{humanize(data.failure_reason)}</p>
            <p className="text-[11px] text-muted-foreground mt-2">
              You will not be charged. Try again or contact support with the reference above.
            </p>
          </div>
        </div>
      )}

      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.25 }}
      >
        <div className="bg-card rounded-2xl border border-border shadow-sm overflow-hidden">
          <ReceiptHero tx={data} format={format} />
          <ReceiptBody tx={data} format={format} />
          <ReceiptFooter tx={data} />
        </div>
      </motion.div>

      <ReportPreviewDialog
        open={previewOpen}
        onOpenChange={setPreviewOpen}
        title={`Receipt - ${data.transaction_code}`}
        html={receiptHtml}
      />
    </div>
  );
};

// ─────────────────────────────────────────────────────────────────────────────

const StatusPill = ({ status }: { status: TransactionStatus }) => {
  const map: Record<TransactionStatus, { label: string; cls: string; icon: React.ReactNode }> = {
    succeeded: { label: "Paid", cls: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400", icon: <CheckCircle2 className="w-3.5 h-3.5" /> },
    paid: { label: "Paid", cls: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400", icon: <CheckCircle2 className="w-3.5 h-3.5" /> },
    credited: { label: "Credited", cls: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400", icon: <CheckCircle2 className="w-3.5 h-3.5" /> },
    pending: { label: "Pending", cls: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400", icon: <Clock className="w-3.5 h-3.5" /> },
    processing: { label: "Processing", cls: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400", icon: <Loader2 className="w-3.5 h-3.5 animate-spin" /> },
    failed: { label: "Failed", cls: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400", icon: <XCircle className="w-3.5 h-3.5" /> },
    cancelled: { label: "Cancelled", cls: "bg-muted text-muted-foreground", icon: <XCircle className="w-3.5 h-3.5" /> },
    refunded: { label: "Refunded", cls: "bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400", icon: <CheckCircle2 className="w-3.5 h-3.5" /> },
  };
  const v = map[status];
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold ${v?.cls || "bg-muted text-muted-foreground"}`}>
      {v?.icon} {v?.label || status}
    </span>
  );
};

const ReceiptHero = ({ tx, format }: { tx: Transaction; format: (n: number) => string }) => {
  const isSuccess = ["succeeded", "paid", "credited"].includes(tx.status);
  return (
    <div className="relative px-6 md:px-8 py-7 text-white overflow-hidden" style={{ background: 'linear-gradient(135deg, #FF8A5C 0%, #FF7145 55%, #E85A30 100%)' }}>
      <div className="absolute -top-8 -right-8 w-40 h-40 rounded-full bg-white/15 blur-2xl" />
      <div className="absolute -bottom-12 -left-6 w-44 h-44 rounded-full bg-white/10 blur-2xl" />

      <div className="relative flex items-start justify-between">
        <div className="flex items-center gap-2">
          <img src={nuruLogo} alt="Nuru" className="h-8 w-auto" />
          <span className="text-xs font-bold tracking-[0.18em] uppercase text-white/85">Receipt</span>
        </div>
        <StatusPill status={tx.status} />
      </div>

      <div className="relative mt-6">
        <p className="text-xs uppercase tracking-wider text-white/75">
          {isSuccess ? "Amount paid" : "Amount"}
        </p>
        <div className="mt-1 flex items-baseline gap-2">
          <h1 className="text-3xl md:text-4xl font-bold tracking-tight">{format(tx.gross_amount)}</h1>
        </div>
        <p className="mt-1 text-sm text-white/85 line-clamp-2">
          {tx.payment_description || tx.description || tx.target_type.replace(/_/g, " ")}
        </p>
      </div>

      <div className="relative mt-5 inline-flex items-center gap-1.5 text-[11px] text-white/85 bg-white/15 rounded-full px-2.5 py-1">
        <ShieldCheck className="w-3 h-3" /> Verified by Nuru
      </div>
    </div>
  );
};

const ReceiptBody = ({ tx, format }: { tx: Transaction; format: (n: number) => string }) => {
  const fee = typeof tx.commission_amount === "number"
    ? tx.commission_amount
    : Math.max(0, tx.gross_amount - (tx.net_amount || tx.gross_amount));
  const subtotal = typeof tx.net_amount === "number" ? tx.net_amount : tx.gross_amount - fee;
  const host = getActiveHost();
  const verifyUrl = `https://${host}/shared/receipt/${tx.transaction_code}`;
  return (
    <div className="px-6 md:px-8 py-6 space-y-5">
      <div className="flex items-start gap-5">
        <div className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm flex-1 min-w-0">
          <DetailRow label="Reference" value={tx.transaction_code} mono />
          <DetailRow label="Date" value={formatLocalDateTime(tx.initiated_at)} />
          {tx.completed_at && (
            <DetailRow label="Completed" value={formatLocalDateTime(tx.completed_at)} />
          )}
          <DetailRow label="Type" value={tx.target_type.replace(/_/g, " ")} capitalize />
          {(tx.provider_name || tx.method_type) && (
            <DetailRow
              label="Method"
              value={
                <span className="inline-flex items-center gap-1.5">
                  <ProviderIcon type={tx.method_type || ""} />
                  {tx.provider_name || tx.method_type}
                </span>
              }
            />
          )}
        </div>
        <div className="shrink-0 text-center">
          <div className="p-2 bg-white rounded-lg border border-border">
            <QRCodeSVG
              value={verifyUrl}
              size={92}
              level="H"
              marginSize={0}
              imageSettings={{ src: nuruLogo, height: 14, width: 36, excavate: false }}
            />
          </div>
          <p className="mt-1.5 text-[9px] uppercase tracking-wider text-muted-foreground font-medium">
            Scan to verify
          </p>
        </div>
      </div>

      <div className="border border-border rounded-xl divide-y divide-border">
        <SummaryRow label="Amount" value={format(subtotal)} />
        <SummaryRow label="Service fee" value={fee > 0 ? format(fee) : "Free"} muted />
        <SummaryRow label="Total" value={format(tx.gross_amount)} bold />
      </div>

      {tx.failure_reason && (
        <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-3 text-xs text-destructive">
          <p className="font-semibold mb-0.5">Reason</p>
          <p className="text-destructive/90">{tx.failure_reason}</p>
        </div>
      )}
    </div>
  );
};

const ReceiptFooter = ({ tx }: { tx: Transaction }) => {
  const host = getActiveHost();
  return (
    <div className="px-6 md:px-8 py-5 border-t border-border bg-muted/30 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 text-[11px] text-muted-foreground">
      <p className="truncate">
        Verify at {host}/shared/receipt/{tx.transaction_code}
      </p>
      <Badge variant="outline" className="text-[10px] w-fit">
        © {new Date().getFullYear()} Nuru
      </Badge>
    </div>
  );
};

const DetailRow = ({
  label, value, mono, capitalize,
}: { label: string; value: React.ReactNode; mono?: boolean; capitalize?: boolean }) => (
  <div className="min-w-0">
    <p className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</p>
    <p className={`text-sm text-foreground truncate ${mono ? "font-mono" : "font-medium"} ${capitalize ? "capitalize" : ""}`}>
      {value}
    </p>
  </div>
);

const SummaryRow = ({
  label, value, bold, muted,
}: { label: string; value: string; bold?: boolean; muted?: boolean }) => (
  <div className="flex items-center justify-between px-4 py-2.5">
    <span className={`text-sm ${muted ? "text-muted-foreground" : "text-foreground"}`}>{label}</span>
    <span className={`text-sm tabular-nums ${bold ? "font-bold text-foreground" : muted ? "text-muted-foreground" : "font-medium text-foreground"}`}>
      {value}
    </span>
  </div>
);

const ProviderIcon = ({ type }: { type: string }) => {
  if (type === "wallet") return <Wallet className="w-3.5 h-3.5" />;
  if (type === "mobile_money") return <Smartphone className="w-3.5 h-3.5" />;
  if (type === "bank") return <Building2 className="w-3.5 h-3.5" />;
  return null;
};

export default ReceiptPage;
