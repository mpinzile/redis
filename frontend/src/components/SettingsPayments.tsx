import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Plus,
  Smartphone,
  Building2,
  Star,
  Trash2,
  Loader2,
  MapPin,
  ChevronLeft,
} from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api";
import { showApiErrors } from "@/lib/api/showApiErrors";
import { useCurrentUser } from "@/hooks/useCurrentUser";
import { useCurrency } from "@/hooks/useCurrency";
import { useWorkspaceMeta } from "@/hooks/useWorkspaceMeta";
import { PaymentSetupModal } from "@/components/payments/PaymentSetupModal";
import { SUPPORTED_REGIONS, RegionCode, PrimaryRegionCode } from "@/lib/region/config";
import type { PaymentProfile } from "@/lib/api/payments-types";

/**
 * Settings → Payments page.
 *
 * Lets the user:
 *  • Switch their country/currency (re-runs `confirmCountry`).
 *  • Manage payout profiles (mobile money + bank).
 */
const SettingsPayments = () => {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { data: user, refetch } = useCurrentUser();
  const { currency, countryCode } = useCurrency();

  useWorkspaceMeta({
    title: "Payments",
    description: "Manage your country, currency, and payout methods.",
  });

  const [editing, setEditing] = useState<PaymentProfile | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [savingCountry, setSavingCountry] = useState<RegionCode | null>(null);

  const profilesQuery = useQuery({
    queryKey: ["payment-profiles"],
    queryFn: async () => {
      const res = await api.paymentProfiles.list();
      // Backend returns `data` as a flat array — not `{ profiles: [...] }`.
      return res.success ? (Array.isArray(res.data) ? res.data : []) : [];
    },
  });

  // Centralised refresh — invalidates BOTH the list and the
  // "required-status" gate so dependent screens (wallet/payouts) update too.
  const refreshProfiles = () => {
    queryClient.invalidateQueries({ queryKey: ["payment-profiles"] });
    queryClient.invalidateQueries({ queryKey: ["payment-profiles", "required-status"] });
    profilesQuery.refetch();
  };

  const handleCountryChange = async (code: PrimaryRegionCode) => {
    if (code === countryCode) return;
    setSavingCountry(code);
    try {
      const res = await api.profile.confirmCountry({ country_code: code, source: "manual" });
      if (!res.success) {
        showApiErrors(res, "Failed to update country");
        return;
      }
      const region = SUPPORTED_REGIONS.find((r) => r.code === code);
      toast.success(`Switched to ${region?.name ?? code}`);
      await Promise.all([refetch(), queryClient.invalidateQueries({ queryKey: ["wallets"] })]);
    } finally {
      setSavingCountry(null);
    }
  };

  const handleEdit = (profile: PaymentProfile) => {
    setEditing(profile);
    setModalOpen(true);
  };

  const handleAdd = () => {
    setEditing(null);
    setModalOpen(true);
  };

  const handleSetDefault = async (profile: PaymentProfile) => {
    const res = await api.paymentProfiles.setDefault(profile.id);
    if (!res.success) {
      showApiErrors(res, "Failed to set default");
      return;
    }
    toast.success("Default payout updated");
    refreshProfiles();
  };

  const handleDelete = async (profile: PaymentProfile) => {
    if (!confirm(`Remove ${profile.account_holder_name}?`)) return;
    const res = await api.paymentProfiles.remove(profile.id);
    if (!res.success) {
      showApiErrors(res, "Failed to delete");
      return;
    }
    toast.success("Payout method removed");
    refreshProfiles();
  };

  return (
    <div className="space-y-6 pb-12">
      <div className="flex items-center gap-2">
        <div className="flex-1 min-w-0">
          <h1 className="text-xl md:text-2xl font-semibold">Payments</h1>
          <p className="text-sm text-muted-foreground">Country, currency, and where you receive money.</p>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="flex-shrink-0 self-center"
          onClick={() => navigate(-1)}
          aria-label="Back"
        >
          <ChevronLeft className="w-5 h-5" />
        </Button>
      </div>

      {/* Country & currency */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <MapPin className="h-4 w-4 text-primary" /> Country & currency
          </CardTitle>
          <CardDescription>
            Your wallet is currently held in <strong>{currency}</strong>.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid sm:grid-cols-2 gap-3">
          {SUPPORTED_REGIONS.map((region) => {
            const active = (user?.country_code ?? countryCode) === region.code;
            const isSaving = savingCountry === region.code;
            const ccy = region.code === "TZ" ? "TZS" : "KES";
            return (
              <button
                key={region.code}
                type="button"
                disabled={isSaving}
                onClick={() => handleCountryChange(region.code as PrimaryRegionCode)}
                className={`text-left rounded-xl border p-4 transition-all disabled:opacity-60 ${active ? "border-primary bg-primary/5 ring-2 ring-primary/20" : "border-border hover:border-primary/40 hover:bg-muted/40"}`}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <span className="text-2xl leading-none">{region.flag}</span>
                    <div>
                      <p className="font-medium text-foreground">{region.name}</p>
                      <p className="text-xs text-muted-foreground">Wallet - {ccy}</p>
                    </div>
                  </div>
                  {isSaving ? (
                    <Loader2 className="h-4 w-4 animate-spin text-primary" />
                  ) : (
                    <div className={`h-4 w-4 rounded-full border-2 ${active ? "border-primary bg-primary" : "border-muted-foreground/40"}`} />
                  )}
                </div>
              </button>
            );
          })}
        </CardContent>
      </Card>

      {/* Payout methods */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0">
          <div>
            <CardTitle className="text-base">Payout methods</CardTitle>
            <CardDescription>Where we send your earnings and refunds.</CardDescription>
          </div>
          <Button size="sm" onClick={handleAdd}>
            <Plus className="h-4 w-4 mr-1" /> Add
          </Button>
        </CardHeader>
        <CardContent className="space-y-3">
          {profilesQuery.isLoading ? (
            <>
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </>
          ) : profilesQuery.data && profilesQuery.data.length > 0 ? (
            profilesQuery.data.map((profile) => (
              <ProfileRow
                key={profile.id}
                profile={profile}
                onEdit={() => handleEdit(profile)}
                onSetDefault={() => handleSetDefault(profile)}
                onDelete={() => handleDelete(profile)}
              />
            ))
          ) : (
            <div className="rounded-lg border border-dashed border-border p-6 text-center">
              <p className="text-sm text-muted-foreground">No payout methods yet.</p>
              <Button onClick={handleAdd} variant="outline" size="sm" className="mt-3">
                <Plus className="h-4 w-4 mr-1" /> Add your first method
              </Button>
            </div>
          )}
        </CardContent>
      </Card>

      <PaymentSetupModal
        open={modalOpen}
        onOpenChange={setModalOpen}
        profile={editing}
        onSaved={refreshProfiles}
      />
    </div>
  );
};

const ProfileRow = ({
  profile,
  onEdit,
  onSetDefault,
  onDelete,
}: {
  profile: PaymentProfile;
  onEdit: () => void;
  onSetDefault: () => void;
  onDelete: () => void;
}) => {
  const Icon = profile.method_type === "mobile_money" ? Smartphone : Building2;
  return (
    <div className="flex items-center justify-between rounded-lg border border-border p-3 hover:bg-muted/30 transition-colors">
      <div className="flex items-center gap-3 min-w-0">
        <div className="h-10 w-10 rounded-lg bg-primary/10 text-primary flex items-center justify-center">
          <Icon className="h-5 w-5" />
        </div>
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <p className="text-sm font-medium text-foreground truncate">{profile.account_holder_name}</p>
            {profile.is_default && (
              <Badge variant="secondary" className="text-[10px] px-1.5 py-0">Default</Badge>
            )}
            {profile.is_verified && (
              <Badge className="bg-green-500/15 text-green-700 border-0 text-[10px] px-1.5 py-0">Verified</Badge>
            )}
          </div>
          <p className="text-xs text-muted-foreground truncate">
            {(profile.method_type === "mobile_money"
              ? profile.network_name
              : profile.bank_name) ?? profile.method_type.replace("_", " ")}
            {" - "}
            {profile.method_type === "mobile_money"
              ? profile.phone_number
              : profile.account_number}
          </p>
        </div>
      </div>
      <div className="flex items-center gap-1 shrink-0">
        {!profile.is_default && (
          <Button variant="ghost" size="icon" onClick={onSetDefault} title="Set as default">
            <Star className="h-4 w-4" />
          </Button>
        )}
        <Button variant="ghost" size="sm" onClick={onEdit}>Edit</Button>
        <Button variant="ghost" size="icon" onClick={onDelete} title="Remove">
          <Trash2 className="h-4 w-4 text-destructive" />
        </Button>
      </div>
    </div>
  );
};

export default SettingsPayments;
