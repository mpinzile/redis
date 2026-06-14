import { useState, useEffect, useCallback, useRef } from 'react';
import { useParams, useNavigate, useLocation } from 'react-router-dom';
import EventAutomationsPage from '@/pages/event/EventAutomationsPage';
import { ChevronLeft, Users, UserCheck, CheckCircle2, Plus, Search, Trash2, X, Loader2, Images, ChevronDown, FileText, ChevronRight, Eye } from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import ShareIcon from '@/assets/icons/share-icon.svg';
import CalendarIcon from '@/assets/icons/calendar-icon.svg';
import LocationIcon from '@/assets/icons/location-icon.svg';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent } from '@/components/ui/tabs';
import { PillTabsNav } from '@/components/ui/pill-tabs';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { useWorkspaceMeta } from '@/hooks/useWorkspaceMeta';
import EventRSVP from './EventRSVP';
import EventCardsTab from './events/EventCardsTab';
import EventGuestList from './events/EventGuestList';
import EventCommittee from './events/EventCommittee';
import EventContributions from './events/EventContributions';
import EventExpenses from './events/EventExpenses';
import EventBudget from './events/EventBudget';
import EventChecklist from './events/EventChecklist';
import EventSchedule from './events/EventSchedule';
import { useEventContributors } from '@/data/useContributors';
import { useEvent } from '@/data/useEvents';
import { useCurrentUser } from '@/hooks/useCurrentUser';
import { usePolling } from '@/hooks/usePolling';
import { useCurrency } from '@/hooks/useCurrency';
import { getEventCountdown } from '@/utils/getEventCountdown';
import { EventManagementSkeleton } from '@/components/ui/EventManagementSkeleton';
import { eventsApi, showCaughtError } from '@/lib/api';
import { Skeleton } from '@/components/ui/skeleton';
import { servicesApi } from '@/lib/api/services';
import { photoLibrariesApi } from '@/lib/api/photoLibraries';

import { toast } from 'sonner';
import { useEventPermissions } from '@/hooks/useEventPermissions';
import ShareEventToFeed from '@/components/ShareEventToFeed';
import EventTicketManagement from '@/components/events/EventTicketManagement';
import EventGuestCheckIn from '@/components/events/EventGuestCheckIn';
import EventMeetings from '@/components/events/EventMeetings';
import EventGroupCta from '@/components/eventGroups/EventGroupCta';
import EventOverviewDashboard from '@/components/events/EventOverviewDashboard';
import EventSponsors from '@/components/events/EventSponsors';
import { LogOfflinePaymentDialog } from '@/components/events/LogOfflinePaymentDialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useLanguage } from '@/lib/i18n/LanguageContext';

const EventManagement = () => {
  const { format: formatPrice } = useCurrency();
  const { t } = useLanguage();
  const { id } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const { data: currentUser } = useCurrentUser();

  const { event: apiEvent, loading: eventLoading, refetch: refetchEvent } = useEvent(id || null);
  usePolling(refetchEvent, 15000);

  const { permissions, loading: permsLoading } = useEventPermissions(id || null);
  const { summary: contributionSummary } = useEventContributors(id || null);

  const event = apiEvent;

  // Determine if current user is the event creator
  const isCreator = permissions.is_creator;

  useWorkspaceMeta({
    title: event?.title || 'Event Management',
    description: `Manage services, committee, contributions, and invitations for ${event?.title || 'your event'}.`
  });

  const [activeTab, setActiveTab] = useState(() => {
    const tab = new URLSearchParams(location.search).get('tab');
    return tab || 'overview';
  });
  const [openingWorkspace, setOpeningWorkspace] = useState(false);

  useEffect(() => {
    const tab = new URLSearchParams(location.search).get('tab');
    if (tab && tab !== activeTab) setActiveTab(tab);
  }, [location.search, activeTab]);

  const openWorkspace = useCallback(async () => {
    if (!id || openingWorkspace) return;
    setOpeningWorkspace(true);
    try {
      const { eventGroupsApi } = await import('@/lib/api/eventGroups');
      let res = await eventGroupsApi.getForEvent(id);
      if (!res.success || !res.data?.id) {
        res = await eventGroupsApi.createForEvent(id);
      }
      const groupId = (res.data as any)?.id;
      if (groupId) navigate(`/event-group/${groupId}`);
      else toast.error('Could not open workspace');
    } catch (e: any) {
      toast.error(e?.message || 'Could not open workspace');
    } finally {
      setOpeningWorkspace(false);
    }
  }, [id, navigate, openingWorkspace]);
  const [showAddServiceDialog, setShowAddServiceDialog] = useState(false);
  const [serviceSearch, setServiceSearch] = useState('');
  const [deleteServiceId, setDeleteServiceId] = useState<string | null>(null);
  const [logPaymentFor, setLogPaymentFor] = useState<{ id: string; vendorName: string; serviceTitle: string; agreedPrice?: number | null } | null>(null);

  const [lightboxOpen, setLightboxOpen] = useState(false);
  const [lightboxIndex, setLightboxIndex] = useState(0);

  // Dynamic event services
  const [eventServices, setEventServices] = useState<any[]>([]);
  const [servicesLoading, setServicesLoading] = useState(false);
  // Photo libraries created by service providers for this event
  const [eventPhotoLibraries, setEventPhotoLibraries] = useState<any[]>([]);

  const loadEventServices = async () => {
    if (!id) return;
    setServicesLoading(true);
    try {
      const res = await eventsApi.getEventServices(id);
      if (res.success) {
        const data = res.data as any;
        setEventServices(Array.isArray(data) ? data : data?.items || []);
      }
    } catch { /* silent */ }
    finally { setServicesLoading(false); }
  };

  const loadEventPhotoLibraries = async () => {
    if (!id) return;
    try {
      const res = await photoLibrariesApi.getEventLibraries(id);
      if (res.success && res.data) {
        setEventPhotoLibraries(res.data.libraries || []);
      }
    } catch { /* silent */ }
  };


  // Lazy-load services + photo libraries only when the user opens the
  // Services tab (or the Overview, which renders the completed/total counter).
  // This avoids two extra round-trips on the very first navigation into a
  // brand-new event, which is the slowest path.
  const _servicesLoaded = useRef(false);
  useEffect(() => {
    if (!id) return;
    const needsServices = activeTab === 'services' || activeTab === 'overview';
    if (needsServices && !_servicesLoaded.current) {
      _servicesLoaded.current = true;
      loadEventServices();
      loadEventPhotoLibraries();
    }
  }, [id, activeTab]);

  const completedServices = eventServices.filter((s: any) => s.status === 'completed').length;
  const totalServices = eventServices.length;
  const progress = totalServices > 0 ? Math.round((completedServices / totalServices) * 100) : 0;

  const [updatingStatusId, setUpdatingStatusId] = useState<string | null>(null);

  const updateServiceStatus = async (serviceId: string, newStatus: string) => {
    setUpdatingStatusId(serviceId);
    try {
      await eventsApi.updateEventService(id!, serviceId, { service_status: newStatus });
      loadEventServices();
      toast.success(`Service status updated to ${newStatus}`);
    } catch (err: any) { showCaughtError(err); }
    finally { setUpdatingStatusId(null); }
  };

  const statusOptions = [
    { value: 'pending', label: 'Pending', color: 'bg-yellow-500' },
    { value: 'assigned', label: 'Assigned', color: 'bg-blue-500' },
    { value: 'in_progress', label: 'In Progress', color: 'bg-orange-500' },
    { value: 'completed', label: 'Completed', color: 'bg-green-500' },
    { value: 'cancelled', label: 'Cancelled', color: 'bg-red-500' },
  ];

  const handleRemoveService = async () => {
    if (!deleteServiceId || !id) return;
    try {
      await eventsApi.removeEventService(id, deleteServiceId);
      toast.success('Service removed');
      loadEventServices();
    } catch (err: any) { showCaughtError(err); }
    setDeleteServiceId(null);
  };

  // Service provider search
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [searchLoading, setSearchLoading] = useState(false);
  const [addingServiceId, setAddingServiceId] = useState<string | null>(null);

  const handleServiceSearch = async (query: string) => {
    setServiceSearch(query);
    if (query.length < 2) { setSearchResults([]); return; }
    setSearchLoading(true);
    try {
      const res = await servicesApi.search({ search: query, limit: 20 });
      if (res.success) {
        const data = res.data as any;
        setSearchResults(data?.services || (Array.isArray(data) ? data : []));
      }
    } catch { /* silent */ }
    finally { setSearchLoading(false); }
  };

  const handleAddService = async (service: any) => {
    if (!id) return;
    setAddingServiceId(service.id);
    try {
      const res = await eventsApi.addEventService(id, {
        provider_service_id: service.id,
        provider_user_id: service.provider?.id,
        notes: service.title,
      });
      if (res.success) {
        toast.success(`${service.title} added to event`);
        loadEventServices();
        setShowAddServiceDialog(false);
        setServiceSearch('');
        setSearchResults([]);
      } else {
        showCaughtError(res);
      }
    } catch (err: any) { showCaughtError(err); }
    finally { setAddingServiceId(null); }
  };

  if (eventLoading || permsLoading) return <EventManagementSkeleton />;
  if (!event) return <div className="text-center py-8 text-muted-foreground">Event not found</div>;

  const eventImages: string[] = (() => {
    if (apiEvent?.gallery_images && (apiEvent.gallery_images as string[]).length > 0) return apiEvent.gallery_images as string[];
    if ((apiEvent as any)?.images?.length > 0) {
      return (apiEvent as any).images.map((img: any) => img.image_url || img.url || img);
    }
    const cover = (apiEvent as any)?.cover_image || (apiEvent as any)?.cover_image_url;
    return cover ? [cover] : [];
  })();
  const hasImages = eventImages.length > 0;

  const openLightbox = (index: number) => { setLightboxIndex(index); setLightboxOpen(true); };
  const closeLightbox = () => setLightboxOpen(false);

  const eventTitle = apiEvent?.title || '';
  const eventDate = apiEvent?.start_date || '';
  const eventLocation = apiEvent?.location || '';
  const eventGuestCount = apiEvent?.guest_count || 0;
  const expectedGuests = apiEvent?.expected_guests || 0;
  const eventBudget = apiEvent?.budget ? formatPrice(apiEvent.budget) : '';
  const eventDescription = apiEvent?.description || '';
  const isEventEnded = (() => {
    const dateStr = (apiEvent as any)?.end_date || apiEvent?.start_date;
    if (!dateStr) return false;
    return new Date(dateStr) < new Date();
  })();

  return (
    <div>
      {/* Header */}
      <div className="mb-6">
        {/* Top row: title + back button (back stays on the right, matching other pages). */}
        <div className="flex items-center gap-2 mb-3">
          <h1 className="flex-1 min-w-0 text-lg sm:text-xl md:text-2xl lg:text-3xl font-bold break-words leading-tight">
            {eventTitle}
          </h1>
          <Button
            variant="ghost"
            size="icon"
            className="flex-shrink-0 self-center"
            onClick={() => navigate('/my-events')}
            aria-label="Back"
          >
            <ChevronLeft className="w-5 h-5" />
          </Button>
        </div>
        <div className="flex flex-wrap items-center gap-2 mb-3">
          {event && (
            <Button
              variant="outline"
              size="sm"
              className="gap-2"
              onClick={() => navigate(`/event/${event.id}`)}
              title="View public event page"
            >
              <Eye className="w-4 h-4 opacity-70" />
              <span className="hidden sm:inline">View Public Page</span>
              <span className="sm:hidden">Public</span>
            </Button>
          )}
          {isCreator && event && (
            <ShareEventToFeed
              event={{
                id: event.id,
                title: event.title,
                start_date: event.start_date,
                location: event.location,
                cover_image: (event as any).cover_image || eventImages[0],
              }}
              trigger={
                <Button variant="outline" size="sm" className="gap-2">
                  <SvgIcon src={ShareIcon} alt="" className="w-4 h-4 opacity-70" />
                  <span className="hidden sm:inline">Share to Feed</span>
                  <span className="sm:hidden">Share</span>
                </Button>
              }
            />
          )}
        </div>
        <div className="flex flex-wrap gap-3 text-sm text-muted-foreground">
          <span className="flex items-center gap-2"><SvgIcon src={CalendarIcon} alt="Calendar" className="w-4 h-4 flex-shrink-0" /><span className="truncate">{eventDate}</span></span>
          {(() => {
            const countdown = getEventCountdown(apiEvent?.start_date);
            if (!countdown) return null;
            return (
              <span className={`flex items-center gap-1.5 text-xs font-medium px-2 py-0.5 rounded-full ${countdown.isPast ? 'bg-muted text-muted-foreground' : 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300'}`}>
                {countdown.text}
              </span>
            );
          })()}
          <span className="flex items-start gap-2 break-words min-w-0"><SvgIcon src={LocationIcon} alt="Location" className="w-4 h-4 flex-shrink-0 mt-0.5" /><span className="break-words">{eventLocation}</span></span>
          <span className="flex items-center gap-2"><Users className="w-4 h-4 flex-shrink-0" /><span className="truncate">{expectedGuests} expected</span></span>
          <span className="flex items-center gap-2"><UserCheck className="w-4 h-4 flex-shrink-0" /><span className="truncate">{apiEvent?.confirmed_guest_count || 0} confirmed</span></span>
        </div>
      </div>

      {/* Event images */}
      {hasImages && (
        <div className="mb-6">
          {eventImages.length === 1 ? (
            <div className="relative w-full rounded-lg overflow-hidden border border-border bg-muted/30">
              <img src={eventImages[0]} alt={`${eventTitle} image`} className="w-full h-auto block cursor-pointer" onClick={() => openLightbox(0)} />
            </div>
          ) : (
            <div className="flex gap-3 overflow-x-auto py-2">
              {eventImages.map((src, idx) => (
                <div key={idx} className="relative w-56 h-40 flex-shrink-0 rounded-lg overflow-hidden border border-border cursor-pointer" onClick={() => openLightbox(idx)}>
                  <img src={src} alt={`event ${idx}`} className="w-full h-full object-cover" />
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Lightbox */}
      {lightboxOpen && hasImages && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" onClick={closeLightbox}>
          <div className="relative max-w-[90vw] max-h-[90vh] w-full" onClick={(e) => e.stopPropagation()}>
            <button onClick={closeLightbox} className="absolute -top-3 -right-3 bg-white rounded-full p-2 shadow z-50" aria-label={t("close")}>✕</button>
            <img src={eventImages[lightboxIndex]} alt={`zoom ${lightboxIndex}`} className="w-full h-full object-contain rounded" style={{ maxHeight: '80vh' }} />
            {eventImages.length > 1 && (
              <>
                <button onClick={() => setLightboxIndex((i) => (i - 1 + eventImages.length) % eventImages.length)} className="absolute left-2 top-1/2 -translate-y-1/2 bg-white/80 p-2 rounded-full" aria-label="Previous">‹</button>
                <button onClick={() => setLightboxIndex((i) => (i + 1) % eventImages.length)} className="absolute right-2 top-1/2 -translate-y-1/2 bg-white/80 p-2 rounded-full" aria-label="Next">›</button>
              </>
            )}
          </div>
        </div>
      )}

      <AlertDialog open={!!deleteServiceId} onOpenChange={() => setDeleteServiceId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('remove')} {t('services')}?</AlertDialogTitle>
            <AlertDialogDescription>{t('are_you_sure')}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('cancel')}</AlertDialogCancel>
            <AlertDialogAction onClick={handleRemoveService} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">{t('remove')} {t('services')}</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <PillTabsNav
          activeTab={activeTab}
          onTabChange={setActiveTab}
          tabs={[
            { value: 'overview', label: t('overview') },
            { value: 'checklist', label: t('checklist') },
            { value: 'budget', label: t('budget') },
            { value: 'expenses', label: t('expenses') },
            { value: 'services', label: t('services') },
            { value: 'committee', label: t('committee') },
            { value: 'contributions', label: t('contributions') },
            { value: 'guests', label: t('guests') },
            { value: 'cards', label: 'Cards' },
            { value: 'rsvp', label: t('rsvp') },
            { value: 'schedule', label: t('schedule') || 'Schedule' },
            { value: 'meetings', label: 'Meetings' },
            ...((apiEvent as any)?.sells_tickets ? [{ value: 'tickets', label: t('tickets') }] : []),
            { value: 'sponsors', label: 'Sponsors' },
            ...(isCreator ? [{ value: 'reminders', label: 'Reminders' }] : []),
            ...(isCreator && !isEventEnded ? [{ value: 'check-in', label: t('check_in') }] : []),
          ]}
        />

        <TabsContent value="overview" className="space-y-5">
          {/* Group Chat CTA — create or open the event group from here */}
          <EventGroupCta eventId={id || ''} onOpen={openWorkspace} opening={openingWorkspace} />

          {/* Premium overview dashboard — all values come from the backend */}
          {id && <EventOverviewDashboard eventId={id} />}

          {/* Row 1: Financial overview */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <Card className="w-full"><CardContent className="p-5"><div className="flex items-center justify-between"><div className="flex-1"><p className="text-xs text-muted-foreground">Budget Status</p><p className="text-base font-semibold mt-1">{eventBudget}</p><p className="text-xs text-muted-foreground mt-1">Budget allocated</p></div><div className="w-9 h-9 bg-blue-100 rounded-lg flex items-center justify-center"><Users className="w-4 h-4 text-blue-600" /></div></div></CardContent></Card>
            <Card className="w-full"><CardContent className="p-5"><div className="flex items-center justify-between"><div className="flex-1"><p className="text-xs text-muted-foreground">Total Pledged</p><p className="text-base font-semibold text-primary mt-1">{formatPrice(contributionSummary?.total_pledged || 0)}</p><p className="text-xs text-muted-foreground mt-1">{contributionSummary?.pledged_count || 0} contributor{(contributionSummary?.pledged_count || 0) !== 1 ? 's' : ''} pledged</p></div><div className="w-9 h-9 bg-purple-100 rounded-lg flex items-center justify-center"><Users className="w-4 h-4 text-purple-600" /></div></div></CardContent></Card>
            {apiEvent?.budget && contributionSummary && (
              <Card className="w-full"><CardContent className="p-5"><div className="flex items-center justify-between"><div className="flex-1"><p className="text-xs text-muted-foreground">Unpledged</p><p className="text-base font-semibold text-destructive mt-1">{formatPrice(Math.max(0, (apiEvent.budget as number) - (contributionSummary.total_pledged || 0)))}</p><p className="text-xs text-muted-foreground mt-1">Budget − Total Pledged</p></div><div className="w-9 h-9 bg-red-100 rounded-lg flex items-center justify-center"><Users className="w-4 h-4 text-red-600" /></div></div></CardContent></Card>
            )}
          </div>
          {/* Row 2: Cash in Hand */}
          <Card className="w-full border-primary/20 bg-primary/5">
            <CardContent className="p-5">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <p className="text-xs text-muted-foreground">Cash in Hand</p>
                  <p className="text-xl font-bold text-primary mt-1">{formatPrice(contributionSummary?.total_paid || 0)}</p>
                </div>
                <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center">
                  <CheckCircle2 className="w-5 h-5 text-primary" />
                </div>
              </div>
              <div className="grid grid-cols-3 gap-3">
                <div className="text-center p-2 rounded-md bg-background">
                  <p className="text-base font-semibold">{contributionSummary?.paid_count || 0}</p>
                  <p className="text-[10px] text-muted-foreground">Paid contributors</p>
                </div>
                <div className="text-center p-2 rounded-md bg-background">
                  <p className="text-base font-semibold">{formatPrice(Math.max(0, (contributionSummary?.total_pledged || 0) - (contributionSummary?.total_paid || 0)))}</p>
                  <p className="text-[10px] text-muted-foreground">Outstanding</p>
                </div>
                <div className="text-center p-2 rounded-md bg-background">
                  <p className="text-base font-semibold">{contributionSummary?.total_pledged ? Math.round(((contributionSummary?.total_paid || 0) / contributionSummary.total_pledged) * 100) : 0}%</p>
                  <p className="text-[10px] text-muted-foreground">Collection rate</p>
                </div>
              </div>
            </CardContent>
          </Card>
          {/* Row 3: Event progress + Guest overview */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <Card className="w-full"><CardContent className="p-5"><div className="flex items-center justify-between"><div className="flex-1"><p className="text-xs text-muted-foreground">Event Progress</p><p className="text-base font-semibold mt-1">{completedServices}/{totalServices} Services</p><div className="w-full bg-muted rounded-full h-2 mt-2"><div className="bg-primary h-2 rounded-full transition-all" style={{ width: `${progress}%` }} /></div></div></div></CardContent></Card>
            <Card className="w-full"><CardContent className="p-5"><div className="flex items-center justify-between"><div className="flex-1"><p className="text-xs text-muted-foreground">Guest Overview</p><p className="text-base font-semibold mt-1">{eventGuestCount}</p><p className="text-xs text-muted-foreground mt-1">of {expectedGuests} expected guests</p></div><div className="w-9 h-9 bg-green-100 rounded-lg flex items-center justify-center"><Users className="w-4 h-4 text-green-600" /></div></div></CardContent></Card>
            <Card className="w-full"><CardContent className="p-5"><div className="flex items-center justify-between"><div className="flex-1"><p className="text-xs text-muted-foreground">Confirmed Guests</p><p className="text-base font-semibold text-green-600 mt-1">{apiEvent?.confirmed_guest_count || 0}</p></div><div className="w-9 h-9 bg-green-100 rounded-lg flex items-center justify-center"><UserCheck className="w-4 h-4 text-green-600" /></div></div></CardContent></Card>
          </div>
          <Card><CardContent className="p-4"><p className="text-[10px] text-muted-foreground mb-1">Event Description</p><p className="text-sm text-muted-foreground">{eventDescription}</p></CardContent></Card>

        </TabsContent>

        <TabsContent value="checklist" className="space-y-6">
          <EventChecklist eventId={id!} eventTypeId={apiEvent?.event_type_id} permissions={permissions} />
        </TabsContent>

        <TabsContent value="budget" className="space-y-6">
          <EventBudget
            eventId={id!}
            eventTitle={eventTitle}
            eventBudget={apiEvent?.budget ? parseFloat(String(apiEvent.budget).replace(/[^0-9]/g, '')) : undefined}
            eventType={apiEvent?.event_type_id || ''}
            eventTypeName={apiEvent?.event_type?.name}
            eventLocation={apiEvent?.location || ''}
            expectedGuests={apiEvent?.expected_guests ? String(apiEvent.expected_guests) : ''}
            permissions={permissions}
          />
        </TabsContent>

        <TabsContent value="expenses" className="space-y-6">
          <EventExpenses
            eventId={id!}
            eventTitle={eventTitle}
            eventBudget={apiEvent?.budget ? parseFloat(String(apiEvent.budget).replace(/[^0-9]/g, '')) : undefined}
            totalRaised={contributionSummary?.total_paid || 0}
            permissions={permissions}
          />
        </TabsContent>

        <TabsContent value="services" className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-lg font-bold">Service Providers</h2>
              <p className="text-xs text-muted-foreground">{eventServices.length} service{eventServices.length !== 1 ? 's' : ''} - {completedServices} completed</p>
            </div>
            {(permissions.can_manage_vendors || permissions.is_creator) && (
              <Button size="sm" onClick={() => setShowAddServiceDialog(true)}>
                <Plus className="w-4 h-4 mr-1.5" />Add Service
              </Button>
            )}
          </div>

          {servicesLoading ? (
            <div className="grid grid-cols-1 gap-3 md:grid-cols-4">
              {[...Array(3)].map((_, i) => (
                <div key={i} className="rounded-2xl border border-border bg-card overflow-hidden">
                  <div className="h-32 bg-muted animate-pulse" />
                  <div className="p-4 space-y-2">
                    <div className="h-4 bg-muted rounded animate-pulse w-3/4" />
                    <div className="h-3 bg-muted rounded animate-pulse w-1/2" />
                  </div>
                </div>
              ))}
            </div>
          ) : eventServices.length === 0 ? (
            <div className="text-center py-16 border-2 border-dashed border-border rounded-2xl">
              <div className="w-16 h-16 bg-primary/10 rounded-2xl flex items-center justify-center mx-auto mb-4">
                <Plus className="w-8 h-8 text-primary opacity-60" />
              </div>
              <h3 className="font-bold text-lg mb-1">No Services Yet</h3>
              <p className="text-sm text-muted-foreground mb-4">Add service providers to make your event a success.</p>
              {(permissions.can_manage_vendors || permissions.is_creator) && (
                <Button onClick={() => setShowAddServiceDialog(true)}>
                  <Plus className="w-4 h-4 mr-1.5" />Add First Service
                </Button>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-3 md:grid-cols-4">
              {eventServices.map((service: any) => {
                // Backend returns service.service.image (single string from _service_booking_dict)
                const extractFirstImage = (arr: any) => {
                  if (!Array.isArray(arr) || arr.length === 0) return '';
                  const first = arr[0];
                  if (typeof first === 'string') return first;
                  return first?.url || first?.image_url || first?.file_url || first?.thumbnail_url || '';
                };
                const serviceImage = service.service?.image
                  || service.service?.primary_image
                  || service.service?.cover_image
                  || service.service?.image_url
                  || extractFirstImage(service.service?.images)
                  || extractFirstImage(service.service?.gallery_images)
                  || '';

                const isActiveService = ['completed', 'assigned', 'in_progress'].includes(service.status);
                // provider_service_id is the UserService id that was added to the event
                const providerServiceId = service.provider_service_id || service.service?.id;
                const serviceCategory = (service.service?.category || service.service?.service_type_name || service.service?.title || '').toLowerCase();
                const isPhotographyService = serviceCategory.includes('photo') || serviceCategory.includes('cinema') || serviceCategory.includes('video') || serviceCategory.includes('film');
                const matchedLibrary = isPhotographyService && isActiveService
                  ? eventPhotoLibraries.find((lib: any) =>
                      lib.user_service_id === providerServiceId ||
                      lib.user_service_id === service.provider_service_id ||
                      lib.user_service_id === service.service?.id ||
                      (lib.service?.id && (lib.service.id === providerServiceId || lib.service.id === service.provider_service_id))
                    ) ?? (eventPhotoLibraries.length > 0 ? eventPhotoLibraries[0] : null)
                  : null;

                const statusStyle: Record<string, string> = {
                  completed: 'bg-emerald-500 text-white',
                  assigned: 'bg-blue-500 text-white',
                  in_progress: 'bg-indigo-500 text-white',
                  pending: 'bg-amber-500 text-white',
                  cancelled: 'bg-destructive text-white',
                };
                const isCompleted = service.status === 'completed';

                return (
                  <div
                    key={service.id}
                    className={`rounded-2xl border overflow-hidden bg-card transition-all hover:shadow-md
                      ${isCompleted ? 'border-emerald-200 dark:border-emerald-800/60' : 'border-border'}`}
                  >
                    {/* Image Header */}
                    <div className="relative aspect-[4/3] bg-muted overflow-hidden">
                      {serviceImage ? (
                        <img src={serviceImage} alt={service.service?.title} className="w-full h-full object-cover" />
                      ) : (
                        <div className="flex items-center justify-center h-full">
                          <Users className="w-10 h-10 text-muted-foreground/20" />
                        </div>
                      )}

                      {/* Status badge */}
                      <div className="absolute top-3 left-3">
                        <span className={`text-[11px] font-semibold px-2.5 py-1 rounded-full ${statusStyle[service.status] || 'bg-muted text-muted-foreground'}`}>
                          {service.status}
                        </span>
                      </div>

                      {/* Price */}
                      {service.quoted_price && (
                        <div className="absolute top-3 right-3 bg-black/50 backdrop-blur-sm text-white text-xs px-2.5 py-1 rounded-full font-semibold">
                          {formatPrice(service.quoted_price)}
                        </div>
                      )}

                      {/* Status is system-driven (booking accepted → assigned, OTP confirmed → completed,
                          booking cancelled → cancelled). It cannot be changed manually. */}
                    </div>

                    {/* Body */}
                    <div className="p-4 space-y-3">
                      {/* Provider info */}
                      <div className="flex items-center gap-2">
                        <Avatar className="w-7 h-7 flex-shrink-0">
                          <AvatarFallback className="bg-primary/10 text-primary text-xs font-semibold">
                            {(service.service?.provider_name || service.service?.title || 'S')[0]}
                          </AvatarFallback>
                        </Avatar>
                        <div className="min-w-0">
                          <p className="text-xs font-medium text-foreground truncate flex items-center gap-1">
                            {service.service?.title || 'Unnamed Service'}

                          </p>
                          {service.service?.provider_name && (
                            <p className="text-[11px] text-muted-foreground truncate">{service.service.provider_name}</p>
                          )}
                        </div>
                        {(permissions.can_manage_vendors || permissions.is_creator) && !isActiveService && (
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => setDeleteServiceId(service.id)}
                            className="ml-auto text-muted-foreground hover:text-destructive h-7 w-7 p-0 flex-shrink-0"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </Button>
                        )}
                      </div>

                      {/* Photo Library CTA for photography services */}
                      {isPhotographyService && isActiveService && (
                        matchedLibrary ? (
                          <button
                            onClick={() => navigate(`/photo-library/${matchedLibrary.id}`)}
                            className="w-full flex items-center justify-between gap-2 rounded-xl border border-border bg-muted/40 hover:bg-muted transition-colors px-3 py-2 text-sm"
                          >
                            <div className="flex items-center gap-2 min-w-0">
                              {matchedLibrary.photos && matchedLibrary.photos.length > 0 ? (
                                <div className="flex -space-x-1 shrink-0">
                                  {matchedLibrary.photos.slice(0, 3).map((p: any, i: number) => (
                                    <img key={i} src={p.url} alt="" className="w-6 h-6 rounded-full object-cover border-2 border-card" />
                                  ))}
                                </div>
                              ) : (
                                <Images className="w-4 h-4 text-primary flex-shrink-0" />
                              )}
                              <span className="font-medium text-foreground text-xs truncate">Photo Library</span>
                            </div>
                            <span className="text-[11px] text-muted-foreground bg-background px-2 py-0.5 rounded-full border border-border shrink-0">
                              {matchedLibrary.photo_count || 0} photos
                            </span>
                          </button>
                        ) : (
                          <div className="flex items-center gap-2 rounded-xl border border-dashed border-border bg-muted/20 px-3 py-2">
                            <Images className="w-3.5 h-3.5 text-muted-foreground flex-shrink-0" />
                            <span className="text-xs text-muted-foreground">No photo library shared yet</span>
                          </div>
                        )
                      )}

                      {/* Log offline payment CTA */}
                      {(permissions.can_manage_vendors || permissions.is_creator) && service.status === 'assigned' && (
                        <Button
                          size="sm"
                          variant="outline"
                          className="w-full min-h-8 text-xs whitespace-normal leading-tight"
                          onClick={() => setLogPaymentFor({
                            id: service.id,
                            vendorName: service.service?.provider_name || service.service?.title || 'Vendor',
                            serviceTitle: service.service?.title || 'Service',
                            agreedPrice: service.quoted_price ? Number(service.quoted_price) : null,
                          })}
                        >
                          Log offline payment
                        </Button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </TabsContent>

        <TabsContent value="committee" className="space-y-6">
          <EventCommittee eventId={id!} permissions={permissions} eventTitle={event?.title || 'Event'} />
        </TabsContent>

        <TabsContent value="contributions" className="space-y-6">
          <EventContributions eventId={id!} eventTitle={eventTitle} eventBudget={apiEvent?.budget ? parseFloat(String(apiEvent.budget).replace(/[^0-9]/g, '')) : undefined} eventEndDate={apiEvent?.start_date} reminderContactPhone={(apiEvent as any)?.reminder_contact_phone || ''} isCreator={isCreator} permissions={permissions} />
        </TabsContent>


        <TabsContent value="guests" className="space-y-6">
          <EventGuestList eventId={id!} permissions={permissions} />
        </TabsContent>

        <TabsContent value="cards" className="space-y-6">
          <EventCardsTab eventId={id!} />
        </TabsContent>



        <TabsContent value="rsvp" className="space-y-6">
          <EventRSVP eventId={id || ''} eventTitle={eventTitle} permissions={permissions} />
        </TabsContent>

        <TabsContent value="schedule" className="space-y-6">
          <EventSchedule eventId={id!} />
        </TabsContent>

        <TabsContent value="meetings" className="space-y-6">
          <EventMeetings eventId={id!} isCreator={isCreator} eventName={eventTitle} />
        </TabsContent>

        {(apiEvent as any)?.sells_tickets && (
          <TabsContent value="tickets" className="space-y-4">
            <EventTicketManagement eventId={id!} isCreator={isCreator} />
          </TabsContent>
        )}

        <TabsContent value="sponsors" className="space-y-4">
          <EventSponsors eventId={id!} isCreator={isCreator} />
        </TabsContent>

        {isCreator && (
          <TabsContent value="reminders" className="space-y-4">
            <EventAutomationsPage eventId={id!} embedded />
          </TabsContent>
        )}

        {isCreator && !isEventEnded && (
          <TabsContent value="check-in" className="space-y-4">
            <EventGuestCheckIn
              eventId={id!}
              isCreator={isCreator}
              eventTitle={eventTitle}
              eventDate={eventDate}
              eventLocation={eventLocation}
              guestCount={eventGuestCount}
              confirmedCount={apiEvent?.confirmed_guest_count || 0}
            />
          </TabsContent>
        )}
      </Tabs>

      {/* Add Service Dialog */}
      <Dialog open={showAddServiceDialog} onOpenChange={setShowAddServiceDialog}>
        <DialogContent className="sm:max-w-[500px] max-h-[85vh] overflow-hidden flex flex-col">
          <DialogHeader><DialogTitle>Add Service Provider</DialogTitle><DialogDescription>Search for a service provider to assign to your event</DialogDescription></DialogHeader>
          <div className="space-y-4 flex-1 min-h-0 flex flex-col">
            <div className="relative flex-shrink-0">
              <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
              <Input placeholder="Search by name, category..." value={serviceSearch} onChange={(e) => handleServiceSearch(e.target.value)} className="pl-9" autoComplete="off" />
            </div>
            <ScrollArea className="flex-1 min-h-0 max-h-[50vh] pr-4">
              <div className="space-y-2">
                {searchLoading && (
                  <div className="flex items-center justify-center py-8"><Loader2 className="w-5 h-5 animate-spin text-muted-foreground" /></div>
                )}
                {!searchLoading && searchResults.map((service: any) => (
                  <button
                    key={service.id}
                    onClick={() => handleAddService(service)}
                    disabled={addingServiceId === service.id}
                    className="w-full text-left p-3 rounded-lg border border-border hover:bg-muted transition-colors flex items-center gap-3"
                  >
                    <Avatar className="w-10 h-10 flex-shrink-0">
                      <AvatarImage src={service.primary_image || service.images?.[0]?.url} />
                      <AvatarFallback>{service.title?.[0]}</AvatarFallback>
                    </Avatar>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-medium truncate">{service.title}</span>

                      </div>
                      <div className="flex items-center gap-1.5 text-sm text-muted-foreground flex-wrap">
                        <span className="truncate">{service.category_name || service.category || service.service_type_name}</span>
                        {service.provider?.name && <><span>•</span><span className="truncate">{service.provider.name}</span></>}
                        {service.min_price && <><span>•</span><span className="whitespace-nowrap">From TZS {formatPrice(service.min_price)}</span></>}
                      </div>
                    </div>
                    {addingServiceId === service.id && <Loader2 className="w-4 h-4 animate-spin" />}
                  </button>
                ))}
                {!searchLoading && serviceSearch.length >= 2 && searchResults.length === 0 && (
                  <div className="text-center py-8 text-muted-foreground">No service providers found</div>
                )}
                {!searchLoading && serviceSearch.length < 2 && (
                  <div className="text-center py-8 text-muted-foreground">Type at least 2 characters to search</div>
                )}
              </div>
            </ScrollArea>
          </div>
        </DialogContent>
      </Dialog>

      {logPaymentFor && (
        <LogOfflinePaymentDialog
          open={!!logPaymentFor}
          onOpenChange={(v) => { if (!v) setLogPaymentFor(null); }}
          eventId={id!}
          eventServiceId={logPaymentFor.id}
          vendorName={logPaymentFor.vendorName}
          serviceTitle={logPaymentFor.serviceTitle}
          agreedPrice={logPaymentFor.agreedPrice}
          onLogged={() => loadEventServices()}
        />
      )}
    </div>
  );
};

export default EventManagement;
