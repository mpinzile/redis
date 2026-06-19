import { useEffect, useState, useCallback, useRef } from "react";
import { Tag, Plus, Pencil, Trash2, Loader2, ChevronLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { adminApi } from "@/lib/api/admin";
import { usePolling } from "@/hooks/usePolling";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";

export default function AdminIssueCategories() {
  useAdminMeta("Issue Categories");
  const navigate = useNavigate();
  const { confirm, ConfirmDialog } = useConfirmDialog();
  const [categories, setCategories] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const initialLoad = useRef(true);
  const [dialog, setDialog] = useState<{ mode: "create" | "edit"; item?: any } | null>(null);
  const [form, setForm] = useState({ name: "", description: "", icon: "", display_order: 0, is_active: true });
  const [saving, setSaving] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (initialLoad.current) setLoading(true);
    const res = await adminApi.getIssueCategories();
    if (res.success) {
      setCategories(Array.isArray(res.data) ? res.data : []);
    } else if (initialLoad.current) toast.error("Failed to load categories");
    setLoading(false);
    initialLoad.current = false;
  }, []);

  useEffect(() => { load(); }, [load]);
  usePolling(load);

  const openCreate = () => {
    setForm({ name: "", description: "", icon: "", display_order: categories.length, is_active: true });
    setDialog({ mode: "create" });
  };
  const openEdit = (item: any) => {
    setForm({ name: item.name, description: item.description || "", icon: item.icon || "", display_order: item.display_order || 0, is_active: item.is_active });
    setDialog({ mode: "edit", item });
  };

  const handleSave = async () => {
    if (!form.name.trim()) { toast.error("Name is required"); return; }
    setSaving(true);
    const res = dialog?.mode === "edit" && dialog.item
      ? await adminApi.updateIssueCategory(dialog.item.id, form)
      : await adminApi.createIssueCategory(form);
    if (res.success) {
      toast.success(dialog?.mode === "edit" ? "Category updated" : "Category created");
      setDialog(null);
      load();
    } else toast.error(res.message || "Save failed");
    setSaving(false);
  };

  const handleDelete = async (id: string) => {
    const ok = await confirm({
      title: "Delete this category?",
      description: "Existing issues will keep their current category. This cannot be undone.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    setDeletingId(id);
    const res = await adminApi.deleteIssueCategory(id);
    if (res.success) { toast.success("Category deleted"); load(); }
    else toast.error(res.message || "Delete failed");
    setDeletingId(null);
  };

  return (
    <div className="space-y-6">
      <ConfirmDialog />
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Button variant="ghost" size="sm" onClick={() => navigate("/admin/issues")}>
            <ChevronLeft className="w-4 h-4 mr-1" /> Issues
          </Button>
          <div>
            <h2 className="text-xl font-bold text-foreground">Issue Categories</h2>
            <p className="text-sm text-muted-foreground mt-0.5">Manage issue categories users can select from</p>
          </div>
        </div>
        <Button onClick={openCreate} size="sm"><Plus className="w-4 h-4 mr-1.5" /> Add Category</Button>
      </div>

      {loading ? (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="bg-card border border-border rounded-xl p-4 space-y-2">
              <Skeleton className="h-4 w-1/3" />
              <Skeleton className="h-3 w-2/3" />
            </div>
          ))}
        </div>
      ) : categories.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <Tag className="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p>No issue categories yet</p>
          <Button variant="outline" size="sm" className="mt-3" onClick={openCreate}>Add First Category</Button>
        </div>
      ) : (
        <div className="space-y-2">
          {categories.map((cat) => (
            <div key={cat.id} className={cn("bg-card border border-border rounded-xl p-4", !cat.is_active && "opacity-60")}>
              <div className="flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-medium text-sm text-foreground">{cat.name}</span>
                    {!cat.is_active && <span className="text-xs text-muted-foreground">(inactive)</span>}
                    <span className="text-xs text-muted-foreground">• {cat.issue_count || 0} issue(s)</span>
                  </div>
                  {cat.description && <p className="text-xs text-muted-foreground line-clamp-1">{cat.description}</p>}
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  <Button variant="ghost" size="sm" onClick={() => openEdit(cat)}><Pencil className="w-3.5 h-3.5" /></Button>
                  <Button variant="ghost" size="sm" className="text-destructive hover:bg-destructive/10" onClick={() => handleDelete(cat.id)} disabled={deletingId === cat.id}>
                    {deletingId === cat.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Trash2 className="w-3.5 h-3.5" />}
                  </Button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      <Dialog open={!!dialog} onOpenChange={() => setDialog(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>{dialog?.mode === "edit" ? "Edit Category" : "New Issue Category"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Name *</Label>
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="e.g., Bug Report" />
            </div>
            <div className="space-y-1.5">
              <Label>Description</Label>
              <Textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} rows={2} placeholder="Brief description..." />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Icon</Label>
                <Input value={form.icon} onChange={(e) => setForm({ ...form, icon: e.target.value })} placeholder="calendar, bug, etc." />
              </div>
              <div className="space-y-1.5">
                <Label>Display Order</Label>
                <Input type="number" value={form.display_order} onChange={(e) => setForm({ ...form, display_order: Number(e.target.value) })} />
              </div>
            </div>
            <div className="flex items-center gap-3">
              <Switch checked={form.is_active} onCheckedChange={(v) => setForm({ ...form, is_active: v })} />
              <Label>Active (visible to users)</Label>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialog(null)}>Cancel</Button>
            <Button onClick={handleSave} disabled={saving}>
              {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}
              {dialog?.mode === "edit" ? "Save Changes" : "Create Category"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
