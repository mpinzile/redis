/**
 * WhatsApp Logs Dashboard
 * -----------------------
 * Lists every WhatsApp send attempt (invitations, OTPs, RSVPs, tickets,
 * contributions, vendor bookings, password resets, media, button, plain
 * text), and lets the user filter, inspect, resend, and delete them.
 *
 * Mounted at:
 *   /whatsapp-logs          — user-facing (scoped to their events / actions)
 *   /admin/whatsapp-logs    — admin route (same component, server returns
 *                              full visibility + soft-delete toggle works)
 */
import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import {
  Search, RefreshCw, Loader2, CheckCircle2, Clock, AlertTriangle,
  XCircle, Mail, Eye, RotateCcw, ChevronLeft, ChevronRight,
  Trash2, ShieldAlert, Filter, Phone, MessageSquare, Copy, ArchiveRestore,
  FileSpreadsheet, FileText,
} from "lucide-react";
import {
  listWhatsappLogs, getWhatsappLog, getWhatsappLogStats, resendWhatsappLog,
  bulkResendWhatsappLogs,
  deleteWhatsappLog, bulkDeleteWhatsappLogs, restoreWhatsappLog,
  listWhatsappLogEvents, listWhatsappLogPurposes,
  type WaLog, type WaLogDetail, type WaLogStatus, type WaLogQuery,
  type WaEventOption,
} from "@/lib/api/whatsappLogs";
import {
  WA_ERROR_LABELS, exportLogsToExcel, exportLogsToPdf,
} from "@/lib/whatsappLogsExport";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { toast } from "@/hooks/use-toast";
import { getTimeAgo } from "@/utils/getTimeAgo";

const STATUS_META: Record<WaLogStatus | "total", { label: string; tone: string; icon: any }> = {
  queued:    { label: "Queued",    tone: "bg-slate-100 text-slate-700 border-slate-200",          icon: Clock },
  sent:      { label: "Sent",      tone: "bg-sky-50 text-sky-700 border-sky-200",                 icon: Mail },
  delivered: { label: "Delivered", tone: "bg-emerald-50 text-emerald-700 border-emerald-200",     icon: CheckCircle2 },
  read:      { label: "Read",      tone: "bg-violet-50 text-violet-700 border-violet-200",        icon: Eye },
  failed:    { label: "Failed",    tone: "bg-rose-50 text-rose-700 border-rose-200",              icon: XCircle },
  rejected:  { label: "Rejected",  tone: "bg-amber-50 text-amber-800 border-amber-200",           icon: AlertTriangle },
  pending:   { label: "Pending",   tone: "bg-slate-100 text-slate-700 border-slate-200",          icon: Clock },
  unknown:   { label: "Unknown",   tone: "bg-slate-100 text-slate-700 border-slate-200",          icon: AlertTriangle },
  total:     { label: "Total",     tone: "bg-slate-50 text-slate-700 border-slate-200",           icon: Mail },
};

const CATEGORY_LABEL: Record<string, string> = {
  invitation: "Invitation", invitation_card: "Invitation Card",
  otp: "OTP", password_reset: "Password Reset", account_setup: "Account Setup",
  rsvp: "RSVP", contribution: "Contribution", committee: "Committee",
  meeting: "Meeting", ticket: "Ticket", vendor_booking: "Vendor / Booking",
  payment: "Payment", reminder: "Reminder", expense: "Expense",
  text: "Plain Text", template: "Template", media: "Media", system: "System",
};

const STATUS_OPTIONS: WaLogStatus[] = ["queued","sent","delivered","read","failed","rejected","pending","unknown"];
const CATEGORY_OPTIONS = Object.keys(CATEGORY_LABEL);
const RECIPIENT_TYPE_OPTIONS = [
  { v: "guest", l: "Guest" }, { v: "contributor", l: "Contributor" },
  { v: "ticket_buyer", l: "Ticket buyer" }, { v: "participant", l: "Participant" },
  { v: "vendor", l: "Vendor" }, { v: "client", l: "Client" }, { v: "user", l: "User" },
];
const PURPOSE_LABEL: Record<string, string> = {
  invitation_card: "Invitation card", invitation_text: "Invitation text",
  invitation_text_fallback: "Invitation text (fallback)", invitation_message: "Invitation message",
  thank_you_card: "Thank-you card", thank_you_message: "Thank-you message",
  contribution_receipt: "Contribution receipt", contribution_target: "Contribution target",
  contribution_invite: "Contribution invite", organiser_alert: "Organiser alert",
  committee_invitation: "Committee invite", meeting_invitation: "Meeting invite",
  ticket_receipt: "Ticket receipt", ticket_transfer: "Ticket transfer",
  ticket_delivery: "Ticket delivery", payment_confirmation: "Payment confirmation",
  vendor_payment: "Vendor payment", vendor_receipt: "Vendor receipt",
  vendor_confirmed_alert: "Vendor confirmed",
  booking_request: "Booking request", booking_accepted: "Booking accepted",
  expense_notification: "Expense notification",
  event_reminder: "Event reminder", account_setup: "Account setup", free_text: "Free text",
};

function StatusPill({ status }: { status: WaLogStatus }) {
  const meta = STATUS_META[status] ?? STATUS_META.unknown;
  const Icon = meta.icon;
  return (
    <span className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium ${meta.tone}`}>
      <Icon className="h-3 w-3" />{meta.label}
    </span>
  );
}

function AvailabilityBadge({ value }: { value: boolean | null }) {
  if (value === true)  return <span className="inline-flex items-center gap-1 text-[10px] rounded-full px-1.5 py-0.5 border bg-emerald-50 text-emerald-700 border-emerald-200">on WhatsApp</span>;
  if (value === false) return <span className="inline-flex items-center gap-1 text-[10px] rounded-full px-1.5 py-0.5 border bg-rose-50 text-rose-700 border-rose-200">not on WhatsApp</span>;
  return null;
}

function FallbackBadge({ log }: { log: WaLog }) {
  if (!log.fallback_attempted) return null;
  const ok = log.fallback_status === "sent" || log.fallback_status === "delivered";
  const cls = ok
    ? "bg-emerald-50 text-emerald-700 border-emerald-200"
    : "bg-amber-50 text-amber-800 border-amber-200";
  const label = `${(log.fallback_channel || "sms").toUpperCase()} ${log.fallback_status || "attempted"}`;
  return (
    <span className={`inline-flex items-center gap-1 text-[10px] rounded-full px-1.5 py-0.5 border ${cls}`}>
      <ShieldAlert className="h-2.5 w-2.5" />{label}
    </span>
  );
}

function StatCard({ label, count, tone, active, onClick }:
  { label: string; count: number; tone: string; active?: boolean; onClick?: () => void; }) {
  return (
    <button type="button" onClick={onClick}
      className={`text-left rounded-xl border p-3 transition-all ${tone} ${active ? "ring-2 ring-offset-1 ring-slate-400" : "hover:shadow-sm"}`}>
      <div className="text-[11px] uppercase tracking-wide opacity-70">{label}</div>
      <div className="mt-1 text-2xl font-semibold">{count.toLocaleString()}</div>
    </button>
  );
}

export default function WhatsappLogs() {
  const [filters, setFilters] = useState<WaLogQuery>({ page: 1, limit: 25 });
  const [search, setSearch] = useState("");
  const [recipient, setRecipient] = useState("");
  const [logs, setLogs] = useState<WaLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [pagination, setPagination] = useState<{ total: number; total_pages: number; current_page: number } | null>(null);
  const [stats, setStats] = useState<Record<string, number>>({});
  const [events, setEvents] = useState<WaEventOption[]>([]);
  const [purposes, setPurposes] = useState<string[]>([]);
  const [showDeleted, setShowDeleted] = useState(false);
  const [showFilters, setShowFilters] = useState(false);

  // Selection (for bulk delete)
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [exporting, setExporting] = useState(false);

  const [activeLog, setActiveLog] = useState<WaLogDetail | null>(null);
  const [activeLoading, setActiveLoading] = useState(false);

  const [resendTarget, setResendTarget] = useState<WaLog | null>(null);
  const [resendBusy, setResendBusy] = useState(false);

  const [bulkResendOpen, setBulkResendOpen] = useState(false);
  const [bulkResendBusy, setBulkResendBusy] = useState(false);

  const [confirmDelete, setConfirmDelete] = useState<{ ids: string[]; bulk: boolean } | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);

  const initialLoad = useRef(true);

  const fetchLogs = useCallback(async (opts?: { silent?: boolean }) => {
    if (!opts?.silent) setLoading(true);
    try {
      const res: any = await listWhatsappLogs({
        ...filters,
        q: search || undefined,
        recipient: recipient || undefined,
        with_deleted: showDeleted ? 1 : 0,
      });
      const payload = res?.data;
      const items: WaLog[] = Array.isArray(payload) ? payload
        : Array.isArray(payload?.items) ? payload.items
        : Array.isArray(res?.items) ? res.items : [];
      const pg = payload?.pagination ?? res?.pagination ?? null;
      setLogs(items);
      setPagination(pg ? {
        total: pg.total_items ?? pg.total ?? items.length,
        total_pages: pg.total_pages ?? 1,
        current_page: pg.page ?? pg.current_page ?? 1,
      } : null);
      // Clear stale selections (rows no longer visible).
      setSelected((prev) => {
        if (!prev.size) return prev;
        const visible = new Set(items.map((l) => l.id));
        const next = new Set<string>();
        prev.forEach((id) => visible.has(id) && next.add(id));
        return next;
      });
    } catch (e: any) {
      if (!opts?.silent) {
        toast({ title: "Failed to load WhatsApp logs", description: e?.message ?? "Try again.", variant: "destructive" });
      }
    } finally {
      if (!opts?.silent) setLoading(false);
    }
  }, [filters, search, recipient, showDeleted]);

  const fetchStats = useCallback(async () => {
    try {
      const r = await getWhatsappLogStats(7);
      setStats((r?.data as any) ?? {});
    } catch {/* no-op */}
  }, []);

  const fetchAux = useCallback(async () => {
    try {
      const [evRes, pRes] = await Promise.all([listWhatsappLogEvents(), listWhatsappLogPurposes()]);
      setEvents((evRes?.data as any) || []);
      setPurposes((pRes?.data as any) || []);
    } catch {/* no-op */}
  }, []);

  useEffect(() => { fetchLogs(); }, [fetchLogs]);
  useEffect(() => { fetchStats(); fetchAux(); }, [fetchStats, fetchAux]);

  // Silent background refresh — also keeps the Events dropdown fresh so
  // newly-logged events appear without the user reloading the page.
  useEffect(() => {
    const id = window.setInterval(() => {
      if (document.visibilityState !== "visible") return;
      fetchLogs({ silent: true });
      fetchStats();
      fetchAux();
    }, 20000);
    return () => window.clearInterval(id);
  }, [fetchLogs, fetchStats, fetchAux]);

  const onOpenLog = async (id: string) => {
    setActiveLoading(true);
    setActiveLog({ id } as any);
    try {
      const r = await getWhatsappLog(id);
      if (r?.success) setActiveLog(r.data as WaLogDetail);
    } catch (e: any) {
      toast({ title: "Couldn't load log detail", description: e?.message ?? "", variant: "destructive" });
      setActiveLog(null);
    } finally {
      setActiveLoading(false);
    }
  };

  const onResend = async () => {
    if (!resendTarget) return;
    setResendBusy(true);
    try {
      const r = await resendWhatsappLog(resendTarget.id);
      if (r?.success) {
        toast({ title: "Resend queued", description: "A fresh attempt has been scheduled. The original failure record is kept for audit." });
        setResendTarget(null);
        await Promise.all([fetchLogs(), fetchStats()]);
      } else { throw new Error(r?.message || "Resend failed"); }
    } catch (e: any) {
      toast({ title: "Couldn't resend", description: e?.message ?? "", variant: "destructive" });
    } finally { setResendBusy(false); }
  };

  const selectedLogs = useMemo(
    () => logs.filter((l) => selected.has(l.id)),
    [logs, selected],
  );
  const retryableSelected = useMemo(
    () => selectedLogs.filter((l) => l.retryable),
    [selectedLogs],
  );

  const onBulkResend = async () => {
    if (retryableSelected.length === 0) return;
    setBulkResendBusy(true);
    try {
      const ids = retryableSelected.map((l) => l.id);
      const r = await bulkResendWhatsappLogs(ids);
      const data = r?.data;
      toast({
        title: "Bulk resend queued",
        description: `Queued ${data?.queued ?? 0}` +
          (data?.skipped ? ` - skipped ${data.skipped}` : "") +
          ". Each retry runs on its own worker, so large batches send in parallel.",
      });
      setBulkResendOpen(false);
      setSelected(new Set());
      await Promise.all([fetchLogs(), fetchStats()]);
    } catch (e: any) {
      toast({ title: "Bulk resend failed", description: e?.message ?? "", variant: "destructive" });
    } finally {
      setBulkResendBusy(false);
    }
  };

  const hasActiveFilters = useMemo(() => (
    !!(filters.status || filters.category || filters.message_purpose ||
       filters.event_id || filters.error_code || filters.whatsapp_available ||
       filters.fallback_status || filters.recipient_type || filters.message_type ||
       search || recipient || showDeleted)
  ), [filters, search, recipient, showDeleted]);

  const resetAllFilters = () => {
    setFilters({ page: 1, limit: filters.limit ?? 25 });
    setSearch("");
    setRecipient("");
    setShowDeleted(false);
  };

  const onDelete = async () => {
    if (!confirmDelete) return;
    setDeleteBusy(true);
    try {
      if (confirmDelete.bulk) {
        const r = await bulkDeleteWhatsappLogs(confirmDelete.ids);
        toast({ title: "Deleted", description: `Removed ${r?.data?.deleted ?? confirmDelete.ids.length} log(s).` });
      } else {
        await deleteWhatsappLog(confirmDelete.ids[0]);
        toast({ title: "Deleted", description: "Log removed." });
      }
      setConfirmDelete(null);
      setSelected(new Set());
      await Promise.all([fetchLogs(), fetchStats()]);
    } catch (e: any) {
      toast({ title: "Couldn't delete", description: e?.message ?? "", variant: "destructive" });
    } finally { setDeleteBusy(false); }
  };

  const onRestore = async (id: string) => {
    try {
      await restoreWhatsappLog(id);
      toast({ title: "Restored", description: "Log restored." });
      await fetchLogs();
    } catch (e: any) {
      toast({ title: "Couldn't restore", description: e?.message ?? "(admins only)", variant: "destructive" });
    }
  };

  const copyPhone = async (phone: string) => {
    try { await navigator.clipboard.writeText(phone); toast({ title: "Copied", description: phone }); }
    catch { /* no-op */ }
  };

  /** Fetch the full filtered result set (across all pages) for export. */
  const fetchAllForExport = useCallback(async (): Promise<WaLog[]> => {
    const PAGE = 100; // server caps page size at 100
    const collected: WaLog[] = [];
    const seen = new Set<string>();
    let page = 1;
    // Hard cap so an over-eager admin can't run away with 100k rows.
    for (let i = 0; i < 500; i++) {
      const res: any = await listWhatsappLogs({
        ...filters,
        q: search || undefined,
        recipient: recipient || undefined,
        with_deleted: showDeleted ? 1 : 0,
        page, limit: PAGE,
      });
      const payload = res?.data;
      const items: WaLog[] = Array.isArray(payload) ? payload
        : Array.isArray(payload?.items) ? payload.items
        : Array.isArray(res?.items) ? res.items : [];
      if (!items.length) break;
      let added = 0;
      for (const it of items) {
        if (it?.id && !seen.has(it.id)) { seen.add(it.id); collected.push(it); added++; }
      }
      const pg = payload?.pagination ?? res?.pagination ?? null;
      const totalPages = pg?.total_pages ?? null;
      if (totalPages != null) {
        if (page >= totalPages) break;
      } else if (added === 0) {
        break;
      }
      page += 1;
    }
    return collected;
  }, [filters, search, recipient, showDeleted]);

  const activeFilterChips = useMemo(() => {
    const chips: { label: string; value: string }[] = [];
    if (filters.status) chips.push({ label: "Status", value: filters.status });
    if (filters.category) chips.push({ label: "Category", value: filters.category });
    if (filters.message_purpose) chips.push({ label: "Purpose", value: filters.message_purpose });
    if (filters.event_id) {
      const ev = events.find((e) => e.event_id === filters.event_id);
      if (ev) chips.push({ label: "Event", value: ev.event_name });
    }
    if (filters.error_code) chips.push({ label: "Error", value: WA_ERROR_LABELS[filters.error_code] || filters.error_code });
    if (filters.whatsapp_available) chips.push({ label: "WhatsApp", value: filters.whatsapp_available });
    if (filters.fallback_status) chips.push({ label: "Fallback", value: filters.fallback_status });
    if (search) chips.push({ label: "Search", value: search });
    if (recipient) chips.push({ label: "Phone", value: recipient });
    return chips;
  }, [filters, events, search, recipient]);

  const onExport = async (kind: "xlsx" | "pdf") => {
    setExporting(true);
    try {
      // Selection takes precedence; otherwise export ALL across pagination
      // matching the current filters.
      const all = selectedLogs.length > 0 ? selectedLogs : await fetchAllForExport();
      if (!all.length) {
        toast({ title: "Nothing to export", description: "No logs match the current filters." });
        return;
      }
      if (kind === "xlsx") exportLogsToExcel(all);
      else await exportLogsToPdf(all, activeFilterChips);
      toast({
        title: "Report ready",
        description: `${all.length} record${all.length === 1 ? "" : "s"} exported${selectedLogs.length ? " (selected rows)" : ""}.`,
      });
    } catch (e: any) {
      toast({ title: "Export failed", description: e?.message ?? "Try again.", variant: "destructive" });
    } finally {
      setExporting(false);
    }
  };

  const statusFilter = filters.status ?? "";
  const setStatusFilter = (s: string) => setFilters((f) => ({ ...f, status: s || undefined, page: 1 }));

  const statBlocks = useMemo(() => {
    const order: (WaLogStatus | "total")[] = ["total","delivered","read","sent","queued","failed","rejected"];
    return order.map((k) => ({ key: k, label: STATUS_META[k].label, tone: STATUS_META[k].tone, count: Number(stats[k] || 0) }));
  }, [stats]);

  const allSelectedOnPage = logs.length > 0 && logs.every((l) => selected.has(l.id));
  const toggleSelectAll = (checked: boolean) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (checked) logs.forEach((l) => next.add(l.id));
      else logs.forEach((l) => next.delete(l.id));
      return next;
    });
  };
  const toggleOne = (id: string, checked: boolean) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (checked) next.add(id); else next.delete(id);
      return next;
    });
  };

  return (
    <div className="mx-auto w-full max-w-7xl px-3 py-4 md:px-6 md:py-6 space-y-5">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl md:text-2xl font-semibold tracking-tight text-slate-900">WhatsApp Logs</h1>
          <p className="text-sm text-slate-500">Every WhatsApp message Nuru tried to send — what worked, what failed, and why.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" onClick={() => setShowFilters((s) => !s)}>
            <Filter className="h-4 w-4 mr-2" /> {showFilters ? "Hide filters" : "More filters"}
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={resetAllFilters}
            disabled={!hasActiveFilters}
            title="Clear all filters"
          >
            <XCircle className="h-4 w-4 mr-2" /> Reset filters
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm" disabled={exporting || logs.length === 0}>
                {exporting ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <FileSpreadsheet className="h-4 w-4 mr-2" />}
                Download
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-48">
              <DropdownMenuItem onClick={() => onExport("xlsx")}>
                <FileSpreadsheet className="h-4 w-4 mr-2 text-emerald-600" /> Excel (.xlsx)
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => onExport("pdf")}>
                <FileText className="h-4 w-4 mr-2 text-rose-600" /> PDF report
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <Button variant="outline" size="sm" onClick={() => { fetchLogs(); fetchStats(); fetchAux(); }}>
            <RefreshCw className="h-4 w-4 mr-2" /> Refresh
          </Button>
        </div>
      </header>

      {/* Stats strip */}
      <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-2">
        {statBlocks.map((s) => (
          <StatCard key={s.key} label={s.label} count={s.count} tone={s.tone}
            active={s.key !== "total" && statusFilter === s.key}
            onClick={() => s.key === "total" ? setStatusFilter("") : setStatusFilter(s.key)} />
        ))}
      </div>

      {/* Primary filters */}
      <div className="grid grid-cols-1 md:grid-cols-12 gap-2 rounded-xl border bg-white p-3">
        <div className="md:col-span-3 relative">
          <Search className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
          <Input className="pl-9" placeholder="Search name, summary, template, error…"
            value={search} onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && setFilters((f) => ({ ...f, page: 1 }))} />
        </div>
        <div className="md:col-span-2">
          <Input placeholder="Phone (e.g. 0712… or 2557…)" value={recipient}
            onChange={(e) => setRecipient(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && setFilters((f) => ({ ...f, page: 1 }))} />
        </div>
        <div className="md:col-span-2">
          <Select value={statusFilter || "__all"} onValueChange={(v) => setStatusFilter(v === "__all" ? "" : v)}>
            <SelectTrigger><SelectValue placeholder="Status" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="__all">All statuses</SelectItem>
              {STATUS_OPTIONS.map((s) => (<SelectItem key={s} value={s}>{STATUS_META[s].label}</SelectItem>))}
            </SelectContent>
          </Select>
        </div>
        <div className="md:col-span-2">
          <Select value={filters.category ?? "__all"} onValueChange={(v) => setFilters((f) => ({ ...f, category: v === "__all" ? undefined : v, page: 1 }))}>
            <SelectTrigger><SelectValue placeholder="Category" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="__all">All categories</SelectItem>
              {CATEGORY_OPTIONS.map((c) => (<SelectItem key={c} value={c}>{CATEGORY_LABEL[c]}</SelectItem>))}
            </SelectContent>
          </Select>
        </div>
        <div className="md:col-span-2">
          <Select value={filters.event_id ?? "__all"} onValueChange={(v) => setFilters((f) => ({ ...f, event_id: v === "__all" ? undefined : v, page: 1 }))}>
            <SelectTrigger><SelectValue placeholder="Event" /></SelectTrigger>
            <SelectContent className="max-h-80">
              <SelectItem value="__all">All events</SelectItem>
              {events.map((e) => (
                <SelectItem key={e.event_id} value={e.event_id}>{e.event_name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="md:col-span-1">
          <Button className="w-full" onClick={() => setFilters((f) => ({ ...f, page: 1 }))}>Apply</Button>
        </div>
      </div>

      {/* Secondary filters (collapsible) */}
      {showFilters && (
        <div className="grid grid-cols-1 md:grid-cols-12 gap-2 rounded-xl border bg-white p-3">
          <div className="md:col-span-3">
            <Select value={filters.message_purpose ?? "__all"} onValueChange={(v) => setFilters((f) => ({ ...f, message_purpose: v === "__all" ? undefined : v, page: 1 }))}>
              <SelectTrigger><SelectValue placeholder="Purpose" /></SelectTrigger>
              <SelectContent className="max-h-80">
                <SelectItem value="__all">Any purpose</SelectItem>
                {purposes.map((p) => (
                  <SelectItem key={p} value={p}>{PURPOSE_LABEL[p] ?? p}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="md:col-span-2">
            <Select value={filters.recipient_type ?? "__all"} onValueChange={(v) => setFilters((f) => ({ ...f, recipient_type: v === "__all" ? undefined : v, page: 1 }))}>
              <SelectTrigger><SelectValue placeholder="Recipient" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__all">Any recipient type</SelectItem>
                {RECIPIENT_TYPE_OPTIONS.map((r) => (<SelectItem key={r.v} value={r.v}>{r.l}</SelectItem>))}
              </SelectContent>
            </Select>
          </div>
          <div className="md:col-span-2">
            <Select value={filters.message_type ?? "__all"} onValueChange={(v) => setFilters((f) => ({ ...f, message_type: v === "__all" ? undefined : v, page: 1 }))}>
              <SelectTrigger><SelectValue placeholder="Type" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__all">All types</SelectItem>
                {["text", "template", "media", "button", "image", "document"].map((t) => (
                  <SelectItem key={t} value={t}>{t}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="md:col-span-2">
            <Select value={(filters.whatsapp_available ?? "") || "__all"} onValueChange={(v) => setFilters((f) => ({ ...f, whatsapp_available: v === "__all" ? "" : (v as any), page: 1 }))}>
              <SelectTrigger><SelectValue placeholder="WhatsApp availability" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__all">All recipients</SelectItem>
                <SelectItem value="true">On WhatsApp</SelectItem>
                <SelectItem value="false">Not on WhatsApp</SelectItem>
                <SelectItem value="unknown">Unknown</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="md:col-span-2">
            <Select value={filters.fallback_status ?? "__all"} onValueChange={(v) => setFilters((f) => ({ ...f, fallback_status: v === "__all" ? undefined : v, page: 1 }))}>
              <SelectTrigger><SelectValue placeholder="SMS fallback" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__all">Any fallback</SelectItem>
                <SelectItem value="none">No fallback</SelectItem>
                <SelectItem value="attempted">Attempted</SelectItem>
                <SelectItem value="sent">SMS sent</SelectItem>
                <SelectItem value="delivered">SMS delivered</SelectItem>
                <SelectItem value="failed">SMS failed</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="md:col-span-3">
            <Select value={filters.error_code ?? "__all"} onValueChange={(v) => setFilters((f) => ({ ...f, error_code: v === "__all" ? undefined : v, page: 1 }))}>
              <SelectTrigger><SelectValue placeholder="Specific error" /></SelectTrigger>
              <SelectContent className="max-h-80">
                <SelectItem value="__all">Any error</SelectItem>
                {Object.entries(WA_ERROR_LABELS).map(([code, label]) => (
                  <SelectItem key={code} value={code}>
                    <span className="font-mono text-xs text-slate-500 mr-2">{code}</span>{label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="md:col-span-1 flex items-center justify-end gap-2 text-xs">
            <label className="inline-flex items-center gap-1 cursor-pointer select-none">
              <Checkbox checked={showDeleted} onCheckedChange={(v) => setShowDeleted(!!v)} />
              <span>Deleted</span>
            </label>
          </div>
        </div>
      )}

      {/* Bulk-actions bar */}
      {selected.size > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl border bg-amber-50/60 border-amber-200 px-4 py-2 text-sm">
          <div className="text-amber-900">
            <span className="font-semibold">{selected.size}</span> selected
            {retryableSelected.length > 0 && (
              <span className="ml-2 text-amber-700/80">
                - {retryableSelected.length} retryable
              </span>
            )}
          </div>
          <div className="flex flex-wrap gap-2">
            <Button variant="ghost" size="sm" onClick={() => setSelected(new Set())}>Clear</Button>
            <Button
              variant="outline"
              size="sm"
              disabled={retryableSelected.length === 0}
              onClick={() => setBulkResendOpen(true)}
              title={retryableSelected.length === 0
                ? "Select failed / rejected messages to resend"
                : `Resend ${retryableSelected.length} message(s)`}
            >
              <RotateCcw className="h-4 w-4 mr-2" />
              Resend selected {retryableSelected.length > 0 ? `(${retryableSelected.length})` : ""}
            </Button>
            <Button variant="destructive" size="sm"
              onClick={() => setConfirmDelete({ ids: Array.from(selected), bulk: true })}>
              <Trash2 className="h-4 w-4 mr-2" /> Delete selected
            </Button>
          </div>
        </div>
      )}

      {/* List */}
      <div className="rounded-xl border bg-white overflow-hidden">
        <div className="hidden lg:grid grid-cols-12 gap-3 px-4 py-2 text-[11px] font-semibold uppercase tracking-wide text-slate-500 bg-slate-50 border-b items-center">
          <div className="col-span-1 flex items-center">
            <Checkbox checked={allSelectedOnPage} onCheckedChange={(v) => toggleSelectAll(!!v)} />
          </div>
          <div className="col-span-3">Recipient</div>
          <div className="col-span-3">Purpose - Event</div>
          <div className="col-span-2">Type / Template</div>
          <div className="col-span-2">Status</div>
          <div className="col-span-1 text-right">Actions</div>
        </div>

        {loading ? (
          <div className="p-4 space-y-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="flex gap-3">
                <Skeleton className="h-10 w-10 rounded-full shrink-0" />
                <div className="flex-1 space-y-2">
                  <Skeleton className="h-4 w-1/3" />
                  <Skeleton className="h-3 w-2/3" />
                </div>
              </div>
            ))}
          </div>
        ) : logs.length === 0 ? (
          <div className="px-4 py-14 text-center text-sm text-slate-500">
            No WhatsApp messages match your filters yet.
          </div>
        ) : (
          <ul className="divide-y">
            {logs.map((log) => {
              const hasImage = !!log.media_url;
              const displayName = (log.recipient_name && log.recipient_name.trim()) || log.recipient_phone;
              const initials = displayName.split(/\s+/).filter(Boolean).slice(0, 2)
                .map((p) => p[0]?.toUpperCase() ?? "").join("") || "?";
              const isSel = selected.has(log.id);
              const preview = log.summary || log.template_name || log.action || "";
              return (
                <li key={log.id} className={`px-3 sm:px-4 py-3 hover:bg-slate-50/60 ${log.deleted_at ? "opacity-60" : ""}`}>
                  {/* Mobile / tablet: stacked card layout */}
                  <div className="flex gap-3 lg:hidden">
                    <Checkbox className="mt-1" checked={isSel} onCheckedChange={(v) => toggleOne(log.id, !!v)} />
                    {hasImage ? (
                      <img src={log.media_url!} alt="" className="w-12 h-12 rounded-md object-cover bg-slate-100 shrink-0" loading="lazy" />
                    ) : (
                      <div className="w-10 h-10 rounded-full bg-slate-100 text-slate-600 text-xs font-semibold flex items-center justify-center shrink-0">{initials}</div>
                    )}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2">
                        <div className="min-w-0">
                          <div className="text-sm font-medium text-slate-900 truncate">{displayName}</div>
                          <div className="text-[11px] text-slate-500 truncate flex items-center gap-1">
                            <Phone className="h-3 w-3" />{log.recipient_phone}
                            <button onClick={() => copyPhone(log.recipient_phone)} className="ml-1 opacity-60 hover:opacity-100"><Copy className="h-3 w-3" /></button>
                          </div>
                        </div>
                        <StatusPill status={log.status} />
                      </div>
                      <div className="text-xs text-slate-600 truncate mt-1">
                        {PURPOSE_LABEL[log.message_purpose || ""] ?? (CATEGORY_LABEL[log.category] ?? log.category)}
                        {log.event_name_snapshot && <span className="text-slate-400"> - {log.event_name_snapshot}</span>}
                      </div>
                      {preview && (
                        <div className="text-[11px] text-slate-500 line-clamp-2 mt-1 break-words">{preview}</div>
                      )}
                      {log.failure_reason && (
                        <div className="text-[11px] text-rose-600 truncate mt-0.5">{log.failure_reason}</div>
                      )}
                      <div className="flex flex-wrap items-center gap-1 mt-1.5">
                        <AvailabilityBadge value={log.whatsapp_available} />
                        <FallbackBadge log={log} />
                        {log.deleted_at && <span className="text-[10px] rounded-full px-1.5 py-0.5 border bg-slate-100 text-slate-600 border-slate-200">deleted</span>}
                      </div>
                      <div className="flex items-center justify-between mt-2">
                        <span className="text-[11px] text-slate-400">
                          {log.updated_at ? getTimeAgo(log.updated_at) : "—"}
                          {log.retry_count > 0 && <> - Retry × {log.retry_count}</>}
                        </span>
                        <div className="flex gap-1.5">
                          <Button size="sm" variant="outline" className="h-7 px-2" onClick={() => onOpenLog(log.id)}>
                            <Eye className="h-3.5 w-3.5" />
                          </Button>
                          {log.retryable && (
                            <Button size="sm" variant="outline" className="h-7 px-2" onClick={() => setResendTarget(log)}>
                              <RotateCcw className="h-3.5 w-3.5" />
                            </Button>
                          )}
                          {log.deleted_at ? (
                            <Button size="sm" variant="outline" className="h-7 px-2" onClick={() => onRestore(log.id)} title="Restore (admin only)">
                              <ArchiveRestore className="h-3.5 w-3.5" />
                            </Button>
                          ) : (
                            <Button size="sm" variant="outline" className="h-7 px-2 text-rose-600" onClick={() => setConfirmDelete({ ids: [log.id], bulk: false })}>
                              <Trash2 className="h-3.5 w-3.5" />
                            </Button>
                          )}
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Desktop: 12-col grid */}
                  <div className="hidden lg:grid grid-cols-12 gap-3 items-center">
                    <div className="col-span-1">
                      <Checkbox checked={isSel} onCheckedChange={(v) => toggleOne(log.id, !!v)} />
                    </div>
                    <div className="col-span-3 min-w-0 flex items-center gap-3">
                      {hasImage ? (
                        <img src={log.media_url!} alt="" className="w-10 h-10 rounded-md object-cover bg-slate-100 shrink-0" loading="lazy" />
                      ) : (
                        <div className="w-10 h-10 rounded-full bg-slate-100 text-slate-600 text-xs font-semibold flex items-center justify-center shrink-0">{initials}</div>
                      )}
                      <div className="min-w-0">
                        <div className="text-sm font-medium text-slate-900 truncate">{displayName}</div>
                        <div className="text-[11px] text-slate-500 truncate flex items-center gap-1">
                          {log.recipient_phone}
                          <button onClick={() => copyPhone(log.recipient_phone)} className="opacity-60 hover:opacity-100"><Copy className="h-3 w-3" /></button>
                        </div>
                        <div className="flex flex-wrap items-center gap-1 mt-0.5">
                          <AvailabilityBadge value={log.whatsapp_available} />
                          <FallbackBadge log={log} />
                          {log.deleted_at && <span className="text-[10px] rounded-full px-1.5 py-0.5 border bg-slate-100 text-slate-600 border-slate-200">deleted</span>}
                        </div>
                      </div>
                    </div>
                    <div className="col-span-3 min-w-0">
                      <div className="text-sm text-slate-800 truncate">
                        {PURPOSE_LABEL[log.message_purpose || ""] ?? (CATEGORY_LABEL[log.category] ?? log.category)}
                      </div>
                      {log.event_name_snapshot && (
                        <div className="text-[11px] text-slate-500 truncate">Event: {log.event_name_snapshot}</div>
                      )}
                      {preview && (
                        <div className="text-[11px] text-slate-500 truncate">{preview}</div>
                      )}
                      {log.failure_reason && (
                        <div className="text-[11px] text-rose-600 truncate">{log.failure_reason}</div>
                      )}
                    </div>
                    <div className="col-span-2 min-w-0">
                      <div className="text-xs text-slate-700">{log.message_type}</div>
                      <div className="text-[11px] text-slate-500 truncate">{log.template_name || log.action || "—"}</div>
                    </div>
                    <div className="col-span-2">
                      <StatusPill status={log.status} />
                      <div className="text-[11px] text-slate-500 mt-1">
                        {log.updated_at ? getTimeAgo(log.updated_at) : "—"}
                        {log.retry_count > 0 && <> - ×{log.retry_count}</>}
                      </div>
                    </div>
                    <div className="col-span-1 flex justify-end gap-1.5">
                      <Button size="sm" variant="outline" onClick={() => onOpenLog(log.id)} title="Details">
                        <Eye className="h-3.5 w-3.5" />
                      </Button>
                      {log.retryable && (
                        <Button size="sm" variant="outline" onClick={() => setResendTarget(log)} title="Resend">
                          <RotateCcw className="h-3.5 w-3.5" />
                        </Button>
                      )}
                      {log.deleted_at ? (
                        <Button size="sm" variant="outline" onClick={() => onRestore(log.id)} title="Restore (admin only)">
                          <ArchiveRestore className="h-3.5 w-3.5" />
                        </Button>
                      ) : (
                        <Button size="sm" variant="outline" className="text-rose-600" onClick={() => setConfirmDelete({ ids: [log.id], bulk: false })} title="Delete">
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      )}
                    </div>
                  </div>
                </li>
              );
            })}
          </ul>
        )}

        {/* Pagination */}
        {pagination && pagination.total_pages > 1 && (
          <div className="flex items-center justify-between border-t px-4 py-3 text-sm">
            <div className="text-slate-500">
              Page {pagination.current_page} of {pagination.total_pages} - {pagination.total} total
            </div>
            <div className="flex gap-2">
              <Button variant="outline" size="sm" disabled={pagination.current_page <= 1}
                onClick={() => setFilters((f) => ({ ...f, page: (f.page ?? 1) - 1 }))}>
                <ChevronLeft className="h-4 w-4" />
              </Button>
              <Button variant="outline" size="sm" disabled={pagination.current_page >= pagination.total_pages}
                onClick={() => setFilters((f) => ({ ...f, page: (f.page ?? 1) + 1 }))}>
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </div>
        )}
      </div>

      {/* Detail dialog */}
      <Dialog open={!!activeLog} onOpenChange={(o) => !o && setActiveLog(null)}>
        <DialogContent className="w-[calc(100vw-1.5rem)] sm:w-auto max-w-[min(48rem,calc(100vw-1.5rem))] max-h-[90vh] overflow-y-auto overflow-x-hidden p-4 sm:p-6">
          <DialogHeader>
            <DialogTitle className="text-base sm:text-lg">WhatsApp message detail</DialogTitle>
          </DialogHeader>
          {activeLoading || !activeLog?.created_at ? (
            <div className="space-y-3">
              <Skeleton className="h-6 w-1/2" />
              <Skeleton className="h-24 w-full" />
              <Skeleton className="h-24 w-full" />
            </div>
          ) : (
            <div className="space-y-4 text-sm min-w-0">
              {activeLog.media_url && (
                <div className="rounded-lg border bg-slate-50 p-3 flex justify-center">
                  <img src={activeLog.media_url} alt="Card preview" className="max-h-72 w-auto max-w-full rounded-md shadow-sm object-contain" loading="lazy" />
                </div>
              )}

              <div className="rounded-lg border bg-white p-3">
                <div className="text-[11px] uppercase tracking-wide text-slate-500 mb-1">Recipient</div>
                <div className="text-sm font-medium text-slate-900 break-words">
                  {activeLog.recipient_name || activeLog.recipient_phone}
                </div>
                {activeLog.recipient_name && (
                  <div className="text-xs text-slate-500 break-words">{activeLog.recipient_phone}</div>
                )}
                <div className="flex flex-wrap items-center gap-1 mt-1.5">
                  <AvailabilityBadge value={activeLog.whatsapp_available} />
                  {activeLog.recipient_type && (
                    <span className="text-[10px] rounded-full px-1.5 py-0.5 border bg-slate-100 text-slate-600 border-slate-200">
                      {activeLog.recipient_type}
                    </span>
                  )}
                </div>
              </div>

              {activeLog.event_name_snapshot && (
                <div className="rounded-lg border bg-white p-3">
                  <div className="text-[11px] uppercase tracking-wide text-slate-500 mb-1">Event</div>
                  <div className="text-sm text-slate-900 break-words">{activeLog.event_name_snapshot}</div>
                  {activeLog.event_id && (
                    <div className="text-[11px] text-slate-500 break-all">{activeLog.event_id}</div>
                  )}
                </div>
              )}

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <Info label="Status" value={<StatusPill status={activeLog.status} />} />
                <Info label="Purpose" value={PURPOSE_LABEL[activeLog.message_purpose || ""] ?? activeLog.message_purpose ?? (CATEGORY_LABEL[activeLog.category] ?? activeLog.category)} />
                <Info label="Source module" value={activeLog.source_module ?? "—"} />
                <Info label="Message type" value={activeLog.message_type} />
                <Info label="Template" value={activeLog.template_name ?? activeLog.action ?? "—"} />
                <Info label="Language" value={activeLog.language ?? "—"} />
                <Info label="Provider message id" value={activeLog.provider_message_id ?? "—"} />
                <Info label="Retries" value={String(activeLog.retry_count ?? 0)} />
                <Info label="Queued" value={activeLog.queued_at ? new Date(activeLog.queued_at).toLocaleString() : "—"} />
                <Info label="Sent" value={activeLog.sent_at ? new Date(activeLog.sent_at).toLocaleString() : "—"} />
                <Info label="Delivered" value={activeLog.delivered_at ? new Date(activeLog.delivered_at).toLocaleString() : "—"} />
                <Info label="Read" value={activeLog.read_at ? new Date(activeLog.read_at).toLocaleString() : "—"} />
                {activeLog.failed_at && <Info label="Failed" value={new Date(activeLog.failed_at).toLocaleString()} />}
                {activeLog.fbtrace_id && <Info label="fbtrace_id" value={activeLog.fbtrace_id} />}
              </div>

              {(activeLog.failure_reason || activeLog.error_code || activeLog.error_message || activeLog.error_title) && (
                <div className="rounded-lg border border-rose-200 bg-rose-50 p-3">
                  <div className="text-xs font-semibold text-rose-800 uppercase tracking-wide mb-1">Failure details</div>
                  {activeLog.error_title && <div className="text-sm font-medium text-rose-900 break-words">{activeLog.error_title}</div>}
                  {activeLog.failure_reason && <div className="text-sm text-rose-900 break-words mt-0.5">{activeLog.failure_reason}</div>}
                  <div className="text-xs text-rose-700 mt-1 break-words">
                    {activeLog.error_code && <span className="mr-2">Code: <code>{activeLog.error_code}</code></span>}
                    {activeLog.error_message && <span className="break-all">Message: {activeLog.error_message}</span>}
                  </div>
                  {activeLog.error_details && (
                    <pre className="text-[11px] leading-snug text-rose-900 max-h-48 overflow-y-auto whitespace-pre-wrap break-all mt-2 bg-white/60 rounded p-2 border border-rose-200">
                      {JSON.stringify(activeLog.error_details, null, 2)}
                    </pre>
                  )}
                </div>
              )}

              {activeLog.fallback_attempted && (
                <div className="rounded-lg border border-amber-200 bg-amber-50 p-3">
                  <div className="text-xs font-semibold text-amber-900 uppercase tracking-wide mb-1">SMS fallback</div>
                  <div className="text-sm text-amber-900">
                    Channel: <span className="font-medium">{activeLog.fallback_channel ?? "sms"}</span>
                    {" - "}Status: <span className="font-medium">{activeLog.fallback_status ?? "—"}</span>
                  </div>
                  {activeLog.fallback_provider && (
                    <div className="text-xs text-amber-800 mt-0.5">Provider: {activeLog.fallback_provider}</div>
                  )}
                  {activeLog.fallback_message_id && (
                    <div className="text-xs text-amber-800 mt-0.5 break-all">Message id: {activeLog.fallback_message_id}</div>
                  )}
                  {activeLog.fallback_error && (
                    <div className="text-xs text-rose-700 mt-0.5 break-all">Error: {activeLog.fallback_error}</div>
                  )}
                </div>
              )}

              {activeLog.summary && (
                <Section title="Summary">
                  <div className="whitespace-pre-wrap break-words text-slate-800">{activeLog.summary}</div>
                </Section>
              )}

              <Section title="Request payload"><Json value={activeLog.request_payload} /></Section>
              <Section title="Response payload"><Json value={activeLog.response_payload} /></Section>
              {activeLog.webhook_payload && (
                <Section title="Latest webhook update"><Json value={activeLog.webhook_payload} /></Section>
              )}

              {activeLog.history && activeLog.history.length > 0 && (
                <Section title="Related attempts">
                  <ul className="space-y-1">
                    {activeLog.history.map((h) => (
                      <li key={h.id} className="flex items-center justify-between gap-2 text-xs border rounded px-2 py-1">
                        <span className="truncate">{new Date(h.created_at || "").toLocaleString()}</span>
                        <StatusPill status={h.status} />
                      </li>
                    ))}
                  </ul>
                </Section>
              )}
            </div>
          )}
          <DialogFooter className="flex-col-reverse sm:flex-row gap-2">
            {activeLog && !activeLog.deleted_at && (
              <Button variant="outline" className="text-rose-600"
                onClick={() => { if (activeLog) { setConfirmDelete({ ids: [activeLog.id], bulk: false }); setActiveLog(null); } }}>
                <Trash2 className="h-4 w-4 mr-2" /> Delete
              </Button>
            )}
            {activeLog?.retryable && (
              <Button variant="outline" onClick={() => { setResendTarget(activeLog); }}>
                <RotateCcw className="h-4 w-4 mr-2" /> Resend
              </Button>
            )}
            <Button onClick={() => setActiveLog(null)}>Close</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Resend confirm */}
      <AlertDialog open={!!resendTarget} onOpenChange={(o) => !o && setResendTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Resend this WhatsApp message?</AlertDialogTitle>
            <AlertDialogDescription>
              A brand-new send attempt will be queued to{" "}
              <span className="font-medium">{resendTarget?.recipient_name || resendTarget?.recipient_phone}</span>
              {" "}using the same purpose and content. The original failure record stays in your logs for audit history.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={resendBusy}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={onResend} disabled={resendBusy}>
              {resendBusy ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <RotateCcw className="h-4 w-4 mr-2" />}
              Yes, resend
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Bulk resend confirm */}
      <AlertDialog open={bulkResendOpen} onOpenChange={(o) => !o && setBulkResendOpen(false)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Resend {retryableSelected.length} WhatsApp message{retryableSelected.length === 1 ? "" : "s"}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              Each message is queued as its own background job, so resending many
              messages runs in parallel across workers — not one after another.
              Original failure records are kept for audit history.
              {selected.size > retryableSelected.length && (
                <>
                  {" "}
                  <span className="block mt-2 text-amber-700">
                    {selected.size - retryableSelected.length} selected log
                    {selected.size - retryableSelected.length === 1 ? "" : "s"} will
                    be skipped (not in a retryable state).
                  </span>
                </>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={bulkResendBusy}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={onBulkResend} disabled={bulkResendBusy || retryableSelected.length === 0}>
              {bulkResendBusy ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <RotateCcw className="h-4 w-4 mr-2" />}
              Yes, resend {retryableSelected.length}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Delete confirm */}
      <AlertDialog open={!!confirmDelete} onOpenChange={(o) => !o && setConfirmDelete(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirmDelete?.bulk ? `Delete ${confirmDelete.ids.length} logs?` : "Delete this log?"}
            </AlertDialogTitle>
            <AlertDialogDescription>
              The entry is hidden from your list immediately. Admins keep the full audit trail and can restore it later.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleteBusy}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={onDelete} disabled={deleteBusy} className="bg-rose-600 hover:bg-rose-700">
              {deleteBusy ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Trash2 className="h-4 w-4 mr-2" />}
              Yes, delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function Info({ label, value }: { label: string; value: any }) {
  return (
    <div className="text-xs">
      <div className="uppercase tracking-wide text-slate-500">{label}</div>
      <div className="text-sm text-slate-900 break-all">{value}</div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="text-[11px] uppercase tracking-wide text-slate-500 mb-1">{title}</div>
      <div className="rounded-lg border bg-slate-50 p-3">{children}</div>
    </div>
  );
}

function Json({ value }: { value: any }) {
  if (value === null || value === undefined) return <div className="text-slate-500 text-xs">No data</div>;
  let text = "";
  try { text = JSON.stringify(value, null, 2); } catch { text = String(value); }
  return (
    <pre className="text-[11px] leading-snug text-slate-800 max-h-72 overflow-y-auto whitespace-pre-wrap break-all">{text}</pre>
  );
}
