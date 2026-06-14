import EditorialFeaturePage from "@/components/features/EditorialFeaturePage";
import { useMeta } from "@/hooks/useMeta";

const ServiceProviders = () => {
  useMeta({
    title: "Vendors & Service Providers | Nuru",
    description:
      "A growth and trust platform for caterers, decorators, photographers, MCs, venues, transport, sound and entertainment vendors. Verified, bookable, paid on time.",
  });

  return (
    <EditorialFeaturePage
      kicker="Service - 02 - Vendors"
      title="A growth platform, not a chase."
      lead="Caterers, decorators, photographers, MCs, transport, sound, lighting, entertainment, venues. Build a verified Nuru profile, accept bookings, get paid through protected payments · and stop chasing money."
      specs={[
        { label: "Verification", value: "ID + business" },
        { label: "Payouts", value: "Protected" },
        { label: "Reach", value: "Tanzania + Kenya" },
        { label: "Profile cost", value: "Free" },
      ]}
      sections={[
        {
          title: "Be discovered by the right organisers.",
          lead: "Your verified profile, portfolio and reviews work for you 24/7. Organisers find you by category, city, budget and date · and book directly.",
          bullets: [
            "Public profile with portfolio gallery.",
            "Searchable by category, city, price band.",
            "Reviews tied to real bookings only.",
            "Built-in messaging with organisers.",
            "Calendar and availability management.",
            "Repeat-customer dashboard.",
          ],
        },
        {
          title: "Bookings, contracts, payments · handled.",
          lead: "Every booking is a structured contract with deposit, milestones, deliverables and final settlement. No more verbal agreements, no more missing money.",
          bullets: [
            "Protected deposits via M-Pesa, Airtel, Mixx by Yas, banks, cards.",
            "Milestone-based release, not lump sums.",
            "Automatic receipts for organisers and you.",
            "Dispute and appeal flow when something goes wrong.",
            "Tax-ready transaction history.",
            "Payouts within 24 hours of release.",
          ],
        },
        {
          title: "Trust earned, displayed, defended.",
          lead: "Verified identity, verified business, verified reviews. The Nuru badge means an organiser can hire you with the same confidence as a bank counterparty.",
          bullets: [
            "National ID / business verification.",
            "Public verification badge on profile.",
            "Reviews can't be bought or faked.",
            "Appeal and remediation flow for disputes.",
            "Protection against impersonation.",
            "Visible track record · bookings completed, on-time rate.",
          ],
        },
      ]}
      cta={{
        eyebrow: "Become a Nuru vendor",
        title: "Get verified. Get booked.",
        body: "Free to join. We earn only when you do.",
        primary: { label: "Create vendor profile", href: "/register" },
        secondary: { label: "Trust & protection", href: "/features/trust" },
      }}
    />
  );
};

export default ServiceProviders;
