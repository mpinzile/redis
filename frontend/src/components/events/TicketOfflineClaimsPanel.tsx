import { useEffect, useState, useCallback } from "react";
import { Loader2, Check, X, Receipt, ImageIcon, Phone, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { toast } from "sonner";
import { ticketOfflineClaimsApi, type TicketOfflineClaim } from "@/lib/api/ticketOfflineClaims";
import { useCurrency } from "@/hooks/useCurrency";

interface Props {
  eventId: string;
}

type StatusFilter = "pending" | "confirmed" | "rejected";

const STATUS_BADGE: Record<StatusFilter, string> = {
  pending: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300",
  confirmed: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300",
  rejected: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300",
};

const TicketOfflineClaimsPanel = ({ eventId }: Props) => {
  const { format: formatPrice } = useCurrency();
  const [status, setStatus] = useState<StatusFilter>("pending");
  const [claims, setClaims] = useState<TicketOfflineClaim[]>([]);
  const [loading, setLoading] = useState(true);
  const [actingId, setActingId] = useState<string | null>(null);
  const [rejectTarget, setRejectTarget] = useState<TicketOfflineClaim | null>(null);
  const [rejectReason, setRejectReason] = useState("");
  const [previewImage, setPreviewImage] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await ticketOfflineClaimsApi.list(eventId, status);
      if (res.success && res.data) setClaims(res.data.claims || []);
    } catch {
      /* silent */
    } finally {
      setLoading(false);
    }
  }, [eventId, status]);

  useEffect(() => {
    load();
  }, [load]);

  const handleConfirm = async (claim: TicketOfflineClaim) => {
    setActingId(claim.id);
    try {
      const res = await ticketOfflineClaimsApi.confirm(claim.id);
      if (res.success) {
        toast.success("Claim confirmed · ticket issued.");
        load();
      } else {
        toast.error(res.message || "Could not confirm claim.");
      }
    } finally {
      setActingId(null);
    }
  };

  const handleReject = async () => {
    if (!rejectTarget) return;
    setActingId(rejectTarget.id);
    try {
      const res = await ticketOfflineClaimsApi.reject(rejectTarget.id, rejectReason.trim() || undefined);
      if (res.success) {
        toast.success("Claim rejected.");
        setRejectTarget(null);
        setRejectReason("");
        load();
      } else {
        toast.error(res.message || "Could not reject claim.");
      }
    } finally {
      setActingId(null);
    }
  };

  return (
    <Card className="mt-6">
      <CardContent className="p-5 sm:p-6">
        <div className="flex flex-wrap items-center justify-between gap-3 mb-5">
          <div className="flex items-center gap-2">
            <Receipt className="w-5 h-5 text-muted-foreground" />
            <h3 className="text-base sm:text-lg font-semibold">Offline ticket payment claims</h3>
          </div>
          <Tabs value={status} onValueChange={(v) => setStatus(v as StatusFilter)}>
            <TabsList>
              <TabsTrigger value="pending">Pending</TabsTrigger>
              <TabsTrigger value="confirmed">Confirmed</TabsTrigger>
              <TabsTrigger value="rejected">Rejected</TabsTrigger>
            </TabsList>
          </Tabs>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-12 text-muted-foreground">
            <Loader2 className="w-5 h-5 animate-spin mr-2" /> Loading…
          </div>
        ) : claims.length === 0 ? (
          <div className="text-center py-12 text-sm text-muted-foreground">
            No {status} claims.
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {claims.map((c) => (
              <li key={c.id} className="py-4 flex flex-col sm:flex-row sm:items-start gap-4">
                {/* Receipt thumbnail (only when uploaded) */}
                {c.receipt_image_url ? (
                  <button
                    onClick={() => setPreviewImage(c.receipt_image_url!)}
                    className="shrink-0 w-20 h-20 rounded-lg overflow-hidden border border-border bg-muted hover:opacity-90 transition-opacity"
                    aria-label="View receipt"
                  >
                    <img
                      src={c.receipt_image_url}
                      alt="Receipt"
                      className="w-full h-full object-cover"
                    />
                  </button>
                ) : (
                  <div className="shrink-0 w-20 h-20 rounded-lg border border-dashed border-border flex items-center justify-center text-muted-foreground">
                    <ImageIcon className="w-5 h-5" />
                  </div>
                )}

                <div className="flex-1 min-w-0">
                  <div className="flex flex-wrap items-center gap-2 mb-1">
                    <p className="font-medium truncate">{c.claimant_name}</p>
                    <Badge className={STATUS_BADGE[c.status]} variant="secondary">
                      {c.status}
                    </Badge>
                    <Badge variant="outline">×{c.quantity}</Badge>
                  </div>
                  <p className="text-sm text-muted-foreground">
                    {formatPrice(c.amount)} ·{" "}
                    {c.payment_channel === "bank" ? "Bank" : "Mobile money"}
                    {c.provider_name ? ` - ${c.provider_name}` : ""}
                  </p>
                  <p className="text-xs text-muted-foreground mt-1 break-all">
                    Ref: <span className="font-mono">{c.transaction_code}</span>
                    {c.payer_account ? ` - From ${c.payer_account}` : ""}
                  </p>
                  <div className="flex flex-wrap gap-x-4 gap-y-1 mt-1.5 text-xs text-muted-foreground">
                    {c.claimant_phone && (
                      <span className="inline-flex items-center gap-1">
                        <Phone className="w-3 h-3" />
                        {c.claimant_phone}
                      </span>
                    )}
                    {c.claimant_email && (
                      <span className="inline-flex items-center gap-1">
                        <Mail className="w-3 h-3" />
                        {c.claimant_email}
                      </span>
                    )}
                  </div>
                  {c.status === "rejected" && c.rejection_reason && (
                    <p className="text-xs text-destructive mt-1.5">
                      Reason: {c.rejection_reason}
                    </p>
                  )}
                </div>

                {c.status === "pending" && (
                  <div className="flex gap-2 sm:flex-col sm:items-stretch shrink-0">
                    <Button
                      size="sm"
                      onClick={() => handleConfirm(c)}
                      disabled={actingId === c.id}
                    >
                      {actingId === c.id ? (
                        <Loader2 className="w-4 h-4 animate-spin" />
                      ) : (
                        <Check className="w-4 h-4 mr-1" />
                      )}
                      Confirm
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setRejectTarget(c)}
                      disabled={actingId === c.id}
                    >
                      <X className="w-4 h-4 mr-1" />
                      Reject
                    </Button>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardContent>

      {/* Receipt preview lightbox */}
      <Dialog open={!!previewImage} onOpenChange={(o) => !o && setPreviewImage(null)}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>Receipt</DialogTitle>
          </DialogHeader>
          {previewImage && (
            <img
              src={previewImage}
              alt="Receipt full"
              className="w-full h-auto rounded-lg border border-border"
            />
          )}
        </DialogContent>
      </Dialog>

      {/* Reject dialog */}
      <Dialog open={!!rejectTarget} onOpenChange={(o) => !o && setRejectTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reject claim</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            Optionally tell the buyer why this claim was rejected. They will be notified.
          </p>
          <Textarea
            value={rejectReason}
            onChange={(e) => setRejectReason(e.target.value)}
            placeholder="Reason (optional)"
            rows={3}
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setRejectTarget(null)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={handleReject}
              disabled={actingId === rejectTarget?.id}
            >
              {actingId === rejectTarget?.id && (
                <Loader2 className="w-4 h-4 animate-spin mr-1" />
              )}
              Reject claim
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
};

export default TicketOfflineClaimsPanel;
