/**
 * EventCardsTab — organisers pick a thank-you card template, edit the text
 * fields stored per-event in event_cards.custom_text_values, preview the
 * rendered PNG, and dispatch the card to selected contributors.
 *
 * The original SVG template stays untouched on disk; only the per-event
 * overrides are persisted. The contributor name placeholder is substituted
 * server-side at delivery.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog";
import { Checkbox } from "@/components/ui/checkbox";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import SentCardsPanel from "./SentCardsPanel";
import PreparedCardsPanel from "./PreparedCardsPanel";
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent,
  DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";

import { Loader2, ChevronDown } from "lucide-react";
import {
  eventCardsApi,
  absolutizeApiUrl,
  type CardCategory,
  type CardTemplateSummary,
  type CardTemplateDetail,
  type SavedEventCard,
} from "@/lib/api/eventCards";
import { createCardRenderJob, purgeLeakedRenderHosts } from "@/lib/cards/renderCardPng";
import { useEventContributors } from "@/data/useContributors";
import { eventsApi } from "@/lib/api/events";
import type { EventGuest } from "@/lib/api/types";
import { useCurrentUser } from "@/hooks/useCurrentUser";
import QRCode from "qrcode";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";

interface Props {
  eventId: string;
}

type BatchStatus = "not_sent" | "sending" | "sent" | "partial_failure" | "failed" | "cancelled" | "renderer_stuck";

interface BatchFailure {
  recipient_id: string;
  name: string;
  reason: string;
}

interface BatchState {
  batch_no: number;
  recipient_ids: string[];
  sent_ids: string[];
  failed: BatchFailure[];
  status: BatchStatus;
  started_at?: string;
  finished_at?: string;
}

interface BatchJob {
  job_id: string;
  event_id: string;
  template_slug: string;
  batch_size: number;
  batches: BatchState[];
}

const BATCH_STORAGE_PREFIX = "nuru.cardBatchJob.";
const loadBatchJob = (jobId: string): BatchJob | null => {
  try {
    const raw = localStorage.getItem(BATCH_STORAGE_PREFIX + jobId);
    return raw ? (JSON.parse(raw) as BatchJob) : null;
  } catch { return null; }
};
const saveBatchJob = (job: BatchJob) => {
  try { localStorage.setItem(BATCH_STORAGE_PREFIX + job.job_id, JSON.stringify(job)); } catch { /* quota */ }
};

const escapeHtml = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/** Convert leading / trailing spaces into non-breaking spaces so the SVG
 *  renderer doesn't collapse them — lets the user pad text manually
 *  (e.g. "  EHEMA" to nudge the title further right). */
const preserveEdgeSpaces = (s: string) => {
  const m = s.match(/^(\s*)([\s\S]*?)(\s*)$/);
  if (!m) return s;
  const [, lead, mid, trail] = m;
  return lead.replace(/ /g, "\u00A0") + mid + trail.replace(/ /g, "\u00A0");
};

const escapeRegExp = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Re-center a text element on the canvas X axis. Supports both the
 *  matrix(...) and translate(...) transform forms emitted by Illustrator. */
const centerTextElement = (svg: string, id: string, centerX: number) => {
  const re = new RegExp(`(<(?:text|tspan)\\b[^>]*\\bid\\s*=\\s*"${escapeRegExp(id)}"[^>]*>)`, "i");
  return svg.replace(re, (open) => {
    let next = open.replace(
      /transform="matrix\(1\s+0\s+0\s+1\s+[-0-9.]+\s+([-0-9.]+)\)"/i,
      (_m, y) => `transform="matrix(1 0 0 1 ${centerX} ${y})"`,
    );
    next = next.replace(
      /transform="translate\(\s*[-0-9.]+[\s,]+([-0-9.]+)\s*\)"/i,
      (_m, y) => `transform="translate(${centerX} ${y})"`,
    );
    next = /text-anchor=/i.test(next)
      ? next.replace(/text-anchor="[^"]*"/i, 'text-anchor="middle"')
      : next.replace(/>$/, ' text-anchor="middle">');
    return next;
  });
};

/**
 * Replace the body of a multi-line `<text id="...">` element while
 * preserving the original `<tspan>`-based line geometry. The Illustrator
 * export hand-tunes each tspan's `x`/`y` (or `dy`) so the paragraph
 * looks centered between the card's decorative leaves. If we naively
 * dump the edited string in as a single line, the whole paragraph
 * collapses onto one row and overflows the card width.
 *
 * Strategy: read the original tspan count + line-height + the average
 * characters-per-line, word-wrap the new value across the same number
 * of lines (or more if the user typed a longer paragraph), and emit
 * fresh tspans that share `x="0"` so the parent `text-anchor="middle"`
 * keeps every line visually centered around the card axis.
 */
const replaceMultilineText = (svg: string, id: string, newValue: string): string => {
  const elRe = new RegExp(
    `(<text\\b[^>]*\\bid\\s*=\\s*"${escapeRegExp(id)}"[^>]*>)([\\s\\S]*?)(</text>)`,
    "i",
  );
  return svg.replace(elRe, (full, openTag: string, body: string, closeTag: string) => {
    const tspanRe = /<tspan\b([^>]*)>([\s\S]*?)<\/tspan>/gi;
    const tspans: { attrs: string; text: string }[] = [];
    let mm: RegExpExecArray | null;
    while ((mm = tspanRe.exec(body))) tspans.push({ attrs: mm[1], text: mm[2] });

    // Single-line text (no tspans, or only one) — keep the old behaviour
    // so titles/subtitles can keep their original anchor offsets.
    if (tspans.length <= 1) {
      return `${openTag}${escapeHtml(preserveEdgeSpaces(newValue))}${closeTag}`;
    }

    // Detect line height from the first two tspans (their `y` delta or `dy`).
    let lineHeight = 33.84;
    const yOf = (attrs: string) => {
      const dy = parseFloat((attrs.match(/\bdy\s*=\s*"([-0-9.]+)"/i) || [])[1] || "");
      if (!Number.isNaN(dy) && dy) return dy;
      return parseFloat((attrs.match(/\by\s*=\s*"([-0-9.]+)"/i) || [])[1] || "0");
    };
    // If every tspan shares the same vertical position (i.e. they're just
    // per-letter kerning runs from Illustrator, not separate paragraph lines),
    // treat the whole element as single-line — otherwise we'd word-wrap a
    // visually single-row title across many lines.
    const distinctYs = new Set(tspans.map((t) => Math.round(yOf(t.attrs) * 10) / 10));
    if (distinctYs.size <= 1) {
      return `${openTag}${escapeHtml(preserveEdgeSpaces(newValue))}${closeTag}`;
    }
    const y0 = yOf(tspans[0].attrs);
    const y1 = yOf(tspans[1].attrs);
    const delta = y1 - y0;
    if (Math.abs(delta) > 0.5) lineHeight = Math.abs(delta);

    // Reuse the first tspan's class so font sizing/colour stay identical.
    const klass = (tspans[0].attrs.match(/\bclass\s*=\s*"([^"]*)"/i) || [])[1] || "";
    const classAttr = klass ? ` class="${klass}"` : "";

    // Estimate the visual line width from the original wrapping so the
    // re-flow keeps the same paragraph silhouette.
    const decoded = (s: string) => s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
    const lens = tspans.map((t) => decoded(t.text).trim().length).filter((n) => n > 0);
    const avgLen = lens.length ? Math.round(lens.reduce((a, b) => a + b, 0) / lens.length) : 40;
    // Give wrapped paragraphs significantly more horizontal room than the
    // original tspan slice suggested, so longer values don't break onto a
    // new line after only a handful of characters.
    const maxLineLen = Math.max(40, Math.round(avgLen * 1.6));

    // Greedy word wrap.
    const words = newValue.replace(/\s+/g, " ").trim().split(" ").filter(Boolean);
    const lines: string[] = [];
    let cur = "";
    for (const w of words) {
      if (!cur) { cur = w; continue; }
      if ((cur + " " + w).length <= maxLineLen) cur += " " + w;
      else { lines.push(cur); cur = w; }
    }
    if (cur) lines.push(cur);
    if (!lines.length) lines.push("");

    const tspansOut = lines
      .map((ln, i) => {
        const pos = i === 0 ? 'y="0"' : `dy="${lineHeight}"`;
        return `<tspan x="0" ${pos}${classAttr}>${escapeHtml(ln)}</tspan>`;
      })
      .join("");

    return `${openTag}${tspansOut}${closeTag}`;
  });
};

const buildQrSvgGroup = (
  payload: string,
  placement?: { x: number; y: number; width: number; height: number },
): string => {
  if (!placement) return "";
  const qr = QRCode.create(payload || "NURU-PREVIEW-001", { errorCorrectionLevel: "M" });
  const moduleCount = qr.modules.size;
  const side = Math.min(placement.width, placement.height);
  const scale = side / moduleCount;
  const offsetX = (placement.width - side) / 2;
  const offsetY = (placement.height - side) / 2;
  const cells: string[] = [];
  for (let y = 0; y < moduleCount; y += 1) {
    for (let x = 0; x < moduleCount; x += 1) {
      if (!qr.modules.get(x, y)) continue;
      cells.push(`<rect x="${(offsetX + x * scale).toFixed(3)}" y="${(offsetY + y * scale).toFixed(3)}" width="${scale.toFixed(3)}" height="${scale.toFixed(3)}"/>`);
    }
  }
  return `<g id="frontend_generated_qr_code" transform="translate(${placement.x} ${placement.y})" shape-rendering="crispEdges"><rect x="0" y="0" width="${placement.width}" height="${placement.height}" fill="#FFFFFF"/> <g fill="#111111">${cells.join("")}</g></g>`;
};


/** Strip the XML declaration / DOCTYPE / Adobe Illustrator comments so the
 *  HTML parser doesn't render their trailing `]>` as visible text. */
const sanitizeSvg = (raw: string) =>
  raw
    .replace(/<\?xml[\s\S]*?\?>/i, "")
    .replace(/<!DOCTYPE[\s\S]*?\]>/i, "")
    .replace(/<!DOCTYPE[^>]*>/i, "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .trim();

/** Apply edits + contributor name + absolute font URLs in the browser so the
 *  preview is instant and doesn't require an authenticated PNG round-trip.
 *  IMPORTANT: only fields the user actually changed (i.e. that differ from the
 *  template default) are touched — otherwise we'd collapse the original
 *  multi-tspan wrapping that the designer hand-tuned in Illustrator. */
function buildPreviewSvg(
  rawSvg: string,
  slug: string,
  edits: Record<string, string>,
  defaults: Record<string, string>,
  contributorPlaceholderId: string | undefined,
  contributorName: string,
  fonts: string[] = [],
  opts: { preserveTextPositions?: boolean; replaceDefaultsInPreview?: boolean; qrPlacement?: { x: number; y: number; width: number; height: number }; qrPayload?: string; viewBox?: { width: number; height: number } } = {},
): string {
  let svg = sanitizeSvg(rawSvg);
  // Derive centerX from the SVG's own viewBox so cards with non-A4 canvases
  // (e.g. thank-you uses 1122x1402) don't get every text element re-centered
  // to the wrong X and pushed off the frame.
  let intrinsicWidth: number | undefined;
  const vbMatch = svg.match(/viewBox\s*=\s*"\s*[-\d.]+\s+[-\d.]+\s+([\d.]+)\s+([\d.]+)\s*"/i);
  if (vbMatch) intrinsicWidth = parseFloat(vbMatch[1]);
  const centerX = (opts.viewBox?.width ?? intrinsicWidth ?? 595.28) / 2;

  Object.entries(edits).forEach(([id, val]) => {
    const def = defaults[id] ?? "";
    if (!opts.replaceDefaultsInPreview && (val ?? "") === def) return;
    // Multi-tspan paragraphs need word-wrap into the same line geometry,
    // otherwise the whole paragraph collapses onto one line and overflows.
    // Single-line titles fall through replaceMultilineText's fast path.
    svg = replaceMultilineText(svg, id, val ?? "");
  });
  if (contributorPlaceholderId && contributorName) {
    svg = replaceMultilineText(svg, contributorPlaceholderId, contributorName);
  }
  if (fonts.length) {
    // Emit @font-face under several family-name aliases so SVGs authored in
    // Illustrator (which strips spaces — e.g. font-family="AnthonyHunter")
    // resolve the same file as ones that keep the spaced family name.
    const faceBlocks = fonts.map((f) => {
      const url = absolutizeApiUrl(`/api/v1/cards/templates/${slug}/asset/${encodeURIComponent(f)}`);
      svg = svg.replace(new RegExp(`url\\((['"]?)${escapeRegExp(f)}\\1\\)`, "g"), `url('${url}')`);
      const isItalic = /italic/i.test(f);
      const isCollection = /sitka/i.test(f);
      const bare = f.replace(/\.(ttf|otf|woff2?|eot)$/i, "");
      const spaced = bare.replace(/\s*Italic\s*$/i, "").trim();
      const squashed = spaced.replace(/\s+/g, "");
      const format = isCollection ? "collection" : /\.otf$/i.test(f) ? "opentype" : /\.woff2$/i.test(f) ? "woff2" : /\.woff$/i.test(f) ? "woff" : "truetype";
      const families = Array.from(new Set([spaced, squashed]));
      return families.map((fam) =>
        `@font-face{font-family:'${fam}';src:url('${url}') format('${format}');font-weight:400;font-style:${isItalic ? "italic" : "normal"};font-display:swap;}`
      ).join("");
    }).join("");
    svg = svg.replace(/<\/svg>\s*$/i, `<style>${faceBlocks}</style></svg>`);
  }
  const qrGroup = buildQrSvgGroup(opts.qrPayload || "NURU-PREVIEW-001", opts.qrPlacement);
  if (qrGroup) {
    svg = svg.replace(/<g\s+id="frontend_generated_qr_code"[\s\S]*?<\/g>/i, "");
    svg = svg.replace(/<\/svg>\s*$/i, `${qrGroup}</svg>`);
  }
  if (!opts.preserveTextPositions) {
    // Center every editable text node + the contributor placeholder so wrapped
    // or long values stay visually balanced on legacy cards.
    Object.keys(defaults).forEach((id) => { svg = centerTextElement(svg, id, centerX); });
  }
  // Always center the contributor name — guests can be very long or short and
  // a left-anchored placeholder would visibly drift across the card.
  if (contributorPlaceholderId) {
    svg = centerTextElement(svg, contributorPlaceholderId, centerX);
  }
  return svg;
}

/** Inline-SVG thumbnail for the template gallery so the contributor name
 *  shows the current user and @font-face URLs resolve absolutely. */
function TemplateThumb({ slug, contributorName }: { slug: string; contributorName: string }) {
  const [markup, setMarkup] = useState<string>("");
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const res = await eventCardsApi.getTemplate(slug);
        if (!alive) return;
        const detail = res.data;
        if (!detail) return;
        const defaults: Record<string, string> = {};
        (detail.metadata.editable_fields || []).forEach((f) => { defaults[f.id] = f.default ?? ""; });
        const svg = buildPreviewSvg(
          detail.svg,
          detail.slug,
          {},
          defaults,
          detail.metadata.contributor_placeholder_id,
          contributorName,
          detail.metadata.fonts || [],
          {
            preserveTextPositions: detail.metadata.preserve_text_positions,
            replaceDefaultsInPreview: detail.metadata.replace_defaults_in_preview,
            qrPlacement: detail.metadata.qr_placement,
            qrPayload: "NURU-PREVIEW-001",
            viewBox: (detail.metadata as any)?.view_box,
          },
        );
        setMarkup(svg);
      } catch {
        /* ignore — fallback to blank */
      }
    })();
    return () => { alive = false; };
  }, [slug, contributorName]);
  if (!markup) return <div className="w-full h-full bg-muted animate-pulse" />;
  return (
    <div
      className="w-full h-full [&>svg]:w-full [&>svg]:h-full [&>svg]:object-cover"
      dangerouslySetInnerHTML={{ __html: markup }}
    />
  );
}

export default function EventCardsTab({ eventId }: Props) {
  const { confirm, ConfirmDialog } = useConfirmDialog();
  const [categories, setCategories] = useState<CardCategory[]>([]);
  const [activeCategory, setActiveCategory] = useState<string>("");
  const [templates, setTemplates] = useState<CardTemplateSummary[]>([]);
  const [savedCard, setSavedCard] = useState<SavedEventCard | null>(null);
  const [activeTemplate, setActiveTemplate] = useState<CardTemplateDetail | null>(null);
  const [values, setValues] = useState<Record<string, string>>({});
  const [loadingCats, setLoadingCats] = useState(true);
  const [loadingTpl, setLoadingTpl] = useState(false);
  const [saving, setSaving] = useState(false);
  const [previewBust, setPreviewBust] = useState(0);
  const [sendOpen, setSendOpen] = useState(false);
  const [sendStep, setSendStep] = useState<"pick" | "batches">("pick");
  const [batchSize, setBatchSize] = useState<number>(10);
  const [batches, setBatches] = useState<BatchState[]>([]);
  const [activeBatchNo, setActiveBatchNo] = useState<number | null>(null);
  const [activeBatchProgress, setActiveBatchProgress] = useState<
    | {
        done: number;
        total: number;
        prepared: number;
        uploaded: number;
        failed: number;
        currentName?: string;
        avgMs?: number;
        etaMs?: number;
        phase: "preparing" | "sending" | "done";
      }
    | null
  >(null);
  const cancelRef = useRef<boolean>(false);
  const [contributorSearch, setContributorSearch] = useState("");
  const [selectedContributorIds, setSelectedContributorIds] = useState<Set<string>>(new Set());
  // Recipient ids hidden from the picker because the user chose "only those
  // not prepared/sent yet". Populated by openSend when mode === "skip_existing".
  const [excludedRecipientIds, setExcludedRecipientIds] = useState<Set<string>>(new Set());
  const [excludedReason, setExcludedReason] = useState<"prepared" | "sent" | null>(null);

  const { eventContributors, refetch: fetchEventContributors } = useEventContributors(eventId);
  const [eventGuests, setEventGuests] = useState<EventGuest[]>([]);
  const [loadingGuests, setLoadingGuests] = useState(false);
  const initialFetched = useRef(false);
  const guestsFetched = useRef(false);
  const { data: currentUser } = useCurrentUser();
  const currentUserName = useMemo(() => {
    const fn = (currentUser?.first_name || "").trim();
    const ln = (currentUser?.last_name || "").trim();
    return [fn, ln].filter(Boolean).join(" ") || currentUser?.username || "";
  }, [currentUser]);

  // ── Audience derived from the active template metadata. Invitation
  //    cards target the event guest list; thank-you cards target pledging
  //    contributors. Defaults to "contributors" for backward compat.
  const recipientNounRaw: string = activeTemplate?.metadata?.recipient_noun || "Contributor";
  const recipientNounLower = recipientNounRaw.toLowerCase();
  const recipientNounPlural = `${recipientNounLower}s`;
  // Audience is driven by either an explicit `recipient_source` or inferred
  // from `recipient_noun` (e.g. "Guest" → guests). This keeps older templates
  // that only set `recipient_noun` working without an extra metadata field.
  const audience: "contributors" | "guests" =
    (activeTemplate?.metadata?.recipient_source as "contributors" | "guests" | undefined) ||
    (recipientNounLower === "guest" ? "guests" : "contributors");

  const fetchEventGuests = useCallback(async () => {
    setLoadingGuests(true);
    try {
      let all: EventGuest[] = [];
      let page = 1;
      while (true) {
        const res: any = await eventsApi.getGuests(eventId, { page, limit: 200 });
        if (res?.success) {
          all = [...all, ...(res.data?.guests || [])];
          const tp = res.data?.pagination?.total_pages || 1;
          if (page >= tp) break;
          page += 1;
        } else break;
      }
      setEventGuests(all);
    } catch (e: any) {
      toast({ title: "Could not load guests", description: e?.message, variant: "destructive" });
    } finally {
      setLoadingGuests(false);
    }
  }, [eventId]);


  // ── Load categories ────────────────────────────────────────────────
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const res = await eventCardsApi.listCategories();
        if (!alive) return;
        const cats = res.data?.categories || [];
        setCategories(cats);
        if (cats.length && !activeCategory) setActiveCategory(cats[0].category);
      } catch (e: any) {
        toast({ title: "Could not load card categories", description: e?.message, variant: "destructive" });
      } finally {
        if (alive) setLoadingCats(false);
      }
    })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── Load templates + the event's saved card for the active category
  useEffect(() => {
    if (!activeCategory || !eventId) return;
    let alive = true;
    (async () => {
      setLoadingTpl(true);
      try {
        const [tplRes, savedRes] = await Promise.all([
          eventCardsApi.listTemplates(activeCategory),
          eventCardsApi.listEventCards(eventId),
        ]);
        if (!alive) return;
        const tpls = tplRes.data?.templates || [];
        setTemplates(tpls);
        const mine = (savedRes.data?.event_cards || []).find((c) => c.category === activeCategory) || null;
        setSavedCard(mine);
        // Decide which template to load into the editor
        const slug = mine?.card_template_slug || tpls[0]?.slug;
        if (slug) {
          const detail = await eventCardsApi.getTemplate(slug);
          if (!alive) return;
          setActiveTemplate(detail.data || null);
          const editable = detail.data?.metadata?.editable_fields || [];
          const seed: Record<string, string> = {};
          editable.forEach((f) => {
            const saved = (mine?.custom_text_values || {})[f.id];
            seed[f.id] = saved !== undefined && saved !== "" ? saved : (f.default ?? "");
          });
          setValues(seed);
        } else {
          setActiveTemplate(null);
          setValues({});
        }
      } catch (e: any) {
        toast({ title: "Could not load templates", description: e?.message, variant: "destructive" });
      } finally {
        if (alive) setLoadingTpl(false);
      }
    })();
    return () => { alive = false; };
  }, [activeCategory, eventId]);

  const pickTemplate = useCallback(async (slug: string) => {
    setLoadingTpl(true);
    try {
      const detail = await eventCardsApi.getTemplate(slug);
      const editable = detail.data?.metadata?.editable_fields || [];
      // Keep existing values when switching templates if the field id matches;
      // otherwise fall back to the template's default for that field.
      const seed: Record<string, string> = {};
      editable.forEach((f) => {
        const existing = values[f.id];
        seed[f.id] = existing !== undefined && existing !== "" ? existing : (f.default ?? "");
      });
      setActiveTemplate(detail.data || null);
      setValues(seed);
    } catch (e: any) {
      toast({ title: "Could not load template", description: e?.message, variant: "destructive" });
    } finally {
      setLoadingTpl(false);
    }
  }, [values]);

  const persistActiveCard = useCallback(
    async ({ silent = false }: { silent?: boolean } = {}) => {
      if (!activeTemplate || !activeCategory) return null;
      setSaving(true);
      try {
        const res = await eventCardsApi.saveEventCard(eventId, {
          category: activeCategory,
          card_template_id: activeTemplate.id,
          card_template_slug: activeTemplate.slug,
          custom_text_values: values,
        });
        const nextSavedCard = res.data || null;
        setSavedCard(nextSavedCard);
        setPreviewBust(Date.now());
        if (!silent) {
          toast({ title: "Card saved", description: "Your changes are now live for this event." });
        }
        return nextSavedCard;
      } catch (e: any) {
        toast({ title: "Could not save", description: e?.message, variant: "destructive" });
        return null;
      } finally {
        setSaving(false);
      }
    },
    [activeTemplate, activeCategory, eventId, values],
  );

  const onSave = useCallback(async () => {
    await persistActiveCard();
  }, [persistActiveCard]);

  const currentJobId = useMemo(
    () => (activeTemplate?.slug ? `${eventId}-${activeTemplate.slug}` : ""),
    [eventId, activeTemplate?.slug],
  );

  // When true, the batch flow stages the rendered cards on the Prepared
  // Cards tab instead of dispatching them via WhatsApp/SMS immediately.
  const prepareModeRef = useRef(false);
  const [prepareModeUi, setPrepareModeUi] = useState(false);

  // Duplicate handling for the upcoming send/prepare batch:
  //   "fresh"          → resend / re-prepare for every selected recipient
  //                      (default — matches the previous behaviour).
  //   "skip_existing"  → silently drop anyone already sent/prepared. The
  //                      backend enforces this so a previously prepared
  //                      card keeps its stable URL untouched.
  const sendModeRef = useRef<"fresh" | "skip_existing">("fresh");

  const openSend = useCallback(async (opts: { prepareOnly?: boolean; mode?: "fresh" | "skip_existing" } = {}) => {
    const prepareOnly = !!opts.prepareOnly;
    const mode = opts.mode || "fresh";
    prepareModeRef.current = prepareOnly;
    setPrepareModeUi(prepareOnly);
    sendModeRef.current = mode;
    let activeSavedCard = savedCard;

    if (audience === "guests" && !activeSavedCard) {
      activeSavedCard = await persistActiveCard({ silent: true });
    }

    if (!activeSavedCard) {
      toast({ title: "Save the card first", description: "Configure and save the card before sending." });
      return;
    }
    if (audience === "guests") {
      if (!guestsFetched.current) { fetchEventGuests(); guestsFetched.current = true; }
    } else if (!initialFetched.current) { fetchEventContributors(); initialFetched.current = true; }
    setSelectedContributorIds(new Set());
    setContributorSearch("");

    // ── Pre-filter for "Only those not prepared / not sent yet" ──
    // The backend already enforces skip_existing at dispatch time, but the
    // picker should also reflect that choice so the user sees (and confirms)
    // ONLY the remaining recipients — not the full list. The exclusion set
    // is CATEGORY-scoped (one backend call), matching the backend's
    // skip_existing filter exactly — template ids are deliberately ignored
    // because switching templates within a category must not reset who
    // already has a card.
    setExcludedRecipientIds(new Set());
    setExcludedReason(null);
    if (mode === "skip_existing" && activeCategory) {
      try {
        const res = await eventCardsApi.getCardRecipientStatus(eventId, activeCategory);
        const ids = prepareOnly ? res.data?.prepared_ids || [] : res.data?.sent_ids || [];
        setExcludedRecipientIds(new Set(ids));
        setExcludedReason(prepareOnly ? "prepared" : "sent");
      } catch (err) {
        // Non-fatal — backend will still enforce skip_existing on submit.
        console.warn("[cards] skip_existing pre-filter failed", err);
      }
    }

    // Resume any saved job for this template (so refresh keeps the report)
    const existing = currentJobId ? loadBatchJob(currentJobId) : null;
    if (existing && existing.batches.length > 0) {
      setBatches(existing.batches);
      setBatchSize(existing.batch_size);
      setSendStep("batches");
    } else {
      setBatches([]);
      setSendStep("pick");
    }
    setSendOpen(true);
  }, [savedCard, audience, persistActiveCard, fetchEventContributors, fetchEventGuests, currentJobId, eventId, activeCategory]);


  const toggleContributor = (id: string) => {
    setSelectedContributorIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  // Unified recipient list driven by `audience`. Each entry has the same
  // shape so the picker UI doesn't have to branch.
  type Recipient = { id: string; name: string; phone: string; subtitle?: string; qrPayload?: string };
  const eligibleContributors: Recipient[] = useMemo(() => {
    let list: Recipient[];
    if (audience === "guests") {
      const allowed = new Set(
        (activeTemplate?.metadata?.recipient_filter as string[] | undefined) || ["pending", "confirmed", "maybe"],
      );
      list = eventGuests
        .filter((g) => allowed.has(String(g.rsvp_status)))
        .map((g) => ({
          id: g.id,
          name: g.name || "Guest",
          phone: g.phone || "",
          subtitle: g.rsvp_status,
          qrPayload: (g as any).qr_payload || g.id,
        }));
    } else {
      list = eventContributors
        .filter((ec) => Number(ec.pledge_amount || 0) > 0)
        .map((ec) => ({ id: ec.id, name: ec.contributor?.name || "Unnamed", phone: ec.contributor?.phone || "" }));
    }
    // Hide anyone the user told us to skip ("Only those not prepared/sent yet").
    if (excludedRecipientIds.size > 0) {
      list = list.filter((r) => !excludedRecipientIds.has(r.id));
    }
    return list;
  }, [audience, eventGuests, eventContributors, activeTemplate?.metadata?.recipient_filter, excludedRecipientIds]);

  // Pre-tick every remaining recipient when the user chose "Only those not
  // prepared/sent yet" — saves them from re-selecting after we shrink the list.
  useEffect(() => {
    if (!sendOpen || sendStep !== "pick" || !excludedReason) return;
    if (eligibleContributors.length === 0) return;
    setSelectedContributorIds((prev) => {
      if (prev.size > 0) return prev; // user already touched the list
      return new Set(eligibleContributors.map((r) => r.id));
    });
  }, [sendOpen, sendStep, excludedReason, eligibleContributors]);

  const filteredContributors = useMemo(() => {
    const q = contributorSearch.trim().toLowerCase();
    if (!q) return eligibleContributors;
    return eligibleContributors.filter(
      (r) => r.name.toLowerCase().includes(q) || r.phone.toLowerCase().includes(q),
    );
  }, [eligibleContributors, contributorSearch]);


  const allFilteredSelected =
    filteredContributors.length > 0 &&
    filteredContributors.every((ec) => selectedContributorIds.has(ec.id));

  const toggleSelectAllFiltered = () => {
    setSelectedContributorIds((prev) => {
      const next = new Set(prev);
      if (allFilteredSelected) {
        filteredContributors.forEach((ec) => next.delete(ec.id));
      } else {
        filteredContributors.forEach((ec) => next.add(ec.id));
      }
      return next;
    });
  };

  // Build batches from the currently selected contributors and move to step 2.
  const continueToBatches = useCallback(() => {
    if (selectedContributorIds.size === 0 || !activeTemplate?.slug) return;
    const ids = Array.from(selectedContributorIds);
    const size = Math.max(1, batchSize);
    const newBatches: BatchState[] = [];
    for (let i = 0; i < ids.length; i += size) {
      newBatches.push({
        batch_no: newBatches.length + 1,
        recipient_ids: ids.slice(i, i + size),
        sent_ids: [],
        failed: [],
        status: "not_sent",
      });
    }
    setBatches(newBatches);
    if (currentJobId) {
      saveBatchJob({
        job_id: currentJobId,
        event_id: eventId,
        template_slug: activeTemplate.slug,
        batch_size: size,
        batches: newBatches,
      });
    }
    setSendStep("batches");
  }, [selectedContributorIds, batchSize, activeTemplate?.slug, currentJobId, eventId]);

  const persistBatches = useCallback(
    (next: BatchState[]) => {
      setBatches(next);
      if (!currentJobId || !activeTemplate?.slug) return;
      saveBatchJob({
        job_id: currentJobId,
        event_id: eventId,
        template_slug: activeTemplate.slug,
        batch_size: batchSize,
        batches: next,
      });
    },
    [currentJobId, activeTemplate?.slug, eventId, batchSize],
  );

  // Render + upload + send a specific set of recipient ids. Used for both
  // initial batch sends and "retry failed" — keeps the proven single-flow
  // pipeline; only the input list changes.
  //
  // Performance design:
  //   - Build the template SVG ONCE per call with a unique token in place
  //     of the contributor name. Fonts get inlined once via the reusable
  //     render job, document.fonts.ready waited on once, and a single
  //     off-screen DOM host is reused for every recipient.
  //   - Per recipient: swap the token, capture to JPEG, upload, release.
  //   - Default concurrency is 1: canvas rasterisation is CPU heavy and
  //     parallel canvases starve the UI thread. Two workers occasionally
  //     produce smeared output on older devices.
  const prepareAndSendIds = useCallback(
    async (
      ids: string[],
      opts: { batchNo: number; mode?: "normal" | "safe" } = { batchNo: 0 },
    ): Promise<{ sentIds: string[]; failed: BatchFailure[]; rendererStuck: boolean; unattempted: string[] }> => {
      const mode = opts.mode ?? "normal";
      const batchNo = opts.batchNo;
      if (!activeTemplate?.svg || !activeCategory) {
        return { sentIds: [], failed: ids.map((id) => ({ recipient_id: id, name: "", reason: "Template not ready" })), rendererStuck: false, unattempted: [] };
      }

      const idToName: Record<string, string> = {};
      const idToQrPayload: Record<string, string> = {};
      eligibleContributors.forEach((r) => {
        if (ids.includes(r.id)) {
          idToName[r.id] = r.name || (audience === "guests" ? "Guest" : "Friend");
          if (audience === "guests") {
            // Each guest needs their own QR baked into their SVG. Falls back
            // to the attendee id, which the backend also accepts.
            idToQrPayload[r.id] = r.qrPayload || r.id;
          }
        }
      });

      const isGuestRun = audience === "guests";

      const meta = activeTemplate.metadata || {};
      const defaults: Record<string, string> = {};
      (meta.editable_fields || []).forEach((f) => { defaults[f.id] = f.default ?? ""; });
      const placeholderId = meta.contributor_placeholder_id || "contributor_name_text";


      const NAME_TOKEN = "__NURU_NAME_TOKEN_7F3A__";
      // For contributor/thank-you cards the same QR (preview payload) is fine
      // across the whole batch, so we build the SVG once. Invitation cards
      // need a per-guest QR baked in — we'll rebuild per recipient below.
      const buildSvgFor = (qrPayload: string) =>
        buildPreviewSvg(
          activeTemplate.svg,
          activeTemplate.slug,
          values,
          defaults,
          placeholderId,
          NAME_TOKEN,
          meta.fonts || [],
          {
            preserveTextPositions: meta.preserve_text_positions,
            replaceDefaultsInPreview: meta.replace_defaults_in_preview,
            qrPlacement: meta.qr_placement,
            qrPayload,
            viewBox: (meta as any)?.view_box,
          },
        );
      const preparedTemplateSvg = isGuestRun
        ? buildSvgFor(idToQrPayload[ids[0]] || ids[0] || "NURU-PREVIEW-001")
        : buildSvgFor("NURU-PREVIEW-001");

      const TIMEOUT_MS = 30_000;
      const RENDER_OPTS = {
        width: 1080,
        pixelRatio: mode === "safe" ? 1 : 1,
        mimeType: "image/png" as const,
        quality: 0.92,
        timeoutMs: TIMEOUT_MS,
      };

      // Build one shared job for normal mode; safe mode (and invitation
      // cards, which need a per-guest QR baked in) rebuilds per recipient.
      let sharedJob: Awaited<ReturnType<typeof createCardRenderJob>> | null = null;
      const buildJob = async (svgOverride?: string) =>
        createCardRenderJob(svgOverride ?? preparedTemplateSvg, RENDER_OPTS);

      // Preflight render — confirm the renderer can produce at least one card
      // before we mark the whole batch as failed.
      try {
        const preflight = await buildJob();
        try {
          const firstName = idToName[ids[0]] || (isGuestRun ? "Guest" : "Friend");
          await preflight.render({ token: NAME_TOKEN, value: firstName });
          if (mode === "normal" && !isGuestRun) sharedJob = preflight; else preflight.dispose();
        } catch (e: any) {
          preflight.dispose();
          purgeLeakedRenderHosts();
          if (import.meta.env.DEV) {
            console.warn(`[card_renderer_preflight_failed] batch=${batchNo} reason=${e?.message || e}`);
          }
          return { sentIds: [], failed: [], rendererStuck: true, unattempted: ids };
        }
      } catch (e: any) {
        return {
          sentIds: [],
          failed: ids.map((id) => ({
            recipient_id: id,
            name: idToName[id] || "Friend",
            reason: `Template prep failed: ${e?.message || e}`,
          })),
          rendererStuck: false,
          unattempted: [],
        };
      }

      const failed: BatchFailure[] = [];
      const preRendered: Record<string, string> = {};
      const total = ids.length;
      const timings: number[] = [];
      let done = 0;
      let prepared = 0;
      let uploaded = 0;
      let consecutiveTimeouts = 0;
      let rendererStuck = false;
      let stuckAtIndex = ids.length;

      const updateProgress = (currentName?: string, phase: "preparing" | "sending" = "preparing") => {
        const avgMs = timings.length ? timings.reduce((a, b) => a + b, 0) / timings.length : undefined;
        const remaining = Math.max(0, total - done);
        const etaMs = avgMs ? avgMs * remaining : undefined;
        setActiveBatchProgress({ done, total, prepared, uploaded, failed: failed.length, currentName, avgMs, etaMs, phase });
      };
      updateProgress();

      try {
        for (let i = 0; i < ids.length; i++) {
          if (cancelRef.current) { stuckAtIndex = i; break; }
          const id = ids[i];
          const name = idToName[id] || (isGuestRun ? "Guest" : "Friend");
          updateProgress(name);
          const tStart = performance.now();
          let renderMs = 0;
          let uploadMs = 0;
          let sizeKb = 0;
          let timedOut = false;
          let cleanupOk = true;

          if (import.meta.env.DEV) console.log(`[card_prepare_start] batch=${batchNo} recipient=${name}`);

          // Per-recipient job for safe mode (full cleanup between cards) and
          // for guest invitations (each guest's QR is baked into its own SVG).
          let job = sharedJob;
          try {
            if (mode === "safe") {
              job = await buildJob();
            } else if (isGuestRun) {
              const guestSvg = buildSvgFor(idToQrPayload[id] || id);
              job = await buildJob(guestSvg);
            }
            if (!job) throw new Error("Render job not initialised");

            if (import.meta.env.DEV) console.log(`[card_prepare_stage] batch=${batchNo} recipient=${name} stage=render_canvas`);
            const tRender = performance.now();
            const blob = await job.render({ token: NAME_TOKEN, value: name });
            renderMs = performance.now() - tRender;
            sizeKb = Math.round(blob.size / 1024);
            prepared += 1;

            if (import.meta.env.DEV) console.log(`[card_prepare_stage] batch=${batchNo} recipient=${name} stage=upload`);
            const tUp = performance.now();
            const file = new File([blob], `card-${id}.png`, { type: blob.type || "image/png" });
            const res = await eventCardsApi.uploadRenderedCard(eventId, activeCategory, id, file);
            uploadMs = performance.now() - tUp;
            const url = res.data?.url;
            if (!url) throw new Error("Upload returned no URL");
            preRendered[id] = url;
            uploaded += 1;
            consecutiveTimeouts = 0;
          } catch (e: any) {
            const msg: string = e?.message || "Render/upload failed";
            timedOut = /timed out/i.test(msg);
            const reason = timedOut
              ? "Rendering took too long. Try Safe retry or a smaller batch."
              : msg;
            failed.push({ recipient_id: id, name, reason });
            if (timedOut) {
              consecutiveTimeouts += 1;
              if (import.meta.env.DEV) {
                console.warn(
                  `[card_prepare_timeout] batch=${batchNo} recipient=${name} timeoutMs=${TIMEOUT_MS} stage=render_canvas cleanupOk=${cleanupOk}`,
                );
              }
            } else {
              consecutiveTimeouts = 0;
            }
          } finally {
            // Per-recipient cleanup (always for safe mode; on timeout for normal).
            // Per-recipient cleanup (always for safe mode and guest runs;
            // on timeout for normal contributor mode).
            if (mode === "safe" || isGuestRun || timedOut) {
              try {
                if ((mode === "safe" || isGuestRun) && job) job.dispose();
                if (timedOut && mode === "normal" && sharedJob) {
                  sharedJob.dispose();
                  sharedJob = null;
                }
                purgeLeakedRenderHosts();
                await new Promise((r) => requestAnimationFrame(() => r(null)));
                await new Promise((r) => setTimeout(r, mode === "safe" ? 300 : 150));
                if (import.meta.env.DEV) console.log(`[card_prepare_cleanup] batch=${batchNo} recipient=${name} ok=true`);
              } catch {
                cleanupOk = false;
              }
            }

            const totalMs = performance.now() - tStart;
            timings.push(totalMs);
            done += 1;
            if (import.meta.env.DEV) {
              console.log(
                `[card_prepare_done] batch=${batchNo} recipient=${name} renderMs=${Math.round(renderMs)} uploadMs=${Math.round(uploadMs)} totalMs=${Math.round(totalMs)} sizeKb=${sizeKb}`,
              );
            }
            updateProgress(name);
          }

          // Detect stuck renderer: 3 consecutive timeouts → stop batch.
          if (consecutiveTimeouts >= 3) {
            rendererStuck = true;
            stuckAtIndex = i + 1;
            if (import.meta.env.DEV) {
              console.warn(`[card_renderer_stuck] batch=${batchNo} consecutiveTimeouts=3 action=stop_batch`);
            }
            break;
          }

          // For normal contributor mode: rebuild the shared job if it was
          // disposed on a timeout. Guest runs never use the shared job.
          if (mode === "normal" && !isGuestRun && !sharedJob) {
            try { sharedJob = await buildJob(); } catch { rendererStuck = true; break; }
          }
        }
      } finally {
        if (sharedJob) sharedJob.dispose();
        purgeLeakedRenderHosts();
      }

      const unattempted = rendererStuck ? ids.slice(stuckAtIndex) : [];
      // Remove failures that were actually unattempted (shouldn't happen, defensive).
      const attemptedFailed = failed.filter((f) => !unattempted.includes(f.recipient_id));

      const preparedIds = Object.keys(preRendered);
      if (preparedIds.length === 0) {
        return { sentIds: [], failed: attemptedFailed, rendererStuck, unattempted };
      }
      updateProgress(undefined, "sending");
      try {
        const prepareOnly = prepareModeRef.current;
        const dispatchMode = sendModeRef.current;
        if (isGuestRun) {
          if (prepareOnly) {
            await eventCardsApi.prepareForGuests(eventId, activeCategory, preparedIds, preRendered, dispatchMode);
          } else {
            await eventCardsApi.sendToGuests(eventId, activeCategory, preparedIds, preRendered, dispatchMode);
          }
        } else {
          if (prepareOnly) {
            await eventCardsApi.prepareForContributors(eventId, activeCategory, preparedIds, preRendered, dispatchMode);
          } else {
            await eventCardsApi.sendToContributors(eventId, activeCategory, preparedIds, preRendered, dispatchMode);
          }
        }
        return { sentIds: preparedIds, failed: attemptedFailed, rendererStuck, unattempted };
      } catch (e: any) {
        const reason = e?.message || (prepareModeRef.current ? "Prepare request failed" : "Send request failed");
        preparedIds.forEach((id) => attemptedFailed.push({ recipient_id: id, name: idToName[id] || (isGuestRun ? "Guest" : "Friend"), reason }));
        return { sentIds: [], failed: attemptedFailed, rendererStuck, unattempted };
      }
    },

    [activeTemplate, activeCategory, eventId, values, eligibleContributors, audience],
  );

  const sendBatch = useCallback(
    async (batchNo: number, opts: { retryOnly?: boolean; mode?: "normal" | "safe" } = {}) => {
      const target = batches.find((b) => b.batch_no === batchNo);
      if (!target) return;
      const alreadySent = new Set(target.sent_ids);
      const failedIds = new Set(target.failed.map((f) => f.recipient_id));
      // Safe mode includes failed + pending (everything not already sent).
      // Normal "Retry failed only" includes just failed entries.
      const ids = opts.retryOnly && opts.mode !== "safe"
        ? target.recipient_ids.filter((id) => failedIds.has(id) && !alreadySent.has(id))
        : target.recipient_ids.filter((id) => !alreadySent.has(id));
      if (ids.length === 0) {
        toast({ title: "Nothing to send", description: "All recipients in this batch are already sent." });
        return;
      }
      cancelRef.current = false;
      setActiveBatchNo(batchNo);
      setActiveBatchProgress({ done: 0, total: ids.length, prepared: 0, uploaded: 0, failed: 0, phase: "preparing" });
      const started_at = new Date().toISOString();
      persistBatches(batches.map((b) => (b.batch_no === batchNo ? { ...b, status: "sending", started_at } : b)));
      try {
        const { sentIds, failed, rendererStuck, unattempted } = await prepareAndSendIds(ids, { batchNo, mode: opts.mode });
        const finished_at = new Date().toISOString();
        const unattemptedSet = new Set(unattempted);
        const next = batches.map((b) => {
          if (b.batch_no !== batchNo) return b;
          const newSent = Array.from(new Set([...b.sent_ids, ...sentIds]));
          const retainedFailures = b.failed.filter((f) => !sentIds.includes(f.recipient_id) && !unattemptedSet.has(f.recipient_id));
          const mergedFailures = [
            ...retainedFailures.filter((f) => !failed.some((g) => g.recipient_id === f.recipient_id)),
            ...failed,
          ];
          let status: BatchStatus;
          if (rendererStuck) status = "renderer_stuck";
          else if (cancelRef.current && newSent.length < b.recipient_ids.length) status = "cancelled";
          else if (newSent.length === b.recipient_ids.length) status = "sent";
          else if (newSent.length > 0) status = "partial_failure";
          else status = "failed";
          return { ...b, sent_ids: newSent, failed: mergedFailures, status, started_at, finished_at };
        });
        persistBatches(next);
        if (rendererStuck) {
          toast({
            title: `Batch ${batchNo} stopped`,
            description: "Rendering appears stuck. We stopped this batch to protect your browser. Reset renderer and retry remaining in Safe mode.",
            variant: "destructive",
          });
        } else {
          toast({
            title: `Batch ${batchNo} ${cancelRef.current ? "cancelled" : "completed"}`,
            description: `${sentIds.length} sent, ${failed.length} failed`,
          });
        }
      } catch (e: any) {
        toast({ title: "Batch failed", description: e?.message, variant: "destructive" });
      } finally {
        cancelRef.current = false;
        setActiveBatchNo(null);
        setActiveBatchProgress(null);
      }
    },
    [batches, persistBatches, prepareAndSendIds],
  );

  const resetRenderer = useCallback(() => {
    const removed = purgeLeakedRenderHosts();
    if (import.meta.env.DEV) console.log(`[card_renderer_reset] ok=true removedHosts=${removed}`);
    toast({ title: "Renderer reset", description: "Hidden render host cleared. You can retry now." });
  }, []);

  const cancelActiveBatch = useCallback(() => { cancelRef.current = true; }, []);

  const goBackToPick = useCallback(() => {
    setSendStep("pick");
  }, []);


  const previewSvgMarkup = useMemo(() => {
    if (!activeTemplate?.svg) return null;
    const meta = activeTemplate.metadata || {};
    const defaults: Record<string, string> = {};
    (meta.editable_fields || []).forEach((f) => { defaults[f.id] = f.default ?? ""; });
    const prefix = (values["__guest_name_prefix"] ?? "").trim();
    const previewName = prefix ? `${prefix} ${currentUserName}` : currentUserName;
    return buildPreviewSvg(
      activeTemplate.svg,
      activeTemplate.slug,
      values,
      defaults,
      meta.contributor_placeholder_id || "contributor_name_text",
      previewName,
      meta.fonts || [],
      {
        preserveTextPositions: meta.preserve_text_positions,
        replaceDefaultsInPreview: meta.replace_defaults_in_preview,
        qrPlacement: meta.qr_placement,
        qrPayload: "NURU-PREVIEW-001",
            viewBox: (meta as any)?.view_box,
      },
    );
  }, [activeTemplate, values, currentUserName]);

  // ── Render ────────────────────────────────────────────────────────
  if (loadingCats) {
    return (
      <div className="flex items-center justify-center py-24 text-muted-foreground">
        <Loader2 className="w-5 h-5 animate-spin mr-2" /> Loading cards…
      </div>
    );
  }

  if (categories.length === 0) {
    return (
      <Card>
        <CardContent className="py-12 text-center text-muted-foreground text-sm">
          No card templates are available yet.
        </CardContent>
      </Card>
    );
  }

  const editable = activeTemplate?.metadata?.editable_fields || [];
  const lockedIds = new Set(activeTemplate?.metadata?.locked_ids || []);

  return (
    <>
    <ConfirmDialog />
    <Tabs defaultValue="templates" className="space-y-4">
      <TabsList>
        <TabsTrigger value="templates">Templates</TabsTrigger>
        <TabsTrigger value="prepared">Prepared Cards</TabsTrigger>
        <TabsTrigger value="sent">Sent Cards</TabsTrigger>
      </TabsList>
      <TabsContent value="prepared" className="mt-4">
        <PreparedCardsPanel eventId={eventId} />
      </TabsContent>
      <TabsContent value="sent" className="mt-4">
        <SentCardsPanel eventId={eventId} />
      </TabsContent>

      <TabsContent value="templates" className="mt-4 space-y-6">
      {/* Category pills */}
      {categories.length > 1 && (
        <div className="flex flex-wrap gap-2">

          {categories.map((c) => (
            <button
              key={c.category}
              onClick={() => setActiveCategory(c.category)}
              className={`px-3 py-1.5 rounded-full text-xs font-medium border transition ${
                activeCategory === c.category
                  ? "bg-primary text-primary-foreground border-primary"
                  : "bg-background text-foreground border-border hover:bg-muted"
              }`}
            >
              {c.name}
            </button>
          ))}
        </div>
      )}

      {/* Template gallery */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Templates</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
            {templates.map((t) => {
              const selected = activeTemplate?.slug === t.slug;
              return (
                <button
                  key={t.slug}
                  onClick={() => pickTemplate(t.slug)}
                  className={`group relative aspect-[5/7] rounded-xl overflow-hidden border-2 transition ${
                    selected ? "border-primary shadow-md" : "border-border hover:border-muted-foreground/40"
                  }`}
                >
                  <div className="w-full h-full bg-muted flex items-center justify-center overflow-hidden">
                    <TemplateThumb slug={t.slug} contributorName={currentUserName} />
                  </div>
                  <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent p-2">
                    <p className="text-white text-[11px] font-medium truncate">{t.name}</p>
                  </div>
                  {selected && (
                    <Badge className="absolute top-2 right-2 bg-primary text-primary-foreground">Selected</Badge>
                  )}
                </button>
              );
            })}
          </div>
        </CardContent>
      </Card>

      {/* Editor + preview */}
      {activeTemplate && (
        <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
          <Card className="lg:col-span-3">
            <CardHeader className="pb-3 flex flex-row items-center justify-between">
              <CardTitle className="text-base">Edit text</CardTitle>
              {loadingTpl && <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />}
            </CardHeader>
            <CardContent className="space-y-4">
              {editable.length === 0 && (
                <p className="text-sm text-muted-foreground">This template has no editable fields.</p>
              )}
              {activeTemplate?.metadata?.contributor_placeholder_id && (
                <div className="space-y-1.5 rounded-md border border-border bg-muted/30 p-3">
                  <label className="text-xs font-medium text-muted-foreground">
                    Optional guest-name prefix (e.g. "Dear", "Hello", "Mwalimu")
                  </label>
                  <Input
                    value={values["__guest_name_prefix"] ?? ""}
                    onChange={(e) => setValues((p) => ({ ...p, __guest_name_prefix: e.target.value }))}
                    maxLength={30}
                    placeholder="Leave empty for no prefix"
                    autoComplete="off"
                  />
                  <p className="text-[10px] text-muted-foreground">
                    Shown before every guest's name on the card.
                  </p>
                </div>
              )}
              {editable.map((f) => {
                if (lockedIds.has(f.id)) return null;
                const v = values[f.id] ?? "";
                return (
                  <div key={f.id} className="space-y-1.5">
                    <label className="text-xs font-medium text-muted-foreground">{f.label}</label>
                    {f.multiline ? (
                      <Textarea
                        value={v}
                        onChange={(e) => setValues((p) => ({ ...p, [f.id]: e.target.value }))}
                        maxLength={f.max_length}
                        rows={3}
                        autoComplete="off"
                      />
                    ) : (
                      <Input
                        value={v}
                        onChange={(e) => setValues((p) => ({ ...p, [f.id]: e.target.value }))}
                        maxLength={f.max_length}
                        autoComplete="off"
                      />
                    )}
                    {f.max_length && (
                      <p className="text-[10px] text-muted-foreground text-right">
                        {v.length}/{f.max_length}
                      </p>
                    )}
                  </div>
                );
              })}
              <div className="flex flex-wrap gap-2 pt-2">
                <Button onClick={onSave} disabled={saving}>
                  {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" /> Saving</> : "Save card"}
                </Button>

                {/* Prepare cards — split menu so the organiser can choose
                     between re-preparing everyone (fresh) and only the
                     recipients without a prepared card yet (skip). */}
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button
                      variant="outline"
                      disabled={saving || (!savedCard && audience !== "guests")}
                      title="Render cards in your browser and stage them on the Prepared Cards tab without sending"
                    >
                      Prepare cards
                      <ChevronDown className="w-3.5 h-3.5 ml-1.5 opacity-70" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="start" className="w-72">
                    <DropdownMenuLabel>How should we prepare?</DropdownMenuLabel>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem onClick={() => { void openSend({ prepareOnly: true, mode: "fresh" }); }}>
                      <div className="flex flex-col">
                        <span className="font-medium">Fresh prepare (all selected)</span>
                        <span className="text-xs text-muted-foreground">Re-renders every selected recipient. Replaces any previously prepared card.</span>
                      </div>
                    </DropdownMenuItem>
                    <DropdownMenuItem onClick={() => { void openSend({ prepareOnly: true, mode: "skip_existing" }); }}>
                      <div className="flex flex-col">
                        <span className="font-medium">Only those not prepared yet</span>
                        <span className="text-xs text-muted-foreground">Skips recipients that already have a prepared card so their stable URL stays the same.</span>
                      </div>
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>

                {/* Send — same picker, dispatch path. */}
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button
                      variant="outline"
                      disabled={saving || (!savedCard && audience !== "guests")}
                    >
                      Send to {recipientNounPlural}
                      <ChevronDown className="w-3.5 h-3.5 ml-1.5 opacity-70" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="start" className="w-72">
                    <DropdownMenuLabel>How should we send?</DropdownMenuLabel>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem onClick={() => { void openSend({ mode: "fresh" }); }}>
                      <div className="flex flex-col">
                        <span className="font-medium">Fresh send (all selected)</span>
                        <span className="text-xs text-muted-foreground">Sends to every selected recipient, even those already sent before.</span>
                      </div>
                    </DropdownMenuItem>
                    <DropdownMenuItem onClick={() => { void openSend({ mode: "skip_existing" }); }}>
                      <div className="flex flex-col">
                        <span className="font-medium">Only those not sent yet</span>
                        <span className="text-xs text-muted-foreground">Skips anyone whose card was already delivered. Useful for catching up new recipients.</span>
                      </div>
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>

              </div>

            </CardContent>
          </Card>

          <Card className="lg:col-span-2">
            <CardHeader className="pb-3">
              <CardTitle className="text-base">Preview</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="aspect-[3/4] rounded-xl bg-white overflow-hidden flex items-center justify-center">
                {previewSvgMarkup ? (
                  <div
                    className="w-full h-full [&>svg]:w-full [&>svg]:h-full [&>svg]:block"
                    dangerouslySetInnerHTML={{ __html: previewSvgMarkup }}
                  />
                ) : (
                  <p className="text-xs text-muted-foreground px-6 text-center">
                    Pick a template to see a preview.
                  </p>
                )}
              </div>
              <p className="text-[11px] text-muted-foreground mt-2">
                {(() => {
                  const noun = (activeTemplate?.metadata?.recipient_noun || "Contributor").toLowerCase();
                  return `${noun.charAt(0).toUpperCase()}${noun.slice(1)} names are added automatically when the card is sent.`;
                })()}
              </p>
            </CardContent>
          </Card>
        </div>
      )}

      {/* Send dialog */}
      <Dialog open={sendOpen} onOpenChange={(o) => { if (activeBatchNo === null) setSendOpen(o); }}>
        <DialogContent className="max-w-2xl h-[90vh] flex flex-col p-0 gap-0">
          <DialogHeader className="px-6 pt-6 pb-3 shrink-0 border-b border-border">
            <DialogTitle>
              {sendStep === "pick"
                ? (prepareModeUi ? `Prepare cards for ${recipientNounPlural}` : `Send card to ${recipientNounPlural}`)
                : (prepareModeUi ? "Prepare in batches" : "Send in batches")}
            </DialogTitle>
            <DialogDescription>
              {sendStep === "pick"
                ? `Pick ${recipientNounPlural} and choose a batch size. You'll ${prepareModeUi ? "prepare" : "send"} each batch manually.`
                : `${prepareModeUi ? "Prepare" : "Send"} each batch manually. The browser only processes one batch at a time.`}
            </DialogDescription>
          </DialogHeader>

          <div className="flex-1 min-h-0 overflow-y-auto px-6 py-4">
          {sendStep === "pick" && (
            eligibleContributors.length === 0 ? (
              <p className="text-sm text-muted-foreground py-6 text-center">
                {excludedReason
                  ? `Every eligible ${recipientNounPlural === "guests" ? "guest" : "contributor"} has already been ${excludedReason}. Nothing left to ${prepareModeUi ? "prepare" : "send"}.`
                  : audience === "guests"
                    ? (loadingGuests ? "Loading guests…" : "No eligible guests on this event yet.")
                    : "No contributors with a pledge yet."}
              </p>
            ) : (
              <>
                {excludedRecipientIds.size > 0 && excludedReason && (
                  <div className="mb-3 px-3 py-2 rounded-md bg-muted/60 text-xs text-muted-foreground">
                    Hiding {excludedRecipientIds.size} {excludedRecipientIds.size === 1 ? "recipient" : "recipients"} already {excludedReason}. Showing only the remaining {eligibleContributors.length}.
                  </div>
                )}
                <div className="space-y-3">
                  <div className="flex items-center gap-3">
                    <label className="text-xs font-medium text-muted-foreground whitespace-nowrap">
                      Group recipients into batches of:
                    </label>
                    <div className="flex gap-1">
                      {[5, 10, 20, 30, 50].map((n) => (
                        <button
                          key={n}
                          type="button"
                          onClick={() => setBatchSize(n)}
                          className={`px-2.5 py-1 rounded-md text-xs font-medium border transition ${
                            batchSize === n
                              ? "bg-primary text-primary-foreground border-primary"
                              : "bg-background text-foreground border-border hover:bg-muted"
                          }`}
                        >
                          {n}
                        </button>
                      ))}
                    </div>
                  </div>
                  <Input
                    value={contributorSearch}
                    onChange={(e) => setContributorSearch(e.target.value)}
                    placeholder="Search by name or phone"
                    autoComplete="off"
                  />
                  <label className="flex items-center gap-2 px-2 py-1.5 rounded-md hover:bg-muted cursor-pointer text-sm">
                    <Checkbox
                      checked={allFilteredSelected}
                      onCheckedChange={toggleSelectAllFiltered}
                    />
                    <span className="flex-1">
                      {allFilteredSelected ? "Unselect all" : "Select all"}
                      <span className="text-muted-foreground ml-1">
                        ({filteredContributors.length}
                        {contributorSearch ? ` of ${eligibleContributors.length}` : ""})
                      </span>
                    </span>
                    {selectedContributorIds.size > 0 && (
                      <span className="text-xs text-muted-foreground">
                        {selectedContributorIds.size} selected
                      </span>
                    )}
                  </label>
                </div>

                <div className="mt-3 space-y-1.5">
                  {filteredContributors.length === 0 ? (
                    <p className="text-sm text-muted-foreground py-6 text-center">
                      No {recipientNounPlural} match "{contributorSearch}".
                    </p>
                  ) : (
                    filteredContributors.map((ec) => {
                      const id = ec.id;
                      const checked = selectedContributorIds.has(id);
                      const name = ec.name || "Unnamed";
                      const phone = ec.phone || "";
                      return (
                        <label key={id} className="flex items-center gap-3 p-2 rounded-lg hover:bg-muted cursor-pointer">
                          <Checkbox checked={checked} onCheckedChange={() => toggleContributor(id)} />
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-medium truncate">{name}</p>
                            {phone && <p className="text-xs text-muted-foreground truncate">{phone}</p>}
                          </div>
                        </label>
                      );
                    })
                  )}
                </div>
              </>
            )
          )}

          {sendStep === "batches" && (
            <BatchesView
              batches={batches}
              batchSize={batchSize}
              activeBatchNo={activeBatchNo}
              activeBatchProgress={activeBatchProgress}
              recipientInfo={Object.fromEntries(
                eligibleContributors.map((ec) => [ec.id, { name: ec.name || "Unnamed", phone: ec.phone || "" }])
              )}
              onSendBatch={(n) => sendBatch(n)}
              onRetryFailed={(n) => sendBatch(n, { retryOnly: true })}
              onSafeRetry={(n) => sendBatch(n, { retryOnly: true, mode: "safe" })}
              onResetRenderer={resetRenderer}
              onResendAll={async (n) => {
                const ok = await confirm({
                  title: "Resend the entire batch?",
                  description: "This may deliver the card a second time to recipients already marked as sent.",
                  confirmLabel: "Resend batch",
                });
                if (!ok) return;
                persistBatches(batches.map((b) => (b.batch_no === n ? { ...b, sent_ids: [], failed: [], status: "not_sent" } : b)));
              }}
              onClearReport={(n) => {
                persistBatches(batches.map((b) => (b.batch_no === n ? { ...b, sent_ids: [], failed: [], status: "not_sent", started_at: undefined, finished_at: undefined } : b)));
              }}
              onCancelActive={cancelActiveBatch}
              prepareMode={prepareModeUi}
            />
          )}
          </div>

          <DialogFooter className="flex-col sm:flex-row gap-2 px-6 py-4 border-t border-border shrink-0">
            {sendStep === "pick" ? (
              <>
                <Button variant="outline" onClick={() => setSendOpen(false)}>Cancel</Button>
                <Button onClick={continueToBatches} disabled={selectedContributorIds.size === 0}>
                  Continue ({selectedContributorIds.size} → {Math.ceil(selectedContributorIds.size / Math.max(1, batchSize))} batch{Math.ceil(selectedContributorIds.size / Math.max(1, batchSize)) === 1 ? "" : "es"})
                </Button>
              </>
            ) : (
              <>
                <Button variant="outline" onClick={goBackToPick} disabled={activeBatchNo !== null}>
                  Back to selection
                </Button>
                <Button variant="outline" onClick={() => setSendOpen(false)} disabled={activeBatchNo !== null}>
                  Close
                </Button>
              </>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
      </TabsContent>
    </Tabs>
    </>
  );

}

interface BatchesViewProps {
  batches: BatchState[];
  batchSize: number;
  activeBatchNo: number | null;
  activeBatchProgress:
    | {
        done: number;
        total: number;
        prepared: number;
        uploaded: number;
        failed: number;
        currentName?: string;
        avgMs?: number;
        etaMs?: number;
        phase: "preparing" | "sending" | "done";
      }
    | null;
  recipientInfo: Record<string, { name: string; phone: string }>;
  onSendBatch: (n: number) => void;
  onRetryFailed: (n: number) => void;
  onSafeRetry: (n: number) => void;
  onResetRenderer: () => void;
  onResendAll: (n: number) => void;
  onClearReport: (n: number) => void;
  onCancelActive: () => void;
  prepareMode?: boolean;
}

const STATUS_LABELS: Record<BatchStatus, string> = {
  not_sent: "Not sent",
  sending: "Sending",
  sent: "Sent",
  partial_failure: "Partial failure",
  failed: "Failed",
  cancelled: "Cancelled",
  renderer_stuck: "Renderer stuck",
};

const STATUS_BADGE: Record<BatchStatus, string> = {
  not_sent: "bg-muted text-muted-foreground",
  sending: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300",
  sent: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300",
  partial_failure: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300",
  failed: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300",
  cancelled: "bg-muted text-muted-foreground",
  renderer_stuck: "bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-300",
};

function BatchesView({
  batches, batchSize, activeBatchNo, activeBatchProgress, recipientInfo,
  onSendBatch, onRetryFailed, onSafeRetry, onResetRenderer, onResendAll, onClearReport, onCancelActive, prepareMode,
}: BatchesViewProps) {
  const verb = prepareMode ? "Prepare" : "Send";
  const verbLower = prepareMode ? "prepare" : "send";
  const pastTense = prepareMode ? "prepared" : "sent";
  const presentTense = prepareMode ? "Preparing" : "Sending";
  const STATUS_LABELS_LOCAL: Record<BatchStatus, string> = prepareMode
    ? { ...STATUS_LABELS, not_sent: "Not prepared", sending: "Preparing", sent: "Prepared" }
    : STATUS_LABELS;
  const [expanded, setExpanded] = useState<Set<number>>(new Set());
  const toggle = (n: number) => setExpanded((p) => {
    const next = new Set(p);
    if (next.has(n)) next.delete(n); else next.add(n);
    return next;
  });

  const totalSelected = batches.reduce((s, b) => s + b.recipient_ids.length, 0);
  const totalSent = batches.reduce((s, b) => s + b.sent_ids.length, 0);
  const totalFailed = batches.reduce((s, b) => s + b.failed.length, 0);
  const totalPending = Math.max(0, totalSelected - totalSent - totalFailed);
  const completed = batches.filter((b) => b.status === "sent").length;
  const remaining = batches.length - completed;

  return (
    <div className="space-y-3">
      <div className="rounded-lg border border-border bg-muted/30 p-3 text-xs space-y-1">
        <p className="font-medium text-foreground">
          {totalSelected} selected - {totalSent} {pastTense} - {totalFailed} failed - {totalPending} pending
        </p>
        <p className="text-muted-foreground">
          {completed} of {batches.length} batches completed - {remaining} remaining - batch size {batchSize}
        </p>
        <div className="pt-1">
          <Button size="sm" variant="outline" onClick={onResetRenderer} disabled={activeBatchNo !== null}>
            Reset renderer
          </Button>
        </div>
      </div>

      <div className="space-y-2">
          {batches.map((b) => {
            const start = (b.batch_no - 1) * batchSize + 1;
            const end = start + b.recipient_ids.length - 1;
            const sentCount = b.sent_ids.length;
            const failedCount = b.failed.length;
            const pendingCount = b.recipient_ids.length - sentCount - failedCount;
            const isActive = activeBatchNo === b.batch_no;
            const isOpen = expanded.has(b.batch_no);
            return (
              <div key={b.batch_no} className="rounded-lg border border-border p-3 space-y-2">
                <div className="flex flex-wrap items-center gap-2">
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium">
                      Batch {b.batch_no} - {start}–{end} of {totalSelected}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {b.recipient_ids.length} recipients - {pastTense} {sentCount} - failed {failedCount} - pending {pendingCount}
                    </p>
                  </div>
                  <span className={`text-[10px] uppercase tracking-wide px-2 py-0.5 rounded-full font-medium ${STATUS_BADGE[b.status]}`}>
                    {STATUS_LABELS_LOCAL[b.status]}
                  </span>
                </div>

                {isActive && activeBatchProgress && (
                  <div className="text-xs text-muted-foreground space-y-1">
                    <p className="font-medium text-foreground">
                      {activeBatchProgress.phase === "sending"
                        ? (prepareMode ? "Staging prepared cards…" : "Sending prepared cards…")
                        : `Card ${Math.min(activeBatchProgress.done + 1, activeBatchProgress.total)} of ${activeBatchProgress.total}${activeBatchProgress.currentName ? `: ${activeBatchProgress.currentName}` : ""}`}
                    </p>
                    <p>
                      Prepared {activeBatchProgress.prepared} - Uploaded {activeBatchProgress.uploaded} - Failed {activeBatchProgress.failed} - Pending {Math.max(0, activeBatchProgress.total - activeBatchProgress.done)}
                    </p>
                    {activeBatchProgress.avgMs !== undefined && (
                      <p>
                        Average: {(activeBatchProgress.avgMs / 1000).toFixed(1)}s/card
                        {activeBatchProgress.etaMs !== undefined && activeBatchProgress.etaMs > 0
                          ? ` - ETA ${Math.max(1, Math.round(activeBatchProgress.etaMs / 1000))}s`
                          : ""}
                      </p>
                    )}
                    <div className="h-1.5 w-full bg-muted rounded-full overflow-hidden">
                      <div
                        className="h-full bg-primary transition-all"
                        style={{ width: `${activeBatchProgress.total ? (activeBatchProgress.done / activeBatchProgress.total) * 100 : 0}%` }}
                      />
                    </div>
                  </div>
                )}

                <div className="flex flex-wrap gap-2">
                  {b.status === "not_sent" && (
                    <Button size="sm" onClick={() => onSendBatch(b.batch_no)} disabled={activeBatchNo !== null}>
                      {isActive ? <><Loader2 className="w-3.5 h-3.5 mr-1 animate-spin" /> {presentTense}</> : `${verb} batch`}
                    </Button>
                  )}
                  {(b.status === "partial_failure" || b.status === "cancelled" || b.status === "renderer_stuck") && pendingCount > 0 && (
                    <Button size="sm" onClick={() => onSendBatch(b.batch_no)} disabled={activeBatchNo !== null}>
                      {verb} remaining ({pendingCount})
                    </Button>
                  )}
                  {failedCount > 0 && (
                    <Button size="sm" variant="outline" onClick={() => onRetryFailed(b.batch_no)} disabled={activeBatchNo !== null}>
                      Retry failed only ({failedCount})
                    </Button>
                  )}
                  {(failedCount > 0 || (b.status === "renderer_stuck" && pendingCount > 0)) && (
                    <Button size="sm" variant="outline" onClick={() => onSafeRetry(b.batch_no)} disabled={activeBatchNo !== null}>
                      Safe retry failed/pending
                    </Button>
                  )}
                  {(b.status === "sent" || b.status === "partial_failure" || b.status === "failed" || b.status === "cancelled" || b.status === "renderer_stuck") && (
                    <Button size="sm" variant="ghost" onClick={() => onResendAll(b.batch_no)} disabled={activeBatchNo !== null}>
                      {prepareMode ? "Re-prepare all" : "Resend all"}
                    </Button>
                  )}
                  {b.status === "sent" && (
                    <Button size="sm" variant="ghost" onClick={() => onClearReport(b.batch_no)} disabled={activeBatchNo !== null}>
                      Clear report
                    </Button>
                  )}
                  {isActive && (
                    <Button size="sm" variant="outline" onClick={onCancelActive}>
                      Cancel
                    </Button>
                  )}
                  <Button size="sm" variant="ghost" onClick={() => toggle(b.batch_no)}>
                    {isOpen ? "Hide recipients" : "View recipients"}
                  </Button>
                </div>

                {isOpen && (
                  <div className="text-xs text-muted-foreground space-y-1 pt-1 border-t border-border">
                    <p className="font-medium text-foreground">Recipients ({b.recipient_ids.length})</p>
                    <ul className="space-y-0.5">
                      {b.recipient_ids.map((id) => {
                        const info = recipientInfo[id];
                        const sent = b.sent_ids.includes(id);
                        const failed = b.failed.find((f) => f.recipient_id === id);
                        return (
                          <li key={id} className="flex items-baseline gap-2">
                            <span className={`inline-block w-1.5 h-1.5 rounded-full shrink-0 ${failed ? "bg-red-500" : sent ? "bg-green-500" : "bg-muted-foreground/40"}`} />
                            <span className="flex-1 break-words">
                              <span className="text-foreground">{info?.name || id}</span>
                              {info?.phone && <span className="text-muted-foreground"> - {info.phone}</span>}
                              {failed && <span className="text-red-600 dark:text-red-400"> — {failed.reason}</span>}
                            </span>
                          </li>
                        );
                      })}
                    </ul>
                    {b.started_at && (
                      <p className="pt-1">
                        Started {new Date(b.started_at).toLocaleString()}
                        {b.finished_at ? ` - Finished ${new Date(b.finished_at).toLocaleString()}` : ""}
                      </p>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
    </div>
  );
}
