/**
 * My Contribution Payments — full payment history for contributions the
 * current user has paid towards events. Mirrors MyTicketPaymentsTab.
 */
import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { ChevronLeft, ChevronRight, HandCoins, Search, ArrowDownRight, Printer } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { receivedPaymentsApi, type ReceivedPayment } from "@/lib/api/receivedPayments";
import { useCurrency } from "@/hooks/useCurrency";
import { openPaymentReceipt } from "@/utils/printPaymentReceipt";
import { useNavigate } from "react-router-dom";

const STATUS_STYLES: Record<string, string> = {
  completed: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300",
  confirmed: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300",
  pending: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300",
  failed: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300",
  refunded: "bg-muted text-muted-foreground",
};

const RowSkeleton = () => (
  <Card>
    <CardContent className="p-4 flex items-center gap-3">
      <Skeleton className="w-10 h-10 rounded-full" />
      <div className="flex-1 space-y-2">
        <Skeleton className="h-4 w-2/3" />
        <Skeleton className="h-3 w-1/3" />
      </div>
      <Skeleton className="h-5 w-20" />
    </CardContent>
  </Card>
);

const MyContributionPaymentsTab = () => {
  const { format } = useCurrency();
  const navigate = useNavigate();
  const [payments, setPayments] = useState<ReceivedPayment[]>([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [pagination, setPagination] = useState<any>(null);
  const [search, setSearch] = useState("");

  useEffect(() => {
    setLoading(true);
    receivedPaymentsApi
      .myContributions({ page, limit: 15, ...(search ? { search } : {}) })
      .then((res) => {
        if (res.success && res.data) {
          setPayments(res.data.payments || []);
          setPagination(res.data.pagination || null);
        }
      })
      .finally(() => setLoading(false));
  }, [page, search]);

  return (
    <div className="space-y-4">
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          value={search}
          onChange={(e) => { setPage(1); setSearch(e.target.value); }}
          placeholder="Search by code, event, beneficiary…"
          className="pl-9 h-9"
        />
      </div>

      {loading ? (
        <div className="space-y-2">{[...Array(4)].map((_, i) => <RowSkeleton key={i} />)}</div>
      ) : payments.length === 0 ? (
        <div className="text-center py-12 border-2 border-dashed border-border rounded-2xl">
          <HandCoins className="w-10 h-10 mx-auto mb-3 text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground font-medium">No contributions paid yet</p>
          <p className="text-xs text-muted-foreground mt-1">Receipts for contributions you pay will appear here.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {payments.map((p, i) => (
            <motion.div key={p.id} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.03 }}>
              <Card className="hover:border-primary/30 transition-colors group">
                <CardContent className="p-4 flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-primary/10 text-primary flex items-center justify-center shrink-0">
                    <ArrowDownRight className="w-5 h-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <p className="text-sm font-semibold truncate">{p.description || "Contribution payment"}</p>
                      <Badge className={`text-[10px] capitalize border-0 ${STATUS_STYLES[p.status || "pending"] || STATUS_STYLES.pending}`}>
                        {p.status || "pending"}
                      </Badge>
                      {p.is_offline && (
                        <Badge variant="outline" className="text-[10px]">Offline</Badge>
                      )}
                    </div>
                    <p className="text-[11px] text-muted-foreground mt-0.5 truncate font-mono">
                      {p.transaction_code}
                      {p.method_type && ` - ${p.method_type}`}
                      {p.provider_name && ` - ${p.provider_name}`}
                    </p>
                    <p className="text-[11px] text-muted-foreground mt-0.5">
                      {p.completed_at || p.confirmed_at || p.initiated_at
                        ? new Date((p.completed_at || p.confirmed_at || p.initiated_at) as string).toLocaleString()
                        : ""}
                    </p>
                  </div>
                  <div className="text-right shrink-0">
                    <p className="text-sm font-bold text-foreground">{format(p.gross_amount)}</p>
                    {p.commission_amount > 0 && (
                      <p className="text-[10px] text-muted-foreground">fee {format(p.commission_amount)}</p>
                    )}
                  </div>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="shrink-0 opacity-60 hover:opacity-100"
                    title="Open receipt"
                    onClick={() => openPaymentReceipt(navigate, p)}
                  >
                    <Printer className="w-4 h-4" />
                  </Button>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>
      )}

      {pagination && pagination.total_pages > 1 && (
        <div className="flex items-center justify-center gap-3 pt-2">
          <Button variant="outline" size="sm" disabled={!pagination.has_previous} onClick={() => setPage(p => p - 1)}>
            <ChevronLeft className="w-4 h-4" />
          </Button>
          <span className="text-sm text-muted-foreground">Page {pagination.page} of {pagination.total_pages}</span>
          <Button variant="outline" size="sm" disabled={!pagination.has_next} onClick={() => setPage(p => p + 1)}>
            <ChevronRight className="w-4 h-4" />
          </Button>
        </div>
      )}
    </div>
  );
};

export default MyContributionPaymentsTab;
