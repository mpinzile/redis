import { useState, useEffect, useCallback, useRef } from 'react';
import { downloadFile } from '@/utils/downloadFile';
import { useParams, useNavigate } from 'react-router-dom';
import {
  ChevronLeft, ChevronRight, Upload, Trash2, Globe, Lock,
  CheckCircle2, Clock, X, ZoomIn, Calendar, MapPin,
  Check, AlertCircle, HardDrive, Download
} from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import ShareIcon from '@/assets/icons/share-icon.svg';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { Skeleton } from '@/components/ui/skeleton';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { photoLibrariesApi, PhotoLibrary } from '@/lib/api/photoLibraries';
import { showApiErrors, showCaughtError } from '@/lib/api';
import { useWorkspaceMeta } from '@/hooks/useWorkspaceMeta';
import PhotosIcon from '@/assets/icons/photos-icon.svg';
import MediaThumb from '@/components/MediaThumb';
import { useLanguage } from '@/lib/i18n/LanguageContext';

const MAX_IMAGE_MB = 10;
const STORAGE_LIMIT_MB = 200;

// ─── Module-level cache ───
const _libCache: Record<string, { library: PhotoLibrary; ts: number }> = {};

const PhotoLibraryDetail = () => {
  const { t } = useLanguage();
  const { libraryId } = useParams<{ libraryId: string }>();
  const navigate = useNavigate();
  const cached = libraryId ? _libCache[libraryId] : null;
  const [library, setLibrary] = useState<PhotoLibrary | null>(cached?.library || null);
  const [loading, setLoading] = useState(!cached);
  const [uploading, setUploading] = useState(false);
  const [uploadQueue, setUploadQueue] = useState<{ file: File; status: 'pending' | 'uploading' | 'done' | 'error' }[]>([]);
  const [lightboxIdx, setLightboxIdx] = useState<number | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [privacy, setPrivacy] = useState<'public' | 'event_creator_only'>(cached?.library.privacy || 'event_creator_only');
  const [description, setDescription] = useState(cached?.library.description || '');
  const [savingSettings, setSavingSettings] = useState(false);
  const [copied, setCopied] = useState(false);
  const [deletePhotoId, setDeletePhotoId] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const initialLoad = useRef(!cached);

  useWorkspaceMeta({
    title: library?.name || 'Photo Library',
    description: 'Manage event photo library'
  });

  const fetchLibrary = useCallback(async () => {
    if (!libraryId) return;
    if (initialLoad.current) setLoading(true);
    try {
      const res = await photoLibrariesApi.getLibrary(libraryId);
      if (res.success && res.data) {
        _libCache[libraryId] = { library: res.data, ts: Date.now() };
        initialLoad.current = false;
        setLibrary(res.data);
        setPrivacy(res.data.privacy);
        setDescription(res.data.description || '');
      }
    } catch (err) { showCaughtError(err); }
    finally { setLoading(false); }
  }, [libraryId]);

  useEffect(() => { fetchLibrary(); }, [fetchLibrary]);

  const handleFilesSelected = async (files: FileList | null) => {
    if (!files || files.length === 0 || !libraryId) return;
    const validFiles: File[] = [];
    for (const file of Array.from(files)) {
      if (!file.type.startsWith('image/')) { toast.error(`${file.name}: Only image files allowed`); continue; }
      if (file.size > MAX_IMAGE_MB * 1024 * 1024) { toast.error(`${file.name}: Too large (max ${MAX_IMAGE_MB}MB)`); continue; }
      validFiles.push(file);
    }
    if (validFiles.length === 0) return;
    const queue = validFiles.map(f => ({ file: f, status: 'pending' as const }));
    setUploadQueue(queue);
    setUploading(true);
    let successCount = 0;
    for (let i = 0; i < queue.length; i++) {
      setUploadQueue(prev => prev.map((q, idx) => idx === i ? { ...q, status: 'uploading' } : q));
      try {
        const res = await photoLibrariesApi.uploadPhoto(libraryId, queue[i].file);
        if (res.success) {
          successCount++;
          setUploadQueue(prev => prev.map((q, idx) => idx === i ? { ...q, status: 'done' } : q));
        } else {
          setUploadQueue(prev => prev.map((q, idx) => idx === i ? { ...q, status: 'error' } : q));
          toast.error(res.message || `Failed to upload ${queue[i].file.name}`);
        }
      } catch {
        setUploadQueue(prev => prev.map((q, idx) => idx === i ? { ...q, status: 'error' } : q));
      }
    }
    setUploading(false);
    if (successCount > 0) {
      toast.success(`${successCount} photo${successCount > 1 ? 's' : ''} uploaded!`);
      await fetchLibrary();
    }
    setTimeout(() => setUploadQueue([]), 2000);
  };

  const handleDeletePhoto = async (photoId: string) => {
    if (!libraryId) return;
    try {
      const res = await photoLibrariesApi.deletePhoto(libraryId, photoId);
      if (!showApiErrors(res)) {
        toast.success('Photo deleted');
        setLibrary(prev => prev ? {
          ...prev,
          photos: prev.photos.filter(p => p.id !== photoId),
          photo_count: prev.photo_count - 1,
        } : prev);
      }
    } catch (err) { showCaughtError(err); }
    setDeletePhotoId(null);
  };

  const handleSaveSettings = async () => {
    if (!libraryId) return;
    setSavingSettings(true);
    try {
      const res = await photoLibrariesApi.updateLibrary(libraryId, { privacy, description });
      if (!showApiErrors(res)) {
        toast.success('Library settings saved');
        setLibrary(prev => prev ? { ...prev, privacy, description } : prev);
        setSettingsOpen(false);
      }
    } catch (err) { showCaughtError(err); }
    finally { setSavingSettings(false); }
  };

  const copyShareLink = () => {
    if (!library) return;
    const url = `${window.location.origin}/shared/photo-library/${library.share_token}`;
    navigator.clipboard.writeText(url).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
      toast.success('Share link copied!');
    });
  };

  /* ─── SKELETON LOADING STATE ─── */
  if (loading) {
    return (
      <div className="pb-16">
        <div className="flex items-center gap-3 py-4 px-1 mb-4">
          <Skeleton className="w-20 h-4" />
        </div>
        <Skeleton className="w-full h-44 rounded-2xl mb-6" />
        <Skeleton className="w-full h-20 rounded-2xl mb-6" />
        <Skeleton className="w-full h-12 rounded-xl mb-6" />
        <div className="columns-2 md:columns-3 gap-3 space-y-3">
          {[...Array(6)].map((_, i) => (
            <Skeleton key={i} className={`w-full rounded-xl break-inside-avoid ${i % 3 === 0 ? 'h-52' : i % 3 === 1 ? 'h-36' : 'h-44'}`} />
          ))}
        </div>
      </div>
    );
  }

  if (!library) {
    return (
      <div className="text-center py-20">
        <AlertCircle className="w-12 h-12 text-muted-foreground mx-auto mb-4" />
        <p className="text-muted-foreground">Library not found</p>
        <Button variant="outline" className="mt-4" onClick={() => navigate(-1)}>Go Back</Button>
      </div>
    );
  }

  const photos = library.photos || [];
  const isOwner = library.is_owner !== false; // false = viewer (event organizer), undefined/true = owner
  const storagePct = library.storage_used_percent;
  const storageColor = storagePct > 90 ? 'text-destructive' : storagePct > 70 ? 'text-amber-600' : 'text-emerald-600';

  return (
    <div className="pb-16">

      {/* ─── TOP BAR ─── */}
      <div className="flex items-center justify-between gap-2 py-4 px-1 mb-2">
        <div className="flex gap-2 flex-wrap min-w-0">
          <Button variant="outline" size="sm" onClick={copyShareLink}>
            {copied ? <Check className="w-4 h-4 mr-1.5 text-emerald-500" /> : <img src={ShareIcon} alt="" className="w-4 h-4 mr-1.5 dark:invert opacity-70" />}
            {copied ? 'Copied!' : 'Share'}
          </Button>
          {isOwner && (
            <Button variant="outline" size="sm" onClick={() => setSettingsOpen(true)}>
              {library.privacy === 'public' ? <Globe className="w-4 h-4 mr-1.5" /> : <Lock className="w-4 h-4 mr-1.5" />}
              {library.privacy === 'public' ? 'Public' : 'Private'}
            </Button>
          )}
          {!isOwner && (
            <span className="inline-flex items-center gap-1.5 text-sm text-muted-foreground px-3 py-1.5 bg-muted rounded-md">
              {library.privacy === 'public' ? <Globe className="w-4 h-4" /> : <Lock className="w-4 h-4" />}
              {library.privacy === 'public' ? 'Public' : 'Private'}
            </span>
          )}
        </div>
        <Button variant="ghost" size="icon" className="flex-shrink-0" onClick={() => navigate(-1)} aria-label="Go back">
          <ChevronLeft className="w-5 h-5" />
        </Button>
      </div>

      {/* ─── HERO HEADER ─── */}
      <div className="relative rounded-2xl overflow-hidden mb-6 bg-gradient-to-br from-primary/20 via-primary/10 to-background border border-border h-44">
        <div className="absolute inset-0 opacity-5" style={{ backgroundImage: 'radial-gradient(circle at 2px 2px, hsl(var(--primary)) 1px, transparent 0)', backgroundSize: '28px 28px' }} />
        {photos.length > 0 && (
          <div className="absolute inset-0">
            {photos.length >= 3 ? (
              <div className="grid grid-cols-3 h-full gap-0.5 opacity-30">
                {photos.slice(0, 3).map((p, i) => (
                  <MediaThumb key={i} url={p.url} mediaType={p.media_type} className="w-full h-full object-cover" showPlayBadge={false} />
                ))}
              </div>
            ) : (
              <MediaThumb url={photos[0].url} mediaType={photos[0].media_type} className="w-full h-full object-cover opacity-20" showPlayBadge={false} />
            )}
          </div>
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-background/80 via-background/40 to-transparent" />
        <div className="absolute inset-0 flex flex-col justify-end p-6">
          <div className="flex items-end gap-4">
            <div className="w-12 h-12 rounded-xl bg-primary/20 backdrop-blur-sm flex items-center justify-center shrink-0">
              <img src={PhotosIcon} alt="Photos" className="w-6 h-6 dark:invert" />
            </div>
            <div className="flex-1 min-w-0">
              <h1 className="text-2xl font-bold text-foreground truncate">{library.name}</h1>
              {library.event && (
                <div className="flex items-center gap-3 mt-0.5 text-sm text-muted-foreground flex-wrap">
                  {library.event.start_date && (
                    <span className="flex items-center gap-1">
                      <Calendar className="w-3.5 h-3.5" />
                      {new Date(library.event.start_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}
                    </span>
                  )}
                  {library.event.location && (
                    <span className="flex items-center gap-1">
                      <MapPin className="w-3.5 h-3.5" />
                      {library.event.location}
                    </span>
                  )}
                </div>
              )}
            </div>
            <Badge className={`shrink-0 gap-1 ${library.privacy === 'public' ? 'bg-emerald-500 text-white' : 'bg-muted text-muted-foreground'}`}>
              {library.privacy === 'public' ? <Globe className="w-3 h-3" /> : <Lock className="w-3 h-3" />}
              {library.privacy === 'public' ? 'Public' : 'Private'}
            </Badge>
          </div>
        </div>
      </div>

      {/* ─── STORAGE METER (owner only) ─── */}
      {isOwner && (
        <div className="bg-card border border-border rounded-2xl p-5 mb-5">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <HardDrive className="w-4 h-4 text-primary" />
              <span className="text-sm font-semibold text-foreground">Storage</span>
            </div>
            <span className={`text-sm font-bold ${storageColor}`}>
              {library.total_size_mb.toFixed(1)}MB / {STORAGE_LIMIT_MB}MB
            </span>
          </div>
          <Progress value={storagePct} className="h-2" />
          <div className="flex justify-between text-xs text-muted-foreground mt-2">
            <span>{photos.length} photo{photos.length !== 1 ? 's' : ''}</span>
            <span>{(STORAGE_LIMIT_MB - library.total_size_mb).toFixed(1)}MB remaining</span>
          </div>
        </div>
      )}

      {/* ─── UPLOAD QUEUE (owner only) ─── */}
      {isOwner && uploadQueue.length > 0 && (
        <div className="bg-primary/5 border border-primary/20 rounded-2xl p-4 mb-5 space-y-2">
          <p className="text-sm font-semibold text-foreground mb-2">Uploading {uploadQueue.length} photos…</p>
          {uploadQueue.map((item, idx) => (
            <div key={idx} className="flex items-center gap-3">
              <div className="w-5 h-5 flex-shrink-0">
                {item.status === 'uploading' && <div className="w-4 h-4 border-2 border-primary border-t-transparent rounded-full animate-spin" />}
                {item.status === 'done' && <CheckCircle2 className="w-4 h-4 text-emerald-500" />}
                {item.status === 'error' && <X className="w-4 h-4 text-destructive" />}
                {item.status === 'pending' && <Clock className="w-4 h-4 text-muted-foreground" />}
              </div>
              <p className="text-sm truncate flex-1 text-foreground">{item.file.name}</p>
              <span className="text-xs text-muted-foreground">{(item.file.size / (1024 * 1024)).toFixed(1)}MB</span>
            </div>
          ))}
        </div>
      )}

      {/* ─── UPLOAD BUTTON (owner only) ─── */}
      {isOwner && (
        <div className="mb-6">
          <Button
            className="w-full"
            onClick={() => fileInputRef.current?.click()}
            disabled={uploading}
            size="lg"
          >
            {uploading
              ? <><div className="w-4 h-4 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin mr-2" />Uploading…</>
              : <><Upload className="w-5 h-5 mr-2" />Upload Photos</>
            }
          </Button>
          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept="image/*"
            className="hidden"
            onChange={(e) => handleFilesSelected(e.target.files)}
          />
        </div>
      )}

      {/* ─── PHOTO COUNT (viewer only) ─── */}
      {!isOwner && (
        <div className="flex items-center gap-2 text-sm text-muted-foreground mb-5">
          <img src={PhotosIcon} alt="" className="w-4 h-4 dark:invert opacity-60" />
          <span>{photos.length} photo{photos.length !== 1 ? 's' : ''}</span>
        </div>
      )}

      {/* ─── PHOTO GRID ─── */}
      {photos.length === 0 ? (
        isOwner ? (
          <div
            className="border-2 border-dashed border-border rounded-2xl p-16 text-center cursor-pointer hover:border-primary/40 hover:bg-primary/5 transition-all"
            onClick={() => fileInputRef.current?.click()}
          >
            <div className="w-16 h-16 bg-primary/10 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <img src={PhotosIcon} alt="Photos" className="w-8 h-8 opacity-60 dark:invert" />
            </div>
            <p className="text-lg font-semibold text-foreground mb-1">No photos yet</p>
            <p className="text-sm text-muted-foreground">Click to upload your event photos</p>
            <p className="text-xs text-muted-foreground mt-2">Max {MAX_IMAGE_MB}MB per image - Up to {STORAGE_LIMIT_MB}MB total storage</p>
          </div>
        ) : (
          <div className="border-2 border-dashed border-border rounded-2xl p-16 text-center">
            <div className="w-16 h-16 bg-muted rounded-2xl flex items-center justify-center mx-auto mb-4">
              <img src={PhotosIcon} alt="Photos" className="w-8 h-8 opacity-40 dark:invert" />
            </div>
            <p className="text-lg font-semibold text-foreground mb-1">No photos yet</p>
            <p className="text-sm text-muted-foreground">The photographer hasn't uploaded any photos yet</p>
          </div>
        )
      ) : (
        <div className="columns-2 md:columns-3 lg:columns-4 gap-3 space-y-3">
          {photos.map((photo, idx) => (
            <div
              key={photo.id}
              className="relative group break-inside-avoid rounded-xl overflow-hidden bg-muted border border-border/50 shadow-sm hover:shadow-md transition-all"
            >
              <MediaThumb
                url={photo.url}
                mediaType={photo.media_type}
                durationSeconds={photo.duration_seconds}
                alt={photo.original_name || `Photo ${idx + 1}`}
                className="w-full object-cover cursor-zoom-in block"
                onClick={() => setLightboxIdx(idx)}
                loading="lazy"
              />
              <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-all flex items-center justify-center opacity-0 group-hover:opacity-100">
                <div className="flex gap-2">
                  <button
                    onClick={() => setLightboxIdx(idx)}
                    className="p-2 bg-white/90 rounded-full hover:bg-white transition-colors shadow"
                  >
                    <ZoomIn className="w-4 h-4 text-foreground" />
                  </button>
                  <button
                    onClick={(e) => { e.stopPropagation(); downloadFile(photo.url, photo.original_name || `photo-${idx + 1}.jpg`); }}
                    className="p-2 bg-white/90 rounded-full hover:bg-white transition-colors shadow inline-flex"
                    title={t("download")}
                  >
                    <Download className="w-4 h-4 text-foreground" />
                  </button>
                  {isOwner && (
                    <button
                      onClick={() => setDeletePhotoId(photo.id)}
                      className="p-2 bg-destructive/90 rounded-full hover:bg-destructive transition-colors shadow"
                    >
                      <Trash2 className="w-4 h-4 text-white" />
                    </button>
                  )}
                </div>
              </div>
              {photo.caption && (
                <div className="absolute bottom-0 inset-x-0 bg-gradient-to-t from-black/70 to-transparent p-2">
                  <p className="text-white text-xs truncate">{photo.caption}</p>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
      {/* ─── LIGHTBOX ─── */}
      {lightboxIdx !== null && photos.length > 0 && (
        <div
          className="fixed inset-0 z-50 bg-black/97 flex items-center justify-center p-4"
          onClick={() => setLightboxIdx(null)}
        >
          {/* Top controls */}
          <div className="absolute top-4 right-4 flex items-center gap-2 z-10">
            <button
              className="p-2 rounded-full bg-white/10 hover:bg-white/20 text-white transition-colors inline-flex"
              onClick={(e) => { e.stopPropagation(); downloadFile(photos[lightboxIdx]?.url, photos[lightboxIdx]?.original_name || `photo-${lightboxIdx + 1}.jpg`); }}
              title="Download photo"
            >
              <Download className="w-5 h-5" />
            </button>
            <button
              onClick={() => setLightboxIdx(null)}
              className="p-2 bg-white/10 hover:bg-white/20 text-white rounded-full transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
          <div className="relative max-w-[95vw] max-h-[95vh]" onClick={e => e.stopPropagation()}>
            {photos[lightboxIdx]?.media_type === 'video' ? (
              <video
                src={photos[lightboxIdx]?.url}
                controls
                autoPlay
                playsInline
                className="max-w-full max-h-[90vh] rounded-xl bg-black"
              />
            ) : (
              <img
                src={photos[lightboxIdx]?.url}
                alt={photos[lightboxIdx]?.original_name || 'Photo'}
                className="max-w-full max-h-[90vh] object-contain rounded-xl"
              />
            )}
            {photos.length > 1 && (
              <>
                <button
                  onClick={() => setLightboxIdx(i => (i! - 1 + photos.length) % photos.length)}
                  className="absolute left-3 top-1/2 -translate-y-1/2 bg-white/10 hover:bg-white/20 text-white p-3 rounded-full transition-colors"
                >
                  <ChevronLeft className="w-5 h-5" />
                </button>
                <button
                  onClick={() => setLightboxIdx(i => (i! + 1) % photos.length)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 bg-white/10 hover:bg-white/20 text-white p-3 rounded-full transition-colors"
                >
                  <ChevronRight className="w-5 h-5" />
                </button>
              </>
            )}
            <div className="absolute bottom-3 left-1/2 -translate-x-1/2 bg-black/60 text-white text-sm px-3 py-1 rounded-full">
              {lightboxIdx + 1} / {photos.length}
            </div>
          </div>
        </div>
      )}

      {/* ─── DELETE CONFIRMATION ─── */}
      <Dialog open={!!deletePhotoId} onOpenChange={() => setDeletePhotoId(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete Photo?</DialogTitle>
          </DialogHeader>
          <p className="text-muted-foreground">This action cannot be undone.</p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeletePhotoId(null)}>Cancel</Button>
            <Button variant="destructive" onClick={() => deletePhotoId && handleDeletePhoto(deletePhotoId)}>Delete</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ─── SETTINGS DIALOG ─── */}
      <Dialog open={settingsOpen} onOpenChange={setSettingsOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Library Settings</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Privacy</Label>
              <Select value={privacy} onValueChange={(v) => setPrivacy(v as any)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="event_creator_only">
                    <div className="flex items-center gap-2">
                      <Lock className="w-4 h-4" />
                      Private – Event creator only
                    </div>
                  </SelectItem>
                  <SelectItem value="public">
                    <div className="flex items-center gap-2">
                      <Globe className="w-4 h-4" />
                      Public – Anyone with the link
                    </div>
                  </SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                {privacy === 'public'
                  ? 'Anyone who is a Nuru user and has the link can view this library.'
                  : 'Only the event creator and you can view this library.'}
              </p>
            </div>
            <div className="space-y-2">
              <Label>Description (optional)</Label>
              <Textarea
                value={description}
                onChange={e => setDescription(e.target.value)}
                placeholder="Add a description for this photo collection…"
                rows={3}
              />
            </div>
            <div className="space-y-2">
              <Label>Share Link</Label>
              <div className="flex gap-2">
                <input
                  readOnly
                  value={`${window.location.origin}/shared/photo-library/${library.share_token}`}
                  className="flex-1 text-xs bg-muted rounded-md px-3 py-2 text-muted-foreground font-mono border border-border"
                />
                <Button size="sm" variant="outline" onClick={copyShareLink}>
                  {copied ? <Check className="w-4 h-4 text-emerald-500" /> : <img src={ShareIcon} alt="" className="w-4 h-4 dark:invert opacity-70" />}
                </Button>
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSettingsOpen(false)}>Cancel</Button>
            <Button onClick={handleSaveSettings} disabled={savingSettings}>
              {savingSettings && <div className="w-4 h-4 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin mr-2" />}
              Save Settings
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default PhotoLibraryDetail;
