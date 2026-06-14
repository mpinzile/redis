/**
 * MyReservations — airline-style ticket holds shown on the My Tickets page.
 *
 * Each row shows a live countdown to `reserved_until`. When the countdown hits
 * zero the row is removed from the UI and the next sweep call deletes it on
 * the backend. The user can:
 *   - "Pay now"          → converts reservation → pending order → opens CheckoutModal
 *   - "I already paid"   → opens CheckoutModal in offline-claim mode
 *   - "Cancel"           → DELETEs the reservation
 */
import { useEffect, useState } from "react";
import { Loader2, MapPin, Clock, X } from "lucide-react";
import TicketIcon from "@/assets/icons/ticket-icon.svg";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ticketingApi, TicketReservation } from "@/lib/api/ticketing";
import { useCurrency } from "@/hooks/useCurrency";
import { toast } from "sonner";
import CheckoutModal from "@/components/payments/CheckoutModal";

function fmtRemaining(seconds: number): string {
  if (seconds <= 0) return "Expired";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s.toString().padStart(2, "0")}s`;
  return `${s}s`;
}

const MyReservations = () => {
  const { format: formatPrice } = useCurrency();
  const [items, setItems] = useState<TicketReservation[]>([]);
  const [loading, setLoading] = useState(true);
  const [now, setNow] = useState(() => Date.now());
  const [busyId, setBusyId] = useState<string | null>(null);
  const [checkout, setCheckout] = useState<null | {
    reservation: TicketReservation;
    pendingTicketId: string;
  }>(null);
  const [paidIds, setPaidIds] = useState<Set<string>>(new Set());

  const load = () => {
    setLoading(true);
    ticketingApi
      .getMyReservations()
      .then((res) => {
        if (res.success && res.data) {
          const list = ((res.data as any).reservations || []) as TicketReservation[];
          // Merge: keep any reservation we have locally that the server has
          // converted to a pending order (under organizer/gateway review) so
          // the user still sees it until it's actually paid or expired.
          setItems((prev) => {
            const serverIds = new Set(list.map((r) => r.id));
            const stillPending = prev.filter(
              (p) =>
                !serverIds.has(p.id) &&
                !paidIds.has(p.id) &&
                (!p.reserved_until || new Date(p.reserved_until).getTime() > Date.now()),
            );
            return [...list, ...stillPending];
          });
        }
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  // Auto-prune any rows whose deadline passed in the browser.
  useEffect(() => {
    setItems((prev) => prev.filter((r) => !r.reserved_until || new Date(r.reserved_until).getTime() > now));
  }, [now]);

  const handlePay = async (r: TicketReservation) => {
    setBusyId(r.id);
    try {
      const res = await ticketingApi.convertReservation(r.id);
      if (res.success && res.data) {
        setCheckout({ reservation: r, pendingTicketId: (res.data as any).ticket_id });
      } else {
        toast.error(res.message || "Could not start payment");
        load();
      }
    } catch {
      toast.error("Could not start payment");
    } finally {
      setBusyId(null);
    }
  };

  const handleCancel = async (r: TicketReservation) => {
    setBusyId(r.id);
    try {
      const res = await ticketingApi.cancelReservation(r.id);
      if (res.success) {
        toast.success("Reservation cancelled");
        setItems((prev) => prev.filter((x) => x.id !== r.id));
      } else {
        toast.error(res.message || "Could not cancel");
      }
    } finally {
      setBusyId(null);
    }
  };

  if (loading) return null;
  if (items.length === 0) return null;

  return (
    <div>
      <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
        Reservations awaiting payment
      </h3>
      <div className="space-y-3">
        {items.map((r) => {
          const deadline = r.reserved_until ? new Date(r.reserved_until).getTime() : null;
          const remaining = deadline ? Math.max(0, Math.floor((deadline - now) / 1000)) : 0;
          const isUrgent = remaining < 30 * 60;
          return (
            <Card key={r.id} className={isUrgent ? "border-amber-300 dark:border-amber-700" : undefined}>
              <CardContent className="p-3 sm:p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-start gap-3 min-w-0 flex-1">
                    <div className="w-9 h-9 rounded-lg bg-amber-500/10 flex items-center justify-center flex-shrink-0">
                      <img src={TicketIcon} alt="" className="w-4 h-4 dark:invert" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-semibold text-foreground truncate">
                        {r.event?.name || "Event"}
                      </p>
                      <div className="flex flex-wrap items-center gap-x-3 gap-y-0.5 mt-0.5">
                        {r.ticket_class && (
                          <span className="text-[11px] text-muted-foreground">
                            {r.ticket_class} × {r.quantity}
                          </span>
                        )}
                        <span className="text-[11px] font-semibold text-foreground">
                          {formatPrice(r.total_amount)}
                        </span>
                        {r.event?.location && (
                          <span className="text-[11px] text-muted-foreground flex items-center gap-1 truncate">
                            <MapPin className="w-3 h-3" />
                            {r.event.location}
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-1.5 mt-1.5">
                        <Badge
                          variant="outline"
                          className={`text-[10px] ${
                            isUrgent
                              ? "border-amber-400 text-amber-700 dark:text-amber-300"
                              : "text-muted-foreground"
                          }`}
                        >
                          <Clock className="w-3 h-3 mr-1" />
                          Pay within {fmtRemaining(remaining)}
                        </Badge>
                        <Badge variant="outline" className="text-[10px] font-mono tracking-wide">
                          {r.ticket_code}
                        </Badge>
                      </div>
                    </div>
                  </div>
                  {/* No manual dismiss — reservations stay visible until paid or expired. */}
                </div>
                <div className="flex gap-2 mt-3">
                  <Button
                    size="sm"
                    className="flex-1"
                    onClick={() => handlePay(r)}
                    disabled={busyId === r.id || remaining <= 0}
                  >
                    {busyId === r.id ? <Loader2 className="w-3.5 h-3.5 animate-spin mr-1.5" /> : null}
                    Pay now
                  </Button>
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>

      {checkout && (
        <CheckoutModal
          open={!!checkout}
          onOpenChange={(v) => {
            if (!v) {
              // Closing without success → keep the reservation visible.
              // It is now a pending order under review (organizer or gateway);
              // it should remain until actually paid or expired.
              setCheckout(null);
            }
          }}
          targetType="event_ticket"
          targetId={checkout.pendingTicketId}
          offlineClaimTargetId={checkout.reservation.ticket_class_id}
          offlineClaimQuantity={checkout.reservation.quantity}
          amount={checkout.reservation.total_amount}
          allowBank={false}
          title={`Pay for ${checkout.reservation.ticket_class || "ticket"} × ${checkout.reservation.quantity}`}
          description={`Reservation ${checkout.reservation.ticket_code}`}
          onSuccess={() => {
            toast.success("Payment confirmed · your ticket is now issued.");
            const paidId = checkout.reservation.id;
            setPaidIds((prev) => new Set(prev).add(paidId));
            setItems((prev) => prev.filter((x) => x.id !== paidId));
            setCheckout(null);
          }}
        />
      )}
    </div>
  );
};

export default MyReservations;
