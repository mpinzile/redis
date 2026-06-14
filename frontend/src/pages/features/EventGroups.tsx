import EditorialFeaturePage from "@/components/features/EditorialFeaturePage";
import { useMeta } from "@/hooks/useMeta";

const EventGroups = () => {
  useMeta({
    title: "Event Groups · Contributors, Organisers & Committees | Nuru",
    description:
      "Bring contributors, organisers and committee members into one structured group per event. Coordinate, contribute, decide · without losing the audit trail.",
  });

  return (
    <EditorialFeaturePage
      kicker="Service - 07 - Event Groups"
      title="One group. Every role. Total clarity."
      lead="Every Nuru event has a structured group that brings together organisers, contributors and committee members. Roles are explicit, permissions are granular, and every conversation, contribution and decision is recorded against the event."
      specs={[
        { label: "Roles", value: "Org · Comm · Contrib" },
        { label: "Permissions", value: "Granular" },
        { label: "Audit", value: "Full ledger" },
        { label: "Privacy", value: "Per-channel" },
      ]}
      sections={[
        {
          title: "Roles that match how families actually run events.",
          lead: "Organisers lead. Committee members run portfolios · food, decoration, transport, entertainment. Contributors give and stay informed. Each sees only what they need.",
          bullets: [
            "Organiser, committee, contributor, guest roles.",
            "Custom committees per event (food, decor, transport…).",
            "Per-committee budgets and tasks.",
            "Contributors see goals and progress, not raw lists.",
            "Private organiser-only channel.",
            "Read-only family channel for elders.",
          ],
        },
        {
          title: "Conversations that don't get lost.",
          lead: "Replace a dozen WhatsApp groups with structured channels per topic. Search history, pin announcements, and tag decisions to action items.",
          bullets: [
            "Channels per committee and topic.",
            "Pinned announcements.",
            "Polls for group decisions.",
            "Built-in video meetings (Service 06).",
            "File and image sharing.",
            "Translated mentions across English and Swahili.",
          ],
        },
        {
          title: "Every action lives on the ledger.",
          lead: "Contributions, vendor decisions, budget changes, RSVP edits · every action is timestamped and attached to the event. No more 'who agreed to that?'",
          bullets: [
            "Full activity feed per event.",
            "Tamper-evident decision log.",
            "Per-user contribution history.",
            "Filtered exports for committees and elders.",
            "Closeout report after the event.",
            "Privacy controls on what contributors see.",
          ],
        },
      ]}
      cta={{
        eyebrow: "Event groups",
        title: "Bring everyone into one room. Quietly.",
        primary: { label: "Open a workspace", href: "/register" },
        secondary: { label: "Built-in meetings", href: "/features/meetings" },
      }}
    />
  );
};

export default EventGroups;
