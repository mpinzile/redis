import { useEffect, useState, useCallback } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { ChevronLeft, ShieldCheck, CheckCircle2, XCircle, FileText, RefreshCw, ExternalLink } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { adminApi } from "@/lib/api/admin";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

const statusBadge = (s: string) => {
  if (s === "pending") return "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400";
  if (s === "verified") return "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400";
  if (s === "rejected") return "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400";
  return "bg-muted text-muted-foreground";
};

export default function AdminKycDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [detail, setDetail] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [actionDialog, setActionDialog] = useState<{ type: "approve" | "reject"; itemId: string; itemName: string } | null>(null);
  const [notes, setNotes] = useState("");
  const [actionLoading, setActionLoading] = useState(false);

  useAdminMeta(detail?.service_name ? `KYC - ${detail.service_name}` : "KYC Review");

  const load = useCallback(async () => {
    if (!id) return;
    const res = await adminApi.getKycDetail(id);
    if (res.success) setDetail(res.data);
    else toast.error("Failed to load KYC details");
    setLoading(false);
  }, [id]);

  useEffect(() => { load(); }, [load]);

  const handleAction = async () => {
    if (!actionDialog) return;
    setActionLoading(true);
    let res;
    if (actionDialog.type === "approve") {
      res = await adminApi.approveKycItem(actionDialog.itemId, notes);
    } else {
      if (!notes.trim()) { toast.error("Please provide rejection reason"); setActionLoading(false); return; }
      res = await adminApi.rejectKycItem(actionDialog.itemId, notes);
    }
    if (res.success) {
      const msg = actionDialog.type === "approve"
        ? res.data?.all_approved
          ? "✅ All KYC items approved · service is now verified!"
          : `KYC item approved (${res.data?.approved_count}/${res.data?.total_count} complete)`
        : "KYC item rejected";
      toast.success(msg);
      setActionDialog(null); setNotes("");
      load();
    } else toast.error(res.message || "Action failed");
    setActionLoading(false);
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-40 w-full rounded-xl" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  if (!detail) {
    return (
      <div className="text-center py-20 text-muted-foreground">
        <p>KYC submission not found.</p>
        <Button variant="outline" className="mt-4" onClick={() => navigate("/admin/kyc")}>Back to KYC</Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="sm" onClick={() => navigate("/admin/kyc")}>
          <ChevronLeft className="w-4 h-4 mr-1" /> KYC Verification
        </Button>
        <div className="flex-1" />
        <span className={cn("text-xs px-2.5 py-1 rounded-full font-medium capitalize", statusBadge(detail.status ?? ""))}>
          {detail.status}
        </span>
      </div>

      {/* Service + Owner */}
      <div className="bg-card border border-border rounded-xl p-5">
        <div className="flex items-start gap-4">
          <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
            <ShieldCheck className="w-5 h-5 text-primary" />
          </div>
          <div className="flex-1">
            <h1 className="text-lg font-bold text-foreground">{detail.service_name}</h1>
            <p className="text-sm text-muted-foreground mt-0.5">
              Owner: <span className="font-medium text-foreground">{detail.user?.name}</span>
              {detail.user?.email && <span className="ml-2 text-muted-foreground">({detail.user.email})</span>}
            </p>
          </div>
          {detail.service_id && (
            <Button variant="outline" size="sm" onClick={() => navigate(`/admin/services/${detail.service_id}`)}>
              <ExternalLink className="w-3.5 h-3.5 mr-1.5" /> View Service
            </Button>
          )}
        </div>
      </div>

      {/* KYC Items */}
      <div className="bg-card border border-border rounded-xl p-5">
        <h2 className="font-semibold text-foreground mb-4">KYC Requirements ({(detail.kyc_items || []).length})</h2>
        {(detail.kyc_items || []).length === 0 ? (
          <p className="text-muted-foreground text-sm text-center py-6">No KYC items found</p>
        ) : (
          <div className="space-y-2">
            {(detail.kyc_items || []).map((item: any) => (
              <div key={item.id} className="border border-border rounded-lg p-4 flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <p className="font-medium text-foreground">{item.name || "Unnamed KYC Item"}</p>
                  {item.description && <p className="text-xs text-muted-foreground mt-0.5">{item.description}</p>}
                  {item.remarks && (
                    <p className="text-xs text-muted-foreground mt-1 italic">Note: {item.remarks}</p>
                  )}
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <span className={cn("text-xs px-2 py-0.5 rounded-full font-medium capitalize", statusBadge(item.status))}>
                    {item.status}
                  </span>
                  {item.status === "pending" && (
                    <>
                      <Button variant="ghost" size="sm" className="text-primary hover:bg-primary/10 h-7 px-2"
                        onClick={() => setActionDialog({ type: "approve", itemId: item.id, itemName: item.name || "KYC item" })}>
                        <CheckCircle2 className="w-3.5 h-3.5" />
                      </Button>
                      <Button variant="ghost" size="sm" className="text-destructive hover:bg-destructive/10 h-7 px-2"
                        onClick={() => setActionDialog({ type: "reject", itemId: item.id, itemName: item.name || "KYC item" })}>
                        <XCircle className="w-3.5 h-3.5" />
                      </Button>
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Uploaded Files */}
      {(detail.files || []).length > 0 && (
        <div className="bg-card border border-border rounded-xl p-5">
          <h2 className="font-semibold text-foreground mb-4">Uploaded Documents ({detail.files.length})</h2>
          <div className="space-y-1.5">
            {(detail.files || []).map((f: any) => (
              <a key={f.id} href={f.file_url} target="_blank" rel="noopener noreferrer"
                className="flex items-center gap-2 text-primary hover:underline text-xs bg-muted rounded-lg px-4 py-2.5">
                <FileText className="w-4 h-4 shrink-0" />
                <span className="font-medium">{f.kyc_name || "Document"}</span>
                <span className="text-muted-foreground ml-auto">View ↗</span>
              </a>
            ))}
          </div>
        </div>
      )}

      {/* Action Dialog */}
      <Dialog open={!!actionDialog} onOpenChange={() => { setActionDialog(null); setNotes(""); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {actionDialog?.type === "approve" ? "Approve" : "Reject"} — {actionDialog?.itemName}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <Label>{actionDialog?.type === "approve" ? "Notes (optional)" : "Rejection reason (required)"}</Label>
            <Textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3} placeholder="Add notes..." />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setActionDialog(null); setNotes(""); }}>Cancel</Button>
            <Button onClick={handleAction} disabled={actionLoading} variant={actionDialog?.type === "reject" ? "destructive" : "default"}>
              {actionLoading ? "Processing..." : `Confirm ${actionDialog?.type === "approve" ? "Approval" : "Rejection"}`}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
