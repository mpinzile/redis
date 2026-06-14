/**
 * Members drawer — list members grouped/badged by role (organizer - committee - contributor).
 * Admins can remove non-organizer members and add event contributors who aren't yet in the group.
 */
import { useEffect, useState, useMemo } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import {
  RefreshCw, Crown, ShieldCheck, Users as UsersIcon, UserPlus, CheckCircle2,
  Clock, Trash2, Plus, Search,
} from "lucide-react";
import { eventGroupsApi } from "@/lib/api/eventGroups";
import { toast } from "sonner";

const initials = (n: string) => (n || "?").trim().split(/\s+/).slice(0, 2).map(s => s[0]).join("").toUpperCase();

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  groupId: string;
  isAdmin?: boolean;
}

const ROLE_ORDER: Record<string, number> = { organizer: 0, committee: 1, contributor: 2, guest: 3 };

const roleBadge = (role: string, isAdmin: boolean) => {
  if (role === "organizer" || isAdmin) {
    return (
      <Badge className="text-[9px] gap-1 bg-primary text-primary-foreground border-0 shadow-sm">
        <Crown className="w-2.5 h-2.5" /> Organizer
      </Badge>
    );
  }
  if (role === "committee") {
    return (
      <Badge className="text-[9px] gap-1 bg-secondary text-secondary-foreground border-0">
        <ShieldCheck className="w-2.5 h-2.5" /> Committee
      </Badge>
    );
  }
  return (
    <Badge variant="outline" className="text-[9px] gap-1 border-primary/30 text-primary bg-primary/5">
      <UsersIcon className="w-2.5 h-2.5" /> Contributor
    </Badge>
  );
};

const MembersDrawer = ({ open, onOpenChange, groupId, isAdmin }: Props) => {
  const [members, setMembers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [syncing, setSyncing] = useState(false);

  // remove dialog
  const [toRemove, setToRemove] = useState<any | null>(null);
  const [removing, setRemoving] = useState(false);

  // add picker
  const [addOpen, setAddOpen] = useState(false);
  const [addLoading, setAddLoading] = useState(false);
  const [addable, setAddable] = useState<{ contributor_id: string; name: string; phone?: string; is_nuru_user: boolean }[]>([]);
  const [addSearch, setAddSearch] = useState("");
  const [addingId, setAddingId] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    const res = await eventGroupsApi.members(groupId);
    if (res.success && res.data) setMembers(res.data.members || []);
    setLoading(false);
  };

  useEffect(() => { if (open) load(); /* eslint-disable-next-line */ }, [open, groupId]);

  const sync = async () => {
    setSyncing(true);
    const res = await eventGroupsApi.syncMembers(groupId);
    setSyncing(false);
    if (res.success) { toast.success("Members synced"); load(); }
    else toast.error(res.message || "Sync failed");
  };

  const openAdd = async () => {
    setAddOpen(true);
    setAddSearch("");
    setAddLoading(true);
    const res = await eventGroupsApi.addableContributors(groupId);
    setAddLoading(false);
    if (res.success && res.data) setAddable(res.data.contributors || []);
    else toast.error(res.message || "Could not load contributors");
  };

  const addOne = async (contributorId: string) => {
    setAddingId(contributorId);
    const res = await eventGroupsApi.addContributorMember(groupId, contributorId);
    setAddingId(null);
    if (res.success) {
      toast.success("Member added");
      setAddable((list) => list.filter((c) => c.contributor_id !== contributorId));
      load();
    } else toast.error(res.message || "Could not add");
  };

  const confirmRemove = async () => {
    if (!toRemove) return;
    setRemoving(true);
    const res = await eventGroupsApi.removeMember(groupId, toRemove.id);
    setRemoving(false);
    if (res.success) {
      toast.success("Member removed");
      setMembers((list) => list.filter((x) => x.id !== toRemove.id));
      setToRemove(null);
    } else toast.error(res.message || "Could not remove");
  };

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    const list = q ? members.filter(m => (m.display_name || "").toLowerCase().includes(q)) : members;
    return [...list].sort((a, b) => {
      const ra = ROLE_ORDER[a.role] ?? 9;
      const rb = ROLE_ORDER[b.role] ?? 9;
      if (ra !== rb) return ra - rb;
      return (a.display_name || "").localeCompare(b.display_name || "");
    });
  }, [members, search]);

  const filteredAddable = useMemo(() => {
    const q = addSearch.trim().toLowerCase();
    const list = q ? addable.filter(c => (c.name || "").toLowerCase().includes(q) || (c.phone || "").toLowerCase().includes(q)) : addable;
    return [...list].sort((a, b) => (a.name || "").localeCompare(b.name || ""));
  }, [addable, addSearch]);

  const counts = useMemo(() => {
    const isJoined = (m: any) => m.has_joined ?? (!!m.user_id || !!m.guest_name);
    return {
      organizer: members.filter(m => m.role === "organizer" || m.is_admin).length,
      committee: members.filter(m => m.role === "committee" && !m.is_admin).length,
      contributor: members.filter(m => m.role === "contributor" || m.role === "guest").length,
      joined: members.filter(isJoined).length,
      pending: members.filter(m => !isJoined(m)).length,
    };
  }, [members]);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full sm:max-w-md p-0 flex flex-col">
        <SheetHeader className="p-4 pr-12 border-b border-border">
          <SheetTitle className="flex items-center justify-between gap-2 flex-wrap">
            <span>Members ({members.length})</span>
            <div className="flex items-center gap-1.5">
              {isAdmin && (
                <Button size="sm" variant="default" onClick={openAdd}>
                  <Plus className="w-3.5 h-3.5 mr-1.5" /> Add
                </Button>
              )}
              {isAdmin && (
                <Button size="sm" variant="outline" onClick={sync} disabled={syncing}>
                  <RefreshCw className={`w-3.5 h-3.5 mr-1.5 ${syncing ? "animate-spin" : ""}`} /> Sync
                </Button>
              )}
            </div>
          </SheetTitle>
          <div className="flex flex-wrap gap-1.5 pt-1">
            <Badge variant="outline" className="text-[10px] gap-1"><Crown className="w-2.5 h-2.5 text-primary" /> {counts.organizer}</Badge>
            <Badge variant="outline" className="text-[10px] gap-1"><ShieldCheck className="w-2.5 h-2.5 text-secondary-foreground" /> {counts.committee}</Badge>
            <Badge variant="outline" className="text-[10px] gap-1"><UsersIcon className="w-2.5 h-2.5 text-muted-foreground" /> {counts.contributor}</Badge>
            <Badge className="text-[10px] gap-1 bg-primary/10 text-primary border border-primary/20"><CheckCircle2 className="w-2.5 h-2.5" /> {counts.joined} joined</Badge>
            {counts.pending > 0 && (
              <Badge variant="outline" className="text-[10px] gap-1 text-muted-foreground"><Clock className="w-2.5 h-2.5" /> {counts.pending} pending</Badge>
            )}
          </div>
        </SheetHeader>
        <div className="p-3 border-b border-border">
          <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search members…" className="h-9" />
        </div>
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="p-3 space-y-2">{[...Array(6)].map((_, i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
          ) : (
            <div className="divide-y divide-border">
              {filtered.map((m) => {
                const joined = m.has_joined ?? (!!m.user_id || !!m.guest_name);
                const canRemove = isAdmin && m.role !== "organizer" && !m.is_me;
                return (
                  <div key={m.id} className={`p-3 flex items-center gap-3 ${joined ? "" : "bg-muted/30"}`}>
                    <Avatar className={`w-9 h-9 ${joined ? "" : "opacity-60"}`}>
                      {m.avatar_url && <AvatarImage src={m.avatar_url} />}
                      <AvatarFallback className="bg-primary/10 text-primary text-xs">{initials(m.display_name)}</AvatarFallback>
                    </Avatar>
                    <div className="flex-1 min-w-0">
                      <p className={`text-sm font-semibold truncate ${joined ? "" : "text-muted-foreground"}`}>{m.display_name}</p>
                      <div className="flex items-center gap-1.5 mt-0.5 flex-wrap">
                        {roleBadge(m.role, !!m.is_admin)}
                        {joined ? (
                          <Badge className="text-[9px] gap-1 bg-primary/10 text-primary border border-primary/20">
                            <CheckCircle2 className="w-2.5 h-2.5" /> Joined
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="text-[9px] gap-1 text-muted-foreground">
                            <Clock className="w-2.5 h-2.5" /> Pending
                          </Badge>
                        )}
                        {!m.user_id && joined && <Badge variant="outline" className="text-[9px]">guest</Badge>}
                      </div>
                    </div>
                    {canRemove && (
                      <Button
                        size="icon"
                        variant="ghost"
                        className="h-8 w-8 text-destructive hover:bg-destructive/10 hover:text-destructive"
                        onClick={() => setToRemove(m)}
                        title="Remove member"
                      >
                        <Trash2 className="w-4 h-4" />
                      </Button>
                    )}
                  </div>
                );
              })}
              {filtered.length === 0 && (
                <div className="p-10 text-center text-muted-foreground text-sm">
                  <UserPlus className="w-8 h-8 mx-auto mb-2 opacity-30" />
                  No members match.
                </div>
              )}
            </div>
          )}
        </div>
      </SheetContent>

      {/* Remove confirmation */}
      <AlertDialog open={!!toRemove} onOpenChange={(v) => !v && setToRemove(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove {toRemove?.display_name}?</AlertDialogTitle>
            <AlertDialogDescription>
              They'll lose access to this group's chat and scoreboard. You can re-add them later.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={removing}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={confirmRemove}
              disabled={removing}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {removing ? "Removing…" : "Remove"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Add member picker */}
      <Dialog open={addOpen} onOpenChange={setAddOpen}>
        <DialogContent className="max-w-md p-0 overflow-hidden">
          <DialogHeader className="p-4 border-b border-border">
            <DialogTitle className="flex items-center gap-2">
              <UserPlus className="w-4 h-4 text-primary" /> Add member
            </DialogTitle>
            <DialogDescription>
              Pick an event contributor to add to the group.
            </DialogDescription>
          </DialogHeader>
          <div className="p-3 border-b border-border">
            <div className="relative">
              <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={addSearch}
                onChange={(e) => setAddSearch(e.target.value)}
                placeholder="Search by name or phone…"
                className="h-9 pl-8"
              />
            </div>
          </div>
          <div className="max-h-[60vh] overflow-y-auto">
            {addLoading ? (
              <div className="p-3 space-y-2">{[...Array(4)].map((_, i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
            ) : filteredAddable.length === 0 ? (
              <div className="p-10 text-center text-muted-foreground text-sm">
                <CheckCircle2 className="w-8 h-8 mx-auto mb-2 opacity-30" />
                Everyone's already in the group.
              </div>
            ) : (
              <div className="divide-y divide-border">
                {filteredAddable.map((c) => (
                  <div key={c.contributor_id} className="p-3 flex items-center gap-3">
                    <Avatar className="w-9 h-9">
                      <AvatarFallback className="bg-primary/10 text-primary text-xs">{initials(c.name)}</AvatarFallback>
                    </Avatar>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold truncate">{c.name}</p>
                      <div className="flex items-center gap-1.5 mt-0.5 flex-wrap">
                        {c.phone && <span className="text-[11px] text-muted-foreground">{c.phone}</span>}
                        {c.is_nuru_user ? (
                          <Badge variant="outline" className="text-[9px] border-primary/30 text-primary">Nuru user</Badge>
                        ) : (
                          <Badge variant="outline" className="text-[9px] text-muted-foreground">Invite required</Badge>
                        )}
                      </div>
                    </div>
                    <Button
                      size="sm"
                      onClick={() => addOne(c.contributor_id)}
                      disabled={addingId === c.contributor_id}
                    >
                      {addingId === c.contributor_id ? "Adding…" : <><Plus className="w-3.5 h-3.5 mr-1" /> Add</>}
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </Sheet>
  );
};

export default MembersDrawer;
