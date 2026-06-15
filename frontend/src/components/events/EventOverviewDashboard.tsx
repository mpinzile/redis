/**
 * EventOverviewDashboard — premium overview block aligned with the design mockup.
 * All values come from the backend `getManagementOverview` endpoint — never hardcoded.
 */
import { useEffect, useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ArrowUpRight, ArrowDownRight } from "lucide-react";
import { eventsApi } from "@/lib/api";
import { useCurrency } from "@/hooks/useCurrency";
import { cn } from "@/lib/utils";

type Overview = Awaited<ReturnType<typeof eventsApi.getManagementOverview>>["data"];

interface Props {
  eventId: string;
  refreshKey?: number;
}

const SLICE_COLORS = ["#F5B400", "#111827", "#6B7280", "#D1D5DB"];

export default function EventOverviewDashboard({ eventId, refreshKey }: Props) {
  const { format } = useCurrency();
  const [data, setData] = useState<Overview | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    eventsApi
      .getManagementOverview(eventId)
      .then((res) => alive && setData(res.success ? (res.data as Overview) : null))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [eventId, refreshKey]);

  if (loading || !data) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {[0, 1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-20 rounded-2xl" />
          ))}
        </div>
        <div className="grid md:grid-cols-2 gap-4">
          <Skeleton className="h-72 rounded-2xl" />
          <Skeleton className="h-72 rounded-2xl" />
        </div>
      </div>
    );
  }

  const { kpis, ticket_sales, contribution_status, revenue_summary, is_ticketed } = data;

  // Build donut slices: tickets when ticketed, contribution status otherwise
  const donutSlices: { label: string; value: number; color: string }[] = is_ticketed
    ? ticket_sales.classes.map((c, i) => ({ label: c.name, value: c.sold, color: SLICE_COLORS[i % SLICE_COLORS.length] }))
    : [
        { label: "Paid", value: (contribution_status as any).fully_paid_count ?? contribution_status.paid_count, color: "#16A34A" },
        { label: "In Progress", value: (contribution_status as any).in_progress_count ?? 0, color: "#E7A622" },
        { label: "Outstanding", value: contribution_status.outstanding_count, color: "#DC2626" },
      ];
  const donutTotal = donutSlices.reduce((a, b) => a + b.value, 0);
  const centerNumber = is_ticketed
    ? ticket_sales.total_sold
    : donutSlices.reduce((a, b) => a + b.value, 0);
  const centerLabel = is_ticketed ? "Total Sold" : "Contributions";

  return (
    <div className="space-y-5">
      {/* KPI strip */}
      <div>
        <h3 className="text-sm font-bold mb-3">Event Overview</h3>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {is_ticketed && (
            <KpiCard value={kpis.tickets_sold.toLocaleString()} label="Tickets Sold" />
          )}
          <KpiCard value={format(kpis.total_revenue)} label="Total Revenue" />
          <KpiCard value={kpis.contributions_count.toLocaleString()} label="Contributions" />
          <KpiCard value={kpis.days_to_go.toString()} label="Days to Go" />
        </div>
      </div>

      {/* Donut + revenue summary */}
      <div className="grid md:grid-cols-2 gap-4">
        <Card className="rounded-2xl">
          <CardContent className="p-5">
            <h3 className="text-sm font-bold mb-4">{is_ticketed ? "Ticket Sales" : "Contribution Status"}</h3>
            <div className="flex justify-center">
              <Donut slices={donutSlices} centerNumber={centerNumber} centerLabel={centerLabel} />
            </div>
            <div className="mt-5 space-y-2.5">
              {donutSlices.map((s) => {
                const pct = donutTotal > 0 ? Math.round((s.value / donutTotal) * 100) : 0;
                return (
                  <div key={s.label} className="flex items-center gap-2 text-sm">
                    <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ background: s.color }} />
                    <span className="flex-1 text-foreground">{s.label}</span>
                    <span className="font-semibold tabular-nums">
                      {s.value.toLocaleString()} <span className="text-muted-foreground font-normal">({pct}%)</span>
                    </span>
                  </div>
                );
              })}
              {donutTotal === 0 && (
                <p className="text-xs text-muted-foreground text-center pt-2">No data yet</p>
              )}
            </div>
          </CardContent>
        </Card>

        <Card className="rounded-2xl">
          <CardContent className="p-5">
            <h3 className="text-sm font-bold mb-4">Revenue Summary</h3>
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-xs text-muted-foreground">Total Revenue</p>
                <p className="text-2xl font-bold mt-0.5 tracking-tight">{format(revenue_summary.total_revenue)}</p>
                <p className="text-[11px] text-muted-foreground mt-0.5">vs last {revenue_summary.trend_window_days} days</p>
              </div>
              {revenue_summary.trend_pct !== null && (
                <span
                  className={cn(
                    "inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-semibold",
                    revenue_summary.trend_pct >= 0
                      ? "bg-emerald-50 text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-400"
                      : "bg-rose-50 text-rose-700 dark:bg-rose-900/20 dark:text-rose-400"
                  )}
                >
                  {revenue_summary.trend_pct >= 0 ? (
                    <ArrowUpRight className="w-3 h-3" />
                  ) : (
                    <ArrowDownRight className="w-3 h-3" />
                  )}
                  {Math.abs(revenue_summary.trend_pct)}%
                </span>
              )}
            </div>
            <div className="mt-5 divide-y divide-border">
              <RevRow label="Tickets" value={format(revenue_summary.tickets)} />
              <RevRow label="Contributions" value={format(revenue_summary.contributions)} />
              <RevRow label="Sponsors" value={format(revenue_summary.sponsors)} />
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function KpiCard({ value, label }: { value: string; label: string }) {
  return (
    <Card className="rounded-2xl">
      <CardContent className="p-4">
        <p className="text-lg sm:text-xl font-bold tracking-tight tabular-nums truncate">{value}</p>
        <p className="text-[11px] text-muted-foreground mt-1">{label}</p>
      </CardContent>
    </Card>
  );
}

function RevRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between py-3 first:pt-0 last:pb-0">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span className="text-sm font-semibold tabular-nums">{value}</span>
    </div>
  );
}

function Donut({
  slices,
  centerNumber,
  centerLabel,
  size = 180,
  stroke = 28,
}: {
  slices: { label: string; value: number; color: string }[];
  centerNumber: number;
  centerLabel: string;
  size?: number;
  stroke?: number;
}) {
  const total = slices.reduce((a, b) => a + b.value, 0);
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  let offset = 0;
  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="hsl(var(--muted))" strokeWidth={stroke} />
        {total > 0 &&
          slices.map((s, i) => {
            const len = (s.value / total) * c;
            const dasharray = `${len} ${c - len}`;
            const el = (
              <circle
                key={i}
                cx={size / 2}
                cy={size / 2}
                r={r}
                fill="none"
                stroke={s.color}
                strokeWidth={stroke}
                strokeDasharray={dasharray}
                strokeDashoffset={-offset}
                strokeLinecap="butt"
              />
            );
            offset += len;
            return el;
          })}
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-2xl font-bold tracking-tight tabular-nums">{centerNumber.toLocaleString()}</span>
        <span className="text-[11px] text-muted-foreground mt-0.5">{centerLabel}</span>
      </div>
    </div>
  );
}
