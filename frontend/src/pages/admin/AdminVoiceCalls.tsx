import { useEffect, useState, useMemo, useCallback } from "react";
import { motion } from "framer-motion";
import {
  PhoneCall, Search, Loader2, AlertTriangle, RefreshCw, X, ChevronDown, ChevronUp,
  Power,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "sonner";
import { voiceCallsApi, type JobStatus, type VoiceFeatureStatus } from "@/lib/api/voiceCalls";
import { cn } from "@/lib/utils";
import { getTimeAgo } from "@/utils/getTimeAgo";

type AdminRow = Awaited<ReturnType<typeof voiceCallsApi.adminListJobs>>["data"] extends (infer T)[] | undefined
  ? T
  : never;

const STATUS_FILTERS: { label: string; value: JobStatus | "all" }[] = [
  { label: "All", value: "all" },
  { label: "Pending", value: "pending" },
  { label: "In progress", value: "in_progress" },
  { label: "Completed", value: "completed" },
  { label: "Failed", value: "failed" },
  { label: "No answer", value: "no_answer" },
  { label: "Busy", value: "busy" },
  { label: "Blocked", value: "blocked" },
  { label: "Opted out", value: "opted_out" },
];

const statusTone = (s: string) => {
  if (s === "completed") return "bg-emerald-50 text-emerald-700 border-emerald-200";
  if (s === "in_progress" || s === "queued") return "bg-sky-50 text-sky-700 border-sky-200";
  if (s === "failed" || s === "blocked") return "bg-rose-50 text-rose-700 border-rose-200";
  if (s === "no_answer" || s === "busy") return "bg-amber-50 text-amber-700 border-amber-200";
  if (s === "opted_out") return "bg-zinc-100 text-zinc-700 border-zinc-200";
  return "bg-muted text-muted-foreground border-border";
};

export default function AdminVoiceCalls() {
  const [rows, setRows] = useState<AdminRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [status, setStatus] = useState<JobStatus | "all">("all");
  const [hasError, setHasError] = useState(false);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [expanded, setExpanded] = useState<string | null>(null);

  const load = useCallback(async (silent = false) => {
    if (!silent) setLoading(true); else setRefreshing(true);
    try {
      const res = await voiceCallsApi.adminListJobs({
        status: status === "all" ? undefined : status,
        has_error: hasError || undefined,
        q: q.trim() || undefined,
        page,
        page_size: 50,
      });
      if (res.success && Array.isArray(res.data)) {
        setRows(res.data as AdminRow[]);
        setTotalPages(res.pagination?.total_pages ?? 1);
      }
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [status, hasError, q, page]);

  useEffect(() => { load(); }, [load]);

  const counts = useMemo(() => {
    const out = { total: rows.length, errors: 0, completed: 0, dialing: 0 };
    for (const r of rows as any[]) {
      if (r.last_error) out.errors++;
      if (r.job.status === "completed") out.completed++;
      if (r.job.status === "in_progress" || r.job.status === "queued") out.dialing++;
    }
    return out;
  }, [rows]);

  return (
    <div className="p-6 space-y-6 max-w-[1400px] mx-auto">
      {/* Header */}
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight flex items-center gap-2">
            <PhoneCall className="h-5 w-5 text-primary" />
            Voice Calls
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Every Smart RSVP call across all organisers, with errors and provider logs.
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => load(true)}
          disabled={refreshing}
        >
          <RefreshCw className={cn("h-4 w-4 mr-2", refreshing && "animate-spin")} />
          Refresh
        </Button>
      </div>

      <FeatureToggleCard />

      {/* KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { label: "Jobs", value: counts.total, tone: "text-foreground" },
          { label: "Dialing now", value: counts.dialing, tone: "text-sky-600" },
          { label: "Completed", value: counts.completed, tone: "text-emerald-600" },
          { label: "With errors", value: counts.errors, tone: "text-rose-600" },
        ].map((k) => (
          <div key={k.label} className="rounded-2xl border bg-card p-4">
            <div className="text-xs uppercase tracking-wide text-muted-foreground">
              {k.label}
            </div>
            <div className={cn("text-2xl font-semibold mt-1", k.tone)}>{k.value}</div>
          </div>
        ))}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[240px] max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); }}
            placeholder="Search phone or recipient name"
            className="pl-9"
            autoComplete="off"
          />
        </div>
        <div className="flex items-center gap-1.5 flex-wrap">
          {STATUS_FILTERS.map((f) => (
            <button
              key={f.value}
              onClick={() => { setStatus(f.value); setPage(1); }}
              className={cn(
                "px-3 h-8 rounded-full text-xs font-medium border transition",
                status === f.value
                  ? "bg-primary text-primary-foreground border-primary"
                  : "bg-background border-border text-muted-foreground hover:text-foreground",
              )}
            >
              {f.label}
            </button>
          ))}
          <button
            onClick={() => { setHasError((v) => !v); setPage(1); }}
            className={cn(
              "px-3 h-8 rounded-full text-xs font-medium border transition flex items-center gap-1.5",
              hasError
                ? "bg-rose-50 text-rose-700 border-rose-200"
                : "bg-background border-border text-muted-foreground hover:text-foreground",
            )}
          >
            <AlertTriangle className="h-3.5 w-3.5" />
            Errors only
          </button>
        </div>
      </div>

      {/* Table */}
      <div className="rounded-2xl border bg-card overflow-hidden">
        {loading ? (
          <div className="p-4 space-y-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-16 w-full rounded-xl" />
            ))}
          </div>
        ) : rows.length === 0 ? (
          <div className="py-16 text-center text-sm text-muted-foreground">
            No voice jobs match these filters.
          </div>
        ) : (
          <div className="divide-y">
            {rows.map((r: any) => {
              const isOpen = expanded === r.job.id;
              return (
                <motion.div key={r.job.id} layout className="px-4 py-3">
                  <button
                    onClick={() => setExpanded(isOpen ? null : r.job.id)}
                    className="w-full flex items-center gap-4 text-left"
                  >
                    <div className="w-10 h-10 rounded-full bg-primary/10 text-primary flex items-center justify-center shrink-0">
                      <PhoneCall className="h-4 w-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-medium truncate">
                          {r.job.recipient_name || r.job.phone_e164}
                        </span>
                        <span className="text-xs text-muted-foreground">
                          {r.job.phone_e164}
                        </span>
                        <span
                          className={cn(
                            "text-[10px] uppercase tracking-wide px-2 py-0.5 rounded-full border",
                            statusTone(r.job.status),
                          )}
                        >
                          {r.job.status}
                        </span>
                        {r.last_error && (
                          <span className="text-[10px] uppercase tracking-wide px-2 py-0.5 rounded-full border bg-rose-50 text-rose-700 border-rose-200 inline-flex items-center gap-1">
                            <AlertTriangle className="h-3 w-3" />
                            Error
                          </span>
                        )}
                      </div>
                      <div className="text-xs text-muted-foreground mt-0.5 truncate">
                        {r.owner?.name || "Unknown owner"}
                        {r.owner?.phone ? ` · ${r.owner.phone}` : ""}
                        {r.campaign?.title ? ` · ${r.campaign.title}` : ""}
                        {" · "}
                        {r.job.created_at ? getTimeAgo(r.job.created_at) : ""}
                      </div>
                    </div>
                    {isOpen ? <ChevronUp className="h-4 w-4 text-muted-foreground" /> : <ChevronDown className="h-4 w-4 text-muted-foreground" />}
                  </button>

                  {isOpen && (
                    <div className="mt-3 ml-14 grid gap-3 md:grid-cols-2">
                      <div className="rounded-xl border bg-background p-3 text-xs space-y-1.5">
                        <div><span className="text-muted-foreground">Attempts:</span> {r.job.attempt} / {r.job.max_attempts}</div>
                        <div><span className="text-muted-foreground">Country / TZ:</span> {r.job.country || "—"} {r.job.timezone ? `· ${r.job.timezone}` : ""}</div>
                        <div><span className="text-muted-foreground">Last called:</span> {r.job.last_called_at ? new Date(r.job.last_called_at).toLocaleString() : "—"}</div>
                        {r.job.block_reason && (
                          <div className="text-rose-700"><span className="text-muted-foreground">Block reason:</span> {r.job.block_reason}</div>
                        )}
                        {r.job.summary && (
                          <div className="pt-2 border-t mt-2"><span className="text-muted-foreground">Summary:</span> {r.job.summary}</div>
                        )}
                      </div>
                      <div className="rounded-xl border bg-background p-3 text-xs space-y-2">
                        <div className="font-medium">Provider logs</div>
                        {(r.logs?.length ?? 0) === 0 ? (
                          <div className="text-muted-foreground">No provider attempts yet.</div>
                        ) : (
                          r.logs.map((l: any) => (
                            <div key={l.id} className="rounded-lg border p-2 space-y-0.5">
                              <div className="flex items-center justify-between gap-2">
                                <span className="font-mono text-[10px] truncate">
                                  {l.provider}{l.provider_call_sid ? ` · ${l.provider_call_sid.slice(0, 10)}…` : ""}
                                </span>
                                <span className={cn("text-[10px] px-1.5 rounded-full border", statusTone(l.status))}>
                                  {l.status}
                                </span>
                              </div>
                              {l.error_message && (
                                <div className="text-rose-700 text-[11px]">
                                  {l.error_code ? `[${l.error_code}] ` : ""}{l.error_message}
                                </div>
                              )}
                              <div className="text-muted-foreground text-[10px]">
                                {l.created_at ? new Date(l.created_at).toLocaleString() : ""}
                                {l.duration_seconds ? ` · ${l.duration_seconds}s` : ""}
                              </div>
                            </div>
                          ))
                        )}
                      </div>
                    </div>
                  )}
                </motion.div>
              );
            })}
          </div>
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-2">
          <Button variant="outline" size="sm" disabled={page <= 1}
            onClick={() => setPage((p) => Math.max(1, p - 1))}>
            Previous
          </Button>
          <span className="text-xs text-muted-foreground">Page {page} of {totalPages}</span>
          <Button variant="outline" size="sm" disabled={page >= totalPages}
            onClick={() => setPage((p) => p + 1)}>
            Next
          </Button>
        </div>
      )}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────
// Feature toggle (admin on/off switch for Smart RSVP Calls)
// ──────────────────────────────────────────────────────────────────

function FeatureToggleCard() {
  const [feature, setFeature] = useState<VoiceFeatureStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [msgEn, setMsgEn] = useState("");
  const [msgSw, setMsgSw] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    const res = await voiceCallsApi.getFeatureStatus();
    if (res.success && res.data) {
      setFeature(res.data);
      setMsgEn(res.data.disabled_message_en);
      setMsgSw(res.data.disabled_message_sw);
    }
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  const onToggle = async (next: boolean) => {
    setSaving(true);
    const res = await voiceCallsApi.updateFeatureStatus({ enabled: next });
    setSaving(false);
    if (res.success && res.data) {
      setFeature(res.data);
      toast.success(next ? "Voice Assistant enabled" : "Voice Assistant disabled");
    } else {
      toast.error("Could not update feature status");
    }
  };

  const onSaveMessages = async () => {
    setSaving(true);
    const res = await voiceCallsApi.updateFeatureStatus({
      disabled_message_en: msgEn,
      disabled_message_sw: msgSw,
    });
    setSaving(false);
    if (res.success && res.data) {
      setFeature(res.data);
      toast.success("Polite message updated");
    } else {
      toast.error("Could not save message");
    }
  };

  if (loading) return <Skeleton className="h-32 w-full rounded-2xl" />;
  const enabled = !!feature?.enabled;

  return (
    <div className={cn(
      "rounded-2xl border p-5 space-y-4",
      enabled
        ? "bg-card border-border"
        : "bg-amber-50/60 dark:bg-amber-500/10 border-amber-200 dark:border-amber-500/30",
    )}>
      <div className="flex items-start gap-4">
        <div className={cn(
          "h-10 w-10 rounded-full flex items-center justify-center shrink-0",
          enabled ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-700",
        )}>
          <Power className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div>
              <div className="font-semibold">Smart RSVP Calls feature</div>
              <div className="text-xs text-muted-foreground mt-0.5">
                {enabled
                  ? "Live — organisers and admins can place voice calls."
                  : "Paused — every user sees a polite \"temporarily unavailable\" message."}
              </div>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-muted-foreground">
                {enabled ? "Enabled" : "Disabled"}
              </span>
              <Switch checked={enabled} disabled={saving} onCheckedChange={onToggle} />
            </div>
          </div>
        </div>
      </div>

      <div className="grid md:grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <label className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
            Message (English)
          </label>
          <Textarea
            value={msgEn}
            onChange={(e) => setMsgEn(e.target.value)}
            rows={3}
            autoComplete="off"
          />
        </div>
        <div className="space-y-1.5">
          <label className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
            Ujumbe (Kiswahili)
          </label>
          <Textarea
            value={msgSw}
            onChange={(e) => setMsgSw(e.target.value)}
            rows={3}
            autoComplete="off"
          />
        </div>
      </div>
      <div className="flex justify-end">
        <Button size="sm" onClick={onSaveMessages} disabled={saving}>
          {saving && <Loader2 className="h-3.5 w-3.5 mr-2 animate-spin" />}
          Save messages
        </Button>
      </div>
    </div>
  );
}
