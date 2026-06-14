/**
 * AdminPaymentsLedger — every payment that hit Nuru, with filters and a
 * drilldown drawer showing payer, beneficiary, commission, ledger entries
 * and admin history.
 */
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  Search, Loader2, ChevronLeft, ChevronRight, ExternalLink, Filter,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { adminPaymentsOpsApi, type LedgerRow } from "@/lib/api/adminPaymentsOps";
import { fmtDateTime, fmtMoney, StatusBadge, describeReason } from "./_shared";

const STATUSES = ["all", "pending", "processing", "succeeded", "failed", "cancelled", "refunded"];

export default function AdminPaymentsLedger() {
  const [page, setPage] = useState(1);
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("all");
  const [country, setCountry] = useState("all");
  const [selected, setSelected] = useState<string | null>(null);

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ["admin-payments-ledger", page, q, status, country],
    queryFn: async () => {
      const res = await adminPaymentsOpsApi.ledger({
        page, limit: 25,
        q: q.trim() || undefined,
        status: status === "all" ? undefined : status,
        country_code: country === "all" ? undefined : country,
      });
      return res.success ? res.data : null;
    },
    placeholderData: (prev) => prev,
  });

  return (
    <div className="space-y-3">
      <Card>
        <CardContent className="p-3 flex flex-wrap items-center gap-2">
          <div className="relative flex-1 min-w-[220px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }}
              placeholder="Search code, payer, beneficiary, reference…"
              className="pl-9 h-9"
            />
          </div>
          <Select value={status} onValueChange={(v) => { setStatus(v); setPage(1); }}>
            <SelectTrigger className="w-36 h-9 text-xs"><Filter className="w-3 h-3 mr-1" /><SelectValue /></SelectTrigger>
            <SelectContent>
              {STATUSES.map((s) => <SelectItem key={s} value={s} className="text-xs capitalize">{s}</SelectItem>)}
            </SelectContent>
          </Select>
          <Select value={country} onValueChange={(v) => { setCountry(v); setPage(1); }}>
            <SelectTrigger className="w-28 h-9 text-xs"><SelectValue placeholder="Country" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all" className="text-xs">All</SelectItem>
              <SelectItem value="TZ" className="text-xs">TZ</SelectItem>
              <SelectItem value="KE" className="text-xs">KE</SelectItem>
            </SelectContent>
          </Select>
        </CardContent>
      </Card>

      {isLoading ? (
        <Card><CardContent className="py-12 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-muted-foreground" /></CardContent></Card>
      ) : !data?.transactions?.length ? (
        <Card><CardContent className="py-12 text-center text-sm text-muted-foreground">No transactions match the filters.</CardContent></Card>
      ) : (
        <Card className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-xs min-w-[900px]">
              <thead className="bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="text-left px-3 py-2.5 font-semibold">When</th>
                  <th className="text-left px-3 py-2.5 font-semibold">Code</th>
                  <th className="text-left px-3 py-2.5 font-semibold">Payer</th>
                  <th className="text-left px-3 py-2.5 font-semibold">Beneficiary</th>
                  <th className="text-left px-3 py-2.5 font-semibold">Reason</th>
                  <th className="text-right px-3 py-2.5 font-semibold">Gross</th>
                  <th className="text-right px-3 py-2.5 font-semibold">Comm.</th>
                  <th className="text-right px-3 py-2.5 font-semibold">Net</th>
                  <th className="text-center px-3 py-2.5 font-semibold">Status</th>
                  <th className="px-3 py-2.5"></th>
                </tr>
              </thead>
              <tbody>
                {data.transactions.map((t: LedgerRow) => (
                  <tr key={t.id} className="border-t border-border hover:bg-muted/20 transition-colors">
                    <td className="px-3 py-2.5 text-muted-foreground whitespace-nowrap">{fmtDateTime(t.created_at)}</td>
                    <td className="px-3 py-2.5 font-mono text-[11px]">{t.transaction_code}</td>
                    <td className="px-3 py-2.5">
                      <div className="font-medium text-foreground">{t.payer?.name ?? "—"}</div>
                      <div className="text-[10px] text-muted-foreground">{t.payer?.phone ?? ""}</div>
                    </td>
                    <td className="px-3 py-2.5">
                      <div className="font-medium text-foreground">{t.beneficiary?.name ?? "—"}</div>
                      <div className="text-[10px] text-muted-foreground">{t.country_code}</div>
                    </td>
                    <td className="px-3 py-2.5 max-w-[200px] truncate" title={describeReason(t.target_type, t.target_name, t.payment_description)}>
                      {describeReason(t.target_type, t.target_name, t.payment_description)}
                    </td>
                    <td className="px-3 py-2.5 text-right font-semibold">{fmtMoney(t.gross_amount, t.currency_code)}</td>
                    <td className="px-3 py-2.5 text-right text-muted-foreground">{fmtMoney(t.commission_amount, t.currency_code)}</td>
                    <td className="px-3 py-2.5 text-right text-emerald-600 dark:text-emerald-400 font-medium">{fmtMoney(t.net_amount, t.currency_code)}</td>
                    <td className="px-3 py-2.5 text-center"><StatusBadge status={t.status} /></td>
                    <td className="px-3 py-2.5 text-right">
                      <Button size="sm" variant="ghost" className="h-7 px-2" onClick={() => setSelected(t.id)}>
                        <ExternalLink className="w-3.5 h-3.5" />
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {data?.pagination && (
        <div className="flex items-center justify-between text-xs text-muted-foreground pt-1">
          <span>Page {page} {isFetching && <Loader2 className="inline w-3 h-3 animate-spin ml-1" />}</span>
          <div className="flex gap-1.5">
            <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))} className="h-8">
              <ChevronLeft className="w-3.5 h-3.5" />
            </Button>
            <Button size="sm" variant="outline" disabled={!(data.pagination as any)?.has_more} onClick={() => setPage((p) => p + 1)} className="h-8">
              <ChevronRight className="w-3.5 h-3.5" />
            </Button>
          </div>
        </div>
      )}

      <LedgerDrawer txId={selected} onClose={() => setSelected(null)} />
    </div>
  );
}

function LedgerDrawer({ txId, onClose }: { txId: string | null; onClose: () => void }) {
  const { data, isLoading } = useQuery({
    queryKey: ["admin-payments-ledger-detail", txId],
    queryFn: async () => {
      if (!txId) return null;
      const res = await adminPaymentsOpsApi.ledgerDetail(txId);
      return res.success ? res.data : null;
    },
    enabled: !!txId,
  });

  return (
    <Sheet open={!!txId} onOpenChange={(o) => !o && onClose()}>
      <SheetContent className="sm:max-w-xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Transaction details</SheetTitle>
        </SheetHeader>
        {isLoading || !data ? (
          <div className="py-12 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-muted-foreground" /></div>
        ) : (
          <div className="space-y-5 mt-4 text-sm">
            <div className="grid grid-cols-2 gap-3">
              <Field label="Code">{data.transaction_code}</Field>
              <Field label="Status"><StatusBadge status={data.status} /></Field>
              <Field label="Created">{fmtDateTime(data.created_at)}</Field>
              <Field label="Completed">{fmtDateTime(data.completed_at)}</Field>
              <Field label="Country">{data.country_code}</Field>
              <Field label="Method">{data.method_type}</Field>
            </div>

            <Section title="Amounts">
              <Row label="Gross">{fmtMoney(data.gross_amount, data.currency_code)}</Row>
              <Row label="Commission">{fmtMoney(data.commission_amount, data.currency_code)}</Row>
              <Row label="Net to beneficiary" emphasis>{fmtMoney(data.net_amount, data.currency_code)}</Row>
            </Section>

            <Section title="Payer">
              <Row label="Name">{data.payer?.name ?? "—"}</Row>
              <Row label="Phone">{data.payer?.phone ?? "—"}</Row>
              <Row label="Email">{data.payer?.email ?? "—"}</Row>
            </Section>

            <Section title="Beneficiary">
              <Row label="Name">{data.beneficiary?.name ?? "—"}</Row>
              <Row label="Phone">{data.beneficiary?.phone ?? "—"}</Row>
              <Row label="Email">{data.beneficiary?.email ?? "—"}</Row>
            </Section>

            <Section title="Reason">
              <p className="text-foreground">{describeReason(data.target_type, data.target_name, data.payment_description)}</p>
              {((data as any).failure_reason || (data as any).failure_reason_from_callbacks) && (
                <p className="mt-2 text-xs text-destructive">
                  <span className="font-semibold">Failure: </span>
                  {(data as any).failure_reason || (data as any).failure_reason_from_callbacks}
                </p>
              )}
            </Section>

            <Section title="Provider">
              <Row label="Name">{data.provider_name ?? "—"}</Row>
              <Row label="External reference"><span className="font-mono text-xs">{data.external_reference ?? "—"}</span></Row>
            </Section>

            <Section title={`Gateway callbacks (${((data as any).callback_logs ?? []).length})`}>
              {!((data as any).callback_logs ?? []).length ? (
                <p className="text-xs text-muted-foreground italic">
                  No callbacks have been received from the payment gateway for this transaction yet.
                  If this transaction is failed/stuck, the gateway never POSTed to our CallBackURL —
                  verify <span className="font-mono">API_BASE_URL</span> is publicly reachable and matches
                  the URL configured on the SasaPay merchant app.
                </p>
              ) : (
                <ul className="space-y-2">
                  {(data as any).callback_logs.map((c: any) => (
                    <li key={c.id} className="text-xs border-l-2 border-primary/40 pl-3 py-0.5">
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-foreground">
                          {c.gateway ?? "GATEWAY"} - code {c.result_code ?? "—"}
                        </span>
                        <span className="text-muted-foreground">{fmtDateTime(c.received_at)}</span>
                      </div>
                      {c.result_desc && (
                        <div className="text-muted-foreground mt-0.5">{c.result_desc}</div>
                      )}
                      {c.processing_error && (
                        <div className="text-destructive mt-0.5">⚠ {c.processing_error}</div>
                      )}
                      <details className="mt-1">
                        <summary className="cursor-pointer text-muted-foreground hover:text-foreground select-none">
                          Raw payload
                        </summary>
                        <pre className="mt-1 p-2 rounded bg-muted/40 text-[10px] overflow-x-auto whitespace-pre-wrap break-all">
{JSON.stringify(c.payload, null, 2)}
                        </pre>
                      </details>
                    </li>
                  ))}
                </ul>
              )}
            </Section>

            {Array.isArray(data.admin_history) && data.admin_history.length > 0 && (
              <Section title="Admin actions">
                <ul className="space-y-2">
                  {data.admin_history.map((h: any, i: number) => (
                    <li key={i} className="text-xs border-l-2 border-primary pl-3 py-0.5">
                      <div className="font-medium text-foreground">{h.action}</div>
                      <div className="text-muted-foreground">{fmtDateTime(h.created_at)} - {h.admin_name ?? "Admin"}</div>
                      {h.note && <div className="text-muted-foreground italic mt-0.5">"{h.note}"</div>}
                    </li>
                  ))}
                </ul>
              </Section>
            )}
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}

const Field = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <div>
    <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
    <p className="text-sm font-medium mt-0.5">{children}</p>
  </div>
);

const Section = ({ title, children }: { title: string; children: React.ReactNode }) => (
  <div>
    <p className="text-[10px] uppercase tracking-wide font-semibold text-muted-foreground mb-2">{title}</p>
    <div className="rounded-lg border border-border bg-muted/20 p-3 space-y-1.5">{children}</div>
  </div>
);

const Row = ({ label, emphasis, children }: { label: string; emphasis?: boolean; children: React.ReactNode }) => (
  <div className="flex items-center justify-between text-xs">
    <span className="text-muted-foreground">{label}</span>
    <span className={emphasis ? "font-semibold text-emerald-600 dark:text-emerald-400" : "font-medium text-foreground"}>{children}</span>
  </div>
);
