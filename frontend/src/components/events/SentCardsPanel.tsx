/**
 * SentCardsPanel — read-only browser for cards that have already been
 * dispatched on a given event. Lists unique card templates with their
 * delivery counts; drilling into a template lists each recipient with
 * the WhatsApp availability label, phone number and the most recent
 * generated card URL. Organisers can select recipients and download a
 * ZIP of PNGs or a combined PDF — both reuse the existing rendered
 * card and never trigger a new send.
 */
import { useCallback, useEffect, useMemo, useState } from "react";
import { toast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import {
  ArrowLeft,
  Download,
  FileText,
  Loader2,
  MessageCircle,
  MessageSquareOff,
  HelpCircle,
  Send,
} from "lucide-react";
import {
  eventCardsApi,
  type SentCardRecipient,
  type SentCardTemplateSummary,
  type WhatsAppStatus,
} from "@/lib/api/eventCards";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";

interface Props {
  eventId: string;
}

function formatDate(value?: string | null): string {
  if (!value) return "—";
  try {
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return "—";
    return d.toLocaleString();
  } catch {
    return "—";
  }
}

function WhatsAppBadge({ status }: { status: WhatsAppStatus }) {
  if (status === "on_whatsapp") {
    return (
      <Badge className="bg-emerald-500/15 text-emerald-700 hover:bg-emerald-500/15 border border-emerald-500/30">
        <MessageCircle className="w-3 h-3 mr-1" /> On WhatsApp
      </Badge>
    );
  }
  if (status === "not_on_whatsapp") {
    return (
      <Badge className="bg-destructive/15 text-destructive hover:bg-destructive/15 border border-destructive/30">
        <MessageSquareOff className="w-3 h-3 mr-1" /> Not on WhatsApp
      </Badge>
    );
  }
  return (
    <Badge variant="outline" className="text-muted-foreground">
      <HelpCircle className="w-3 h-3 mr-1" /> Unknown
    </Badge>
  );
}

function triggerBlobDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export default function SentCardsPanel({ eventId }: Props) {
  const [templates, setTemplates] = useState<SentCardTemplateSummary[]>([]);
  const [loadingTemplates, setLoadingTemplates] = useState(true);
  const [templatesError, setTemplatesError] = useState<string | null>(null);

  const [activeTemplate, setActiveTemplate] = useState<SentCardTemplateSummary | null>(null);
  const [recipients, setRecipients] = useState<SentCardRecipient[]>([]);
  const [loadingRecipients, setLoadingRecipients] = useState(false);
  const [recipientsError, setRecipientsError] = useState<string | null>(null);

  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState("");
  const [waFilter, setWaFilter] = useState<"all" | "whatsapp" | "normal">("all");
  const [downloading, setDownloading] = useState<"images" | "pdf" | null>(null);
  const [resending, setResending] = useState(false);
  const { confirm, ConfirmDialog } = useConfirmDialog();

  const refreshTemplates = useCallback(async () => {
    setLoadingTemplates(true);
    setTemplatesError(null);
    try {
      const res: any = await eventCardsApi.listSentCardTemplates(eventId);
      const items: SentCardTemplateSummary[] = res?.data?.templates ?? res?.templates ?? [];
      setTemplates(items);
    } catch (err: any) {
      setTemplatesError(err?.message || "Failed to load sent cards.");
    } finally {
      setLoadingTemplates(false);
    }
  }, [eventId]);

  useEffect(() => { refreshTemplates(); }, [refreshTemplates]);

  const openTemplate = useCallback(async (tpl: SentCardTemplateSummary) => {
    setActiveTemplate(tpl);
    setSelectedIds(new Set());
    setSearch("");
    setWaFilter("all");
    setLoadingRecipients(true);
    setRecipientsError(null);
    setRecipients([]);
    try {
      const res: any = await eventCardsApi.listSentCardRecipients(eventId, tpl.template_id);
      const items: SentCardRecipient[] = res?.data?.recipients ?? res?.recipients ?? [];
      setRecipients(items);
    } catch (err: any) {
      setRecipientsError(err?.message || "Failed to load recipients.");
    } finally {
      setLoadingRecipients(false);
    }
  }, [eventId]);

  const counts = useMemo(() => {
    let whatsapp = 0;
    let normal = 0;
    for (const r of recipients) {
      if (r.whatsapp_status === "on_whatsapp") whatsapp += 1;
      else if (r.whatsapp_status === "not_on_whatsapp") normal += 1;
    }
    return { all: recipients.length, whatsapp, normal };
  }, [recipients]);

  const filteredRecipients = useMemo(() => {
    const q = search.trim().toLowerCase();
    return recipients.filter((r) => {
      if (waFilter === "whatsapp" && r.whatsapp_status !== "on_whatsapp") return false;
      if (waFilter === "normal" && r.whatsapp_status !== "not_on_whatsapp") return false;
      if (!q) return true;
      return (
        (r.recipient_name || "").toLowerCase().includes(q) ||
        (r.recipient_phone || "").toLowerCase().includes(q)
      );
    });
  }, [recipients, search, waFilter]);


  const allFilteredSelected =
    filteredRecipients.length > 0 &&
    filteredRecipients.every((r) => selectedIds.has(r.sent_id));

  const toggleSelectAll = () => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (allFilteredSelected) {
        filteredRecipients.forEach((r) => next.delete(r.sent_id));
      } else {
        filteredRecipients.forEach((r) => next.add(r.sent_id));
      }
      return next;
    });
  };

  const toggleOne = (sentId: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(sentId)) next.delete(sentId);
      else next.add(sentId);
      return next;
    });
  };

  const clearSelection = () => setSelectedIds(new Set());

  const safeSeg = (s: string) =>
    (s || "").trim().replace(/[^a-zA-Z0-9._-]+/g, "_").replace(/_+/g, "_").replace(/^_|_$/g, "") || "card";

  const timestamp = () =>
    new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);

  // Fetch a card URL → Blob (CORS-friendly; falls back to fetch w/o mode).
  const fetchCardBlob = async (url: string): Promise<Blob> => {
    try {
      const r = await fetch(url, { mode: "cors", cache: "force-cache" });
      if (r.ok) return await r.blob();
    } catch {}
    const r2 = await fetch(url, { cache: "force-cache" });
    if (!r2.ok) throw new Error(`Failed to fetch card (${r2.status})`);
    return await r2.blob();
  };

  const blobToDataUrl = (blob: Blob): Promise<string> =>
    new Promise((resolve, reject) => {
      const fr = new FileReader();
      fr.onload = () => resolve(String(fr.result));
      fr.onerror = () => reject(fr.error);
      fr.readAsDataURL(blob);
    });

  const loadImageSize = (dataUrl: string): Promise<{ w: number; h: number }> =>
    new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve({ w: img.naturalWidth, h: img.naturalHeight });
      img.onerror = () => reject(new Error("Image decode failed"));
      img.src = dataUrl;
    });

  const doDownload = async (format: "images" | "pdf") => {
    if (selectedIds.size === 0) {
      toast({ title: "Select recipients first", description: "Pick at least one recipient to download.", variant: "destructive" });
      return;
    }
    const chosen = recipients.filter(
      (r) => selectedIds.has(r.sent_id) && !!r.rendered_card_url,
    );
    if (chosen.length === 0) {
      toast({ title: "No card image", description: "Selected recipients have no rendered card yet.", variant: "destructive" });
      return;
    }
    setDownloading(format);
    try {
      // Fetch every selected card in parallel — high quality, original PNG.
      const fetched = await Promise.all(
        chosen.map(async (r) => ({
          rec: r,
          blob: await fetchCardBlob(r.rendered_card_url as string),
        })),
      );

      if (format === "images") {
        if (fetched.length === 1) {
          const { rec, blob } = fetched[0];
          triggerBlobDownload(blob, `${safeSeg(rec.recipient_name || "card")}.png`);
        } else {
          const { default: JSZip } = await import("jszip");
          const zip = new JSZip();
          const used = new Set<string>();
          for (const { rec, blob } of fetched) {
            let base = safeSeg(rec.recipient_name || "card");
            let name = `${base}.png`;
            let i = 2;
            while (used.has(name)) name = `${base}_${i++}.png`;
            used.add(name);
            zip.file(name, blob);
          }
          const out = await zip.generateAsync({ type: "blob" });
          triggerBlobDownload(out, `invitation_cards_${timestamp()}.zip`);
        }
      } else {
        // PDF: always one combined PDF, one page per card (no zip — zipped PDFs were unreadable).
        const { jsPDF } = await import("jspdf");
        // Decode all images first so we can size each page to the source PNG (max quality, no scaling loss).
        const pages = await Promise.all(
          fetched.map(async ({ rec, blob }) => {
            const dataUrl = await blobToDataUrl(blob);
            const { w, h } = await loadImageSize(dataUrl);
            return { rec, dataUrl, w, h };
          }),
        );
        const first = pages[0];
        const pdf = new jsPDF({
          orientation: first.w >= first.h ? "landscape" : "portrait",
          unit: "px",
          format: [first.w, first.h],
          compress: true,
        });
        pdf.addImage(first.dataUrl, "PNG", 0, 0, first.w, first.h, undefined, "FAST");
        for (let i = 1; i < pages.length; i++) {
          const p = pages[i];
          pdf.addPage([p.w, p.h], p.w >= p.h ? "landscape" : "portrait");
          pdf.addImage(p.dataUrl, "PNG", 0, 0, p.w, p.h, undefined, "FAST");
        }
        const filename =
          pages.length === 1
            ? `${safeSeg(pages[0].rec.recipient_name || "card")}.pdf`
            : `invitation_cards_${timestamp()}.pdf`;
        pdf.save(filename);
      }

      toast({
        title: format === "pdf" ? "PDF ready" : fetched.length === 1 ? "Card downloaded" : "Cards ready",
        description: `Downloaded ${fetched.length} card${fetched.length === 1 ? "" : "s"}.`,
      });
    } catch (err: any) {
      toast({
        title: "Download failed",
        description: err?.message || "Could not download the selected cards.",
        variant: "destructive",
      });
    } finally {
      setDownloading(null);
    }
  };

  const doResend = async () => {
    if (selectedIds.size === 0) {
      toast({
        title: "Select recipients first",
        description: "Pick at least one recipient to resend the card.",
        variant: "destructive",
      });
      return;
    }
    const ids = Array.from(selectedIds);
    const ok = await confirm({
      title: `Resend card to ${ids.length} recipient${ids.length === 1 ? "" : "s"}?`,
      description: `They'll receive the same card image again on WhatsApp or SMS.`,
      confirmLabel: "Resend",
    });
    if (!ok) return;
    setResending(true);
    try {
      const res: any = await eventCardsApi.resendSentCards(eventId, ids);
      const queued = res?.data?.queued ?? res?.queued ?? ids.length;
      toast({
        title: "Resending cards",
        description: `Queued ${queued} card${queued === 1 ? "" : "s"} for delivery.`,
      });
      clearSelection();
      // Refresh the row metadata so timestamps / delivery_status update.
      if (activeTemplate) openTemplate(activeTemplate);
    } catch (err: any) {
      toast({
        title: "Resend failed",
        description: err?.message || "Could not resend the selected cards.",
        variant: "destructive",
      });
    } finally {
      setResending(false);
    }
  };



  // ── Render: template list ───────────────────────────────────────
  if (!activeTemplate) {
    if (loadingTemplates) {
      return (
        <div className="flex items-center justify-center py-16 text-muted-foreground">
          <Loader2 className="w-5 h-5 animate-spin mr-2" /> Loading sent cards…
        </div>
      );
    }
    if (templatesError) {
      return (
        <Card>
          <CardContent className="py-10 text-center space-y-3">
            <p className="text-sm text-destructive">{templatesError}</p>
            <Button variant="outline" size="sm" onClick={refreshTemplates}>Retry</Button>
          </CardContent>
        </Card>
      );
    }
    if (templates.length === 0) {
      return (
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground text-sm">
            No cards have been sent for this event yet. Once you send a card from the Templates tab, it'll appear here.
          </CardContent>
        </Card>
      );
    }
    return (
      <div className="space-y-3">
        {templates.map((t) => (
          <button
            key={t.template_id}
            onClick={() => openTemplate(t)}
            className="w-full text-left rounded-xl border border-border bg-card hover:border-primary/60 hover:shadow-sm transition p-4 flex items-center gap-4"
          >
            <div className="w-16 h-20 rounded-md bg-muted overflow-hidden flex items-center justify-center shrink-0">
              {t.thumbnail_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={t.thumbnail_url} alt={t.name} className="w-full h-full object-cover" />
              ) : (
                <FileText className="w-6 h-6 text-muted-foreground" />
              )}
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-medium truncate">{t.name}</p>
              <p className="text-xs text-muted-foreground capitalize">{t.category.replace(/-/g, " ")}</p>
              <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                <span><strong className="text-foreground">{t.recipient_count}</strong> recipient{t.recipient_count === 1 ? "" : "s"}</span>
                <span>Last sent {formatDate(t.last_sent_at)}</span>
              </div>
            </div>
            <Badge variant="outline" className="shrink-0">View</Badge>
          </button>
        ))}
      </div>
    );
  }

  // ── Render: recipients for active template ──────────────────────
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <Button variant="ghost" size="sm" onClick={() => { setActiveTemplate(null); setRecipients([]); }}>
          <ArrowLeft className="w-4 h-4 mr-1" /> All sent cards
        </Button>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold truncate">{activeTemplate.name}</h3>
          <p className="text-xs text-muted-foreground">
            {activeTemplate.recipient_count} recipient{activeTemplate.recipient_count === 1 ? "" : "s"} ·
            Last sent {formatDate(activeTemplate.last_sent_at)}
          </p>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {(["all", "whatsapp", "normal"] as const).map((key) => {
          const label = key === "all" ? "All" : key === "whatsapp" ? "WhatsApp" : "Normal";
          const count = counts[key];
          const active = waFilter === key;
          return (
            <button
              key={key}
              type="button"
              onClick={() => { setWaFilter(key); setSelectedIds(new Set()); }}
              className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium transition ${
                active
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-border bg-background text-foreground hover:bg-muted"
              }`}
            >
              {label}
              <span className={`rounded-full px-1.5 py-0.5 text-[10px] ${active ? "bg-primary-foreground/20" : "bg-muted text-muted-foreground"}`}>
                {count}
              </span>
            </button>
          );
        })}
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <Input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by name or phone"
          className="flex-1 min-w-[200px]"
        />
        <Button
          variant="outline"
          size="sm"
          onClick={toggleSelectAll}
          disabled={filteredRecipients.length === 0}
        >
          {allFilteredSelected ? "Unselect all" : "Select all"}
        </Button>
        <Button
          variant="ghost"
          size="sm"
          onClick={clearSelection}
          disabled={selectedIds.size === 0}
        >
          Clear ({selectedIds.size})
        </Button>
        <Button
          size="sm"
          onClick={() => doDownload("images")}
          disabled={selectedIds.size === 0 || downloading !== null}
        >
          {downloading === "images" ? (
            <><Loader2 className="w-4 h-4 mr-1 animate-spin" />Preparing…</>
          ) : (
            <><Download className="w-4 h-4 mr-1" />Download images</>
          )}
        </Button>
        <Button
          size="sm"
          variant="secondary"
          onClick={() => doDownload("pdf")}
          disabled={selectedIds.size === 0 || downloading !== null}
        >
          {downloading === "pdf" ? (
            <><Loader2 className="w-4 h-4 mr-1 animate-spin" />Preparing…</>
          ) : (
            <><FileText className="w-4 h-4 mr-1" />Download PDF</>
          )}
        </Button>
        <Button
          size="sm"
          variant="default"
          onClick={doResend}
          disabled={selectedIds.size === 0 || resending}
        >
          {resending ? (
            <><Loader2 className="w-4 h-4 mr-1 animate-spin" />Resending…</>
          ) : (
            <><Send className="w-4 h-4 mr-1" />Resend ({selectedIds.size})</>
          )}
        </Button>
      </div>

      {loadingRecipients ? (
        <div className="flex items-center justify-center py-16 text-muted-foreground">
          <Loader2 className="w-5 h-5 animate-spin mr-2" /> Loading recipients…
        </div>
      ) : recipientsError ? (
        <Card>
          <CardContent className="py-10 text-center space-y-3">
            <p className="text-sm text-destructive">{recipientsError}</p>
            <Button variant="outline" size="sm" onClick={() => openTemplate(activeTemplate)}>Retry</Button>
          </CardContent>
        </Card>
      ) : filteredRecipients.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            {recipients.length === 0
              ? "No recipients recorded for this template yet."
              : "No recipients match your search."}
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {filteredRecipients.map((r) => {
            const selected = selectedIds.has(r.sent_id);
            return (
              <div
                key={r.sent_id}
                className={`rounded-lg border p-3 flex items-start gap-3 transition ${
                  selected ? "border-primary bg-primary/5" : "border-border bg-card"
                }`}
              >
                <Checkbox
                  className="mt-1"
                  checked={selected}
                  onCheckedChange={() => toggleOne(r.sent_id)}
                />
                <div className="w-12 h-16 rounded bg-muted overflow-hidden flex items-center justify-center shrink-0">
                  {r.rendered_card_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={r.rendered_card_url}
                      alt={r.recipient_name}
                      className="w-full h-full object-cover"
                      loading="lazy"
                    />
                  ) : (
                    <FileText className="w-5 h-5 text-muted-foreground" />
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="font-medium truncate">{r.recipient_name || "Recipient"}</p>
                    <WhatsAppBadge status={r.whatsapp_status} />
                    {r.delivery_status && r.delivery_status !== "sent" && (
                      <Badge variant="outline" className="capitalize">{r.delivery_status}</Badge>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    {r.recipient_phone || "No phone"} - {formatDate(r.sent_at)}
                  </p>
                  {r.rendered_card_url && (
                    <a
                      href={r.rendered_card_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-xs text-primary hover:underline break-all"
                    >
                      Open card
                    </a>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
      <ConfirmDialog />
    </div>
  );
}
