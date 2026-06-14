import { useEffect, useState, useCallback } from "react";
import {
  Activity, Database, Server, Wifi, WifiOff,
  AlertTriangle, CheckCircle, RefreshCw, Clock,
  HardDrive, Layers, Zap, TrendingUp,
} from "lucide-react";
import { motion } from "framer-motion";
import { toast } from "sonner";
import { resolveApiBaseUrl } from "@/lib/api/helpers";

const BASE_URL = resolveApiBaseUrl();

async function monitorFetch<T>(path: string): Promise<T | null> {
  const token = localStorage.getItem("admin_token");
  try {
    const res = await fetch(`${BASE_URL}/admin/monitoring${path}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error(`${res.status}`);
    const json = await res.json();
    return json.data as T;
  } catch {
    return null;
  }
}

interface RedisData {
  status: string;
  uptime_seconds?: number;
  connected_clients?: number;
  used_memory_mb?: number;
  peak_memory_mb?: number;
  total_keys?: number;
  cache_hit_rate_pct?: number;
  keyspace_hits?: number;
  keyspace_misses?: number;
  ops_per_second?: number;
  key_prefixes?: Record<string, number>;
  alerts?: Alert[];
}

interface CeleryData {
  workers: Record<string, { status: string; active_tasks: number; pool_size: number | string; uptime: number }> | { error?: string };
  queues: Record<string, number | string>;
  scheduled_tasks: { name: string; task: string; schedule: string }[];
  alerts?: Alert[];
}

interface DbData {
  pool: { pool_size?: number; checked_in?: number; checked_out?: number; overflow?: number };
  active_connections: number;
  table_sizes: { table: string; size: string; size_bytes: number; rows: number; error?: string }[];
  slow_queries: { query: string; calls: number; mean_ms: number; total_ms: number; rows: number; cache_hit_ratio: number; note?: string }[];
  alerts?: Alert[];
}

interface HealthData {
  redis: string;
  celery: string;
  api: string;
}

interface Alert {
  level: "warning" | "critical";
  message: string;
}

function StatusBadge({ status }: { status: string }) {
  const ok = status === "ok" || status === "connected" || status === "online";
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold ${ok ? "bg-emerald-500/15 text-emerald-400" : "bg-destructive/15 text-destructive"}`}>
      {ok ? <CheckCircle className="w-3 h-3" /> : <WifiOff className="w-3 h-3" />}
      {status}
    </span>
  );
}

function AlertBanner({ alerts }: { alerts: Alert[] }) {
  if (!alerts?.length) return null;
  return (
    <div className="space-y-1.5 mb-3">
      {alerts.map((a, i) => (
        <div key={i} className={`flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-medium ${a.level === "critical" ? "bg-destructive/15 text-destructive" : "bg-amber-500/15 text-amber-400"}`}>
          <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
          {a.message}
        </div>
      ))}
    </div>
  );
}

function Card({ title, icon: Icon, children, loading }: { title: string; icon: React.ElementType; children: React.ReactNode; loading?: boolean }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-card border border-border rounded-xl p-5"
    >
      <div className="flex items-center gap-2 mb-4">
        <Icon className="w-4 h-4 text-primary" />
        <h3 className="text-sm font-bold text-foreground">{title}</h3>
      </div>
      {loading ? (
        <div className="space-y-2">
          {[1, 2, 3].map(i => <div key={i} className="h-4 bg-muted/60 rounded animate-pulse" />)}
        </div>
      ) : children}
    </motion.div>
  );
}

function Stat({ label, value, unit, warn }: { label: string; value: string | number | undefined; unit?: string; warn?: boolean }) {
  return (
    <div className="flex flex-col">
      <span className="text-[11px] text-muted-foreground uppercase tracking-wide">{label}</span>
      <span className={`text-lg font-bold ${warn ? "text-amber-400" : "text-foreground"}`}>
        {value ?? "—"}{unit && <span className="text-xs text-muted-foreground ml-0.5">{unit}</span>}
      </span>
    </div>
  );
}

function formatUptime(seconds?: number): string {
  if (!seconds) return "—";
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

export default function AdminMonitoring() {
  const [redis, setRedis] = useState<RedisData | null>(null);
  const [celery, setCelery] = useState<CeleryData | null>(null);
  const [db, setDb] = useState<DbData | null>(null);
  const [health, setHealth] = useState<HealthData | null>(null);
  const [loading, setLoading] = useState(true);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);

  const fetchAll = useCallback(async () => {
    setLoading(true);
    const [r, c, d, h] = await Promise.all([
      monitorFetch<RedisData>("/redis"),
      monitorFetch<CeleryData>("/celery"),
      monitorFetch<DbData>("/database"),
      monitorFetch<HealthData>("/health"),
    ]);
    setRedis(r);
    setCelery(c);
    setDb(d);
    setHealth(h);
    setLastRefresh(new Date());
    setLoading(false);
  }, []);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  // Auto-refresh every 30s
  useEffect(() => {
    const interval = setInterval(fetchAll, 30000);
    return () => clearInterval(interval);
  }, [fetchAll]);

  const allAlerts = [
    ...(redis?.alerts || []),
    ...(celery?.alerts || []),
    ...(db?.alerts || []),
  ];

  const workers = celery?.workers && !("error" in celery.workers) ? celery.workers : null;

  return (
    <div className="space-y-6 max-w-7xl">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-foreground">System Monitoring</h1>
          <p className="text-xs text-muted-foreground mt-0.5">
            {lastRefresh ? `Last refreshed ${lastRefresh.toLocaleTimeString()}` : "Loading..."} - Auto-refreshes every 30s
          </p>
        </div>
        <button
          onClick={() => { fetchAll(); toast.success("Refreshed"); }}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary/10 text-primary text-xs font-medium hover:bg-primary/20 transition"
        >
          <RefreshCw className="w-3.5 h-3.5" /> Refresh
        </button>
      </div>

      {/* Global Alerts */}
      {allAlerts.length > 0 && (
        <div className="bg-card border border-destructive/30 rounded-xl p-4">
          <div className="flex items-center gap-2 mb-2">
            <AlertTriangle className="w-4 h-4 text-destructive" />
            <span className="text-sm font-bold text-destructive">{allAlerts.length} Active Alert{allAlerts.length > 1 ? "s" : ""}</span>
          </div>
          <AlertBanner alerts={allAlerts} />
        </div>
      )}

      {/* Health Status Row */}
      <div className="grid grid-cols-3 gap-3">
        {(["redis", "celery", "api"] as const).map((svc) => {
          const status = health?.[svc] || "unknown";
          const ok = status === "ok";
          const icons = { redis: Database, celery: Layers, api: Server };
          const Icon = icons[svc];
          return (
            <motion.div
              key={svc}
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              className={`flex items-center gap-3 px-4 py-3 rounded-xl border ${ok ? "border-emerald-500/30 bg-emerald-500/5" : "border-destructive/30 bg-destructive/5"}`}
            >
              <Icon className={`w-5 h-5 ${ok ? "text-emerald-400" : "text-destructive"}`} />
              <div>
                <div className="text-xs font-bold text-foreground capitalize">{svc}</div>
                <div className={`text-[11px] font-medium ${ok ? "text-emerald-400" : "text-destructive"}`}>{status}</div>
              </div>
            </motion.div>
          );
        })}
      </div>

      {/* Redis */}
      <Card title="Redis Cache" icon={Database} loading={loading && !redis}>
        {redis?.status === "unavailable" ? (
          <p className="text-sm text-muted-foreground">Redis is not connected</p>
        ) : redis ? (
          <>
            <AlertBanner alerts={redis.alerts || []} />
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-4">
              <Stat label="Hit Rate" value={redis.cache_hit_rate_pct} unit="%" warn={redis.cache_hit_rate_pct !== undefined && redis.cache_hit_rate_pct < 80} />
              <Stat label="Memory" value={redis.used_memory_mb} unit="MB" />
              <Stat label="Clients" value={redis.connected_clients} />
              <Stat label="Keys" value={redis.total_keys} />
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-4">
              <Stat label="Ops/sec" value={redis.ops_per_second} />
              <Stat label="Hits" value={redis.keyspace_hits?.toLocaleString()} />
              <Stat label="Misses" value={redis.keyspace_misses?.toLocaleString()} />
              <Stat label="Uptime" value={formatUptime(redis.uptime_seconds)} />
            </div>
            {redis.key_prefixes && Object.keys(redis.key_prefixes).length > 0 && (
              <div>
                <h4 className="text-xs font-semibold text-muted-foreground mb-2 uppercase">Key Prefixes</h4>
                <div className="flex flex-wrap gap-1.5">
                  {Object.entries(redis.key_prefixes).slice(0, 12).map(([prefix, count]) => (
                    <span key={prefix} className="px-2 py-0.5 bg-muted/60 text-foreground text-[11px] rounded-md font-mono">
                      {prefix}: {count}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </>
        ) : <p className="text-sm text-muted-foreground">Failed to load Redis stats</p>}
      </Card>

      {/* Celery */}
      <Card title="Celery Workers & Queues" icon={Layers} loading={loading && !celery}>
        {celery ? (
          <>
            <AlertBanner alerts={celery.alerts || []} />
            {/* Workers */}
            <h4 className="text-xs font-semibold text-muted-foreground mb-2 uppercase">Workers</h4>
            {workers ? (
              <div className="space-y-2 mb-4">
                {Object.entries(workers).map(([name, info]) => (
                  <div key={name} className="flex items-center justify-between px-3 py-2 bg-muted/30 rounded-lg">
                    <div className="flex items-center gap-2">
                      <StatusBadge status={info.status} />
                      <span className="text-xs font-mono text-foreground truncate max-w-[200px]">{name}</span>
                    </div>
                    <div className="flex items-center gap-4 text-xs text-muted-foreground">
                      <span><Zap className="w-3 h-3 inline mr-0.5" />{info.active_tasks} active</span>
                      <span>pool: {info.pool_size}</span>
                      <span><Clock className="w-3 h-3 inline mr-0.5" />{formatUptime(info.uptime)}</span>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-xs text-muted-foreground mb-4">No workers detected or workers offline</p>
            )}

            {/* Queue Depths */}
            <h4 className="text-xs font-semibold text-muted-foreground mb-2 uppercase">Queue Depths</h4>
            <div className="grid grid-cols-2 gap-3 mb-4">
              {Object.entries(celery.queues).map(([queue, depth]) => {
                const d = typeof depth === "number" ? depth : 0;
                const warn = d > 100;
                return (
                  <div key={queue} className={`px-3 py-2 rounded-lg border ${warn ? "border-amber-500/40 bg-amber-500/5" : "border-border bg-muted/20"}`}>
                    <div className="text-[11px] text-muted-foreground uppercase">{queue}</div>
                    <div className={`text-lg font-bold ${warn ? "text-amber-400" : "text-foreground"}`}>{String(depth)}</div>
                  </div>
                );
              })}
            </div>

            {/* Scheduled Tasks */}
            {celery.scheduled_tasks?.length > 0 && (
              <>
                <h4 className="text-xs font-semibold text-muted-foreground mb-2 uppercase">Beat Schedule</h4>
                <div className="space-y-1">
                  {celery.scheduled_tasks.map((t, i) => (
                    <div key={i} className="flex items-center justify-between px-3 py-1.5 bg-muted/20 rounded text-xs">
                      <span className="font-mono text-foreground">{t.name}</span>
                      <span className="text-muted-foreground">{t.schedule}</span>
                    </div>
                  ))}
                </div>
              </>
            )}
          </>
        ) : <p className="text-sm text-muted-foreground">Failed to load Celery stats</p>}
      </Card>

      {/* Database */}
      <Card title="Database Performance" icon={HardDrive} loading={loading && !db}>
        {db ? (
          <>
            <AlertBanner alerts={db.alerts || []} />
            {/* Pool */}
            <div className="grid grid-cols-2 sm:grid-cols-5 gap-4 mb-4">
              <Stat label="Pool Size" value={db.pool.pool_size} />
              <Stat label="Checked In" value={db.pool.checked_in} />
              <Stat label="Checked Out" value={db.pool.checked_out} />
              <Stat label="Overflow" value={db.pool.overflow} />
              <Stat label="Active Conns" value={db.active_connections} />
            </div>

            {/* Table Sizes */}
            <h4 className="text-xs font-semibold text-muted-foreground mb-2 uppercase">Largest Tables</h4>
            <div className="overflow-x-auto mb-4">
              <table className="w-full text-xs">
                <thead>
                  <tr className="text-muted-foreground border-b border-border">
                    <th className="text-left py-1.5 pr-4">Table</th>
                    <th className="text-right py-1.5 pr-4">Size</th>
                    <th className="text-right py-1.5">Rows (est)</th>
                  </tr>
                </thead>
                <tbody>
                  {db.table_sizes.slice(0, 15).map((t, i) => (
                    <tr key={i} className="border-b border-border/40">
                      <td className="py-1.5 pr-4 font-mono text-foreground">{t.table}</td>
                      <td className="py-1.5 pr-4 text-right text-muted-foreground">{t.size}</td>
                      <td className="py-1.5 text-right text-muted-foreground">{t.rows?.toLocaleString() ?? "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Slow Queries */}
            <h4 className="text-xs font-semibold text-muted-foreground mb-2 uppercase flex items-center gap-1.5">
              <TrendingUp className="w-3.5 h-3.5" /> Slow Queries (mean &gt; 100ms)
            </h4>
            {db.slow_queries.length === 0 || db.slow_queries[0]?.note ? (
              <p className="text-xs text-muted-foreground">{db.slow_queries[0]?.note || "No slow queries detected"}</p>
            ) : (
              <div className="space-y-2">
                {db.slow_queries.map((q, i) => (
                  <div key={i} className="p-3 bg-muted/20 rounded-lg border border-border/40">
                    <code className="text-[11px] text-foreground/80 block mb-1.5 break-all leading-relaxed">{q.query}</code>
                    <div className="flex flex-wrap gap-3 text-[11px] text-muted-foreground">
                      <span>Mean: <strong className={q.mean_ms > 500 ? "text-destructive" : "text-foreground"}>{q.mean_ms}ms</strong></span>
                      <span>Calls: {q.calls.toLocaleString()}</span>
                      <span>Total: {(q.total_ms / 1000).toFixed(1)}s</span>
                      <span>Rows: {q.rows.toLocaleString()}</span>
                      <span>Cache Hit: {q.cache_hit_ratio}%</span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </>
        ) : <p className="text-sm text-muted-foreground">Failed to load DB stats</p>}
      </Card>
    </div>
  );
}
