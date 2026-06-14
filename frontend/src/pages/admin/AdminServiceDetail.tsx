import { useEffect, useState, useCallback } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { ChevronLeft, Star, Package, Image as ImageIcon, ShieldCheck, Ban, CheckCircle, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { adminApi } from "@/lib/api/admin";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

const statusBadge = (s: string) => {
  if (s === "pending") return "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400";
  if (s === "verified") return "bg-primary/10 text-primary";
  if (s === "rejected") return "bg-destructive/10 text-destructive";
  return "bg-muted text-muted-foreground";
};

const kycStatusBadge = (s: string) => {
  if (s === "pending") return "bg-amber-100 text-amber-700";
  if (s === "verified") return "bg-green-100 text-green-700";
  if (s === "rejected") return "bg-red-100 text-red-700";
  return "bg-muted text-muted-foreground";
};

const VERIFICATION_STATUSES = ["pending", "verified", "rejected"];

export default function AdminServiceDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { confirm, ConfirmDialog } = useConfirmDialog();
  const [service, setService] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [newVerificationStatus, setNewVerificationStatus] = useState("");
  const [updatingStatus, setUpdatingStatus] = useState(false);

  useAdminMeta(service?.title ? `Service - ${service.title}` : "Service Detail");

  const load = useCallback(async () => {
    if (!id) return;
    const res = await adminApi.getServiceDetail(id);
    if (res.success) {
      setService(res.data);
      setNewVerificationStatus(res.data?.verification_status || "pending");
    } else toast.error("Failed to load service details");
    setLoading(false);
  }, [id]);

  useEffect(() => { load(); }, [load]);

  const handleToggleActive = async () => {
    if (!service) return;
    const ok = await confirm({
      title: service.is_active ? "Suspend Service?" : "Activate Service?",
      description: `${service.is_active ? "Suspend" : "Activate"} service "${service.title}"?`,
      confirmLabel: service.is_active ? "Suspend" : "Activate",
      destructive: service.is_active,
    });
    if (!ok) return;
    const res = await adminApi.toggleServiceActive(id!, !service.is_active);
    if (res.success) { toast.success(service.is_active ? "Service suspended" : "Service activated"); load(); }
    else toast.error(res.message || "Failed");
  };

  const handleStatusUpdate = async () => {
    if (!newVerificationStatus || !id) return;
    setUpdatingStatus(true);
    const res = await adminApi.updateServiceVerificationStatus(id, newVerificationStatus);
    if (res.success) { toast.success("Verification status updated"); load(); }
    else toast.error(res.message || "Failed");
    setUpdatingStatus(false);
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-32 w-full rounded-xl" />
        <div className="grid grid-cols-3 gap-4"><Skeleton className="h-24 rounded-xl" /><Skeleton className="h-24 rounded-xl" /><Skeleton className="h-24 rounded-xl" /></div>
      </div>
    );
  }

  if (!service) {
    return (
      <div className="text-center py-20 text-muted-foreground">
        <p>Service not found.</p>
        <Button variant="outline" className="mt-4" onClick={() => navigate("/admin/services")}>Back to Services</Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <ConfirmDialog />

      {/* Header */}
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="sm" onClick={() => navigate("/admin/services")}>
          <ChevronLeft className="w-4 h-4 mr-1" /> Services
        </Button>
        <div className="flex-1" />
        <span className={cn("text-xs px-2.5 py-1 rounded-full font-medium capitalize", statusBadge(service.verification_status))}>
          {service.verification_status}
        </span>
        <span className={cn("text-xs px-2.5 py-1 rounded-full font-medium", service.is_active ? "bg-primary/10 text-primary" : "bg-muted text-muted-foreground")}>
          {service.is_active ? "Active" : "Suspended"}
        </span>
      </div>

      {/* Provider Info */}
      <div className="bg-card border border-border rounded-xl p-5">
        <div className="flex items-center gap-4">
          {service.user?.avatar ? (
            <img src={service.user.avatar} alt={service.user.name} className="w-12 h-12 rounded-full object-cover shrink-0" />
          ) : (
            <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center text-lg font-bold text-primary shrink-0">
              {service.user?.name?.[0] || "?"}
            </div>
          )}
          <div className="flex-1">
            <h1 className="text-xl font-bold text-foreground">{service.title}</h1>
            <p className="text-sm text-muted-foreground">
              by <span className="font-medium text-foreground">{service.user?.name}</span>
              {service.user?.email && <span className="ml-1 text-muted-foreground">· {service.user.email}</span>}
              {service.user?.phone && <span className="ml-1 text-muted-foreground">· {service.user.phone}</span>}
            </p>
            <p className="text-xs text-muted-foreground mt-0.5">{service.category}{service.service_type ? ` / ${service.service_type}` : ""}{service.location ? ` - ${service.location}` : ""}</p>
          </div>
        </div>
        {service.description && (
          <p className="text-sm text-muted-foreground mt-4 leading-relaxed">{service.description}</p>
        )}
      </div>

      {/* Meta grid */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        {(service.min_price || service.max_price) && (
          <div className="bg-card border border-border rounded-xl p-4">
            <p className="text-xs text-muted-foreground mb-1">Price Range (TZS)</p>
            <p className="font-semibold text-foreground text-sm">
              {service.min_price ? Number(service.min_price).toLocaleString() : "—"}
              {service.max_price ? ` – ${Number(service.max_price).toLocaleString()}` : ""}
            </p>
          </div>
        )}
        <div className="bg-card border border-border rounded-xl p-4">
          <p className="text-xs text-muted-foreground mb-1">Rating</p>
          <p className="font-semibold text-foreground text-sm flex items-center gap-1">
            <Star className="w-3.5 h-3.5 text-primary" />
            {service.average_rating ?? "—"} <span className="text-xs font-normal text-muted-foreground">({service.total_ratings ?? 0})</span>
          </p>
        </div>
        <div className="bg-card border border-border rounded-xl p-4">
          <p className="text-xs text-muted-foreground mb-1">Availability</p>
          <p className="font-semibold text-foreground text-sm capitalize">{service.availability || "—"}</p>
        </div>
        <div className="bg-card border border-border rounded-xl p-4">
          <p className="text-xs text-muted-foreground mb-1">Created</p>
          <p className="font-semibold text-foreground text-sm">{service.created_at ? new Date(service.created_at).toLocaleDateString() : "—"}</p>
        </div>
      </div>

      {/* Manage Status */}
      <div className="bg-card border border-border rounded-xl p-5">
        <h2 className="font-semibold text-foreground mb-4 flex items-center gap-2"><ShieldCheck className="w-4 h-4" /> Manage Service</h2>
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="flex-1 space-y-2">
            <p className="text-sm font-medium text-foreground">Verification Status</p>
            <Select value={newVerificationStatus} onValueChange={setNewVerificationStatus}>
              <SelectTrigger>
                <SelectValue placeholder="Select status" />
              </SelectTrigger>
              <SelectContent>
                {VERIFICATION_STATUSES.map(s => (
                  <SelectItem key={s} value={s} className="capitalize">{s}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button onClick={handleStatusUpdate} disabled={updatingStatus || newVerificationStatus === service.verification_status} size="sm">
              {updatingStatus ? "Updating..." : "Update Verification Status"}
            </Button>
          </div>
          <div className="flex-1 space-y-2">
            <p className="text-sm font-medium text-foreground">Active Status</p>
            <p className="text-xs text-muted-foreground">
              Currently: <span className={cn("font-medium", service.is_active ? "text-primary" : "text-destructive")}>
                {service.is_active ? "Active" : "Suspended"}
              </span>
            </p>
            <Button
              size="sm"
              variant={service.is_active ? "destructive" : "default"}
              onClick={handleToggleActive}
            >
              {service.is_active ? <><Ban className="w-3.5 h-3.5 mr-1.5" /> Suspend Service</> : <><CheckCircle className="w-3.5 h-3.5 mr-1.5" /> Activate Service</>}
            </Button>
          </div>
        </div>
      </div>

      {/* Images */}
      {service.images?.length > 0 && (
        <div className="bg-card border border-border rounded-xl p-5">
          <h2 className="font-semibold text-foreground mb-4 flex items-center gap-2"><ImageIcon className="w-4 h-4" /> Images ({service.images.length})</h2>
          <div className="flex gap-2 flex-wrap">
            {service.images.map((img: any) => (
              <a key={img.id} href={img.url} target="_blank" rel="noopener noreferrer">
                <img src={img.url} alt="Service" className="w-24 h-20 rounded-lg object-cover border border-border hover:opacity-80 transition-opacity" />
              </a>
            ))}
          </div>
        </div>
      )}

      {/* Packages */}
      {service.packages?.length > 0 && (
        <div className="bg-card border border-border rounded-xl p-5">
          <h2 className="font-semibold text-foreground mb-4 flex items-center gap-2"><Package className="w-4 h-4" /> Packages ({service.packages.length})</h2>
          <div className="space-y-2">
            {service.packages.map((pkg: any) => (
              <div key={pkg.id} className="border border-border rounded-lg p-4">
                <div className="flex justify-between items-start">
                  <p className="font-medium text-foreground">{pkg.name}</p>
                  <p className="font-semibold text-primary text-sm">{pkg.price ? `TZS ${Number(pkg.price).toLocaleString()}` : "—"}</p>
                </div>
                {pkg.description && <p className="text-xs text-muted-foreground mt-1">{pkg.description}</p>}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Verification */}
      {service.verification && (
        <div className="bg-card border border-border rounded-xl p-5">
          <h2 className="font-semibold text-foreground mb-4 flex items-center gap-2"><ShieldCheck className="w-4 h-4" /> KYC Status</h2>
          <div className="space-y-2">
            {(service.verification.kyc_items || []).map((k: any) => (
              <div key={k.id} className="flex items-center justify-between bg-muted/40 rounded-lg px-4 py-2.5">
                <span className="text-sm text-foreground">{k.name || "KYC Item"}</span>
                <span className={cn("text-xs px-2 py-0.5 rounded-full font-medium capitalize", kycStatusBadge(k.status))}>{k.status}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
