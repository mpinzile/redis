import { useEffect, useState, useCallback, useRef } from "react";
import { HelpCircle, Plus, Pencil, Trash2, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { adminApi } from "@/lib/api/admin";
import { adminCaches } from "@/lib/api/adminCache";
import { usePolling } from "@/hooks/usePolling";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";

export default function AdminFaqs() {
  useAdminMeta("FAQs");
  const { confirm, ConfirmDialog } = useConfirmDialog();
  const cache = adminCaches.faqs;
  const [faqs, setFaqs] = useState<any[]>(cache.data);
  const [loading, setLoading] = useState(!cache.loaded);
  const initialLoad = useRef(!cache.loaded);
  const [dialog, setDialog] = useState<{ mode: "create" | "edit"; item?: any } | null>(null);
  const [form, setForm] = useState({ question: "", answer: "", category: "General", display_order: 0, is_active: true });
  const [saving, setSaving] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (initialLoad.current) setLoading(true);
    const res = await adminApi.getFaqs();
    if (res.success) {
      const data = Array.isArray(res.data) ? res.data : [];
      cache.set(data);
      setFaqs(data);
    } else if (initialLoad.current) toast.error("Failed to load FAQs");
    setLoading(false);
    initialLoad.current = false;
  }, []);

  useEffect(() => {
    if (!cache.loaded) initialLoad.current = true;
    load();
  }, [load]);
  usePolling(load);

  const openCreate = () => { setForm({ question: "", answer: "", category: "General", display_order: faqs.length, is_active: true }); setDialog({ mode: "create" }); };
  const openEdit = (item: any) => { setForm({ question: item.question, answer: item.answer, category: item.category || "General", display_order: item.display_order || 0, is_active: item.is_active }); setDialog({ mode: "edit", item }); };


  const handleSave = async () => {
    if (!form.question.trim() || !form.answer.trim()) { toast.error("Question and answer are required"); return; }
    setSaving(true);
    const res = dialog?.mode === "edit" && dialog.item
      ? await adminApi.updateFaq(dialog.item.id, form)
      : await adminApi.createFaq(form);
    if (res.success) { toast.success(dialog?.mode === "edit" ? "FAQ updated" : "FAQ created"); setDialog(null); load(); }
    else toast.error(res.message || "Save failed");
    setSaving(false);
  };

  const handleDelete = async (id: string) => {
    const ok = await confirm({
      title: "Delete this FAQ?",
      description: "It will be removed from the public help center.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    setDeletingId(id);
    const res = await adminApi.deleteFaq(id);
    if (res.success) { toast.success("FAQ deleted"); load(); }
    else toast.error("Delete failed");
    setDeletingId(null);
  };

  const categories = Array.from(new Set(faqs.map((f) => f.category).filter(Boolean)));

  return (
    <div className="space-y-6">
      <ConfirmDialog />
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-foreground">FAQs</h2>
          <p className="text-sm text-muted-foreground mt-0.5">Manage the help center frequently asked questions</p>
        </div>
        <Button onClick={openCreate} size="sm"><Plus className="w-4 h-4 mr-1.5" /> Add FAQ</Button>
      </div>

      {loading ? (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="bg-card border border-border rounded-xl p-4 space-y-2">
              <Skeleton className="h-4 w-20" />
              <Skeleton className="h-4 w-3/4" />
              <Skeleton className="h-3 w-full" />
              <Skeleton className="h-3 w-2/3" />
            </div>
          ))}
        </div>
      ) : faqs.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground"><HelpCircle className="w-10 h-10 mx-auto mb-3 opacity-30" /><p>No FAQs yet</p><Button variant="outline" size="sm" className="mt-3" onClick={openCreate}>Add First FAQ</Button></div>
      ) : (
        <div className="space-y-2">
          {faqs.map((faq) => (
            <div key={faq.id} className={cn("bg-card border border-border rounded-xl p-4", !faq.is_active && "opacity-60")}>
              <div className="flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-xs bg-muted px-2 py-0.5 rounded-full text-muted-foreground">{faq.category}</span>
                    {!faq.is_active && <span className="text-xs text-muted-foreground">(inactive)</span>}
                  </div>
                  <p className="font-medium text-sm text-foreground">{faq.question}</p>
                  <p className="text-sm text-muted-foreground mt-1 line-clamp-2">{faq.answer}</p>
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  <Button variant="ghost" size="sm" onClick={() => openEdit(faq)}><Pencil className="w-3.5 h-3.5" /></Button>
                  <Button variant="ghost" size="sm" className="text-destructive hover:bg-destructive/10" onClick={() => handleDelete(faq.id)} disabled={deletingId === faq.id}>
                    {deletingId === faq.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Trash2 className="w-3.5 h-3.5" />}
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
            <DialogTitle>{dialog?.mode === "edit" ? "Edit FAQ" : "New FAQ"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Question *</Label>
              <Input value={form.question} onChange={(e) => setForm({ ...form, question: e.target.value })} placeholder="What is Nuru?" />
            </div>
            <div className="space-y-1.5">
              <Label>Answer *</Label>
              <Textarea value={form.answer} onChange={(e) => setForm({ ...form, answer: e.target.value })} rows={4} placeholder="Detailed answer..." />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Category</Label>
                <Input value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })} placeholder="General" list="faq-categories" />
                <datalist id="faq-categories">{categories.map((c) => <option key={c} value={c} />)}</datalist>
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
              {dialog?.mode === "edit" ? "Save Changes" : "Create FAQ"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
