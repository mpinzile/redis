import { useState, useEffect, useRef } from "react";
import { Link } from "react-router-dom";
import { Loader2, Search, MapPin, ChevronLeft, ChevronRight, Minus, Plus, Clock } from "lucide-react";
import SvgIcon from '@/components/ui/svg-icon';
import TicketIcon from "@/assets/icons/ticket-icon.svg";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { ticketingApi, TicketClass } from "@/lib/api/ticketing";
import { useCurrency } from '@/hooks/useCurrency';
import { getEventCountdown } from "@/utils/getEventCountdown";
import { toast } from "sonner";
import { motion } from "framer-motion";
import CountdownClock from "@/components/CountdownClock";
import { useLanguage } from '@/lib/i18n/LanguageContext';
import CheckoutModal from "@/components/payments/CheckoutModal";
import ReservationSuccess from "@/components/tickets/ReservationSuccess";
import { getEventImage } from "@/lib/eventImage";

let _browseEventsCache: any[] = [];
let _browseEventsPagination: any = null;
let _browseEventsHasLoaded = false;

const BrowseTickets = () => {
  const { format: formatPrice } = useCurrency();
  const { t } = useLanguage();
  const [events, setEvents] = useState<any[]>(_browseEventsCache);
  const [loading, setLoading] = useState(!_browseEventsHasLoaded);
  const initialLoad = useRef(!_browseEventsHasLoaded);
  const [page, setPage] = useState(1);
  const [pagination, setPagination] = useState<any>(_browseEventsPagination);
  const [searchQuery, setSearchQuery] = useState("");

  const [selectedEvent, setSelectedEvent] = useState<any>(null);
  const [ticketClasses, setTicketClasses] = useState<TicketClass[]>([]);
  const [loadingClasses, setLoadingClasses] = useState(false);
  const [selectedClass, setSelectedClass] = useState<TicketClass | null>(null);
  const [quantity, setQuantity] = useState(1);
  const [purchasing, setPurchasing] = useState(false);
  const [reserving, setReserving] = useState(false);
  const [purchaseResult, setPurchaseResult] = useState<any>(null);
  const [reservation, setReservation] = useState<any>(null);
  const [checkoutOpen, setCheckoutOpen] = useState(false);
  const [pendingTicketId, setPendingTicketId] = useState<string | null>(null);
  const [debouncedSearch, setDebouncedSearch] = useState("");

  const loadEvents = async (p = 1, search = "") => {
    if (initialLoad.current) setLoading(true);
    try {
      const res = await ticketingApi.getTicketedEvents({ page: p, limit: 12, search: search || undefined });
      if (res.success && res.data) {
        const data = res.data as any;
        const evts = data.events || [];
        if (p === 1 && !search) {
          _browseEventsCache = evts;
          _browseEventsPagination = data.pagination || null;
          _browseEventsHasLoaded = true;
        }
        setEvents(evts);
        setPagination(data.pagination || null);
      }
    } catch {}
    finally { setLoading(false); initialLoad.current = false; }
  };

  const refreshSelectedEventClasses = async () => {
    if (!selectedEvent?.id) return;
    try {
      const res = await ticketingApi.getTicketClasses(selectedEvent.id);
      if (res.success && res.data) {
        setTicketClasses((res.data as any).ticket_classes || []);
      }
    } catch {}
  };

  useEffect(() => { loadEvents(page, debouncedSearch); }, [page, debouncedSearch]);

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(searchQuery);
      setPage(1);
    }, 400);
    return () => clearTimeout(timer);
  }, [searchQuery]);

  const openEventTickets = async (event: any) => {
    setSelectedEvent(event);
    setSelectedClass(null);
    setQuantity(1);
    setPurchaseResult(null);
    setPendingTicketId(null);
    setCheckoutOpen(false);
    setLoadingClasses(true);
    try {
      const res = await ticketingApi.getTicketClasses(event.id);
      if (res.success && res.data) {
        setTicketClasses((res.data as any).ticket_classes || []);
      }
    } catch {}
    finally { setLoadingClasses(false); }
  };

  const handlePurchase = async () => {
    if (!selectedClass) return;
    setPurchasing(true);
    try {
      const res = await ticketingApi.purchaseTicket({ ticket_class_id: selectedClass.id, quantity });
      if (res.success && res.data) {
        const data = res.data as any;
        setPurchaseResult({ ticket_code: data.ticket_code, total_amount: data.total_amount });
        setPendingTicketId(data.ticket_id || data.id || null);
        // Show reservation summary first — user must click "Pay now" to open checkout.
        setCheckoutOpen(false);
      } else {
        toast.error((res as any).message || "Could not reserve ticket");
      }
    } catch {
      toast.error("Failed to reserve ticket");
    } finally {
      setPurchasing(false);
    }
  };

  /**
   * Airline-style hold: creates a reservation row with a countdown deadline
   * (returned in `reserved_until`). The ticket isn't issued yet — the user can
   * pay later from the My Tickets → Reservations panel before it expires.
   */
  const handleReserve = async () => {
    if (!selectedClass) return;
    setReserving(true);
    try {
      const res = await ticketingApi.reserveTicket({ ticket_class_id: selectedClass.id, quantity });
      if (res.success && res.data) {
        const data = res.data as any;
        setReservation({
          ticket_code: data.ticket_code,
          total_amount: data.total_amount,
          reserved_until: data.reserved_until,
          ticket_class_name: selectedClass.name,
          quantity,
          event_name: selectedEvent?.name,
        });
        setPendingTicketId(data.ticket_id || data.id || null);
        setPurchaseResult(null);
        setCheckoutOpen(false);
      } else {
        toast.error((res as any).message || "Could not reserve ticket");
      }
    } catch {
      toast.error("Failed to reserve ticket");
    } finally {
      setReserving(false);
    }
  };

  const filteredEvents = events;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center flex-shrink-0">
            <img src={TicketIcon} alt={t("tickets")} className="w-5 h-5 dark:invert" />
          </div>
          <div className="min-w-0">
            <h1 className="text-lg sm:text-xl font-bold text-foreground truncate">{t("browse_tickets")}</h1>
            <p className="text-xs sm:text-sm text-muted-foreground truncate">Find events and purchase tickets</p>
          </div>
        </div>
        <Link to="/my-tickets" className="flex-shrink-0">
          <Button variant="outline" size="sm" className="gap-2">
            <img src={TicketIcon} alt="" className="w-3.5 h-3.5 dark:invert" />
            <span className="hidden sm:inline">My Tickets</span>
            <span className="sm:hidden">Mine</span>
          </Button>
        </Link>
      </div>

      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          placeholder={t('search_events_tickets')}
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="pl-10"
        />
      </div>

      {loading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {[...Array(6)].map((_, i) => (
            <Card key={i} className="overflow-hidden animate-pulse">
              <div className="h-40 bg-muted" />
              <CardContent className="p-4 space-y-2">
                <div className="h-4 bg-muted rounded w-3/4" />
                <div className="h-3 bg-muted rounded w-1/2" />
              </CardContent>
            </Card>
          ))}
        </div>
      ) : filteredEvents.length === 0 ? (
        <div className="text-center py-16 border-2 border-dashed border-border rounded-2xl">
          <img src={TicketIcon} alt="" className="w-12 h-12 mx-auto mb-4 dark:invert opacity-20" />
          <p className="text-muted-foreground font-medium">No ticketed events found</p>
          <p className="text-xs text-muted-foreground mt-1">Check back later for upcoming events</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredEvents.map((event, i) => {
            const d = event.start_date ? new Date(event.start_date) : null;
            const countdown = getEventCountdown(event.start_date);
            return (
              <motion.div
                key={event.id}
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * 0.05 }}
              >
                <Card
                  className="overflow-hidden cursor-pointer hover:shadow-lg hover:border-primary/30 transition-all group"
                  onClick={() => openEventTickets(event)}
                >
                  <div className="relative h-40 bg-muted overflow-hidden">
                    <img src={getEventImage(event)} alt={event.name} className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300" />
                    <div className="absolute bottom-3 left-3">
                      <Badge className="bg-primary text-primary-foreground shadow-lg text-xs font-bold px-2.5 py-1">
                        From {formatPrice(event.min_price)}
                      </Badge>
                    </div>
                    {event.total_available <= 0 && (
                      <div className="absolute top-3 right-3">
                        <Badge variant="destructive" className="text-xs font-bold">Sold Out</Badge>
                      </div>
                    )}
                    {event.is_owner && event.ticket_approval_status !== 'approved' && (
                      <div className="absolute top-3 left-3">
                        <Badge variant="secondary" className="text-[10px] font-semibold shadow">
                          Pending review
                        </Badge>
                      </div>
                    )}
                  </div>
                  <CardContent className="p-0">
                    <div className="flex">
                      {d && (
                        <div className={`flex flex-col items-center justify-center px-4 py-3 border-r border-border min-w-[60px] ${
                          countdown?.isPast ? 'bg-muted/50' : 'bg-primary/5'
                        }`}>
                          <span className={`text-xl font-bold leading-none ${countdown?.isPast ? 'text-muted-foreground' : 'text-primary'}`}>
                            {d.getDate()}
                          </span>
                          <span className={`text-[10px] font-bold uppercase tracking-wider mt-0.5 ${countdown?.isPast ? 'text-muted-foreground' : 'text-primary'}`}>
                            {d.toLocaleDateString('en-US', { month: 'short' })}
                          </span>
                          <span className="text-[9px] text-muted-foreground mt-0.5">
                            {d.getFullYear()}
                          </span>
                        </div>
                      )}
                      <div className="flex-1 min-w-0 p-3 space-y-1.5">
                        <h3 className="font-semibold text-foreground text-sm line-clamp-2 leading-tight">{event.name}</h3>
                        {event.location && (
                          <p className="text-[11px] text-muted-foreground flex items-center gap-1 truncate">
                            <MapPin className="w-3 h-3 flex-shrink-0" />
                            {event.location}
                          </p>
                        )}
                        <div className="flex items-center gap-1.5 flex-wrap pt-0.5">
                          {event.start_date && (
                            <CountdownClock targetDate={event.start_date} compact />
                          )}
                          <Badge variant="outline" className="text-[9px] px-1.5 py-0 h-4">
                            {event.ticket_class_count} class{event.ticket_class_count !== 1 ? 'es' : ''}
                          </Badge>
                          {event.total_available > 0 && (
                            <span className="text-[9px] text-muted-foreground">{event.total_available} left</span>
                          )}
                        </div>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              </motion.div>
            );
          })}
        </div>
      )}

      {pagination && pagination.total_pages > 1 && (
        <div className="flex items-center justify-center gap-3">
          <Button variant="outline" size="sm" disabled={!pagination.has_previous} onClick={() => setPage(p => p - 1)}>
            <ChevronLeft className="w-4 h-4" />
          </Button>
          <span className="text-sm text-muted-foreground">Page {pagination.page} of {pagination.total_pages}</span>
          <Button variant="outline" size="sm" disabled={!pagination.has_next} onClick={() => setPage(p => p + 1)}>
            <ChevronRight className="w-4 h-4" />
          </Button>
        </div>
      )}

      <Dialog open={!!selectedEvent} onOpenChange={(open) => {
        if (!open) {
          setSelectedEvent(null);
          setSelectedClass(null);
          setQuantity(1);
          setPurchaseResult(null);
          setReservation(null);
          setPendingTicketId(null);
          setCheckoutOpen(false);
        }
      }}>
        <DialogContent className="max-w-md p-0 overflow-hidden">
          {selectedEvent && (
            <>
              <div className="h-36 overflow-hidden">
                <img src={getEventImage(selectedEvent)} alt={selectedEvent.name} className="w-full h-full object-cover" />
              </div>
              <div className="p-5 space-y-4">
                <div>
                  <h2 className="font-bold text-foreground text-lg">{selectedEvent.name}</h2>
                  {selectedEvent.start_date && (
                    <p className="text-xs text-muted-foreground flex items-center gap-1.5 mt-1">
                      <img src={TicketIcon} alt="" className="w-3 h-3 dark:invert" />
                      {new Date(selectedEvent.start_date).toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}
                    </p>
                  )}
                  {selectedEvent.location && (
                    <p className="text-xs text-muted-foreground flex items-center gap-1.5 mt-0.5">
                      <MapPin className="w-3 h-3" />
                      {selectedEvent.location}
                    </p>
                  )}
                </div>

                {selectedClass && (purchaseResult || reservation) && (
                  <CheckoutModal
                    open={checkoutOpen}
                    onOpenChange={async (open) => {
                      setCheckoutOpen(open);
                      if (!open) await refreshSelectedEventClasses();
                    }}
                    targetType="event_ticket"
                    targetId={pendingTicketId || selectedClass.id}
                    offlineClaimTargetId={selectedClass.id}
                    offlineClaimQuantity={quantity}
                    amount={(purchaseResult?.total_amount ?? reservation?.total_amount) || 0}
                    allowBank={false}
                    title={`Buy ${quantity} ${selectedClass.name} ticket${quantity > 1 ? 's' : ''}`}
                    description={`Ticket for ${selectedEvent.name} - ${selectedClass.name} × ${quantity}`}
                    onSuccess={() => {
                      toast.success("Payment confirmed · your ticket is now issued.", {
                        description: "View it under My Tickets.",
                      });
                      setCheckoutOpen(false);
                      setSelectedEvent(null);
                      setSelectedClass(null);
                      setQuantity(1);
                      setPurchaseResult(null);
                      setReservation(null);
                      setPendingTicketId(null);
                    }}
                  />
                )}

                {reservation && !checkoutOpen ? (
                  <ReservationSuccess
                    data={reservation}
                    onPayNow={() => setCheckoutOpen(true)}
                    onClose={() => setSelectedEvent(null)}
                  />
                ) : purchaseResult && !checkoutOpen ? (
                  <div className="text-center space-y-3 py-4">
                    <div className="w-14 h-14 rounded-full bg-amber-500/10 flex items-center justify-center mx-auto">
                      <img src={TicketIcon} alt="" className="w-7 h-7 dark:invert" />
                    </div>
                    <div>
                      <p className="font-bold text-foreground">Complete payment to confirm</p>
                      <p className="text-xs text-muted-foreground">Reserved but not yet issued — pay to secure your ticket</p>
                    </div>
                    <div className="p-3 rounded-lg bg-muted/50 border border-border">
                      <p className="text-xs text-muted-foreground mb-1">Reservation reference</p>
                      <p className="text-lg font-mono font-bold text-foreground tracking-wider">{purchaseResult.ticket_code}</p>
                    </div>
                    <p className="text-sm text-muted-foreground">
                      Amount due: <span className="font-semibold text-foreground">{formatPrice(purchaseResult.total_amount)}</span>
                    </p>
                    <Button className="w-full" onClick={() => setCheckoutOpen(true)}>Pay now</Button>
                  </div>
                ) : loadingClasses ? (
                  <div className="flex items-center justify-center gap-2 py-8">
                    <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />
                    <span className="text-sm text-muted-foreground">Loading tickets...</span>
                  </div>
                ) : ticketClasses.length === 0 ? (
                  <p className="text-center text-sm text-muted-foreground py-4">No ticket classes available</p>
                ) : (
                  <>
                    <div className="space-y-2">
                      {ticketClasses.map((tc) => {
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
                            {selectedClass?.id === tc.id && <div className="absolute left-0 top-3 bottom-3 w-1 rounded-full bg-primary" />}
                            <div className="flex items-start justify-between gap-3">
                              <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2 mb-1">
                                  <h3 className="font-semibold text-foreground text-sm">{tc.name}</h3>
                                  {isSoldOut && <Badge variant="destructive" className="text-[10px]">Sold Out</Badge>}
                                </div>
                                {tc.description && <p className="text-xs text-muted-foreground mb-1">{tc.description}</p>}
                                <p className="text-[11px] text-muted-foreground">{tc.available} of {tc.quantity} available</p>
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
                      <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} className="pt-3 border-t border-border space-y-3">
                        <div className="flex items-center justify-between">
                          <span className="text-sm font-medium">Quantity</span>
                          <div className="flex items-center gap-3">
                            <Button variant="outline" size="icon" className="h-8 w-8" onClick={() => setQuantity(Math.max(1, quantity - 1))} disabled={quantity <= 1}>
                              <Minus className="w-3 h-3" />
                            </Button>
                            <span className="text-lg font-semibold w-8 text-center">{quantity}</span>
                            <Button variant="outline" size="icon" className="h-8 w-8" onClick={() => setQuantity(Math.min(selectedClass.available, quantity + 1))} disabled={quantity >= selectedClass.available}>
                              <Plus className="w-3 h-3" />
                            </Button>
                          </div>
                        </div>
                        <div className="flex items-center justify-between text-sm">
                          <span className="text-muted-foreground">{selectedClass.name} × {quantity}</span>
                          <span className="font-bold">{formatPrice(selectedClass.price * quantity)}</span>
                        </div>
                        <div className="space-y-2">
                          <Button className="w-full gap-2" size="lg" onClick={handlePurchase} disabled={purchasing || reserving}>
                            {purchasing ? <Loader2 className="w-4 h-4 animate-spin" /> : <img src={TicketIcon} alt="" className="w-4 h-4 invert" />}
                            Pay now
                          </Button>
                          <Button
                            variant="outline"
                            className="w-full gap-2"
                            size="lg"
                            onClick={handleReserve}
                            disabled={purchasing || reserving}
                          >
                            {reserving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Clock className="w-4 h-4" />}
                            Reserve - pay later
                          </Button>
                          <p className="text-[11px] text-center text-muted-foreground">
                            Reserve to hold {quantity > 1 ? 'these tickets' : 'this ticket'} now and pay before the hold expires.
                          </p>
                        </div>
                      </motion.div>
                    )}
                  </>
                )}
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default BrowseTickets;
