import { useState, useEffect, useCallback } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Loader2, Banknote, Smartphone, Building2, MoreHorizontal, RefreshCw, X, ShieldCheck, Clock } from "lucide-react";
import { offlinePaymentsApi, type OfflineVendorPayment } from "@/lib/api/offlinePayments";
import { toast } from "sonner";
import { useCurrency } from "@/hooks/useCurrency";

const METHODS = [
  { value: "cash", label: "Cash", icon: Banknote },
  { value: "mobile_money", label: "Mobile Money", icon: Smartphone },
  { value: "bank", label: "Bank Transfer", icon: Building2 },
  { value: "other", label: "Other", icon: MoreHorizontal },
];

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  eventId: string;
  eventServiceId: string;
  vendorName: string;
  serviceTitle: string;
  agreedPrice?: number | null;
  onLogged?: (p: OfflineVendorPayment) => void;
}

export function LogOfflinePaymentDialog({
  open, onOpenChange, eventId, eventServiceId, vendorName, serviceTitle, agreedPrice, onLogged,
}: Props) {
  const { format } = useCurrency();
  const [amount, setAmount] = useState("");
  const [amountRaw, setAmountRaw] = useState(""); // unformatted for submit
  const [method, setMethod] = useState("cash");
  const [reference, setReference] = useState("");
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const [history, setHistory] = useState<OfflineVendorPayment[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);

  const loadHistory = useCallback(async () => {
    setHistoryLoading(true);
    try {
      const res = await offlinePaymentsApi.listForEvent(eventId);
      const items = (res.data?.items || []).filter((p) => p.event_service_id === eventServiceId);
      setHistory(items);
    } catch (_) {
      // soft fail
    } finally {
      setHistoryLoading(false);
    }
  }, [eventId, eventServiceId]);

  useEffect(() => { if (open) loadHistory(); }, [open, loadHistory]);

  const reset = () => {
    setAmount(""); setAmountRaw(""); setMethod("cash"); setReference(""); setNote("");
  };

  const confirmedTotal = history.filter((p) => p.status === "confirmed").reduce((s, p) => s + Number(p.amount || 0), 0);
  const remaining = agreedPrice ? Math.max(agreedPrice - confirmedTotal, 0) : null;

  const formatNumber = (val: string) => {
    const clean = val.replace(/[^0-9.]/g, "");
    const [intPart, decPart] = clean.split(".");
    const formattedInt = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return decPart !== undefined ? `${formattedInt}.${decPart}` : formattedInt;
  };

  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const raw = e.target.value.replace(/[^0-9.]/g, "");
    setAmountRaw(raw);
    setAmount(formatNumber(raw));
  };

  const handleSubmit = async () => {
    const amt = parseFloat(amountRaw);
    if (!amt || amt <= 0) { toast.error("Enter a valid amount"); return; }
    setSubmitting(true);
    try {
      const res = await offlinePaymentsApi.log(eventId, eventServiceId, {
        amount: amt, method, reference: reference.trim() || undefined, note: note.trim() || undefined,
      });
      if (res.success && res.data) {
        toast.success("OTP sent to vendor for confirmation");
        onLogged?.(res.data);
        reset();
        loadHistory();
      } else {
        toast.error(res.message || "Failed to log payment");
      }
    } catch (e: unknown) {
      toast.error((e as Error)?.message || "Failed to log payment");
    } finally {
      setSubmitting(false);
    }
  };

  const cancelOne = async (id: string) => {
    const res = await offlinePaymentsApi.cancel(id);
    if (res.success) { toast.success("Cancelled"); loadHistory(); } else toast.error(res.message || "Failed");
  };
  const resendOne = async (id: string) => {
    const res = await offlinePaymentsApi.resend(id);
    if (res.success) { toast.success("OTP resent"); loadHistory(); } else toast.error(res.message || "Failed");
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Log offline payment</DialogTitle>
          <DialogDescription>
            Recording a payment you made to <span className="font-medium text-foreground">{vendorName}</span>{" "}
            for <span className="font-medium text-foreground">{serviceTitle}</span> outside the platform.
            They will get an SMS code to confirm receipt.
          </DialogDescription>
        </DialogHeader>

        {agreedPrice ? (
          <div className="rounded-xl border border-border bg-muted/40 p-3 text-xs flex items-center justify-between">
            <div>
              <div className="text-muted-foreground">Agreed</div>
              <div className="font-semibold text-foreground">{format(agreedPrice)}</div>
            </div>
            <div>
              <div className="text-muted-foreground">Confirmed paid</div>
              <div className="font-semibold text-emerald-600">{format(confirmedTotal)}</div>
            </div>
            {remaining !== null && (
              <div>
                <div className="text-muted-foreground">Remaining</div>
                <div className="font-semibold text-foreground">{format(remaining)}</div>
              </div>
            )}
          </div>
        ) : null}

        <div className="space-y-4">
          <div>
            <Label className="text-xs">Amount</Label>
            <Input
              type="text" inputMode="decimal" placeholder="0"
              value={amount} onChange={handleAmountChange} className="mt-1"
            />
          </div>

          <div>
            <Label className="text-xs">Method</Label>
            <div className="mt-1.5 grid grid-cols-4 gap-2">
              {METHODS.map((m) => {
                const Icon = m.icon;
                const active = method === m.value;
                return (
                  <button
                    key={m.value} type="button" onClick={() => setMethod(m.value)}
                    className={`flex flex-col items-center gap-1 rounded-xl border px-2 py-2.5 text-[11px] font-medium transition ${
                      active
                        ? "border-primary bg-primary/10 text-primary"
                        : "border-border bg-background hover:bg-muted text-foreground"
                    }`}
                  >
                    <Icon className="w-4 h-4" />
                    {m.label}
                  </button>
                );
              })}
            </div>
          </div>

          <div>
            <Label className="text-xs">Reference (optional)</Label>
            <Input
              placeholder="Txn ID, mobile money ref, etc."
              value={reference} onChange={(e) => setReference(e.target.value)} className="mt-1"
            />
          </div>

          <div>
            <Label className="text-xs">Note (optional)</Label>
            <Textarea
              rows={2} placeholder="Anything the vendor should know"
              value={note} onChange={(e) => setNote(e.target.value)} className="mt-1"
            />
          </div>

          <Button onClick={handleSubmit} disabled={submitting} className="w-full">
            {submitting && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
            Send OTP & log payment
          </Button>
        </div>

        <div className="pt-2 border-t border-border">
          <div className="text-xs font-semibold text-muted-foreground mb-2">Recent</div>
          {historyLoading ? (
            <div className="text-xs text-muted-foreground">Loading…</div>
          ) : history.length === 0 ? (
            <div className="text-xs text-muted-foreground">No payments logged yet.</div>
          ) : (
            <div className="space-y-2">
              {history.slice(0, 5).map((p) => (
                <div key={p.id} className="flex items-center justify-between gap-2 rounded-lg border border-border bg-card px-3 py-2">
                  <div className="min-w-0">
                    <div className="text-sm font-semibold text-foreground">{format(p.amount)}</div>
                    <div className="text-[11px] text-muted-foreground capitalize truncate">
                      {p.method || "offline"}{p.reference ? ` - ${p.reference}` : ""}
                    </div>
                  </div>
                  <StatusPill status={p.status} />
                  {p.status === "pending" && (
                    <div className="flex items-center gap-1">
                      <Button size="sm" variant="ghost" className="h-7 w-7 p-0" onClick={() => resendOne(p.id)} title="Resend OTP">
                        <RefreshCw className="w-3.5 h-3.5" />
                      </Button>
                      <Button size="sm" variant="ghost" className="h-7 w-7 p-0 text-destructive" onClick={() => cancelOne(p.id)} title="Cancel">
                        <X className="w-3.5 h-3.5" />
                      </Button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function StatusPill({ status }: { status: OfflineVendorPayment["status"] }) {
  const styles: Record<string, string> = {
    pending: "bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-400",
    confirmed: "bg-emerald-100 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-400",
    cancelled: "bg-muted text-muted-foreground",
    expired: "bg-muted text-muted-foreground",
    rejected: "bg-rose-100 text-rose-700 dark:bg-rose-500/15 dark:text-rose-400",
  };
  const Icon = status === "confirmed" ? ShieldCheck : Clock;
  return (
    <span className={`inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full capitalize ${styles[status] || "bg-muted text-muted-foreground"}`}>
      <Icon className="w-3 h-3" /> {status}
    </span>
  );
}
