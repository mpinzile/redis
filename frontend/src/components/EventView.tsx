import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { ChevronLeft, Clock, Users, CheckCircle, XCircle, Loader2, Camera, Images, Edit2, FileText, Navigation } from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import CalendarIcon from '@/assets/icons/calendar-icon.svg';
import LocationIcon from '@/assets/icons/location-icon.svg';
import { motion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { eventsApi } from '@/lib/api/events';
import { photoLibrariesApi } from '@/lib/api/photoLibraries';
import type { PhotoLibrary } from '@/lib/api/photoLibraries';
import { toast } from 'sonner';
import { showCaughtError } from '@/lib/api';
import EventTicketPurchase from './EventTicketPurchase';
import ReportPreviewDialog from '@/components/ReportPreviewDialog';
import { generateEventReportHtml } from '@/utils/generateEventReport';
import { useCurrentUser } from '@/hooks/useCurrentUser';
import { getEventImage } from '@/lib/eventImage';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import VenueMapPreview from '@/components/VenueMapPreview';
import DirectionsMapDialog from '@/components/DirectionsMapDialog';

const EventView = () => {
  const { t } = useLanguage();
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: currentUser } = useCurrentUser();
  const [event, setEvent] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [respondingStatus, setRespondingStatus] = useState<string | null>(null);
  const [rsvpStatus, setRsvpStatus] = useState<string>('pending');
  
  const [hasInvitation, setHasInvitation] = useState(false);
  const [photoLibraries, setPhotoLibraries] = useState<PhotoLibrary[]>([]);
  const [reportPreviewOpen, setReportPreviewOpen] = useState(false);
  const [reportHtml, setReportHtml] = useState('');
  const [directionsOpen, setDirectionsOpen] = useState(false);

  const hasVenueCoordinates = Boolean(
    event?.venue_coordinates?.latitude && event?.venue_coordinates?.longitude,
  );

  const handleOpenDirections = () => {
    if (!hasVenueCoordinates) {
      toast.error('Directions are only available when the event venue has map coordinates.');
      return;
    }

    setDirectionsOpen(true);
  };

  const fetchEvent = useCallback(async () => {
    if (!id) return;
    try {
      const res = await eventsApi.getById(id);
      if (res.success && res.data) {
        setEvent(res.data);
      }
    } catch {
      toast.error('Failed to load event');
    } finally {
      setLoading(false);
    }
  }, [id]);

  // Also fetch invitation status
  useEffect(() => {
    if (!id) return;
    eventsApi.getInvitedEvents({ limit: 100 }).then(res => {
      if (res.success) {
        const inv = res.data?.events?.find((e: any) => e.id === id);
        if (inv?.invitation) {
          setHasInvitation(true);
          if (inv.invitation.rsvp_status) {
            setRsvpStatus(inv.invitation.rsvp_status);
          }
        }
      }
    }).catch(() => {});
  }, [id]);

  useEffect(() => { fetchEvent(); }, [fetchEvent]);

  // Fetch photo libraries when the event creator views the event
  useEffect(() => {
    if (!id || !event || !currentUser) return;
    const isCreator = event.organizer_id === currentUser.id || event.organizer?.id === currentUser.id;
    if (!isCreator) return;
    photoLibrariesApi.getEventLibraries(id).then(res => {
      if (res.success && res.data?.libraries?.length) {
        setPhotoLibraries(res.data.libraries);
      }
    }).catch(() => {});
  }, [id, event, currentUser]);

  const handleRSVP = async (status: 'confirmed' | 'declined') => {
    if (!id) return;
    setRespondingStatus(status);
    try {
      const res = await eventsApi.respondToInvitation(id, { rsvp_status: status });
      if (res.success) {
        setRsvpStatus(status);
        toast.success(status === 'confirmed' ? 'You have accepted the invitation!' : 'You have declined the invitation.');
      } else {
        toast.error(res.message || 'Failed to update RSVP');
      }
    } catch (err: any) {
      showCaughtError(err, 'Failed to respond');
    } finally {
      setRespondingStatus(null);
    }
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-64 w-full rounded-xl" />
        <Skeleton className="h-10 w-2/3" />
        <Skeleton className="h-6 w-1/2" />
        <div className="grid grid-cols-2 gap-4">
          <Skeleton className="h-24 rounded-lg" />
          <Skeleton className="h-24 rounded-lg" />
        </div>
      </div>
    );
  }

  if (!event) {
    return (
      <div className="text-center py-16">
        <p className="text-muted-foreground mb-4">Event not found or you don't have access.</p>
        <Button variant="outline" onClick={() => navigate(-1)}>Go Back</Button>
      </div>
    );
  }

  const coverImage = getEventImage(event);

  const isCreator = !!(currentUser && event && (event.organizer_id === currentUser.id || event.organizer?.id === currentUser.id));

  const handleGenerateReport = () => {
    if (!event) return;
    const html = generateEventReportHtml({
      title: event.title,
      description: event.description,
      event_type: event.event_type?.name,
      start_date: event.start_date,
      start_time: event.start_time,
      location: event.location,
      venue: event.venue,
      status: event.status,
    });
    setReportHtml(html);
    setReportPreviewOpen(true);
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <h1 className="flex-1 min-w-0 text-lg sm:text-2xl md:text-3xl font-bold break-words leading-tight">
            {event.title || 'Event Details'}
          </h1>
          <Button variant="ghost" size="icon" className="flex-shrink-0" onClick={() => navigate(-1)} aria-label="Back">
            <ChevronLeft className="w-5 h-5" />
          </Button>
        </div>
        {isCreator && (
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => navigate(`/create-event?edit=${id}`)} className="gap-1.5">
              <Edit2 className="w-4 h-4" />
              <span className="hidden sm:inline">Edit</span>
              <span className="sm:hidden">Edit</span>
            </Button>
            <Button variant="outline" size="sm" onClick={handleGenerateReport} className="gap-1.5">
              <FileText className="w-4 h-4" />
              Report
            </Button>
          </div>
        )}
      </div>

      {/* Cover Image */}
      {coverImage && (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="relative w-full rounded-xl overflow-hidden bg-muted/30"
        >
          <img
            src={coverImage}
            alt={event.title}
            className="w-full h-auto block"
          />
          <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent" />
          <div className="absolute bottom-4 left-4 right-4">
            <Badge className="bg-primary/90 text-primary-foreground mb-2">
              {event.event_type?.name || 'Event'}
            </Badge>
            <h1 className="text-2xl sm:text-3xl font-bold text-white">{event.title}</h1>
          </div>
        </motion.div>
      )}

      {!coverImage && (
        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
          <h1 className="text-2xl sm:text-3xl font-bold text-foreground">{event.title}</h1>
          {event.event_type?.name && (
            <Badge variant="outline" className="mt-2">{event.event_type.name}</Badge>
          )}
        </motion.div>
      )}

      {/* RSVP Status & Actions - only show if user has an invitation */}
      {hasInvitation && (
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
        >
          <Card className="border-primary/20 bg-primary/5">
            <CardContent className="p-5">
              <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-medium text-muted-foreground mb-1">Your RSVP Status</p>
                  <Badge className={
                    rsvpStatus === 'confirmed' ? 'bg-green-100 text-green-800' :
                    rsvpStatus === 'declined' ? 'bg-destructive/10 text-destructive' :
                    'bg-amber-100 text-amber-800'
                  }>
                    {rsvpStatus === 'confirmed' && <CheckCircle className="w-3 h-3 mr-1" />}
                    {rsvpStatus === 'declined' && <XCircle className="w-3 h-3 mr-1" />}
                    {rsvpStatus.charAt(0).toUpperCase() + rsvpStatus.slice(1)}
                  </Badge>
                </div>
                <div className="flex flex-wrap gap-2">
                  {rsvpStatus === 'pending' && (
                    <>
                      <Button size="sm" onClick={() => handleRSVP('confirmed')} disabled={!!respondingStatus} className="gap-1.5">
                        {respondingStatus === 'confirmed' ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle className="w-4 h-4" />}
                        Accept
                      </Button>
                      <Button size="sm" variant="outline" onClick={() => handleRSVP('declined')} disabled={!!respondingStatus} className="gap-1.5 text-destructive hover:text-destructive">
                        {respondingStatus === 'declined' ? <Loader2 className="w-4 h-4 animate-spin" /> : <XCircle className="w-4 h-4" />}
                        Decline
                      </Button>
                    </>
                  )}
                  {rsvpStatus === 'confirmed' && (
                    <>
                      <Button size="sm" variant="outline" onClick={() => handleRSVP('declined')} disabled={!!respondingStatus} className="gap-1.5 text-destructive hover:text-destructive">
                        {respondingStatus === 'declined' ? <Loader2 className="w-4 h-4 animate-spin" /> : <XCircle className="w-4 h-4" />}
                        Cancel RSVP
                      </Button>
                    </>
                  )}
                  {rsvpStatus === 'declined' && (
                    <Button size="sm" variant="outline" onClick={() => handleRSVP('confirmed')} disabled={!!respondingStatus} className="gap-1.5">
                      {respondingStatus === 'confirmed' ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle className="w-4 h-4" />}
                      Accept Instead
                    </Button>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>
        </motion.div>
      )}

      {/* Event Details */}
      <motion.div
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.2 }}
        className="grid grid-cols-1 sm:grid-cols-2 gap-4"
      >
        {event.start_date && (
          <Card>
            <CardContent className="p-4 flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                <img src={CalendarIcon} alt="Date" className="w-5 h-5" />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Date</p>
                <p className="font-medium text-foreground">
                  {new Date(event.start_date).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}
                </p>
              </div>
            </CardContent>
          </Card>
        )}

        {event.start_time && (
          <Card>
            <CardContent className="p-4 flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                <Clock className="w-5 h-5 text-primary" />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Time</p>
                <p className="font-medium text-foreground">{event.start_time}</p>
              </div>
            </CardContent>
          </Card>
        )}

        {(event.location || event.venue) && (
          <Card className="sm:col-span-2">
            <CardContent className="p-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                  <img src={LocationIcon} alt="Location" className="w-5 h-5" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-muted-foreground">Location</p>
                  <p className="font-medium text-foreground">{event.venue || event.location}</p>
                  {event.venue && event.location && event.venue !== event.location && (
                    <p className="text-sm text-muted-foreground">{event.location}</p>
                  )}
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  className="shrink-0 rounded-xl gap-1.5"
                  onClick={handleOpenDirections}
                >
                  <Navigation className="w-3.5 h-3.5" />
                  Directions
                </Button>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Venue Map */}
        {event.venue_coordinates?.latitude && event.venue_coordinates?.longitude && (
          <Card className="sm:col-span-2 overflow-hidden p-0">
            <VenueMapPreview
              latitude={parseFloat(event.venue_coordinates.latitude)}
              longitude={parseFloat(event.venue_coordinates.longitude)}
              venueName={event.venue || event.location}
              address={event.venue_address || event.location}
              height="220px"
              onDirections={handleOpenDirections}
            />
          </Card>
        )}

        {event.total_guests > 0 && (
          <Card>
            <CardContent className="p-4 flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                <Users className="w-5 h-5 text-primary" />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Guests</p>
                <p className="font-medium text-foreground">{event.confirmed_guests || 0} confirmed of {event.total_guests}</p>
              </div>
            </CardContent>
          </Card>
        )}
      </motion.div>

      {/* Ticket Purchase Section */}
      {id && event.sells_tickets && (
        <EventTicketPurchase eventId={id} eventName={event.title} event={event} />
      )}

      {/* Description */}
      {event.description && (
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3 }}
        >
          <Card>
            <CardContent className="p-5">
              <h2 className="font-semibold text-foreground mb-2">About This Event</h2>
              <p className="text-muted-foreground whitespace-pre-wrap">{event.description}</p>
            </CardContent>
          </Card>
        </motion.div>
      )}

      {/* What to Expect */}
      {((Array.isArray(event.what_to_expect) && event.what_to_expect.length > 0) || (event.what_to_expect_notes && String(event.what_to_expect_notes).trim().length > 0)) && (
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.32 }}
        >
          <Card>
            <CardContent className="p-5">
              <h2 className="font-semibold text-foreground mb-3">What to Expect</h2>
              {Array.isArray(event.what_to_expect) && event.what_to_expect.length > 0 && (
                <ul className="space-y-3 mb-3">
                  {event.what_to_expect.map((it: any, idx: number) => {
                    const label = (it?.label || it?.title || '').toString().trim();
                    if (!label) return null;
                    const desc = (it?.description || '').toString().trim();
                    return (
                      <li key={idx} className="flex items-start gap-3">
                        <span className="mt-1.5 h-2 w-2 rounded-full bg-primary shrink-0" />
                        <div>
                          <p className="text-sm font-medium text-foreground">{label}</p>
                          {desc && <p className="text-sm text-muted-foreground">{desc}</p>}
                        </div>
                      </li>
                    );
                  })}
                </ul>
              )}
              {event.what_to_expect_notes && (
                <p className="text-sm text-muted-foreground whitespace-pre-wrap">{event.what_to_expect_notes}</p>
              )}
            </CardContent>
          </Card>
        </motion.div>
      )}


      {/* Guest of Honor */}
      {(event as any).guest_of_honor && (
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.32 }}
        >
          <Card>
            <CardContent className="p-5">
              <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Guest of Honor</h3>
              <p className="text-foreground text-lg font-semibold mt-1">{(event as any).guest_of_honor}</p>
            </CardContent>
          </Card>
        </motion.div>
      )}

      {/* Additional details - flexible label/details rows, with legacy
          dress_code / special_instructions as fallback when no extra_details
          are recorded yet. */}
      {(() => {
        const rawExtras = (event as any).extra_details;
        const rows: Array<{ label: string; details: string }> = [];
        if (Array.isArray(rawExtras)) {
          for (const it of rawExtras) {
            const label = String(it?.label || '').trim();
            const details = String(it?.details || it?.description || '').trim();
            if (label && details) rows.push({ label, details });
          }
        }
        if (rows.length === 0) {
          if (event.dress_code) rows.push({ label: 'Dress Code', details: event.dress_code });
          if (event.special_instructions) rows.push({ label: 'Special Instructions', details: event.special_instructions });
        }
        if (rows.length === 0) return null;
        return (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.35 }}
          >
            <Card>
              <CardContent className="p-5 divide-y divide-border">
                {rows.map((r, i) => (
                  <div key={i} className={i === 0 ? 'pb-3' : 'py-3 last:pb-0'}>
                    <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{r.label}</h3>
                    <p className="text-foreground mt-1 whitespace-pre-line">{r.details}</p>
                  </div>
                ))}
              </CardContent>
            </Card>
          </motion.div>
        );
      })()}

      {/* Schedule */}
      {event.schedule?.length > 0 && (
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4 }}
        >
          <Card>
            <CardContent className="p-5">
              <h2 className="font-semibold text-foreground mb-4">Event Schedule</h2>
              <div className="space-y-3">
                {event.schedule.map((item: any) => (
                  <div key={item.id} className="flex gap-3 items-start">
                    <div className="w-16 text-sm font-medium text-primary flex-shrink-0">
                      {item.start_time ? new Date(item.start_time).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : ''}
                    </div>
                    <div className="flex-1 border-l-2 border-primary/20 pl-3">
                      <p className="font-medium text-foreground">{item.title}</p>
                      {item.description && <p className="text-sm text-muted-foreground">{item.description}</p>}
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </motion.div>
      )}

      {/* Photo Libraries - shown to event creator when photography provider has uploaded */}
      {photoLibraries.length > 0 && (
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.45 }}
        >
          <Card className="border-primary/20">
            <CardContent className="p-5">
              <div className="flex items-center gap-2 mb-4">
                <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center">
                  <Camera className="w-5 h-5 text-primary" />
                </div>
                <div>
                  <h2 className="font-semibold text-foreground">Event Photo Libraries</h2>
                  <p className="text-xs text-muted-foreground">Uploaded by your photography service provider(s)</p>
                </div>
              </div>
              <div className="space-y-3">
                {photoLibraries.map((lib) => (
                  <Link
                    key={lib.id}
                    to={`/photo-library/${lib.id}`}
                    className="flex items-center justify-between p-3 rounded-lg border border-border hover:border-primary/40 hover:bg-primary/5 transition-all group"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-md bg-muted flex items-center justify-center">
                        <Images className="w-5 h-5 text-muted-foreground" />
                      </div>
                      <div>
                        <p className="font-medium text-foreground text-sm">{lib.name}</p>
                        <div className="flex items-center gap-2 mt-0.5">
                          <span className="text-xs text-muted-foreground">{lib.photo_count} photo{lib.photo_count !== 1 ? 's' : ''}</span>
                          <span className="text-xs text-muted-foreground">·</span>
                          <span className="text-xs text-muted-foreground">{lib.total_size_mb?.toFixed(1) ?? '0'} MB</span>
                          <Badge
                            variant="outline"
                            className={`text-xs px-1.5 py-0 ${lib.privacy === 'public' ? 'border-green-500/40 text-green-600' : 'border-amber-500/40 text-amber-600'}`}
                          >
                            {lib.privacy === 'public' ? 'Public' : 'Private'}
                          </Badge>
                        </div>
                      </div>
                    </div>
                    <div className="text-primary opacity-0 group-hover:opacity-100 transition-opacity">
                      <ChevronLeft className="w-4 h-4 rotate-180" />
                    </div>
                  </Link>
                ))}
              </div>
            </CardContent>
          </Card>
        </motion.div>
      )}

      <ReportPreviewDialog
        open={reportPreviewOpen}
        onOpenChange={setReportPreviewOpen}
        title="Event Report"
        html={reportHtml}
      />

      {event?.venue_coordinates?.latitude && event?.venue_coordinates?.longitude && (
        <DirectionsMapDialog
          open={directionsOpen}
          onOpenChange={setDirectionsOpen}
          destinationLat={parseFloat(event.venue_coordinates.latitude)}
          destinationLng={parseFloat(event.venue_coordinates.longitude)}
          venueName={event.venue || event.location}
          address={event.venue_address || event.location}
        />
      )}
    </div>
  );
};

export default EventView;
