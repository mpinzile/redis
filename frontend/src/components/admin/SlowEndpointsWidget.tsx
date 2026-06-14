import { useEffect, useState } from "react";
import { Activity, AlertTriangle, Zap } from "lucide-react";
import { motion } from "framer-motion";
import { adminApi } from "@/lib/api/admin";
import { Skeleton } from "@/components/ui/skeleton";

interface EndpointRow {
  method: string;
  path: string;
  count: number;
  avg_ms: number;
  p95_ms: number;
  max_ms: number;
  slow_count: number;
  error_count: number;
}

interface SlowResponse {
  window_minutes: number;
  threshold_ms: number;
  total_samples: number;
  endpoints: EndpointRow[];
}

const methodTone = (m: string) => {
  switch (m) {
    case "GET":    return "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400";
    case "POST":   return "bg-blue-500/10 text-blue-600 dark:text-blue-400";
    case "PUT":    return "bg-amber-500/10 text-amber-600 dark:text-amber-400";
    case "DELETE": return "bg-rose-500/10 text-rose-600 dark:text-rose-400";
    default:       return "bg-muted text-muted-foreground";
  }
};

const msTone = (ms: number, threshold: number) => {
  if (ms >= threshold * 2) return "text-rose-500";
  if (ms >= threshold)     return "text-amber-500";
  return "text-foreground";
};

export default function SlowEndpointsWidget() {
  const [data, setData] = useState<SlowResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    const load = async () => {
      const r = await adminApi.getSlowEndpoints(60, 10);
      if (!alive) return;
      if (r.success) {
        setData(r.data);
        setError(null);
      } else {
        setError("Failed to load slow endpoints");
      }
      setLoading(false);
    };
    load();
    const id = setInterval(load, 30_000); // refresh every 30s
    return () => { alive = false; clearInterval(id); };
  }, []);

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: 0.1 }}
      className="bg-card border border-border/60 rounded-xl p-5"
    >
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <div className="w-9 h-9 rounded-xl bg-amber-500/10 flex items-center justify-center">
            <Activity className="w-4.5 h-4.5 text-amber-500" />
          </div>
          <div>
            <h3 className="text-sm font-bold tracking-tight text-foreground">Slowest Endpoints</h3>
            <p className="text-xs text-muted-foreground">
              {data
                ? `Last ${data.window_minutes} min - ${data.total_samples.toLocaleString()} requests - threshold ${data.threshold_ms}ms`
                : "Loading…"}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-1 text-[10px] text-muted-foreground uppercase tracking-wide">
          <Zap className="w-3 h-3" /> live
        </div>
      </div>

      {loading ? (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-10 w-full rounded-md" />
          ))}
        </div>
      ) : error ? (
        <div className="flex items-center gap-2 text-sm text-rose-500">
          <AlertTriangle className="w-4 h-4" /> {error}
        </div>
      ) : !data || data.endpoints.length === 0 ? (
        <div className="text-sm text-muted-foreground py-6 text-center">
          No traffic recorded yet. Slow endpoints will appear here as they happen.
        </div>
      ) : (
        <div className="overflow-x-auto -mx-2">
          <table className="w-full text-xs">
            <thead>
              <tr className="text-muted-foreground border-b border-border/40">
                <th className="text-left px-2 py-2 font-medium">Endpoint</th>
                <th className="text-right px-2 py-2 font-medium">Calls</th>
                <th className="text-right px-2 py-2 font-medium">Avg</th>
                <th className="text-right px-2 py-2 font-medium">p95</th>
                <th className="text-right px-2 py-2 font-medium">Max</th>
                <th className="text-right px-2 py-2 font-medium">Slow</th>
              </tr>
            </thead>
            <tbody>
              {data.endpoints.map((e) => (
                <tr key={`${e.method}-${e.path}`} className="border-b border-border/30 last:border-0 hover:bg-muted/30 transition-colors">
                  <td className="px-2 py-2">
                    <div className="flex items-center gap-2">
                      <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${methodTone(e.method)}`}>
                        {e.method}
                      </span>
                      <span className="font-mono text-[11px] text-foreground truncate max-w-[260px]" title={e.path}>
                        {e.path}
                      </span>
                    </div>
                  </td>
                  <td className="px-2 py-2 text-right text-muted-foreground tabular-nums">{e.count.toLocaleString()}</td>
                  <td className={`px-2 py-2 text-right font-semibold tabular-nums ${msTone(e.avg_ms, data.threshold_ms)}`}>
                    {e.avg_ms.toFixed(0)}ms
                  </td>
                  <td className={`px-2 py-2 text-right tabular-nums ${msTone(e.p95_ms, data.threshold_ms)}`}>
                    {e.p95_ms.toFixed(0)}ms
                  </td>
                  <td className="px-2 py-2 text-right text-muted-foreground tabular-nums">{e.max_ms.toFixed(0)}ms</td>
                  <td className="px-2 py-2 text-right">
                    {e.slow_count > 0 ? (
                      <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-amber-500/10 text-amber-600 dark:text-amber-400">
                        {e.slow_count}
                      </span>
                    ) : (
                      <span className="text-muted-foreground/50">0</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </motion.div>
  );
}
