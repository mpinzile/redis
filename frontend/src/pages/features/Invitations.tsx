import EditorialFeaturePage from "@/components/features/EditorialFeaturePage";
import { useMeta } from "@/hooks/useMeta";

const Invitations = () => {
  useMeta({
    title: "Digital Invitations & RSVP | Nuru",
    description:
      "Send personalised digital invitations across SMS, WhatsApp, email and short links. Track RSVPs in real time. Send reminders. Manage seating and dietary notes.",
  });

  return (
    <EditorialFeaturePage
      kicker="Service - 03 - Invitations"
      title="Invitations that arrive · and reply."
      lead="Beautiful, personalised invitations delivered through SMS, WhatsApp, email or a unique short link. Each guest gets their own page. Each RSVP lands in your dashboard, instantly."
      specs={[
        { label: "Channels", value: "SMS · WA · Email · Link" },
        { label: "Personalisation", value: "Per guest" },
        { label: "Tracking", value: "Real-time" },
        { label: "Cost", value: "Per delivery" },
      ]}
      sections={[
        {
          title: "Personal at scale.",
          lead: "Each invitation is unique to the guest · their name, table, dress code, programme, and a one-tap RSVP. No more group blasts.",
          bullets: [
            "Personalised guest landing pages.",
            "Multi-language SMS and WhatsApp.",
            "Built-in design templates by event type.",
            "Add programme, map and dress code.",
            "Plus-ones and dietary preferences.",
            "Resend reminders to non-responders only.",
          ],
        },
        {
          title: "RSVP that respects organisers.",
          lead: "See exactly who is coming, who has not responded, and who needs a nudge. Plan seating, food orders and transport off real numbers.",
          bullets: [
            "Live RSVP counters by status.",
            "Filter by family, side, table, or category.",
            "Export to CSV anytime.",
            "Auto-reminder schedules.",
            "Capacity caps and waitlists.",
            "Seating chart with drag-and-drop.",
          ],
        },
        {
          title: "Becomes your check-in on the day.",
          lead: "Every digital invitation is also a check-in token. Pair with NFC NuruCards or QR scan for fast entry · no paper lists, no confusion at the gate.",
          bullets: [
            "Scan-to-check-in via NFC or QR.",
            "Live arrival board for organisers.",
            "Self check-in for trusted guests.",
            "Block re-entry / duplicate detection.",
            "Tag VIPs and protocol arrivals.",
            "Post-event attendance report.",
          ],
        },
      ]}
      cta={{
        eyebrow: "Invitations & RSVP",
        title: "Send invitations people actually open.",
        primary: { label: "Try it free", href: "/register" },
        secondary: { label: "About NuruCards", href: "/features/nfc-cards" },
      }}
    />
  );
};

export default Invitations;
