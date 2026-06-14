import EditorialFeaturePage from "@/components/features/EditorialFeaturePage";
import { useMeta } from "@/hooks/useMeta";

const EventPlanning = () => {
  useMeta({
    title: "Event Planning Workspace | Nuru",
    description:
      "Plan weddings, conferences, graduations, exhibitions, and family celebrations from one workspace. Budgets, timelines, committees, vendors and contributions · all connected.",
  });

  return (
    <EditorialFeaturePage
      kicker="Service - 01 - Event Planning"
      title="The command centre of every celebration."
      lead="Open a workspace for any occasion · wedding, conference, graduation, exhibition, family gathering or business event. Build budgets, invite guests, coordinate committees, collect contributions, sell tickets, and book vendors from one place."
      specs={[
        { label: "Event types", value: "Weddings → Conferences" },
        { label: "Workspace cost", value: "Free to open" },
        { label: "Coordination", value: "Real-time" },
        { label: "Records", value: "Audit-grade" },
      ]}
      sections={[
        {
          title: "One workspace, every moving part.",
          lead: "Stop juggling spreadsheets, group chats, and notebooks. Nuru consolidates the entire event into a single, transparent surface.",
          bullets: [
            "Live budget that updates as expenses are recorded.",
            "Timelines with milestones, deadlines and reminders.",
            "Task assignment across organisers and committees.",
            "Guest list with RSVP, dietary and seating notes.",
            "Vendor coordination and booking history.",
            "Real-time progress, no manual follow-up.",
          ],
        },
        {
          title: "Committees that actually coordinate.",
          lead: "Add the people running decoration, food, transport, invitations or entertainment. Each committee gets the visibility they need · nothing more, nothing less.",
          bullets: [
            "Role-based access for committee members.",
            "Shared sub-budgets per committee.",
            "Built-in announcements and group threads.",
            "Built-in video meetings for committee calls.",
            "Activity log for every decision and change.",
            "Handover-ready records when the event ends.",
          ],
        },
        {
          title: "Built for every event.",
          lead: "Weddings, memorials, send-offs, corporate offsites, fundraisers, graduations, conferences, birthdays. Every workflow respects how families, companies and communities actually run events · anywhere in the world.",
          bullets: [
            "Multi-event programmes (pre-, main, after).",
            "Multiple organisers with shared control.",
            "Family contribution tracking, not just ticket sales.",
            "Local payment methods built-in (M-Pesa, Airtel, Mixx by Yas, banks).",
            "Bilingual interfaces · English and Swahili.",
            "Works on the slowest connections.",
          ],
        },
      ]}
      cta={{
        eyebrow: "Open a workspace",
        title: "Plan smarter. Celebrate better.",
        body: "Free to open, free to invite your committee. You only pay when you transact.",
        primary: { label: "Create your workspace", href: "/register" },
        secondary: { label: "See all features", href: "/features/payments" },
      }}
    />
  );
};

export default EventPlanning;
