import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  CheckCircle2, ShieldCheck, AlertTriangle, Ticket, UserCheck,
  XCircle, Ban, Clock, Sparkles,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";

/**
 * Test Check-In preview — lets organizers and team members see exactly what
 * each scan-result state looks like, without touching real guest/ticket data.
 */

type Scenario =
  | "guest_success"
  | "ticket_success"
  | "already_used"
  | "invalid"
  | "no_permission"
  | "event_closed";

interface ScenarioConfig {
  key: Scenario;
  label: string;
  tone: "success" | "warning" | "danger";
  title: string;
  subtitle: string;
  name: string;
  meta?: string;
  icon: React.ComponentType<{ className?: string }>;
}

const scenarios: ScenarioConfig[] = [
  {
    key: "guest_success", label: "Guest checked in", tone: "success",
    title: "Welcome In", subtitle: "Guest has been checked in successfully",
    name: "Amani Mushi", meta: "Confirmed · Table 4", icon: CheckCircle2,
  },
  {
    key: "ticket_success", label: "Ticket checked in", tone: "success",
    title: "Ticket Verified", subtitle: "Single-entry ticket accepted",
    name: "Neema Kileo", meta: "VIP · NRU-T7-92K1", icon: Ticket,
  },
  {
    key: "already_used", label: "Already checked in", tone: "warning",
    title: "Already Checked In", subtitle: "Checked in earlier at 14:22",
    name: "Baraka Mwakasege", meta: "Confirmed · Table 2", icon: ShieldCheck,
  },
  {
    key: "invalid", label: "Invalid QR", tone: "danger",
    title: "Invalid Code", subtitle: "We couldn't match this QR to any guest or ticket",
    name: "Unknown", icon: XCircle,
  },
  {
    key: "no_permission", label: "No permission", tone: "danger",
    title: "Access Denied", subtitle: "Your check-in session has been revoked",
    name: "—", icon: Ban,
  },
  {
    key: "event_closed", label: "Check-in closed", tone: "warning",
    title: "Check-In Closed", subtitle: "This event has already ended",
    name: "—", icon: Clock,
  },
];

const toneStyles: Record<ScenarioConfig["tone"], { bg: string; ring: string; icon: string; text: string }> = {
  success: {
    bg: "bg-gradient-to-b from-emerald-500/10 to-emerald-500/5",
    ring: "ring-emerald-500/15", icon: "text-emerald-500", text: "text-emerald-600 dark:text-emerald-400",
  },
  warning: {
    bg: "bg-gradient-to-b from-amber-500/10 to-amber-500/5",
    ring: "ring-amber-500/15", icon: "text-amber-500", text: "text-amber-600 dark:text-amber-400",
  },
  danger: {
    bg: "bg-gradient-to-b from-destructive/10 to-destructive/5",
    ring: "ring-destructive/15", icon: "text-destructive", text: "text-destructive",
  },
};

const initials = (n: string) => n.split(" ").map((w) => w[0]).join("").toUpperCase().slice(0, 2);

const TestCheckinPreview = () => {
  const [active, setActive] = useState<Scenario>("guest_success");
  const scn = scenarios.find((s) => s.key === active)!;
  const tone = toneStyles[scn.tone];
  const Icon = scn.icon;

  return (
    <Card className="border-border/60 overflow-hidden">
      <CardContent className="p-5">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
              <Sparkles className="w-4 h-4 text-primary" />
            </div>
            <div>
              <h4 className="text-sm font-semibold text-foreground">Test Check-In</h4>
              <p className="text-[11px] text-muted-foreground">Preview every scan result. No real data is touched.</p>
            </div>
          </div>
          <Badge variant="secondary" className="text-[10px]">Preview only</Badge>
        </div>

        <div className="flex flex-wrap gap-2 mb-4">
          {scenarios.map((s) => (
            <Button
              key={s.key}
              size="sm"
              variant={active === s.key ? "default" : "outline"}
              className="h-8 text-xs"
              onClick={() => setActive(s.key)}
            >
              {s.label}
            </Button>
          ))}
        </div>

        <div className="rounded-2xl border border-border bg-background overflow-hidden">
          <AnimatePresence mode="wait">
            <motion.div
              key={scn.key}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.18 }}
            >
              <div className={`px-6 py-7 text-center ${tone.bg}`}>
                <motion.div
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ type: "spring", stiffness: 200, damping: 15 }}
                  className={`w-16 h-16 mx-auto rounded-full bg-background flex items-center justify-center ring-4 ${tone.ring}`}
                >
                  <Icon className={`w-8 h-8 ${tone.icon}`} />
                </motion.div>
                <p className={`mt-3 font-bold text-base ${tone.text}`}>{scn.title}</p>
                <p className="text-xs text-muted-foreground mt-1 max-w-xs mx-auto">{scn.subtitle}</p>
              </div>

              {scn.name !== "—" && (
                <div className="px-5 py-4 flex items-center gap-3 border-t border-border">
                  <Avatar className="w-10 h-10 ring-2 ring-primary/15">
                    <AvatarFallback className="bg-primary/10 text-primary font-semibold text-sm">
                      {initials(scn.name)}
                    </AvatarFallback>
                  </Avatar>
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-foreground truncate">{scn.name}</p>
                    {scn.meta && <p className="text-xs text-muted-foreground truncate">{scn.meta}</p>}
                  </div>
                  {scn.tone === "success" && (
                    <Badge className="ml-auto bg-emerald-500/15 text-emerald-700 dark:text-emerald-400 hover:bg-emerald-500/15">
                      <UserCheck className="w-3 h-3 mr-1" /> Scanned
                    </Badge>
                  )}
                  {scn.tone === "warning" && (
                    <Badge variant="secondary" className="ml-auto">Warning</Badge>
                  )}
                  {scn.tone === "danger" && (
                    <Badge variant="destructive" className="ml-auto">Blocked</Badge>
                  )}
                </div>
              )}

              <div className="px-5 py-3 bg-muted/30 border-t border-border flex items-center justify-between">
                <span className="text-[11px] text-muted-foreground inline-flex items-center gap-1.5">
                  <AlertTriangle className="w-3 h-3" />
                  Preview mode — no scan recorded
                </span>
                <span className="text-[11px] text-muted-foreground font-mono">{new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</span>
              </div>
            </motion.div>
          </AnimatePresence>
        </div>
      </CardContent>
    </Card>
  );
};

export default TestCheckinPreview;
