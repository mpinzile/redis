/**
 * ReservationSuccess — premium "your ticket is on hold" card shown after the
 * user picks "Reserve · pay later". Surfaces the live countdown to the payment
 * deadline plus quick actions (Pay now, Go to My Tickets, Done).
 *
 * Used by every place we offer a reservation flow (BrowseTickets,
 * EventTicketPurchase, etc.) so the experience is identical.
 */
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Clock, CheckCircle2 } from "lucide-react";
import TicketIcon from "@/assets/icons/ticket-icon.svg";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useCurrency } from "@/hooks/useCurrency";

export interface ReservationSuccessData {
  ticket_code: string;
  total_amount: number;
  reserved_until: string; // ISO
  ticket_class_name?: string;
  quantity?: number;
  event_name?: string;
}

interface Props {
  data: ReservationSuccessData;
  /** Open the checkout modal so the user can pay immediately. */
  onPayNow?: () => void;
  /** Close everything (e.g. dismiss outer dialog). */
  onClose?: () => void;
}

function fmtRemaining(seconds: number): string {
  if (seconds <= 0) return "Expired";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s.toString().padStart(2, "0")}s`;
  return `${s}s`;
}

const ReservationSuccess = ({ data, onPayNow, onClose }: Props) => {
  const { format: formatPrice } = useCurrency();
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const deadline = new Date(data.reserved_until).getTime();
  const remaining = Math.max(0, Math.floor((deadline - now) / 1000));
  const isUrgent = remaining > 0 && remaining < 30 * 60;
  const expired = remaining <= 0;

  const deadlineLabel = new Date(data.reserved_until).toLocaleString(undefined, {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });

  return (
    <div className="text-center space-y-4 py-2">
      <div className="w-16 h-16 rounded-full bg-emerald-500/10 flex items-center justify-center mx-auto">
        <CheckCircle2 className="w-8 h-8 text-emerald-600" />
      </div>

      <div>
        <p className="font-bold text-foreground text-lg">Reserved - pay later</p>
        <p className="text-xs text-muted-foreground mt-1">
          We're holding{" "}
          {data.quantity && data.quantity > 1
            ? `${data.quantity} tickets`
            : "your ticket"}{" "}
          for you. Pay before the timer runs out to confirm.
        </p>
      </div>

      {/* Countdown card */}
      <div
        className={`p-4 rounded-xl border-2 ${
          expired
            ? "border-destructive/40 bg-destructive/5"
            : isUrgent
              ? "border-amber-400 bg-amber-50 dark:bg-amber-950/20"
              : "border-emerald-300 dark:border-emerald-800 bg-emerald-50 dark:bg-emerald-950/20"
        }`}
      >
        <div className="flex items-center justify-center gap-2 mb-1">
          <Clock
            className={`w-4 h-4 ${
              expired
                ? "text-destructive"
                : isUrgent
                  ? "text-amber-600"
                  : "text-emerald-600"
            }`}
          />
          <span className="text-[11px] uppercase tracking-wider text-muted-foreground font-semibold">
            Payment due in
          </span>
        </div>
        <p
          className={`text-3xl font-bold tabular-nums tracking-tight ${
            expired
              ? "text-destructive"
              : isUrgent
                ? "text-amber-700 dark:text-amber-300"
                : "text-emerald-700 dark:text-emerald-300"
          }`}
        >
          {fmtRemaining(remaining)}
        </p>
        <p className="text-[11px] text-muted-foreground mt-1">by {deadlineLabel}</p>
      </div>

      {/* Reservation summary */}
      <div className="p-3 rounded-lg bg-muted/50 border border-border space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-xs text-muted-foreground">Reservation code</span>
          <Badge variant="outline" className="font-mono tracking-wider text-xs">
            {data.ticket_code}
          </Badge>
        </div>
        {data.ticket_class_name && (
          <div className="flex items-center justify-between text-xs">
            <span className="text-muted-foreground">Ticket</span>
            <span className="font-medium text-foreground">
              {data.ticket_class_name}
              {data.quantity && data.quantity > 1 ? ` × ${data.quantity}` : ""}
            </span>
          </div>
        )}
        <div className="flex items-center justify-between text-sm pt-1 border-t border-border">
          <span className="text-muted-foreground">Amount due</span>
          <span className="font-bold text-foreground">{formatPrice(data.total_amount)}</span>
        </div>
      </div>

      <div className="flex flex-col gap-2">
        {onPayNow && !expired && (
          <Button className="w-full" onClick={onPayNow}>
            <img src={TicketIcon} alt="" className="w-4 h-4 invert mr-2" />
            Pay now
          </Button>
        )}
        <Button variant="outline" asChild className="w-full">
          <Link to="/my-tickets" onClick={onClose}>
            View in My Tickets
          </Link>
        </Button>
        {onClose && (
          <Button variant="ghost" size="sm" onClick={onClose} className="w-full">
            Done
          </Button>
        )}
      </div>
    </div>
  );
};

export default ReservationSuccess;
