import { useEffect, useState, useCallback, useRef } from "react";
import { Shield, Plus, Trash2, RefreshCw, Eye, EyeOff, Loader2, UserCog } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { AdminTableSkeleton } from "@/components/ui/AdminTableSkeleton";
import { adminApi } from "@/lib/api/admin";
import { adminCaches } from "@/lib/api/adminCache";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";
import { usePolling } from "@/hooks/usePolling";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

const ROLES = ["admin", "moderator", "support"];

const roleBadge = (role: string) => {
  if (role === "admin") return "bg-destructive/10 text-destructive";
  if (role === "moderator") return "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400";
  return "bg-primary/10 text-primary";
};

export default function AdminAdmins() {
  useAdminMeta("Admin Accounts");
  const cache = adminCaches.admins;
  const [admins, setAdmins] = useState<any[]>(cache.data);
  const [loading, setLoading] = useState(!cache.loaded);
  const initialLoad = useRef(!cache.loaded);
  const [createOpen, setCreateOpen] = useState(false);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  const [form, setForm] = useState({ full_name: "", email: "", username: "", password: "", role: "support" });
  const [creating, setCreating] = useState(false);
  const { confirm, ConfirmDialog } = useConfirmDialog();

  const load = useCallback(async () => {
    if (initialLoad.current) setLoading(true);
    const res = await adminApi.getAdmins();
    if (res.success) {
      const data = Array.isArray(res.data) ? res.data : [];
      cache.set(data);
      setAdmins(data);
    } else if (initialLoad.current) toast.error("Failed to load admin accounts");
    setLoading(false);
    initialLoad.current = false;
  }, []);

  useEffect(() => {
    if (!cache.loaded) initialLoad.current = true;
    load();
  }, [load]);
  usePolling(load);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.full_name.trim() || !form.email.trim() || !form.username.trim() || !form.password) {
      toast.error("All fields are required"); return;
    }
    if (form.password.length < 8) { toast.error("Password must be at least 8 characters"); return; }
    setCreating(true);
    const res = await adminApi.createAdmin(form);
    if (res.success) {
      toast.success("Admin account created");
      setCreateOpen(false);
      setForm({ full_name: "", email: "", username: "", password: "", role: "support" });
      load();
    } else toast.error(res.message || "Failed to create admin");
    setCreating(false);
  };

  const handleToggleActive = async (id: string, isActive: boolean, name: string) => {
    const ok = await confirm({
      title: isActive ? "Deactivate Admin?" : "Activate Admin?",
      description: `${isActive ? "Deactivate" : "Activate"} admin account for ${name}?`,
      confirmLabel: isActive ? "Deactivate" : "Activate",
      destructive: isActive,
    });
    if (!ok) return;
    setActionLoading(id);
    const res = isActive ? await adminApi.deactivateAdmin(id) : await adminApi.activateAdmin(id);
    if (res.success) { toast.success(isActive ? "Admin deactivated" : "Admin activated"); load(); }
    else toast.error(res.message || "Action failed");
    setActionLoading(null);
  };

  const handleDelete = async (id: string, name: string) => {
    const ok = await confirm({
      title: "Delete Admin Account?",
      description: `Permanently delete admin account for "${name}"? This action cannot be undone.`,
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    setActionLoading(id);
    const res = await adminApi.deleteAdmin(id);
    if (res.success) { toast.success("Admin account deleted"); load(); }
    else toast.error(res.message || "Failed to delete admin");
    setActionLoading(null);
  };

  // Get current admin's id to prevent self-deletion
  const currentAdminId = (() => {
    try { const s = localStorage.getItem("admin_user"); return s ? JSON.parse(s).id : null; } catch { return null; }
  })();

  return (
    <div className="space-y-6">
      <ConfirmDialog />

      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-foreground">Admin Accounts</h2>
          <p className="text-sm text-muted-foreground mt-0.5">Create and manage Nuru admin panel users</p>
        </div>
        <Button onClick={() => setCreateOpen(true)}>
          <Plus className="w-4 h-4 mr-1.5" /> New Admin
        </Button>
      </div>

      {loading ? (
        <AdminTableSkeleton columns={5} rows={6} />
      ) : admins.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <UserCog className="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p>No admin accounts found</p>
        </div>
      ) : (
        <div className="bg-card border border-border rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-muted/50">
              <tr>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Admin</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Username</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Role</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Status</th>
                <th className="text-left px-4 py-3 font-medium text-muted-foreground">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {admins.map((a) => {
                const isSelf = a.id === currentAdminId;
                return (
                  <tr key={a.id} className="hover:bg-muted/30 transition-colors">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2.5">
                        <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center text-xs font-semibold text-primary shrink-0">
                          {a.full_name?.[0]?.toUpperCase() || "A"}
                        </div>
                        <div>
                          <div className="font-medium text-foreground">{a.full_name} {isSelf && <span className="text-xs text-muted-foreground">(you)</span>}</div>
                          <div className="text-xs text-muted-foreground">{a.email}</div>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-muted-foreground">@{a.username}</td>
                    <td className="px-4 py-3">
                      <span className={cn("text-xs px-2 py-0.5 rounded-full font-medium capitalize", roleBadge(a.role))}>
                        {a.role}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <span className={cn("text-xs px-2 py-0.5 rounded-full font-medium", a.is_active ? "bg-primary/10 text-primary" : "bg-destructive/10 text-destructive")}>
                        {a.is_active ? "Active" : "Inactive"}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-1">
                        {!isSelf && (
                          <>
                            <Button variant="ghost" size="sm"
                              className={a.is_active ? "text-destructive hover:bg-destructive/10" : "text-primary"}
                              onClick={() => handleToggleActive(a.id, a.is_active, a.full_name)}
                              disabled={actionLoading === a.id}>
                              {actionLoading === a.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : (a.is_active ? "Deactivate" : "Activate")}
                            </Button>
                            <Button variant="ghost" size="sm" className="text-destructive hover:bg-destructive/10"
                              onClick={() => handleDelete(a.id, a.full_name)}
                              disabled={actionLoading === a.id}>
                              <Trash2 className="w-3.5 h-3.5" />
                            </Button>
                          </>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Create Admin Dialog */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Shield className="w-5 h-5 text-primary" /> Create Admin Account
            </DialogTitle>
          </DialogHeader>
          <form onSubmit={handleCreate} className="space-y-4">
            <div className="space-y-1.5">
              <Label>Full Name *</Label>
              <Input value={form.full_name} onChange={(e) => setForm(f => ({ ...f, full_name: e.target.value }))} placeholder="e.g. Jane Doe" />
            </div>
            <div className="space-y-1.5">
              <Label>Email *</Label>
              <Input type="email" value={form.email} onChange={(e) => setForm(f => ({ ...f, email: e.target.value }))} placeholder="admin@nuru.tz" />
            </div>
            <div className="space-y-1.5">
              <Label>Username *</Label>
              <Input value={form.username} onChange={(e) => setForm(f => ({ ...f, username: e.target.value.toLowerCase().replace(/\s+/g, "") }))} placeholder="janedoe" />
            </div>
            <div className="space-y-1.5">
              <Label>Password *</Label>
              <div className="relative">
                <Input type={showPassword ? "text" : "password"} value={form.password} onChange={(e) => setForm(f => ({ ...f, password: e.target.value }))} placeholder="Min. 8 characters" className="pr-10" />
                <button type="button" className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground" onClick={() => setShowPassword(v => !v)}>
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Role *</Label>
              <Select value={form.role} onValueChange={(v) => setForm(f => ({ ...f, role: v }))}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {ROLES.map((r) => (
                    <SelectItem key={r} value={r}>
                      <span className="capitalize">{r}</span>
                      {r === "admin" && " - Full access"}
                      {r === "moderator" && " - Content moderation"}
                      {r === "support" && " - Customer support"}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="bg-muted/50 border border-border rounded-lg p-3 text-xs text-muted-foreground">
              <strong className="text-foreground">Role permissions:</strong>
              <ul className="mt-1 space-y-0.5 list-disc list-inside">
                <li><strong>Admin</strong> — Full platform access, can manage other admins</li>
                <li><strong>Moderator</strong> — Content & KYC management</li>
                <li><strong>Support</strong> — Tickets, live chats, user management</li>
              </ul>
            </div>
            <DialogFooter>
              <Button variant="outline" type="button" onClick={() => setCreateOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={creating}>
                {creating ? <Loader2 className="w-4 h-4 animate-spin mr-1.5" /> : <Plus className="w-4 h-4 mr-1.5" />}
                Create Admin
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
