import EditorialFeaturePage from "@/components/features/EditorialFeaturePage";
import { useMeta } from "@/hooks/useMeta";

const Payments = () => {
  useMeta({
    title: "Built-in Payments & Contributions | Nuru",
    description:
      "Mobile money, cards and bank transfers · built into every Nuru event. Contributions, deposits, ticket sales and vendor payouts, settled in 24 hours with full audit trail.",
  });

  return (
    <EditorialFeaturePage
      kicker="Service - 05 - Payments"
      title="Money that behaves like a bank, feels like family."
      lead="Mobile money, cards and bank transfers, built into every workspace. Contributions, ticket sales, deposits and payouts settle within 24 hours · with receipts, dispute protection and a complete audit trail."
      specs={[
        { label: "Methods", value: "M-Pesa · Airtel · Mixx by Yas · Card · Bank" },
        { label: "Settlement", value: "≤ 24 hours" },
        { label: "Receipts", value: "Auto-issued" },
        { label: "Coverage", value: "TZ · KE · International" },
      ]}
      sections={[
        {
          title: "Every channel families actually use.",
          lead: "Contributors choose the method that's natural for them · phone, card or bank · and the money lands in the same place.",
          bullets: [
            "M-Pesa, Airtel Money, Mixx by Yas, Halopesa.",
            "Visa and Mastercard, debit and credit.",
            "Bank transfer with auto-matching references.",
            "International contributions in USD.",
            "Cash recorded manually with receipt.",
            "QR and link-based contributions.",
          ],
        },
        {
          title: "Contribution pages that feel personal.",
          lead: "Share a single secure link. Each contributor sees the event, the cause, and a ledger of who has given. Privacy controls let you hide amounts when needed.",
          bullets: [
            "Branded public contribution pages.",
            "Optional named or anonymous giving.",
            "Real-time progress towards the goal.",
            "Per-contributor receipts via SMS / WA / email.",
            "Refund and reversal flow.",
            "Embedded in invitations and NuruCards.",
          ],
        },
        {
          title: "Trust infrastructure, end to end.",
          lead: "Money moves through licensed processors. Vendor deposits sit in protected payments until milestones are met. Every shilling is recorded.",
          bullets: [
            "PCI-DSS aligned card processing.",
            "Vendor deposit protection.",
            "Milestone-based release.",
            "Dispute and reconciliation flow.",
            "Daily reconciled ledger.",
            "Tax-ready transaction exports.",
          ],
        },
      ]}
      cta={{
        eyebrow: "Built-in payments",
        title: "Audit-grade. End-to-end.",
        body: "Open a free workspace and start collecting in minutes.",
        primary: { label: "Open a workspace", href: "/register" },
        secondary: { label: "Trust & protection", href: "/features/trust" },
      }}
    />
  );
};

export default Payments;
