import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { CheckCircle2, ShieldCheck, AlertTriangle, Info } from "lucide-react";
import SvgIcon from "@/components/ui/svg-icon";
import ScanIcon from "@/assets/icons/scan-icon.svg";
import CalendarIcon from "@/assets/icons/calendar-icon.svg";
import LocationIcon from "@/assets/icons/location-icon.svg";
import UserIcon from "@/assets/icons/user-icon.svg";
import TicketIcon from "@/assets/icons/ticket-icon.svg";
import ClockIcon from "@/assets/icons/clock-icon.svg";
import { Card, CardContent } from "@/components/ui/card";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";

/**
 * Test Check-In preview — mirrors the real post-scan UI rendered by
 * EventGuestCheckIn's scan dialog (success / already / error variants).
 */

type Scenario =
  | "guest_success"
  | "ticket_success"
  | "already_used"
  | "not_found"
  | "wrong_event"
  | "ticket_pending"
  | "event_ended";

interface ScenarioConfig {
  key: Scenario;
  label: string;
  kind: "success" | "warning" | "error";
  // success/warning fields
  title: string;
  subtitle: string;
  name: string;
  meta?: string;
  code: string;
  ticketType?: string;
  checkedInAt?: string;
  // error fields
  reasonLabel?: string;
  whatThisMeans?: string;
}

const scenarios: ScenarioConfig[] = [
  {
    key: "guest_success", label: "Guest checked in", kind: "success",
    title: "Welcome In", subtitle: "Guest has been checked in successfully",
    name: "Amani Mushi", meta: "Table 4", code: "NRU-GST-1942",
    ticketType: "Guest Pass", checkedInAt: "17 Jun 2026, 7:32 PM",
  },
  {
    key: "ticket_success", label: "Ticket checked in", kind: "success",
    title: "Welcome In", subtitle: "Ticket verified and admitted",
    name: "Neema Kileo", meta: "VIP", code: "NRU-T7-92K1",
    ticketType: "VIP", checkedInAt: "17 Jun 2026, 7:45 PM",
  },
  {
    key: "already_used", label: "Already checked in", kind: "warning",
    title: "Already Checked In", subtitle: "Checked in at 02:22 PM",
    name: "Baraka Mwakasege", meta: "Table 2", code: "NRU-GST-2048",
    ticketType: "Guest Pass", checkedInAt: "17 Jun 2026, 2:22 PM",
  },
  {
    key: "not_found", label: "Not recognised", kind: "error",
    title: "Unable to Check In",
    subtitle: "We couldn't match this QR to any guest or ticket for this event.",
    name: "Unknown", code: "UNMATCHED-QR",
    reasonLabel: "Not Recognised",
    whatThisMeans: "The code may belong to another event, or the guest is not on the list.",
  },
  {
    key: "wrong_event", label: "Wrong event", kind: "error",
    title: "Unable to Check In",
    subtitle: "This QR code belongs to a different event.",
    name: "Joseph Kimaro", code: "NRU-GST-7711",
    reasonLabel: "Wrong Event",
    whatThisMeans: "Switch to the correct event in the scanner and try again.",
  },
  {
    key: "ticket_pending", label: "Awaiting payment", kind: "error",
    title: "Unable to Check In",
    subtitle: "This ticket hasn't been paid for yet.",
    name: "Halima Said", code: "NRU-T7-55C2",
    reasonLabel: "Awaiting Payment",
    whatThisMeans: "The buyer must complete payment before this ticket can be used.",
  },
  {
    key: "event_ended", label: "Event ended", kind: "warning",
    title: "Check-In Closed", subtitle: "This event has already ended.",
    name: "Amani Mushi", meta: "Table 4", code: "NRU-GST-1942",
    reasonLabel: "Event Ended",
    whatThisMeans: "Reopen check-in from event settings if guests are still arriving.",
  },
];

const initials = (n: string) =>
  n.split(" ").map((w) => w[0]).join("").toUpperCase().slice(0, 2);

const TestCheckinPreview = () => {
  const [active, setActive] = useState<Scenario>("guest_success");
  const scn = scenarios.find((s) => s.key === active)!;
  const tabsRef = useRef<HTMLDivElement>(null);
  const tabRefs = useRef<Record<string, HTMLButtonElement | null>>({});

  // Auto-center the active tab.
  useEffect(() => {
    const wrap = tabsRef.current;
    const btn = tabRefs.current[active];
    if (!wrap || !btn) return;
    const wrapRect = wrap.getBoundingClientRect();
    const btnRect = btn.getBoundingClientRect();
    const offset = btnRect.left - wrapRect.left - (wrapRect.width / 2) + (btnRect.width / 2);
    wrap.scrollTo({ left: wrap.scrollLeft + offset, behavior: "smooth" });
  }, [active]);

  const renderResult = () => {
    if (scn.kind === "error") {
      return (
        <div className="px-5 pb-5 space-y-4 pt-5">
          <div className="text-center">
            <div className="w-20 h-20 rounded-full bg-destructive/10 flex items-center justify-center mx-auto mb-4">
              <AlertTriangle className="w-10 h-10 text-destructive" />
            </div>
            <h3 className="text-lg font-bold text-destructive mb-1">{scn.title}</h3>
            <p className="text-sm text-muted-foreground max-w-xs mx-auto">{scn.subtitle}</p>
          </div>

          <div className="rounded-xl border border-border divide-y divide-border/70">
            <Row icon={ClockIcon} label="Scan Time" value="17 Jun 2026, 7:32 PM" />
            <Row icon={UserIcon} label="Guest" value={scn.name} />
            <Row icon={CalendarIcon} label="Event" value="Mlimani City Hall" />
            <Row icon={TicketIcon} label="Ticket / QR Code" value={scn.code} mono />
            <div className="flex items-center px-3 py-2.5">
              <div className="w-8 h-8 rounded-full bg-destructive/10 flex items-center justify-center mr-3">
                <Info className="w-4 h-4 text-destructive" />
              </div>
              <span className="text-[13px] text-muted-foreground flex-1">Reason</span>
              <Badge className="bg-destructive/10 text-destructive hover:bg-destructive/10 border-0 rounded-full">
                {scn.reasonLabel}
              </Badge>
            </div>
          </div>

          {scn.whatThisMeans && (
            <div className="rounded-xl border border-destructive/20 bg-destructive/[0.04] p-3.5">
              <p className="text-[13px] font-bold text-destructive mb-1">What this means</p>
              <p className="text-[12.5px] text-muted-foreground">{scn.whatThisMeans}</p>
            </div>
          )}
        </div>
      );
    }

    const isWarning = scn.kind === "warning";
    const toneBg = isWarning
      ? "bg-gradient-to-b from-amber-500/10 to-amber-500/5"
      : "bg-gradient-to-b from-emerald-500/10 to-emerald-500/5";
    const ringClass = isWarning ? "bg-amber-500/15 ring-amber-500/10" : "bg-emerald-500/15 ring-emerald-500/10";
    const titleClass = isWarning ? "text-amber-600 dark:text-amber-400" : "text-emerald-600 dark:text-emerald-400";
    const Icon = isWarning ? ShieldCheck : CheckCircle2;
    const iconColor = isWarning ? "text-amber-500" : "text-emerald-500";

    return (
      <div className="divide-y divide-border">
        <div className={`px-6 py-8 text-center ${toneBg}`}>
          <div className={`w-20 h-20 rounded-full flex items-center justify-center mx-auto ring-4 ${ringClass}`}>
            <Icon className={`w-10 h-10 ${iconColor}`} />
          </div>
          <p className={`${titleClass} font-bold text-lg mt-3`}>{scn.title}</p>
          <p className="text-sm text-muted-foreground mt-1">{scn.subtitle}</p>
        </div>

        <div className="px-5 py-5 flex items-center gap-4">
          <Avatar className="w-14 h-14 ring-2 ring-primary/20">
            <AvatarFallback className="bg-primary/10 text-primary text-lg font-bold">
              {initials(scn.name)}
            </AvatarFallback>
          </Avatar>
          <div className="flex-1 min-w-0">
            <p className="font-bold text-foreground truncate text-lg">{scn.name}</p>
            {scn.meta && <Badge variant="secondary" className="text-xs mt-1">{scn.meta}</Badge>}
          </div>
        </div>

        <div className="px-5 py-4 bg-muted/30 space-y-2">
          <p className="font-semibold text-sm text-foreground">Mlimani City Hall</p>
          <p className="text-xs text-muted-foreground flex items-center gap-2">
            <SvgIcon src={CalendarIcon} alt="" className="w-3.5 h-3.5" />17 Jun 2026, 7:30 PM
          </p>
          <p className="text-xs text-muted-foreground flex items-center gap-2">
            <SvgIcon src={LocationIcon} alt="" className="w-3.5 h-3.5" />Mikocheni, Dar es Salaam
          </p>
        </div>

        <div className="px-5 py-4 grid grid-cols-2 gap-3 text-[12px]">
          <Mini label="Ticket Type" value={scn.ticketType || "Guest Pass"} />
          <Mini label="Ticket ID" value={scn.code} mono />
          {scn.checkedInAt && <Mini label="Checked In At" value={scn.checkedInAt} colSpan />}
        </div>
      </div>
    );
  };

  return (
    <Card className="border-border/60 overflow-hidden">
      <CardContent className="p-5">
        <div className="flex items-center gap-2 mb-4">
          <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
            <SvgIcon src={ScanIcon} alt="" className="w-4 h-4 text-primary" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-foreground">Scan Previews</h4>
            <p className="text-[11px] text-muted-foreground">Preview every scan result.</p>
          </div>
        </div>

        <div
          ref={tabsRef}
          className="flex gap-2 mb-4 overflow-x-auto scrollbar-none -mx-1 px-1 scroll-smooth"
          style={{ scrollbarWidth: "none" }}
        >
          {scenarios.map((s) => {
            const selected = active === s.key;
            return (
              <button
                key={s.key}
                ref={(el) => (tabRefs.current[s.key] = el)}
                onClick={() => setActive(s.key)}
                className={`shrink-0 h-8 px-3.5 rounded-full text-[12px] font-semibold transition-colors ${
                  selected
                    ? "bg-primary text-primary-foreground"
                    : "bg-muted text-foreground/70 hover:bg-muted/70"
                }`}
              >
                {s.label}
              </button>
            );
          })}
        </div>

        <div className="rounded-2xl border border-border bg-background overflow-hidden shadow-sm">
          <AnimatePresence mode="wait">
            <motion.div
              key={scn.key}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.18 }}
            >
              {renderResult()}
            </motion.div>
          </AnimatePresence>
        </div>
      </CardContent>
    </Card>
  );
};

const Row = ({ icon, label, value, mono }: { icon: string; label: string; value: string; mono?: boolean }) => (
  <div className="flex items-center px-3 py-2.5">
    <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center mr-3">
      <SvgIcon src={icon} alt="" className="w-4 h-4 text-primary" />
    </div>
    <span className="text-[13px] text-muted-foreground flex-1">{label}</span>
    <span className={`text-[13px] font-bold text-foreground text-right ${mono ? "font-mono text-[12px]" : ""}`}>{value}</span>
  </div>
);

const Mini = ({ label, value, mono, colSpan }: { label: string; value: string; mono?: boolean; colSpan?: boolean }) => (
  <div className={colSpan ? "col-span-2" : ""}>
    <p className="text-[10px] uppercase tracking-wide text-muted-foreground/80 font-semibold">{label}</p>
    <p className={`text-[13px] font-bold text-foreground ${mono ? "font-mono text-[12px]" : ""}`}>{value}</p>
  </div>
);

export default TestCheckinPreview;
