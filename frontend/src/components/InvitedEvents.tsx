import { useState, useEffect, useCallback } from 'react';
import { Clock, CheckCircle, XCircle, HelpCircle, Loader2, Timer } from 'lucide-react';
import QrIcon from '@/assets/icons/qr-icon.svg';
import SvgIcon from '@/components/ui/svg-icon';
import CalendarIcon from '@/assets/icons/calendar-icon.svg';
import LocationIcon from '@/assets/icons/location-icon.svg';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { useNavigate } from 'react-router-dom';
import { eventsApi } from '@/lib/api/events';
import { toast } from 'sonner';
import { showCaughtError } from '@/lib/api';
import InvitationCard from './InvitationCard';
import { getEventCountdown } from '@/utils/getEventCountdown';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import { getEventImage } from '@/lib/eventImage';
import { getEventOwnerName } from '@/lib/eventOwner';

const rsvpStyles: Record<string, string> = {
  pending: 'bg-amber-100 text-amber-800',
  confirmed: 'bg-green-100 text-green-800',
  declined: 'bg-destructive/10 text-destructive',
  maybe: 'bg-blue-100 text-blue-800',
};

const rsvpIcons: Record<string, any> = {
  pending: HelpCircle,
  confirmed: CheckCircle,
  declined: XCircle,
  maybe: HelpCircle,
};

const InvitedEvents = () => {
  const { t } = useLanguage();
  const navigate = useNavigate();
  const [events, setEvents] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  const [qrEventId, setQrEventId] = useState<string | null>(null);
  const [respondingAction, setRespondingAction] = useState<{ eventId: string; status: string } | null>(null);

  const fetchInvited = useCallback(async () => {
    setLoading(true);
    try {
      const response = await eventsApi.getInvitedEvents();
      if (response.success) {
        setEvents(response.data?.events || []);
      } else {
        setError(response.message);
      }
    } catch {
      setError('Failed to load invited events');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchInvited(); }, [fetchInvited]);

  const handleRSVP = async (eventId: string, rsvpStatus: 'confirmed' | 'declined') => {
    setRespondingAction({ eventId, status: rsvpStatus });
    try {
      const response = await eventsApi.respondToInvitation(eventId, { rsvp_status: rsvpStatus });
      if (response.success) {
        toast.success(rsvpStatus === 'confirmed' ? 'You have accepted the invitation!' : 'You have declined the invitation.');
        // Update local state
        setEvents(prev => prev.map(ev =>
          ev.id === eventId
            ? { ...ev, invitation: { ...ev.invitation, rsvp_status: rsvpStatus } }
            : ev
        ));
      } else {
        toast.error(response.message || 'Failed to update RSVP');
      }
    } catch (err: any) {
      showCaughtError(err, 'Failed to respond to invitation');
    } finally {
      setRespondingAction(null);
    }
  };

  if (loading) {
    return (
      <div className="space-y-4">
        {[1, 2].map(i => (
          <div key={i} className="bg-card rounded-lg border border-border p-4">
            <div className="flex gap-4">
              <Skeleton className="w-32 h-24 rounded-lg" />
              <div className="flex-1 space-y-2">
                <Skeleton className="h-6 w-48" />
                <Skeleton className="h-4 w-32" />
                <Skeleton className="h-4 w-full" />
              </div>
            </div>
          </div>
        ))}
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-center py-8">
        <p className="text-destructive mb-4">{error}</p>
        <Button onClick={fetchInvited}>Retry</Button>
      </div>
    );
  }

  if (events.length === 0) {
    return (
      <div className="text-center py-12">
        <img src={CalendarIcon} alt="Calendar" className="w-12 h-12 mx-auto mb-4" />
        <p className="text-muted-foreground">You haven't been invited to any events yet.</p>
      </div>
    );
  }

  return (
    <>
      <div className="space-y-4">
        {events.map((event) => {
          const rsvpStatus = event.invitation?.rsvp_status || 'pending';
          const RsvpIcon = rsvpIcons[rsvpStatus] || HelpCircle;
          const isResponding = respondingAction?.eventId === event.id;
          const respondingStatus = respondingAction?.eventId === event.id ? respondingAction.status : null;

          return (
            <article
              key={event.id}
              className="bg-card rounded-lg border border-border transition-colors relative cursor-pointer hover:border-primary/30"
              onClick={() => navigate(`/event/${event.id}`)}
            >
              {/* Diagonal status badge */}
              <div className="absolute top-0 right-0 z-10 overflow-hidden rounded-tr-lg" style={{ width: '90px', height: '90px', pointerEvents: 'none' }}>
                <div className={`absolute ${rsvpStatus === 'confirmed' ? 'bg-green-500' : rsvpStatus === 'declined' ? 'bg-red-500' : rsvpStatus === 'maybe' ? 'bg-blue-500' : 'bg-amber-500'}`}
                  style={{
                    width: '140px', textAlign: 'center', transform: 'rotate(45deg)',
                    top: '16px', right: '-36px',
                    padding: '3px 0', fontSize: '10px', fontWeight: 600, color: 'white', letterSpacing: '0.5px',
                    boxShadow: '0 1px 3px rgba(0,0,0,0.2)'
                  }}
                >
                  {rsvpStatus.charAt(0).toUpperCase() + rsvpStatus.slice(1)}
                </div>
              </div>
              <div className="p-4">
                <div className="flex flex-col sm:flex-row gap-4">
                  <div className="w-full sm:w-32 h-24 flex-shrink-0 rounded-lg overflow-hidden bg-muted/10">
                    <img src={getEventImage(event)} alt={event.title} className="w-full h-full object-cover" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <h3 className="font-semibold text-base text-foreground">{event.title}</h3>
                        {event.event_type && (
                          <span className="inline-flex items-center px-2 py-0.5 rounded-md bg-primary/10 text-primary text-xs font-medium mt-1">
                            {event.event_type.name}
                          </span>
                        )}
                      </div>
                    </div>

                    <div className="flex flex-wrap items-center gap-3 text-sm text-muted-foreground mt-3">
                      {event.start_date && (
                        <span className="flex items-center gap-1">
                          <img src={CalendarIcon} alt="Calendar" className="w-4 h-4" />
                          {new Date(event.start_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })}
                        </span>
                      )}
                      {(() => {
                        const countdown = getEventCountdown(event.start_date);
                        if (!countdown) return null;
                        return (
                          <span className={`flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-full ${countdown.isPast ? 'bg-muted text-muted-foreground' : 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300'}`}>
                            <Timer className="w-3 h-3" />
                            {countdown.text}
                          </span>
                        );
                      })()}
                      {event.start_time && (
                        <span className="flex items-center gap-1">
                          <Clock className="w-4 h-4" />
                          {event.start_time}
                        </span>
                      )}
                      {event.location && (
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            navigate(`/event/${event.id}#venue`);
                          }}
                          className="flex items-center gap-1 text-primary hover:text-primary/80 hover:underline transition-colors cursor-pointer"
                          title="View venue on map"
                        >
                          <img src={LocationIcon} alt="Location" className="w-4 h-4" />
                          {event.location}
                        </button>
                      )}
                    </div>

                    {(() => {
                      const ownerName = getEventOwnerName(event as any);
                      return ownerName ? (
                        <p className="text-sm text-muted-foreground mt-2">
                          Organized by <span className="font-medium text-foreground">{ownerName}</span>
                        </p>
                      ) : null;
                    })()}

                    {/* RSVP Action Buttons */}
                    <div className="flex flex-wrap items-center gap-2 mt-3">
                      {rsvpStatus === 'pending' && (
                        <>
                          <Button
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation();
                              handleRSVP(event.id, 'confirmed');
                            }}
                            disabled={isResponding}
                            className="gap-1.5"
                          >
                            {respondingStatus === 'confirmed' ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle className="w-4 h-4" />}
                            Accept
                          </Button>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={(e) => {
                              e.stopPropagation();
                              handleRSVP(event.id, 'declined');
                            }}
                            disabled={isResponding}
                            className="gap-1.5 text-destructive hover:text-destructive"
                          >
                            {respondingStatus === 'declined' ? <Loader2 className="w-4 h-4 animate-spin" /> : <XCircle className="w-4 h-4" />}
                            Decline
                          </Button>
                        </>
                      )}
                      {rsvpStatus === 'confirmed' && (
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={(e) => {
                            e.stopPropagation();
                            handleRSVP(event.id, 'declined');
                          }}
                          disabled={isResponding}
                          className="gap-1.5 text-destructive hover:text-destructive"
                        >
                          {respondingStatus === 'declined' ? <Loader2 className="w-4 h-4 animate-spin" /> : <XCircle className="w-4 h-4" />}
                          Cancel RSVP
                        </Button>
                      )}
                      {rsvpStatus === 'declined' && (
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={(e) => {
                            e.stopPropagation();
                            handleRSVP(event.id, 'confirmed');
                          }}
                          disabled={isResponding}
                          className="gap-1.5"
                        >
                          {respondingStatus === 'confirmed' ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle className="w-4 h-4" />}
                          Accept Instead
                        </Button>
                      )}
                      {rsvpStatus === 'confirmed' && (
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={(e) => {
                            e.stopPropagation();
                            setQrEventId(event.id);
                          }}
                          className="gap-1.5"
                        >
                          <SvgIcon src={QrIcon} alt="QR" className="w-4 h-4" />
                          View Invitation
                        </Button>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            </article>
          );
        })}
      </div>

      {qrEventId && (
        <InvitationCard
          eventId={qrEventId}
          open={!!qrEventId}
          onClose={() => setQrEventId(null)}
        />
      )}
    </>
  );
};

export default InvitedEvents;
