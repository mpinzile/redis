import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FormattedNumberInput } from "@/components/ui/formatted-number-input";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Loader2, Smartphone, Building2, Wallet as WalletIcon, ShieldCheck, ArrowLeft, CheckCircle2 } from "lucide-react";
import { toast } from "sonner";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { showApiErrors } from "@/lib/api/showApiErrors";
import { useCurrency } from "@/hooks/useCurrency";
import { cn } from "@/lib/utils";
import OfflinePaymentClaimModal from "@/components/payments/OfflinePaymentClaimModal";
import type {
  PaymentTargetType,
  PaymentProvider,
  Transaction,
} from "@/lib/api/payments-types";

interface CheckoutModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** What is being paid for. Determines fee snapshot on the backend. */
  targetType: PaymentTargetType;
  /** ID of the resource being paid for (event id, ticket id, etc.). */
  targetId?: string;
  /**
   * Optional: the user who should receive the funds. Backend will also
   * auto-resolve this for booking/contribution targets, but passing it here
   * makes intent explicit and lets the backend cross-check.
   */
  beneficiaryUserId?: string;
  /** Amount in major units (e.g. 12500 = 12,500 TZS). Optional → user enters it (top-ups). */
  amount?: number;
  /** Allow editing the amount (true for wallet top-ups, false for tickets). */
  amountEditable?: boolean;
  /** Allow paying from the in-app wallet. Defaults to true. */
  allowWallet?: boolean;
  /**
   * Allow paying via Bank Transfer. Defaults to true.
   * Wallet top-ups pass `false` — bank deposits are coming soon, mobile money only for now.
   */
  allowBank?: boolean;
  /** Friendly label shown in the header e.g. "Top up wallet" or "Buy 2 tickets". */
  title: string;
  description?: string;
  /** Custom submit button label (defaults to "Pay {amount}"). */
  submitLabel?: string;
  /** Called once the transaction reaches a terminal state. */
  onSuccess?: (tx: Transaction) => void;
  /**
   * Optional override for the "Already paid?" claim flow. For tickets,
   * `targetId` may already point at a reservation; the offline-claim API
   * needs the ticket *class* id instead.
   */
  offlineClaimTargetId?: string;
  /** For ticket offline claims — number of tickets the buyer paid for. */
  offlineClaimQuantity?: number;
}

type Method = "wallet" | "mobile_money" | "bank";

/**
 * Premium checkout modal — Phase 4.
 *
 * Renders a country-aware payment sheet:
 *  • Wallet (instant, free) — only if `allowWallet`.
 *  • Mobile money (STK push) — phone number prompt.
 *  • Bank transfer — account number.
 *
 * On submit it calls `/payments/initiate` and polls `/payments/{code}/status`
 * every 2.5s until the gateway returns a terminal state.
 */
export const CheckoutModal = ({
  open,
  onOpenChange,
  targetType,
  targetId,
  beneficiaryUserId,
  amount: initialAmount,
  amountEditable = false,
  allowWallet = true,
  allowBank = true,
  title,
  description,
  submitLabel,
  onSuccess,
  offlineClaimTargetId,
  offlineClaimQuantity,
}: CheckoutModalProps) => {
  const { currency, countryCode, format } = useCurrency();
  const navigate = useNavigate();

  const [method, setMethod] = useState<Method>(allowWallet ? "wallet" : "mobile_money");
  const [providerId, setProviderId] = useState<string>("");
  const [amountStr, setAmountStr] = useState<string>(
    initialAmount ? String(initialAmount) : ""
  );
  const [phone, setPhone] = useState("");
  const [accountNumber, setAccountNumber] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [offlineClaimOpen, setOfflineClaimOpen] = useState(false);

  const amount = Number(amountStr) || initialAmount || 0;

  // Offline-claim is only meaningful for things the buyer was going to pay
  // someone else for — contributions and tickets. It makes no sense for
  // wallet top-ups or vendor service payments (those go through Nuru).
  // For tickets we require an explicit class id so the backend stores the
  // claim against the right ticket class (not the reservation row).
  const offlineId =
    targetType === "event_ticket"
      ? offlineClaimTargetId
      : targetId;
  const supportsOfflineClaim =
    (targetType === "event_contribution" || targetType === "event_ticket") && !!offlineId;

  // Load providers for the active country.
  const providersQuery = useQuery({
    queryKey: ["payment-providers", countryCode, method],
    enabled: open && !!countryCode && method !== "wallet",
    queryFn: async () => {
      const res = await api.payments.providers({
        country_code: countryCode!,
        purpose: "collection",
      });
      return res.success ? (Array.isArray(res.data) ? res.data : []) : [];
    },
  });

  const filteredProviders: PaymentProvider[] = (providersQuery.data ?? []).filter((p) =>
    method === "mobile_money" ? p.provider_type === "mobile_money" : p.provider_type === "bank"
  );

  // Preselect the first provider whenever the rail changes.
  if (
    method !== "wallet" &&
    filteredProviders.length > 0 &&
    !filteredProviders.find((p) => p.id === providerId)
  ) {
    setProviderId(filteredProviders[0].id);
  }

  // Fee preview — commission is added on top (free for wallet top-ups).
  const feeQuery = useQuery({
    queryKey: ["fee-preview", countryCode, currency, targetType, amount],
    enabled: open && !!countryCode && amount > 0,
    queryFn: async () => {
      const res = await api.payments.feePreview({
        country_code: countryCode!,
        currency_code: currency,
        target_type: targetType,
        gross_amount: amount,
      });
      return res.success ? res.data : null;
    },
  });

  const feeAmount = feeQuery.data?.commission_amount ?? 0;
  const totalCharged = feeQuery.data?.total_charged ?? amount;

  const pollUntilTerminal = async (transactionId: string): Promise<Transaction | null> => {
    // Give users up to 4 minutes to enter PIN on their phone — STK pushes
    // routinely take 60–120s during peak load on M-Pesa / Airtel Money.
    const start = Date.now();
    while (Date.now() - start < 240_000) {
      await new Promise((r) => setTimeout(r, 3000));
      // Backend status endpoint is keyed by UUID id, NOT transaction_code.
      const res = await api.payments.getStatus(transactionId);
      if (res.success && res.data) {
        const status = res.data.status;
        if (["succeeded", "failed", "cancelled", "refunded", "paid", "credited"].includes(status)) {
          return res.data;
        }
      }
    }
    return null;
  };

  const handleSubmit = async () => {
    if (amount <= 0) {
      toast.error("Enter a valid amount");
      return;
    }
    if (method === "mobile_money" && !phone) {
      toast.error("Enter your mobile number");
      return;
    }
    if (method === "bank" && !accountNumber) {
      toast.error("Enter your account number");
      return;
    }

    setSubmitting(true);
    try {
      // Build a description that always meets the backend's 8-char minimum.
      const baseDesc = (description || title || "").trim();
      const payment_description =
        baseDesc.length >= 8
          ? baseDesc
          : `${title || "Payment"} for ${targetType.replace(/_/g, " ")}`.trim();

      const res = await api.payments.initiate({
        target_type: targetType,
        target_id: targetId,
        beneficiary_user_id: beneficiaryUserId,
        // Send the *requested* amount; the backend computes commission
        // server-side and adds it on top (so receipts/ledgers stay
        // tamper-proof). The UI shows the user the resulting total.
        gross_amount: amount,
        country_code: countryCode!,
        currency_code: currency,
        method_type: method,
        payment_channel: method === "mobile_money" ? "stk_push" : method,
        payment_description,
        provider_id: method !== "wallet" ? providerId : undefined,
        phone_number: method === "mobile_money" ? phone : undefined,
        account_number: method === "bank" ? accountNumber : undefined,
      });

      if (!res.success || !res.data) {
        showApiErrors(res, "Failed to start payment");
        return;
      }

      const tx = res.data.transaction;
      const receiptAction = (code: string) => ({
        label: "View receipt",
        onClick: () => navigate(`/wallet/receipt/${code}`),
      });

      // Wallet payments settle synchronously.
      if (method === "wallet" || tx.status === "succeeded") {
        toast.success("Payment successful", {
          description: `Reference ${tx.transaction_code}`,
          action: receiptAction(tx.transaction_code),
        });
        onSuccess?.(tx);
        onOpenChange(false);
        return;
      }

      // STK push / bank: payment is now in-flight. Dismiss the modal
      // immediately so the user isn't trapped behind a spinner · we'll
      // notify them via toast once the gateway confirms.
      toast.message(
        res.data.user_message ||
          "Payment is being processed. Check your phone to approve · we'll notify you when it's confirmed.",
        { description: `Reference ${tx.transaction_code}`, duration: 6000 },
      );
      onOpenChange(false);
      setSubmitting(false);

      const final = await pollUntilTerminal(tx.id);
      const commission = Number(final?.commission_snapshot?.computed_fee ?? 0);
      const commissionLine = commission > 0 ? ` - Fee ${format(commission)}` : "";
      if (final?.status === "succeeded" || final?.status === "paid" || final?.status === "credited") {
        toast.success("Payment confirmed", {
          description: `Reference ${final.transaction_code}${commissionLine}`,
          action: receiptAction(final.transaction_code),
        });
        onSuccess?.(final);
        onOpenChange(false);
      } else if (final) {
        toast.error(final.failure_reason || `Payment ${final.status}`, {
          description: `Reference ${final.transaction_code}`,
          action: receiptAction(final.transaction_code),
        });
      } else {
        toast.warning("Still waiting on the gateway. Check Wallet → History in a moment.", {
          action: receiptAction(tx.transaction_code),
        });
        onOpenChange(false);
      }
    } catch {
      toast.error("Something went wrong. Please try again.");
    } finally {
      setSubmitting(false);
    }
  };

  // ── Stepped flow ─────────────────────────────────────────────
  // Steps: amount (skipped if amount is fixed) → method → details (skipped for wallet) → review
  // Keeps the modal small and focused — no more giant scrollable sheet.
  type Step = "amount" | "method" | "details" | "review";
  const steps: Step[] = [
    ...(amountEditable ? (["amount"] as Step[]) : []),
    "method" as Step,
    ...((["mobile_money", "bank"] as Method[]).includes(method) ? (["details"] as Step[]) : []),
    "review" as Step,
  ];
  const [stepIdx, setStepIdx] = useState(0);
  // Reset to first step every time the modal opens.
  useEffect(() => { if (open) setStepIdx(0); }, [open]);
  // Clamp stepIdx if the steps array shrinks (e.g. user switched to wallet which removes "details").
  useEffect(() => { if (stepIdx > steps.length - 1) setStepIdx(steps.length - 1); }, [stepIdx, steps.length]);
  const currentStep = steps[Math.min(stepIdx, steps.length - 1)];

  const canAdvance = (): boolean => {
    if (currentStep === "amount") return amount > 0;
    if (currentStep === "method") return !!method;
    if (currentStep === "details") {
      if (method === "mobile_money") return !!providerId && !!phone.trim();
      if (method === "bank") return !!providerId && !!accountNumber.trim();
    }
    return true;
  };

  const goNext = () => {
    if (!canAdvance()) {
      if (currentStep === "amount") toast.error("Enter a valid amount");
      else if (currentStep === "details" && method === "mobile_money") toast.error("Enter your mobile number");
      else if (currentStep === "details" && method === "bank") toast.error("Enter your account number");
      return;
    }
    setStepIdx((i) => Math.min(i + 1, steps.length - 1));
  };
  const goBack = () => setStepIdx((i) => Math.max(i - 1, 0));

  return (
    <Dialog open={open} onOpenChange={(v) => !submitting && onOpenChange(v)}>
      <DialogContent className="sm:max-w-md p-0 overflow-hidden">
        {/* Header with progress bar */}
        <div className="px-6 pt-6 pb-4 border-b border-border">
          <div className="flex items-center gap-2 mb-3">
            {stepIdx > 0 && !submitting && (
              <button
                onClick={goBack}
                className="p-1 -ml-1 rounded-md hover:bg-muted text-muted-foreground hover:text-foreground transition-colors"
                aria-label="Back"
              >
                <ArrowLeft className="h-4 w-4" />
              </button>
            )}
            <DialogHeader className="flex-1 text-left space-y-0.5">
              <DialogTitle className="text-base">{title}</DialogTitle>
              {description && <DialogDescription className="text-xs">{description}</DialogDescription>}
            </DialogHeader>
            <span className="text-[10px] uppercase tracking-wider text-muted-foreground font-semibold tabular-nums">
              {stepIdx + 1}/{steps.length}
            </span>
          </div>
          {/* Progress dots */}
          <div className="flex items-center gap-1.5">
            {steps.map((_, i) => (
              <div
                key={i}
                className={cn(
                  "h-1 flex-1 rounded-full transition-colors",
                  i <= stepIdx ? "bg-primary" : "bg-muted",
                )}
              />
            ))}
          </div>
        </div>

        {/* Body */}
        <div className="px-6 py-5 space-y-5 max-h-[60vh] overflow-y-auto">
          {currentStep === "amount" && (
            <div className="space-y-3">
              <div className="rounded-xl bg-gradient-to-br from-primary/10 to-primary/5 p-4">
                <p className="text-xs text-muted-foreground uppercase tracking-wide">Amount</p>
                <FormattedNumberInput
                  value={amountStr}
                  onChange={setAmountStr}
                  prefix={`${currency} `}
                  placeholder={`${currency} 0`}
                  className="mt-1 text-2xl font-bold border-0 bg-transparent shadow-none px-0 focus-visible:ring-0"
                  autoFocus
                />
              </div>
              <p className="text-xs text-muted-foreground">Enter the amount you want to pay.</p>
            </div>
          )}

          {currentStep === "method" && (
            <div className="space-y-3">
              {!amountEditable && (
                <div className="rounded-xl bg-gradient-to-br from-primary/10 to-primary/5 p-4">
                  <p className="text-xs text-muted-foreground uppercase tracking-wide">Amount</p>
                  <p className="mt-1 text-2xl font-bold text-foreground">{format(amount)}</p>
                </div>
              )}
              <div>
                <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">How would you like to pay?</p>
                <RadioGroup value={method} onValueChange={(v) => setMethod(v as Method)} className="space-y-2">
                  {allowWallet && (
                    <MethodOption value="wallet" icon={<WalletIcon className="h-5 w-5" />} title="Nuru Wallet" subtitle="Instant · No fee" current={method} />
                  )}
                  <MethodOption value="mobile_money" icon={<Smartphone className="h-5 w-5" />} title="Mobile Money" subtitle="M-Pesa, Mixx by Yas, Airtel Money, HaloPesa" current={method} />
                  {allowBank ? (
                    <MethodOption value="bank" icon={<Building2 className="h-5 w-5" />} title="Bank Transfer" subtitle="CRDB, NMB, Equity, KCB" current={method} />
                  ) : (
                    <MethodOption value="bank" icon={<Building2 className="h-5 w-5" />} title="Bank Transfer" subtitle="Coming soon" current={method} disabled badge="Coming soon" />
                  )}
                </RadioGroup>
              </div>
            </div>
          )}

          {currentStep === "details" && method === "mobile_money" && (
            <div className="space-y-4">
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Provider</Label>
                <ProviderRadios providers={filteredProviders} value={providerId} onChange={setProviderId} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="ck-phone" className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Mobile number</Label>
                <Input
                  id="ck-phone"
                  type="tel"
                  inputMode="tel"
                  placeholder="07XXXXXXXX"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  autoFocus
                />
                <p className="text-[11px] text-muted-foreground">You'll receive a prompt on this number to approve the payment.</p>
              </div>
            </div>
          )}

          {currentStep === "details" && method === "bank" && (
            <div className="space-y-4">
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Bank</Label>
                <ProviderRadios providers={filteredProviders} value={providerId} onChange={setProviderId} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="ck-account" className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Account number</Label>
                <Input
                  id="ck-account"
                  inputMode="numeric"
                  value={accountNumber}
                  onChange={(e) => setAccountNumber(e.target.value)}
                  autoFocus
                />
              </div>
            </div>
          )}

          {currentStep === "review" && (
            <div className="space-y-4">
              <div className="rounded-xl border border-border bg-muted/30 p-4 space-y-2 text-sm">
                <div className="flex items-center justify-between text-muted-foreground">
                  <span>Amount</span>
                  <span className="tabular-nums text-foreground font-medium">{format(amount)}</span>
                </div>
                <div className="flex items-center justify-between text-muted-foreground">
                  <span>Service fee</span>
                  <span className="tabular-nums">{feeAmount > 0 ? `+ ${format(feeAmount)}` : "Free"}</span>
                </div>
                <div className="flex items-center justify-between border-t border-border pt-2 font-semibold text-foreground">
                  <span>Total</span>
                  <span className="tabular-nums">{format(totalCharged)}</span>
                </div>
                <div className="flex items-center justify-between text-muted-foreground pt-2 border-t border-border">
                  <span>Method</span>
                  <span className="text-foreground font-medium">
                    {method === "wallet" ? "Nuru Wallet" : method === "mobile_money" ? "Mobile Money" : "Bank Transfer"}
                  </span>
                </div>
                {method !== "wallet" && (
                  <div className="flex items-center justify-between text-muted-foreground">
                    <span>{method === "mobile_money" ? "Phone" : "Account"}</span>
                    <span className="text-foreground font-medium tabular-nums">{method === "mobile_money" ? phone : accountNumber}</span>
                  </div>
                )}
              </div>
              <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
                <ShieldCheck className="h-3.5 w-3.5" />
                <span>Secured by Nuru. Funds held in escrow until delivery.</span>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-border bg-muted/20 space-y-2">
          {currentStep === "review" ? (
            <Button onClick={handleSubmit} disabled={submitting} size="lg" className="w-full">
              {submitting ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Processing...
                </>
              ) : (
                `${submitLabel ?? "Pay"} ${format(totalCharged)}`
              )}
            </Button>
          ) : (
            <Button onClick={goNext} size="lg" className="w-full" disabled={!canAdvance()}>
              Continue
            </Button>
          )}

          {supportsOfflineClaim && currentStep !== "review" && (
            <button
              type="button"
              onClick={() => setOfflineClaimOpen(true)}
              className="w-full flex items-center justify-center gap-2 rounded-lg border border-dashed border-primary/40 bg-primary/5 hover:bg-primary/10 text-primary text-sm font-semibold py-2.5 transition-colors"
            >
              <CheckCircle2 className="h-4 w-4" />
              I already paid {targetType === "event_ticket" ? "for this ticket" : "this contribution"}
            </button>
          )}
        </div>
      </DialogContent>

      {/* Nested: "Already paid another way" claim flow */}
      {supportsOfflineClaim && offlineId && (
        <OfflinePaymentClaimModal
          open={offlineClaimOpen}
          onOpenChange={setOfflineClaimOpen}
          targetType={targetType as "event_contribution" | "event_ticket"}
          targetId={offlineId}
          quantity={offlineClaimQuantity ?? 1}
          defaultAmount={amount > 0 ? amount : undefined}
          amountEditable={amountEditable}
          title={targetType === "event_ticket" ? "Already paid for ticket?" : "Already paid your contribution?"}
          description={description}
          onSubmitted={() => onOpenChange(false)}
        />
      )}
    </Dialog>
  );
};

const MethodOption = ({
  value,
  icon,
  title,
  subtitle,
  current,
  disabled = false,
  badge,
}: {
  value: Method;
  icon: React.ReactNode;
  title: string;
  subtitle: string;
  current: Method;
  disabled?: boolean;
  badge?: string;
}) => {
  const active = current === value && !disabled;
  return (
    <Label
      htmlFor={`m-${value}`}
      aria-disabled={disabled}
      className={`flex items-center gap-3 rounded-lg border p-3 transition-all ${
        disabled
          ? "border-border bg-muted/30 opacity-60 cursor-not-allowed"
          : active
            ? "border-primary bg-primary/5 cursor-pointer"
            : "border-border hover:bg-muted/40 cursor-pointer"
      }`}
    >
      <RadioGroupItem value={value} id={`m-${value}`} className="sr-only" disabled={disabled} />
      <div className={`h-9 w-9 rounded-lg flex items-center justify-center ${active ? "bg-primary text-primary-foreground" : "bg-muted text-foreground"}`}>
        {icon}
      </div>
      <div className="flex-1">
        <p className="text-sm font-medium text-foreground">{title}</p>
        <p className="text-xs text-muted-foreground">{subtitle}</p>
      </div>
      {badge ? (
        <span className="text-[10px] uppercase tracking-wide font-semibold text-muted-foreground bg-muted px-2 py-0.5 rounded-full">
          {badge}
        </span>
      ) : (
        <div className={`h-4 w-4 rounded-full border-2 ${active ? "border-primary bg-primary" : "border-muted-foreground/40"}`} />
      )}
    </Label>
  );
};

const ProviderRadios = ({
  providers,
  value,
  onChange,
}: {
  providers: PaymentProvider[];
  value: string;
  onChange: (v: string) => void;
}) => {
  if (!providers.length) {
    return <p className="text-xs text-muted-foreground">No providers available for your country.</p>;
  }
  return (
    <div className="grid grid-cols-2 gap-2">
      {providers.map((p) => {
        const active = value === p.id;
        return (
          <button
            key={p.id}
            type="button"
            onClick={() => onChange(p.id)}
            className={`text-left rounded-lg border p-2.5 text-xs transition-all ${
              active ? "border-primary bg-primary/5" : "border-border hover:bg-muted/40"
            }`}
          >
            <p className="font-medium text-foreground truncate">{p.name ?? p.display_name ?? p.code}</p>
            <p className="text-[10px] text-muted-foreground uppercase">{p.code}</p>
          </button>
        );
      })}
    </div>
  );
};

export default CheckoutModal;
