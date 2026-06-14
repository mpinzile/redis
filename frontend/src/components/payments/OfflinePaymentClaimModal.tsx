/**
 * OfflinePaymentClaimModal — "I already paid via another method" flow.
 *
 * Used in two scenarios:
 *   1. event_contribution → POST /user-contributors/events/:id/self-contribute
 *   2. event_ticket       → POST /ticketing/classes/:id/offline-claim
 *
 * Steps: channel (mobile_money | bank) → provider + payer account →
 * amount + transaction code + optional receipt image → review.
 * The submission goes via multipart/form-data so the backend can validate
 * and store the receipt image alongside the audit trail.
 */
import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FormattedNumberInput } from "@/components/ui/formatted-number-input";
import { Textarea } from "@/components/ui/textarea";
import { Loader2, Smartphone, Building2, ArrowLeft, ImagePlus, X, ShieldCheck, CheckCircle2 } from "lucide-react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useCurrency } from "@/hooks/useCurrency";
import { api } from "@/lib/api";
import { postFormData } from "@/lib/api/helpers";
import type { PaymentProvider } from "@/lib/api/payments-types";

type Channel = "mobile_money" | "bank";
type Step = "channel" | "details" | "amount" | "review";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  /** What is being claimed against. */
  targetType: "event_contribution" | "event_ticket";
  /**
   * For event_contribution: the event_id (POSTs /events/{id}/self-contribute).
   * For event_ticket: the ticket_class_id (POSTs /classes/{id}/offline-claim).
   */
  targetId: string;
  /** Defaults to the outstanding balance / quoted total. User can edit if `amountEditable`. */
  defaultAmount?: number;
  amountEditable?: boolean;
  /** For tickets we need the qty so the backend records the right count. */
  quantity?: number;
  title: string;
  description?: string;
  onSubmitted?: () => void;
}

const MAX_BYTES = 5 * 1024 * 1024;
const MIN_BYTES = 4 * 1024;
const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"];

export const OfflinePaymentClaimModal = ({
  open,
  onOpenChange,
  targetType,
  targetId,
  defaultAmount,
  amountEditable = false,
  quantity = 1,
  title,
  description,
  onSubmitted,
}: Props) => {
  const { currency, countryCode, format } = useCurrency();

  const [stepIdx, setStepIdx] = useState(0);
  const [channel, setChannel] = useState<Channel>("mobile_money");
  const [providerId, setProviderId] = useState<string>("");
  const [providerName, setProviderName] = useState<string>("");
  const [payerAccount, setPayerAccount] = useState("");
  const [amountStr, setAmountStr] = useState(defaultAmount ? String(defaultAmount) : "");
  const [transactionCode, setTransactionCode] = useState("");
  const [note, setNote] = useState("");
  const [receiptFile, setReceiptFile] = useState<File | null>(null);
  const [receiptPreview, setReceiptPreview] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Reset on open
  useEffect(() => {
    if (open) {
      setStepIdx(0);
      setChannel("mobile_money");
      setProviderId("");
      setProviderName("");
      setPayerAccount("");
      setAmountStr(defaultAmount ? String(defaultAmount) : "");
      setTransactionCode("");
      setNote("");
      setReceiptFile(null);
      setReceiptPreview(null);
    }
  }, [open, defaultAmount]);

  // Cleanup blob URL
  useEffect(() => {
    return () => { if (receiptPreview) URL.revokeObjectURL(receiptPreview); };
  }, [receiptPreview]);

  const providersQuery = useQuery({
    queryKey: ["offline-claim-providers", countryCode],
    enabled: open && !!countryCode,
    queryFn: async () => {
      const res = await api.payments.providers({ country_code: countryCode!, purpose: "collection" });
      return res.success && Array.isArray(res.data) ? res.data : [];
    },
  });

  const filteredProviders: PaymentProvider[] = useMemo(
    () => (providersQuery.data ?? []).filter((p) =>
      channel === "mobile_money" ? p.provider_type === "mobile_money" : p.provider_type === "bank"
    ),
    [providersQuery.data, channel]
  );

  const steps: Step[] = useMemo(() => {
    const base: Step[] = ["channel", "details"];
    if (amountEditable) base.push("amount");
    base.push("review");
    return base;
  }, [amountEditable]);
  const currentStep = steps[Math.min(stepIdx, steps.length - 1)];

  const amount = Number(amountStr) || defaultAmount || 0;

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (!ALLOWED_TYPES.includes(file.type)) {
      toast.error("Only JPG, PNG or WebP images are allowed");
      return;
    }
    if (file.size < MIN_BYTES) {
      toast.error("Receipt image is too small to be valid");
      return;
    }
    if (file.size > MAX_BYTES) {
      toast.error("Receipt image must be 5 MB or smaller");
      return;
    }
    if (receiptPreview) URL.revokeObjectURL(receiptPreview);
    setReceiptFile(file);
    setReceiptPreview(URL.createObjectURL(file));
  };

  const clearReceipt = () => {
    if (receiptPreview) URL.revokeObjectURL(receiptPreview);
    setReceiptFile(null);
    setReceiptPreview(null);
  };

  const canAdvance = (): boolean => {
    if (currentStep === "channel") return !!channel;
    if (currentStep === "details") {
      const hasProvider = !!providerId || providerName.trim().length > 1;
      return hasProvider;
    }
    if (currentStep === "amount") return amount > 0;
    return true;
  };

  const goNext = () => {
    if (!canAdvance()) {
      if (currentStep === "details") toast.error("Pick a provider or type a name");
      else if (currentStep === "amount") toast.error("Enter a valid amount");
      return;
    }
    // Provider id → snapshot name for review screen
    if (currentStep === "details" && providerId && !providerName) {
      const p = filteredProviders.find((x) => x.id === providerId);
      if (p) setProviderName(p.name ?? p.display_name ?? p.code ?? "");
    }
    setStepIdx((i) => Math.min(i + 1, steps.length - 1));
  };
  const goBack = () => setStepIdx((i) => Math.max(i - 1, 0));

  const handleSubmit = async () => {
    if (amount <= 0) { toast.error("Amount must be greater than zero"); return; }
    if (transactionCode.trim().length < 3) { toast.error("Transaction code is required"); return; }

    setSubmitting(true);
    try {
      const fd = new FormData();
      fd.append("amount", String(amount));
      fd.append("payment_channel", channel);
      fd.append("transaction_code", transactionCode.trim());
      if (providerId) fd.append("provider_id", providerId);
      if (providerName.trim()) fd.append("provider_name", providerName.trim());
      if (payerAccount.trim()) fd.append("payer_account", payerAccount.trim());
      if (note.trim()) fd.append("note", note.trim());
      if (receiptFile) fd.append("receipt_image", receiptFile);

      let endpoint = "";
      if (targetType === "event_contribution") {
        endpoint = `/user-contributors/events/${targetId}/self-contribute`;
      } else {
        fd.append("quantity", String(quantity));
        endpoint = `/ticketing/classes/${targetId}/offline-claim`;
      }

      const res = await postFormData<any>(endpoint, fd);
      if (!res.success) {
        toast.error(res.message || "Could not submit claim");
        return;
      }
      toast.success("Submitted for review", {
        description: "The organiser will confirm or reject shortly. You'll be notified.",
      });
      onSubmitted?.();
      onOpenChange(false);
    } catch (e) {
      toast.error("Something went wrong. Please try again.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !submitting && onOpenChange(v)}>
      <DialogContent className="sm:max-w-md p-0 overflow-hidden">
        {/* Header */}
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
          {currentStep === "channel" && (
            <div className="space-y-3">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
                How did you pay?
              </p>
              <button
                type="button"
                onClick={() => setChannel("mobile_money")}
                className={cn(
                  "w-full flex items-center gap-3 rounded-lg border p-3 text-left transition-all",
                  channel === "mobile_money" ? "border-primary bg-primary/5" : "border-border hover:bg-muted/40"
                )}
              >
                <div className={cn(
                  "h-9 w-9 rounded-lg flex items-center justify-center",
                  channel === "mobile_money" ? "bg-primary text-primary-foreground" : "bg-muted text-foreground"
                )}>
                  <Smartphone className="h-5 w-5" />
                </div>
                <div className="flex-1">
                  <p className="text-sm font-medium text-foreground">Mobile Money</p>
                  <p className="text-xs text-muted-foreground">M-Pesa, Mixx by Yas, Airtel Money…</p>
                </div>
              </button>
              <button
                type="button"
                onClick={() => setChannel("bank")}
                className={cn(
                  "w-full flex items-center gap-3 rounded-lg border p-3 text-left transition-all",
                  channel === "bank" ? "border-primary bg-primary/5" : "border-border hover:bg-muted/40"
                )}
              >
                <div className={cn(
                  "h-9 w-9 rounded-lg flex items-center justify-center",
                  channel === "bank" ? "bg-primary text-primary-foreground" : "bg-muted text-foreground"
                )}>
                  <Building2 className="h-5 w-5" />
                </div>
                <div className="flex-1">
                  <p className="text-sm font-medium text-foreground">Bank Transfer</p>
                  <p className="text-xs text-muted-foreground">CRDB, NMB, Equity, KCB…</p>
                </div>
              </button>
            </div>
          )}

          {currentStep === "details" && (
            <div className="space-y-4">
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  {channel === "mobile_money" ? "Mobile network" : "Bank"}
                </Label>
                {providersQuery.isLoading ? (
                  <div className="text-xs text-muted-foreground flex items-center gap-2">
                    <Loader2 className="h-3 w-3 animate-spin" /> Loading providers…
                  </div>
                ) : filteredProviders.length > 0 ? (
                  <div className="grid grid-cols-2 gap-2">
                    {filteredProviders.map((p) => {
                      const active = providerId === p.id;
                      const label = p.name ?? p.display_name ?? p.code;
                      return (
                        <button
                          key={p.id}
                          type="button"
                          onClick={() => { setProviderId(p.id); setProviderName(label); }}
                          className={cn(
                            "text-left rounded-lg border p-2.5 text-xs transition-all",
                            active ? "border-primary bg-primary/5" : "border-border hover:bg-muted/40"
                          )}
                        >
                          <p className="font-medium text-foreground truncate">{label}</p>
                          <p className="text-[10px] text-muted-foreground uppercase">{p.code}</p>
                        </button>
                      );
                    })}
                  </div>
                ) : (
                  <p className="text-xs text-muted-foreground">No providers listed for your country — type the name below.</p>
                )}
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="oc-other" className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  Other (type if not listed)
                </Label>
                <Input
                  id="oc-other"
                  value={!providerId ? providerName : ""}
                  onChange={(e) => { setProviderId(""); setProviderName(e.target.value); }}
                  placeholder={channel === "mobile_money" ? "e.g. Mixx by Yas" : "e.g. Stanbic Bank"}
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="oc-account" className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  {channel === "mobile_money" ? "Number you paid from (optional)" : "Account paid from (optional)"}
                </Label>
                <Input
                  id="oc-account"
                  value={payerAccount}
                  onChange={(e) => setPayerAccount(e.target.value)}
                  placeholder={channel === "mobile_money" ? "07XX XXX XXX" : "0123 4567 8901"}
                  inputMode={channel === "mobile_money" ? "tel" : "numeric"}
                />
              </div>
            </div>
          )}

          {currentStep === "amount" && (
            <div className="space-y-3">
              <div className="rounded-xl bg-gradient-to-br from-primary/10 to-primary/5 p-4">
                <p className="text-xs text-muted-foreground uppercase tracking-wide">Amount paid</p>
                <FormattedNumberInput
                  value={amountStr}
                  onChange={setAmountStr}
                  prefix={`${currency} `}
                  placeholder={`${currency} 0`}
                  className="mt-1 text-2xl font-bold border-0 bg-transparent shadow-none px-0 focus-visible:ring-0"
                  autoFocus
                />
              </div>
              <p className="text-xs text-muted-foreground">Enter the exact amount you sent.</p>
            </div>
          )}

          {currentStep === "review" && (
            <div className="space-y-4">
              <div className="space-y-1.5">
                <Label htmlFor="oc-txn" className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  Transaction code <span className="text-destructive">*</span>
                </Label>
                <Input
                  id="oc-txn"
                  value={transactionCode}
                  onChange={(e) => setTransactionCode(e.target.value.toUpperCase())}
                  placeholder="e.g. QHJ8X12B45"
                  className="font-mono tracking-wider"
                  autoFocus
                />
                <p className="text-[11px] text-muted-foreground">
                  The reference from your mobile money / bank confirmation message.
                </p>
              </div>

              <div className="space-y-1.5">
                <Label className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  Receipt image (optional)
                </Label>
                {receiptPreview ? (
                  <div className="relative rounded-lg border border-border overflow-hidden bg-muted">
                    <img src={receiptPreview} alt="Receipt preview" className="w-full max-h-48 object-contain" />
                    <button
                      type="button"
                      onClick={clearReceipt}
                      className="absolute top-2 right-2 h-7 w-7 rounded-full bg-background/90 backdrop-blur border border-border flex items-center justify-center text-foreground hover:bg-destructive hover:text-destructive-foreground transition-colors"
                      aria-label="Remove receipt"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                    <p className="text-[11px] text-muted-foreground p-2 truncate">
                      {receiptFile?.name} - {((receiptFile?.size ?? 0) / 1024).toFixed(0)} KB
                    </p>
                  </div>
                ) : (
                  <label
                    htmlFor="oc-receipt"
                    className="flex flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed border-border bg-muted/30 px-4 py-6 text-center cursor-pointer hover:border-primary/50 hover:bg-muted/50 transition-colors"
                  >
                    <ImagePlus className="h-6 w-6 text-muted-foreground" />
                    <span className="text-xs font-medium text-foreground">Tap to attach a screenshot</span>
                    <span className="text-[10px] text-muted-foreground">JPG, PNG or WebP - up to 5 MB</span>
                  </label>
                )}
                <input
                  id="oc-receipt"
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  className="sr-only"
                  onChange={handleFileSelect}
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="oc-note" className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  Note (optional)
                </Label>
                <Textarea
                  id="oc-note"
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  rows={2}
                  placeholder="Any context the organiser should know"
                />
              </div>

              <div className="rounded-xl border border-border bg-muted/30 p-4 space-y-2 text-sm">
                <div className="flex items-center justify-between text-muted-foreground">
                  <span>Channel</span>
                  <span className="text-foreground font-medium capitalize">{channel.replace("_", " ")}</span>
                </div>
                <div className="flex items-center justify-between text-muted-foreground">
                  <span>Provider</span>
                  <span className="text-foreground font-medium">{providerName || "—"}</span>
                </div>
                <div className="flex items-center justify-between text-muted-foreground">
                  <span>Amount</span>
                  <span className="text-foreground font-semibold tabular-nums">{format(amount)}</span>
                </div>
              </div>

              <div className="flex items-start gap-2 text-[11px] text-muted-foreground">
                <ShieldCheck className="h-3.5 w-3.5 mt-0.5 flex-shrink-0" />
                <span>The organiser will verify your transaction and approve it. False claims can be rejected.</span>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-border bg-muted/20">
          {currentStep === "review" ? (
            <Button onClick={handleSubmit} disabled={submitting} size="lg" className="w-full">
              {submitting ? (
                <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Submitting…</>
              ) : (
                <><CheckCircle2 className="h-4 w-4 mr-2" /> Submit for review</>
              )}
            </Button>
          ) : (
            <Button onClick={goNext} size="lg" className="w-full" disabled={!canAdvance()}>
              Continue
            </Button>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default OfflinePaymentClaimModal;
