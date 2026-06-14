import { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { Users, Loader2 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import SvgIcon from '@/components/ui/svg-icon';
import CalendarIcon from '@/assets/icons/calendar-icon.svg';
import LocationIcon from '@/assets/icons/location-icon.svg';
import TicketIcon from '@/assets/icons/ticket-icon.svg';
import PrintIcon from '@/assets/icons/print-icon.svg';
import videoChatIcon from '@/assets/video-chat-icon.svg';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import PrintableTicket from '@/components/PrintableTicket';

import { useEvents } from '@/data/useEvents';
import { useServices } from '@/data/useUserServices';
import { useFollowSuggestions, useCircles } from '@/data/useSocial';
import { eventsApi } from '@/lib/api/events';
import { ticketingApi } from '@/lib/api/ticketing';
import { meetingsApi } from '@/lib/api/meetings';
import { useCurrency } from '@/hooks/useCurrency';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import { getEventImage } from '@/lib/eventImage';

// Loading skeleton for sidebar cards
const SidebarCardSkeleton = ({ title, count = 3 }: { title: string; count?: number }) => (
  <div className="bg-card rounded-lg p-4 border border-border">
    <h2 className="font-semibold text-foreground mb-4">{title}</h2>
    <div className="space-y-3">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="flex gap-3 p-2 rounded-lg">
          <Skeleton className="w-12 h-12 rounded-lg" />
          <div className="flex-1 min-w-0 space-y-2">
            <Skeleton className="h-4 w-3/4" />
            <Skeleton className="h-3 w-1/2" />
          </div>
        </div>
      ))}
    </div>
  </div>
);

interface UpcomingEvent {
  id: string;
  title: string;
  start_date?: string;
  cover_image?: string;
  status?: string;
  role: 'creator' | 'committee' | 'guest';
  sells_tickets?: boolean;
  ticket_approval_status?: string;
}

const ROLE_LABELS: Record<string, string> = {
  creator: 'My Event',
  committee: 'Committee',
  guest: 'Invited',
};

// ── Ticket-Selling Events Section ──
const TicketEventsSection = ({ navigate }: { navigate: (path: string) => void }) => {
  const { format: formatPrice } = useCurrency();
  const { t } = useLanguage();
  const [ticketEvents, setTicketEvents] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const loadedRef = useRef(false);

  useEffect(() => {
    if (loadedRef.current) return;
    loadedRef.current = true;
    ticketingApi.getTicketedEvents({ limit: 5 }).then((res) => {
      if (res.success && res.data) {
        const data = res.data as any;
        setTicketEvents(data.events || []);
      }
    }).catch(() => {}).finally(() => setLoading(false));
  }, []);

  if (loading || ticketEvents.length === 0) return null;

  return (
    <div className="bg-card rounded-lg p-4 border border-border">
      <h2 className="font-semibold text-foreground mb-4 flex items-center gap-2">
        <img src={TicketIcon} alt="Ticket" className="w-4 h-4 dark:invert" />
        Events with Tickets
      </h2>
      <div className="space-y-3">
        {ticketEvents.map((event) => (
          <div
            key={event.id}
            className="flex gap-3 cursor-pointer hover:bg-muted/50 p-2 rounded-lg transition-colors"
            onClick={() => navigate(`/event/${event.id}`)}
          >
            <div className="w-12 h-12 rounded-lg bg-muted flex items-center justify-center overflow-hidden flex-shrink-0">
              <img src={getEventImage(event)} alt={event.name} className="w-full h-full object-cover" />
            </div>
            <div className="flex-1 min-w-0">
              <h3 className="font-medium text-sm text-foreground truncate">{event.name}</h3>
              <p className="text-xs text-muted-foreground">
                {event.start_date ? new Date(event.start_date).toLocaleDateString('en-US', {
                  weekday: 'short', month: 'short', day: 'numeric'
                }) : 'Date TBD'}
              </p>
              <div className="flex items-center gap-2 mt-1">
                <Badge variant="secondary" className="text-[10px] h-4">
                  From {formatPrice(event.min_price)}
                </Badge>
                {event.total_available <= 0 && (
                  <Badge variant="destructive" className="text-[10px] h-4">Sold Out</Badge>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

// ── My Meetings Section ──
const MyMeetingsSection = ({ navigate }: { navigate: (path: string) => void }) => {
  const [meetings, setMeetings] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchMeetings = useCallback(async (isInitial = false) => {
    try {
      const res = await meetingsApi.myMeetings();
      if (res.success && res.data) {
        const data = res.data as any[];
        const active = data.filter((m: any) => m.status !== 'ended').slice(0, 5);
        setMeetings(active);
      }
    } catch { /* silent */ }
    finally { if (isInitial) setLoading(false); }
  }, []);

  useEffect(() => {
    fetchMeetings(true);
  }, [fetchMeetings]);

  // Poll every 30s
  useEffect(() => {
    const interval = setInterval(() => fetchMeetings(), 30000);
    return () => clearInterval(interval);
  }, [fetchMeetings]);

  // Show nothing only after initial load completes with no meetings
  if (loading) return null;
  if (meetings.length === 0) return null;

  return (
    <div className="bg-card rounded-lg border border-border overflow-hidden">
      <div className="px-4 pt-4 pb-2 flex items-center gap-2">
        <div className="w-6 h-6 rounded-md bg-primary/10 flex items-center justify-center">
          <SvgIcon src={videoChatIcon} className="w-3.5 h-3.5" />
        </div>
        <h2 className="font-semibold text-foreground text-sm">My Meetings</h2>
      </div>
      <div className="px-2 pb-3 space-y-1">
        {meetings.map((meeting) => {
          const isLive = meeting.status === 'in_progress';
          const scheduledDate = meeting.scheduled_at
            ? new Date(meeting.scheduled_at).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
            : '';
          const scheduledTime = meeting.scheduled_at
            ? new Date(meeting.scheduled_at).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
            : '';

          return (
            <div
              key={meeting.id}
              className={`flex gap-3 p-2.5 rounded-xl cursor-pointer transition-all ${
                isLive
                  ? 'bg-emerald-50 dark:bg-emerald-950/30 ring-1 ring-emerald-200 dark:ring-emerald-800'
                  : 'hover:bg-muted/50'
              }`}
              onClick={() => navigate(`/meet/${meeting.room_id}?eventId=${meeting.event_id}&meetingId=${meeting.id}`)}
            >
              <div className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${
                isLive ? 'bg-emerald-100 dark:bg-emerald-900' : 'bg-primary/10'
              }`}>
                <SvgIcon src={videoChatIcon} className={`w-4 h-4 ${isLive ? 'text-emerald-600 dark:text-emerald-400' : ''}`} />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1.5">
                  <h3 className="font-medium text-sm text-foreground truncate">{meeting.title}</h3>
                  {isLive && (
                    <Badge className="bg-emerald-500 text-white text-[9px] h-4 px-1.5 animate-pulse">LIVE</Badge>
                  )}
                </div>
                <p className="text-[11px] text-muted-foreground truncate">
                  {meeting.event_name || 'Event'}
                </p>
                <div className="flex items-center gap-2 mt-0.5">
                  <span className="text-[10px] text-muted-foreground">{scheduledDate} - {scheduledTime}</span>
                  <span className="text-[10px] text-muted-foreground flex items-center gap-0.5">
                    <Users className="w-2.5 h-2.5" /> {meeting.participant_count}
                  </span>
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};


// ── My Upcoming Tickets Section ──
const MyTicketsSection = ({ navigate }: { navigate: (path: string) => void }) => {
  const [tickets, setTickets] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const loadedRef = useRef(false);
  const [printTicket, setPrintTicket] = useState<any>(null);

  useEffect(() => {
    if (loadedRef.current) return;
    loadedRef.current = true;
    ticketingApi.getMyUpcomingTickets().then((res) => {
      if (res.success && res.data) {
        const data = res.data as any;
        setTickets(data.tickets || []);
      }
    }).catch(() => {}).finally(() => setLoading(false));
  }, []);

  if (loading || tickets.length === 0) return null;

  return (
    <>
      <div className="bg-card rounded-lg border border-border overflow-hidden">
        <div className="px-4 pt-4 pb-2">
          <h2 className="font-semibold text-foreground flex items-center gap-2">
            <img src={TicketIcon} alt="Ticket" className="w-4 h-4 dark:invert" />
            My Tickets
          </h2>
        </div>
        <div className="px-2 pb-3 space-y-1">
          {tickets.map((ticket) => {
            const event = ticket.event;
            const startDate = event?.start_date ? new Date(event.start_date) : null;
            const isToday = startDate && startDate.toDateString() === new Date().toDateString();
            return (
              <div
                key={ticket.id}
                className="flex gap-3 cursor-pointer hover:bg-muted/50 px-2 py-2.5 rounded-lg transition-colors"
                onClick={() => navigate(`/event/${event?.id}`)}
              >
                <div className="relative w-11 h-11 rounded-lg bg-muted flex items-center justify-center overflow-hidden flex-shrink-0">
                  <img src={getEventImage(event)} alt={event?.name} className="w-full h-full object-cover" />
                  {isToday && (
                    <span className="absolute top-0 right-0 w-2.5 h-2.5 bg-green-500 rounded-full border-2 border-card" />
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-1">
                    <h3 className="font-medium text-sm text-foreground truncate">{event?.name}</h3>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setPrintTicket({
                          ticket_code: ticket.ticket_code,
                          event_title: event?.name || 'Event',
                          event_date: event?.start_date,
                          event_time: event?.start_time ? event.start_time.slice(0, 5) : undefined,
                          event_location: event?.location,
                          ticket_class: ticket.ticket_class_name || ticket.ticket_class,
                          quantity: ticket.quantity,
                          buyer_name: ticket.buyer_name,
                          total_amount: ticket.total_amount,
                          currency: ticket.currency,
                          status: ticket.status,
                          cover_image_url: getEventImage(event),
                          checked_in: (ticket as any).checked_in,
                          checked_in_at: (ticket as any).checked_in_at,
                        });
                      }}
                      className="flex-shrink-0 p-1 rounded hover:bg-muted text-muted-foreground hover:text-foreground transition-colors"
                      title="Print ticket"
                    >
                      <img src={PrintIcon} alt="Print" className="w-3.5 h-3.5 dark:invert" />
                    </button>
                  </div>
                  <div className="flex items-center gap-2 mt-0.5">
                    <span className="text-[11px] text-muted-foreground">
                      {startDate
                        ? isToday
                          ? 'Today'
                          : startDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
                        : 'Date TBD'}
                    </span>
                    {event?.start_time && (
                      <span className="text-[11px] text-muted-foreground">
                        - {event.start_time.slice(0, 5)}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-1.5 mt-1">
                    <Badge variant="outline" className="text-[10px] h-4 px-1.5 font-mono tracking-wide">
                      {ticket.ticket_code}
                    </Badge>
                    <span className="text-[10px] h-4 px-1.5 capitalize inline-flex items-center rounded-full border border-border bg-muted text-muted-foreground">
                      {ticket.status}
                    </span>
                    {ticket.quantity > 1 && (
                      <span className="text-[10px] text-muted-foreground">×{ticket.quantity}</span>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {printTicket && (
        <PrintableTicket
          ticket={printTicket}
          open={!!printTicket}
          onClose={() => setPrintTicket(null)}
        />
      )}
    </>
  );
};

const RightSidebar = ({ onNavigate }: { onNavigate?: () => void } = {}) => {
  const { t } = useLanguage();
  const rawNavigate = useNavigate();
  const navigate = useCallback((path: string) => {
    rawNavigate(path);
    onNavigate?.();
  }, [rawNavigate, onNavigate]);
  const { events, loading: eventsLoading } = useEvents();
  const { services, loading: servicesLoading } = useServices();
  const { suggestions, loading: suggestionsLoading } = useFollowSuggestions(3);
  const { circles, addMember, createCircle } = useCircles();
  const [addingUserId, setAddingUserId] = useState<string | null>(null);
  const [addedUserIds, setAddedUserIds] = useState<Set<string>>(new Set());
  const [hiddenSuggestionIds, setHiddenSuggestionIds] = useState<Set<string>>(new Set());

  const [committeeEvents, setCommitteeEvents] = useState<any[]>([]);
  const [invitedEvents, setInvitedEvents] = useState<any[]>([]);
  const [extraLoading, setExtraLoading] = useState(true);
  const extraLoadedRef = useRef(false);

  const fetchExtra = useCallback(async () => {
    try {
      const [commRes, invRes] = await Promise.all([
        eventsApi.getCommitteeEvents({ limit: 5 }),
        eventsApi.getInvitedEvents({ limit: 5 }),
      ]);
      if (commRes.success) setCommitteeEvents(commRes.data.events || []);
      if (invRes.success) setInvitedEvents(invRes.data.events || []);
    } catch { /* silent */ }
    finally {
      if (!extraLoadedRef.current) {
        extraLoadedRef.current = true;
        setExtraLoading(false);
      }
    }
  }, []);

  // Initial fetch
  useEffect(() => {
    fetchExtra();
  }, [fetchExtra]);

  // Background poll every 15s to keep sidebar data fresh
  useEffect(() => {
    const id = setInterval(() => { fetchExtra(); }, 15000);
    return () => clearInterval(id);
  }, [fetchExtra]);

  const handleAddToCircle = async (user: any) => {
    if (addingUserId) return;
    setAddingUserId(user.id);
    try {
      let circleId = circles[0]?.id;
      if (!circleId) {
        const newCircle = await createCircle({ name: 'My Circle', description: 'My close friends' });
        circleId = newCircle?.id;
      }
      if (!circleId) throw new Error('No circle');
      await addMember(circleId, user.id);
      setAddedUserIds(prev => new Set([...prev, user.id]));
      setHiddenSuggestionIds(prev => new Set([...prev, user.id]));
      toast.success(`Circle request sent to ${user.first_name}`);
    } catch {
      toast.error('Failed to add to circle');
    } finally {
      setAddingUserId(null);
    }
  };

  // Merge & deduplicate events by ID, prioritizing creator > committee > guest
  // Filter out: past events, declined/cancelled invitations
  const now = new Date();
  const upcomingEvents = useMemo<UpcomingEvent[]>(() => {
    const map = new Map<string, UpcomingEvent>();

    for (const ev of (events || [])) {
      map.set(ev.id, { id: ev.id, title: ev.title, start_date: ev.start_date, cover_image: ev.cover_image, status: ev.status, role: 'creator', sells_tickets: (ev as any).sells_tickets, ticket_approval_status: (ev as any).ticket_approval_status });
    }
    for (const ev of committeeEvents) {
      if (!map.has(ev.id)) {
        const img = ev.cover_image || (ev.images?.length > 0 ? (ev.images.find((i: any) => i.is_featured)?.image_url || ev.images[0]?.image_url || ev.images[0]?.url) : null) || ev.cover_image_url;
        map.set(ev.id, { id: ev.id, title: ev.title || ev.name, start_date: ev.start_date, cover_image: img, status: ev.status, role: 'committee' });
      }
    }
    for (const ev of invitedEvents) {
      if (!map.has(ev.id)) {
        const rsvpStatus = (ev.rsvp_status || ev.invitation_status || '').toLowerCase();
        // Skip declined/rejected invitations
        if (['declined', 'rejected', 'not_attending'].includes(rsvpStatus)) continue;
        map.set(ev.id, { id: ev.id, title: ev.title || ev.name, start_date: ev.start_date, cover_image: ev.cover_image || ev.cover_image_url, status: ev.status, role: 'guest' });
      }
    }

    return Array.from(map.values())
      .filter((ev) => {
        if (ev.start_date && new Date(ev.start_date) < now) return false;
        if (ev.status?.toLowerCase() === 'cancelled') return false;
        // Hide ticketed events that aren't approved from sidebar
        if (ev.sells_tickets && ev.ticket_approval_status !== 'approved') return false;
        return true;
      })
      .sort((a, b) => {
        if (!a.start_date) return 1;
        if (!b.start_date) return -1;
        return new Date(a.start_date).getTime() - new Date(b.start_date).getTime();
      });
  }, [events, committeeEvents, invitedEvents]);

  const displayedEvents = upcomingEvents.slice(0, 6);
  const hasMoreEvents = upcomingEvents.length > 6;

  const allLoading = (eventsLoading || extraLoading) && displayedEvents.length === 0;

  // Track if we've ever loaded data to avoid skeleton flicker on re-mount
  const hasLoadedServices = services.length > 0 || !servicesLoading;
  const hasLoadedSuggestions = suggestions.length > 0 || !suggestionsLoading;

  return (
    <div className="space-y-6">
      {/* Upcoming Events — only show when loading or there are events */}
      {allLoading ? (
        <SidebarCardSkeleton title="Upcoming Events" count={3} />
      ) : displayedEvents.length > 0 ? (
        <div className="bg-card rounded-lg p-4 border border-border">
          <h2 className="font-semibold text-foreground mb-4">Upcoming Events</h2>
          <div className="space-y-3">
            {displayedEvents.map((event) => {
              const roleLabel = ROLE_LABELS[event.role];
              const roleBg = event.role === 'creator' ? 'bg-primary' : event.role === 'committee' ? 'bg-amber-500' : 'bg-blue-500';
              return (
              <div key={event.id} className="flex gap-3 cursor-pointer hover:bg-muted/50 p-2 rounded-lg transition-colors"
                onClick={() => navigate(event.role === 'guest' ? `/event/${event.id}` : `/event-management/${event.id}`)}
              >
                <div className="relative w-12 h-12 rounded-lg bg-muted flex items-center justify-center overflow-hidden flex-shrink-0">
                  <img src={getEventImage(event)} alt={event.title} className="w-full h-full object-cover" />
                  <span className={`absolute bottom-0 left-0 right-0 text-[7px] font-semibold text-white text-center py-0.5 ${roleBg}`}>
                    {roleLabel}
                  </span>
                </div>
                <div className="flex-1 min-w-0">
                  <h3 className="font-medium text-sm text-foreground truncate">{event.title}</h3>
                  <p className="text-xs text-muted-foreground">
                    {event.start_date ? new Date(event.start_date).toLocaleDateString('en-US', { 
                      weekday: 'short', 
                      month: 'short', 
                      day: 'numeric' 
                    }) : 'Date TBD'}
                  </p>
                </div>
              </div>
              );
            })}
          </div>
          {hasMoreEvents && (
            <Button
              variant="ghost"
              size="sm"
              className="w-full mt-3 text-xs text-primary hover:text-primary/80"
              onClick={() => navigate('/my-events')}
            >
              View all events →
            </Button>
          )}
        </div>
      ) : null /* No card when no upcoming events */}

      {/* My Meetings */}
      <MyMeetingsSection navigate={navigate} />

      {/* My Upcoming Tickets */}
      <MyTicketsSection navigate={navigate} />

      {/* Service Providers */}
      {servicesLoading && !hasLoadedServices ? (
        <SidebarCardSkeleton title="Service Providers" count={4} />
      ) : services.length > 0 ? (
        <div className="bg-card rounded-lg p-4 border border-border">
          <h2 className="font-semibold text-foreground mb-4">Service Providers</h2>
          <div className="grid grid-cols-2 gap-3">
            {services.slice(0, 4).map((service: any) => {
              const imgUrl = service.primary_image?.thumbnail_url 
                || service.primary_image?.url 
                || service.primary_image 
                || service.images?.[0]?.thumbnail_url 
                || service.images?.[0]?.url 
                || service.images?.[0]
                || service.cover_image
                || service.image_url
                || service.media?.[0]?.url
                || service.media?.[0]?.thumbnail_url;
              const title = service.title || service.name || service.service_category?.name || 'Service';
              const initials = title.split(' ').map((w: string) => w[0]).join('').slice(0, 2).toUpperCase();
              return (
                <div key={service.id} className="text-center cursor-pointer hover:bg-muted/50 p-2 rounded-lg transition-colors" onClick={() => navigate(`/services/view/${service.id}`)}>
                  <div className="w-16 h-16 rounded-lg bg-muted mx-auto mb-2 overflow-hidden flex items-center justify-center">
                    {imgUrl ? (
                      <img
                        src={imgUrl}
                        alt={title}
                        className="w-full h-full object-cover"
                      />
                    ) : (
                      <span className="text-sm font-semibold text-muted-foreground">{initials}</span>
                    )}
                  </div>
                  <p className="text-xs font-medium text-foreground capitalize line-clamp-2 flex items-center gap-1">{title}</p>
                </div>
              );
            })}
          </div>
        </div>
      ) : (
        <div className="bg-card rounded-lg p-4 border border-border">
          <h2 className="font-semibold text-foreground mb-4">Service Providers</h2>
          <div className="grid grid-cols-2 gap-3">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="text-center p-2 rounded-lg border border-dashed border-border/50">
                <div className="w-16 h-16 rounded-lg bg-muted/50 mx-auto mb-2 flex items-center justify-center">
                  <div className="w-8 h-8 rounded bg-muted" />
                </div>
                <div className="h-3 w-12 bg-muted/50 rounded mx-auto" />
              </div>
            ))}
          </div>
          <p className="text-xs text-muted-foreground text-center mt-3">No providers yet</p>
        </div>
      )}

      {/* Friend Suggestions / People You May Know */}
      {suggestionsLoading && !hasLoadedSuggestions ? (
        <SidebarCardSkeleton title="People You May Know" count={3} />
      ) : suggestions.filter(u => !hiddenSuggestionIds.has(u.id)).length > 0 ? (
        <div className="bg-card rounded-lg p-4 border border-border">
          <h2 className="font-semibold text-foreground mb-4">People You May Know</h2>
          <div className="space-y-3">
            {suggestions.filter(u => !hiddenSuggestionIds.has(u.id)).map((user) => (
              <div key={user.id} className="flex items-center gap-3">
                <div 
                  className="w-10 h-10 rounded-full bg-muted overflow-hidden flex items-center justify-center cursor-pointer"
                  onClick={() => navigate(`/u/${(user as any).username || user.id}?from=add`)}
                >
                  {user.avatar ? (
                    <img
                      src={user.avatar}
                      alt={user.first_name}
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <span className="text-sm font-medium text-muted-foreground">
                      {user.first_name?.[0]}{user.last_name?.[0]}
                    </span>
                  )}
                </div>
                <div 
                  className="flex-1 min-w-0 cursor-pointer"
                  onClick={() => navigate(`/u/${(user as any).username || user.id}?from=add`)}
                >
                  <h3 className="font-medium text-sm text-foreground hover:underline">
                    {user.first_name} {user.last_name}
                  </h3>
                  <p className="text-xs text-muted-foreground">
                    {(user as any).mutual_count || 0} mutual friends
                  </p>
                </div>
                <Button
                  size="sm"
                  variant={addedUserIds.has(user.id) ? "default" : "outline"}
                  className="text-xs shrink-0"
                  onClick={() => handleAddToCircle(user)}
                  disabled={!!addingUserId || addedUserIds.has(user.id)}
                >
                  {addingUserId === user.id ? (
                    <Loader2 className="w-3 h-3 animate-spin" />
                  ) : addedUserIds.has(user.id) ? (
                    "Sent ✓"
                  ) : (
                    t("add")
                  )}
                </Button>
              </div>
            ))}
          </div>
        </div>
      ) : null}

      {/* Ticket-Selling Events */}
      <TicketEventsSection navigate={navigate} />

      {/* Promoted Events - placeholder */}
      <div className="bg-card rounded-lg p-4 border border-border">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold text-foreground">Promoted Events</h2>
          <span className="text-xs text-muted-foreground">Sponsored</span>
        </div>
        <div className="space-y-4">
          <div className="p-3 rounded-lg border border-dashed border-border/50">
            <div className="w-full h-24 rounded-lg bg-muted/50 mb-3 flex items-center justify-center">
              <img src={CalendarIcon} alt="Calendar" className="w-8 h-8 opacity-50" />
            </div>
            <div className="space-y-2">
              <div className="h-4 w-3/4 bg-muted/50 rounded" />
              <div className="flex items-center gap-1">
                <img src={CalendarIcon} alt="Calendar" className="w-3 h-3 opacity-50" />
                <div className="h-3 w-20 bg-muted/30 rounded" />
              </div>
              <div className="flex items-center gap-1">
                <img src={LocationIcon} alt="Location" className="w-3 h-3 opacity-50" />
                <div className="h-3 w-24 bg-muted/30 rounded" />
              </div>
              <div className="flex items-center gap-1">
                <Users className="w-3 h-3 text-muted" />
                <div className="h-3 w-16 bg-muted/30 rounded" />
              </div>
            </div>
          </div>
        </div>
        <p className="text-xs text-muted-foreground text-center mt-3">No promoted events</p>
      </div>
    </div>
  );
};

export default RightSidebar;
