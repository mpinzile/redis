import { useEffect, useMemo, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  ShieldCheck, Copy, RefreshCw, Trash2, UserPlus, Search,
  Loader2, X, AlertTriangle, ScanLine, Users, Eye, EyeOff, Lock,
} from "lucide-react";
import SvgIcon from "@/components/ui/svg-icon";
import KeySquareIcon from "@/assets/icons/key-square-icon.svg";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import { toast } from "sonner";
import { checkinTeamApi, CheckinTeamMember, CheckinCode } from "@/lib/api/checkinTeam";
import { useUserSearch } from "@/hooks/useUserSearch";

interface Props {
  eventId: string;
  canManage: boolean;
}

const initials = (name?: string) =>
  (name || "?").split(" ").map((w) => w[0]).join("").toUpperCase().slice(0, 2);

const CheckinTeam = ({ eventId, canManage: canManageProp }: Props) => {
  const [members, setMembers] = useState<CheckinTeamMember[]>([]);
  const [code, setCode] = useState<CheckinCode | null>(null);
  const [serverCanManage, setServerCanManage] = useState<boolean | null>(null);
  const [serverCanScan, setServerCanScan] = useState<boolean>(false);
  const [loading, setLoading] = useState(true);
  const [busyCode, setBusyCode] = useState<"generate" | "revoke" | null>(null);

  // Server is the source of truth; fall back to the prop until the first
  // /checkin-team response arrives so the UI doesn't briefly hide actions.
  const canManage = serverCanManage ?? canManageProp;

  const [addOpen, setAddOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [adding, setAdding] = useState<string | null>(null);
  const { results, loading: searchLoading, search, clear } = useUserSearch();

  const [revealedCode, setRevealedCode] = useState<string | null>(null);
  const [revealOpen, setRevealOpen] = useState(false);
  const [revealJustGenerated, setRevealJustGenerated] = useState(false);

  const [passwordOpen, setPasswordOpen] = useState(false);
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [revealing, setRevealing] = useState(false);

  const [confirmRevoke, setConfirmRevoke] = useState(false);
  const [confirmRemove, setConfirmRemove] = useState<CheckinTeamMember | null>(null);

  const memberUserIds = useMemo(() => new Set(members.map((m) => m.user.id)), [members]);

  const refresh = async () => {
    setLoading(true);
    try {
      const res = await checkinTeamApi.list(eventId);
      if (res.success && res.data) {
        setMembers(Array.isArray(res.data.members) ? res.data.members : []);
        setCode(res.data.code || null);
        if (res.data.permissions) {
          setServerCanManage(!!res.data.permissions.can_manage);
          setServerCanScan(!!res.data.permissions.can_scan);
        }
      }
    } catch {
      // silent
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void refresh(); }, [eventId]);
  useEffect(() => { search(query); }, [query, search]);

  const handleGenerate = async () => {
    setBusyCode("generate");
    try {
      const res = await checkinTeamApi.generateCode(eventId);
      if (res.success && res.data?.code) {
        setRevealedCode(res.data.code);
        setRevealJustGenerated(true);
        setRevealOpen(true);
        await refresh();
      } else {
        toast.error(res.message || "Could not generate code");
      }
    } finally {
      setBusyCode(null);
    }
  };

  const handleRevoke = async () => {
    setBusyCode("revoke");
    try {
      const res = await checkinTeamApi.revokeCode(eventId);
      if (res.success) {
        toast.success("Access code revoked. Active scanners have been logged out.");
        await refresh();
      } else {
        toast.error(res.message || "Could not revoke code");
      }
    } finally {
      setBusyCode(null);
      setConfirmRevoke(false);
    }
  };

  const handleReveal = async () => {
    if (!password.trim()) {
      toast.error("Enter your password to view the code");
      return;
    }
    setRevealing(true);
    try {
      const res = await checkinTeamApi.revealCode(eventId, password);
      if (res.success && res.data?.code) {
        setRevealedCode(res.data.code);
        setRevealJustGenerated(false);
        setPasswordOpen(false);
        setPassword("");
        setShowPassword(false);
        setRevealOpen(true);
      } else {
        toast.error(res.message || "Could not reveal code");
      }
    } finally {
      setRevealing(false);
    }
  };

  const handleAdd = async (userId: string) => {
    setAdding(userId);
    try {
      const res = await checkinTeamApi.addMember(eventId, userId);
      if (res.success) {
        toast.success("Added to the check-in team");
        setQuery("");
        clear();
        await refresh();
      } else {
        toast.error(res.message || "Could not add member");
      }
    } finally {
      setAdding(null);
    }
  };

  const handleRemove = async (member: CheckinTeamMember) => {
    try {
      const res = await checkinTeamApi.removeMember(eventId, member.id);
      if (res.success) {
        toast.success("Removed from the check-in team");
        await refresh();
      } else {
        toast.error(res.message || "Could not remove member");
      }
    } finally {
      setConfirmRemove(null);
    }
  };

  // Strip the leading "NRU-" prefix when displaying or copying the code:
  // the mobile app pre-fills "NRU" on the access screen, so showing it here
  // makes organizers (and the team members they share it with) re-type it.
  const stripNru = (value: string) => value.replace(/^NRU-?/i, "");

  const copyCode = async (value: string) => {
    try {
      await navigator.clipboard.writeText(stripNru(value));
      toast.success("Code copied");
    } catch {
      toast.error("Couldn't copy to clipboard");
    }
  };


  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="relative overflow-hidden rounded-2xl border border-border bg-gradient-to-br from-amber-500/10 via-amber-500/5 to-background p-6">
        <div className="absolute -top-12 -right-12 w-44 h-44 rounded-full bg-amber-500/10" />
        <div className="relative flex items-start gap-4">
          <div className="w-12 h-12 rounded-2xl bg-amber-500/15 flex items-center justify-center shrink-0">
            <ShieldCheck className="w-6 h-6 text-amber-600" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="text-lg font-bold tracking-tight text-foreground">Check-In Team</h3>
            <p className="text-sm text-muted-foreground mt-0.5 max-w-prose">
              Authorize trusted Nuru users to scan guests and tickets for this event without
              sharing your account. Each person uses a single access code on their phone.
            </p>
          </div>
        </div>
      </div>

      {/* Access Code Card */}
      <Card className="border-border/60">
        <CardContent className="p-5">
          <div className="flex items-start justify-between gap-4">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                <SvgIcon src={KeySquareIcon} alt="" className="w-5 h-5 text-primary" />
              </div>
              <div className="min-w-0">
                <p className="text-sm font-semibold text-foreground">Event Access Code</p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Share this code with your check-in team. It only unlocks scanning for this event.
                </p>
                {code ? (
                  <div className="mt-3 flex items-center gap-2 flex-wrap">
                    <code className="px-3 py-1.5 rounded-md bg-muted font-mono text-sm tracking-wider text-foreground">
                      {stripNru(code.prefix)}
                    </code>

                    <Badge
                      variant={code.status === "active" ? "default" : "secondary"}
                      className={code.status === "active" ? "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400 hover:bg-emerald-500/15" : ""}
                    >
                      {code.status}
                    </Badge>
                    {code.created_at && (
                      <span className="text-[11px] text-muted-foreground">
                        Created {new Date(code.created_at).toLocaleDateString()}
                      </span>
                    )}
                  </div>
                ) : (
                  <p className="text-xs text-muted-foreground mt-3 italic">
                    No active code yet. Generate one to start your check-in team.
                  </p>
                )}
              </div>
            </div>
          </div>

          {canManage && (
            <div className="mt-4 flex flex-wrap gap-2">
              <Button
                size="sm"
                onClick={handleGenerate}
                disabled={busyCode !== null}
                className="gap-2"
              >
                {busyCode === "generate" ? <Loader2 className="w-4 h-4 animate-spin" /> : <RefreshCw className="w-4 h-4" />}
                {code ? "Regenerate" : "Generate code"}
              </Button>
              {code && code.status === "active" && (
                <Button
                  size="sm"
                  variant="outline"
                  className="gap-2"
                  onClick={() => { setPassword(""); setShowPassword(false); setPasswordOpen(true); }}
                  disabled={busyCode !== null}
                >
                  <Eye className="w-4 h-4" />
                  View code
                </Button>
              )}
              {code && code.status === "active" && (
                <Button
                  size="sm"
                  variant="outline"
                  className="gap-2 text-destructive border-destructive/30 hover:bg-destructive/5 hover:text-destructive"
                  onClick={() => setConfirmRevoke(true)}
                  disabled={busyCode !== null}
                >
                  <Trash2 className="w-4 h-4" />
                  Revoke
                </Button>
              )}
            </div>
          )}

          {!canManage && code && (
            <p className="mt-4 text-xs text-muted-foreground">
              Only the event organizer can rotate this code.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Members */}
      <Card className="border-border/60">
        <CardContent className="p-5">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <Users className="w-4 h-4 text-muted-foreground" />
              <h4 className="text-sm font-semibold text-foreground">
                Team Members {members.length > 0 && <span className="text-muted-foreground font-normal">({members.length})</span>}
              </h4>
            </div>
            {canManage && (
              <Button size="sm" variant="outline" className="gap-2" onClick={() => setAddOpen(true)}>
                <UserPlus className="w-4 h-4" />
                Add member
              </Button>
            )}
          </div>

          {loading ? (
            <div className="py-8 flex justify-center">
              <Loader2 className="w-5 h-5 animate-spin text-muted-foreground" />
            </div>
          ) : members.length === 0 ? (
            <div className="text-center py-10 border-2 border-dashed border-border rounded-xl">
              <div className="w-12 h-12 mx-auto mb-3 rounded-2xl bg-muted/60 flex items-center justify-center">
                <ScanLine className="w-6 h-6 text-muted-foreground/50" />
              </div>
              <p className="text-sm font-medium text-foreground">No check-in team yet</p>
              <p className="text-xs text-muted-foreground mt-1 max-w-xs mx-auto">
                Add trusted people from your Nuru network. They will scan with their own phones.
              </p>
            </div>
          ) : (
            <ul className="divide-y divide-border">
              <AnimatePresence initial={false}>
                {members.map((m) => (
                  <motion.li
                    key={m.id}
                    layout
                    initial={{ opacity: 0, y: -6 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -6 }}
                    className="flex items-center gap-3 py-3"
                  >
                    <Avatar className="w-10 h-10 ring-1 ring-border">
                      {m.user.avatar && <AvatarImage src={m.user.avatar} alt={m.user.full_name} />}
                      <AvatarFallback className="bg-primary/10 text-primary text-xs font-semibold">
                        {initials(m.user.full_name)}
                      </AvatarFallback>
                    </Avatar>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">
                        {m.user.full_name || m.user.email}
                      </p>
                      {m.user.phone && (
                        <p className="text-xs text-muted-foreground truncate">{m.user.phone}</p>
                      )}
                    </div>
                    {canManage && (
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-muted-foreground hover:text-destructive"
                        onClick={() => setConfirmRemove(m)}
                        aria-label="Remove from team"
                      >
                        <X className="w-4 h-4" />
                      </Button>
                    )}
                  </motion.li>
                ))}
              </AnimatePresence>
            </ul>
          )}
        </CardContent>
      </Card>

      {/* Add member dialog */}
      <Dialog open={addOpen} onOpenChange={(o) => { setAddOpen(o); if (!o) { setQuery(""); clear(); } }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Add to check-in team</DialogTitle>
            <DialogDescription>
              Search Nuru users by name, phone, or email. They'll be able to scan once you
              share the event access code with them.
            </DialogDescription>
          </DialogHeader>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              autoFocus
              placeholder="Search Nuru users..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="pl-9"
            />
          </div>
          <div className="max-h-72 overflow-y-auto -mx-1 px-1">
            {searchLoading ? (
              <div className="py-6 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-muted-foreground" /></div>
            ) : query.length < 2 ? (
              <p className="text-xs text-center text-muted-foreground py-6">Type at least 2 characters to search.</p>
            ) : results.length === 0 ? (
              <p className="text-xs text-center text-muted-foreground py-6">No matching Nuru users.</p>
            ) : (
              <ul className="divide-y divide-border">
                {results.map((u) => {
                  const already = memberUserIds.has(u.id);
                  return (
                    <li key={u.id} className="flex items-center gap-3 py-3">
                      <Avatar className="w-9 h-9 ring-1 ring-border">
                        {u.avatar && <AvatarImage src={u.avatar} />}
                        <AvatarFallback className="bg-primary/10 text-primary text-xs font-semibold">
                          {initials(u.full_name || `${u.first_name} ${u.last_name}`)}
                        </AvatarFallback>
                      </Avatar>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-foreground truncate">
                          {u.full_name || `${u.first_name} ${u.last_name}`.trim()}
                        </p>
                        <p className="text-xs text-muted-foreground truncate">{u.phone || u.email}</p>
                      </div>
                      {already ? (
                        <Badge variant="secondary" className="text-[10px]">On team</Badge>
                      ) : (
                        <Button
                          size="sm"
                          onClick={() => handleAdd(u.id)}
                          disabled={adding === u.id}
                          className="gap-1.5"
                        >
                          {adding === u.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <UserPlus className="w-3.5 h-3.5" />}
                          Add
                        </Button>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        </DialogContent>
      </Dialog>

      {/* Reveal generated/revealed code dialog */}
      <Dialog open={revealOpen} onOpenChange={(o) => { setRevealOpen(o); if (!o) setRevealedCode(null); }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{revealJustGenerated ? "New access code" : "Event access code"}</DialogTitle>
            <DialogDescription>
              {revealJustGenerated
                ? "Copy this code now and share it with your check-in team. You can view it again later by re-entering your password."
                : "Share this code with your check-in team. They redeem it in the Nuru app to enter Check-In Mode."}
            </DialogDescription>
          </DialogHeader>
          {revealedCode && (
            <div className="space-y-4">
              <div className="rounded-2xl border-2 border-dashed border-primary/40 bg-primary/5 p-6 text-center">
                <p className="text-[10px] uppercase tracking-widest text-muted-foreground mb-2">Event code</p>
                <p className="font-mono text-2xl font-bold tracking-[0.2em] text-primary select-all">
                  {stripNru(revealedCode)}
                </p>
                <p className="mt-2 text-[10px] text-muted-foreground">
                  The "NRU" prefix is added automatically in the mobile app — share only what you see above.
                </p>
              </div>

              <div className="flex gap-2">
                <Button onClick={() => copyCode(revealedCode)} className="flex-1 gap-2">
                  <Copy className="w-4 h-4" />
                  Copy code
                </Button>
                <Button variant="outline" onClick={() => setRevealOpen(false)} className="flex-1">
                  Done
                </Button>
              </div>
              <p className="text-[11px] text-muted-foreground text-center">
                Anyone you've added to the team can redeem this code in the Nuru mobile app to enter Check-In Mode.
              </p>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Confirm password to reveal */}
      <Dialog open={passwordOpen} onOpenChange={(o) => { setPasswordOpen(o); if (!o) { setPassword(""); setShowPassword(false); } }}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Lock className="w-4 h-4 text-primary" />
              Confirm your password
            </DialogTitle>
            <DialogDescription>
              For your safety, re-enter your account password to reveal the active access code.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="relative">
              <Input
                type={showPassword ? "text" : "password"}
                placeholder="Your password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") void handleReveal(); }}
                autoComplete="off"
                autoFocus
                className="pr-10"
              />
              <button
                type="button"
                onClick={() => setShowPassword((s) => !s)}
                className="absolute right-2 top-1/2 -translate-y-1/2 p-1.5 text-muted-foreground hover:text-foreground"
                aria-label={showPassword ? "Hide password" : "Show password"}
              >
                {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setPasswordOpen(false)} className="flex-1">
                Cancel
              </Button>
              <Button onClick={handleReveal} disabled={revealing || !password.trim()} className="flex-1 gap-2">
                {revealing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Eye className="w-4 h-4" />}
                Reveal
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>


      {/* Confirm revoke */}
      <Dialog open={confirmRevoke} onOpenChange={setConfirmRevoke}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="w-5 h-5 text-destructive" />
              Revoke access code?
            </DialogTitle>
            <DialogDescription>
              Active scanners will be signed out immediately. You can generate a new code right after.
            </DialogDescription>
          </DialogHeader>
          <div className="flex gap-2 justify-end">
            <Button variant="outline" onClick={() => setConfirmRevoke(false)}>Cancel</Button>
            <Button variant="destructive" onClick={handleRevoke} disabled={busyCode === "revoke"} className="gap-2">
              {busyCode === "revoke" && <Loader2 className="w-4 h-4 animate-spin" />}
              Revoke code
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Confirm remove member */}
      <Dialog open={!!confirmRemove} onOpenChange={(o) => !o && setConfirmRemove(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Remove from team?</DialogTitle>
            <DialogDescription>
              {confirmRemove?.user.full_name || "This person"} will no longer be able to scan
              guests or tickets for this event. Any active session is ended.
            </DialogDescription>
          </DialogHeader>
          <div className="flex gap-2 justify-end">
            <Button variant="outline" onClick={() => setConfirmRemove(null)}>Cancel</Button>
            <Button variant="destructive" onClick={() => confirmRemove && handleRemove(confirmRemove)}>
              Remove
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default CheckinTeam;
