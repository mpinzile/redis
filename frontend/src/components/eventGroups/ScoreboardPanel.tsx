/**
 * Premium scoreboard — leaderboard of contributors with pledges, paid,
 * outstanding, and balance. Polls softly every 8s.
 */
import { useEffect, useMemo, useState } from "react";
import { Trophy, TrendingUp, Wallet, Users, Crown, Medal, Search, ChevronLeft, ChevronRight } from "lucide-react";
import { motion } from "framer-motion";
import { Card, CardContent } from "@/components/ui/card";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { eventGroupsApi } from "@/lib/api/eventGroups";
import { useCurrency } from "@/hooks/useCurrency";
import { usePolling } from "@/hooks/usePolling";

const PAGE_SIZE = 15;

interface Row {
  member_id: string;
  display_name: string;
  avatar_url?: string | null;
  role?: string;
  pledged: number;
  paid: number;
  balance: number;
  rank?: number;
}

interface Summary {
  total_pledged: number;
  total_paid: number;
  outstanding: number;
  collection_rate: number;
  contributors: number;
  budget?: number | null;
  currency?: string;
}

const initials = (n: string) => (n || "?").trim().split(/\s+/).slice(0, 2).map(s => s[0]).join("").toUpperCase();

const RANK_ICON: Record<number, JSX.Element> = {
  1: <Crown className="w-4 h-4 text-amber-500" />,
  2: <Medal className="w-4 h-4 text-slate-400" />,
  3: <Medal className="w-4 h-4 text-orange-500" />,
};

// Per-group cache so toggling between Chat ↔ Contributors tabs does not
// re-show the skeleton when the panel re-mounts.
const scoreboardCache: Record<string, { rows: Row[]; summary: Summary | null }> = {};

const ScoreboardPanel = ({ groupId }: { groupId: string }) => {
  const { format } = useCurrency();
  const cached = scoreboardCache[groupId];
  const [rows, setRows] = useState<Row[]>(cached?.rows || []);
  const [summary, setSummary] = useState<Summary | null>(cached?.summary || null);
  const [loading, setLoading] = useState(!cached);
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);

  const fetchData = async () => {
    const res = await eventGroupsApi.scoreboard(groupId);
    if (res.success && res.data) {
      const raw: Row[] = res.data.rows || [];
      // Sort: highest completion % first, then strictly alphabetical within
      // the same percentage bucket (e.g. all 80% contributors A→Z).
      const pct = (r: Row) => {
        const p = r.pledged > 0 ? r.paid / r.pledged : (r.paid > 0 ? 1 : 0);
        return Math.round(p * 10000); // bucket to 2 decimals to avoid float drift
      };
      const sorted = [...raw].sort((a, b) => {
        const diff = pct(b) - pct(a);
        if (diff !== 0) return diff;
        return (a.display_name || "").localeCompare(b.display_name || "", undefined, { sensitivity: "base" });
      });
      const list: Row[] = sorted.map((r, i) => ({ ...r, rank: i + 1 }));
      setRows(list);
      setSummary(res.data.summary || null);
      scoreboardCache[groupId] = { rows: list, summary: res.data.summary || null };
    }
    setLoading(false);
  };

  useEffect(() => { fetchData(); /* eslint-disable-next-line */ }, [groupId]);
  usePolling(fetchData, 8000, !loading);

  const top3 = rows.slice(0, 3);

  // Filter + paginate the leaderboard.
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((r) => (r.display_name || "").toLowerCase().includes(q));
  }, [rows, search]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);
  const pageRows = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);

  // Reset to page 1 whenever the search changes.
  useEffect(() => { setPage(1); }, [search]);

  return (
    <div className="space-y-5">
      {/* Summary cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Card className="bg-gradient-to-br from-primary/10 to-primary/5 border-primary/20">
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <p className="text-xs text-muted-foreground">Total Pledged</p>
              <TrendingUp className="w-4 h-4 text-primary" />
            </div>
            {loading ? <Skeleton className="h-6 w-24 mt-2" /> :
              <p className="text-lg font-bold text-primary mt-1">{format(summary?.total_pledged || 0)}</p>
            }
          </CardContent>
        </Card>
        <Card className="bg-gradient-to-br from-emerald-500/10 to-emerald-500/5 border-emerald-500/20">
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <p className="text-xs text-muted-foreground">Cash in Hand</p>
              <Wallet className="w-4 h-4 text-emerald-600" />
            </div>
            {loading ? <Skeleton className="h-6 w-24 mt-2" /> :
              <p className="text-lg font-bold text-emerald-600 mt-1">{format(summary?.total_paid || 0)}</p>
            }
          </CardContent>
        </Card>
        <Card className="bg-gradient-to-br from-amber-500/10 to-amber-500/5 border-amber-500/20">
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <p className="text-xs text-muted-foreground">Outstanding</p>
              <Wallet className="w-4 h-4 text-amber-600" />
            </div>
            {loading ? <Skeleton className="h-6 w-24 mt-2" /> :
              <p className="text-lg font-bold text-amber-600 mt-1">{format(summary?.outstanding || 0)}</p>
            }
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <p className="text-xs text-muted-foreground">Contributors</p>
              <Users className="w-4 h-4 text-muted-foreground" />
            </div>
            {loading ? <Skeleton className="h-6 w-12 mt-2" /> :
              <p className="text-lg font-bold mt-1">{summary?.contributors || 0}</p>
            }
          </CardContent>
        </Card>
      </div>

      {/* Collection progress */}
      {summary && (summary.total_pledged > 0 || summary.budget) && (
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between mb-2">
              <p className="text-sm font-semibold">Collection Progress</p>
              <span className="text-sm font-bold text-primary">{Math.round(summary.collection_rate || 0)}%</span>
            </div>
            <Progress value={summary.collection_rate || 0} className="h-2" />
            <p className="text-[11px] text-muted-foreground mt-2">
              {format(summary.total_paid)} collected of {format(summary.total_pledged)} pledged
              {summary.budget ? ` - Budget ${format(summary.budget)}` : ""}
            </p>
          </CardContent>
        </Card>
      )}

      {/* Podium top 3 */}
      {top3.length > 0 && (
        <div className="grid grid-cols-3 gap-2 sm:gap-3">
          {[1, 0, 2].map((idx) => {
            const r = top3[idx];
            if (!r) return <div key={idx} />;
            const heights = ["h-32", "h-40", "h-28"];
            const h = idx === 0 ? heights[1] : idx === 1 ? heights[0] : heights[2];
            return (
              <motion.div
                key={r.member_id}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: idx * 0.1 }}
                className="flex flex-col items-center justify-end"
              >
                <Avatar className={`w-14 h-14 sm:w-16 sm:h-16 ring-4 ${
                  idx === 0 ? "ring-amber-400" : idx === 1 ? "ring-slate-300" : "ring-orange-400"
                } shadow-lg mb-2`}>
                  {r.avatar_url && <AvatarImage src={r.avatar_url} />}
                  <AvatarFallback className="bg-primary/10 text-primary font-bold">{initials(r.display_name)}</AvatarFallback>
                </Avatar>
                <div className={`w-full ${h} bg-gradient-to-t ${
                  idx === 0 ? "from-amber-400/30 to-amber-400/5 border-amber-400/40"
                  : idx === 1 ? "from-slate-300/30 to-slate-300/5 border-slate-300/40"
                  : "from-orange-400/30 to-orange-400/5 border-orange-400/40"
                } border rounded-t-xl p-2 sm:p-3 text-center flex flex-col justify-end`}>
                  <div className="flex items-center justify-center gap-1 mb-1">
                    {RANK_ICON[r.rank!]}
                    <span className="text-xs font-bold">#{r.rank}</span>
                  </div>
                  <p className="text-xs font-semibold truncate">{r.display_name}</p>
                  <p className="text-[10px] sm:text-xs text-primary font-bold mt-0.5">{format(r.paid)}</p>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}

      {/* Full leaderboard */}
      <Card>
        <CardContent className="p-0">
          <div className="px-4 py-3 border-b border-border flex items-center gap-2 flex-wrap">
            <Trophy className="w-4 h-4 text-primary" />
            <p className="font-semibold text-sm">Top Contributors</p>
            <Badge variant="outline" className="ml-auto text-[10px]">
              {filtered.length}{search ? ` of ${rows.length}` : ""} {rows.length === 1 ? "contributor" : "contributors"}
            </Badge>
          </div>
          {/* Search */}
          {!loading && rows.length > 0 && (
            <div className="px-4 py-2.5 border-b border-border bg-muted/30">
              <div className="relative">
                <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                <Input
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Search contributors by name…"
                  className="h-9 pl-8 text-sm"
                />
              </div>
            </div>
          )}
          {loading ? (
            <div className="divide-y divide-border">
              {[...Array(5)].map((_, i) => (
                <div key={i} className="p-3 flex items-center gap-3">
                  <Skeleton className="w-9 h-9 rounded-full" />
                  <Skeleton className="h-4 flex-1" />
                  <Skeleton className="h-4 w-20" />
                </div>
              ))}
            </div>
          ) : rows.length === 0 ? (
            <div className="p-10 text-center text-muted-foreground">
              <Trophy className="w-10 h-10 mx-auto mb-2 opacity-30" />
              <p className="text-sm">No contributors yet</p>
            </div>
          ) : pageRows.length === 0 ? (
            <div className="p-10 text-center text-muted-foreground">
              <Search className="w-10 h-10 mx-auto mb-2 opacity-30" />
              <p className="text-sm">No contributors match “{search}”</p>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {pageRows.map((r, index) => {
                const pct = r.pledged > 0 ? Math.min(100, Math.round((r.paid / r.pledged) * 100)) : 0;
                return (
                  <motion.div
                    key={r.member_id || `${r.display_name}-${index}`}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    className="p-3 flex items-center gap-3 hover:bg-muted/40 transition-colors"
                  >
                    <span className="w-7 text-center text-xs font-bold text-muted-foreground">#{r.rank}</span>
                    <Avatar className="w-9 h-9">
                      {r.avatar_url && <AvatarImage src={r.avatar_url} />}
                      <AvatarFallback className="bg-primary/10 text-primary text-xs">{initials(r.display_name)}</AvatarFallback>
                    </Avatar>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2">
                        <p className="text-sm font-semibold truncate">{r.display_name}</p>
                        <p className="text-sm font-bold text-primary">{format(r.paid)}</p>
                      </div>
                      <div className="flex items-center gap-2 mt-1">
                        <div className="flex-1 h-1.5 rounded-full bg-muted overflow-hidden">
                          <div className="h-full bg-primary transition-all" style={{ width: `${pct}%` }} />
                        </div>
                        <span className="text-[10px] text-muted-foreground font-medium w-10 text-right">{pct}%</span>
                      </div>
                      <p className="text-[10px] text-muted-foreground mt-0.5">
                        Pledged {format(r.pledged)} - Balance {format(r.balance)}
                      </p>
                    </div>
                  </motion.div>
                );
              })}
            </div>
          )}
          {/* Pagination */}
          {!loading && totalPages > 1 && (
            <div className="px-4 py-2.5 border-t border-border flex items-center justify-between bg-muted/20">
              <p className="text-[11px] text-muted-foreground">
                Page {safePage} of {totalPages} - showing {pageRows.length} of {filtered.length}
              </p>
              <div className="flex items-center gap-1">
                <Button
                  variant="outline" size="icon" className="h-7 w-7"
                  disabled={safePage <= 1}
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  aria-label="Previous page"
                >
                  <ChevronLeft className="w-3.5 h-3.5" />
                </Button>
                <Button
                  variant="outline" size="icon" className="h-7 w-7"
                  disabled={safePage >= totalPages}
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  aria-label="Next page"
                >
                  <ChevronRight className="w-3.5 h-3.5" />
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
};

export default ScoreboardPanel;
