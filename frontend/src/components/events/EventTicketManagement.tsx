import { useState, useEffect, useRef, useCallback } from "react";
import { Loader2, Check, X, ChevronLeft, ChevronRight, CheckCircle2, ShieldCheck, AlertTriangle, Phone, Mail, Calendar, MapPin, Clock, Keyboard, Send } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import SvgIcon from '@/components/ui/svg-icon';
import CameraIcon from "@/assets/icons/camera-icon.svg";
import { Skeleton } from "@/components/ui/skeleton";
import TicketIcon from "@/assets/icons/ticket-icon.svg";
import ScanIcon from "@/assets/icons/scan-icon.svg";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Avatar, AvatarImage, AvatarFallback } from "@/components/ui/avatar";
import { ticketingApi } from "@/lib/api/ticketing";
import { get, put } from "@/lib/api/helpers";
import { useCurrency } from '@/hooks/useCurrency';
import { toast } from "sonner";
import { motion, AnimatePresence } from "framer-motion";
import { useLanguage } from '@/lib/i18n/LanguageContext';
import ReceivedPaymentsPanel from '@/components/payments/ReceivedPaymentsPanel';
import TicketOfflineClaimsPanel from '@/components/events/TicketOfflineClaimsPanel';

interface EventTicketManagementProps {
  eventId: string;
  isCreator: boolean;
}

const STATUS_STYLES: Record<string, string> = {
  confirmed: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300",
  approved: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300",
  pending: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300",
  rejected: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300",
  cancelled: "bg-muted text-muted-foreground",
};

const EventTicketManagement = ({ eventId, isCreator }: EventTicketManagementProps) => {
  const { format: formatPrice } = useCurrency();
  const { t } = useLanguage();
  const [tickets, setTickets] = useState<any[]>([]);
  const [ticketClasses, setTicketClasses] = useState<any[]>([]);
  const [approvalStatus, setApprovalStatus] = useState<string | null>(null);
  const [rejectionReason, setRejectionReason] = useState<string | null>(null);
  const [removedReason, setRemovedReason] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [classesLoading, setClassesLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [pagination, setPagination] = useState<any>(null);
  
  const [updatingId, setUpdatingId] = useState<string | null>(null);
  const [sendingId, setSendingId] = useState<string | null>(null);

  const handleSendTicket = async (ticket: any) => {
    if (!ticket?.buyer_phone) {
      toast.error('Buyer phone number is missing');
      return;
    }
    setSendingId(ticket.id);
    try {
      const { data: render, error: rErr } = await supabase.functions.invoke('render-card', {
        body: { kind: 'ticket', event_id: eventId, ticket_code: ticket.ticket_code },
      });
      if (rErr || !render?.url) throw new Error(rErr?.message || 'Failed to render ticket');

      const { error: sErr } = await supabase.functions.invoke('whatsapp-send', {
        body: {
          action: 'send_ticket',
          phone: ticket.buyer_phone,
          params: {
            image_url: render.url,
            guest_name: ticket.buyer_name || 'Friend',
            event_name: ticket.event_name || 'the event',
            event_date: ticket.event_date || 'TBD',
            ticket_class: ticket.ticket_class || 'General',
            ticket_code: ticket.ticket_code,
          },
        },
      });
      if (sErr) throw new Error(sErr.message);
      toast.success('Ticket sent via WhatsApp');
    } catch (e: any) {
      toast.error(e?.message || 'Failed to send ticket');
    } finally {
      setSendingId(null);
    }
  };

  const [scanOpen, setScanOpen] = useState(false);
  const [scanMode, setScanMode] = useState<'manual' | 'camera'>('manual');
  const [scanCode, setScanCode] = useState("");
  const [scanLoading, setScanLoading] = useState(false);
  const [scannedTicket, setScannedTicket] = useState<any>(null);
  const [scanError, setScanError] = useState<string | null>(null);
  const [checkingIn, setCheckingIn] = useState(false);
  const [checkInDone, setCheckInDone] = useState(false);
  const cameraRef = useRef<HTMLDivElement>(null);
  const scannerRef = useRef<any>(null);

  const loadTickets = async (p = 1) => {
    setLoading(true);
    try {
      const res = await ticketingApi.getEventTickets(eventId, { page: p, limit: 20 });
      if (res.success && res.data) {
        const data = res.data as any;
        setTickets(data.tickets || []);
        setPagination(data.pagination || null);
      }
    } catch { /* silent */ }
    finally { setLoading(false); }
  };

  const loadClasses = async () => {
    setClassesLoading(true);
    try {
      const res = await ticketingApi.getMyTicketClasses(eventId);
      if (res.success && res.data) {
        const d = res.data as any;
        setTicketClasses(d.ticket_classes || []);
        setApprovalStatus(d.ticket_approval_status || "pending");
        setRejectionReason(d.ticket_rejection_reason || null);
        setRemovedReason(d.ticket_removed_reason || null);
      }
    } catch { /* silent */ }
    finally { setClassesLoading(false); }
  };

  useEffect(() => {
    loadTickets(page);
    loadClasses();
  }, [eventId, page]);

  const handleStatusUpdate = async (ticketId: string, status: 'approved' | 'rejected') => {
    setUpdatingId(ticketId);
    try {
      const res = await ticketingApi.updateTicketStatus(ticketId, status);
      if (res.success) {
        toast.success(`Ticket ${status}`);
        loadTickets(page);
        loadClasses();
      } else {
        toast.error((res as any).message || `Failed to ${status} ticket`);
      }
    } catch {
      toast.error(`Failed to ${status} ticket`);
    } finally {
      setUpdatingId(null);
    }
  };

  const handleScanLookup = async () => {
    const code = scanCode.trim();
    if (!code) return;
    setScanLoading(true);
    setScanError(null);
    setScannedTicket(null);
    setCheckInDone(false);
    try {
      const res = await get<any>(`/ticketing/verify/${code}`);
      if (res.success && (res.data as any)?.ticket) {
        setScannedTicket((res.data as any).ticket);
      } else {
        setScanError(res.message || 'Ticket not found');
      }
    } catch {
      setScanError('Failed to look up ticket');
    } finally {
      setScanLoading(false);
    }
  };

  const handleScanCheckIn = async () => {
    if (!scannedTicket) return;
    setCheckingIn(true);
    try {
      const res = await put<any>(`/ticketing/verify/${scannedTicket.ticket_code}/check-in`, {});
      if (res.success) {
        setCheckInDone(true);
        setScannedTicket((prev: any) => prev ? { ...prev, checked_in: true, checked_in_at: (res.data as any)?.checked_in_at || new Date().toISOString() } : prev);
        toast.success('Guest checked in!');
        loadTickets(page);
      } else {
        toast.error(res.message || 'Check-in failed');
      }
    } catch {
      toast.error('Check-in failed');
    } finally {
      setCheckingIn(false);
    }
  };

  const resetScan = useCallback(() => {
    setScanCode("");
    setScannedTicket(null);
    setScanError(null);
    setCheckInDone(false);
    setScanMode('manual');
    // Stop camera scanner if running
    if (scannerRef.current) {
      try { scannerRef.current.stop(); } catch {}
      scannerRef.current = null;
    }
  }, []);

  const startCameraScanner = useCallback(async () => {
    // Check if mediaDevices API is available (requires HTTPS or secure context)
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      toast.error('Camera access requires a secure connection (HTTPS). Please use HTTPS or a supported browser.');
      return;
    }
    // Request camera permission first
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
      stream.getTracks().forEach(track => track.stop());
    } catch (permErr: any) {
      if (permErr.name === 'NotAllowedError') {
        toast.error('Camera permission denied. Please allow camera access in your browser settings.');
      } else if (permErr.name === 'NotFoundError') {
        toast.error('No camera found on this device.');
      } else {
        toast.error('Could not access camera: ' + (permErr.message || 'Unknown error'));
      }
      return;
    }

    setScanMode('camera');
    await new Promise(r => setTimeout(r, 400));
    if (!cameraRef.current) return;
    try {
      const { Html5Qrcode } = await import('html5-qrcode');
      const scanner = new Html5Qrcode(cameraRef.current.id);
      scannerRef.current = scanner;
      await scanner.start(
        { facingMode: 'environment' },
        { fps: 10, qrbox: { width: 250, height: 250 } },
        (decodedText) => {
          let code = decodedText;
          const match = decodedText.match(/\/ticket\/([A-Z0-9-]+)/i);
          if (match) code = match[1];
          setScanCode(code.toUpperCase());
          try { scanner.stop(); } catch {}
          scannerRef.current = null;
          setScanMode('manual');
          setScanLoading(true);
          setScanError(null);
          setScannedTicket(null);
          setCheckInDone(false);
          get<any>(`/ticketing/verify/${code}`).then(res => {
            if (res.success && (res.data as any)?.ticket) {
              setScannedTicket((res.data as any).ticket);
            } else {
              setScanError(res.message || 'Ticket not found');
            }
          }).catch(() => setScanError('Failed to look up ticket')).finally(() => setScanLoading(false));
        },
        () => {}
      );
    } catch {
      toast.error('Failed to start camera scanner. Please try again.');
      setScanMode('manual');
    }
  }, []);

  // Cleanup scanner on dialog close
  useEffect(() => {
    if (!scanOpen && scannerRef.current) {
      try { scannerRef.current.stop(); } catch {}
      scannerRef.current = null;
    }
  }, [scanOpen]);

  const getInitials = (name?: string) => {
    if (!name) return '?';
    return name.split(' ').map((w: string) => w[0]).join('').toUpperCase().slice(0, 2);
  };

  const formatDate = (dateStr: string) =>
    new Date(dateStr).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });

  const formatTime = (timeStr: string) => {
    try {
      const [h, m] = timeStr.split(':');
      const hour = parseInt(h);
      return `${hour % 12 || 12}:${m} ${hour >= 12 ? 'PM' : 'AM'}`;
    } catch { return timeStr; }
  };

  // Summary
  // Use sold from ticket classes (backend computes via SUM of order quantities)
  const totalSold = ticketClasses.reduce((sum: number, tc: any) => sum + (tc.sold || 0), 0);
  const totalQuantity = ticketClasses.reduce((sum: number, tc: any) => sum + (tc.quantity || 0), 0);
  const totalRevenue = tickets.reduce((sum: number, t: any) => sum + (t.total_amount || 0), 0);

  const scannedIsValid = scannedTicket ? ['confirmed', 'approved'].includes(scannedTicket.status) : false;
  const canScanCheckIn = scannedIsValid && !scannedTicket?.checked_in && !checkInDone;

  return (
    <div className="space-y-4">
      {/* Ticket Approval Status Banner */}
      {classesLoading ? (
        <div className="flex items-start gap-3 p-4 rounded-xl border border-border">
          <Skeleton className="w-5 h-5 rounded-full shrink-0" />
          <div className="flex-1 space-y-2">
            <Skeleton className="h-4 w-32" />
            <Skeleton className="h-3 w-full" />
          </div>
        </div>
      ) : approvalStatus === "pending" ? (
        <div className="flex items-start gap-3 p-4 rounded-xl bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800">
          <Clock className="w-5 h-5 text-amber-600 mt-0.5 shrink-0" />
          <div>
            <p className="font-semibold text-amber-800 dark:text-amber-300 text-sm">Pending Approval</p>
            <p className="text-xs text-amber-700 dark:text-amber-400 mt-0.5">Your ticketed event is being reviewed by Nuru. Tickets will be visible to the public once approved.</p>
          </div>
        </div>
      ) : approvalStatus === "rejected" ? (
        <div className="flex items-start gap-3 p-4 rounded-xl bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
          <AlertTriangle className="w-5 h-5 text-red-600 mt-0.5 shrink-0" />
          <div>
            <p className="font-semibold text-red-800 dark:text-red-300 text-sm">Rejected</p>
            <p className="text-xs text-red-700 dark:text-red-400 mt-0.5">Your ticketed event was not approved.{rejectionReason ? ` Reason: ${rejectionReason}` : ''}</p>
          </div>
        </div>
      ) : approvalStatus === "removed" ? (
        <div className="flex items-start gap-3 p-4 rounded-xl bg-muted border border-border">
          <AlertTriangle className="w-5 h-5 text-muted-foreground mt-0.5 shrink-0" />
          <div>
            <p className="font-semibold text-foreground text-sm">Removed</p>
            <p className="text-xs text-muted-foreground mt-0.5">Your ticketed event has been removed by Nuru.{removedReason ? ` Reason: ${removedReason}` : ''}</p>
          </div>
        </div>
      ) : approvalStatus === "approved" ? (
        <div className="flex items-start gap-3 p-4 rounded-xl bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800">
          <CheckCircle2 className="w-5 h-5 text-green-600 mt-0.5 shrink-0" />
          <div>
            <p className="font-semibold text-green-800 dark:text-green-300 text-sm">Approved</p>
            <p className="text-xs text-green-700 dark:text-green-400 mt-0.5">Your tickets are live and visible on the public tickets page.</p>
          </div>
        </div>
      ) : null}

      {/* Scan action */}
      {isCreator && (
        <Button
          onClick={() => { resetScan(); setScanOpen(true); }}
          className="w-full h-11 bg-gradient-to-r from-primary to-primary/80 hover:from-primary/90 hover:to-primary/70 text-primary-foreground font-semibold rounded-xl shadow-md"
        >
          <img src={ScanIcon} alt="Scan" className="w-4 h-4 mr-2 invert" />
          Scan / Enter Ticket Code
        </Button>
      )}
      {isCreator && (
        <ReceivedPaymentsPanel
          source={{ kind: 'event-tickets', eventId }}
          title="Ticket payments received"
        />
      )}
      {isCreator && <TicketOfflineClaimsPanel eventId={eventId} />}

      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-xs text-muted-foreground">Ticket Classes</p>
            <p className="text-lg font-bold mt-1">{ticketClasses.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-xs text-muted-foreground">Tickets Sold</p>
            <p className="text-lg font-bold mt-1">{totalSold} / {totalQuantity}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-xs text-muted-foreground">Orders</p>
            <p className="text-lg font-bold mt-1">{pagination?.total_items || tickets.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-xs text-muted-foreground">Revenue</p>
            <p className="text-lg font-bold text-primary mt-1">{formatPrice(totalRevenue)}</p>
          </CardContent>
        </Card>
      </div>

      {/* Ticket classes overview */}
      {ticketClasses.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {ticketClasses.map((tc: any) => (
            <div key={tc.id} className="flex items-center gap-2 px-3 py-1.5 rounded-full border border-border bg-card text-xs">
              <img src={TicketIcon} alt="" className="w-3.5 h-3.5 dark:invert opacity-70" />
              <span className="font-medium">{tc.name}</span>
              <span className="text-muted-foreground">{tc.sold}/{tc.quantity}</span>
              <span className="text-primary font-semibold">{formatPrice(tc.price)}</span>
            </div>
          ))}
        </div>
      )}

      {/* Ticket orders list */}
      <div>
        <h3 className="text-sm font-semibold text-foreground mb-3">
          Ticket Orders
        </h3>

        {loading ? (
          <div className="space-y-2">
            {[...Array(4)].map((_, i) => (
              <div key={i} className="flex items-center gap-3 p-3 rounded-xl border border-border bg-card">
                <div className="flex-1 min-w-0 space-y-2">
                  <div className="flex items-center gap-2">
                    <Skeleton className="h-4 w-28" />
                    <Skeleton className="h-4 w-20" />
                  </div>
                  <div className="flex items-center gap-2">
                    <Skeleton className="h-3 w-16" />
                    <Skeleton className="h-3 w-10" />
                    <Skeleton className="h-3 w-14" />
                  </div>
                </div>
                <Skeleton className="h-5 w-16 rounded-full" />
              </div>
            ))}
          </div>
        ) : tickets.length === 0 ? (
          <div className="text-center py-12 border-2 border-dashed border-border rounded-xl">
            <img src={TicketIcon} alt="" className="w-10 h-10 mx-auto mb-3 dark:invert opacity-30" />
            <p className="text-sm text-muted-foreground">No ticket orders yet</p>
          </div>
        ) : (
          <div className="space-y-2">
            {tickets.map((ticket: any) => (
              <div
                key={ticket.id}
                className="flex items-center gap-3 p-3 rounded-xl border border-border bg-card hover:bg-muted/30 transition-colors"
              >
                {/* Buyer info */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <p className="text-sm font-medium text-foreground">{ticket.buyer_name || "Unknown"}</p>
                    <Badge variant="outline" className="text-[10px] h-4 font-mono tracking-wide">
                      {ticket.ticket_code}
                    </Badge>
                  </div>
                  <div className="flex items-center gap-2 mt-0.5 text-xs text-muted-foreground flex-wrap">
                    {ticket.ticket_class && <span>{ticket.ticket_class}</span>}
                    <span>×{ticket.quantity}</span>
                    <span className="font-medium text-foreground">{formatPrice(ticket.total_amount)}</span>
                    {ticket.buyer_phone && <span>· {ticket.buyer_phone}</span>}
                  </div>
                </div>

                {/* Status */}
                <Badge className={`text-[10px] capitalize ${STATUS_STYLES[ticket.status] || STATUS_STYLES.pending}`}>
                  {ticket.status}
                </Badge>

                {/* Actions */}
                {isCreator && ticket.status !== 'cancelled' && (
                  <div className="flex items-center gap-1 flex-shrink-0">
                    {ticket.status === 'approved' && ticket.buyer_phone && (
                      <Button
                        size="icon"
                        variant="ghost"
                        className="h-7 w-7 text-blue-600 hover:text-blue-700 hover:bg-blue-50 dark:hover:bg-blue-900/20"
                        disabled={sendingId === ticket.id}
                        onClick={() => handleSendTicket(ticket)}
                        title="Send ticket via WhatsApp"
                      >
                        {sendingId === ticket.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Send className="w-3.5 h-3.5" />}
                      </Button>
                    )}
                    {ticket.status !== 'approved' && (
                      <Button
                        size="icon"
                        variant="ghost"
                        className="h-7 w-7 text-green-600 hover:text-green-700 hover:bg-green-50 dark:hover:bg-green-900/20"
                        disabled={updatingId === ticket.id}
                        onClick={() => handleStatusUpdate(ticket.id, 'approved')}
                        title="Approve"
                      >
                        {updatingId === ticket.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Check className="w-3.5 h-3.5" />}
                      </Button>
                    )}
                    {ticket.status !== 'rejected' && (
                      <Button
                        size="icon"
                        variant="ghost"
                        className="h-7 w-7 text-red-600 hover:text-red-700 hover:bg-red-50 dark:hover:bg-red-900/20"
                        disabled={updatingId === ticket.id}
                        onClick={() => handleStatusUpdate(ticket.id, 'rejected')}
                        title="Reject"
                      >
                        <X className="w-3.5 h-3.5" />
                      </Button>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}

        {/* Pagination */}
        {pagination && pagination.total_pages > 1 && (
          <div className="flex items-center justify-center gap-2 mt-4">
            <Button
              variant="outline"
              size="sm"
              disabled={!pagination.has_previous}
              onClick={() => setPage(p => p - 1)}
            >
              <ChevronLeft className="w-4 h-4" />
            </Button>
            <span className="text-xs text-muted-foreground">
              Page {pagination.page} of {pagination.total_pages}
            </span>
            <Button
              variant="outline"
              size="sm"
              disabled={!pagination.has_next}
              onClick={() => setPage(p => p + 1)}
            >
              <ChevronRight className="w-4 h-4" />
            </Button>
          </div>
        )}
      </div>

      {/* Scan Ticket Dialog */}
      <Dialog open={scanOpen} onOpenChange={(open) => { setScanOpen(open); if (!open) resetScan(); }}>
        <DialogContent className="max-w-md p-0 overflow-hidden">
          <DialogHeader className="p-5 pb-0">
            <DialogTitle className="flex items-center gap-2 text-base">
              <img src={ScanIcon} alt="Scan" className="w-4 h-4 dark:invert" />
              Verify & Check-In Ticket
            </DialogTitle>
          </DialogHeader>

          {!scannedTicket && !scanError && (
            <div className="px-5 pb-5 space-y-3">
              {scanMode === 'camera' ? (
                <div className="space-y-3">
                  <div id="scan-camera-reader" ref={cameraRef} className="w-full rounded-lg overflow-hidden" />
                  <Button variant="outline" size="sm" className="w-full gap-2" onClick={() => { if (scannerRef.current) { try { scannerRef.current.stop(); } catch {} scannerRef.current = null; } setScanMode('manual'); }}>
                    <Keyboard className="w-4 h-4" />
                    Enter Code Manually
                  </Button>
                </div>
              ) : (
                <>
                  <p className="text-xs text-muted-foreground">Enter the ticket code or scan the QR code</p>
                  <div className="flex gap-2">
                    <Input
                      placeholder="NTK-XXXXXXXX"
                      value={scanCode}
                      onChange={(e) => setScanCode(e.target.value.toUpperCase())}
                      onKeyDown={(e) => e.key === 'Enter' && handleScanLookup()}
                      className="font-mono tracking-wider"
                      autoFocus
                    />
                    <Button onClick={handleScanLookup} disabled={scanLoading || !scanCode.trim()}>
                      {scanLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Verify'}
                    </Button>
                  </div>
                  <Button variant="outline" size="sm" className="w-full gap-2" onClick={startCameraScanner}>
                    <img src={CameraIcon} alt="Camera" className="w-4 h-4 dark:invert" />
                    Scan QR with Camera
                  </Button>
                </>
              )}
            </div>
          )}

          {scanError && (
            <div className="px-5 pb-5 text-center space-y-3">
              <div className="w-14 h-14 rounded-full bg-destructive/10 flex items-center justify-center mx-auto">
                <AlertTriangle className="w-7 h-7 text-destructive" />
              </div>
              <p className="text-sm text-destructive font-medium">{scanError}</p>
              <Button variant="outline" size="sm" onClick={resetScan}>Try Again</Button>
            </div>
          )}

          {scannedTicket && (
            <div className="divide-y divide-border">
              {/* Status Banner */}
              <div className={`px-5 py-4 text-center ${
                scannedTicket.checked_in || checkInDone
                  ? 'bg-amber-500/10'
                  : scannedIsValid ? 'bg-emerald-500/10' : 'bg-destructive/10'
              }`}>
                <AnimatePresence mode="wait">
                  {(scannedTicket.checked_in || checkInDone) ? (
                    <motion.div key="used" initial={{ scale: 0.8, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="space-y-1">
                      <ShieldCheck className="w-8 h-8 mx-auto text-amber-500" />
                      <p className="text-amber-600 dark:text-amber-400 font-bold text-sm">ALREADY USED</p>
                      <p className="text-muted-foreground text-xs">
                        {scannedTicket.checked_in_at ? `Checked in at ${new Date(scannedTicket.checked_in_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : ''}
                      </p>
                      {scannedTicket.checked_in_by?.full_name && (
                        <p className="text-[11px] text-muted-foreground">
                          by <span className="text-foreground/80 font-medium">{scannedTicket.checked_in_by.full_name}</span>
                        </p>
                      )}
                    </motion.div>
                  ) : scannedIsValid ? (
                    <motion.div key="valid" initial={{ scale: 0.8, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="space-y-1">
                      <CheckCircle2 className="w-8 h-8 mx-auto text-emerald-500" />
                      <p className="text-emerald-600 dark:text-emerald-400 font-bold text-sm">VALID TICKET</p>
                    </motion.div>
                  ) : (
                    <motion.div key="invalid" initial={{ scale: 0.8, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="space-y-1">
                      <AlertTriangle className="w-8 h-8 mx-auto text-destructive" />
                      <p className="text-destructive font-bold text-sm">{scannedTicket.status?.toUpperCase()}</p>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>

              {/* Buyer */}
              <div className="px-5 py-4 flex items-center gap-3">
                <Avatar className="w-12 h-12 ring-2 ring-border">
                  {scannedTicket.buyer_avatar ? <AvatarImage src={scannedTicket.buyer_avatar} /> : null}
                  <AvatarFallback className="bg-muted text-foreground font-bold">{getInitials(scannedTicket.buyer_name)}</AvatarFallback>
                </Avatar>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-foreground truncate">{scannedTicket.buyer_name || 'Unknown'}</p>
                  {scannedTicket.buyer_phone && (
                    <p className="text-xs text-muted-foreground flex items-center gap-1"><Phone className="w-3 h-3" />{scannedTicket.buyer_phone}</p>
                  )}
                  {scannedTicket.buyer_email && (
                    <p className="text-xs text-muted-foreground flex items-center gap-1 truncate"><Mail className="w-3 h-3" />{scannedTicket.buyer_email}</p>
                  )}
                </div>
              </div>

              {/* Event & Ticket Details */}
              <div className="px-5 py-4 space-y-2">
                <p className="font-semibold text-foreground text-sm">{scannedTicket.event_title}</p>
                {scannedTicket.ticket_class && (
                  <Badge variant="secondary" className="text-[10px] tracking-[1.5px] uppercase">{scannedTicket.ticket_class}</Badge>
                )}
                <div className="space-y-1.5 mt-2">
                  {scannedTicket.event_date && (
                    <p className="text-xs text-muted-foreground flex items-center gap-2"><Calendar className="w-3 h-3" />{formatDate(scannedTicket.event_date)}</p>
                  )}
                  {scannedTicket.event_time && (
                    <p className="text-xs text-muted-foreground flex items-center gap-2"><Clock className="w-3 h-3" />{formatTime(scannedTicket.event_time)}</p>
                  )}
                  {scannedTicket.event_location && (
                    <p className="text-xs text-muted-foreground flex items-center gap-2"><MapPin className="w-3 h-3" />{scannedTicket.event_location}</p>
                  )}
                </div>
              </div>

              {/* Ticket Meta */}
              <div className="px-5 py-3 grid grid-cols-3 gap-2 text-center">
                <div>
                  <p className="text-[9px] tracking-[1.5px] uppercase text-muted-foreground">Code</p>
                  <p className="font-mono text-xs font-bold text-foreground">{scannedTicket.ticket_code}</p>
                </div>
                <div>
                  <p className="text-[9px] tracking-[1.5px] uppercase text-muted-foreground">Qty</p>
                  <p className="text-xs font-bold text-foreground">{scannedTicket.quantity}</p>
                </div>
                <div>
                  <p className="text-[9px] tracking-[1.5px] uppercase text-muted-foreground">Total</p>
                  <p className="text-xs font-bold text-foreground">{scannedTicket.currency || 'TZS'} {scannedTicket.total_amount?.toLocaleString()}</p>
                </div>
              </div>

              {/* Check-in Action */}
              <div className="px-5 py-4">
                <AnimatePresence mode="wait">
                  {checkInDone ? (
                    <motion.div key="done" initial={{ scale: 0.9, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="text-center space-y-1">
                      <CheckCircle2 className="w-8 h-8 text-emerald-500 mx-auto" />
                      <p className="text-emerald-600 dark:text-emerald-400 font-bold text-sm">Checked In!</p>
                      <p className="text-muted-foreground text-xs">Guest may enter</p>
                      <Button variant="outline" size="sm" className="mt-2" onClick={resetScan}>Scan Another</Button>
                    </motion.div>
                  ) : canScanCheckIn ? (
                    <Button
                      onClick={handleScanCheckIn}
                      disabled={checkingIn}
                      className="w-full h-10 bg-emerald-600 hover:bg-emerald-500 text-white font-semibold rounded-xl"
                    >
                      {checkingIn ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <ShieldCheck className="w-4 h-4 mr-2" />}
                      {checkingIn ? 'Checking In...' : 'Check In Attendee'}
                    </Button>
                  ) : scannedTicket.checked_in ? (
                    <div className="text-center">
                      <p className="text-amber-600 dark:text-amber-400 text-sm font-medium">Already used</p>
                      <Button variant="outline" size="sm" className="mt-2" onClick={resetScan}>Scan Another</Button>
                    </div>
                  ) : (
                    <div className="text-center">
                      <p className="text-destructive text-sm font-medium">Cannot check in — ticket is {scannedTicket.status}</p>
                      <Button variant="outline" size="sm" className="mt-2" onClick={resetScan}>Scan Another</Button>
                    </div>
                  )}
                </AnimatePresence>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default EventTicketManagement;
