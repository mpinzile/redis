import EditorialFeaturePage from "@/components/features/EditorialFeaturePage";
import { useMeta } from "@/hooks/useMeta";

const NfcCards = () => {
  useMeta({
    title: "NuruCards · NFC Event Cards | Nuru",
    description:
      "Premium NFC cards for weddings, conferences and exclusive events. Tap to RSVP, tap to check in, tap to contribute. Designed in your event branding.",
  });

  return (
    <EditorialFeaturePage
      kicker="Service - 04 - NuruCards"
      title="A card that knows the guest."
      lead="A premium NFC card branded for your event. One tap shares the invitation, confirms attendance, opens the contribution page, or checks the guest in at the door. The card is the experience."
      specs={[
        { label: "Material", value: "Premium PVC" },
        { label: "Tech", value: "NFC + QR" },
        { label: "Personalisation", value: "Per guest" },
        { label: "Use cases", value: "RSVP · Pay · Enter" },
      ]}
      sections={[
        {
          title: "Designed in your event identity.",
          lead: "Choose a template or upload artwork. Each card carries the guest's name and a quiet, secure NFC chip. They feel like an heirloom · they work like a key.",
          bullets: [
            "Custom finishes · matte, gloss, foil.",
            "Guest name and seat printed.",
            "Branded back with QR fallback.",
            "Programmed and verified before delivery.",
            "Reusable across multi-day programmes.",
            "Bulk discounts for large guest lists.",
          ],
        },
        {
          title: "One tap. Everything happens.",
          lead: "The card is an entry point into the entire event. Tap a phone, the right page opens · every time.",
          bullets: [
            "Tap to RSVP from the invitation.",
            "Tap to contribute without typing details.",
            "Tap to check in at the gate.",
            "Tap to receive the programme and map.",
            "Tap to receive event photos after.",
            "Optional VIP / protocol routing.",
          ],
        },
        {
          title: "Operations-grade at the door.",
          lead: "Forget paper lists. The check-in app pairs with cards and phones for sub-second entry, with a live arrival dashboard for the organiser.",
          bullets: [
            "Sub-second NFC verification.",
            "Works offline, syncs when back online.",
            "Re-entry control and duplicate detection.",
            "Per-gate, per-session check-in.",
            "Live arrival board.",
            "Post-event attendance audit.",
          ],
        },
      ]}
      cta={{
        eyebrow: "Order NuruCards",
        title: "The most memorable invitation in the room.",
        primary: { label: "Request a quote", href: "/contact" },
        secondary: { label: "See invitations", href: "/features/invitations" },
      }}
    />
  );
};

export default NfcCards;
