/**
 * ReceivedPaymentsPanel — paginated, read-only list of payments that landed
 * on a beneficiary entity (event contributions, event tickets, or a
 * service). Surfaces gross / commission / net / gateway reference.
 *
 * Wallets are **not** updated for these payments — this view is the only
 * place beneficiaries see them.
 */
import { useEffect, useMemo, useState } from "react";
import { Loader2, ChevronLeft, ChevronRight, ExternalLink, Search, Printer, ShieldCheck, Clock } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { receivedPaymentsApi } from "@/lib/api/receivedPayments";
import type { ReceivedPayment, ReceivedPaymentsPage } from "@/lib/api/receivedPayments";
import { offlinePaymentsApi, type OfflineVendorPayment } from "@/lib/api/offlinePayments";
import { openPaymentReceipt } from "@/utils/printPaymentReceipt";
import { useNavigate } from "react-router-dom";
import { format } from "date-fns";

type Source =
  | { kind: "event-contributions"; eventId: string }
  | { kind: "event-tickets"; eventId: string }
  | { kind: "service"; serviceId: string };

interface Props {
  source: Source;
  /** Optional title override; defaults match the source kind. */
  title?: string;
}

const STATUS_VARIANT: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
  credited: "default",
};

export default function ReceivedPaymentsPanel({ source, title }: Props) {
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState("");
  const [search, setSearch] = useState("");
  const [data, setData] = useState<ReceivedPaymentsPage | null>(null);
  // `initialLoading` is true only until the first response arrives. After
  // that, subsequent fetches set `refreshing` (soft) instead of `loading`,
  // so existing rows stay on-screen and we never flash a spinner.
  const [initialLoading, setInitialLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [offlineItems, setOfflineItems] = useState<OfflineVendorPayment[]>([]);

  // Debounce the search input → reset to page 1 when it changes.
  useEffect(() => {
    const t = setTimeout(() => {
      setSearch(searchInput.trim());
      setPage(1);
    }, 350);
    return () => clearTimeout(t);
  }, [searchInput]);

  const params = useMemo(
    () => ({ page, limit: 20, ...(search ? { search } : {}) }),
    [page, search],
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      // Soft-refresh after first paint: keep rows, just dim them slightly.
      if (data) setRefreshing(true);
      try {
        const res =
          source.kind === "event-contributions"
            ? await receivedPaymentsApi.eventContributions(source.eventId, params)
            : source.kind === "event-tickets"
              ? await receivedPaymentsApi.eventTickets(source.eventId, params)
              : await receivedPaymentsApi.service(source.serviceId, params);
        if (cancelled) return;
        if (res.success && res.data) {
          setData(res.data);
          setError(null);
        } else {
          setError(res.message || "Failed to load payments.");
        }

        if (source.kind === "service") {
          const offlineRes = await offlinePaymentsApi.listMine();
          if (!cancelled && offlineRes.success) {
            setOfflineItems((offlineRes.data?.items || []).filter(
              (p) => p.provider_user_service_id === source.serviceId
            ));
          }
        } else if (!cancelled) {
          setOfflineItems([]);
        }
      } catch (e: any) {
        if (!cancelled) setError(e?.message || "Failed to load payments.");
      } finally {
        if (!cancelled) {
          setInitialLoading(false);
          setRefreshing(false);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [source, params]);

  const heading =
    title ??
    (source.kind === "event-contributions"
      ? "Contribution payments"
      : source.kind === "event-tickets"
        ? "Ticket payments"
        : "Service payments");

  return (
    <Card>
      <CardContent className="p-4 sm:p-6 space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h3 className="text-base font-semibold text-foreground">{heading}</h3>
            <p className="text-xs text-muted-foreground">
              All payments received via Nuru.
            </p>
          </div>
          <div className="flex items-center gap-2">
            {refreshing && (
              <Loader2 className="w-3.5 h-3.5 animate-spin text-muted-foreground" />
            )}
            {data?.pagination && (
              <span className="text-xs text-muted-foreground">
                {data.pagination.total_items} total
              </span>
            )}
          </div>
        </div>

        <div className="relative">
          <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none" />
          <Input
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Search by payer, phone, transaction code or reference…"
            className="pl-9"
          />
        </div>

        {initialLoading && (
          <div className="flex items-center justify-center py-10 text-muted-foreground">
            <Loader2 className="w-5 h-5 animate-spin mr-2" /> Loading payments…
          </div>
        )}

        {!initialLoading && error && !data && (
          <div className="rounded-md border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive">
            {error}
          </div>
        )}

        {!initialLoading && !error && data && data.payments.length === 0 && (
          <div className="rounded-md border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
            No payments yet.
          </div>
        )}

        {!initialLoading && data && data.payments.length > 0 && (
          <div
            className={`transition-opacity duration-200 ${refreshing ? "opacity-60" : "opacity-100"}`}
            aria-busy={refreshing}
          >
            {/* Desktop table */}
            <div className="hidden md:block overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-xs text-muted-foreground border-b border-border">
                  <tr>
                    <th className="text-left py-2 pr-3">Payer</th>
                    <th className="text-left py-2 pr-3">Method</th>
                    <th className="text-right py-2 pr-3">Gross</th>
                    <th className="text-right py-2 pr-3">Commission</th>
                    <th className="text-right py-2 pr-3">Net</th>
                    <th className="text-left py-2 pr-3">Reference</th>
                    <th className="text-left py-2 pr-3">Status</th>
                    <th className="text-left py-2 pr-3">Date</th>
                    <th className="py-2"></th>
                  </tr>
                </thead>
                <tbody>
                  {data.payments.map((p) => (
                    <PaymentRow key={p.id} p={p} />
                  ))}
                </tbody>
              </table>
            </div>

            {/* Mobile cards */}
            <div className="md:hidden space-y-2">
              {data.payments.map((p) => (
                <PaymentCard key={p.id} p={p} />
              ))}
            </div>

            {data.pagination && data.pagination.total_pages > 1 && (
              <div className="flex items-center justify-between pt-2">
                <Button
                  variant="outline"
                  size="sm"
                  disabled={page <= 1}
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                >
                  <ChevronLeft className="w-4 h-4 mr-1" /> Previous
                </Button>
                <span className="text-xs text-muted-foreground">
                  Page {page} of {data.pagination.total_pages}
                </span>
                <Button
                  variant="outline"
                  size="sm"
                  disabled={page >= data.pagination.total_pages}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next <ChevronRight className="w-4 h-4 ml-1" />
                </Button>
              </div>
            )}
          </div>
        )}

        {source.kind === "service" && offlineItems.length > 0 && (
          <div className="rounded-lg border border-border bg-muted/20 p-3 space-y-2">
            <div>
              <h4 className="text-sm font-semibold text-foreground">Offline payments</h4>
              <p className="text-xs text-muted-foreground">Paid outside platform — not added to wallet.</p>
            </div>
            <div className="space-y-2">
              {offlineItems.map((p) => (
                <div key={p.id} className="flex items-center justify-between gap-3 rounded-md border border-border bg-card px-3 py-2">
                  <div className="min-w-0">
                    <div className="text-sm font-semibold text-foreground">{fmtMoney(Number(p.amount || 0), p.currency || "TZS")}</div>
                    <div className="text-xs text-muted-foreground truncate">
                      {p.service_title}{p.method ? ` - ${p.method.replace("_", " ")}` : ""}{p.reference ? ` - ${p.reference}` : ""}
                    </div>
                  </div>
                  <span className={`inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full capitalize ${p.status === "confirmed" ? "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400" : "bg-amber-500/15 text-amber-700 dark:text-amber-400"}`}>
                    {p.status === "confirmed" ? <ShieldCheck className="w-3 h-3" /> : <Clock className="w-3 h-3" />}
                    {p.status}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function fmtMoney(n: number, currency: string) {
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency,
      maximumFractionDigits: 0,
    }).format(n);
  } catch {
    return `${currency} ${n.toLocaleString()}`;
  }
}

function fmtDate(s: string | null) {
  if (!s) return "—";
  try {
    return format(new Date(s), "dd MMM yyyy HH:mm");
  } catch {
    return s;
  }
}

function StatusBadge({ status }: { status: string | null }) {
  if (!status) return null;
  const variant = STATUS_VARIANT[status] || "outline";
  return (
    <Badge variant={variant} className="capitalize">
      {status}
    </Badge>
  );
}

function PaymentRow({ p }: { p: ReceivedPayment }) {
  const navigate = useNavigate();
  return (
    <tr className="border-b border-border/60 last:border-0">
      <td className="py-2 pr-3">
        <div className="font-medium text-foreground">{p.payer_name || "—"}</div>
        {p.payer_phone && (
          <div className="text-xs text-muted-foreground">{p.payer_phone}</div>
        )}
      </td>
      <td className="py-2 pr-3 text-foreground">
        {p.provider_name || p.method_type || "—"}
      </td>
      <td className="py-2 pr-3 text-right font-medium text-foreground">
        {fmtMoney(p.gross_amount, p.currency_code)}
      </td>
      <td className="py-2 pr-3 text-right text-muted-foreground">
        {fmtMoney(p.commission_amount, p.currency_code)}
      </td>
      <td className="py-2 pr-3 text-right font-semibold text-foreground">
        {fmtMoney(p.net_amount, p.currency_code)}
      </td>
      <td className="py-2 pr-3">
        <div className="font-mono text-xs text-foreground flex items-center gap-1">
          {p.transaction_code}
        </div>
        {p.external_reference && (
          <div className="font-mono text-[11px] text-muted-foreground flex items-center gap-1">
            <ExternalLink className="w-3 h-3" /> {p.external_reference}
          </div>
        )}
      </td>
      <td className="py-2 pr-3">
        <div className="flex items-center gap-1.5">
          <StatusBadge status={p.status} />
          {p.is_offline && (
            <Badge variant="outline" className="text-[10px]">Offline</Badge>
          )}
        </div>
      </td>
      <td className="py-2 pr-3 text-muted-foreground text-xs">
        {fmtDate(p.confirmed_at || p.completed_at || p.initiated_at)}
      </td>
      <td className="py-2 text-right">
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          title="Open receipt"
          onClick={() => openPaymentReceipt(navigate, p)}
        >
          <Printer className="w-4 h-4" />
        </Button>
      </td>
    </tr>
  );
}

function PaymentCard({ p }: { p: ReceivedPayment }) {
  const navigate = useNavigate();
  return (
    <div className="rounded-md border border-border p-3 space-y-2">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="font-medium text-foreground">{p.payer_name || "—"}</div>
          {p.payer_phone && (
            <div className="text-xs text-muted-foreground">{p.payer_phone}</div>
          )}
        </div>
        <StatusBadge status={p.status} />
      </div>
      <div className="grid grid-cols-3 gap-2 text-xs">
        <div>
          <div className="text-muted-foreground">Gross</div>
          <div className="font-medium text-foreground">
            {fmtMoney(p.gross_amount, p.currency_code)}
          </div>
        </div>
        <div>
          <div className="text-muted-foreground">Commission</div>
          <div className="text-foreground">
            {fmtMoney(p.commission_amount, p.currency_code)}
          </div>
        </div>
        <div>
          <div className="text-muted-foreground">Net</div>
          <div className="font-semibold text-foreground">
            {fmtMoney(p.net_amount, p.currency_code)}
          </div>
        </div>
      </div>
      <div className="text-xs text-muted-foreground flex items-center justify-between">
        <span className="font-mono">{p.transaction_code}</span>
        <span>{fmtDate(p.confirmed_at || p.completed_at || p.initiated_at)}</span>
      </div>
      {(p.provider_name || p.method_type || p.is_offline) && (
        <div className="text-xs text-muted-foreground flex items-center justify-between">
          <span>
            {p.provider_name || p.method_type ? `via ${p.provider_name || p.method_type}` : ""}
            {p.is_offline ? " - offline" : ""}
          </span>
          <Button
            variant="ghost"
            size="sm"
            className="h-7 px-2 gap-1 text-xs"
            onClick={() => openPaymentReceipt(navigate, p)}
          >
            <Printer className="w-3.5 h-3.5" /> Print
          </Button>
        </div>
      )}
    </div>
  );
}
