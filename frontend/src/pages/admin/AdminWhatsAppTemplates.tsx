import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  MessageCircle,
  Search,
  Copy,
  Check,
  AlertTriangle,
  ExternalLink,
  Languages,
} from "lucide-react";
import { toast } from "sonner";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { cn } from "@/lib/utils";
import {
  TEMPLATES,
  SAMPLE,
  renderTemplate,
  validatePlaceholders,
  type WaTemplate,
} from "./whatsappTemplatesData";

type Lang = "sw" | "en";

const STATUS_STYLES: Record<WaTemplate["status"], string> = {
  new: "bg-emerald-50 text-emerald-700 border-emerald-200",
  existing: "bg-sky-50 text-sky-700 border-sky-200",
  updated: "bg-amber-50 text-amber-700 border-amber-200",
};

function HighlightedBody({ text }: { text: string }) {
  // Highlight unresolved placeholders {{N:name}} or {{N}}
  const parts = text.split(/(\{\{[^}]+\}\})/g);
  return (
    <div className="whitespace-pre-wrap font-sans text-sm leading-relaxed text-slate-800">
      {parts.map((p, i) =>
        /^\{\{.+\}\}$/.test(p) ? (
          <span
            key={i}
            className="inline-flex items-center rounded bg-red-100 px-1 text-red-700 font-mono text-xs"
          >
            {p}
          </span>
        ) : (
          <span key={i}>{p}</span>
        ),
      )}
    </div>
  );
}

function TemplateCard({
  t,
  lang,
  overrides,
}: {
  t: WaTemplate;
  lang: Lang;
  overrides: Record<string, string>;
}) {
  const [copied, setCopied] = useState(false);
  const body = lang === "sw" ? t.body_sw : t.body_en;
  const name = lang === "sw" ? t.name_sw : t.name_en;
  const result = useMemo(
    () => renderTemplate(body, t.placeholders, SAMPLE, overrides),
    [body, t.placeholders, overrides],
  );
  const issues = useMemo(() => validatePlaceholders(t), [t]);
  const fullButtonUrl = t.button
    ? `${t.button.prefix}${overrides[t.button.suffixKey] ?? SAMPLE[t.button.suffixKey] ?? ""}`
    : null;

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(result.rendered);
      setCopied(true);
      toast.success("Rendered body copied");
      setTimeout(() => setCopied(false), 1500);
    } catch {
      toast.error("Could not copy");
    }
  };

  return (
    <div className="rounded-2xl border border-slate-200 bg-white shadow-sm overflow-hidden">
      {/* Header */}
      <div className="flex flex-wrap items-center gap-2 justify-between border-b border-slate-100 bg-slate-50/60 px-4 py-3">
        <div className="flex items-center gap-3 min-w-0">
          <span className="shrink-0 inline-flex h-7 min-w-7 items-center justify-center rounded-full bg-slate-900 px-2 text-xs font-semibold text-white">
            #{t.num}
          </span>
          <div className="min-w-0">
            <div className="font-mono text-sm font-semibold text-slate-900 truncate">
              {name}
            </div>
            <div className="text-[11px] text-slate-500 mt-0.5">
              {t.placeholders.length} placeholders - {t.category}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span
            className={cn(
              "text-[10px] uppercase tracking-wider px-2 py-0.5 rounded-full border font-semibold",
              STATUS_STYLES[t.status],
            )}
          >
            {t.status}
          </span>
          <button
            onClick={copy}
            className="inline-flex items-center gap-1 rounded-md border border-slate-200 bg-white px-2 py-1 text-xs text-slate-700 hover:bg-slate-50"
          >
            {copied ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
            {copied ? "Copied" : "Copy"}
          </button>
        </div>
      </div>

      <div className="grid md:grid-cols-2">
        {/* Preview */}
        <div className="p-4 border-b md:border-b-0 md:border-r border-slate-100 bg-[#e7ddd1]/40">
          <div className="text-[10px] uppercase tracking-wider font-semibold text-slate-500 mb-2">
            WhatsApp preview ({lang.toUpperCase()})
          </div>
          <div className="rounded-xl bg-white shadow-sm border border-slate-200 p-3">
            <HighlightedBody text={result.rendered} />
            {t.button && (
              <div className="mt-3 pt-3 border-t border-slate-100">
                <a
                  href={fullButtonUrl ?? "#"}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex w-full items-center justify-center gap-1.5 rounded-lg bg-emerald-50 text-emerald-700 hover:bg-emerald-100 px-3 py-2 text-sm font-semibold border border-emerald-100"
                >
                  {lang === "sw" ? t.button.label_sw : t.button.label_en}
                  <ExternalLink className="w-3.5 h-3.5" />
                </a>
                <div className="mt-1.5 text-[10px] text-slate-500 break-all font-mono">
                  {fullButtonUrl}
                </div>
              </div>
            )}
          </div>

          {(result.missing.length > 0 || result.unresolved.length > 0 || issues.length > 0) && (
            <div className="mt-3 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
              <div className="flex items-center gap-1.5 font-semibold mb-1">
                <AlertTriangle className="w-3.5 h-3.5" />
                Issues detected
              </div>
              <ul className="list-disc pl-4 space-y-0.5">
                {result.missing.map((k) => (
                  <li key={"m" + k}>No sample value for `{k}`</li>
                ))}
                {result.unresolved.map((n) => (
                  <li key={"u" + n}>{`{{${n}}}`} has no placeholder mapping</li>
                ))}
                {issues.map((i, idx) => (
                  <li key={"i" + idx}>{i}</li>
                ))}
              </ul>
            </div>
          )}
        </div>

        {/* Mapping table */}
        <div className="p-4">
          <div className="text-[10px] uppercase tracking-wider font-semibold text-slate-500 mb-2">
            Placeholder mapping
          </div>
          <div className="rounded-lg border border-slate-200 overflow-hidden">
            <table className="w-full text-xs">
              <thead className="bg-slate-50 text-slate-600">
                <tr>
                  <th className="text-left px-2 py-1.5 w-12">#</th>
                  <th className="text-left px-2 py-1.5">Key</th>
                  <th className="text-left px-2 py-1.5">Sample</th>
                </tr>
              </thead>
              <tbody>
                {t.placeholders.map((key, i) => (
                  <tr key={i} className="border-t border-slate-100">
                    <td className="px-2 py-1.5 font-mono text-slate-500">{`{{${i + 1}}}`}</td>
                    <td className="px-2 py-1.5 font-mono text-slate-900">{key}</td>
                    <td className="px-2 py-1.5 text-slate-700">
                      {overrides[key] ?? SAMPLE[key] ?? <span className="text-red-600">— missing —</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {t.button && (
            <div className="mt-3 rounded-lg border border-slate-200 p-2 text-xs">
              <div className="font-semibold text-slate-900 mb-1">
                CTA URL button (dynamic)
              </div>
              <div className="grid grid-cols-[80px_1fr] gap-y-1 text-slate-700">
                <span className="text-slate-500">Label SW</span><span>{t.button.label_sw}</span>
                <span className="text-slate-500">Label EN</span><span>{t.button.label_en}</span>
                <span className="text-slate-500">Prefix</span><span className="font-mono break-all">{t.button.prefix}</span>
                <span className="text-slate-500">{"{{1}}"}</span><span className="font-mono">{t.button.suffixKey}</span>
              </div>
            </div>
          )}

          <div className="mt-3 text-[11px] text-slate-500">
            <span className="font-semibold text-slate-700">Backend:</span>{" "}
            <span className="font-mono">{t.backendRef}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

export default function AdminWhatsAppTemplates() {
  useAdminMeta("WhatsApp Templates Preview");
  const [lang, setLang] = useState<Lang>("sw");
  const [bothLangs, setBothLangs] = useState(false);
  const [q, setQ] = useState("");
  const [statusFilter, setStatusFilter] = useState<"all" | WaTemplate["status"]>("all");
  const [overrides, setOverrides] = useState<Record<string, string>>({});

  const allPlaceholderKeys = useMemo(() => {
    const s = new Set<string>();
    TEMPLATES.forEach((t) => t.placeholders.forEach((k) => s.add(k)));
    TEMPLATES.forEach((t) => t.button && s.add(t.button.suffixKey));
    return Array.from(s).sort();
  }, []);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return TEMPLATES.filter((t) => {
      if (statusFilter !== "all" && t.status !== statusFilter) return false;
      if (!needle) return true;
      return (
        t.key.includes(needle) ||
        t.name_sw.includes(needle) ||
        t.name_en.includes(needle) ||
        t.body_sw.toLowerCase().includes(needle) ||
        t.body_en.toLowerCase().includes(needle) ||
        t.placeholders.some((p) => p.includes(needle))
      );
    });
  }, [q, statusFilter]);

  const totalIssues = useMemo(() => {
    let n = 0;
    TEMPLATES.forEach((t) => (n += validatePlaceholders(t).length));
    return n;
  }, []);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="flex items-center gap-2 text-slate-900">
            <MessageCircle className="w-5 h-5" />
            <h1 className="text-2xl font-bold tracking-tight">WhatsApp Templates Preview</h1>
          </div>
          <p className="text-sm text-slate-500 mt-1">
            Read-only preview of all {TEMPLATES.length} core templates ({TEMPLATES.length * 2} entries × SW/EN).
            Catches placeholder gaps, unmapped indices, and formatting issues before Meta submission.
          </p>
        </div>
        <Link
          to="/admin/whatsapp"
          className="text-xs text-slate-600 hover:text-slate-900 underline"
        >
          ← Back to WhatsApp dashboard
        </Link>
      </div>

      {/* Toolbar */}
      <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <div className="flex flex-wrap items-center gap-3">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              autoComplete="off"
              placeholder="Search name, body, placeholder…"
              className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 focus:border-slate-400 focus:outline-none"
            />
          </div>

          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value as typeof statusFilter)}
            className="text-sm rounded-lg border border-slate-200 px-3 py-2 bg-white"
          >
            <option value="all">All statuses</option>
            <option value="new">New</option>
            <option value="existing">Existing (rewritten)</option>
            <option value="updated">Updated</option>
          </select>

          <div className="inline-flex rounded-lg border border-slate-200 overflow-hidden">
            <button
              onClick={() => { setBothLangs(false); setLang("sw"); }}
              className={cn(
                "px-3 py-2 text-sm font-medium",
                !bothLangs && lang === "sw" ? "bg-slate-900 text-white" : "bg-white text-slate-700 hover:bg-slate-50",
              )}
            >
              Swahili
            </button>
            <button
              onClick={() => { setBothLangs(false); setLang("en"); }}
              className={cn(
                "px-3 py-2 text-sm font-medium border-l border-slate-200",
                !bothLangs && lang === "en" ? "bg-slate-900 text-white" : "bg-white text-slate-700 hover:bg-slate-50",
              )}
            >
              English
            </button>
            <button
              onClick={() => setBothLangs(true)}
              className={cn(
                "inline-flex items-center gap-1 px-3 py-2 text-sm font-medium border-l border-slate-200",
                bothLangs ? "bg-slate-900 text-white" : "bg-white text-slate-700 hover:bg-slate-50",
              )}
            >
              <Languages className="w-3.5 h-3.5" /> Both
            </button>
          </div>
        </div>

        {/* Stats */}
        <div className="flex flex-wrap items-center gap-x-5 gap-y-1 text-xs text-slate-600 mt-3">
          <span>
            Showing <strong className="text-slate-900">{filtered.length}</strong> of {TEMPLATES.length}
          </span>
          <span>
            Catalogue health:{" "}
            {totalIssues === 0 ? (
              <span className="inline-flex items-center gap-1 text-emerald-700 font-semibold">
                <Check className="w-3 h-3" /> No structural issues
              </span>
            ) : (
              <span className="inline-flex items-center gap-1 text-amber-700 font-semibold">
                <AlertTriangle className="w-3 h-3" /> {totalIssues} structural issue(s)
              </span>
            )}
          </span>
        </div>
      </div>

      {/* Sample data overrides */}
      <details className="rounded-2xl border border-slate-200 bg-white shadow-sm">
        <summary className="cursor-pointer select-none px-4 py-3 text-sm font-semibold text-slate-800 hover:bg-slate-50 rounded-2xl">
          Sample data ({allPlaceholderKeys.length} keys) — edit to test edge cases
        </summary>
        <div className="border-t border-slate-100 p-4 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
          {allPlaceholderKeys.map((k) => (
            <label key={k} className="block text-xs">
              <span className="block font-mono text-slate-600 mb-1">{k}</span>
              <input
                value={overrides[k] ?? SAMPLE[k] ?? ""}
                onChange={(e) => setOverrides((o) => ({ ...o, [k]: e.target.value }))}
                autoComplete="off"
                className="w-full px-2 py-1.5 text-sm rounded-md border border-slate-200 focus:border-slate-400 focus:outline-none"
              />
            </label>
          ))}
          <div className="sm:col-span-2 md:col-span-3 flex justify-end">
            <button
              onClick={() => setOverrides({})}
              className="text-xs text-slate-600 hover:text-slate-900 underline"
            >
              Reset overrides
            </button>
          </div>
        </div>
      </details>

      {/* Grid */}
      <div className="space-y-6">
        {filtered.length === 0 && (
          <div className="text-center text-sm text-slate-500 py-12 border border-dashed border-slate-200 rounded-2xl">
            No templates match this filter.
          </div>
        )}
        {filtered.map((t) =>
          bothLangs ? (
            <div key={t.key} className="grid lg:grid-cols-2 gap-4">
              <TemplateCard t={t} lang="sw" overrides={overrides} />
              <TemplateCard t={t} lang="en" overrides={overrides} />
            </div>
          ) : (
            <TemplateCard key={t.key} t={t} lang={lang} overrides={overrides} />
          ),
        )}
      </div>
    </div>
  );
}
