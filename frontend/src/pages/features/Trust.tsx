import EditorialFeaturePage from "@/components/features/EditorialFeaturePage";
import { useMeta } from "@/hooks/useMeta";

const Trust = () => {
  useMeta({
    title: "Trust & Payment Protection | Nuru",
    description:
      "Verified vendors. Protected deposits. Milestone-based release. Dispute resolution. The trust infrastructure that makes celebrations safe.",
  });

  return (
    <EditorialFeaturePage
      kicker="Service - 09 - Trust"
      title="Trust, engineered into every transaction."
      lead="A vendor takes money and disappears. A contribution goes missing. A booking is double-charged. Nuru is built so these stories stop. Every payment is secured, confirmed, reviewed and recorded."
      specs={[
        { label: "Identity", value: "ID + Biometric" },
        { label: "Deposits", value: "Held protected" },
        { label: "Release", value: "Milestone-based" },
        { label: "Disputes", value: "Mediated" },
      ]}
      sections={[
        {
          title: "Verified before you transact.",
          lead: "Every vendor is verified by national ID, business documents and biometric checks before the badge appears. Organisers see exactly who they're dealing with.",
          bullets: [
            "National ID / passport verification.",
            "Business registration (where applicable).",
            "Selfie + liveness check.",
            "Public verified badge on profile.",
            "Re-verification after appeals or flags.",
            "Visible track record per vendor.",
          ],
        },
        {
          title: "Payments that don't vanish.",
          lead: "Deposits sit in protected payments until the vendor delivers. Milestones release funds in stages · never lump-sum, never blind.",
          bullets: [
            "Deposit, milestone, final-settlement model.",
            "Released only on organiser confirmation.",
            "Auto-release windows after delivery.",
            "Refund flow when vendor cancels.",
            "Reconciled ledger updated daily.",
            "PCI-DSS aligned card processing.",
          ],
        },
        {
          title: "Disputes resolved, not buried.",
          lead: "When something goes wrong, both sides have a structured appeal flow with evidence, timelines and a Nuru reviewer. Decisions are recorded.",
          bullets: [
            "Structured appeal with evidence.",
            "Mediated by Nuru reviewers.",
            "Outcome recorded against vendor profile.",
            "Repeat-offender flagging.",
            "Refund and remediation paths.",
            "Transparent timeline visible to both sides.",
          ],
        },
      ]}
      cta={{
        eyebrow: "Trust & protection",
        title: "Audit-grade. End-to-end.",
        body: "The same trust standards apply whether you're paying TZS 50,000 or TZS 50,000,000.",
        primary: { label: "Open a workspace", href: "/register" },
        secondary: { label: "Vendor agreement", href: "/vendor-agreement" },
      }}
    />
  );
};

export default Trust;
