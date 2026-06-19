import { useEffect, useState, useCallback, useRef } from "react";
import { Inbox, Search, Mail, Trash2, Archive, Reply, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { adminApi } from "@/lib/api/admin";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";

type Status = "all" | "new" | "read" | "replied" | "archived";

interface ContactMessage {
  id: string;
  first_name: string;
  last_name: string;
  email: string;
  phone?: string;
  subject?: string;
  message: string;
  source_page?: string;
  source_host?: string;
  status: "new" | "read" | "replied" | "archived";
  is_archived: boolean;
  admin_notes?: string;
  created_at?: string;
  updated_at?: string;
}

const STATUS_OPTIONS: { value: Status; label: string }[] = [
  { value: "all", label: "All" },
  { value: "new", label: "New" },
  { value: "read", label: "Read" },
  { value: "replied", label: "Replied" },
  { value: "archived", label: "Archived" },
];

const STATUS_BADGE: Record<ContactMessage["status"], string> = {
  new: "bg-foreground text-background",
  read: "bg-muted text-foreground",
  replied: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400",
  archived: "bg-muted/60 text-muted-foreground line-through",
};

const formatDate = (iso?: string) => {
  if (!iso) return "—";
  try {
    const d = new Date(iso);
    return d.toLocaleString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
};

export default function AdminContactMessages() {
  useAdminMeta("Contact Messages");
  const { confirm, ConfirmDialog } = useConfirmDialog();


  const [items, setItems] = useState<ContactMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState<Status>("all");
  const [q, setQ] = useState("");
  const [stats, setStats] = useState<{ total: number; new: number; read: number; replied: number; archived: number } | null>(null);
  const [selected, setSelected] = useState<ContactMessage | null>(null);
  const [notes, setNotes] = useState("");
  const [savingNotes, setSavingNotes] = useState(false);
  const initialLoad = useRef(true);

  const load = useCallback(async () => {
    if (initialLoad.current) setLoading(true);
    const [list, st] = await Promise.all([
      adminApi.getContactMessages({
        page: 1,
        limit: 100,
        status: status === "all" ? undefined : status,
        q: q.trim() || undefined,
      }),
      adminApi.getContactStats(),
    ]);
    if (list.success) setItems(Array.isArray(list.data) ? list.data : []);
    else if (initialLoad.current) toast.error("Failed to load contact messages");
    if (st.success) setStats(st.data || null);
    setLoading(false);
    initialLoad.current = false;
  }, [status, q]);

  useEffect(() => {
    load();
  }, [load]);

  const open = async (m: ContactMessage) => {
    const res = await adminApi.getContactMessage(m.id);
    const detail: ContactMessage = res.success ? res.data : m;
    setSelected(detail);
    setNotes(detail.admin_notes || "");
    // Refresh list to reflect "new → read" auto-transition
    if (m.status === "new") load();
  };

  const setMsgStatus = async (id: string, newStatus: ContactMessage["status"]) => {
    const res = await adminApi.updateContactStatus(id, newStatus);
    if (res.success) {
      toast.success(`Marked as ${newStatus}`);
      setSelected((s) => (s ? { ...s, status: newStatus } : s));
      load();
    } else toast.error(res.message || "Update failed");
  };

  const saveNotes = async () => {
    if (!selected) return;
    setSavingNotes(true);
    const res = await adminApi.updateContactNotes(selected.id, notes);
    setSavingNotes(false);
    if (res.success) toast.success("Notes saved");
    else toast.error(res.message || "Failed to save notes");
  };

  const remove = async (id: string) => {
    const ok = await confirm({
      title: "Delete this message?",
      description: "The contact message will be permanently removed. This cannot be undone.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    const res = await adminApi.deleteContactMessage(id);
    if (res.success) {
      toast.success("Message deleted");
      setSelected(null);
      load();
    } else toast.error(res.message || "Delete failed");
  };

  return (
    <div className="space-y-6">
      <ConfirmDialog />
      {/* Header */}
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-lg bg-foreground text-background flex items-center justify-center">
          <Inbox className="w-5 h-5" />
        </div>
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Contact Messages</h1>
          <p className="text-sm text-muted-foreground">
            Submissions from the public Contact form on nuru.tz / nuru.ke.
          </p>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {[
          { label: "Total", value: stats?.total ?? 0 },
          { label: "New", value: stats?.new ?? 0, accent: true },
          { label: "Read", value: stats?.read ?? 0 },
          { label: "Replied", value: stats?.replied ?? 0 },
          { label: "Archived", value: stats?.archived ?? 0 },
        ].map((s) => (
          <div
            key={s.label}
            className={cn(
              "rounded-xl border border-border p-4",
              s.accent && (stats?.new ?? 0) > 0 ? "bg-foreground text-background border-foreground" : "bg-card"
            )}
          >
            <div className="text-[10px] tracking-[0.2em] uppercase opacity-70 mb-1.5">{s.label}</div>
            <div className="text-2xl font-bold tabular-nums">{s.value}</div>
          </div>
        ))}
      </div>

      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="flex-1 relative">
          <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search name, email, subject or message…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            className="pl-9"
          />
        </div>
        <div className="flex gap-1.5 overflow-x-auto">
          {STATUS_OPTIONS.map((s) => (
            <button
              key={s.value}
              onClick={() => setStatus(s.value)}
              className={cn(
                "px-3 py-2 rounded-lg text-xs font-medium whitespace-nowrap transition",
                status === s.value
                  ? "bg-foreground text-background"
                  : "bg-muted text-muted-foreground hover:bg-muted/70"
              )}
            >
              {s.label}
            </button>
          ))}
        </div>
      </div>

      {/* List */}
      <div className="rounded-xl border border-border bg-card overflow-hidden">
        {loading ? (
          <div className="p-4 space-y-2">
            {[...Array(5)].map((_, i) => <Skeleton key={i} className="h-16 w-full" />)}
          </div>
        ) : items.length === 0 ? (
          <div className="p-12 text-center text-muted-foreground">
            <Mail className="w-10 h-10 mx-auto mb-3 opacity-40" />
            <div className="font-medium">No messages here yet</div>
            <div className="text-xs mt-1">Submissions from the contact form will appear here.</div>
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {items.map((m) => (
              <li key={m.id}>
                <button
                  onClick={() => open(m)}
                  className="w-full text-left px-4 py-4 hover:bg-muted/40 transition flex items-start gap-4"
                >
                  <span
                    className={cn(
                      "px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider shrink-0",
                      STATUS_BADGE[m.status]
                    )}
                  >
                    {m.status}
                  </span>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-baseline gap-2 flex-wrap">
                      <span className="font-semibold text-foreground truncate">
                        {m.first_name} {m.last_name}
                      </span>
                      <span className="text-xs text-muted-foreground truncate">{m.email}</span>
                    </div>
                    {m.subject && (
                      <div className="text-sm font-medium text-foreground/90 mt-0.5 truncate">
                        {m.subject}
                      </div>
                    )}
                    <p className="text-sm text-muted-foreground mt-1 line-clamp-2">{m.message}</p>
                    <div className="flex items-center gap-3 mt-2 text-[11px] text-muted-foreground">
                      <span>{formatDate(m.created_at)}</span>
                      {m.source_host && <span>· {m.source_host}</span>}
                      {m.phone && <span>· {m.phone}</span>}
                    </div>
                  </div>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      {/* Detail dialog */}
      <Dialog open={!!selected} onOpenChange={(o) => { if (!o) setSelected(null); }}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-start justify-between gap-4">
              <span className="flex-1">
                {selected?.subject || `${selected?.first_name} ${selected?.last_name}`}
              </span>
              {selected && (
                <span
                  className={cn(
                    "px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider",
                    STATUS_BADGE[selected.status]
                  )}
                >
                  {selected.status}
                </span>
              )}
            </DialogTitle>
          </DialogHeader>

          {selected && (
            <div className="space-y-5">
              {/* Sender meta */}
              <div className="rounded-lg border border-border p-4 bg-muted/30 space-y-1.5 text-sm">
                <div><span className="text-muted-foreground">From:</span> <strong>{selected.first_name} {selected.last_name}</strong></div>
                <div><span className="text-muted-foreground">Email:</span> <a href={`mailto:${selected.email}`} className="text-primary hover:underline">{selected.email}</a></div>
                {selected.phone && <div><span className="text-muted-foreground">Phone:</span> {selected.phone}</div>}
                {selected.source_host && <div><span className="text-muted-foreground">Submitted from:</span> {selected.source_host}{selected.source_page ? selected.source_page : ""}</div>}
                <div><span className="text-muted-foreground">Received:</span> {formatDate(selected.created_at)}</div>
              </div>

              {/* Message */}
              <div>
                <div className="text-[10px] tracking-[0.22em] uppercase text-muted-foreground mb-2">Message</div>
                <div className="rounded-lg border border-border p-4 bg-card whitespace-pre-wrap text-sm leading-relaxed">
                  {selected.message}
                </div>
              </div>

              {/* Internal notes */}
              <div>
                <div className="text-[10px] tracking-[0.22em] uppercase text-muted-foreground mb-2">
                  Internal notes (visible to admins only)
                </div>
                <Textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  rows={3}
                  placeholder="Add a note for the team…"
                />
                <div className="mt-2 flex justify-end">
                  <Button size="sm" variant="outline" onClick={saveNotes} disabled={savingNotes}>
                    {savingNotes && <Loader2 className="w-3.5 h-3.5 mr-1.5 animate-spin" />}
                    Save notes
                  </Button>
                </div>
              </div>
            </div>
          )}

          <DialogFooter className="flex-wrap gap-2 justify-between sm:justify-between">
            <div className="flex flex-wrap gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={() => selected && setMsgStatus(selected.id, "replied")}
                disabled={!selected || selected.status === "replied"}
              >
                <Reply className="w-3.5 h-3.5 mr-1.5" /> Mark as replied
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => selected && setMsgStatus(selected.id, "archived")}
                disabled={!selected || selected.status === "archived"}
              >
                <Archive className="w-3.5 h-3.5 mr-1.5" /> Archive
              </Button>
              {selected && (
                <a
                  href={`mailto:${selected.email}?subject=Re:%20${encodeURIComponent(selected.subject || "Your Nuru enquiry")}`}
                  className="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-md bg-foreground text-background hover:opacity-90"
                >
                  <Mail className="w-3.5 h-3.5" /> Reply by email
                </a>
              )}
            </div>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => selected && remove(selected.id)}
              className="text-destructive hover:text-destructive hover:bg-destructive/10"
            >
              <Trash2 className="w-3.5 h-3.5 mr-1.5" /> Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
