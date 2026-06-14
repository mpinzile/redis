/**
 * AdminPaymentsProviders — CRUD for payment providers per country.
 * Lists providers, lets admin create/edit/delete and toggle active/default.
 */
import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2, Power, Star, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { toast } from "sonner";
import { adminPaymentsApi } from "@/lib/api/adminPayments";
import { showApiErrors } from "@/lib/api/showApiErrors";
import type {
  PaymentProvider, UpsertProviderRequest, CountryCode, CurrencyCode, PaymentProviderType,
} from "@/lib/api/payments-types";

const COUNTRIES: { code: CountryCode; label: string; currency: CurrencyCode }[] = [
  { code: "TZ", label: "Tanzania", currency: "TZS" },
  { code: "KE", label: "Kenya", currency: "KES" },
];

const TYPES: PaymentProviderType[] = ["mobile_money", "bank", "card", "wallet"];

export default function AdminPaymentsProviders() {
  const qc = useQueryClient();
  const [country, setCountry] = useState<CountryCode>("TZ");
  const [editing, setEditing] = useState<PaymentProvider | null>(null);
  const [creating, setCreating] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ["admin-providers", country],
    queryFn: async () => {
      const res = await adminPaymentsApi.listProviders({ country_code: country });
      return res.success ? (Array.isArray(res.data) ? res.data : []) : [];
    },
  });

  const refresh = () => qc.invalidateQueries({ queryKey: ["admin-providers", country] });

  const onDelete = async (id: string) => {
    if (!confirm("Delete this provider? This cannot be undone.")) return;
    const res = await adminPaymentsApi.deleteProvider(id);
    if (res.success) { toast.success("Provider deleted"); refresh(); }
    else showApiErrors(res, "Failed to delete provider");
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <Select value={country} onValueChange={(v) => setCountry(v as CountryCode)}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            {COUNTRIES.map((c) => (
              <SelectItem key={c.code} value={c.code}>{c.label} - {c.currency}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button onClick={() => setCreating(true)} className="gap-2 ml-auto">
          <Plus className="w-4 h-4" /> Add provider
        </Button>
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-10 text-muted-foreground">
          <Loader2 className="w-5 h-5 animate-spin" />
        </div>
      ) : !data?.length ? (
        <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">
          No providers configured for {country}. Click <strong>Add provider</strong> to create one.
        </CardContent></Card>
      ) : (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {data.map((p) => (
            <Card key={p.id} className="relative">
              <CardContent className="p-4">
                <div className="flex items-start gap-3">
                  <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center text-xs font-bold text-primary uppercase">
                    {p.code.slice(0, 2)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="font-semibold text-foreground truncate">{p.name ?? p.display_name ?? p.code}</p>
                      {p.is_default && <Star className="w-3.5 h-3.5 text-amber-500 fill-amber-500" />}
                    </div>
                    <p className="text-[11px] text-muted-foreground uppercase tracking-wide">
                      {p.code} - {p.provider_type.replace("_", " ")}
                    </p>
                    <div className="flex flex-wrap gap-1.5 mt-2">
                      <Badge variant={p.is_active ? "default" : "secondary"} className="text-[10px]">
                        {p.is_active ? "Active" : "Inactive"}
                      </Badge>
                      {p.supports_collection && <Badge variant="outline" className="text-[10px]">Collect</Badge>}
                      {p.supports_payout && <Badge variant="outline" className="text-[10px]">Payout</Badge>}
                    </div>
                  </div>
                </div>
                <div className="flex gap-1.5 mt-3">
                  <Button size="sm" variant="outline" className="flex-1 gap-1.5" onClick={() => setEditing(p)}>
                    <Pencil className="w-3.5 h-3.5" /> Edit
                  </Button>
                  <Button
                    size="sm" variant="outline"
                    onClick={async () => {
                      const res = await adminPaymentsApi.updateProvider(p.id, { is_active: !p.is_active } as any);
                      if (res.success) { toast.success(p.is_active ? "Deactivated" : "Activated"); refresh(); }
                    }}
                    title={p.is_active ? "Deactivate" : "Activate"}
                  >
                    <Power className="w-3.5 h-3.5" />
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => onDelete(p.id)} className="text-destructive">
                    <Trash2 className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {(creating || editing) && (
        <ProviderFormDialog
          open
          country={country}
          provider={editing}
          onClose={() => { setCreating(false); setEditing(null); }}
          onSaved={() => { refresh(); setCreating(false); setEditing(null); }}
        />
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────

function ProviderFormDialog({
  open, country, provider, onClose, onSaved,
}: {
  open: boolean;
  country: CountryCode;
  provider: PaymentProvider | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const isEdit = !!provider;
  const currency = COUNTRIES.find((c) => c.code === country)?.currency ?? "TZS";

  const [form, setForm] = useState<UpsertProviderRequest>({
    code: provider?.code ?? "",
    name: provider?.name ?? provider?.display_name ?? "",
    provider_type: provider?.provider_type ?? "mobile_money",
    country_code: provider?.country_code ?? country,
    currency_code: provider?.currency_code ?? currency,
    logo_url: provider?.logo_url ?? null,
    is_active: provider?.is_active ?? true,
    is_collection_enabled: provider?.is_collection_enabled ?? provider?.supports_collection ?? true,
    is_payout_enabled: provider?.is_payout_enabled ?? provider?.supports_payout ?? true,
    min_amount: provider?.min_amount ?? null,
    max_amount: provider?.max_amount ?? null,
    display_order: provider?.display_order ?? 0,
  });
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!isEdit) setForm((f) => ({ ...f, country_code: country, currency_code: currency }));
  }, [country, currency, isEdit]);

  const save = async () => {
    if (!form.code || !form.name) {
      toast.error("Code and name are required");
      return;
    }
    setBusy(true);
    const res = isEdit
      ? await adminPaymentsApi.updateProvider(provider!.id, form)
      : await adminPaymentsApi.createProvider(form);
    setBusy(false);
    if (res.success) { toast.success(isEdit ? "Provider updated" : "Provider created"); onSaved(); }
    else showApiErrors(res, "Save failed");
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit provider" : "New provider"}</DialogTitle>
        </DialogHeader>
        <div className="grid gap-3 py-2">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Code">
              <Input value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} placeholder="mpesa_ke" />
            </Field>
            <Field label="Name">
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="M-Pesa" />
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Type">
              <Select value={form.provider_type} onValueChange={(v) => setForm({ ...form, provider_type: v as PaymentProviderType })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {TYPES.map((t) => <SelectItem key={t} value={t}>{t.replace("_", " ")}</SelectItem>)}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Display order">
              <Input
                type="number"
                value={form.display_order ?? 0}
                onChange={(e) => setForm({ ...form, display_order: Number(e.target.value) })}
              />
            </Field>
          </div>
          <Field label="Logo URL (optional)">
            <Input value={form.logo_url ?? ""} onChange={(e) => setForm({ ...form, logo_url: e.target.value || null })} />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Min amount">
              <Input type="number" value={form.min_amount ?? ""} onChange={(e) => setForm({ ...form, min_amount: e.target.value ? Number(e.target.value) : null })} />
            </Field>
            <Field label="Max amount">
              <Input type="number" value={form.max_amount ?? ""} onChange={(e) => setForm({ ...form, max_amount: e.target.value ? Number(e.target.value) : null })} />
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-3 pt-1">
            <Toggle label="Active" checked={!!form.is_active} onChange={(v) => setForm({ ...form, is_active: v })} />
            <Toggle label="Collection enabled" checked={!!form.is_collection_enabled} onChange={(v) => setForm({ ...form, is_collection_enabled: v })} />
            <Toggle label="Payout enabled" checked={!!form.is_payout_enabled} onChange={(v) => setForm({ ...form, is_payout_enabled: v })} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>Cancel</Button>
          <Button onClick={save} disabled={busy}>{busy ? "Saving..." : isEdit ? "Save" : "Create"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

const Field = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <div className="space-y-1.5">
    <Label className="text-xs font-medium">{label}</Label>
    {children}
  </div>
);

const Toggle = ({ label, checked, onChange }: { label: string; checked: boolean; onChange: (v: boolean) => void }) => (
  <label className="flex items-center justify-between gap-2 rounded-lg border border-border p-2.5 cursor-pointer">
    <span className="text-xs font-medium">{label}</span>
    <Switch checked={checked} onCheckedChange={onChange} />
  </label>
);
