import { useEffect, useState, useCallback, useRef } from "react";
import { Trash2, Search, Loader2, Mail } from "lucide-react";
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

type Status = "all" | "pending" | "in_progress" | "completed" | "rejected";

interface DeletionRequest {
  id: string;
  user_id?: string | null;
  full_name: string;
  email: string;
  phone?: string;
  reason?: string;
  delete_scope: string;
  source?: string;
  status: "pending" | "in_progress" | "completed" | "rejected";
  admin_notes?: string;
  completed_at?: string;
  created_at?: string;
  updated_at?: string;
}

const STATUS_OPTIONS: { value: Status; label: string }[] = [
  { value: "all", label: "All" },
  { value: "pending", label: "Pending" },
  { value: "in_progress", label: "In progress" },
  { value: "completed", label: "Completed" },
  { value: "rejected", label: "Rejected" },
];

const STATUS_BADGE: Record<DeletionRequest["status"], string> = {
  pending: "bg-foreground text-background",
  in_progress: "bg-amber-500/15 text-amber-700 dark:text-amber-400",
  completed: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400",
  rejected: "bg-muted text-muted-foreground line-through",
};

const fmt = (iso?: string) => {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("en-GB", {
      day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit",
    });
  } catch { return iso; }
};

export default function AdminDeletionRequests() {
  useAdminMeta("Account Deletion Requests");

  const [items, setItems] = useState<DeletionRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState<Status>("all");
  const [q, setQ] = useState("");
  const [stats, setStats] = useState<{ total: number; pending: number; in_progress: number; completed: number; rejected: number } | null>(null);
  const [selected, setSelected] = useState<DeletionRequest | null>(null);
  const [notes, setNotes] = useState("");
  const [savingNotes, setSavingNotes] = useState(false);
  const initialLoad = useRef(true);

  const load = useCallback(async () => {
    if (initialLoad.current) setLoading(true);
    const [list, st] = await Promise.all([
      adminApi.getDeletionRequests({
        page: 1, limit: 100,
        status: status === "all" ? undefined : status,
        q: q.trim() || undefined,
      }),
      adminApi.getDeletionStats(),
    ]);
    if (list.success) setItems(Array.isArray(list.data) ? list.data : []);
    else if (initialLoad.current) toast.error("Failed to load deletion requests");
    if (st.success) setStats(st.data || null);
    setLoading(false);
    initialLoad.current = false;
  }, [status, q]);

  useEffect(() => { load(); }, [load]);

  const open = (r: DeletionRequest) => {
    setSelected(r);
    setNotes(r.admin_notes || "");
  };

  const updateStatus = async (id: string, s: DeletionRequest["status"]) => {
    const res = await adminApi.updateDeletionStatus(id, s);
    if (res.success) {
      toast.success(`Marked as ${s.replace("_", " ")}`);
      setSelected((cur) => (cur ? { ...cur, status: s } : cur));
      load();
    } else toast.error(res.message || "Update failed");
  };

  const saveNotes = async () => {
    if (!selected) return;
    setSavingNotes(true);
    const res = await adminApi.updateDeletionNotes(selected.id, notes);
    setSavingNotes(false);
    if (res.success) toast.success("Notes saved");
    else toast.error(res.message || "Failed to save notes");
  };

  const remove = async (id: string) => {
    if (!confirm("Delete this request record? (This does not undelete the user.)")) return;
    const res = await adminApi.deleteDeletionRequest(id);
    if (res.success) { toast.success("Removed"); setSelected(null); load(); }
    else toast.error(res.message || "Delete failed");
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-lg bg-foreground text-background flex items-center justify-center">
          <Trash2 className="w-5 h-5" />
        </div>
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Account Deletion Requests</h1>
          <p className="text-sm text-muted-foreground">
            Submissions from /data-deletion (web) and the mobile app's settings link.
          </p>
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {[
          { label: "Total", value: stats?.total ?? 0 },
          { label: "Pending", value: stats?.pending ?? 0, accent: true },
          { label: "In progress", value: stats?.in_progress ?? 0 },
          { label: "Completed", value: stats?.completed ?? 0 },
          { label: "Rejected", value: stats?.rejected ?? 0 },
        ].map((s) => (
          <div
            key={s.label}
            className={cn(
              "rounded-xl border border-border p-4",
              s.accent && (stats?.pending ?? 0) > 0 ? "bg-foreground text-background border-foreground" : "bg-card",
            )}
          >
            <div className="text-[10px] tracking-[0.2em] uppercase opacity-70 mb-1.5">{s.label}</div>
            <div className="text-2xl font-bold tabular-nums">{s.value}</div>
          </div>
        ))}
      </div>

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="flex-1 relative">
          <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <Input placeholder="Search name, email or phone…" value={q} onChange={(e) => setQ(e.target.value)} className="pl-9" />
        </div>
        <div className="flex gap-1.5 overflow-x-auto">
          {STATUS_OPTIONS.map((s) => (
            <button
              key={s.value}
              onClick={() => setStatus(s.value)}
              className={cn(
                "px-3 py-2 rounded-lg text-xs font-medium whitespace-nowrap transition",
                status === s.value ? "bg-foreground text-background" : "bg-muted text-muted-foreground hover:bg-muted/70",
              )}
            >
              {s.label}
            </button>
          ))}
        </div>
      </div>

      <div className="rounded-xl border border-border bg-card overflow-hidden">
        {loading ? (
          <div className="p-4 space-y-2">{[...Array(5)].map((_, i) => <Skeleton key={i} className="h-16 w-full" />)}</div>
        ) : items.length === 0 ? (
          <div className="p-12 text-center text-muted-foreground">
            <Trash2 className="w-10 h-10 mx-auto mb-3 opacity-40" />
            <div className="font-medium">No deletion requests</div>
            <div className="text-xs mt-1">Submissions from the public form will appear here.</div>
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {items.map((r) => (
              <li key={r.id}>
                <button onClick={() => open(r)} className="w-full p-4 text-left hover:bg-muted/40 transition flex items-center gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-0.5">
                      <span className="font-medium truncate">{r.full_name}</span>
                      <span className={cn("text-[10px] px-2 py-0.5 rounded-full font-medium uppercase tracking-wider", STATUS_BADGE[r.status])}>
                        {r.status.replace("_", " ")}
                      </span>
                    </div>
                    <div className="text-xs text-muted-foreground truncate">
                      {r.email}{r.phone ? ` - ${r.phone}` : ""} - {r.delete_scope === "data_only" ? "Data only" : "Account + data"}
                    </div>
                  </div>
                  <div className="text-xs text-muted-foreground whitespace-nowrap">{fmt(r.created_at)}</div>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <Dialog open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>{selected?.full_name}</DialogTitle>
          </DialogHeader>
          {selected && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-3 text-sm">
                <div><div className="text-muted-foreground text-xs">Email</div><div className="break-all">{selected.email}</div></div>
                <div><div className="text-muted-foreground text-xs">Phone</div><div>{selected.phone || "—"}</div></div>
                <div><div className="text-muted-foreground text-xs">Scope</div><div>{selected.delete_scope}</div></div>
                <div><div className="text-muted-foreground text-xs">Source</div><div>{selected.source || "—"}</div></div>
                <div><div className="text-muted-foreground text-xs">User ID</div><div className="font-mono text-xs break-all">{selected.user_id || "anonymous"}</div></div>
                <div><div className="text-muted-foreground text-xs">Submitted</div><div>{fmt(selected.created_at)}</div></div>
              </div>
              {selected.reason && (
                <div>
                  <div className="text-muted-foreground text-xs mb-1">Reason</div>
                  <div className="rounded-lg border border-border bg-muted/40 p-3 text-sm whitespace-pre-wrap">{selected.reason}</div>
                </div>
              )}
              <div>
                <div className="text-muted-foreground text-xs mb-1">Internal notes</div>
                <Textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={4} placeholder="Track what was deleted, when, and by whom…" />
                <div className="flex justify-end mt-2">
                  <Button size="sm" variant="outline" onClick={saveNotes} disabled={savingNotes}>
                    {savingNotes ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : "Save notes"}
                  </Button>
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" onClick={() => updateStatus(selected.id, "in_progress")}>Mark in progress</Button>
                <Button size="sm" variant="outline" onClick={() => updateStatus(selected.id, "completed")}>Mark completed</Button>
                <Button size="sm" variant="outline" onClick={() => updateStatus(selected.id, "rejected")}>Reject</Button>
                <a href={`mailto:${selected.email}?subject=${encodeURIComponent("Your Nuru data deletion request")}`} className="inline-flex">
                  <Button size="sm" variant="outline"><Mail className="w-3.5 h-3.5 mr-1.5" /> Email user</Button>
                </a>
              </div>
            </div>
          )}
          <DialogFooter className="flex justify-between items-center">
            <Button variant="ghost" size="sm" className="text-destructive" onClick={() => selected && remove(selected.id)}>
              <Trash2 className="w-3.5 h-3.5 mr-1.5" /> Delete record
            </Button>
            <Button size="sm" onClick={() => setSelected(null)}>Close</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}