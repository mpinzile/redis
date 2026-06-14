import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Loader2, ShieldCheck, Clock, BadgeCheck } from "lucide-react";
import { toast } from "sonner";
import { offlinePaymentsApi, type OfflineVendorPayment } from "@/lib/api/offlinePayments";
import { useCurrency } from "@/hooks/useCurrency";

/**
 * Shows a vendor's offline payments — pending ones can be confirmed via OTP.
 * Confirmed ones are displayed as "Paid offline (not in wallet)".
 */
export function VendorOfflinePaymentsPanel({ eventId }: { eventId?: string | null }) {
  const { format } = useCurrency();
  const [items, setItems] = useState<OfflineVendorPayment[]>([]);
  const [loading, setLoading] = useState(true);
  const [confirmTarget, setConfirmTarget] = useState<OfflineVendorPayment | null>(null);
  const [otp, setOtp] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      const res = await offlinePaymentsApi.listMine();
      let list = res.data?.items || [];
      if (eventId) list = list.filter((p) => p.event_id === eventId);
      setItems(list);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); /* eslint-disable-next-line */ }, [eventId]);

  const handleConfirm = async () => {
    if (!confirmTarget) return;
    if (otp.trim().length < 4) { toast.error("Enter the OTP"); return; }
    setSubmitting(true);
    try {
      const res = await offlinePaymentsApi.confirm(confirmTarget.id, otp.trim());
      if (res.success) {
        toast.success("Payment confirmed");
        setConfirmTarget(null); setOtp("");
        load();
      } else {
        toast.error(res.message || "Could not confirm");
      }
    } finally { setSubmitting(false); }
  };

  if (loading) {
    return (
      <Card>
        <CardContent className="py-6 text-sm text-muted-foreground flex items-center gap-2">
          <Loader2 className="w-4 h-4 animate-spin" /> Loading offline payments…
        </CardContent>
      </Card>
    );
  }

  if (items.length === 0) return null;

  const pending = items.filter((p) => p.status === "pending");
  const confirmed = items.filter((p) => p.status === "confirmed");

  return (
    <>
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Offline payments</CardTitle>
          <p className="text-xs text-muted-foreground">
            Payments organisers logged outside the platform — confirm receipt with the SMS code.
            These do not appear in your wallet.
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          {pending.length > 0 && (
            <div className="space-y-2">
              <div className="text-xs font-semibold text-amber-700 dark:text-amber-400">
                Awaiting your confirmation ({pending.length})
              </div>
              {pending.map((p) => (
                <div key={p.id} className="rounded-xl border border-amber-200 dark:border-amber-500/30 bg-amber-50/50 dark:bg-amber-500/5 p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="text-sm font-semibold text-foreground">{format(p.amount)}</div>
                      <div className="text-xs text-muted-foreground truncate">
                        {p.service_title} - {p.recorded_by_name || "Organiser"}
                      </div>
                      {p.method && (
                        <div className="text-[11px] text-muted-foreground capitalize mt-0.5">
                          via {p.method.replace("_", " ")}{p.reference ? ` - ${p.reference}` : ""}
                        </div>
                      )}
                    </div>
                    <span className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-400">
                      <Clock className="w-3 h-3" /> Pending
                    </span>
                  </div>
                  <Button
                    size="sm" className="mt-2 w-full"
                    onClick={() => { setConfirmTarget(p); setOtp(""); }}
                  >
                    Enter OTP & confirm
                  </Button>
                </div>
              ))}
            </div>
          )}

          {confirmed.length > 0 && (
            <div className="space-y-2">
              <div className="text-xs font-semibold text-emerald-700 dark:text-emerald-400">
                Confirmed offline payments ({confirmed.length})
              </div>
              {confirmed.map((p) => (
                <div key={p.id} className="rounded-xl border border-border bg-card p-3 flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="text-sm font-semibold text-foreground">{format(p.amount)}</div>
                    <div className="text-xs text-muted-foreground truncate">
                      {p.service_title}{p.method ? ` - ${p.method.replace("_", " ")}` : ""}
                    </div>
                    <div className="text-[11px] text-muted-foreground">
                      Paid offline — not added to wallet
                    </div>
                  </div>
                  <span className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-400">
                    <ShieldCheck className="w-3 h-3" /> Confirmed
                  </span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={!!confirmTarget} onOpenChange={(v) => { if (!v) setConfirmTarget(null); }}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Confirm payment receipt</DialogTitle>
            <DialogDescription>
              {confirmTarget && (
                <>Enter the 6-digit code we sent by SMS to confirm you received{" "}
                <span className="font-semibold text-foreground">{format(confirmTarget.amount)}</span>{" "}
                for {confirmTarget.service_title}.</>
              )}
            </DialogDescription>
          </DialogHeader>
          <Input
            value={otp} onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))}
            placeholder="6-digit code" inputMode="numeric" autoFocus
            className="text-center text-lg tracking-widest"
          />
          <Button onClick={handleConfirm} disabled={submitting} className="w-full">
            {submitting && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
            <BadgeCheck className="w-4 h-4 mr-1" /> Confirm receipt
          </Button>
        </DialogContent>
      </Dialog>
    </>
  );
}
