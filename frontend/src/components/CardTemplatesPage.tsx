import { useEffect, useState } from "react";
import { ChevronLeft, Eye, Loader2 } from "lucide-react";
import SvgIcon from "@/components/ui/svg-icon";
import CardIcon from "@/assets/icons/card-icon.svg";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useWorkspaceMeta } from "@/hooks/useWorkspaceMeta";
import { SVG_TEMPLATES, SvgCardTemplate, InvitationContent } from "@/components/invitation-cards/SvgTemplateRegistry";
import SvgCardRenderer from "@/components/invitation-cards/SvgCardRenderer";
import { eventsApi } from "@/lib/api/events";
import { toast } from "sonner";
import { useLanguage } from '@/lib/i18n/LanguageContext';

const CATEGORY_LABELS: Record<string, string> = {
  wedding: "Wedding",
  birthday: "Birthday",
  sendoff: "Send-off",
  corporate: "Corporate",
  anniversary: "Anniversary",
  conference: "Conference",
  graduation: "Graduation",
  memorial: "Memorial",
  baby_shower: "Baby Shower",
};

const PREVIEW_DATA = {
  guestName: "Mgeni Wako",
  secondName: "Mwenzi",
  eventTitle: "Tukio Lako",
  date: "Jumamosi, 15 Machi 2025",
  time: "Saa kumi na mbili jioni",
  venue: "Serena Hotel Dar es Salaam",
  address: "Ohio Street · Dar es Salaam",
  qrValue: "NURU-PREVIEW-001",
};

const CardTemplatesPage = () => {
  const { t } = useLanguage();
  useWorkspaceMeta({
    title: "Invitation Card Templates",
    description: "Browse premium SVG invitation card designs for your events.",
  });

  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const eventId = searchParams.get('eventId');
  const [previewTemplate, setPreviewTemplate] = useState<SvgCardTemplate | null>(null);
  const [filterCategory, setFilterCategory] = useState<string>("all");
  const [content, setContent] = useState<InvitationContent>({});
  const [saving, setSaving] = useState(false);

  // Preload existing override copy if editing for an event
  useEffect(() => {
    if (!eventId) return;
    eventsApi.getInvitationCard(eventId).then((res: any) => {
      if (res?.success && res.data?.event?.invitation_content) {
        setContent(res.data.event.invitation_content);
      }
      const tplId = res?.data?.event?.invitation_template_id;
      if (tplId) {
        const tpl = SVG_TEMPLATES.find(t => t.id === tplId);
        if (tpl) setPreviewTemplate(tpl);
      }
    }).catch(() => {});
  }, [eventId]);

  const updateContent = (key: keyof InvitationContent, value: string) =>
    setContent(prev => ({ ...prev, [key]: value }));

  const handleApply = async () => {
    if (!eventId || !previewTemplate) return;
    setSaving(true);
    try {
      const fd = new FormData();
      fd.append('invitation_template_id', previewTemplate.id);
      // Strip empty fields so renderer falls back to template defaults
      const cleaned: Record<string, string> = {};
      Object.entries(content).forEach(([k, v]) => { if (v && v.trim()) cleaned[k] = v.trim(); });
      fd.append('invitation_content', JSON.stringify(cleaned));
      const res: any = await eventsApi.update(eventId, fd);
      if (res?.success !== false) {
        toast.success('Invitation template applied');
        setPreviewTemplate(null);
      } else {
        toast.error(res?.message || 'Could not save');
      }
    } catch {
      toast.error('Could not save invitation');
    } finally {
      setSaving(false);
    }
  };

  const categories = ["all", ...new Set(SVG_TEMPLATES.flatMap(t => t.category))];

  const filteredTemplates = filterCategory === "all"
    ? SVG_TEMPLATES
    : SVG_TEMPLATES.filter(t => t.category.includes(filterCategory as any));

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <Button
          variant="ghost"
          size="icon"
          onClick={() => navigate("/my-events")}
          className="shrink-0"
        >
          <ChevronLeft className="w-5 h-5" />
        </Button>
        <div className="flex-1">
          <h1 className="text-2xl font-bold tracking-tight">
            Invitation Card Templates
          </h1>
          <p className="text-muted-foreground text-sm mt-0.5">
            Premium designs that automatically fill in guest names and QR codes for each invitation.
          </p>
        </div>
      </div>

      {/* Info banner */}
      <div className="relative overflow-hidden rounded-xl border border-border bg-muted/20 p-5">
        <div className="flex items-start gap-3">
          <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
            <SvgIcon src={CardIcon} alt="" className="w-4.5 h-4.5 text-primary" />
          </div>
          <div className="space-y-1">
            <h3 className="font-semibold text-foreground text-sm">
              How It Works
            </h3>
            <p className="text-sm text-muted-foreground leading-relaxed max-w-xl">
              Nuru picks the best card design based on your event type. When a guest downloads their
              invitation, their name and a unique check-in QR code are placed automatically. No design
              work needed.
            </p>
          </div>
        </div>
      </div>

      {/* Category filter pills */}
      <div className="flex flex-wrap gap-2">
        {categories.map(cat => (
          <Button
            key={cat}
            size="sm"
            variant={filterCategory === cat ? "default" : "outline"}
            className="text-xs h-7 rounded-full"
            onClick={() => setFilterCategory(cat)}
          >
            {cat === "all" ? "All Templates" : CATEGORY_LABELS[cat] || cat}
          </Button>
        ))}
      </div>

      {/* Template grid */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
        {filteredTemplates.map((template) => (
          <Card
            key={template.id}
            className="overflow-hidden cursor-pointer hover:shadow-lg transition-all group border-border/60"
            onClick={() => setPreviewTemplate(template)}
          >
            <div className="relative aspect-[480/680] bg-muted/30 overflow-hidden">
              <img
                src={template.thumbnailUrl}
                alt={template.name}
                className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
              />
              <div className="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors flex items-center justify-center">
                <Eye className="w-6 h-6 text-white opacity-0 group-hover:opacity-100 transition-opacity" />
              </div>
              <div className="absolute top-2 left-2 flex flex-wrap gap-1">
                {template.category.map(cat => (
                  <Badge key={cat} variant="secondary" className="text-[10px] px-1.5 py-0 bg-background/80 backdrop-blur-sm">
                    {CATEGORY_LABELS[cat] || cat}
                  </Badge>
                ))}
              </div>
            </div>
            <CardContent className="p-3">
              <h3 className="text-sm font-semibold text-foreground truncate">{template.name}</h3>
              <p className="text-xs text-muted-foreground line-clamp-2 mt-0.5">{template.description}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {filteredTemplates.length === 0 && (
        <div className="text-center py-12 text-muted-foreground">
          <p>No templates found for this category.</p>
        </div>
      )}

      {/* Preview dialog */}
      <Dialog open={!!previewTemplate} onOpenChange={(o) => { if (!o) { setPreviewTemplate(null); setContent({}); } }}>
        <DialogContent className="max-w-3xl p-0 overflow-hidden border-0 bg-transparent shadow-2xl">
          <DialogHeader className="sr-only">
            <DialogTitle>{previewTemplate?.name || "Template Preview"}</DialogTitle>
          </DialogHeader>
          {previewTemplate && (
            <div className="bg-card rounded-2xl overflow-hidden grid md:grid-cols-[1fr_320px]">
              {/* Live preview */}
              <div className="max-h-[80vh] overflow-y-auto">
                <div className="relative">
                  <SvgCardRenderer
                    template={previewTemplate}
                    data={PREVIEW_DATA}
                    contentOverrides={content}
                  />
                </div>
                <div className="p-4 border-t border-border bg-muted/30 space-y-2">
                  <h3 className="font-semibold text-sm text-foreground">{previewTemplate.name}</h3>
                  <p className="text-xs text-muted-foreground">{previewTemplate.description}</p>
                  <div className="flex flex-wrap gap-1">
                    {previewTemplate.category.map(cat => (
                      <Badge key={cat} variant="outline" className="text-[10px]">
                        {CATEGORY_LABELS[cat] || cat}
                      </Badge>
                    ))}
                    {previewTemplate.hasQr && (
                      <Badge variant="outline" className="text-[10px]">QR Code</Badge>
                    )}
                  </div>
                </div>
              </div>

              {/* Inline content editor */}
              <div className="border-l border-border bg-background/60 p-4 space-y-3 max-h-[80vh] overflow-y-auto">
                <div>
                  <h4 className="font-semibold text-sm">Edit copy</h4>
                  <p className="text-[11px] text-muted-foreground mt-0.5">
                    Live preview. Saved to the event's invitation_content when you apply this template.
                  </p>
                </div>
                {([
                  ['headline', 'Headline'],
                  ['sub_headline', 'Sub-headline'],
                  ['host_line', 'Host line'],
                  ['body', 'Body'],
                  ['footer_note', 'Footer note'],
                  ['dress_code_label', 'Dress code'],
                  ['rsvp_label', 'RSVP label'],
                ] as Array<[keyof InvitationContent, string]>).map(([key, label]) => (
                  <div key={key} className="space-y-1">
                    <Label htmlFor={`fld-${key}`} className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</Label>
                    <Input
                      id={`fld-${key}`}
                      autoComplete="off"
                      value={content[key] || ''}
                      onChange={(e) => updateContent(key, e.target.value)}
                      placeholder="Use template default"
                      className="h-8 text-xs"
                    />
                  </div>
                ))}
                <Button
                  size="sm"
                  variant="outline"
                  className="w-full mt-2"
                  onClick={() => setContent({})}
                >
                  Reset to defaults
                </Button>
                {eventId && (
                  <Button
                    size="sm"
                    className="w-full"
                    disabled={saving}
                    onClick={handleApply}
                  >
                    {saving ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : null}
                    Apply to event
                  </Button>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default CardTemplatesPage;
