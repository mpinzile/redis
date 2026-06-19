import { useEffect, useState, useCallback, useRef } from "react";
import { Package, Plus, Pencil, Trash2, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { adminApi } from "@/lib/api/admin";
import { adminCaches } from "@/lib/api/adminCache";
import { usePolling } from "@/hooks/usePolling";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { toast } from "sonner";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";

export default function AdminEventTypes() {
  useAdminMeta("Event Types");
  const { confirm, ConfirmDialog } = useConfirmDialog();
  const cache = adminCaches.eventTypes;
  const [types, setTypes] = useState<any[]>(cache.data);
  const [loading, setLoading] = useState(!cache.loaded);
  const initialLoad = useRef(!cache.loaded);
  const [dialog, setDialog] = useState<{ mode: "create" | "edit"; item?: any } | null>(null);
  const [form, setForm] = useState({ name: "", description: "", icon: "" });
  const [saving, setSaving] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (initialLoad.current) setLoading(true);
    const res = await adminApi.getEventTypes();
    if (res.success) {
      const data = Array.isArray(res.data) ? res.data : [];
      cache.set(data);
      setTypes(data);
    } else if (initialLoad.current) toast.error("Failed to load event types");
    setLoading(false);
    initialLoad.current = false;
  }, []);

  useEffect(() => {
    if (!cache.loaded) initialLoad.current = true;
    load();
  }, [load]);
  usePolling(load);

  const openCreate = () => { setForm({ name: "", description: "", icon: "" }); setDialog({ mode: "create" }); };
  const openEdit = (item: any) => { setForm({ name: item.name, description: item.description || "", icon: item.icon || "" }); setDialog({ mode: "edit", item }); };


  const handleSave = async () => {
    if (!form.name.trim()) { toast.error("Name is required"); return; }
    setSaving(true);
    let res;
    if (dialog?.mode === "edit" && dialog.item) {
      res = await adminApi.updateEventType(dialog.item.id, form);
    } else {
      res = await adminApi.createEventType(form);
    }
    if (res.success) {
      toast.success(dialog?.mode === "edit" ? "Event type updated" : "Event type created");
      setDialog(null);
      load();
    } else toast.error(res.message || "Save failed");
    setSaving(false);
  };

  const handleDelete = async (id: string, name: string) => {
    const ok = await confirm({
      title: `Delete "${name}"?`,
      description: "This event type will no longer be available when creating events. Existing events keep their current type.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    setDeletingId(id);
    const res = await adminApi.deleteEventType(id);
    if (res.success) { toast.success("Event type deleted"); load(); }
    else toast.error(res.message || "Delete failed");
    setDeletingId(null);
  };

  return (
    <div className="space-y-6">
      <ConfirmDialog />
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-foreground">Event Types</h2>
          <p className="text-sm text-muted-foreground mt-0.5">Manage event categories shown during event creation</p>
        </div>
        <Button onClick={openCreate} size="sm">
          <Plus className="w-4 h-4 mr-1.5" /> Add Event Type
        </Button>
      </div>

      {loading ? (
        <div className="bg-card border border-border rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-muted/50"><tr>{["Name","Description","Icon","Actions"].map(h => <th key={h} className="text-left px-4 py-3"><Skeleton className="h-4 w-16" /></th>)}</tr></thead>
            <tbody className="divide-y divide-border">
              {Array.from({ length: 6 }).map((_, i) => (
                <tr key={i}><td className="px-4 py-3"><Skeleton className="h-4 w-28" /></td><td className="px-4 py-3"><Skeleton className="h-4 w-48" /></td><td className="px-4 py-3"><Skeleton className="h-4 w-8" /></td><td className="px-4 py-3"><div className="flex gap-1"><Skeleton className="h-8 w-14" /><Skeleton className="h-8 w-16" /></div></td></tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : types.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <Package className="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p>No event types yet</p>
          <Button variant="outline" size="sm" className="mt-3" onClick={openCreate}>Add First Event Type</Button>
        </div>
      ) : (
        <div className="bg-card border border-border rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-muted/50">
              <tr>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Name</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Description</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Icon</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {types.map((t) => (
                <tr key={t.id} className="hover:bg-muted/30 transition-colors">
                  <td className="px-4 py-3 font-medium text-foreground">{t.name}</td>
                  <td className="px-4 py-3 text-muted-foreground max-w-xs truncate">{t.description || "—"}</td>
                  <td className="px-4 py-3 text-muted-foreground">{t.icon || "—"}</td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1.5">
                      <Button variant="ghost" size="sm" onClick={() => openEdit(t)}>
                        <Pencil className="w-3.5 h-3.5 mr-1" /> Edit
                      </Button>
                      <Button variant="ghost" size="sm" className="text-destructive hover:bg-destructive/10"
                        onClick={() => handleDelete(t.id, t.name)} disabled={deletingId === t.id}>
                        {deletingId === t.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Trash2 className="w-3.5 h-3.5 mr-1" />}
                        Delete
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Dialog open={!!dialog} onOpenChange={() => setDialog(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{dialog?.mode === "edit" ? "Edit Event Type" : "New Event Type"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Name *</Label>
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="e.g. Wedding, Corporate, Birthday" />
            </div>
            <div className="space-y-1.5">
              <Label>Description</Label>
              <Textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} rows={2} placeholder="Brief description..." />
            </div>
            <div className="space-y-1.5">
              <Label>Icon (emoji or name)</Label>
              <Input value={form.icon} onChange={(e) => setForm({ ...form, icon: e.target.value })} placeholder="💒 or 'wedding'" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialog(null)}>Cancel</Button>
            <Button onClick={handleSave} disabled={saving}>
              {saving ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}
              {dialog?.mode === "edit" ? "Save Changes" : "Create"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
