/**
 * AdminPaymentsOverview — KPI cards, 30-day trend, country donut, status mix.
 * All numbers come from /admin/payments/summary.
 */
import { useQuery } from "@tanstack/react-query";
import {
  ArrowUpRight, ArrowDownRight, Wallet, AlertTriangle, RefreshCcw,
  Banknote, Coins, ClipboardCheck, Hourglass, ShieldAlert,
} from "lucide-react";
import {
  AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, BarChart, Bar, CartesianGrid, Legend,
} from "recharts";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { adminPaymentsOpsApi } from "@/lib/api/adminPaymentsOps";
import { fmtMoney, fmtNumber } from "./_shared";

const COUNTRY_COLORS = ["hsl(var(--primary))", "hsl(220 70% 55%)", "hsl(280 65% 60%)", "hsl(160 65% 45%)"];
const STATUS_COLORS: Record<string, string> = {
  succeeded: "hsl(142 70% 45%)",
  pending: "hsl(38 90% 55%)",
  processing: "hsl(45 95% 55%)",
  failed: "hsl(0 75% 55%)",
  cancelled: "hsl(0 60% 65%)",
  refunded: "hsl(260 65% 60%)",
};

export default function AdminPaymentsOverview() {
  const { data, isLoading, refetch, isFetching } = useQuery({
    queryKey: ["admin-payments-summary"],
    queryFn: async () => {
      const res = await adminPaymentsOpsApi.summary();
      return res.success ? res.data : null;
    },
    refetchInterval: 60_000,
  });

  if (isLoading) return <OverviewSkeleton />;
  if (!data) return (
    <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">
      Couldn't load summary. The backend endpoint may be offline.
    </CardContent></Card>
  );

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <p className="text-xs text-muted-foreground">
          Refreshes every minute - {isFetching && "Updating…"}
        </p>
        <button
          onClick={() => refetch()}
          className="inline-flex items-center gap-1.5 text-xs font-medium text-muted-foreground hover:text-foreground transition-colors"
        >
          <RefreshCcw className="w-3.5 h-3.5" /> Refresh
        </button>
      </div>

      {/* KPI grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <KpiCard
          icon={Banknote} tone="primary"
          label="Today (gross)" value={fmtMoney(data.today.gross, "TZS")}
          sub={`${data.today.count} payments - net ${fmtMoney(data.today.net, "TZS")}`}
        />
        <KpiCard
          icon={Coins} tone="success"
          label="This week" value={fmtMoney(data.week.gross, "TZS")}
          sub={`Commission ${fmtMoney(data.week.commission, "TZS")}`}
        />
        <KpiCard
          icon={Wallet} tone="info"
          label="This month" value={fmtMoney(data.month.gross, "TZS")}
          sub={`${data.month.count} payments`}
        />
        <KpiCard
          icon={ClipboardCheck} tone="muted"
          label="Wallet liability" value={fmtMoney(data.wallet_liability, "TZS")}
          sub="Owed to users"
        />

        <KpiCard
          icon={Hourglass} tone="warning"
          label="Pending payouts"
          value={fmtMoney(data.pending_payouts.amount, "TZS")}
          sub={`${data.pending_payouts.count} requests`}
        />
        <KpiCard
          icon={ArrowUpRight} tone="success"
          label="Completed (30d)"
          value={fmtMoney(data.completed_payouts_30d.amount, "TZS")}
          sub={`${data.completed_payouts_30d.count} settlements`}
        />
        <KpiCard
          icon={ArrowDownRight} tone="danger"
          label="Failed (30d)" value={fmtNumber(data.failed_count_30d)}
          sub="Investigate in Ledger"
        />
        <KpiCard
          icon={ShieldAlert} tone="warning"
          label="Reviews needed" value={fmtNumber(data.reviews_needed)}
          sub="Open Settlements"
        />
      </div>

      {/* Charts row */}
      <div className="grid lg:grid-cols-3 gap-4">
        <Card className="lg:col-span-2">
          <CardContent className="p-5">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-sm font-semibold">Volume — last 30 days</h3>
                <p className="text-xs text-muted-foreground mt-0.5">Gross collections vs. commission earned</p>
              </div>
            </div>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={data.series_30d}>
                  <defs>
                    <linearGradient id="grossGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity={0.35} />
                      <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity={0} />
                    </linearGradient>
                    <linearGradient id="commGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="hsl(142 70% 45%)" stopOpacity={0.3} />
                      <stop offset="100%" stopColor="hsl(142 70% 45%)" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
                  <XAxis
                    dataKey="date"
                    tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }}
                    tickLine={false} axisLine={false}
                    tickFormatter={(v) => {
                      const d = new Date(v);
                      return `${d.getDate()}/${d.getMonth() + 1}`;
                    }}
                  />
                  <YAxis
                    tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }}
                    tickLine={false} axisLine={false}
                    tickFormatter={(v) => v >= 1000000 ? `${(v / 1e6).toFixed(1)}M` : v >= 1000 ? `${(v / 1000).toFixed(0)}k` : v}
                  />
                  <Tooltip
                    contentStyle={{
                      background: "hsl(var(--popover))",
                      border: "1px solid hsl(var(--border))",
                      borderRadius: 8, fontSize: 12,
                    }}
                    formatter={(v: any) => fmtMoney(Number(v), "TZS")}
                  />
                  <Area type="monotone" dataKey="gross" stroke="hsl(var(--primary))" fill="url(#grossGrad)" strokeWidth={2} />
                  <Area type="monotone" dataKey="commission" stroke="hsl(142 70% 45%)" fill="url(#commGrad)" strokeWidth={2} />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-5">
            <h3 className="text-sm font-semibold mb-1">Country mix</h3>
            <p className="text-xs text-muted-foreground mb-4">This month, by gross</p>
            {data.country_mix_month.length === 0 ? (
              <p className="text-xs text-muted-foreground py-10 text-center">No data this month</p>
            ) : (
              <div className="h-56">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={data.country_mix_month}
                      dataKey="gross" nameKey="country_code"
                      innerRadius={50} outerRadius={80} paddingAngle={2}
                    >
                      {data.country_mix_month.map((_, i) => (
                        <Cell key={i} fill={COUNTRY_COLORS[i % COUNTRY_COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip
                      contentStyle={{
                        background: "hsl(var(--popover))",
                        border: "1px solid hsl(var(--border))",
                        borderRadius: 8, fontSize: 12,
                      }}
                      formatter={(v: any, name: any) => [fmtMoney(Number(v), "TZS"), name]}
                    />
                    <Legend wrapperStyle={{ fontSize: 11 }} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Status mix bar */}
      <Card>
        <CardContent className="p-5">
          <h3 className="text-sm font-semibold mb-1">Status mix — this month</h3>
          <p className="text-xs text-muted-foreground mb-4">Count of payments by terminal status</p>
          {data.status_mix_month.length === 0 ? (
            <p className="text-xs text-muted-foreground py-10 text-center">No data</p>
          ) : (
            <div className="h-52">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={data.status_mix_month}>
                  <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
                  <XAxis dataKey="status" tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }} tickLine={false} axisLine={false} />
                  <YAxis tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }} tickLine={false} axisLine={false} />
                  <Tooltip
                    contentStyle={{
                      background: "hsl(var(--popover))",
                      border: "1px solid hsl(var(--border))",
                      borderRadius: 8, fontSize: 12,
                    }}
                  />
                  <Bar dataKey="count" radius={[6, 6, 0, 0]}>
                    {data.status_mix_month.map((s, i) => (
                      <Cell key={i} fill={STATUS_COLORS[s.status] ?? "hsl(var(--muted-foreground))"} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function KpiCard({
  icon: Icon, tone, label, value, sub,
}: {
  icon: any;
  tone: "primary" | "success" | "danger" | "warning" | "info" | "muted";
  label: string;
  value: string;
  sub?: string;
}) {
  const toneClass = {
    primary: "from-primary/10 text-primary",
    success: "from-emerald-500/10 text-emerald-600 dark:text-emerald-400",
    danger:  "from-red-500/10 text-red-600 dark:text-red-400",
    warning: "from-amber-500/10 text-amber-600 dark:text-amber-400",
    info:    "from-blue-500/10 text-blue-600 dark:text-blue-400",
    muted:   "from-muted text-muted-foreground",
  }[tone];

  return (
    <Card className="overflow-hidden">
      <CardContent className="p-4">
        <div className="flex items-start justify-between">
          <div className={cn("h-9 w-9 rounded-lg bg-gradient-to-br to-transparent flex items-center justify-center", toneClass)}>
            <Icon className="w-4 h-4" />
          </div>
        </div>
        <p className="text-[11px] uppercase tracking-wide text-muted-foreground mt-3">{label}</p>
        <p className="text-lg font-bold text-foreground mt-0.5 truncate">{value}</p>
        {sub && <p className="text-[11px] text-muted-foreground mt-0.5 truncate">{sub}</p>}
      </CardContent>
    </Card>
  );
}

function OverviewSkeleton() {
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {Array.from({ length: 8 }).map((_, i) => <Skeleton key={i} className="h-28" />)}
      </div>
      <div className="grid lg:grid-cols-3 gap-4">
        <Skeleton className="h-72 lg:col-span-2" />
        <Skeleton className="h-72" />
      </div>
      <Skeleton className="h-60" />
    </div>
  );
}
