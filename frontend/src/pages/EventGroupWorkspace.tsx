/**
 * Event Group Workspace page.
 * Tabs: Chat | Scoreboard. Header shows group identity + members button.
 * Accessible via `/event-group/:groupId` (logged-in or guest token).
 */
import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { ChevronLeft, Trophy, Users, Lock, Unlock, Link2, BarChart3 } from "lucide-react";
import ChatIcon from "@/assets/group-chat-icon.svg";
import { Tabs, TabsContent } from "@/components/ui/tabs";
import { PillTabsNav } from "@/components/ui/pill-tabs";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { eventGroupsApi } from "@/lib/api/eventGroups";
import { toast } from "sonner";
import ChatPanel from "@/components/eventGroups/ChatPanel";
import ScoreboardPanel from "@/components/eventGroups/ScoreboardPanel";
import AnalyticsPanel from "@/components/eventGroups/AnalyticsPanel";
import MembersDrawer from "@/components/eventGroups/MembersDrawer";

const initials = (n: string) => (n || "?").trim().split(/\s+/).slice(0, 2).map(s => s[0]).join("").toUpperCase();

const groupCacheKey = (id: string) => `nuru:eg:group:${id}`;
const membersCacheKey = (id: string) => `nuru:eg:members:${id}`;

const readCache = <T,>(key: string): T | null => {
  try {
    const raw = sessionStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
};

const writeCache = (key: string, value: unknown) => {
  try { sessionStorage.setItem(key, JSON.stringify(value)); } catch { /* ignore quota */ }
};

const EventGroupWorkspace = () => {
  const { groupId } = useParams<{ groupId: string }>();
  const navigate = useNavigate();
  const [tab, setTab] = useState("chat");
  const [group, setGroup] = useState<any>(() =>
    groupId ? readCache<any>(groupCacheKey(groupId)) : null);
  const [members, setMembers] = useState<any[]>(() =>
    (groupId ? readCache<any[]>(membersCacheKey(groupId)) : null) ?? []);
  // Header + chat can render as soon as `group` resolves — members load
  // independently so the page never blocks on the heavier query.
  const [loadingGroup, setLoadingGroup] = useState(() =>
    !(groupId && readCache(groupCacheKey(groupId))));
  const [drawerOpen, setDrawerOpen] = useState(false);

  useEffect(() => {
    if (!groupId) return;
    // Group payload — small + the only thing the header depends on.
    eventGroupsApi.get(groupId).then((g) => {
      if (g.success && g.data) {
        setGroup(g.data);
        writeCache(groupCacheKey(groupId), g.data);
      }
    }).finally(() => setLoadingGroup(false));
    // Members — heavier; rendered progressively (member count + chat author lookup).
    eventGroupsApi.members(groupId).then((m) => {
      if (m.success && m.data) {
        const list = m.data.members || [];
        setMembers(list);
        writeCache(membersCacheKey(groupId), list);
      }
    });
  }, [groupId]);

  // Keep the browser tab title in sync with the current group.
  useEffect(() => {
    const prev = document.title;
    if (group?.name) {
      const evt = group?.event?.name || group?.event_name;
      document.title = evt ? `${group.name} - ${evt} - Nuru` : `${group.name} - Nuru`;
    }
    return () => { document.title = prev; };
  }, [group?.name, group?.event?.name, group?.event_name]);

  if (!groupId) return null;

  const me = members.find((m) => m.id === group?.viewer?.member_id || m.is_me);
  const isAdmin = !!group?.viewer?.is_admin || group?.viewer?.role === "organizer" || !!me?.is_admin || me?.role === "organizer";

  // Live event status — derived every render from the current event end date
  // (NOT from the stored `is_closed` flag, which would otherwise stay stale
  // after the organizer reschedules the event to a future date).
  const eventEndIso = group?.event?.end_date || group?.event?.start_date || group?.event_end_date || group?.event_start_date;
  const eventEnded = eventEndIso ? new Date(eventEndIso) < new Date() : false;
  // The chat is read-only only when the event has actually ended.
  // The manual `is_closed` admin flag is treated as an override that is
  // automatically released the moment the event is rescheduled forward.
  const effectiveClosed = eventEnded || (!!group?.is_closed && !eventEndIso);
  const canReopen = isAdmin && group?.is_closed && !eventEnded;
  const canClose = isAdmin && !group?.is_closed && !eventEnded;

  const copyGroupInvite = async () => {
    if (!groupId) return;
    const res = await eventGroupsApi.createInvite(groupId, {});
    if (res.success && res.data) {
      const url = `${window.location.origin}/g/${res.data.token}`;
      try {
        await navigator.clipboard.writeText(url);
        toast.success("Invite link copied · share with committee & contributors");
      } catch {
        toast.success("Invite link ready", { description: url });
      }
    } else {
      toast.error(res.message || "Could not create invite link");
    }
  };

  const toggleClosed = async () => {
    if (!groupId || !group) return;
    const next = !group.is_closed;
    if (!next && eventEnded) {
      toast.error("Event has ended · cannot reopen this group");
      return;
    }
    const res = await eventGroupsApi.update(groupId, { is_closed: next });
    if (res.success) {
      setGroup((g: any) => ({ ...g, is_closed: next }));
      toast.success(next ? "Group closed" : "Group reopened");
    } else {
      toast.error(res.message || "Failed to update group");
    }
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={() => navigate(-1)} aria-label="Back">
          <ChevronLeft className="w-5 h-5" />
        </Button>
        {loadingGroup && !group ? (
          <div className="flex items-center gap-3 flex-1">
            <Skeleton className="w-12 h-12 rounded-full" />
            <div className="flex-1 space-y-2">
              <Skeleton className="h-4 w-48" />
              <Skeleton className="h-3 w-32" />
            </div>
          </div>
        ) : group ? (
          <div className="flex items-center gap-3 flex-1 min-w-0">
            <Avatar className="w-12 h-12 ring-2 ring-primary/20">
              {group.image_url && <AvatarImage src={group.image_url} />}
              <AvatarFallback className="bg-primary/10 text-primary font-bold">
                {initials(group.name)}
              </AvatarFallback>
            </Avatar>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <h1 className="text-lg sm:text-xl font-bold truncate">{group.name}</h1>
                {effectiveClosed && (
                  <Badge variant="outline" className="text-[10px] gap-1">
                    <Lock className="w-3 h-3" /> {eventEnded ? "Event ended" : "Closed"}
                  </Badge>
                )}
              </div>
              <p className="text-xs text-muted-foreground truncate">
                {members.length} member{members.length !== 1 ? "s" : ""} - {group.event?.name || group.event_name || ""}
              </p>
            </div>
          </div>
        ) : (
          <p className="flex-1 text-sm text-muted-foreground">Group not found</p>
        )}
        {(canReopen || canClose) && (
          <Button
            variant="outline"
            size="sm"
            onClick={toggleClosed}
            title={canReopen ? "Reopen group" : "Close group"}
          >
            {canReopen ? <Unlock className="w-4 h-4 sm:mr-1.5" /> : <Lock className="w-4 h-4 sm:mr-1.5" />}
            <span className="hidden sm:inline">{canReopen ? "Reopen" : "Close"}</span>
          </Button>
        )}
        {isAdmin && group?.is_closed && eventEnded && (
          <Badge variant="outline" className="text-[10px]">Event ended</Badge>
        )}
        {isAdmin && !group?.is_closed && (
          <Button variant="outline" size="sm" onClick={copyGroupInvite} title="Copy a shareable invite link for anyone">
            <Link2 className="w-4 h-4 sm:mr-1.5" />
            <span className="hidden sm:inline">Copy link</span>
          </Button>
        )}
        <Button variant="outline" size="sm" onClick={() => setDrawerOpen(true)}>
          <Users className="w-4 h-4 sm:mr-1.5" />
          <span className="hidden sm:inline">Members</span>
        </Button>
      </div>

      {/* Tabs — non-organisers only ever see the chat workspace. The
          Contributors scoreboard and Analytics panel contain sensitive
          financial information that's restricted to organisers (the
          backend enforces the same rule on /scoreboard). */}
      <Tabs value={tab} onValueChange={setTab}>
        <PillTabsNav
          activeTab={tab}
          onTabChange={setTab}
          tabs={isAdmin ? [
            { value: "chat", label: "Chat", icon: <img src={ChatIcon} alt="" className="w-3.5 h-3.5 icon-adaptive" /> },
            { value: "scoreboard", label: "Contributors", icon: <Users className="w-3.5 h-3.5" /> },
            { value: "analytics", label: "Analytics", icon: <BarChart3 className="w-3.5 h-3.5" /> },
          ] : [
            { value: "chat", label: "Chat", icon: <img src={ChatIcon} alt="" className="w-3.5 h-3.5 icon-adaptive" /> },
          ]}
        />

        <TabsContent value="chat">
          {/* Wait until group + members are loaded so meMemberId is known
              before rendering bubbles — prevents the left→right flicker. */}
          {loadingGroup && !group ? (
            <div className="bg-card border border-border rounded-2xl h-[480px] animate-pulse" />
          ) : (
            <ChatPanel
              groupId={groupId}
              members={members}
              meMemberId={me?.id || null}
              isAdmin={isAdmin}
              isClosed={effectiveClosed}
            />
          )}
        </TabsContent>

        {isAdmin && (
          <TabsContent value="scoreboard">
            <ScoreboardPanel groupId={groupId} />
          </TabsContent>
        )}

        {isAdmin && (
          <TabsContent value="analytics">
            <AnalyticsPanel groupId={groupId} />
          </TabsContent>
        )}
      </Tabs>


      <MembersDrawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        groupId={groupId}
        isAdmin={isAdmin}
      />
    </div>
  );
};

export default EventGroupWorkspace;
