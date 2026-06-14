import { useEffect, useState, useCallback, useRef } from "react";
import {
  FileCheck, Plus, ChevronDown, Users, Clock, Search,
  Loader2, Eye, Shield, FileText,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { adminApi } from "@/lib/api/admin";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

const AGREEMENT_TYPES = [
  { value: "vendor_agreement", label: "Vendor Agreement" },
  { value: "organiser_agreement", label: "Organiser Agreement" },
];

export default function AdminAgreements() {
  useAdminMeta("Agreements");

  // Versions state
  const [versions, setVersions] = useState<any[]>([]);
  const [loadingVersions, setLoadingVersions] = useState(true);
  const [filterType, setFilterType] = useState<string>("all");

  // Acceptances state
  const [acceptances, setAcceptances] = useState<any[]>([]);
  const [loadingAcceptances, setLoadingAcceptances] = useState(true);
  const [accFilterType, setAccFilterType] = useState<string>("all");
  const [accFilterVersion, setAccFilterVersion] = useState<string>("all");
  const [accSearch, setAccSearch] = useState("");
  const [accPage, setAccPage] = useState(1);
  const [accPagination, setAccPagination] = useState<any>(null);

  // Create dialog
  const [createOpen, setCreateOpen] = useState(false);
  const [createForm, setCreateForm] = useState({
    agreement_type: "vendor_agreement",
    summary: "",
    document_path: "/docs/vendor-agreement.md",
  });
  const [creating, setCreating] = useState(false);

  // Acceptance detail
  const [detailOpen, setDetailOpen] = useState(false);
  const [detailItem, setDetailItem] = useState<any>(null);

  const loadVersions = useCallback(async () => {
    setLoadingVersions(true);
    const params: any = {};
    if (filterType !== "all") params.agreement_type = filterType;
    const res = await adminApi.getAgreementVersions(params);
    if (res.success) setVersions(Array.isArray(res.data) ? res.data : []);
    setLoadingVersions(false);
  }, [filterType]);

  const loadAcceptances = useCallback(async () => {
    setLoadingAcceptances(true);
    const params: any = { page: accPage, limit: 20 };
    if (accFilterType !== "all") params.agreement_type = accFilterType;
    if (accFilterVersion !== "all") params.version = parseInt(accFilterVersion);
    if (accSearch.trim()) params.q = accSearch.trim();
    const res = await adminApi.getAgreementAcceptances(params);
    if (res.success) {
      const d = res.data;
      if (d && typeof d === "object" && !Array.isArray(d) && "items" in d) {
        setAcceptances(Array.isArray((d as any).items) ? (d as any).items : []);
        setAccPagination((d as any).pagination ?? null);
      } else {
        setAcceptances(Array.isArray(d) ? d : []);
        setAccPagination((res as any).pagination ?? null);
      }
    }
    setLoadingAcceptances(false);
  }, [accFilterType, accFilterVersion, accSearch, accPage]);

  useEffect(() => { loadVersions(); }, [loadVersions]);
  useEffect(() => { loadAcceptances(); }, [loadAcceptances]);

  const handleCreate = async () => {
    if (!createForm.agreement_type || !createForm.document_path.trim()) {
      toast.error("Agreement type and document path are required");
      return;
    }
    setCreating(true);
    const res = await adminApi.createAgreementVersion({
      agreement_type: createForm.agreement_type,
      summary: createForm.summary.trim() || undefined,
      document_path: createForm.document_path.trim(),
    });
    if (res.success) {
      toast.success(`Version ${res.data?.version} published`);
      setCreateOpen(false);
      setCreateForm({ agreement_type: "vendor_agreement", summary: "", document_path: "/docs/vendor-agreement.md" });
      loadVersions();
    } else {
      toast.error(res.message || "Failed to publish");
    }
    setCreating(false);
  };

  const latestVersions = AGREEMENT_TYPES.map((t) => {
    const filtered = versions.filter((v) => v.agreement_type === t.value);
    return { ...t, latest: filtered[0], total: filtered.length };
  });

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
            <FileCheck className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-foreground">Legal Agreements</h1>
            <p className="text-sm text-muted-foreground">Manage versions and track user acceptances</p>
          </div>
        </div>
        <Button onClick={() => setCreateOpen(true)} size="sm">
          <Plus className="w-4 h-4 mr-1.5" /> Publish New Version
        </Button>
      </div>

      {/* Overview cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {latestVersions.map((t) => (
          <div
            key={t.value}
            className="rounded-xl border border-border bg-card p-5 space-y-3"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2.5">
                <Shield className="w-4 h-4 text-primary" />
                <span className="font-semibold text-sm text-foreground">{t.label}</span>
              </div>
              {t.latest && (
                <Badge variant="secondary" className="text-xs">
                  v{t.latest.version}
                </Badge>
              )}
            </div>
            {t.latest ? (
              <>
                <p className="text-xs text-muted-foreground line-clamp-2">
                  {t.latest.summary || "No summary provided"}
                </p>
                <div className="flex items-center gap-4 text-xs text-muted-foreground">
                  <span className="flex items-center gap-1">
                    <Users className="w-3.5 h-3.5" />
                    {t.latest.acceptance_count} accepted
                  </span>
                  <span className="flex items-center gap-1">
                    <Clock className="w-3.5 h-3.5" />
                    {t.latest.published_at ? new Date(t.latest.published_at).toLocaleDateString() : "—"}
                  </span>
                </div>
              </>
            ) : (
              <p className="text-xs text-muted-foreground italic">No versions published yet</p>
            )}
          </div>
        ))}
      </div>

      {/* Tabs */}
      <Tabs defaultValue="versions">
        <TabsList>
          <TabsTrigger value="versions">Versions</TabsTrigger>
          <TabsTrigger value="acceptances">User Acceptances</TabsTrigger>
        </TabsList>

        {/* VERSIONS TAB */}
        <TabsContent value="versions" className="space-y-4 mt-4">
          <div className="flex items-center gap-3">
            <Select value={filterType} onValueChange={setFilterType}>
              <SelectTrigger className="w-52">
                <SelectValue placeholder="All types" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Types</SelectItem>
                {AGREEMENT_TYPES.map((t) => (
                  <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {loadingVersions ? (
            <div className="space-y-3">
              {[1, 2, 3].map((i) => <Skeleton key={i} className="h-16 rounded-xl" />)}
            </div>
          ) : versions.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <FileText className="w-10 h-10 mx-auto mb-3 opacity-40" />
              <p className="text-sm">No agreement versions found</p>
            </div>
          ) : (
            <div className="space-y-2">
              {versions.map((v) => (
                <div
                  key={v.id}
                  className="flex items-center gap-4 rounded-xl border border-border bg-card px-5 py-3.5 hover:bg-muted/30 transition-colors"
                >
                  <div className="w-10 h-10 rounded-lg bg-primary/8 flex items-center justify-center shrink-0">
                    <span className="text-sm font-bold text-primary">v{v.version}</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-sm text-foreground">
                        {AGREEMENT_TYPES.find((t) => t.value === v.agreement_type)?.label || v.agreement_type}
                      </span>
                      {v.version === (latestVersions.find((l) => l.value === v.agreement_type)?.latest?.version) && (
                        <Badge className="text-[10px] px-1.5 py-0">Latest</Badge>
                      )}
                    </div>
                    <p className="text-xs text-muted-foreground truncate mt-0.5">
                      {v.summary || "No summary"}
                    </p>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-muted-foreground shrink-0">
                    <span className="flex items-center gap-1">
                      <Users className="w-3.5 h-3.5" /> {v.acceptance_count}
                    </span>
                    <span>{v.published_at ? new Date(v.published_at).toLocaleDateString() : "—"}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </TabsContent>

        {/* ACCEPTANCES TAB */}
        <TabsContent value="acceptances" className="space-y-4 mt-4">
          <div className="flex flex-wrap items-center gap-3">
            <Select value={accFilterType} onValueChange={(v) => { setAccFilterType(v); setAccPage(1); }}>
              <SelectTrigger className="w-48">
                <SelectValue placeholder="All types" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Types</SelectItem>
                {AGREEMENT_TYPES.map((t) => (
                  <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="relative flex-1 min-w-[200px] max-w-xs">
              <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <Input
                placeholder="Search users..."
                value={accSearch}
                onChange={(e) => { setAccSearch(e.target.value); setAccPage(1); }}
                className="pl-9"
              />
            </div>
          </div>

          {loadingAcceptances ? (
            <div className="space-y-3">
              {[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-14 rounded-xl" />)}
            </div>
          ) : acceptances.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <Users className="w-10 h-10 mx-auto mb-3 opacity-40" />
              <p className="text-sm">No acceptances found</p>
            </div>
          ) : (
            <>
              {/* Table header */}
              <div className="hidden sm:grid grid-cols-[1fr_140px_60px_140px_40px] gap-3 px-5 text-xs font-medium text-muted-foreground uppercase tracking-wider">
                <span>User</span>
                <span>Agreement</span>
                <span>Ver.</span>
                <span>Accepted At</span>
                <span></span>
              </div>

              <div className="space-y-1.5">
                {acceptances.map((a) => (
                  <div
                    key={a.id}
                    className="grid grid-cols-1 sm:grid-cols-[1fr_140px_60px_140px_40px] gap-3 items-center rounded-xl border border-border bg-card px-5 py-3 hover:bg-muted/30 transition-colors"
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      {a.user_avatar ? (
                        <img src={a.user_avatar} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" />
                      ) : (
                        <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center text-xs font-bold text-primary shrink-0">
                          {a.user_name?.[0]?.toUpperCase() || "?"}
                        </div>
                      )}
                      <div className="min-w-0">
                        <p className="text-sm font-medium text-foreground truncate">{a.user_name || "Unknown"}</p>
                        <p className="text-xs text-muted-foreground truncate">{a.user_email}</p>
                      </div>
                    </div>
                    <div>
                      <Badge variant="outline" className="text-[10px]">
                        {a.agreement_type === "vendor_agreement" ? "Vendor" : "Organiser"}
                      </Badge>
                    </div>
                    <span className="text-sm font-semibold text-foreground">v{a.version_accepted}</span>
                    <span className="text-xs text-muted-foreground">
                      {a.accepted_at ? new Date(a.accepted_at).toLocaleString() : "—"}
                    </span>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="w-8 h-8 p-0"
                      onClick={() => { setDetailItem(a); setDetailOpen(true); }}
                    >
                      <Eye className="w-3.5 h-3.5" />
                    </Button>
                  </div>
                ))}
              </div>

              {/* Pagination */}
              {accPagination && accPagination.pages > 1 && (
                <div className="flex items-center justify-between pt-2">
                  <span className="text-xs text-muted-foreground">
                    Page {accPagination.page} of {accPagination.pages} - {accPagination.total} total
                  </span>
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={accPage <= 1}
                      onClick={() => setAccPage((p) => p - 1)}
                    >
                      Previous
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={accPage >= accPagination.pages}
                      onClick={() => setAccPage((p) => p + 1)}
                    >
                      Next
                    </Button>
                  </div>
                </div>
              )}
            </>
          )}
        </TabsContent>
      </Tabs>

      {/* Create Version Dialog */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Publish New Agreement Version</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>Agreement Type</Label>
              <Select
                value={createForm.agreement_type}
                onValueChange={(v) =>
                  setCreateForm((f) => ({
                    ...f,
                    agreement_type: v,
                    document_path: v === "vendor_agreement" ? "/docs/vendor-agreement.md" : "/docs/organiser-agreement.md",
                  }))
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {AGREEMENT_TYPES.map((t) => (
                    <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>What Changed (Summary)</Label>
              <Textarea
                placeholder="e.g. Updated cancellation policy and revised commission structure"
                value={createForm.summary}
                onChange={(e) => setCreateForm((f) => ({ ...f, summary: e.target.value }))}
                rows={3}
              />
              <p className="text-[11px] text-muted-foreground">Shown to users when they need to re-accept</p>
            </div>
            <div className="space-y-1.5">
              <Label>Document Path</Label>
              <Input
                value={createForm.document_path}
                onChange={(e) => setCreateForm((f) => ({ ...f, document_path: e.target.value }))}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button>
            <Button onClick={handleCreate} disabled={creating}>
              {creating ? <><Loader2 className="w-4 h-4 mr-1.5 animate-spin" /> Publishing...</> : "Publish Version"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Acceptance Detail Dialog */}
      <Dialog open={detailOpen} onOpenChange={setDetailOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Acceptance Details</DialogTitle>
          </DialogHeader>
          {detailItem && (
            <div className="space-y-3 py-2 text-sm">
              <div>
                <span className="text-muted-foreground text-xs">User</span>
                <p className="font-medium">{detailItem.user_name}</p>
                <p className="text-xs text-muted-foreground">{detailItem.user_email}</p>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <span className="text-muted-foreground text-xs">Agreement</span>
                  <p className="font-medium text-xs">
                    {detailItem.agreement_type === "vendor_agreement" ? "Vendor" : "Organiser"}
                  </p>
                </div>
                <div>
                  <span className="text-muted-foreground text-xs">Version</span>
                  <p className="font-medium text-xs">v{detailItem.version_accepted}</p>
                </div>
              </div>
              <div>
                <span className="text-muted-foreground text-xs">Accepted At</span>
                <p className="text-xs">{detailItem.accepted_at ? new Date(detailItem.accepted_at).toLocaleString() : "—"}</p>
              </div>
              <div>
                <span className="text-muted-foreground text-xs">IP Address</span>
                <p className="text-xs font-mono">{detailItem.ip_address || "—"}</p>
              </div>
              <div>
                <span className="text-muted-foreground text-xs">User Agent</span>
                <p className="text-xs text-muted-foreground break-all">{detailItem.user_agent || "—"}</p>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
