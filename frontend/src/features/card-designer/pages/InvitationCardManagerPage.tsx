import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ArrowLeft, Plus, Star, Copy, Trash2, Eye, Pencil } from "lucide-react";
import { invitationTemplatesApi, type InvitationCardTemplate } from "@/lib/api/invitationTemplates";
import { toast } from "sonner";
import { format } from "date-fns";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";

export default function InvitationCardManagerPage() {
  const { eventId } = useParams<{ eventId: string }>();
  const navigate = useNavigate();
  const { confirm, ConfirmDialog } = useConfirmDialog();
  const [items, setItems] = useState<InvitationCardTemplate[]>([]);
  const [loading, setLoading] = useState(true);

  async function load() {
    if (!eventId) return;
    setLoading(true);
    try {
      const res = await invitationTemplatesApi.list(eventId);
      setItems(res.data || []);
    } finally { setLoading(false); }
  }
  useEffect(() => { load(); }, [eventId]);

  async function activate(id: string) { await invitationTemplatesApi.activate(eventId!, id); toast.success("Activated"); load(); }
  async function dup(id: string) { await invitationTemplatesApi.duplicate(eventId!, id); toast.success("Duplicated"); load(); }
  async function del(id: string) {
    const ok = await confirm({
      title: "Delete this design?",
      description: "This invitation card design will be permanently removed. This cannot be undone.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    await invitationTemplatesApi.remove(eventId!, id);
    toast.success("Deleted");
    load();
  }

  return (
    <div className="max-w-6xl mx-auto p-6 space-y-6">
      <ConfirmDialog />
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={() => navigate(`/event-management/${eventId}`)}><ArrowLeft className="w-4 h-4" /></Button>
        <div className="flex-1">
          <h1 className="text-2xl font-semibold tracking-tight">Invitation Card Designs</h1>
          <p className="text-sm text-muted-foreground">Create personalized invitation cards. Activate one to be used for guest downloads.</p>
        </div>
        <Button onClick={() => navigate(`/events/${eventId}/invitations/cards/new`)}><Plus className="w-4 h-4 mr-1" /> New design</Button>
      </div>

      {loading ? (
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
          {[0,1,2].map(i => <div key={i} className="aspect-[4/5] rounded-xl bg-muted animate-pulse" />)}
        </div>
      ) : items.length === 0 ? (
        <div className="text-center py-16 border-2 border-dashed rounded-xl">
          <h3 className="font-medium mb-1">No designs yet</h3>
          <p className="text-sm text-muted-foreground mb-4">Start from a template or a blank canvas.</p>
          <Button onClick={() => navigate(`/events/${eventId}/invitations/cards/new`)}>Create your first design</Button>
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
          {items.map(t => (
            <Card key={t.id} className="overflow-hidden">
              <div className="aspect-[4/5] bg-muted relative">
                {t.preview_image_url ? (
                  <img src={t.preview_image_url} alt={t.name} className="w-full h-full object-cover" />
                ) : (
                  <div className="w-full h-full flex items-center justify-center text-xs text-muted-foreground">No preview</div>
                )}
                {t.is_active && <Badge className="absolute top-2 left-2"><Star className="w-3 h-3 mr-1" /> Active</Badge>}
              </div>
              <CardContent className="p-3 space-y-2">
                <div className="flex items-center justify-between">
                  <h3 className="font-medium text-sm truncate">{t.name}</h3>
                  <span className="text-[10px] text-muted-foreground">{t.canvas_width}×{t.canvas_height}</span>
                </div>
                <p className="text-[11px] text-muted-foreground">Updated {format(new Date(t.updated_at), "PP")}</p>
                <div className="flex flex-wrap gap-1">
                  <Button size="sm" variant="outline" onClick={() => navigate(`/events/${eventId}/invitations/cards/${t.id}/edit`)}><Pencil className="w-3 h-3 mr-1" /> Edit</Button>
                  <Button size="sm" variant="outline" onClick={() => navigate(`/events/${eventId}/invitations/cards/${t.id}/preview`)}><Eye className="w-3 h-3 mr-1" /> Preview</Button>
                  {!t.is_active && <Button size="sm" onClick={() => activate(t.id)}><Star className="w-3 h-3 mr-1" /> Activate</Button>}
                  <Button size="sm" variant="ghost" onClick={() => dup(t.id)}><Copy className="w-3 h-3" /></Button>
                  <Button size="sm" variant="ghost" onClick={() => del(t.id)}><Trash2 className="w-3 h-3" /></Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
