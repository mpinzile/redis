import { useEffect, useState, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Loader2, RefreshCw, Activity, Ticket, UserCheck } from "lucide-react";
import SvgIcon from "@/components/ui/svg-icon";
import QrIcon from "@/assets/icons/qr-icon.svg";
import { Card, CardContent } from "@/components/ui/card";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { checkinTeamApi, type CheckinLogEntry } from "@/lib/api/checkinTeam";

interface Props {
  eventId: string;
}

const initials = (name?: string) =>
  (name || "?").split(" ").map((w) => w[0]).join("").toUpperCase().slice(0, 2);

const formatWhen = (iso?: string | null) => {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    const today = new Date();
    const sameDay = d.toDateString() === today.toDateString();
    const time = d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    if (sameDay) return `Today, ${time}`;
    return `${d.toLocaleDateString([], { month: "short", day: "numeric" })} · ${time}`;
  } catch {
    return "";
  }
};

const CheckinActivityLog = ({ eventId }: Props) => {
  const [entries, setEntries] = useState<CheckinLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async (silent = false) => {
    if (silent) setRefreshing(true);
    else setLoading(true);
    try {
      const res = await checkinTeamApi.log(eventId, 100);
      if (res?.success) {
        setEntries(Array.isArray(res.data?.entries) ? res.data!.entries : []);
      }
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [eventId]);

  useEffect(() => { void load(); }, [load]);

  return (
    <Card className="border-border/60 shadow-sm">
      <CardContent className="p-5 space-y-4">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <div className="w-9 h-9 rounded-xl bg-primary/10 flex items-center justify-center">
              <Activity className="w-4 h-4 text-primary" />
            </div>
            <div>
              <h3 className="font-semibold text-foreground text-sm">Check-In Activity</h3>
              <p className="text-xs text-muted-foreground">Who scanned whom, and when</p>
            </div>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => load(true)}
            disabled={refreshing || loading}
            className="text-xs"
          >
            {refreshing ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <RefreshCw className="w-3.5 h-3.5" />}
          </Button>
        </div>

        {loading ? (
          <div className="space-y-2">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="h-14 rounded-xl bg-muted/40 animate-pulse" />
            ))}
          </div>
        ) : entries.length === 0 ? (
          <div className="text-center py-10 border-2 border-dashed border-border rounded-2xl">
            <div className="w-14 h-14 bg-muted/50 rounded-2xl flex items-center justify-center mx-auto mb-3">
              <UserCheck className="w-6 h-6 text-muted-foreground/40" />
            </div>
            <p className="font-medium text-sm text-foreground">No check-ins yet</p>
            <p className="text-xs text-muted-foreground mt-1">Scans by you and your team will appear here</p>
          </div>
        ) : (
          <div className="space-y-1.5 max-h-[26rem] overflow-y-auto pr-1 -mr-1">
            <AnimatePresence initial={false}>
              {entries.map((e) => (
                <motion.div
                  key={`${e.kind}-${e.id}-${e.checked_in_at}`}
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0 }}
                  className="flex items-center gap-3 p-2.5 rounded-xl hover:bg-muted/40 transition-colors"
                >
                  <Avatar className="w-9 h-9 ring-2 ring-border">
                    {e.checked_in_by?.avatar ? (
                      <AvatarImage src={e.checked_in_by.avatar} />
                    ) : null}
                    <AvatarFallback className="bg-muted text-foreground text-[11px] font-semibold">
                      {initials(e.checked_in_by?.full_name || e.name)}
                    </AvatarFallback>
                  </Avatar>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 min-w-0">
                      <span className="font-medium text-sm text-foreground truncate">{e.name}</span>
                      <Badge variant="secondary" className="text-[9px] tracking-[1.5px] uppercase shrink-0">
                        {e.kind === "ticket" ? <Ticket className="w-2.5 h-2.5 mr-1" /> : <SvgIcon src={QrIcon} alt="QR" className="w-2.5 h-2.5 mr-1" />}
                        {e.kind}
                      </Badge>
                    </div>
                    <p className="text-[11px] text-muted-foreground truncate">
                      {e.checked_in_by?.full_name
                        ? <>by <span className="text-foreground/80">{e.checked_in_by.full_name}</span> · {formatWhen(e.checked_in_at)}</>
                        : formatWhen(e.checked_in_at)}
                      {e.ref ? <span className="text-muted-foreground/60"> · {e.ref}</span> : null}
                    </p>
                  </div>
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default CheckinActivityLog;
