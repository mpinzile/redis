import { useState, useEffect, useRef, useCallback } from 'react';
import { encodeId } from '@/utils/shortId';
import VideoPlayer from '@/components/VideoPlayer';
import SmartMedia from '@/components/SmartMedia';
import ImageLightbox, { useLightbox } from '@/components/ui/image-lightbox';
import { getTimeAgo } from '@/utils/getTimeAgo';
import { useParams, useNavigate } from 'react-router-dom';
import { ChevronLeft, Heart, Send, X, Loader2, CornerDownRight, ChevronDown, AlertTriangle } from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import ShareIcon from '@/assets/icons/share-icon.svg';
import ShareMenu from '@/components/ShareMenu';
import TicketIcon from '@/assets/icons/ticket-icon.svg';
import CustomCalendarIcon from '@/assets/icons/calendar-icon.svg';
import CustomLocationIcon from '@/assets/icons/location-icon.svg';
import CustomClockIcon from '@/assets/icons/clock-icon.svg';
import CustomImageIcon from '@/assets/icons/image-icon.svg';
import { Button } from '@/components/ui/button';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import { socialApi } from '@/lib/api/social';
import { EmojiPickerPopover } from '@/components/emoji/EmojiPickerPopover';
import { useCurrentUser } from '@/hooks/useCurrentUser';
import { Skeleton } from '@/components/ui/skeleton';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import { NURU_EVENT_DEFAULT_IMAGE } from '@/lib/eventImage';

const getInitials = (name: string) => {
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
  return name.charAt(0).toUpperCase();
};

// ──────────────────────────────────────────────
// Avatar component
// ──────────────────────────────────────────────
const UserAvatar = ({ src, name, size = 'md' }: { src?: string; name: string; size?: 'sm' | 'md' }) => {
  const sizeClasses = size === 'sm' ? 'w-7 h-7 text-[10px]' : 'w-8 h-8 md:w-10 md:h-10 text-xs md:text-sm';
  if (src) {
    return <img src={src} alt={name} className={`${sizeClasses} rounded-full object-cover flex-shrink-0`} />;
  }
  return (
    <div className={`${sizeClasses} rounded-full bg-primary/10 flex items-center justify-center text-primary font-semibold flex-shrink-0`}>
      {getInitials(name)}
    </div>
  );
};

// ──────────────────────────────────────────────
// Inline Reply Input
// ──────────────────────────────────────────────
const InlineReplyInput = ({
  currentUser,
  onSubmit,
  placeholder = 'Write a reply...',
  autoFocus = true,
}: {
  currentUser: any;
  onSubmit: (content: string) => Promise<void>;
  placeholder?: string;
  autoFocus?: boolean;
}) => {
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);

  const handleSubmit = async () => {
    if (!text.trim() || sending) return;
    setSending(true);
    try {
      await onSubmit(text.trim());
      setText('');
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="flex gap-2 items-start mt-2">
      <UserAvatar src={currentUser?.avatar} name={currentUser?.first_name || '?'} size="sm" />
      <div className="flex-1 flex items-start gap-1.5">
        <div className="flex-1 flex items-center gap-1.5 border border-border rounded-full px-3 py-1.5 bg-muted/30">
          <input
            type="text"
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); handleSubmit(); } }}
            placeholder={placeholder}
            autoFocus={autoFocus}
            className="flex-1 bg-transparent text-xs md:text-sm outline-none placeholder:text-muted-foreground"
          />
          <EmojiPickerPopover
            onSelect={(e) => setText((t) => t + e)}
            side="top"
            align="end"
          >
            <button
              type="button"
              className="text-base leading-none px-1 text-muted-foreground hover:text-foreground"
              aria-label="Insert emoji"
            >
              😊
            </button>
          </EmojiPickerPopover>
        </div>
        <button
          onClick={handleSubmit}
          disabled={!text.trim() || sending}
          className="p-1.5 text-primary hover:text-primary/80 disabled:opacity-40 transition-colors"
        >
          {sending ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Send className="w-3.5 h-3.5" />}
        </button>
      </div>
    </div>
  );
};

// ──────────────────────────────────────────────
// Single Echo (Comment) Component — Threaded
// ──────────────────────────────────────────────
const EchoItem = ({
  comment,
  postId,
  currentUser,
  depth = 0,
  onDelete,
  onReplyAdded,
}: {
  comment: any;
  postId: string;
  currentUser: any;
  depth?: number;
  onDelete: (commentId: string) => void;
  onReplyAdded: () => void;
}) => {
  const [glowed, setGlowed] = useState(comment.has_glowed || false);
  const [glowCount, setGlowCount] = useState(comment.glow_count || 0);
  const [showReplyInput, setShowReplyInput] = useState(false);
  const [showReplies, setShowReplies] = useState(false);
  const [replies, setReplies] = useState<any[]>(comment.replies_preview || []);
  const [repliesLoaded, setRepliesLoaded] = useState(false);
  const [loadingReplies, setLoadingReplies] = useState(false);
  const replyCount = comment.reply_count || 0;

  const cUser = comment.user || comment.author || {};
  const cName = cUser.first_name
    ? `${cUser.first_name} ${cUser.last_name || ''}`.trim()
    : cUser.name || cUser.username || 'User';
  const cAvatar = cUser.avatar || '';
  const cVerified = cUser.is_identity_verified || cUser.is_verified || false;
  const isOwn = currentUser?.id === cUser.id;

  const maxDepth = 5;

  const handleGlow = async () => {
    const wasGlowed = glowed;
    setGlowed(!wasGlowed);
    setGlowCount(prev => wasGlowed ? prev - 1 : prev + 1);
    try {
      if (wasGlowed) await socialApi.unglowComment(postId, comment.id);
      else await socialApi.glowComment(postId, comment.id);
    } catch {
      setGlowed(wasGlowed);
      setGlowCount(prev => wasGlowed ? prev + 1 : prev - 1);
      toast.error('Failed to glow echo');
    }
  };

  const handleLoadReplies = async () => {
    if (repliesLoaded) {
      setShowReplies(true);
      return;
    }
    setLoadingReplies(true);
    try {
      const res = await socialApi.getCommentReplies(postId, comment.id);
      if (res.success) {
        const data = res.data as any;
        setReplies(data?.comments || []);
        setRepliesLoaded(true);
        setShowReplies(true);
      }
    } catch {
      toast.error('Failed to load replies');
    } finally {
      setLoadingReplies(false);
    }
  };

  const handleReplySubmit = async (content: string) => {
    try {
      const res = await socialApi.addComment(postId, { content, parent_id: comment.id });
      if (res.success) {
        const newReply = res.data;
        setReplies(prev => [...prev, newReply]);
        setShowReplies(true);
        setRepliesLoaded(true);
        setShowReplyInput(false);
        onReplyAdded();
        toast.success('Reply posted');
      } else {
        toast.error(res.message || 'Failed to post reply');
      }
    } catch {
      toast.error('Failed to post reply');
      throw new Error('failed');
    }
  };

  const handleDeleteReply = async (replyId: string) => {
    try {
      const res = await socialApi.deleteComment(postId, replyId);
      if (res.success) {
        setReplies(prev => prev.filter(r => r.id !== replyId));
        onReplyAdded();
        toast.success('Reply deleted');
      }
    } catch {
      toast.error('Failed to delete reply');
    }
  };

  return (
    <div className={`${depth > 0 ? 'ml-8 md:ml-10' : ''}`}>
      <div className="flex gap-2 md:gap-2.5">
        <UserAvatar src={cAvatar} name={cName} size={depth > 0 ? 'sm' : 'md'} />
        <div className="flex-1 min-w-0">
          {/* Comment bubble */}
           <div className="bg-muted/50 rounded-2xl px-3 py-2 inline-block max-w-full">
            <div className="flex items-center gap-2">
              <span className="font-semibold text-xs md:text-sm">{cName}</span>

            </div>
            {comment.content && (
              <p className="text-xs md:text-sm break-words whitespace-pre-wrap mt-0.5">{comment.content}</p>
            )}
          </div>

          {/* Action row */}
          <div className="flex items-center gap-3 mt-0.5 ml-2 text-xs">
            <span className="text-muted-foreground">
              {comment.created_at ? getTimeAgo(comment.created_at) : ''}
            </span>
            <button
              onClick={handleGlow}
              className={`font-semibold transition-colors ${
                glowed ? 'text-red-500' : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {glowed ? 'Glowed' : 'Glow'}
            </button>
            {depth < maxDepth && (
              <button
                onClick={() => setShowReplyInput(!showReplyInput)}
                className="font-semibold text-muted-foreground hover:text-foreground transition-colors"
              >
                Reply
              </button>
            )}
            {isOwn && (
              <button
                onClick={() => onDelete(comment.id)}
                className="font-semibold text-destructive hover:text-destructive/80 transition-colors"
              >
                Delete
              </button>
            )}
            {glowCount > 0 && (
              <span className="flex items-center gap-0.5 text-muted-foreground">
                <span className="text-xs">❤️</span>
                {glowCount}
              </span>
            )}
          </div>

          {/* View / collapse replies */}
          {replyCount > 0 && (
            <button
              onClick={() => {
                if (showReplies) setShowReplies(false);
                else handleLoadReplies();
              }}
              disabled={loadingReplies}
              className="flex items-center gap-1 mt-1.5 ml-2 text-xs font-semibold text-primary hover:text-primary/80 transition-colors"
            >
              {loadingReplies ? (
                <Loader2 className="w-3 h-3 animate-spin" />
              ) : showReplies ? (
                <ChevronDown className="w-3 h-3 rotate-180 transition-transform" />
              ) : (
                <CornerDownRight className="w-3 h-3" />
              )}
              {showReplies
                ? 'Hide replies'
                : `View ${replyCount} ${replyCount === 1 ? 'reply' : 'replies'}`
              }
            </button>
          )}

          {/* Render replies */}
          {showReplies && replies.length > 0 && (
            <div className="mt-2 space-y-2">
              {replies.map((reply) => (
                <EchoItem
                  key={reply.id}
                  comment={reply}
                  postId={postId}
                  currentUser={currentUser}
                  depth={depth + 1}
                  onDelete={handleDeleteReply}
                  onReplyAdded={onReplyAdded}
                />
              ))}
            </div>
          )}

          {/* Inline reply input */}
          {showReplyInput && depth < maxDepth && (
            <InlineReplyInput
              currentUser={currentUser}
              onSubmit={handleReplySubmit}
              placeholder={`Reply to ${cName}...`}
            />
          )}
        </div>
      </div>
    </div>
  );
};


const MomentDetail = () => {
  const { id } = useParams();
  const navigate = useNavigate();
  const { t } = useLanguage();
  const currentUserQuery = useCurrentUser();
  const currentUser = currentUserQuery.data as any;

  const [post, setPost] = useState<any>(null);
  const [comments, setComments] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [commentsLoading, setCommentsLoading] = useState(true);
  const [input, setInput] = useState('');
  const [sending, setSending] = useState(false);
  const [glowed, setGlowed] = useState(false);
  const [glowCount, setGlowCount] = useState(0);
  const [commentCount, setCommentCount] = useState(0);
  const [shareOpen, setShareOpen] = useState(false);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const inputFileRef = useRef<HTMLInputElement | null>(null);
  const [appealOpen, setAppealOpen] = useState(false);
  const [appealReason, setAppealReason] = useState("");
  const [submittingAppeal, setSubmittingAppeal] = useState(false);
  const [appealSubmitted, setAppealSubmitted] = useState(false);
  const lightbox = useLightbox();

  const shareUrl = `${window.location.origin}/s/${id ? encodeId(id) : ''}`;
  const shareTitle = post?.title || post?.content?.slice(0, 50) || 'Check out this moment on Nuru';

  // Share logic moved to ShareMenu component

  const handleBack = () => {
    if (window.history.length > 1) navigate(-1);
    else navigate('/');
  };

  // Fetch post from API
  useEffect(() => {
    if (!id) return;
    setLoading(true);
    socialApi.getPost(id)
      .then((res) => {
        if (res.success && res.data) {
          const d = res.data as any;
          setPost(d);
          setGlowed(d.has_glowed || false);
          setGlowCount(d.glow_count || d.likes || 0);
          setCommentCount(d.comment_count || d.comments || 0);
        }
      })
      .catch(() => toast.error('Failed to load post'))
      .finally(() => setLoading(false));
  }, [id]);

  // Fetch comments from API
  const fetchComments = useCallback(() => {
    if (!id) return;
    setCommentsLoading(true);
    socialApi.getComments(id, { sort: 'newest' })
      .then((res) => {
        if (res.success) {
          const data = res.data as any;
          setComments(data?.comments || data?.items || (Array.isArray(data) ? data : []));
        }
      })
      .catch(() => {})
      .finally(() => setCommentsLoading(false));
  }, [id]);

  useEffect(() => { fetchComments(); }, [fetchComments]);

  const handleGlow = async () => {
    if (!id) return;
    const wasGlowed = glowed;
    setGlowed(!wasGlowed);
    setGlowCount(prev => wasGlowed ? prev - 1 : prev + 1);
    try {
      if (wasGlowed) await socialApi.unglowPost(id);
      else await socialApi.glowPost(id);
    } catch {
      setGlowed(wasGlowed);
      setGlowCount(prev => wasGlowed ? prev + 1 : prev - 1);
      toast.error('Failed to update glow');
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      const file = e.target.files[0];
      setImageFile(file);
      setImagePreview(URL.createObjectURL(file));
    }
  };

  const removeImage = () => {
    setImageFile(null);
    setImagePreview(null);
    if (inputFileRef.current) inputFileRef.current.value = '';
  };

  const sendEcho = async () => {
    if (!input.trim() || !id || sending) return;
    setSending(true);
    try {
      const res = await socialApi.addComment(id, { content: input.trim() });
      if (res.success) {
        const newComment = res.data;
        if (newComment) {
          setComments(prev => [newComment, ...prev]);
        } else {
          fetchComments();
        }
        setCommentCount(prev => prev + 1);
        setInput('');
        removeImage();
      } else {
        toast.error(res.message || 'Failed to add echo');
      }
    } catch {
      toast.error('Failed to add echo');
    } finally {
      setSending(false);
    }
  };

  const handleDeleteComment = async (commentId: string) => {
    if (!id) return;
    try {
      const res = await socialApi.deleteComment(id, commentId);
      if (res.success) {
        setComments(prev => prev.filter(c => c.id !== commentId));
        setCommentCount(prev => prev - 1);
        toast.success('Echo deleted');
      }
    } catch {
      toast.error('Failed to delete echo');
    }
  };

  const handleSubmitAppeal = async () => {
    if (!id || !appealReason.trim()) return;
    setSubmittingAppeal(true);
    try {
      const res = await socialApi.submitMomentAppeal(id, appealReason.trim());
      if (res.success) { setAppealSubmitted(true); toast.success("Appeal submitted"); setAppealOpen(false); }
      else toast.error(res.message || "Failed to submit appeal");
    } catch { toast.error("Failed to submit appeal"); }
    setSubmittingAppeal(false);
  };

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendEcho();
    }
  };

  if (loading) {
    return (
      <>
        <div className="flex items-center gap-2 mb-3 md:mb-4">
          <h1 className="flex-1 min-w-0 text-xl sm:text-2xl md:text-3xl font-bold break-words leading-tight">Moment</h1>
          <Button variant="ghost" size="icon" className="flex-shrink-0" onClick={handleBack} aria-label="Back">
            <ChevronLeft className="w-5 h-5" />
          </Button>
        </div>
        <div className="bg-card rounded-lg shadow-sm border border-border overflow-hidden mb-4">
          <div className="p-4 flex items-center gap-3">
            <Skeleton className="w-10 h-10 rounded-full" />
            <div className="space-y-2">
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-3 w-24" />
            </div>
          </div>
          <Skeleton className="h-64 mx-4 rounded-lg mb-4" />
          <div className="px-4 py-3 space-y-2">
            <Skeleton className="h-6 w-3/4" />
            <Skeleton className="h-4 w-full" />
          </div>
        </div>
      </>
    );
  }

  if (!post) {
    return (
      <div className="text-center py-12">
        <p className="text-muted-foreground">Post not found</p>
        <Button variant="outline" onClick={handleBack} className="mt-4">Go Back</Button>
      </div>
    );
  }

  // Extract post fields from API response
  const authorName = post.author?.name
    || (post.user?.first_name ? `${post.user.first_name} ${post.user.last_name || ''}`.trim() : null)
    || 'Anonymous';
  const authorAvatar = post.author?.avatar || post.user?.avatar || '';
  const authorVerified = post.user?.is_identity_verified || post.author?.is_verified || false;
  const postTitle = post.title || post.content?.title || '';
  const postContent = post.content?.text || post.content || (typeof post.content === 'string' ? post.content : '');
  const rawMedia = post.images || post.media || [];
  const postImages = rawMedia.map((m: any) => typeof m === 'string' ? m : (m?.image_url || m?.url)).filter(Boolean);
  const mediaTypes = rawMedia.map((m: any) => typeof m === 'string' ? undefined : (m?.media_type || m?.type));
  const isVideoUrl = (url: string, idx: number) => {
    const mt = mediaTypes[idx];
    if (mt && mt !== 'image' && (mt === 'video' || mt.startsWith('video'))) return true;
    // Check extension anywhere in the URL (before query params)
    const urlPath = url.split('?')[0];
    return /\.(mp4|webm|mov|avi|mkv|m4v|3gp)$/i.test(urlPath) || /video/i.test(url);
  };
  const postImage = post.event?.image || post.content?.image || postImages[0] || '';
  const postTimeAgo = post.created_at ? getTimeAgo(post.created_at) : 'Recently';
  const postLocation = post.location || '';
  const isOwner = currentUser && (post.user?.id === currentUser.id || post.author?.id === currentUser.id);
  const isRemoved = post.is_active === false;

  // Shared event detection
  const isEventShare = post.post_type === 'event_share' && !!post.shared_event;
  const sharedEvent = post.shared_event;
  const eventImages = sharedEvent?.images?.length ? sharedEvent.images : (sharedEvent?.cover_image ? [sharedEvent.cover_image] : [NURU_EVENT_DEFAULT_IMAGE]);

  return (
    <>
      {/* Appeal Dialog */}
      <Dialog open={appealOpen} onOpenChange={open => { if (!open) { setAppealOpen(false); setAppealReason(""); } }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('appeal_removal')}</DialogTitle>
            <DialogDescription>{t('appeal_desc')}</DialogDescription>
          </DialogHeader>
          <Textarea rows={4} placeholder={t('appeal_placeholder')} value={appealReason} onChange={e => setAppealReason(e.target.value)} />
          <DialogFooter>
            <Button variant="outline" onClick={() => setAppealOpen(false)}>{t("cancel")}</Button>
            <Button onClick={handleSubmitAppeal} disabled={submittingAppeal || !appealReason.trim()}>
              {submittingAppeal ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null} {t("submit_appeal")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <div className="flex items-center gap-2 mb-3 md:mb-4">
        <h1 className="flex-1 min-w-0 text-xl sm:text-2xl md:text-3xl font-bold break-words leading-tight">Moment</h1>
        <Button variant="ghost" size="icon" className="flex-shrink-0" onClick={handleBack} aria-label="Back">
          <ChevronLeft className="w-5 h-5" />
        </Button>
      </div>

      {/* Removed content banner */}
      {isRemoved && (
        <div className="bg-destructive/10 border border-destructive/30 rounded-xl p-4 mb-4 flex items-start gap-3">
          <AlertTriangle className="w-5 h-5 text-destructive shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm font-medium text-destructive">This moment has been removed by Nuru.</p>
            {post.removal_reason && (
              <p className="text-xs text-muted-foreground mt-0.5">Reason: {post.removal_reason}</p>
            )}
            {isOwner && !appealSubmitted && (
              <Button size="sm" variant="outline" className="mt-2 h-7 text-xs" onClick={() => setAppealOpen(true)}>
                Appeal Removal
              </Button>
            )}
            {appealSubmitted && <p className="text-xs text-muted-foreground mt-1">✓ Appeal submitted — we'll review it shortly.</p>}
            <p className="text-xs text-muted-foreground mt-1 opacity-70">Note: Removed content is permanently deleted after 7 days if no appeal is submitted.</p>
          </div>
        </div>
      )}

      {/* Moment Content */}
      <div className="bg-card rounded-lg shadow-sm border border-border overflow-hidden mb-4 md:mb-6">
        <div className="p-3 md:p-4 flex items-center justify-between">
          <div className="flex items-center gap-2 md:gap-3 min-w-0">
            <UserAvatar src={authorAvatar} name={authorName} />
            <div className="min-w-0">
              <h3 className="font-semibold text-foreground text-sm md:text-base truncate flex items-center gap-1.5">
                {authorName}

              </h3>
              <p className="text-xs md:text-sm text-muted-foreground">
                {postTimeAgo}
                {postLocation && <span className="inline-flex items-center gap-0.5"> - <img src={CustomLocationIcon} alt="" className="w-3 h-3 inline dark:invert" /> {postLocation}</span>}
              </p>
            </div>
          </div>

          <Popover open={shareOpen} onOpenChange={setShareOpen}>
            <PopoverTrigger asChild>
              <Button variant="ghost" size="sm" className="text-muted-foreground flex-shrink-0">
                <img src={ShareIcon} alt="" className="w-4 h-4 dark:invert opacity-70" />
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-48 p-2" align="end">
              <ShareMenu shareUrl={shareUrl} shareTitle={shareTitle} onClose={() => setShareOpen(false)} />
            </PopoverContent>
          </Popover>
        </div>

        {/* ── EVENT SHARE CARD ── */}
        {isEventShare && sharedEvent ? (
          <div className="mx-3 md:mx-4 mb-3">
            {/* Caption above event card */}
            {typeof postContent === 'string' && postContent && (
              <p className="text-foreground text-sm md:text-base whitespace-pre-wrap break-words mb-3">{postContent}</p>
            )}

            <div
              className="rounded-xl border border-border overflow-hidden bg-muted/20 hover:bg-muted/40 transition-colors cursor-pointer"
              onClick={() => navigate(`/event/${sharedEvent.id}`)}
            >
              {/* Event Hero Image(s) */}
              {eventImages.length > 0 && (
                <div className="relative">
                  {eventImages.length === 1 ? (
                    <img src={eventImages[0]} alt={sharedEvent.title} className="w-full h-48 sm:h-56 object-cover" />
                  ) : (
                    <div className="grid grid-cols-2 gap-0.5 h-48 sm:h-56">
                      <img src={eventImages[0]} alt={sharedEvent.title} className={`w-full h-full object-cover ${eventImages.length === 2 ? '' : 'row-span-2'}`} />
                      {eventImages.length === 2 ? (
                        <img src={eventImages[1]} alt="" className="w-full h-full object-cover" />
                      ) : (
                        <div className="flex flex-col gap-0.5">
                          <img src={eventImages[1]} alt="" className="w-full flex-1 object-cover" />
                          {eventImages.length > 2 && (
                            <div className="relative flex-1">
                              <img src={eventImages[2]} alt="" className="w-full h-full object-cover" />
                              {eventImages.length > 3 && (
                                <div className="absolute inset-0 bg-black/50 flex items-center justify-center">
                                  <span className="text-white font-bold text-lg">+{eventImages.length - 3}</span>
                                </div>
                              )}
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  )}
                  {/* Overlay badges */}
                  <div className="absolute top-3 left-3 flex gap-2">
                    {sharedEvent.event_type && (
                      <span className="bg-primary/90 text-primary-foreground text-xs px-2 py-0.5 rounded-full backdrop-blur-sm">
                        {sharedEvent.event_type}
                      </span>
                    )}
                    {sharedEvent.sells_tickets && (
                      <span className="bg-accent text-accent-foreground text-xs px-2 py-0.5 rounded-full backdrop-blur-sm flex items-center gap-1">
                        <img src={TicketIcon} alt="Ticket" className="w-3 h-3 dark:invert" /> Tickets
                      </span>
                    )}
                  </div>
                </div>
              )}

              {/* Event Info */}
              <div className="p-4 space-y-3">
                <h3 className="text-lg font-bold text-foreground leading-tight">{sharedEvent.title}</h3>

                {sharedEvent.description && (
                  <p className="text-sm text-muted-foreground line-clamp-2">{sharedEvent.description}</p>
                )}

                <div className="flex flex-wrap gap-x-4 gap-y-2 text-sm">
                  {sharedEvent.start_date && (
                    <div className="flex items-center gap-1.5 text-muted-foreground">
                      <img src={CustomCalendarIcon} alt="" className="w-4 h-4 flex-shrink-0 dark:invert" />
                      <span>
                        {new Date(sharedEvent.start_date).toLocaleDateString('en-GB', {
                          weekday: 'short', day: 'numeric', month: 'short', year: 'numeric'
                        })}
                      </span>
                    </div>
                  )}
                  {sharedEvent.start_time && (
                    <div className="flex items-center gap-1.5 text-muted-foreground">
                      <img src={CustomClockIcon} alt="" className="w-4 h-4 flex-shrink-0 dark:invert" />
                      <span>{sharedEvent.start_time}</span>
                    </div>
                  )}
                  {sharedEvent.location && (
                    <div className="flex items-center gap-1.5 text-muted-foreground">
                      <img src={CustomLocationIcon} alt="" className="w-4 h-4 flex-shrink-0 dark:invert" />
                      <span className="truncate max-w-[200px]">{sharedEvent.location}</span>
                    </div>
                  )}
                </div>

                {sharedEvent.dress_code && (
                  <div className="text-xs text-muted-foreground">
                    <span className="font-medium text-foreground">Dress Code:</span> {sharedEvent.dress_code}
                  </div>
                )}

                <Button
                  variant="outline"
                  size="sm"
                  className="w-full gap-2 mt-1"
                  onClick={(e) => {
                    e.stopPropagation();
                    navigate(`/event/${sharedEvent.id}`);
                  }}
                >
                  View Event Details
                </Button>
              </div>
            </div>
          </div>
        ) : (
          <>
            {/* Media (Images + Videos) */}
            {postImages.length > 0 ? (
              <div className={`px-3 md:px-4 ${postImages.length > 1 ? 'flex gap-2 overflow-x-auto py-1' : ''}`}>
                {postImages.length === 1 ? (
                  isVideoUrl(postImages[0], 0) ? (
                    <SmartMedia src={postImages[0]} alt="Post" className="w-full max-h-[500px] object-contain rounded-xl md:rounded-2xl bg-muted/30" isVideo={true} />
                  ) : (
                    <img
                      src={postImages[0]}
                      alt="Post"
                      className="w-full max-h-[500px] object-contain rounded-xl md:rounded-2xl bg-muted/30 cursor-pointer hover:opacity-95 transition-opacity"
                      onClick={() => lightbox.openLightbox(postImages.filter((_: string, i: number) => !isVideoUrl(_, i)), 0)}
                    />
                  )
                ) : (
                  postImages.map((media: string, idx: number) => (
                    isVideoUrl(media, idx) ? (
                      <SmartMedia key={idx} src={media} alt={`Post ${idx + 1}`} className="w-40 h-32 md:w-48 md:h-40 flex-shrink-0 rounded-xl" isVideo={true} />
                    ) : (
                      <img
                        key={idx}
                        src={media}
                        alt={`Post ${idx + 1}`}
                        className="w-40 h-32 md:w-48 md:h-40 flex-shrink-0 object-cover rounded-xl cursor-pointer hover:opacity-90 transition-opacity"
                        onClick={() => {
                          const imageOnly = postImages.filter((_: string, i: number) => !isVideoUrl(_, i));
                          const imgIdx = imageOnly.indexOf(media);
                          lightbox.openLightbox(imageOnly, imgIdx >= 0 ? imgIdx : 0);
                        }}
                      />
                    )
                  ))
                )}
              </div>
            ) : postImage ? (
              <div className="px-3 md:px-4">
                {isVideoUrl(postImage, 0) ? (
                  <SmartMedia src={postImage} alt={postTitle || 'Moment image'} className="w-full max-h-[500px] object-contain rounded-lg bg-muted/30" isVideo={true} />
                ) : (
                  <img
                    src={postImage}
                    alt={postTitle || 'Moment image'}
                    className="w-full max-h-[500px] object-contain rounded-lg bg-muted/30 cursor-pointer hover:opacity-95 transition-opacity"
                    onClick={() => lightbox.openLightbox([postImage], 0)}
                  />
                )}
              </div>
            ) : null}

            {/* Content */}
            <div className="px-3 md:px-4 py-2 md:py-3">
              {postTitle && <h2 className="text-lg md:text-xl font-bold text-foreground mb-1">{postTitle}</h2>}
              {typeof postContent === 'string' && postContent && (
                <p className="text-sm md:text-base text-foreground whitespace-pre-wrap">{postContent}</p>
              )}
            </div>
          </>
        )}

        {/* Action Buttons */}
        <div className="px-3 md:px-4 py-2 md:py-3 border-t border-border flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 sm:gap-0">
          <div className="flex gap-2 w-full sm:w-auto justify-start">
            <button
              onClick={handleGlow}
              className={`flex items-center justify-center gap-1.5 px-3 py-1.5 md:px-4 md:py-2 rounded-lg transition-colors text-xs md:text-sm min-w-[60px] md:min-w-[80px] ${
                glowed ? 'bg-red-100 text-red-600' : 'bg-muted/50 text-muted-foreground hover:bg-muted hover:text-foreground'
              }`}
            >
              <span className="text-sm flex-shrink-0">❤️</span>
              <span className="hidden sm:inline whitespace-nowrap">{glowed ? 'Glowed' : 'Glow'}</span>
            </button>
          </div>

          <div className="flex items-center gap-3 md:gap-4 text-xs md:text-sm text-muted-foreground">
            <span>{glowCount} {glowCount === 1 ? 'Glow' : 'Glows'}</span>
            <span className="font-medium">{commentCount} {commentCount === 1 ? 'Echo' : 'Echoes'}</span>
          </div>
        </div>
      </div>

      {/* Echoes (Comments) — Threaded */}
      <div className="bg-card rounded-lg shadow-sm border border-border p-3 md:p-4">
        <h2 className="text-lg md:text-xl font-semibold mb-3 md:mb-4">{commentCount} {commentCount === 1 ? 'Echo' : 'Echoes'}</h2>

        {/* Comment Input */}
        <div className="flex gap-2 md:gap-3 mb-3 md:mb-4">
          <UserAvatar src={currentUser?.avatar} name={`${currentUser?.first_name || ''} ${currentUser?.last_name || ''}`.trim() || '?'} />
          <div className="flex-1 space-y-2">
            {imagePreview && (
              <div className="relative inline-block">
                <img src={imagePreview} alt="preview" className="w-20 h-20 object-cover rounded-lg" />
                <button onClick={removeImage} className="absolute -top-1 -right-1 bg-destructive text-destructive-foreground rounded-full p-0.5">
                  <X className="w-3 h-3" />
                </button>
              </div>
            )}
            <div className="flex items-end gap-2">
              <div className="flex items-end gap-1.5 flex-1 border border-border rounded-lg px-3 py-2 min-w-0">
                <textarea
                  placeholder="Add an echo..."
                  value={input}
                  onChange={(e) => setInput(e.target.value)}
                  onKeyDown={onKeyDown}
                  rows={1}
                  className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground min-w-0 resize-none overflow-hidden whitespace-pre-wrap break-words"
                  style={{ maxHeight: '120px' }}
                  onInput={(e) => { const t = e.target as HTMLTextAreaElement; t.style.height = 'auto'; t.style.height = Math.min(t.scrollHeight, 120) + 'px'; }}
                  autoComplete="off"
                />
                <input
                  ref={inputFileRef}
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={handleFileChange}
                />
                <button onClick={() => inputFileRef.current?.click()} className="text-muted-foreground hover:text-foreground" type="button">
                  <img src={CustomImageIcon} alt="Image" className="w-4 h-4" />
                </button>
              </div>
              <Button
                size="sm"
                onClick={sendEcho}
                disabled={!input.trim() || sending}
              >
                {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
              </Button>
            </div>
          </div>
        </div>

        {/* Comments List — Threaded */}
        {commentsLoading ? (
          <div className="space-y-3">
            {[1, 2].map(i => (
              <div key={i} className="flex gap-3">
                <Skeleton className="w-8 h-8 rounded-full" />
                <div className="flex-1 space-y-2">
                  <Skeleton className="h-4 w-32" />
                  <Skeleton className="h-12 w-full rounded-lg" />
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="space-y-3 md:space-y-4">
            {comments.map((comment) => (
              <EchoItem
                key={comment.id}
                comment={comment}
                postId={id!}
                currentUser={currentUser}
                depth={0}
                onDelete={handleDeleteComment}
                onReplyAdded={() => setCommentCount(prev => prev + 1)}
              />
            ))}

            {comments.length === 0 && !commentsLoading && (
              <p className="text-center text-muted-foreground py-3 md:py-4 text-sm">No echoes yet. Be the first!</p>
            )}
          </div>
        )}
      </div>
      <ImageLightbox
        images={lightbox.images}
        initialIndex={lightbox.index}
        open={lightbox.open}
        onClose={lightbox.closeLightbox}
      />
    </>
  );
};

export default MomentDetail;
