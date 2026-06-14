import { useState, useEffect, useMemo, useCallback } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import {
  ChevronLeft, Star, CheckCircle, ChevronRight, Loader2,
  Award, Briefcase, X, TrendingUp,
  ArrowUpRight, Shield, Edit, Eye, DollarSign, Users, Music
} from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import calendarIcon from '@/assets/icons/calendar-icon.svg';
import locationIcon from '@/assets/icons/location-icon.svg';
import VideoSVG from '@/assets/icons/video-icon.svg';
import photosIcon from '@/assets/icons/photos-icon.svg';
import { motion, AnimatePresence } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Avatar, AvatarImage, AvatarFallback } from '@/components/ui/avatar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { useWorkspaceMeta } from '@/hooks/useWorkspaceMeta';
import { useUserService } from '@/hooks/useUserService';
import { servicesApi, userServicesApi } from '@/lib/api/services';
import { useCurrency } from '@/hooks/useCurrency';
import { ServiceDetailLoadingSkeleton } from '@/components/ui/ServiceLoadingSkeleton';
import { Skeleton } from '@/components/ui/skeleton';
import { UserService, ServicePackage, ServiceReview } from '@/lib/api/types';
import LocationIcon from '@/assets/icons/location-icon.svg';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import ReceivedPaymentsPanel from '@/components/payments/ReceivedPaymentsPanel';

interface BookedDate {
  date: string;
  event_id: string;
  event_name: string;
  event_location?: string;
  status: string;
  agreed_price?: number;
}

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'];

const ServiceDetail = () => {
  const { format: formatPrice } = useCurrency();
  const { t } = useLanguage();
  const { id } = useParams();
  const navigate = useNavigate();

  const { service, loading, error } = useUserService(id!);
  const [packages, setPackages] = useState<ServicePackage[]>([]);
  const [reviews, setReviews] = useState<ServiceReview[]>([]);
  const [reviewsLoading, setReviewsLoading] = useState(false);
  const [bookedDates, setBookedDates] = useState<BookedDate[]>([]);
  const [calendarLoading, setCalendarLoading] = useState(true);
  const [lightboxOpen, setLightboxOpen] = useState(false);
  const [lightboxIndex, setLightboxIndex] = useState(0);
  const [currentMonth, setCurrentMonth] = useState(new Date());
  const [activeTab, setActiveTab] = useState<'overview' | 'calendar' | 'reviews' | 'payments'>('overview');
  const [introMedia, setIntroMedia] = useState<Array<{ id: string; media_type: string; media_url: string }>>([]);

  useWorkspaceMeta({
    title: service?.title || 'My Service',
    description: `Manage ${service?.title || 'your service'} - availability, packages, and reviews.`
  });

  useEffect(() => {
    if (!service) return;
    if ((service as any).packages && Array.isArray((service as any).packages)) {
      setPackages((service as any).packages);
    }
    if ((service as any).intro_media && Array.isArray((service as any).intro_media)) {
      setIntroMedia((service as any).intro_media);
    }
  }, [service]);

  // Intro media: only fetch separately if it isn't already inlined in the service payload
  useEffect(() => {
    if (!id) return;
    if (introMedia.length > 0) return;
    userServicesApi.getIntroMedia(id).then(res => {
      if (res.success && res.data) setIntroMedia(Array.isArray(res.data) ? res.data : []);
    }).catch(() => {});
  }, [id, introMedia.length]);

  const loadReviews = useCallback(async () => {
    if (!id) return;
    setReviewsLoading(true);
    try {
      const res = await servicesApi.getReviews(id, { limit: 10 });
      if (res.success && res.data) setReviews(res.data.reviews || []);
    } catch { /* silent */ }
    finally { setReviewsLoading(false); }
  }, [id]);

  // Lazy: only fetch reviews when the reviews tab is opened (once)
  const [reviewsLoaded, setReviewsLoaded] = useState(false);
  useEffect(() => {
    if (activeTab === 'reviews' && id && !reviewsLoaded) {
      setReviewsLoaded(true);
      loadReviews();
    }
  }, [activeTab, id, reviewsLoaded, loadReviews]);

  // Lazy: only fetch calendar when the calendar tab is opened (once)
  const [calendarLoaded, setCalendarLoaded] = useState(false);
  useEffect(() => {
    if (activeTab !== 'calendar' || !id || calendarLoaded) return;
    setCalendarLoaded(true);
    setCalendarLoading(true);
    servicesApi.getCalendar(id).then((res) => {
      if (res.success && res.data?.booked_dates) setBookedDates(res.data.booked_dates);
    }).catch(() => {}).finally(() => setCalendarLoading(false));
  }, [activeTab, id, calendarLoaded]);


  const getImageUrl = (img: any): string => {
    if (typeof img === 'string') return img;
    if (img && typeof img === 'object' && img.url) return img.url;
    return '';
  };

  const formatPriceDisplay = (svc: UserService): string => {
    if (svc.min_price) return `From ${formatPrice(svc.min_price)}`;
    return 'Price on request';
  };

  const calendarDays = useMemo(() => {
    const year = currentMonth.getFullYear();
    const month = currentMonth.getMonth();
    const firstDay = new Date(year, month, 1).getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const days: Array<{ day: number | null; date: string; isToday: boolean; isPast: boolean; booking: BookedDate | null }> = [];
    for (let i = 0; i < firstDay; i++) days.push({ day: null, date: '', isToday: false, isPast: false, booking: null });
    for (let d = 1; d <= daysInMonth; d++) {
      const date = new Date(year, month, d);
      const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
      const booking = bookedDates.find(b => b.date === dateStr) || null;
      days.push({ day: d, date: dateStr, isToday: date.toDateString() === today.toDateString(), isPast: date < today, booking });
    }
    return days;
  }, [currentMonth, bookedDates]);

  const prevMonth = () => setCurrentMonth(prev => new Date(prev.getFullYear(), prev.getMonth() - 1, 1));
  const nextMonth = () => setCurrentMonth(prev => new Date(prev.getFullYear(), prev.getMonth() + 1, 1));

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'confirmed': case 'completed': case 'accepted': return 'bg-emerald-500';
      case 'pending': return 'bg-amber-500';
      case 'cancelled': return 'bg-red-500';
      default: return 'bg-emerald-500';
    }
  };

  const renderStars = (rating: number) =>
    Array.from({ length: 5 }, (_, i) => (
      <Star key={i} className={`w-4 h-4 ${i < rating ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground/30'}`} />
    ));

  if (loading) return <ServiceDetailLoadingSkeleton />;
  if (error || !service) {
    return (
      <div className="flex flex-col items-center justify-center h-64 gap-3">
        <p className="text-muted-foreground">{error || 'Service not found'}</p>
        <Button variant="outline" onClick={() => navigate(-1)}>Go Back</Button>
      </div>
    );
  }

  const hasImages = Array.isArray(service.images) && service.images.length > 0;
  const imageUrls = hasImages ? service.images.map(getImageUrl).filter(Boolean) : [];
  const isVerified = service.verification_status === 'verified';
  const isPending = service.verification_status === 'pending';
  const rating = service.rating || 0;
  const reviewCount = service.review_count || reviews.length || 0;
  const upcomingBookings = bookedDates.filter(b => new Date(b.date) >= new Date(new Date().toDateString())).sort((a, b) => a.date.localeCompare(b.date));
  const totalRevenue = bookedDates.filter(b => b.agreed_price && (b.status === 'confirmed' || b.status === 'completed')).reduce((sum, b) => sum + (b.agreed_price || 0), 0);
  const isPhotography = (service as any).service_type_name?.toLowerCase().includes('photo') || (service as any).service_category?.name?.toLowerCase().includes('photo');

  const TABS = [
    { key: 'overview', label: 'Overview' },
    { key: 'calendar', label: 'Calendar' },
    { key: 'reviews', label: `Reviews (${reviewCount})` },
    { key: 'payments', label: 'Payments' },
  ] as const;

  return (
    <div className="pb-16">

      {/* ─── TOP BAR ─── */}
      <div className="flex items-center justify-between py-4 px-1 mb-2">
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" asChild>
            <Link to={`/services/view/${id}`}><Eye className="w-4 h-4 mr-1.5" />Public View</Link>
          </Button>
          <Button size="sm" asChild>
            <Link to={`/services/edit/${id}`}><Edit className="w-4 h-4 mr-1.5" />Edit</Link>
          </Button>
        </div>
        <Button variant="ghost" size="icon" onClick={() => navigate(-1)} aria-label="Go back">
          <ChevronLeft className="w-5 h-5" />
        </Button>
      </div>

      {/* ─── HERO GALLERY ─── */}
      {hasImages ? (
        <div className="relative rounded-2xl overflow-hidden mb-6 bg-muted">
          {imageUrls.length === 1 ? (
            <div className="relative w-full h-[380px] cursor-zoom-in bg-muted overflow-hidden" onClick={() => { setLightboxIndex(0); setLightboxOpen(true); }}>
              <img src={imageUrls[0]} alt="" aria-hidden className="absolute inset-0 w-full h-full object-cover scale-110 blur-2xl opacity-60" />
              <img src={imageUrls[0]} alt={service.title} className="relative w-full h-full object-contain" />
            </div>
          ) : (
            <div className={`grid gap-1 h-[380px] ${imageUrls.length === 2 ? 'grid-cols-2' : imageUrls.length === 3 ? 'grid-cols-3' : 'grid-cols-4 grid-rows-2'}`}>
              {imageUrls.slice(0, imageUrls.length >= 4 ? 4 : imageUrls.length).map((img, idx) => {
                const isFirst = idx === 0 && imageUrls.length >= 4;
                return (
                  <div key={idx} className={`relative overflow-hidden cursor-zoom-in group bg-muted ${isFirst ? 'row-span-2 col-span-2' : ''}`}
                    onClick={() => { setLightboxIndex(idx); setLightboxOpen(true); }}>
                    <img src={img} alt="" aria-hidden className="absolute inset-0 w-full h-full object-cover scale-110 blur-2xl opacity-60" />
                    <img src={img} alt={`Photo ${idx + 1}`} className="relative w-full h-full object-contain group-hover:scale-105 transition-transform duration-500" />
                    <div className="absolute inset-0 bg-black/0 group-hover:bg-black/15 transition-colors" />
                    {idx === 3 && imageUrls.length > 4 && (
                      <div className="absolute inset-0 bg-black/60 flex items-center justify-center">
                        <span className="text-white text-2xl font-bold">+{imageUrls.length - 4}</span>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
          {/* Gradient overlay */}
          <div className="absolute inset-0 bg-gradient-to-t from-black/75 via-transparent to-transparent pointer-events-none" />
          {/* Title on image */}
          <div className="absolute bottom-5 left-6 right-6">
            <div className="flex flex-wrap items-center gap-2 mb-2">
              <Badge className="bg-white/20 backdrop-blur-sm text-white border-white/30 text-xs">
                {(service as any).service_category?.name || (service as any).category?.name || 'Service'}
              </Badge>
              {isPending && (
                <Badge className="bg-amber-500/90 text-white border-0 text-xs">Pending Review</Badge>
              )}
            </div>
            <h1 className="text-3xl font-bold text-white flex items-center gap-2">{service.title}</h1>
            {service.location && (
              <p className="text-white/80 text-sm mt-1.5 flex items-center gap-1">
                <img src={locationIcon} alt="location" className="w-3.5 h-3.5 dark:invert" />{service.location}
              </p>
            )}
          </div>
          {imageUrls.length > 1 && (
            <button onClick={() => { setLightboxIndex(0); setLightboxOpen(true); }}
              className="absolute top-4 right-4 bg-black/50 backdrop-blur-sm text-white text-xs px-3 py-1.5 rounded-full border border-white/20 hover:bg-black/70 transition-colors flex items-center gap-1.5">
              <ArrowUpRight className="w-3 h-3" />View all {imageUrls.length}
            </button>
          )}
        </div>
      ) : (
        <div className="relative rounded-2xl overflow-hidden mb-6 h-56 bg-gradient-to-br from-primary/20 via-primary/10 to-background border border-border">
          <div className="absolute inset-0 opacity-5" style={{ backgroundImage: 'radial-gradient(circle at 2px 2px, hsl(var(--primary)) 1px, transparent 0)', backgroundSize: '32px 32px' }} />
          <div className="absolute bottom-5 left-6 right-6 flex items-end justify-between">
            <div>
              <h1 className="text-3xl font-bold text-foreground">{service.title}</h1>
              <p className="text-muted-foreground mt-1">{(service as any).service_category?.name || 'Service'}</p>
            </div>
            <div className="w-16 h-16 rounded-2xl bg-primary/15 flex items-center justify-center">
              <Briefcase className="w-7 h-7 text-primary" />
            </div>
          </div>
        </div>
      )}

      {/* ─── KPI STRIP ─── */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
        {[
          { label: 'Total Revenue', value: totalRevenue > 0 ? formatPrice(totalRevenue) : '—', icon: DollarSign, color: 'text-emerald-600', bg: 'bg-emerald-50 dark:bg-emerald-950/30' },
          { label: 'Avg Rating', value: rating > 0 ? rating.toFixed(1) : '—', icon: Star, color: 'text-yellow-500', bg: 'bg-yellow-50 dark:bg-yellow-950/30' },
          { label: 'Upcoming', value: String(upcomingBookings.length), icon: Star, color: 'text-primary', bg: 'bg-primary/5' },
          { label: 'Completed', value: String((service as any).completed_events || 0), icon: TrendingUp, color: 'text-blue-600', bg: 'bg-blue-50 dark:bg-blue-950/30' },
        ].map(kpi => (
          <div key={kpi.label} className="bg-card border border-border rounded-2xl p-4 flex items-center gap-3">
            <div className={`w-10 h-10 rounded-xl ${kpi.bg} flex items-center justify-center shrink-0`}>
              <kpi.icon className={`w-5 h-5 ${kpi.color}`} />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">{kpi.label}</p>
              <p className="text-xl font-bold text-foreground">{kpi.value}</p>
            </div>
          </div>
        ))}
      </div>

      {/* ─── QUICK ACTIONS ─── */}
      <div className="flex flex-wrap gap-2 mb-6">
        <Button variant="outline" size="sm" asChild>
          <Link to={`/services/events/${id}`}><img src={calendarIcon} alt="calendar" className="w-4 h-4 mr-1.5 inline dark:invert" />{t("my_events")}</Link>
        </Button>
        {isPhotography && (
          <Button variant="outline" size="sm" asChild>
            <Link to={`/services/photo-libraries/${id}`}><img src={photosIcon} alt="photos" className="w-4 h-4 mr-1.5 inline dark:invert" />Photo Libraries</Link>
          </Button>
        )}
        <Button variant="outline" size="sm" asChild>
          <Link to={`/services/verify/${id}/${(service as any).service_type_name || 'service'}`}>
            <Shield className="w-4 h-4 mr-1.5" />KYC Status
          </Link>
        </Button>
      </div>

      {/* ─── TABS ─── */}
      <div className="flex gap-0 border border-border rounded-xl overflow-hidden mb-6 bg-muted/30">
        {TABS.map(tab => (
          <button key={tab.key} onClick={() => setActiveTab(tab.key)}
            className={`flex-1 py-2.5 text-sm font-medium transition-all ${activeTab === tab.key ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'}`}>
            {tab.label}
          </button>
        ))}
      </div>

      {/* ─── TAB: OVERVIEW ─── */}
      {activeTab === 'overview' && (
        <motion.div initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 space-y-5">

            {/* About */}
            {service.description && (
              <div className="bg-card border border-border rounded-2xl p-6">
                <h2 className="text-base font-semibold text-foreground mb-3">About This Service</h2>
                <p className="text-muted-foreground leading-relaxed whitespace-pre-wrap text-sm">{service.description}</p>
              </div>
            )}

            {/* Intro Media */}
            {introMedia.length > 0 && (
              <div className="bg-card border border-border rounded-2xl p-6">
                <h2 className="text-base font-semibold text-foreground mb-4 flex items-center gap-2">
                  <img src={VideoSVG} alt="" className="w-4 h-4 dark:invert" />Intro Clip
                </h2>
                <div className="space-y-3">
                  {introMedia.map((media) => (
                    <div key={media.id} className="rounded-xl overflow-hidden border border-border">
                      {media.media_type === 'video' ? (
                        <div className="aspect-video bg-black">
                          <video src={media.media_url} controls playsInline className="w-full h-full object-contain" />
                        </div>
                      ) : (
                        <div className="p-4 flex items-center gap-3 bg-gradient-to-r from-primary/5 to-transparent">
                          <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                            <Music className="w-6 h-6 text-primary" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-medium text-foreground mb-1">Audio Introduction</p>
                            <audio src={media.media_url} controls className="w-full h-8" />
                          </div>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              {[
                { label: 'Category', value: (typeof (service as any).category === 'string' ? (service as any).category : null) || (service as any).service_category?.name || (service as any).category?.name || service.service_type?.name || (service as any).service_type_name || '—', icon: Briefcase },
                { label: 'On Nuru', value: (() => { const created = (service as any).created_at; if (!created) return 'New'; const days = Math.floor((Date.now() - new Date(created).getTime()) / 86400000); if (days < 1) return 'Today'; if (days < 30) return `${days}d`; const months = Math.floor(days / 30); if (months < 12) return `${months}mo`; return `${Math.floor(months / 12)}yr`; })(), icon: Award },
                { label: 'Location', value: service.location || '—', icon: Briefcase, svgIcon: locationIcon },
                { label: 'Availability', value: service.availability || 'available', icon: Briefcase, svgIcon: calendarIcon },
              ].map(m => (
                <div key={m.label} className="bg-card border border-border rounded-xl p-4">
                  <div className="flex items-center gap-1.5 mb-1.5">
                    {(m as any).svgIcon
                      ? <img src={(m as any).svgIcon} alt={m.label} className="w-3.5 h-3.5 dark:invert" />
                      : <m.icon className="w-3.5 h-3.5 text-muted-foreground" />}
                    <p className="text-xs text-muted-foreground">{m.label}</p>
                  </div>
                  <p className="font-semibold text-foreground text-sm capitalize">{m.value}</p>
                </div>
              ))}
            </div>

            {/* Upcoming assignments */}
            {upcomingBookings.length > 0 && (
              <div className="bg-card border border-border rounded-2xl overflow-hidden">
                <div className="px-5 py-4 border-b border-border flex items-center justify-between">
                  <h2 className="font-semibold text-foreground text-sm">Upcoming Assignments</h2>
                  <Badge variant="outline" className="font-mono text-xs">{upcomingBookings.length}</Badge>
                </div>
                <div className="divide-y divide-border">
                  {upcomingBookings.slice(0, 5).map((b, i) => (
                    <div key={i} className="flex items-center gap-3 px-5 py-3.5">
                      <div className={`w-2.5 h-2.5 rounded-full shrink-0 ${getStatusColor(b.status)}`} />
                      <div className="flex-1 min-w-0">
                        <p className="font-medium text-foreground text-sm truncate">{b.event_name}</p>
                        <div className="flex items-center gap-2 mt-0.5">
                          <span className="text-xs text-muted-foreground">
                            {new Date(b.date).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}
                          </span>
                          {b.event_location && (
                            <span className="text-xs text-muted-foreground flex items-center gap-0.5">
                              <img src={locationIcon} alt="location" className="w-2.5 h-2.5 dark:invert" />{b.event_location}
                            </span>
                          )}
                        </div>
                      </div>
                      {b.agreed_price && (
                        <span className="text-sm font-semibold text-primary shrink-0">{formatPrice(b.agreed_price)}</span>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* RIGHT: Packages */}
          <div className="space-y-4">
            <div className="bg-card border border-border rounded-2xl overflow-hidden">
              <div className="px-5 py-4 border-b border-border flex items-center justify-between">
                <h2 className="font-semibold text-foreground text-sm">Packages</h2>
                {isVerified && (
                  <Button variant="ghost" size="sm" className="h-7 text-xs" asChild>
                    <Link to={`/services/edit/${id}`}>Manage</Link>
                  </Button>
                )}
              </div>
              {packages.length > 0 ? (
                <div className="divide-y divide-border">
                  {packages.map((pkg, idx) => (
                    <div key={pkg.id || idx} className={`p-5 ${idx === 0 ? 'bg-primary/3' : ''}`}>
                      <div className="flex items-start justify-between gap-2 mb-2">
                        <div>
                          <p className="font-semibold text-foreground text-sm">{pkg.name}</p>
                          {idx === 0 && <Badge className="text-[10px] mt-0.5 bg-primary/10 text-primary border-0 h-4">Top</Badge>}
                        </div>
                        <span className="text-primary font-bold text-sm whitespace-nowrap">{formatPrice(pkg.price)}</span>
                      </div>
                      {pkg.description && <p className="text-xs text-muted-foreground mb-3">{pkg.description}</p>}
                      {pkg.features?.length > 0 && (
                        <ul className="space-y-1.5">
                          {pkg.features.map((f, fi) => (
                            <li key={fi} className="flex items-start gap-2 text-xs text-muted-foreground">
                              <CheckCircle className="w-3.5 h-3.5 text-emerald-500 mt-0.5 shrink-0" />{f}
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>
                  ))}
                </div>
              ) : (
                <div className="p-5 text-center">
                  <p className="text-muted-foreground text-sm mb-3">No packages yet</p>
                  {isVerified && (
                    <Button size="sm" variant="outline" asChild>
                      <Link to={`/services/edit/${id}`}>Add Packages</Link>
                    </Button>
                  )}
                </div>
              )}
            </div>

            {/* Trust signals */}
            <div className="bg-card border border-border rounded-2xl p-5 space-y-3">
              <div className="flex items-center gap-3 text-sm">
                <Shield className={`w-5 h-5 shrink-0 ${isVerified ? 'text-emerald-500' : 'text-muted-foreground'}`} />
                <span className="text-muted-foreground">{isVerified ? 'Verified professional' : 'Verification pending'}</span>
              </div>
              <div className="flex items-center gap-3 text-sm">
                <Award className="w-5 h-5 text-primary shrink-0" />
                <span className="text-muted-foreground">
                  {(() => {
                    const created = (service as any).created_at;
                    if (!created) return 'Member of Nuru';
                    const diff = Date.now() - new Date(created).getTime();
                    const days = Math.floor(diff / 86400000);
                    if (days < 1) return 'Joined Nuru today';
                    if (days === 1) return '1 day on Nuru';
                    if (days < 30) return `${days} days on Nuru`;
                    const months = Math.floor(days / 30);
                    if (months < 12) return `${months} ${months === 1 ? 'month' : 'months'} on Nuru`;
                    const years = Math.floor(months / 12);
                    return `${years} ${years === 1 ? 'year' : 'years'} on Nuru`;
                  })()}
                </span>
              </div>
              <div className="flex items-center gap-3 text-sm">
                <Users className="w-5 h-5 text-blue-500 shrink-0" />
                <span className="text-muted-foreground">{(service as any).completed_events || 0} events completed</span>
              </div>
            </div>
          </div>
        </motion.div>
      )}

      {/* ─── TAB: CALENDAR ─── */}
      {activeTab === 'calendar' && (
        <motion.div initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }}
          className="bg-card border border-border rounded-2xl p-6">
          <div className="flex items-center gap-2 mb-5">
            <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
              <img src={calendarIcon} alt="calendar" className="w-4 h-4 dark:invert" />
            </div>
            <div>
              <h2 className="font-semibold text-foreground">Availability Calendar</h2>
              <p className="text-xs text-muted-foreground">Real-time view of your bookings. Hover booked dates for details.</p>
            </div>
          </div>

          {calendarLoading ? (
            <div className="space-y-3 pt-2">
              <div className="flex items-center justify-between">
                <Skeleton className="w-9 h-9 rounded-xl" />
                <Skeleton className="w-36 h-5" />
                <Skeleton className="w-9 h-9 rounded-xl" />
              </div>
              <div className="grid grid-cols-7 gap-1">
                {[...Array(35)].map((_, i) => <Skeleton key={i} className="h-12 rounded-xl" />)}
              </div>
            </div>
          ) : (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <button onClick={prevMonth} className="w-9 h-9 rounded-xl border border-border flex items-center justify-center hover:bg-muted transition-colors">
                  <ChevronLeft className="w-4 h-4" />
                </button>
                <span className="font-bold text-foreground text-lg">{MONTHS[currentMonth.getMonth()]} {currentMonth.getFullYear()}</span>
                <button onClick={nextMonth} className="w-9 h-9 rounded-xl border border-border flex items-center justify-center hover:bg-muted transition-colors">
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>

              <div className="grid grid-cols-7 gap-1">
                {DAYS.map(d => <div key={d} className="text-center text-xs font-semibold text-muted-foreground py-2">{d}</div>)}
              </div>

              <div className="grid grid-cols-7 gap-1">
                {calendarDays.map((cell, idx) => {
                  if (!cell.day) return <div key={`e-${idx}`} className="h-12" />;
                  const isBooked = !!cell.booking;
                  const dayEl = (
                    <div className={`relative h-12 rounded-xl flex flex-col items-center justify-center text-sm font-medium transition-all
                      ${cell.isToday ? 'ring-2 ring-primary bg-primary/10 text-primary' : ''}
                      ${isBooked ? `${getStatusColor(cell.booking!.status)} text-white shadow-sm cursor-pointer` : ''}
                      ${!isBooked && !cell.isPast && !cell.isToday ? 'bg-emerald-50 text-emerald-700 dark:bg-emerald-950/20 dark:text-emerald-400 hover:bg-emerald-100' : ''}
                      ${cell.isPast && !isBooked && !cell.isToday ? 'text-muted-foreground/30' : ''}
                    `}>
                      <span>{cell.day}</span>
                      {isBooked && <div className="absolute bottom-1 w-1 h-1 rounded-full bg-white/80" />}
                    </div>
                  );

                  if (isBooked) {
                    return (
                      <Popover key={cell.date}>
                        <PopoverTrigger asChild>{dayEl}</PopoverTrigger>
                        <PopoverContent side="top" className="max-w-[220px] p-3 rounded-xl">
                          <p className="font-semibold text-sm text-foreground mb-1">{cell.booking!.event_name}</p>
                          {cell.booking!.event_location && (
                            <p className="text-xs text-muted-foreground flex items-center gap-1 mb-1.5">
                              <img src={LocationIcon} alt="" className="w-3 h-3" />{cell.booking!.event_location}
                            </p>
                          )}
                          <div className="flex items-center gap-2">
                            <Badge variant="outline" className="text-[10px] capitalize">{cell.booking!.status}</Badge>
                            {cell.booking!.agreed_price && <span className="text-xs font-semibold text-primary">{formatPrice(cell.booking!.agreed_price)}</span>}
                          </div>
                        </PopoverContent>
                      </Popover>
                    );
                  }
                  return dayEl;
                })}
              </div>

              <div className="flex flex-wrap items-center gap-4 pt-3 border-t border-border text-xs text-muted-foreground">
                <span className="flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-amber-500" />Pending</span>
                <span className="flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-emerald-500" />Confirmed</span>
                <span className="flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-emerald-50 dark:bg-emerald-950/40 border border-emerald-200" />Available</span>
                <span className="flex items-center gap-1.5"><span className="w-3 h-3 rounded ring-2 ring-primary bg-primary/10" />Today</span>
              </div>
            </div>
          )}
        </motion.div>
      )}

      {/* ─── TAB: REVIEWS ─── */}
      {activeTab === 'reviews' && (
        <motion.div initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }}
          className="bg-card border border-border rounded-2xl p-6">
          <div className="flex items-center justify-between mb-5">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
                <Users className="w-4 h-4 text-primary" />
              </div>
              <h2 className="font-semibold text-foreground">Client Reviews</h2>
            </div>
            {rating > 0 && (
              <div className="flex items-center gap-2">
                <div className="flex">{renderStars(Math.round(rating))}</div>
                <span className="font-bold text-foreground">{rating.toFixed(1)}</span>
              </div>
            )}
          </div>

          {reviewsLoading ? (
            <div className="space-y-4 py-4">
              {[...Array(3)].map((_, i) => (
                <div key={i} className="flex gap-4">
                  <Skeleton className="w-10 h-10 rounded-full shrink-0" />
                  <div className="flex-1 space-y-2">
                    <Skeleton className="h-3 w-1/3" />
                    <Skeleton className="h-3 w-full" />
                    <Skeleton className="h-3 w-4/5" />
                  </div>
                </div>
              ))}
            </div>
          ) : reviews.length > 0 ? (
            <div className="space-y-5">
              {reviews.map((review, i) => {
                const avatar = (review as any).user_avatar || (review as any).reviewer_avatar || (review as any).user?.avatar;
                return (
                  <motion.div key={review.id} initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: i * 0.05 }}
                    className="flex gap-4 pb-5 border-b border-border last:border-0 last:pb-0">
                    <Avatar className="w-9 h-9 shrink-0">
                      {avatar && <AvatarImage src={avatar} />}
                      <AvatarFallback className="bg-primary/10 text-primary text-xs font-bold">
                        {(review.user_name || 'A').split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()}
                      </AvatarFallback>
                    </Avatar>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-start justify-between gap-2 mb-1">
                        <div>
                          <p className="font-semibold text-foreground text-sm">{review.user_name || 'Anonymous'}</p>
                          <p className="text-xs text-muted-foreground">
                            {review.created_at ? new Date(review.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' }) : ''}
                          </p>
                        </div>
                        <div className="flex shrink-0">{renderStars(review.rating)}</div>
                      </div>
                      <p className="text-muted-foreground text-sm leading-relaxed">{review.comment}</p>
                    </div>
                  </motion.div>
                );
              })}
            </div>
          ) : (
            <div className="text-center py-12">
              <Star className="w-12 h-12 text-muted-foreground/15 mx-auto mb-3" />
              <p className="text-muted-foreground">No reviews yet</p>
              <p className="text-xs text-muted-foreground mt-1">Reviews appear after completing events</p>
            </div>
          )}
        </motion.div>
      )}

      {/* ─── TAB: PAYMENTS ─── */}
      {activeTab === 'payments' && id && (
        <motion.div initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }}>
          <ReceivedPaymentsPanel
            source={{ kind: 'service', serviceId: id }}
            title="Payments received for this service"
          />
        </motion.div>
      )}

      <AnimatePresence>
        {lightboxOpen && hasImages && (
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 bg-black/95 flex items-center justify-center p-4"
            onClick={() => setLightboxOpen(false)}>
            <motion.div initial={{ scale: 0.95 }} animate={{ scale: 1 }} exit={{ scale: 0.95 }}
              className="relative max-w-5xl w-full" onClick={e => e.stopPropagation()}>
              <button onClick={() => setLightboxOpen(false)} className="absolute -top-10 right-0 text-white/70 hover:text-white flex items-center gap-1 text-sm transition-colors">
                <X className="w-5 h-5" /> Close
              </button>
              <img src={imageUrls[lightboxIndex]} alt={`Photo ${lightboxIndex + 1}`} className="max-w-full max-h-[80vh] object-contain rounded-xl mx-auto block" />
              {imageUrls.length > 1 && (
                <>
                  <button onClick={() => setLightboxIndex(i => (i - 1 + imageUrls.length) % imageUrls.length)}
                    className="absolute left-2 top-1/2 -translate-y-1/2 w-10 h-10 rounded-full bg-white/10 hover:bg-white/20 flex items-center justify-center text-white transition-colors">
                    <ChevronLeft className="w-5 h-5" />
                  </button>
                  <button onClick={() => setLightboxIndex(i => (i + 1) % imageUrls.length)}
                    className="absolute right-2 top-1/2 -translate-y-1/2 w-10 h-10 rounded-full bg-white/10 hover:bg-white/20 flex items-center justify-center text-white transition-colors">
                    <ChevronRight className="w-5 h-5" />
                  </button>
                  <div className="flex justify-center gap-1.5 mt-4">
                    {imageUrls.map((_, i) => (
                      <button key={i} onClick={() => setLightboxIndex(i)}
                        className={`w-2 h-2 rounded-full transition-all ${i === lightboxIndex ? 'bg-white scale-125' : 'bg-white/40'}`} />
                    ))}
                  </div>
                </>
              )}
              <p className="text-center text-white/40 text-xs mt-3">{lightboxIndex + 1} / {imageUrls.length}</p>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

export default ServiceDetail;
