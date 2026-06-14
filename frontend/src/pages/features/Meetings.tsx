import EditorialFeaturePage from "@/components/features/EditorialFeaturePage";
import { useMeta } from "@/hooks/useMeta";

const Meetings = () => {
  useMeta({
    title: "Built-in Video Meetings | Nuru",
    description:
      "HD video meetings inside every event workspace. Run committee calls, vendor briefings and family planning sessions without leaving Nuru.",
  });

  return (
    <EditorialFeaturePage
      kicker="Service - 06 - Meetings"
      title="Committee calls, inside the workspace."
      lead="Built-in HD video meetings for organisers, committees, vendors and family groups. Open a room from any event with one click · no installs, no separate accounts, no link-juggling."
      specs={[
        { label: "Quality", value: "HD video" },
        { label: "Capacity", value: "Up to 50" },
        { label: "Recording", value: "Optional" },
        { label: "Cost", value: "Included" },
      ]}
      sections={[
        {
          title: "Open a room from anywhere in the event.",
          lead: "From the budget page, the vendor thread, or a committee group · one button starts a meeting that everyone in the right room can join.",
          bullets: [
            "Browser-based · no downloads.",
            "Mobile and desktop supported.",
            "Permission-aware: only invited members join.",
            "Persistent room links per committee.",
            "Calendar invitations and reminders.",
            "Low-bandwidth mode for slower networks.",
          ],
        },
        {
          title: "Built for event coordination.",
          lead: "Meetings are tied to the event context · agenda, budget, tasks and decisions made stay attached to the workspace, not lost in a chat app.",
          bullets: [
            "Live shared agenda during the call.",
            "Decisions logged into the event activity.",
            "Action items become tasks automatically.",
            "Optional cloud recording.",
            "Screen sharing for budgets and designs.",
            "End-to-end encrypted signalling.",
          ],
        },
        {
          title: "Replaces the chat-and-link spaghetti.",
          lead: "No more pasting Zoom links into WhatsApp at midnight. The committee opens the workspace, joins the room, gets things done.",
          bullets: [
            "One source of truth per event.",
            "Auto-archive after the event.",
            "Searchable meeting notes.",
            "Vendor briefings on the same surface.",
            "Family planning calls without a third-party tool.",
            "Works on the same phone you used to plan.",
          ],
        },
      ]}
      cta={{
        eyebrow: "Built-in meetings",
        title: "Stop juggling links. Start coordinating.",
        primary: { label: "Open a workspace", href: "/register" },
        secondary: { label: "See event groups", href: "/features/event-groups" },
      }}
    />
  );
};

export default Meetings;
