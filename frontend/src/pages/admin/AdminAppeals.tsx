import { useEffect, useState, useCallback, useRef } from "react";
import { AlertTriangle, Search, ChevronLeft, ChevronRight, Eye, CheckCircle2, XCircle, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { AdminTableSkeleton } from "@/components/ui/AdminTableSkeleton";
import { adminApi } from "@/lib/api/admin";
import { adminCaches } from "@/lib/api/adminCache";
import { usePolling } from "@/hooks/usePolling";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog";

const statusTabs = [
  { label: "All", value: "" },
  { label: "Pending", value: "pending" },
  { label: "Approved", value: "approved" },
  { label: "Rejected", value: "rejected" },
];

const statusBadge = (s: string) => {
  if (s === "pending") return "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400";
  if (s === "approved") return "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400";
  if (s === "rejected") return "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400";
  return "bg-muted text-muted-foreground";
};

export default function AdminAppeals() {
  useAdminMeta("Content Appeals");
  const [items, setItems] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const initialLoad = useRef(true);
  const [status, setStatus] = useState("pending");
  const [page, setPage] = useState(1);
  const [pagination, setPagination] = useState<any>(null);
  const [reviewTarget, setReviewTarget] = useState<any | null>(null);
  const [notes, setNotes] = useState("");
  const [reviewing, setReviewing] = useState(false);
  const [decision, setDecision] = useState<"approved" | "rejected" | null>(null);

  const load = useCallback(async () => {
    if (initialLoad.current) setLoading(true);
    const res = await adminApi.getAppeals({ status: status || undefined, page, limit: 20 });
    if (res.success) {
      const data = Array.isArray(res.data) ? res.data : [];
      setItems(data);
      setPagination((res as any).pagination ?? null);
    } else if (initialLoad.current) toast.error("Failed to load appeals");
    setLoading(false);
    initialLoad.current = false;
  }, [status, page]);

  useEffect(() => { initialLoad.current = true; load(); }, [load]);
  usePolling(load);

  const handleReview = async () => {
    if (!reviewTarget || !decision) return;
    if (decision === "rejected" && !notes.trim()) {
      toast.error("Please provide a rejection reason");
      return;
    }
    setReviewing(true);
    const res = await adminApi.reviewAppeal(reviewTarget.id, decision, notes.trim() || undefined);
    if (res.success) {
      toast.success(decision === "approved" ? "Appeal approved · content restored" : "Appeal rejected");
      setReviewTarget(null); setNotes(""); setDecision(null);
      load();
    } else toast.error(res.message || "Failed");
    setReviewing(false);
  };

  return (
    <div className="space-y-6">
      {/* Review dialog */}
      <Dialog open={!!reviewTarget} onOpenChange={open => { if (!open) { setReviewTarget(null); setNotes(""); setDecision(null); } }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Review Appeal</DialogTitle>
            <DialogDescription>
              {reviewTarget?.user?.name} is appealing the removal of their {reviewTarget?.content_type || "content"}.
            </DialogDescription>
          </DialogHeader>

          {/* Removed content preview */}
          {reviewTarget?.media_url && (
            <div className="w-full h-40 rounded-lg overflow-hidden bg-muted">
              <img src={reviewTarget.media_url} alt="Appealed content" className="w-full h-full object-contain" />
            </div>
          )}
          {reviewTarget?.caption && (
            <p className="text-sm text-muted-foreground italic border-l-2 border-border pl-3">"{reviewTarget.caption}"</p>
          )}

          <div className="p-3 rounded-lg bg-muted/50 border border-border text-sm">
            <p className="font-medium text-foreground mb-1">User's appeal reason:</p>
            <p className="text-muted-foreground">{reviewTarget?.appeal_reason || "No reason provided"}</p>
          </div>

          <div className="flex gap-2">
            <Button
              variant={decision === "approved" ? "default" : "outline"}
              className={cn("flex-1", decision === "approved" && "bg-green-600 hover:bg-green-700 text-white")}
              onClick={() => setDecision("approved")}
            >
              <CheckCircle2 className="w-4 h-4 mr-1.5" /> Approve (Restore)
            </Button>
            <Button
              variant={decision === "rejected" ? "destructive" : "outline"}
              className="flex-1"
              onClick={() => setDecision("rejected")}
            >
              <XCircle className="w-4 h-4 mr-1.5" /> Reject Appeal
            </Button>
          </div>

          {decision && (
            <div>
              <label className="text-sm font-medium text-foreground">
                {decision === "approved" ? "Notes to user (optional)" : "Rejection reason (required)"}
              </label>
              <Textarea
                className="mt-1"
                rows={3}
                value={notes}
                onChange={e => setNotes(e.target.value)}
                placeholder={decision === "approved" ? "Explain why the appeal was accepted..." : "Explain why the appeal was denied..."}
              />
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => { setReviewTarget(null); setNotes(""); setDecision(null); }}>Cancel</Button>
            <Button onClick={handleReview} disabled={!decision || reviewing}>
              {reviewing ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}
              Submit Decision
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-xl font-bold text-foreground">Content Appeals</h2>
          <p className="text-sm text-muted-foreground mt-0.5">Review user appeals for removed posts and moments</p>
        </div>
      </div>

      <div className="flex gap-1 bg-muted p-1 rounded-lg w-fit">
        {statusTabs.map(tab => (
          <button key={tab.value} onClick={() => { setStatus(tab.value); setPage(1); }}
            className={cn("px-3 py-1.5 rounded-md text-sm font-medium transition-colors",
              status === tab.value ? "bg-card text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground")}>
            {tab.label}
          </button>
        ))}
      </div>

      {loading ? (
        <AdminTableSkeleton columns={6} rows={8} />
      ) : items.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <AlertTriangle className="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p>No appeals found</p>
        </div>
      ) : (
        <div className="bg-card border border-border rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-muted/50">
              <tr>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">User</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Content</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Appeal Reason</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Status</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Submitted</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {items.map((appeal: any) => (
                <tr key={appeal.id} className="hover:bg-muted/30 transition-colors">
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <div className="w-7 h-7 rounded-full bg-muted flex items-center justify-center text-xs font-bold overflow-hidden shrink-0">
                        {appeal.user?.avatar ? <img src={appeal.user.avatar} className="w-full h-full object-cover" alt="" /> : appeal.user?.name?.[0]}
                      </div>
                      <div>
                        <div className="font-medium text-foreground text-xs">{appeal.user?.name || "—"}</div>
                        <div className="text-xs text-muted-foreground">@{appeal.user?.username}</div>
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-xs capitalize px-2 py-0.5 rounded-full bg-muted">{appeal.content_type || "post"}</span>
                  </td>
                  <td className="px-4 py-3 text-muted-foreground max-w-xs truncate text-xs">{appeal.appeal_reason || <em>No reason</em>}</td>
                  <td className="px-4 py-3">
                    <span className={cn("text-xs px-2 py-0.5 rounded-full font-medium capitalize", statusBadge(appeal.status))}>{appeal.status}</span>
                  </td>
                  <td className="px-4 py-3 text-xs text-muted-foreground">
                    {appeal.created_at ? new Date(appeal.created_at).toLocaleDateString() : "—"}
                  </td>
                  <td className="px-4 py-3">
                    {appeal.status === "pending" && (
                      <Button variant="ghost" size="sm" onClick={() => { setReviewTarget(appeal); setDecision(null); setNotes(""); }}>
                        <Eye className="w-3.5 h-3.5 mr-1" /> Review
                      </Button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {pagination && pagination.total_pages > 1 && (
        <div className="flex justify-center items-center gap-2">
          <Button variant="outline" size="icon" onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}><ChevronLeft className="w-4 h-4" /></Button>
          <span className="text-sm text-muted-foreground">Page {page} of {pagination.total_pages}</span>
          <Button variant="outline" size="icon" onClick={() => setPage(p => p + 1)} disabled={page >= pagination.total_pages}><ChevronRight className="w-4 h-4" /></Button>
        </div>
      )}
    </div>
  );
}
