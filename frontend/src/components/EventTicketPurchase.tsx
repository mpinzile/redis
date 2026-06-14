import { useState, useEffect } from "react";
import { Loader2, Minus, Plus, MapPin, Clock } from "lucide-react";
import TicketIcon from "@/assets/icons/ticket-icon.svg";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { ticketingApi, TicketClass } from "@/lib/api/ticketing";
import { useCurrency } from "@/hooks/useCurrency";
import { toast } from "sonner";
import { motion } from "framer-motion";
import { useLanguage } from "@/lib/i18n/LanguageContext";
import CheckoutModal from "@/components/payments/CheckoutModal";
import ReservationSuccess from "@/components/tickets/ReservationSuccess";
import { getEventImage } from "@/lib/eventImage";

interface EventTicketPurchaseProps {
  eventId: string;
  eventName?: string;
  /** Optional richer event info for the modal header (cover image, date, location). */
  event?: {
    title?: string;
    cover_image?: string | null;
    images?: { url: string }[];
    start_date?: string | null;
    location?: string | null;
    venue?: string | null;
  };
}

const EventTicketPurchase = ({ eventId, eventName, event }: EventTicketPurchaseProps) => {
  const { format: formatPrice } = useCurrency();
  const { t } = useLanguage();
  const [classes, setClasses] = useState<TicketClass[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [selectedClass, setSelectedClass] = useState<TicketClass | null>(null);
  const [quantity, setQuantity] = useState(1);
  const [purchasing, setPurchasing] = useState(false);
  const [reserving, setReserving] = useState(false);
  const [purchaseResult, setPurchaseResult] = useState<{ ticket_code: string; total_amount: number } | null>(null);
  const [reservation, setReservation] = useState<any>(null);
  const [checkoutOpen, setCheckoutOpen] = useState(false);
  const [pendingTicketId, setPendingTicketId] = useState<string | null>(null);

  const coverImage = getEventImage(event);
  const displayName = event?.title || eventName || "Event";

  const loadClasses = () => {
    setLoading(true);
    ticketingApi
      .getTicketClasses(eventId)
      .then((res) => {
        if (res.success && res.data) {
          setClasses((res.data as any).ticket_classes || []);
        }
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    loadClasses();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [eventId]);

  const resetSelection = () => {
    setSelectedClass(null);
    setQuantity(1);
    setPurchaseResult(null);
    setReservation(null);
    setPendingTicketId(null);
    setCheckoutOpen(false);
  };

  const minPrice = classes.length ? Math.min(...classes.map((c) => Number(c.price) || 0)) : 0;
  const totalAvailable = classes.reduce((sum, c) => sum + (c.available || 0), 0);

  const handlePurchase = async () => {
    if (!selectedClass) return;
    setPurchasing(true);
    try {
      const res = await ticketingApi.purchaseTicket({
        ticket_class_id: selectedClass.id,
        quantity,
      });
      if (res.success && res.data) {
        const data = res.data as any;
        setPurchaseResult({ ticket_code: data.ticket_code, total_amount: data.total_amount });
        setPendingTicketId(data.ticket_id || data.id || null);
        setCheckoutOpen(false);
      } else {
        toast.error(res.message || "Could not reserve ticket");
      }
    } catch {
      toast.error("Failed to reserve ticket");
    } finally {
      setPurchasing(false);
    }
  };

  /**
   * Airline-style hold — surfaces the ReservationSuccess card with countdown.
   */
  const handleReserve = async () => {
    if (!selectedClass) return;
    setReserving(true);
    try {
      const res = await ticketingApi.reserveTicket({
        ticket_class_id: selectedClass.id,
        quantity,
      });
      if (res.success && res.data) {
        const data = res.data as any;
        setReservation({
          ticket_code: data.ticket_code,
          total_amount: data.total_amount,
          reserved_until: data.reserved_until,
          ticket_class_name: selectedClass.name,
          quantity,
          event_name: displayName,
        });
        setPendingTicketId(data.ticket_id || data.id || null);
        setPurchaseResult(null);
        setCheckoutOpen(false);
      } else {
        toast.error(res.message || "Could not reserve ticket");
      }
    } catch {
      toast.error("Failed to reserve ticket");
    } finally {
      setReserving(false);
    }
  };

  if (!loading && classes.length === 0) return null;

  return (
    <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.25 }}>
      {/* Compact entry card — clicking opens the same modal as Browse Tickets */}
      <Card
        className="border-primary/20 cursor-pointer hover:shadow-md hover:border-primary/40 transition-all"
        onClick={() => !loading && setOpen(true)}
      >
        <CardContent className="p-4 sm:p-5">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center flex-shrink-0">
              <img src={TicketIcon} alt={t("tickets")} className="w-5 h-5 dark:invert" />
            </div>
            <div className="flex-1 min-w-0">
              <h2 className="font-semibold text-foreground truncate">Tickets available</h2>
              <p className="text-xs text-muted-foreground truncate flex items-center gap-1">
                <span>From</span>
                {loading ? (
                  <Skeleton className="h-3 w-20 inline-block align-middle" />
                ) : (
                  <span className="font-semibold text-primary">{formatPrice(minPrice)}</span>
                )}
                {!loading && (
                  <>
                    <span>{" - "}{classes.length} class{classes.length !== 1 ? "es" : ""}</span>
                    {totalAvailable > 0 && (
                      <span className="hidden sm:inline"> - {totalAvailable} left</span>
                    )}
                  </>
                )}
              </p>
            </div>
            <Button size="sm" className="gap-2 flex-shrink-0" disabled={loading}>
              <img src={TicketIcon} alt="" className="w-3.5 h-3.5 invert" />
              <span className="hidden sm:inline">Buy ticket</span>
              <span className="sm:hidden">Buy</span>
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Reservation modal — mirrors BrowseTickets exactly */}
      <Dialog
        open={open}
        onOpenChange={(v) => {
          setOpen(v);
          if (!v) resetSelection();
        }}
      >
        <DialogContent className="max-w-md p-0 overflow-hidden">
          {coverImage && (
            <div className="h-36 overflow-hidden">
              <img src={coverImage} alt={displayName} className="w-full h-full object-cover" />
            </div>
          )}
          <div className="p-5 space-y-4">
            <div>
              <h2 className="font-bold text-foreground text-lg">{displayName}</h2>
              {event?.start_date && (
                <p className="text-xs text-muted-foreground flex items-center gap-1.5 mt-1">
                  <img src={TicketIcon} alt="" className="w-3 h-3 dark:invert" />
                  {new Date(event.start_date).toLocaleDateString("en-US", {
                    weekday: "long",
                    month: "long",
                    day: "numeric",
                    year: "numeric",
                  })}
                </p>
              )}
              {(event?.venue || event?.location) && (
                <p className="text-xs text-muted-foreground flex items-center gap-1.5 mt-0.5">
                  <MapPin className="w-3 h-3" />
                  {event.venue || event.location}
                </p>
              )}
            </div>

            {/* CheckoutModal nested — opens after "Pay now" (instant or from reservation) */}
            {selectedClass && (purchaseResult || reservation) && (
              <CheckoutModal
                open={checkoutOpen}
                onOpenChange={(v) => {
                  setCheckoutOpen(v);
                  if (!v) loadClasses();
                }}
                targetType="event_ticket"
                targetId={pendingTicketId || selectedClass.id}
                offlineClaimTargetId={selectedClass.id}
                offlineClaimQuantity={quantity}
                amount={(purchaseResult?.total_amount ?? reservation?.total_amount) || 0}
                allowBank={false}
                title={`Buy ${quantity} ${selectedClass.name} ticket${quantity > 1 ? "s" : ""}`}
                description={`Ticket for ${displayName} - ${selectedClass.name} × ${quantity}`}
                onSuccess={() => {
                  toast.success("Payment confirmed · your ticket is now issued.", {
                    description: "View it under My Tickets.",
                  });
                  setCheckoutOpen(false);
                  setOpen(false);
                  resetSelection();
                }}
              />
            )}

            {reservation && !checkoutOpen ? (
              <ReservationSuccess
                data={reservation}
                onPayNow={() => setCheckoutOpen(true)}
                onClose={() => setOpen(false)}
              />
            ) : purchaseResult && !checkoutOpen ? (
              <div className="text-center space-y-3 py-4">
                <div className="w-14 h-14 rounded-full bg-amber-500/10 flex items-center justify-center mx-auto">
                  <img src={TicketIcon} alt="" className="w-7 h-7 dark:invert" />
                </div>
                <div>
                  <p className="font-bold text-foreground">Complete payment to confirm</p>
                  <p className="text-xs text-muted-foreground">
                    Reserved but not yet issued — pay to secure your ticket
                  </p>
                </div>
                <div className="p-3 rounded-lg bg-muted/50 border border-border">
                  <p className="text-xs text-muted-foreground mb-1">Reservation reference</p>
                  <p className="text-lg font-mono font-bold text-foreground tracking-wider">
                    {purchaseResult.ticket_code}
                  </p>
                </div>
                <p className="text-sm text-muted-foreground">
                  Amount due:{" "}
                  <span className="font-semibold text-foreground">
                    {formatPrice(purchaseResult.total_amount)}
                  </span>
                </p>
                <Button className="w-full" onClick={() => setCheckoutOpen(true)}>
                  Pay now
                </Button>
              </div>
            ) : (
              <>
                <div className="space-y-2">
                  {classes.map((tc) => {
                    const isSoldOut = tc.available <= 0;
                    return (
                      <div
                        key={tc.id}
                        onClick={() => !isSoldOut && setSelectedClass(tc)}
                        className={`relative p-4 rounded-xl border-2 transition-all cursor-pointer ${
                          isSoldOut
                            ? "border-border bg-muted/30 opacity-60 cursor-not-allowed"
                            : selectedClass?.id === tc.id
                              ? "border-primary bg-primary/5 ring-1 ring-primary/20 shadow-md"
                              : "border-border hover:border-primary/40"
                        }`}
                      >
                        {selectedClass?.id === tc.id && (
                          <div className="absolute left-0 top-3 bottom-3 w-1 rounded-full bg-primary" />
                        )}
                        <div className="flex items-start justify-between gap-3">
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 mb-1">
                              <h3 className="font-semibold text-foreground text-sm">{tc.name}</h3>
                              {isSoldOut && (
                                <Badge variant="destructive" className="text-[10px]">Sold Out</Badge>
                              )}
                            </div>
                            {tc.description && (
                              <p className="text-xs text-muted-foreground mb-1">{tc.description}</p>
                            )}
                            <p className="text-[11px] text-muted-foreground">
                              {tc.available} of {tc.quantity} available
                            </p>
                          </div>
                          <div className="text-right flex-shrink-0">
                            <p className="text-lg font-bold text-primary">{formatPrice(tc.price)}</p>
                            <p className="text-[10px] text-muted-foreground">per ticket</p>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>

                {selectedClass && (
                  <motion.div
                    initial={{ opacity: 0, height: 0 }}
                    animate={{ opacity: 1, height: "auto" }}
                    className="pt-3 border-t border-border space-y-3"
                  >
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-medium">Quantity</span>
                      <div className="flex items-center gap-3">
                        <Button
                          variant="outline"
                          size="icon"
                          className="h-8 w-8"
                          onClick={() => setQuantity(Math.max(1, quantity - 1))}
                          disabled={quantity <= 1}
                        >
                          <Minus className="w-3 h-3" />
                        </Button>
                        <span className="text-lg font-semibold w-8 text-center">{quantity}</span>
                        <Button
                          variant="outline"
                          size="icon"
                          className="h-8 w-8"
                          onClick={() =>
                            setQuantity(Math.min(selectedClass.available, quantity + 1))
                          }
                          disabled={quantity >= selectedClass.available}
                        >
                          <Plus className="w-3 h-3" />
                        </Button>
                      </div>
                    </div>
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-muted-foreground">
                        {selectedClass.name} × {quantity}
                      </span>
                      <span className="font-bold">{formatPrice(selectedClass.price * quantity)}</span>
                    </div>
                    <div className="space-y-2">
                      <Button
                        className="w-full gap-2"
                        size="lg"
                        onClick={handlePurchase}
                        disabled={purchasing || reserving}
                      >
                        {purchasing ? (
                          <Loader2 className="w-4 h-4 animate-spin" />
                        ) : (
                          <img src={TicketIcon} alt="" className="w-4 h-4 invert" />
                        )}
                        Pay now
                      </Button>
                      <Button
                        variant="outline"
                        className="w-full gap-2"
                        size="lg"
                        onClick={handleReserve}
                        disabled={purchasing || reserving}
                      >
                        {reserving ? (
                          <Loader2 className="w-4 h-4 animate-spin" />
                        ) : (
                          <Clock className="w-4 h-4" />
                        )}
                        Reserve - pay later
                      </Button>
                      <p className="text-[11px] text-center text-muted-foreground">
                        Reserve to hold {quantity > 1 ? "these tickets" : "this ticket"} now and pay before the hold expires.
                      </p>
                    </div>
                  </motion.div>
                )}
              </>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </motion.div>
  );
};

export default EventTicketPurchase;
