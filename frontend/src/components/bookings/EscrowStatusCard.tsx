/**
 * EscrowStatusCard — visible on the booking detail page.
 */

import { useState } from "react";
import { ShieldCheck, Lock, AlertTriangle, RefreshCw } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useBookingEscrow } from "@/data/useBookingEscrow";
import { useCurrency } from "@/hooks/useCurrency";
import { toast } from "sonner";

interface Props {
  bookingId: string;
  viewerRole: "organiser" | "vendor";
}

const STATUS_LABEL: Record<string, { label: string; className: string }> = {
  pending: { label: "Awaiting payment", className: "bg-muted text-foreground" },
  held: { label: "Funds secured", className: "bg-primary/10 text-primary" },
  partially_released: { label: "Partially released", className: "bg-amber-500/10 text-amber-700" },
  released: { label: "Released to vendor", className: "bg-emerald-500/10 text-emerald-700" },
  refunded: { label: "Refunded", className: "bg-rose-500/10 text-rose-700" },
  disputed: { label: "Disputed (frozen)", className: "bg-destructive/10 text-destructive" },
};

export function EscrowStatusCard({ bookingId, viewerRole }: Props) {
  const { format: formatPrice } = useCurrency();
  const { hold, loading, error, release, refund, refetch } = useBookingEscrow(bookingId);
  const [refundOpen, setRefundOpen] = useState(false);
  const [refundAmount, setRefundAmount] = useState("");
  const [refundReason, setRefundReason] = useState("");
  const [refundBusy, setRefundBusy] = useState(false);
  const [releaseOpen, setReleaseOpen] = useState(false);
  const [releaseBusy, setReleaseBusy] = useState(false);

  if (loading) {
    return (
      <Card>
        <CardContent className="p-6 text-sm text-muted-foreground">Loading escrow…</CardContent>
      </Card>
    );
  }
  if (error || !hold) {
    return (
      <Card>
        <CardContent className="p-6 text-sm text-destructive flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {error || "Escrow not available"}
        </CardContent>
      </Card>
    );
  }

  const statusInfo = STATUS_LABEL[hold.status] ?? { label: hold.status, className: "bg-muted" };

  const handleReleaseConfirm = async () => {
    setReleaseBusy(true);
    try {
      await release("organiser_confirmed_delivery");
      toast.success("Funds released to vendor");
      setReleaseOpen(false);
    } catch (e: any) {
      toast.error(e?.message || "Release failed");
    } finally {
      setReleaseBusy(false);
    }
  };

  const handleRefundConfirm = async () => {
    const amt = Number(refundAmount);
    if (!amt || amt <= 0) {
      toast.error("Enter a valid refund amount");
      return;
    }
    if (amt > hold.amount_currently_held) {
      toast.error(`Maximum refundable is ${formatPrice(hold.amount_currently_held)}`);
      return;
    }
    setRefundBusy(true);
    try {
      await refund(amt, refundReason || "vendor_initiated_refund");
      toast.success("Refund recorded");
      setRefundOpen(false);
      setRefundAmount("");
      setRefundReason("");
    } catch (e: any) {
      toast.error(e?.message || "Refund failed");
    } finally {
      setRefundBusy(false);
    }
  };

  return (
    <>
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-base">
            <ShieldCheck className="w-4 h-4 text-primary" />
            Escrow & Payment Status
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground flex items-center gap-1">
              <Lock className="w-3.5 h-3.5" /> Status
            </span>
            <Badge className={statusInfo.className}>{statusInfo.label}</Badge>
          </div>

          <div className="grid grid-cols-2 gap-3 text-sm">
            <div>
              <p className="text-muted-foreground">Total agreed</p>
              <p className="font-semibold">{formatPrice(hold.amount_total)}</p>
            </div>
            <div>
              <p className="text-muted-foreground">Currently held</p>
              <p className="font-semibold text-primary">{formatPrice(hold.amount_currently_held)}</p>
            </div>
            <div>
              <p className="text-muted-foreground">Released</p>
              <p className="font-medium">{formatPrice(hold.amount_released)}</p>
            </div>
            <div>
              <p className="text-muted-foreground">Refunded</p>
              <p className="font-medium">{formatPrice(hold.amount_refunded)}</p>
            </div>
          </div>

          {hold.auto_release_at && (
            <p className="text-xs text-muted-foreground">
              Auto-release scheduled: {new Date(hold.auto_release_at).toLocaleString()}
            </p>
          )}

          <Separator />

          <div className="flex flex-wrap gap-2">
            {viewerRole === "organiser" && hold.amount_currently_held > 0 && (
              <Button size="sm" onClick={() => setReleaseOpen(true)}>
                Release to vendor
              </Button>
            )}
            {viewerRole === "vendor" && hold.amount_currently_held > 0 && (
              <Button size="sm" variant="outline" onClick={() => setRefundOpen(true)}>
                Issue refund
              </Button>
            )}
            <Button size="sm" variant="ghost" onClick={refetch}>
              <RefreshCw className="w-3.5 h-3.5 mr-1" /> Refresh
            </Button>
          </div>

          {hold.transactions && hold.transactions.length > 0 && (
            <div className="pt-2">
              <p className="text-xs font-semibold text-muted-foreground mb-2 uppercase tracking-wide">
                Ledger
              </p>
              <ul className="space-y-1.5 text-xs">
                {hold.transactions.slice().reverse().map((tx) => (
                  <li key={tx.id} className="flex items-center justify-between gap-2">
                    <span className="text-muted-foreground">
                      {new Date(tx.created_at).toLocaleString()} - {tx.type.replace(/_/g, " ").toLowerCase()}
                    </span>
                    <span className="font-medium">{formatPrice(tx.amount)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Release confirmation dialog */}
      <Dialog open={releaseOpen} onOpenChange={setReleaseOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Release funds to vendor?</DialogTitle>
            <DialogDescription>
              You're about to release {formatPrice(hold.amount_currently_held)} from escrow to the vendor.
              This action confirms you've received the service as agreed and cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setReleaseOpen(false)} disabled={releaseBusy}>
              Cancel
            </Button>
            <Button onClick={handleReleaseConfirm} disabled={releaseBusy}>
              {releaseBusy ? "Releasing…" : "Yes, release funds"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Refund dialog */}
      <Dialog open={refundOpen} onOpenChange={setRefundOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Issue a refund</DialogTitle>
            <DialogDescription>
              Refund up to {formatPrice(hold.amount_currently_held)} from the held funds back to the organiser.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label htmlFor="refund-amount">Refund amount (TZS)</Label>
              <Input
                id="refund-amount"
                type="number"
                inputMode="decimal"
                value={refundAmount}
                onChange={(e) => setRefundAmount(e.target.value)}
                placeholder={`Max ${hold.amount_currently_held}`}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="refund-reason">Reason (optional)</Label>
              <Input
                id="refund-reason"
                value={refundReason}
                onChange={(e) => setRefundReason(e.target.value)}
                placeholder="e.g., partial cancellation, service shortfall"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRefundOpen(false)} disabled={refundBusy}>
              Cancel
            </Button>
            <Button onClick={handleRefundConfirm} disabled={refundBusy || !refundAmount}>
              {refundBusy ? "Processing…" : "Confirm refund"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

export default EscrowStatusCard;
