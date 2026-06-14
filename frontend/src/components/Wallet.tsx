import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  Wallet as WalletIcon,
  ArrowDownLeft,
  ArrowUpRight,
  Plus,
  Hourglass,
  ShieldCheck,
  History,
  HandCoins,
  Send,
  Loader2,
} from "lucide-react";
import { motion } from "framer-motion";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { api } from "@/lib/api";
import { useCurrency } from "@/hooks/useCurrency";
import { useWorkspaceMeta } from "@/hooks/useWorkspaceMeta";
import { CheckoutModal } from "@/components/payments/CheckoutModal";
import { formatLocalDateTime } from "@/utils/formatLocalDateTime";
import { humanize } from "@/lib/humanize";
import type { Wallet, WalletLedgerEntry, Transaction, PaymentProfile } from "@/lib/api/payments-types";
import type { BookingRequest } from "@/lib/api/types";
import MigrationBanner from "@/components/migration/MigrationBanner";

const WalletPage = () => {
  const navigate = useNavigate();
  const { format, currency } = useCurrency();
  const [topUpOpen, setTopUpOpen] = useState(false);
  const [withdrawOpen, setWithdrawOpen] = useState(false);
  const [payOpen, setPayOpen] = useState(false);
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [submittingWithdrawal, setSubmittingWithdrawal] = useState(false);
  const [selectedPayable, setSelectedPayable] = useState<BookingRequest | null>(null);

  useWorkspaceMeta({
    title: "Wallet",
    description: "Manage your Nuru wallet balance, top-ups, vendor payments, and withdrawals.",
  });

  const walletsQuery = useQuery({
    queryKey: ["wallets"],
    queryFn: async () => {
      const res = await api.wallet.list();
      return res.success ? res.data?.wallets ?? [] : [];
    },
  });

  const wallet: Wallet | undefined = useMemo(() => {
    const wallets = walletsQuery.data ?? [];
    return wallets.find((w) => w.currency_code === currency) ?? wallets[0];
  }, [walletsQuery.data, currency]);

  const ledgerQuery = useQuery({
    queryKey: ["wallet-ledger", wallet?.id],
    enabled: !!wallet?.id,
    queryFn: async () => {
      const res = await api.wallet.getLedger(wallet!.id, { limit: 8 });
      return res.success ? res.data?.entries ?? [] : [];
    },
  });

  const [txFilter, setTxFilter] = useState<"all" | "wallet_topup" | "ticket" | "contribution" | "booking" | "withdrawal">("all");

  const txQuery = useQuery({
    queryKey: ["wallet-transactions", txFilter],
    queryFn: async () => {
      const res = await api.payments.history({
        limit: 50,
        ...(txFilter !== "all" ? { target_type: txFilter } : {}),
      });
      return res.success ? res.data?.transactions ?? [] : [];
    },
  });

  const profilesQuery = useQuery({
    queryKey: ["payment-profiles"],
    queryFn: async () => {
      const res = await api.paymentProfiles.list();
      return res.success ? (Array.isArray(res.data) ? res.data : []) : [];
    },
  });

  const myBookingsQuery = useQuery({
    queryKey: ["wallet-payable-bookings"],
    queryFn: async () => {
      const res = await api.bookings.getMyBookings({ status: "accepted", limit: 50 });
      return res.success ? res.data?.bookings ?? [] : [];
    },
  });

  const defaultProfile = useMemo<PaymentProfile | null>(() => {
    const profiles = profilesQuery.data ?? [];
    return profiles.find((p) => p.is_default && p.is_completed) ?? profiles.find((p) => p.is_completed) ?? null;
  }, [profilesQuery.data]);

  const payableBookings = useMemo(() => {
    const bookings = myBookingsQuery.data ?? [];
    return bookings.filter((b) => {
      if (b.status !== "accepted") return false;
      const total = Number(b.quoted_price ?? b.final_price ?? 0);
      const deposit = Number(b.deposit_required ?? 0);
      if (!b.deposit_paid && deposit > 0) return true;
      if (!b.deposit_paid && total > 0) return true;
      return false;
    });
  }, [myBookingsQuery.data]);

  const refreshAll = () => {
    walletsQuery.refetch();
    ledgerQuery.refetch();
    txQuery.refetch();
    myBookingsQuery.refetch();
  };

  const handleTopUpSuccess = () => {
    refreshAll();
  };

  const handleWithdrawalSubmit = async () => {
    if (!wallet) return;
    const amount = Number(withdrawAmount);
    if (!amount || amount <= 0) {
      toast.error("Enter a valid withdrawal amount");
      return;
    }
    if (amount > Number(wallet.available_balance || 0)) {
      toast.error("Amount exceeds available balance");
      return;
    }
    if (!defaultProfile) {
      toast.error("Add a payout method first");
      navigate("/settings/payments");
      return;
    }

    setSubmittingWithdrawal(true);
    try {
      const res = await api.withdrawals.create({
        currency_code: wallet.currency_code,
        amount,
        payment_profile_id: defaultProfile.id,
      });
      if (!res.success) {
        toast.error(res.message || "Failed to submit withdrawal");
        return;
      }
      toast.success("Withdrawal request submitted");
      setWithdrawAmount("");
      setWithdrawOpen(false);
      refreshAll();
    } finally {
      setSubmittingWithdrawal(false);
    }
  };

  const selectedPayAmount = useMemo(() => {
    if (!selectedPayable) return 0;
    const deposit = Number(selectedPayable.deposit_required ?? 0);
    const total = Number(selectedPayable.quoted_price ?? selectedPayable.final_price ?? 0);
    return !selectedPayable.deposit_paid && deposit > 0 ? deposit : total;
  }, [selectedPayable]);

  return (
    <div className="space-y-6 pb-12">
      <MigrationBanner surface="wallet" />
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl md:text-2xl font-semibold">Wallet</h1>
          <p className="text-sm text-muted-foreground">Your money, ready when you need it.</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => navigate("/settings/payments")}>
          Payout settings
        </Button>
      </div>

      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.3 }}
      >
        <Card className="overflow-hidden border-0 shadow-elegant bg-gradient-to-br from-primary via-primary to-primary/80 text-primary-foreground">
          <CardContent className="p-6 md:p-8">
            <div className="flex items-start justify-between">
              <div className="flex items-center gap-2 text-primary-foreground/80">
                <WalletIcon className="h-4 w-4" />
                <span className="text-xs uppercase tracking-wider">Available balance</span>
              </div>
              <Badge variant="secondary" className="bg-white/15 text-primary-foreground hover:bg-white/20 border-0">
                {currency}
              </Badge>
            </div>

            <div className="mt-3">
              {walletsQuery.isLoading ? (
                <Skeleton className="h-10 w-48 bg-white/20" />
              ) : (
                <p className="text-3xl md:text-4xl font-bold tracking-tight">
                  {format(wallet?.available_balance ?? 0)}
                </p>
              )}
            </div>

            <div className="mt-5 grid grid-cols-2 gap-3">
              <MiniStat icon={<Hourglass className="h-3.5 w-3.5" />} label="Pending" value={format(wallet?.pending_balance ?? 0)} />
              <MiniStat icon={<ShieldCheck className="h-3.5 w-3.5" />} label="Reserved" value={format(wallet?.reserved_balance ?? 0)} />
            </div>

            <div className="mt-6 grid grid-cols-1 sm:grid-cols-3 gap-2">
              <Button onClick={() => setTopUpOpen(true)} size="lg" variant="secondary" className="bg-white text-primary hover:bg-white/90">
                <Plus className="h-4 w-4 mr-1.5" /> Top up
              </Button>
              <Button onClick={() => setPayOpen(true)} size="lg" variant="ghost" className="text-primary-foreground hover:bg-white/10">
                <Send className="h-4 w-4 mr-1.5" /> Pay
              </Button>
              <Button onClick={() => setWithdrawOpen(true)} size="lg" variant="ghost" className="text-primary-foreground hover:bg-white/10">
                <ArrowUpRight className="h-4 w-4 mr-1.5" /> Withdraw
              </Button>
            </div>
          </CardContent>
        </Card>
      </motion.div>

      <Tabs defaultValue="ledger">
        <TabsList>
          <TabsTrigger value="ledger" className="gap-2">
            <History className="h-3.5 w-3.5" /> Ledger
          </TabsTrigger>
          <TabsTrigger value="transactions" className="gap-2">
            <ArrowDownLeft className="h-3.5 w-3.5" /> Transactions
          </TabsTrigger>
        </TabsList>

        <TabsContent value="ledger" className="mt-4">
          <Card>
            <CardContent className="p-0">
              {ledgerQuery.isLoading ? (
                <SkeletonRows />
              ) : ledgerQuery.data && ledgerQuery.data.length > 0 ? (
                <ul className="divide-y divide-border">
                  {ledgerQuery.data.map((e) => (
                    <LedgerRow key={e.id} entry={e} format={format} />
                  ))}
                </ul>
              ) : (
                <EmptyState text="No wallet activity yet." />
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="transactions" className="mt-4 space-y-3">
          <div className="flex flex-wrap gap-1.5">
            {([
              { v: "all", l: "All" },
              { v: "wallet_topup", l: "Top-ups" },
              { v: "ticket", l: "Tickets" },
              { v: "contribution", l: "Contributions" },
              { v: "booking", l: "Vendor payments" },
              { v: "withdrawal", l: "Withdrawals" },
            ] as const).map((f) => (
              <button
                key={f.v}
                type="button"
                onClick={() => setTxFilter(f.v)}
                className={`text-xs px-2.5 py-1 rounded-full border transition-colors ${
                  txFilter === f.v
                    ? "border-primary bg-primary text-primary-foreground"
                    : "border-border bg-background text-muted-foreground hover:bg-muted"
                }`}
              >
                {f.l}
              </button>
            ))}
          </div>
          <Card>
            <CardContent className="p-0">
              {txQuery.isLoading ? (
                <SkeletonRows />
              ) : txQuery.data && txQuery.data.length > 0 ? (
                <ul className="divide-y divide-border">
                  {txQuery.data.map((tx) => (
                    <TransactionRow key={tx.id} tx={tx} format={format} onRefreshed={handleTopUpSuccess} />
                  ))}
                </ul>
              ) : (
                <EmptyState text={txFilter === "all" ? "No transactions yet." : "No transactions match this filter."} />
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      <CheckoutModal
        open={topUpOpen}
        onOpenChange={setTopUpOpen}
        targetType="wallet_topup"
        amountEditable
        allowWallet={false}
        allowBank={false}
        title="Top up wallet"
        description={`Add money to your ${currency} wallet via mobile money`}
        submitLabel="Top up"
        onSuccess={handleTopUpSuccess}
      />

      <Dialog open={withdrawOpen} onOpenChange={setWithdrawOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Withdraw from wallet</DialogTitle>
            <DialogDescription>
              {defaultProfile
                ? `Funds will be sent to ${defaultProfile.account_holder_name}${defaultProfile.method_type === "mobile_money" ? ` - ${defaultProfile.network_name ?? "Mobile Money"}` : ` - ${defaultProfile.bank_name ?? "Bank"}`}`
                : "Add a payout method before withdrawing."}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="rounded-lg border border-border bg-muted/30 p-3 text-sm">
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">Available</span>
                <span className="font-semibold text-foreground">{format(wallet?.available_balance ?? 0)}</span>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="withdraw-amount">Amount</Label>
              <Input
                id="withdraw-amount"
                inputMode="decimal"
                placeholder={`Enter amount in ${currency}`}
                value={withdrawAmount}
                onChange={(e) => setWithdrawAmount(e.target.value)}
              />
            </div>
            {!defaultProfile && (
              <Button variant="outline" className="w-full" onClick={() => navigate("/settings/payments")}>
                Setup payout method
              </Button>
            )}
            <Button className="w-full" onClick={handleWithdrawalSubmit} disabled={submittingWithdrawal || !defaultProfile}>
              {submittingWithdrawal ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <ArrowUpRight className="h-4 w-4 mr-2" />}
              Request withdrawal
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={payOpen} onOpenChange={setPayOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Pay vendors</DialogTitle>
            <DialogDescription>Choose a vendor booking that is ready for payment.</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 max-h-[65vh] overflow-y-auto pr-1">
            {myBookingsQuery.isLoading ? (
              <SkeletonRows />
            ) : payableBookings.length > 0 ? (
              payableBookings.map((booking) => {
                const payAmount = !booking.deposit_paid && Number(booking.deposit_required ?? 0) > 0
                  ? Number(booking.deposit_required ?? 0)
                  : Number(booking.quoted_price ?? booking.final_price ?? 0);
                const initials = (booking.provider?.name || "?").split(/\s+/).slice(0, 2).map((s) => s[0]).join("").toUpperCase();
                return (
                  <button
                    key={booking.id}
                    type="button"
                    onClick={() => {
                      setSelectedPayable(booking);
                      setPayOpen(false);
                    }}
                    className="w-full text-left rounded-xl border border-border p-3 hover:bg-muted/40 transition-colors"
                  >
                    <div className="flex items-start gap-3">
                      <Avatar className="h-11 w-11 shrink-0">
                        {booking.provider?.avatar && <AvatarImage src={booking.provider.avatar} alt={booking.provider.name} />}
                        <AvatarFallback className="bg-primary/10 text-primary font-semibold">{initials || "V"}</AvatarFallback>
                      </Avatar>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-start justify-between gap-3">
                          <div className="min-w-0">
                            <p className="text-sm font-semibold text-foreground truncate">{booking.provider?.name || "Vendor"}</p>
                            <p className="text-xs text-muted-foreground truncate">{booking.service?.title || "Service"}</p>
                          </div>
                          <Badge variant="secondary" className="shrink-0">
                            {!booking.deposit_paid && Number(booking.deposit_required ?? 0) > 0 ? "Deposit" : "Payment"}
                          </Badge>
                        </div>
                        <div className="mt-2 flex items-center justify-between gap-2 text-xs text-muted-foreground">
                          <span className="truncate">{booking.event_name || booking.event?.title || "Event booking"}</span>
                          <span className="font-semibold text-foreground">{format(payAmount)}</span>
                        </div>
                      </div>
                    </div>
                  </button>
                );
              })
            ) : (
              <EmptyState text="No vendor payments are waiting right now." />
            )}
          </div>
        </DialogContent>
      </Dialog>

      <CheckoutModal
        open={!!selectedPayable}
        onOpenChange={(open) => { if (!open) setSelectedPayable(null); }}
        targetType="service_booking"
        targetId={selectedPayable?.id}
        beneficiaryUserId={selectedPayable?.provider?.id}
        amount={selectedPayAmount}
        allowBank={false}
        title={`Pay ${selectedPayable?.provider?.name || "vendor"}`}
        description={selectedPayable?.service?.title || "Service booking payment"}
        submitLabel="Pay now"
        onSuccess={() => {
          setSelectedPayable(null);
          refreshAll();
        }}
      />
    </div>
  );
};

const MiniStat = ({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) => (
  <div className="rounded-lg bg-white/10 backdrop-blur-sm px-3 py-2.5">
    <div className="flex items-center gap-1.5 text-[10px] uppercase tracking-wider text-primary-foreground/70">
      {icon}
      {label}
    </div>
    <p className="mt-0.5 text-sm font-semibold">{value}</p>
  </div>
);

const LedgerRow = ({
  entry,
  format,
}: {
  entry: WalletLedgerEntry;
  format: (n: number | string | null | undefined) => string;
}) => {
  const isCredit = ["credit", "release", "settlement"].includes(entry.entry_type);
  return (
    <li className="flex items-center justify-between p-4 hover:bg-muted/30 transition-colors">
      <div className="flex items-center gap-3 min-w-0">
        <div className={`h-9 w-9 rounded-full flex items-center justify-center ${isCredit ? "bg-green-500/15 text-green-600" : "bg-orange-500/15 text-orange-600"}`}>
          {isCredit ? <ArrowDownLeft className="h-4 w-4" /> : <ArrowUpRight className="h-4 w-4" />}
        </div>
        <div className="min-w-0">
          <p className="text-sm font-medium text-foreground truncate">
            {humanize(entry.description) || humanize(entry.entry_type.replace(/_/g, " "))}
          </p>
          <p className="text-[11px] text-muted-foreground">
            {formatLocalDateTime(entry.created_at)} - {entry.reference_code ?? "—"}
          </p>
        </div>
      </div>
      <div className="text-right shrink-0">
        <p className={`text-sm font-semibold ${isCredit ? "text-green-600" : "text-foreground"}`}>
          {isCredit ? "+" : "−"} {format(entry.amount)}
        </p>
        <p className="text-[10px] text-muted-foreground">Bal {format(entry.balance_after)}</p>
      </div>
    </li>
  );
};

const TransactionRow = ({
  tx,
  format,
  onRefreshed,
}: {
  tx: Transaction;
  format: (n: number | string | null | undefined) => string;
  onRefreshed?: () => void;
}) => {
  const [refreshing, setRefreshing] = useState(false);
  const statusTone: Record<string, string> = {
    succeeded: "bg-green-500/15 text-green-700",
    paid: "bg-green-500/15 text-green-700",
    credited: "bg-green-500/15 text-green-700",
    pending: "bg-amber-500/15 text-amber-700",
    processing: "bg-blue-500/15 text-blue-700",
    failed: "bg-destructive/15 text-destructive",
    cancelled: "bg-muted text-muted-foreground",
    refunded: "bg-purple-500/15 text-purple-700",
  };

  const isTerminal = ["credited", "succeeded", "paid", "failed", "cancelled", "refunded"].includes(tx.status);
  const navigate = useNavigate();

  const handleRefresh = async (e: React.MouseEvent) => {
    e.stopPropagation();
    setRefreshing(true);
    try {
      const res = await api.payments.getStatus(tx.id);
      if (res.success) onRefreshed?.();
    } finally {
      setRefreshing(false);
    }
  };

  const openReceipt = () => navigate(`/wallet/receipt/${tx.transaction_code}`);

  return (
    <li className="flex items-center justify-between p-4 hover:bg-muted/30 transition-colors gap-3 cursor-pointer" onClick={openReceipt}>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium text-foreground truncate">
          {humanize(tx.payment_description) || humanize(tx.target_type?.replace(/_/g, " ")) || "Payment"}
        </p>
        <p className="text-[11px] text-muted-foreground truncate">
          {tx.transaction_code} - {formatLocalDateTime(tx.initiated_at || tx.created_at)}
        </p>
      </div>
      <div className="text-right shrink-0 space-y-1">
        <p className="text-sm font-semibold text-foreground">{format(tx.gross_amount)}</p>
        <Badge variant="secondary" className={`${statusTone[tx.status] ?? "bg-muted text-muted-foreground"} border-0 text-[10px] px-1.5 py-0`}>
          {tx.status}
        </Badge>
      </div>
      {!isTerminal && (
        <Button size="icon" variant="ghost" onClick={handleRefresh} disabled={refreshing} aria-label="Refresh status" className="h-8 w-8 shrink-0">
          <History className={`h-4 w-4 ${refreshing ? "animate-spin" : ""}`} />
        </Button>
      )}
    </li>
  );
};

const SkeletonRows = () => (
  <div className="p-4 space-y-3">
    {[0, 1, 2, 3].map((i) => (
      <div key={i} className="flex items-center gap-3">
        <Skeleton className="h-9 w-9 rounded-full" />
        <div className="flex-1 space-y-1.5">
          <Skeleton className="h-3 w-40" />
          <Skeleton className="h-2.5 w-24" />
        </div>
        <Skeleton className="h-3 w-16" />
      </div>
    ))}
  </div>
);

const EmptyState = ({ text }: { text: string }) => (
  <div className="p-10 text-center text-sm text-muted-foreground">{text}</div>
);

export default WalletPage;
