import EditorialFeaturePage from "@/components/features/EditorialFeaturePage";
import { useMeta } from "@/hooks/useMeta";

const Ticketing = () => {
  useMeta({
    title: "Sell & Buy Tickets | Nuru",
    description:
      "Sell tickets for concerts, conferences, fundraisers and exclusive events. Tiered pricing, mobile money checkout, QR + NFC entry, real-time sales dashboard.",
  });

  return (
    <EditorialFeaturePage
      kicker="Service - 08 - Ticketing"
      title="Sell tickets without selling your soul."
      lead="Concerts, conferences, fundraisers, sports days, exclusive dinners. Set tiers, take mobile money or card, scan at the door. No predatory fees, no slow payouts, no walk-away guests."
      specs={[
        { label: "Tiers", value: "Unlimited" },
        { label: "Checkout", value: "M-Pesa · Card · Bank" },
        { label: "Entry", value: "QR + NFC" },
        { label: "Payout", value: "≤ 24h" },
      ]}
      sections={[
        {
          title: "A storefront in minutes.",
          lead: "Publish a public event page with tiered tickets, descriptions, dates and venue. Share a single link · buyers checkout in one screen.",
          bullets: [
            "Multiple tiers (Early, Regular, VIP, Group).",
            "Time-based and quantity-based releases.",
            "Discount codes and group bundles.",
            "SEO-ready public event page.",
            "Add-ons (parking, dinner, merch).",
            "Promoter and affiliate links.",
          ],
        },
        {
          title: "Checkout that respects your buyers.",
          lead: "Mobile money first, card second. Receipts go to SMS, WhatsApp and email. The ticket is also on the buyer's phone in seconds.",
          bullets: [
            "M-Pesa, Airtel, Mixx by Yas, Halopesa.",
            "Visa, Mastercard, USD checkout.",
            "Bank transfer with auto-match.",
            "Tickets delivered via SMS, WhatsApp, email.",
            "Buy-on-behalf for groups.",
            "Refund and exchange controls.",
          ],
        },
        {
          title: "Door operations, solved.",
          lead: "Scan QR codes or tap NuruCards at the gate. Live sales and arrival dashboards keep promoters honest and organisers informed.",
          bullets: [
            "QR scan from any phone.",
            "NFC NuruCards as premium tickets.",
            "Multiple gate scanners in sync.",
            "Re-entry and duplicate prevention.",
            "Live sales and check-in dashboard.",
            "Post-event sales and audit report.",
          ],
        },
      ]}
      cta={{
        eyebrow: "Ticketing",
        title: "Sell out. Settle fast. Sleep well.",
        primary: { label: "Start selling tickets", href: "/register" },
        secondary: { label: "Payments", href: "/features/payments" },
      }}
    />
  );
};

export default Ticketing;
