import { useNavigate } from 'react-router-dom';
import { useCurrency } from '@/hooks/useCurrency';
import { Star, CheckCircle, Users, Plus, Edit, Loader2, Camera, MapPin, ChevronRight, BookOpen, Upload, Trash2, X, Music } from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import CalendarSVG from '@/assets/icons/calendar-icon.svg';
import PhotosSVG from '@/assets/icons/photos-icon.svg';
import ViewSVG from '@/assets/icons/view-icon.svg';
import PackageSVG from '@/assets/icons/package-icon.svg';
import VideoSVG from '@/assets/icons/video-icon.svg';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { useWorkspaceMeta } from '@/hooks/useWorkspaceMeta';
import { useUserServices } from '@/data/useUserServices';
import { useRef, useState } from 'react';
import { ServiceLoadingSkeleton } from '@/components/ui/ServiceLoadingSkeleton';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { showApiErrors, showCaughtError } from '@/lib/api';
import { userServicesApi } from '@/lib/api';
import type { ServiceReview } from '@/lib/api/types';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import SearchHeader from '@/components/ui/search-header';
import MigrationBanner from '@/components/migration/MigrationBanner';

// Detect if a service is photography type
const isPhotographyService = (service: any): boolean => {
  const name = (service.service_type_name || service.service_type?.name || service.category || '').toLowerCase();
  return name.includes('photo') || name.includes('cinema') || name.includes('video') || name.includes('film');
};

const MyServices = () => {
  const { format: formatPrice, currency } = useCurrency();
  const { t } = useLanguage();
  useWorkspaceMeta({
    title: 'My Services',
    description: 'Manage your service offerings, track performance, and connect with event organizers.'
  });

  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const { services, summary, recentReviews, loading, error, refetch } = useUserServices(search);

  const reviews = (recentReviews || []).map((r: any) => ({
    id: r.id,
    rating: r.rating,
    comment: r.comment,
    user_name: r.user_name,
    user_avatar: r.user_avatar,
    created_at: r.created_at,
    service_title: r.service_title,
    service_id: r.service_id || '',
    user_id: '',
    verified_booking: false,
  })) as ServiceReview[];

  const reviewsLoading = loading;
  const [packageDialogOpen, setPackageDialogOpen] = useState(false);
  const [selectedServiceId, setSelectedServiceId] = useState<string | null>(null);
  const [packageForm, setPackageForm] = useState({ name: '', description: '', features: '', price: '' });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [imageDialogService, setImageDialogService] = useState<any | null>(null);
  const [imageUploading, setImageUploading] = useState(false);
  const [deletingImageId, setDeletingImageId] = useState<string | null>(null);
  const imageFileRef = useRef<HTMLInputElement>(null);

  // Intro media dialog state
  const [mediaDialogService, setMediaDialogService] = useState<any | null>(null);
  const [mediaList, setMediaList] = useState<Array<{ id: string; media_type: string; media_url: string }>>([]);
  const [mediaLoading, setMediaLoading] = useState(false);
  const [pendingMediaFile, setPendingMediaFile] = useState<File | null>(null);
  const [mediaUploading, setMediaUploading] = useState(false);
  const [deletingMediaId, setDeletingMediaId] = useState<string | null>(null);
  const mediaFileRef = useRef<HTMLInputElement>(null);

  const handleAddPackage = (serviceId: string) => {
    setSelectedServiceId(serviceId);
    setPackageDialogOpen(true);
  };

  const handleImageUpload = async (files: FileList | null) => {
    if (!files || files.length === 0 || !imageDialogService) return;
    setImageUploading(true);
    let success = 0;
    for (const file of Array.from(files)) {
      if (!file.type.startsWith('image/')) { toast.error(`${file.name}: only images allowed`); continue; }
      if (file.size > 5 * 1024 * 1024) { toast.error(`${file.name}: File is too large (${(file.size / (1024 * 1024)).toFixed(1)}MB). Maximum allowed is 5MB`); continue; }
      try {
        const form = new FormData();
        form.append('images', file);
        const res = await userServicesApi.addImages(imageDialogService.id, form);
        if (!showApiErrors(res)) success++;
      } catch (err) { showCaughtError(err); }
    }
    setImageUploading(false);
    if (success > 0) {
      toast.success(`${success} photo${success > 1 ? 's' : ''} added!`);
      await refetch();
      setImageDialogService(null);
    }
  };

  const handleDeleteImage = async (imageId: string) => {
    if (!imageDialogService) return;
    setDeletingImageId(imageId);
    try {
      const res = await userServicesApi.deleteImage(imageDialogService.id, imageId);
      if (!showApiErrors(res)) {
        toast.success('Photo removed');
        await refetch();
        setImageDialogService((prev: any) => {
          const updated = services.find((s: any) => s.id === prev?.id);
          return updated || prev;
        });
      }
    } catch (err) { showCaughtError(err); }
    finally { setDeletingImageId(null); }
  };

  // ─── INTRO MEDIA HANDLERS ───
  const openMediaDialog = async (service: any) => {
    setMediaDialogService(service);
    setMediaList([]);
    setPendingMediaFile(null);
    setMediaLoading(true);
    try {
      const res = await userServicesApi.getIntroMedia(service.id);
      if (res.success && res.data) setMediaList(Array.isArray(res.data) ? res.data : []);
    } catch { /* silent */ }
    finally { setMediaLoading(false); }
  };

  const handleMediaSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const isVideo = file.type.startsWith('video/');
    const isAudio = file.type.startsWith('audio/');
    if (!isVideo && !isAudio) { toast.error('Please select a video or audio file'); return; }
    setPendingMediaFile(file);
    if (mediaFileRef.current) mediaFileRef.current.value = '';
  };

  const handleConfirmMediaUpload = async () => {
    if (!pendingMediaFile || !mediaDialogService) return;
    const isVideo = pendingMediaFile.type.startsWith('video/');
    setMediaUploading(true);
    try {
      const form = new FormData();
      form.append('media_type', isVideo ? 'video' : 'audio');
      form.append('media', pendingMediaFile);
      const res = await userServicesApi.addIntroMedia(mediaDialogService.id, form);
      if (res.success && res.data) {
        setMediaList(prev => [...prev, res.data as any]);
        toast.success('Intro clip uploaded!');
        setPendingMediaFile(null);
      } else { showApiErrors(res); }
    } catch (err) { showCaughtError(err); }
    finally { setMediaUploading(false); }
  };

  const handleDeleteMedia = async (mediaId: string) => {
    if (!mediaDialogService) return;
    setDeletingMediaId(mediaId);
    try {
      const res = await userServicesApi.deleteIntroMedia(mediaDialogService.id, mediaId);
      if (res.success) {
        setMediaList(prev => prev.filter(m => m.id !== mediaId));
        toast.success('Intro clip removed');
      } else { showApiErrors(res); }
    } catch (err) { showCaughtError(err); }
    finally { setDeletingMediaId(null); }
  };


  const handleSavePackage = async () => {
    if (!selectedServiceId) return;
    if (!packageForm.name.trim()) { toast.error('Please provide a package name.'); return; }
    if (!packageForm.description.trim()) { toast.error('Please include a brief description.'); return; }
    if (!packageForm.price || Number(packageForm.price) <= 0) { toast.error('Please enter a valid price.'); return; }
    if (!packageForm.features.trim()) { toast.error('Please list at least one feature.'); return; }

    setIsSubmitting(true);
    try {
      const result = await userServicesApi.addPackage(selectedServiceId, {
        name: packageForm.name.trim(),
        description: packageForm.description.trim(),
        price: Number(packageForm.price),
        features: packageForm.features.split(',').map(f => f.trim()).filter(Boolean),
      });
      if (showApiErrors(result, 'Failed to add package.')) return;
      toast.success(result.message || 'Package added successfully.');
      setPackageDialogOpen(false);
      setPackageForm({ name: '', description: '', features: '', price: '' });
      setSelectedServiceId(null);
    } catch (err: any) { showCaughtError(err); }
    finally { setIsSubmitting(false); }
  };

  const renderStars = (rating: number) => Array.from({ length: 5 }, (_, i) => (
    <Star key={i} className={`w-3.5 h-3.5 ${i < Math.floor(rating) ? 'text-yellow-400 fill-current' : i < rating ? 'text-yellow-400 fill-current opacity-50' : 'text-muted-foreground/30'}`} />
  ));

  const getImageUrl = (img: any): string => {
    if (typeof img === 'string') return img;
    if (img && typeof img === 'object') return img.url || img.image_url || img.file_url || '';
    return '';
  };

  const getServiceImages = (service: any): any[] => {
    if (Array.isArray(service.images) && service.images.length > 0) return service.images;
    if (service.primary_image) return [{ url: service.primary_image }];
    return [];
  };

  const formatPriceDisplay = (service: any): string => {
    if (service.min_price && service.max_price) return `${formatPrice(service.min_price)} – ${formatPrice(service.max_price)}`;
    if (service.min_price) return `From ${formatPrice(service.min_price)}`;
    return 'Price on request';
  };

  const getCategoryName = (service: any): string => service.category || service.service_category?.name || 'Uncategorized';
  const getServiceTypeName = (service: any): string => service.service_type_name || service.service_type?.name || '';

  if (loading && !search) return <ServiceLoadingSkeleton />;
  if (error) return <p className="text-destructive">{error}</p>;

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 sm:gap-4">
        <div className="min-w-0">
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight break-words leading-tight">{t("my_services")}</h1>
          <p className="text-sm text-muted-foreground mt-1">Your professional portfolio on Nuru</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <SearchHeader
            value={search}
            onChange={setSearch}
            placeholder="Search your services…"
          />
          <Button size="lg" className="shadow-md flex-1 sm:flex-none" onClick={() => navigate('/services/new')}>
            <Plus className="w-4 h-4 mr-2" />
            <span className="hidden sm:inline">Add New Service</span>
            <span className="sm:hidden">Add Service</span>
          </Button>
        </div>
      </div>

      {/* Stats Row */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {[
          { label: 'Services', value: services.length, icon: <img src={PackageSVG} alt="" className="w-5 h-5 dark:invert" />, color: 'text-primary', bg: 'bg-primary/10' },
          { label: 'Avg Rating', value: summary?.average_rating != null && summary.average_rating > 0 ? Number(summary.average_rating).toFixed(1) : '–', icon: <Star className="w-5 h-5" />, color: 'text-yellow-600', bg: 'bg-yellow-100 dark:bg-yellow-900/30' },
          { label: 'Total Reviews', value: summary?.total_reviews ?? services.reduce((s, x) => s + (x.review_count || 0), 0), icon: <Users className="w-5 h-5" />, color: 'text-blue-600', bg: 'bg-blue-100 dark:bg-blue-900/30' },
          { label: 'Completed Events', value: services.reduce((s, x) => s + (x.completed_events || 0), 0), icon: <CheckCircle className="w-5 h-5" />, color: 'text-green-600', bg: 'bg-green-100 dark:bg-green-900/30' },
        ].map((stat, i) => (
          <Card key={i} className="border-border/60">
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide">{stat.label}</p>
                  <p className="text-2xl font-bold mt-1">{stat.value}</p>
                </div>
                <div className={`w-11 h-11 ${stat.bg} rounded-xl flex items-center justify-center ${stat.color}`}>
                  {stat.icon}
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Services Portfolio — 4 cards per row on large screens */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
        {services.map((service) => {
          const images = getServiceImages(service);
          const cover = images.length > 0 ? getImageUrl(images[0]) : '';
          const isPhoto = isPhotographyService(service);
          const isVerified = service.verification_status === 'verified';

          return (
            <Card key={service.id} className="overflow-hidden border-border/60 shadow-sm hover:shadow-lg transition-all flex flex-col group">
              {/* Single cover image — clean, consistent ratio */}
              <div className="relative aspect-[4/3] bg-muted overflow-hidden">
                {cover ? (
                  <img
                    src={cover}
                    alt={service.title}
                    loading="lazy"
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center bg-gradient-to-br from-primary/5 to-primary/10">
                    <img src={PackageSVG} alt="" className="w-10 h-10 opacity-40 dark:invert" />
                  </div>
                )}

                {/* Status badge */}
                <div className="absolute top-2 left-2 flex gap-2">
                  {!isVerified && service.verification_status === 'pending' && (
                    <Badge className="bg-amber-500/95 text-white border-0 shadow text-[10px] px-2 py-0.5">Pending</Badge>
                  )}
                  {isVerified && (
                    <Badge className="bg-green-500/95 text-white border-0 shadow text-[10px] px-2 py-0.5">Verified</Badge>
                  )}
                </div>

                {/* Image count chip */}
                {images.length > 1 && (
                  <div className="absolute bottom-2 right-2 bg-black/60 text-white text-[10px] px-2 py-0.5 rounded-full">
                    {images.length} photos
                  </div>
                )}
              </div>

              <CardContent className="p-4 flex-1 flex flex-col gap-3">
                {/* Title + category */}
                <div className="min-w-0">
                  <h3 className="font-bold text-base leading-tight line-clamp-1">{service.title}</h3>
                  <div className="flex items-center gap-1.5 flex-wrap mt-1.5">
                    <Badge variant="secondary" className="text-[10px] px-1.5 py-0">{getCategoryName(service)}</Badge>
                    {getServiceTypeName(service) && (
                      <Badge variant="outline" className="text-[10px] px-1.5 py-0 border-primary/30 text-primary bg-primary/5">
                        {getServiceTypeName(service)}
                      </Badge>
                    )}
                  </div>
                </div>

                {/* Rating + location */}
                <div className="flex items-center justify-between text-xs text-muted-foreground">
                  <div className="flex items-center gap-1">
                    {renderStars(service.rating || 0)}
                    <span className="ml-0.5 font-semibold text-foreground">{(service.rating || 0).toFixed(1)}</span>
                    <span>({service.review_count || 0})</span>
                  </div>
                  <div className="flex items-center gap-1 truncate max-w-[45%]">
                    <MapPin className="w-3 h-3 flex-shrink-0" />
                    <span className="truncate">{service.location || '—'}</span>
                  </div>
                </div>

                {/* Description */}
                {service.description && (
                  <p className="text-muted-foreground text-xs leading-relaxed line-clamp-2">{service.description}</p>
                )}

                {/* Price */}
                <div className="text-sm font-bold text-primary mt-auto">{formatPriceDisplay(service)}</div>

                {/* Verification CTA (compact) */}
                {!isVerified && (
                  <Button variant="outline" size="sm" className="w-full text-xs border-amber-300 text-amber-700 hover:bg-amber-50 dark:hover:bg-amber-900/20"
                    onClick={() => navigate(`/services/verify/${service.id}/${service.service_type_id || 'default'}`)}>
                    Activate - {service.verification_progress || 0}%
                  </Button>
                )}

                {/* Primary actions */}
                <div className="grid grid-cols-2 gap-2">
                  <Button size="sm" variant="outline" className="text-xs" onClick={() => navigate(`/service/${service.id}`)}>
                    <img src={ViewSVG} alt="" className="w-3 h-3 mr-1 dark:invert" /> View
                  </Button>
                  <Button size="sm" variant="outline" className="text-xs" onClick={() => navigate(`/services/edit/${service.id}`)}>
                    <Edit className="w-3 h-3 mr-1" /> Edit
                  </Button>
                  <Button size="sm" variant="outline" className="text-xs" onClick={() => setImageDialogService(service)}>
                    <img src={PhotosSVG} alt="" className="w-3 h-3 mr-1 dark:invert" /> Photos
                  </Button>
                  <Button size="sm" variant="outline" className="text-xs" onClick={() => navigate(`/bookings?service=${service.id}`)}>
                    <BookOpen className="w-3 h-3 mr-1" /> Bookings
                  </Button>
                  {isVerified && (
                    <Button size="sm" variant="outline" className="text-xs col-span-2" onClick={() => handleAddPackage(service.id)}>
                      <img src={PackageSVG} alt="" className="w-3 h-3 mr-1 dark:invert" /> Add Package
                    </Button>
                  )}
                  {isPhoto && isVerified && (
                    <Button size="sm" variant="outline" className="text-xs col-span-2 border-purple-300 text-purple-700 hover:bg-purple-50 dark:text-purple-300 dark:border-purple-700"
                      onClick={() => navigate(`/services/photo-libraries/${service.id}`)}>
                      <img src={PhotosSVG} alt="" className="w-3 h-3 mr-1 dark:invert" /> Photo Libraries
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          );
        })}

        {services.length === 0 && (
          <div className="col-span-full text-center py-20 border-2 border-dashed border-muted-foreground/20 rounded-2xl">
            <div className="w-20 h-20 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-6">
              <img src={PackageSVG} alt="" className="w-10 h-10 dark:invert" />
            </div>
            <h3 className="text-xl font-bold mb-2">No Services Yet</h3>
            <p className="text-muted-foreground mb-6 max-w-md mx-auto">
              Create your first service to start connecting with event organizers and growing your business on Nuru.
            </p>
            <Button size="lg" onClick={() => navigate('/services/new')}>
              <Plus className="w-5 h-5 mr-2" />
              Create Your First Service
            </Button>
          </div>
        )}
      </div>

      {/* Recent Reviews */}
      {reviews.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Star className="w-5 h-5 text-yellow-500 fill-current" />
              Recent Reviews
            </CardTitle>
          </CardHeader>
          <CardContent>
            {reviewsLoading ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
              </div>
            ) : (
              <div className="space-y-4">
                {reviews.map((review: any) => (
                  <div key={review.id} className="flex gap-4 p-4 border rounded-xl hover:bg-muted/30 transition-colors">
                    <Avatar className="flex-shrink-0">
                      <AvatarImage src={review.user_avatar} alt={review.user_name} />
                      <AvatarFallback className="bg-primary/10 text-primary font-semibold">
                        {review.user_name ? review.user_name.slice(0, 2).toUpperCase() : 'U'}
                      </AvatarFallback>
                    </Avatar>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1 flex-wrap">
                        <h4 className="font-semibold text-sm">{review.user_name}</h4>
                        <div className="flex items-center gap-0.5">{renderStars(review.rating)}</div>
                        {review.service_title && <Badge variant="secondary" className="text-xs">{review.service_title}</Badge>}
                      </div>
                      <p className="text-muted-foreground text-sm">{review.comment}</p>
                      <p className="text-xs text-muted-foreground mt-1">
                        {review.created_at ? new Date(review.created_at).toLocaleDateString() : ''}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Add Package Dialog */}
      <Dialog open={packageDialogOpen} onOpenChange={setPackageDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Add Service Package</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Package Name</Label>
              <Input value={packageForm.name} onChange={(e) => setPackageForm(f => ({ ...f, name: e.target.value }))} placeholder="e.g. Basic, Premium, Gold" />
            </div>
            <div className="space-y-2">
              <Label>Description</Label>
              <Textarea value={packageForm.description} onChange={(e) => setPackageForm(f => ({ ...f, description: e.target.value }))} placeholder="Brief description..." rows={2} />
            </div>
            <div className="space-y-2">
              <Label>Price ({currency})</Label>
              <Input type="number" min="0" value={packageForm.price} onChange={(e) => setPackageForm(f => ({ ...f, price: e.target.value }))} placeholder={currency === "KES" ? "e.g. 6000" : "e.g. 150000"} />
            </div>
            <div className="space-y-2">
              <Label>Features (comma-separated)</Label>
              <Textarea value={packageForm.features} onChange={(e) => setPackageForm(f => ({ ...f, features: e.target.value }))} placeholder="e.g. 5 hours coverage, 200 edited photos, Online gallery" rows={2} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPackageDialogOpen(false)}>Cancel</Button>
            <Button onClick={handleSavePackage} disabled={isSubmitting}>
              {isSubmitting ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
              {isSubmitting ? 'Saving...' : 'Save Package'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ─── PHOTO MANAGEMENT DIALOG ─── */}
      <Dialog open={!!imageDialogService} onOpenChange={(open) => { if (!open) setImageDialogService(null); }}>
        <DialogContent className="sm:max-w-2xl max-h-[85vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <img src={PhotosSVG} alt="" className="w-5 h-5 dark:invert" />
              Manage Photos
              {imageDialogService && (
                <span className="text-sm font-normal text-muted-foreground truncate">— {imageDialogService.title}</span>
              )}
            </DialogTitle>
          </DialogHeader>

          {imageDialogService && (() => {
            const imgs = getServiceImages(imageDialogService);
            return (
              <div className="flex-1 min-h-0 overflow-y-auto space-y-5 pr-1">
                {/* Upload zone */}
                <div
                  className="border-2 border-dashed border-border rounded-2xl p-8 text-center cursor-pointer hover:border-primary/50 hover:bg-primary/5 transition-all"
                  onClick={() => imageFileRef.current?.click()}
                >
                  {imageUploading ? (
                    <div className="flex flex-col items-center gap-2">
                      <Loader2 className="w-8 h-8 animate-spin text-primary" />
                      <p className="text-sm text-muted-foreground">Uploading photos…</p>
                    </div>
                  ) : (
                    <>
                      <div className="w-14 h-14 bg-primary/10 rounded-2xl flex items-center justify-center mx-auto mb-3">
                        <Upload className="w-7 h-7 text-primary" />
                      </div>
                      <p className="font-semibold text-foreground mb-1">Click to upload photos</p>
                      <p className="text-xs text-muted-foreground">PNG, JPG or WebP - Max 5MB per file</p>
                    </>
                  )}
                  <input
                    ref={imageFileRef}
                    type="file"
                    multiple
                    accept="image/*"
                    className="hidden"
                    onChange={e => handleImageUpload(e.target.files)}
                  />
                </div>

                {/* Existing photos grid */}
                {imgs.length > 0 ? (
                  <>
                    <p className="text-sm font-semibold text-foreground">{imgs.length} photo{imgs.length !== 1 ? 's' : ''}</p>
                    <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                      {imgs.map((img: any, idx: number) => {
                        const url = getImageUrl(img);
                        const imgId = img?.id || img?.image_id || String(idx);
                        return (
                          <div key={imgId} className="relative group rounded-xl overflow-hidden bg-muted aspect-square border border-border">
                            <img src={url} alt={`Photo ${idx + 1}`} className="w-full h-full object-cover" />
                            <div className="absolute inset-0 bg-black/0 group-hover:bg-black/50 transition-all flex items-center justify-center opacity-0 group-hover:opacity-100">
                              <button
                                onClick={() => handleDeleteImage(imgId)}
                                disabled={deletingImageId === imgId}
                                className="p-2.5 bg-destructive/90 hover:bg-destructive rounded-full transition-colors shadow-lg"
                              >
                                {deletingImageId === imgId
                                  ? <Loader2 className="w-4 h-4 text-white animate-spin" />
                                  : <Trash2 className="w-4 h-4 text-white" />
                                }
                              </button>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </>
                ) : (
                  <div className="text-center py-6 text-muted-foreground">
                    <Camera className="w-10 h-10 mx-auto mb-2 opacity-30" />
                    <p className="text-sm">No photos yet. Upload your first photo above.</p>
                  </div>
                )}
              </div>
            );
          })()}

          <DialogFooter className="pt-4 border-t border-border mt-4">
            <Button variant="outline" onClick={() => setImageDialogService(null)}>Done</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ─── INTRO MEDIA DIALOG ─── */}
      <Dialog open={!!mediaDialogService} onOpenChange={(open) => { if (!open) { setMediaDialogService(null); setPendingMediaFile(null); } }}>
        <DialogContent className="sm:max-w-xl max-h-[85vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <img src={VideoSVG} alt="" className="w-5 h-5 dark:invert" />
              Intro Clip
              {mediaDialogService && (
                <span className="text-sm font-normal text-muted-foreground truncate">— {mediaDialogService.title}</span>
              )}
            </DialogTitle>
          </DialogHeader>

          <div className="flex-1 min-h-0 overflow-y-auto space-y-4 pr-1">
            {mediaLoading ? (
              <div className="flex items-center justify-center py-12">
                <Loader2 className="w-8 h-8 animate-spin text-primary" />
              </div>
            ) : (
              <>
                {/* Existing media */}
                {mediaList.map((media) => (
                  <div key={media.id} className="rounded-xl border border-border overflow-hidden">
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
                          <p className="text-sm font-medium text-foreground mb-1">Audio Clip</p>
                          <audio src={media.media_url} controls className="w-full h-8" />
                        </div>
                      </div>
                    )}
                    <div className="flex items-center justify-between px-4 py-2.5 border-t border-border">
                      <p className="text-xs text-muted-foreground capitalize">{media.media_type} intro</p>
                      <Button type="button" variant="ghost" size="sm"
                        className="text-destructive hover:text-destructive h-7 px-2 text-xs"
                        onClick={() => handleDeleteMedia(media.id)} disabled={deletingMediaId === media.id}>
                        {deletingMediaId === media.id ? <Loader2 className="w-3.5 h-3.5 animate-spin mr-1" /> : <Trash2 className="w-3.5 h-3.5 mr-1" />}
                        Remove
                      </Button>
                    </div>
                  </div>
                ))}

                {/* Pending file preview */}
                {pendingMediaFile && (
                  <div className="rounded-xl border-2 border-primary/30 bg-primary/5 overflow-hidden">
                    {pendingMediaFile.type.startsWith('video/') ? (
                      <div className="aspect-video bg-black">
                        <video src={URL.createObjectURL(pendingMediaFile)} controls playsInline className="w-full h-full object-contain" />
                      </div>
                    ) : (
                      <div className="p-4 flex items-center gap-3">
                        <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                          <Music className="w-6 h-6 text-primary" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-foreground mb-1">{pendingMediaFile.name}</p>
                          <audio src={URL.createObjectURL(pendingMediaFile)} controls className="w-full h-8" />
                        </div>
                      </div>
                    )}
                    <div className="flex items-center justify-between px-4 py-3 border-t border-primary/20">
                      <p className="text-xs text-muted-foreground">{(pendingMediaFile.size / (1024 * 1024)).toFixed(1)} MB</p>
                      <div className="flex gap-2">
                        <Button type="button" variant="outline" size="sm" onClick={() => setPendingMediaFile(null)} className="h-8">Cancel</Button>
                        <Button type="button" size="sm" onClick={handleConfirmMediaUpload} disabled={mediaUploading} className="h-8">
                          {mediaUploading ? <><Loader2 className="w-3.5 h-3.5 mr-1.5 animate-spin" />Uploading...</> : <><Upload className="w-3.5 h-3.5 mr-1.5" />Upload</>}
                        </Button>
                      </div>
                    </div>
                  </div>
                )}

                {/* Upload zone */}
                {!pendingMediaFile && (
                  <div
                    className="border-2 border-dashed border-border rounded-2xl p-8 text-center cursor-pointer hover:border-primary/50 hover:bg-primary/5 transition-all"
                    onClick={() => mediaFileRef.current?.click()}
                  >
                    <div className="flex items-center justify-center gap-2 mb-3">
                      <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
                        <img src={VideoSVG} alt="" className="w-5 h-5 dark:invert" />
                      </div>
                      <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
                        <Music className="w-5 h-5 text-primary" />
                      </div>
                    </div>
                    <p className="font-semibold text-foreground mb-1">Add intro clip</p>
                    <p className="text-xs text-muted-foreground">Video or audio - Max 1 minute</p>
                    <input ref={mediaFileRef} type="file" accept="video/*,audio/*" className="hidden" onChange={handleMediaSelect} />
                  </div>
                )}

                {mediaList.length === 0 && !pendingMediaFile && (
                  <p className="text-center text-sm text-muted-foreground py-2">No intro clip yet. Add one to introduce your service!</p>
                )}
              </>
            )}
          </div>

          <DialogFooter className="pt-4 border-t border-border mt-4">
            <Button variant="outline" onClick={() => { setMediaDialogService(null); setPendingMediaFile(null); }}>Done</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default MyServices;
