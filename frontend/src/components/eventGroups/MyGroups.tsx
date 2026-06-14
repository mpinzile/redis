/**
 * My Groups inbox — premium, WhatsApp-style list of every event group
 * the current user belongs to, with unread badges, last-message preview,
 * and quick search. Polished for both mobile and desktop.
 */
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { ChevronLeft, Users, Lock, Search, Image as ImageIcon, CheckCheck } from "lucide-react";
import GroupsIcon from "@/assets/icons/groups-icon.svg";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { eventGroupsApi } from "@/lib/api/eventGroups";
import { usePolling } from "@/hooks/usePolling";

const initials = (n?: string) => (n || "?").trim().split(/\s+/).slice(0, 2).map(s => s[0]).join("").toUpperCase();

const timeAgo = (iso?: string) => {
  if (!iso) return "";
  // Server returns naive UTC — append 'Z' so browser converts to local time.
  const normalized = iso.endsWith("Z") || /[+-]\d{2}:?\d{2}$/.test(iso) ? iso : (iso.includes("T") ? `${iso}Z` : `${iso.replace(" ", "T")}Z`);
  const d = new Date(normalized);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "now";
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  if (diff < 604800) return `${Math.floor(diff / 86400)}d`;
  return d.toLocaleDateString([], { day: "numeric", month: "short" });
};

// Module-level cache so navigating away and back shows the previous list
// instantly while a silent background refresh runs (no skeleton flash).
let cachedGroups: any[] | null = null;

/** Called after login/signup so the cache is fresh by the time the user
 *  opens "My Groups" — picks up any event groups the contributor-claim
 *  service just attached on the backend. */
export const prefetchMyGroupsAfterLogin = async () => {
  cachedGroups = null;
  try {
    const res = await eventGroupsApi.listMyGroups();
    if (res.success && res.data) cachedGroups = res.data.groups || [];
  } catch { /* silent — MyGroups will re-fetch on mount */ }
};

/** Clear cached groups on logout so the next user doesn't see stale data. */
export const clearMyGroupsCache = () => { cachedGroups = null; };

const MyGroups = () => {
  const navigate = useNavigate();
  const [groups, setGroups] = useState<any[]>(cachedGroups || []);
  const [loading, setLoading] = useState(cachedGroups === null);
  const [search, setSearch] = useState("");

  const fetchData = async () => {
    const res = await eventGroupsApi.listMyGroups(search || undefined);
    if (res.success && res.data) {
      const list = res.data.groups || [];
      setGroups(list);
      cachedGroups = list;
    }
    setLoading(false);
  };

  useEffect(() => { fetchData(); /* eslint-disable-next-line */ }, [search]);
  usePolling(fetchData, 15000, !loading);

  const totalUnread = useMemo(
    () => groups.reduce((acc, g) => acc + (g.unread_count || 0), 0),
    [groups],
  );
  const unreadGroups = useMemo(() => groups.filter(g => (g.unread_count || 0) > 0).length, [groups]);

  const renderPreview = (g: any) => {
    const lm = g.last_message;
    if (!lm) return <span className="italic opacity-70">No messages yet</span>;
    if (lm.message_type === "image") {
      return (
        <span className="inline-flex items-center gap-1">
          <ImageIcon className="w-3 h-3" /> Photo
        </span>
      );
    }
    if (lm.message_type === "system") {
      return <span className="italic">{lm.content || "Activity update"}</span>;
    }
    return <>{lm.sender_name ? <span className="font-medium text-foreground/80">{lm.sender_name}: </span> : null}{lm.content}</>;
  };

  return (
    <div className="space-y-5">
      {/* Premium header */}
      <div className="relative overflow-hidden rounded-2xl border border-border bg-card shadow-sm">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,hsl(var(--primary)/0.10),transparent_55%)] pointer-events-none" />
        <div className="relative p-4 sm:p-5 flex items-center gap-3">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => navigate(-1)}
            aria-label="Back"
            className="rounded-full hover:bg-primary/10"
          >
            <ChevronLeft className="w-5 h-5" />
          </Button>
          <div className="relative w-11 h-11 rounded-2xl bg-primary/10 flex items-center justify-center shrink-0 ring-1 ring-primary/20">
            <img src={GroupsIcon} alt="" className="w-6 h-6 icon-adaptive" />
            {totalUnread > 0 && (
              <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 rounded-full bg-primary text-primary-foreground text-[10px] font-bold flex items-center justify-center ring-2 ring-card">
                {totalUnread > 99 ? "99+" : totalUnread}
              </span>
            )}
          </div>
          <div className="min-w-0 flex-1">
            <h1 className="text-lg sm:text-xl font-bold tracking-tight truncate">My Groups</h1>
            <p className="text-xs text-muted-foreground mt-0.5">
              {groups.length === 0 && !loading
                ? "All event chat workspaces"
                : `${groups.length} group${groups.length !== 1 ? "s" : ""}${unreadGroups > 0 ? ` - ${unreadGroups} with new messages` : ""}`}
            </p>
          </div>
        </div>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search groups…"
          className="pl-10 h-11 rounded-2xl bg-card border-border/70 focus-visible:ring-1 focus-visible:ring-primary/40"
        />
      </div>

      {loading ? (
        <div className="rounded-2xl border border-border bg-card overflow-hidden divide-y divide-border">
          {[...Array(6)].map((_, i) => (
            <div key={i} className="p-3.5 flex gap-3 items-center">
              <Skeleton className="w-12 h-12 rounded-full" />
              <div className="flex-1 space-y-2">
                <Skeleton className="h-4 w-2/3" />
                <Skeleton className="h-3 w-1/2" />
              </div>
            </div>
          ))}
        </div>
      ) : groups.length === 0 ? (
        <div className="text-center py-16 rounded-2xl border-2 border-dashed border-border bg-card/50">
          <div className="w-16 h-16 mx-auto mb-3 rounded-2xl bg-primary/10 flex items-center justify-center">
            <img src={GroupsIcon} alt="" className="w-8 h-8 opacity-60 icon-adaptive" />
          </div>
          <p className="text-sm font-semibold">No groups yet</p>
          <p className="text-xs text-muted-foreground mt-1 max-w-xs mx-auto">
            Join an event or create your own to start chatting with contributors.
          </p>
        </div>
      ) : (
        <div className="rounded-2xl border border-border bg-card overflow-hidden shadow-sm divide-y divide-border/70">
          {groups.map((g, i) => {
            const unread = g.unread_count || 0;
            const hasUnread = unread > 0;
            const lm = g.last_message;
            const lastTime = timeAgo(lm?.created_at || g.created_at);
            return (
              <motion.button
                key={g.id}
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: Math.min(i * 0.025, 0.2), duration: 0.18 }}
                onClick={() => navigate(`/event-group/${g.id}`)}
                className={`group w-full text-left p-3 sm:p-3.5 flex items-center gap-3 transition-colors hover:bg-muted/40 active:bg-muted/60 ${
                  hasUnread ? "bg-primary/[0.03]" : ""
                }`}
              >
                <div className="relative shrink-0">
                  <Avatar className={`w-12 h-12 sm:w-13 sm:h-13 ring-2 transition-all ${
                    hasUnread ? "ring-primary/40" : "ring-border group-hover:ring-primary/20"
                  }`}>
                    {g.image_url && <AvatarImage src={g.image_url} />}
                    <AvatarFallback className="bg-primary/10 text-primary font-bold text-sm">
                      {initials(g.name)}
                    </AvatarFallback>
                  </Avatar>
                  {g.is_closed && (
                    <span className="absolute -bottom-0.5 -right-0.5 w-4 h-4 rounded-full bg-muted ring-2 ring-card flex items-center justify-center">
                      <Lock className="w-2.5 h-2.5 text-muted-foreground" />
                    </span>
                  )}
                </div>

                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className={`text-sm truncate ${hasUnread ? "font-bold text-foreground" : "font-semibold text-foreground/90"}`}>
                      {g.name}
                    </p>
                    <span className={`ml-auto text-[10.5px] shrink-0 tabular-nums ${
                      hasUnread ? "text-primary font-semibold" : "text-muted-foreground"
                    }`}>
                      {lastTime}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 mt-0.5">
                    <div className={`text-xs truncate flex-1 inline-flex items-center gap-1 ${
                      hasUnread ? "text-foreground/80" : "text-muted-foreground"
                    }`}>
                      {!hasUnread && lm?.is_mine && (
                        <CheckCheck className="w-3 h-3 text-primary/70 shrink-0" />
                      )}
                      <span className="truncate">{renderPreview(g)}</span>
                    </div>
                    {hasUnread && (
                      <Badge className="bg-primary text-primary-foreground text-[10px] h-5 min-w-[20px] px-1.5 rounded-full font-bold shadow-sm">
                        {unread > 99 ? "99+" : unread}
                      </Badge>
                    )}
                  </div>
                  <div className="flex items-center gap-2 mt-2">
                    {/* Stacked member avatars (up to 5) */}
                    {Array.isArray(g.members_preview) && g.members_preview.length > 0 ? (
                      <div className="flex -space-x-2">
                        {g.members_preview.slice(0, 5).map((mem: any) => (
                          <Avatar
                            key={mem.id}
                            className="w-6 h-6 ring-2 ring-card"
                          >
                            {mem.avatar_url && <AvatarImage src={mem.avatar_url} />}
                            <AvatarFallback className="text-[9px] bg-primary/15 text-primary font-semibold">
                              {initials(mem.name)}
                            </AvatarFallback>
                          </Avatar>
                        ))}
                        {(g.member_count || 0) > 5 && (
                          <div className="w-6 h-6 rounded-full ring-2 ring-card bg-muted flex items-center justify-center text-[9px] font-bold text-muted-foreground">
                            +{Math.min(99, (g.member_count || 0) - 5)}
                          </div>
                        )}
                      </div>
                    ) : (
                      <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-muted/60 text-[10.5px] text-muted-foreground">
                        <Users className="w-2.5 h-2.5" />
                        <span className="font-semibold">{g.member_count || 0}</span>
                      </span>
                    )}
                    <span className="text-[10.5px] text-muted-foreground font-medium">
                      {g.member_count || 0} {(g.member_count || 0) === 1 ? "member" : "members"}
                    </span>
                    {g.event_name && (
                      <span className="text-[10.5px] text-muted-foreground/80 truncate ml-auto">
                        - {g.event_name}
                      </span>
                    )}
                  </div>
                </div>
              </motion.button>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default MyGroups;
