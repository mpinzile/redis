/**
 * AdminPayments — top-level Finance Operations Center.
 *
 * Two stacked navigations:
 *   1. Operations sub-nav (Overview - Ledger - Settlements - Reconciliation - Reports)
 *      — the new enterprise dashboard. State-driven (no router changes needed).
 *   2. Configuration sub-nav (Providers - Commissions - Transactions [legacy])
 *      — kept for finance settings.
 */
import { useState } from "react";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { cn } from "@/lib/utils";
import {
  LayoutDashboard, BookOpen, Banknote, GitCompareArrows, FileBarChart,
  Wallet, Receipt, Percent,
} from "lucide-react";

import AdminPaymentsOverview from "./payments/AdminPaymentsOverview";
import AdminPaymentsLedger from "./payments/AdminPaymentsLedger";
import AdminPaymentsSettlements from "./payments/AdminPaymentsSettlements";
import AdminPaymentsReconciliation from "./payments/AdminPaymentsReconciliation";
import AdminPaymentsReports from "./payments/AdminPaymentsReports";

import AdminPaymentsProviders from "./payments/AdminPaymentsProviders";
import AdminPaymentsCommissions from "./payments/AdminPaymentsCommissions";
import AdminPaymentsTransactions from "./payments/AdminPaymentsTransactions";

type OpsTab =
  | "overview" | "ledger" | "settlements" | "reconciliation" | "reports"
  | "providers" | "commissions" | "transactions";

const OPS_TABS: { key: OpsTab; label: string; icon: any; group: "ops" | "config" }[] = [
  { key: "overview",       label: "Overview",       icon: LayoutDashboard,  group: "ops" },
  { key: "ledger",         label: "Ledger",         icon: BookOpen,         group: "ops" },
  { key: "settlements",    label: "Settlements",    icon: Banknote,         group: "ops" },
  { key: "reconciliation", label: "Reconciliation", icon: GitCompareArrows, group: "ops" },
  { key: "reports",        label: "Reports",        icon: FileBarChart,     group: "ops" },
  { key: "providers",      label: "Providers",      icon: Wallet,           group: "config" },
  { key: "commissions",    label: "Commissions",    icon: Percent,          group: "config" },
  { key: "transactions",   label: "Transactions",   icon: Receipt,          group: "config" },
];

export default function AdminPayments() {
  useAdminMeta("Payments");
  const [tab, setTab] = useState<OpsTab>("overview");

  const opsTabs = OPS_TABS.filter((t) => t.group === "ops");
  const configTabs = OPS_TABS.filter((t) => t.group === "config");

  return (
    <div className="space-y-5">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-foreground">Finance Operations</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Treasury controls — payments in, settlements out, commissions, reconciliation.
          </p>
        </div>
      </div>

      {/* Sub-nav — operations row */}
      <div className="border-b border-border">
        <div className="flex items-center gap-1 overflow-x-auto pb-px">
          {opsTabs.map((t) => (
            <NavPill key={t.key} active={tab === t.key} onClick={() => setTab(t.key)} icon={t.icon}>
              {t.label}
            </NavPill>
          ))}
          <span className="mx-2 h-5 w-px bg-border" />
          {configTabs.map((t) => (
            <NavPill key={t.key} active={tab === t.key} onClick={() => setTab(t.key)} icon={t.icon} subtle>
              {t.label}
            </NavPill>
          ))}
        </div>
      </div>

      <div>
        {tab === "overview" && <AdminPaymentsOverview />}
        {tab === "ledger" && <AdminPaymentsLedger />}
        {tab === "settlements" && <AdminPaymentsSettlements />}
        {tab === "reconciliation" && <AdminPaymentsReconciliation />}
        {tab === "reports" && <AdminPaymentsReports />}
        {tab === "providers" && <AdminPaymentsProviders />}
        {tab === "commissions" && <AdminPaymentsCommissions />}
        {tab === "transactions" && <AdminPaymentsTransactions />}
      </div>
    </div>
  );
}

function NavPill({
  active, onClick, icon: Icon, subtle, children,
}: {
  active: boolean;
  onClick: () => void;
  icon: any;
  subtle?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "inline-flex items-center gap-1.5 px-3 py-2 text-xs font-medium rounded-t-md border-b-2 transition-colors whitespace-nowrap",
        active
          ? "border-primary text-foreground bg-muted/40"
          : subtle
            ? "border-transparent text-muted-foreground/70 hover:text-foreground hover:bg-muted/30"
            : "border-transparent text-muted-foreground hover:text-foreground hover:bg-muted/30"
      )}
    >
      <Icon className="w-3.5 h-3.5" />
      {children}
    </button>
  );
}
