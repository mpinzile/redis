import { useState, useEffect } from 'react';
import ImageLightbox, { useLightbox } from '@/components/ui/image-lightbox';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { Heart, MessageCircle, MapPin } from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import ShareIcon from '@/assets/icons/share-icon.svg';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { getTimeAgo } from '@/utils/getTimeAgo';
import { useCurrentUser } from '@/hooks/useCurrentUser';
import { resolveApiBaseUrl } from '@/lib/api/helpers';
import nuruLogo from '@/assets/nuru-logo.png';
import { useLanguage } from '@/lib/i18n/LanguageContext';

const API_BASE = resolveApiBaseUrl();

const getInitials = (name: string) => {
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
  return name.charAt(0).toUpperCase();
};

const getImageUrl = (img: any): string | null => {
  if (typeof img === 'string') return img;
  if (img && typeof img === 'object' && img.url) return img.url;
  return null;
};

const isVideoMedia = (img: any): boolean => {
  if (typeof img === 'object' && img.media_type === 'video') return true;
  if (typeof img === 'string') return /\.(mp4|webm|mov|avi)(\?|$)/i.test(img);
  const url = typeof img === 'object' ? img.url : '';
  return /\.(mp4|webm|mov|avi)(\?|$)/i.test(url);
};

const GuestPost = () => {
  const { t } = useLanguage();
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { userIsLoggedIn } = useCurrentUser();
  const [post, setPost] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const guestLightbox = useLightbox();

  useEffect(() => {
    if (userIsLoggedIn && id) {
      navigate(`/post/${id}`, { replace: true });
    }
  }, [userIsLoggedIn, id, navigate]);

  useEffect(() => {
    if (!id || userIsLoggedIn) return;
    setLoading(true);
    fetch(`${API_BASE}/posts/${id}/public`)
      .then(res => res.json())
      .then(data => {
        if (data.success && data.data) {
          setPost(data.data);
          // Update OG meta tags dynamically
          const ogTitle = document.querySelector('meta[property="og:title"]');
          const ogDesc = document.querySelector('meta[property="og:description"]');
          const ogImage = document.querySelector('meta[property="og:image"]');
          const ogUrl = document.querySelector('meta[property="og:url"]');
          
          if (data.data.images?.length > 0) {
            const firstUrl = getImageUrl(data.data.images[0]);
            if (firstUrl) {
              if (ogImage) ogImage.setAttribute('content', firstUrl);
              else {
                const meta = document.createElement('meta');
                meta.setAttribute('property', 'og:image');
                meta.setAttribute('content', firstUrl);
                document.head.appendChild(meta);
              }
            }
          }
          const title = data.data.content?.slice(0, 60) || 'Shared on Nuru';
          if (ogTitle) ogTitle.setAttribute('content', title);
          if (ogDesc) ogDesc.setAttribute('content', data.data.content?.slice(0, 160) || 'Check out this moment on Nuru');
          if (ogUrl) ogUrl.setAttribute('content', window.location.href);
        } else {
          setError(data.message || 'Post not found or is private');
        }
      })
      .catch(() => setError('Failed to load post'))
      .finally(() => setLoading(false));
  }, [id, userIsLoggedIn]);

  if (userIsLoggedIn) return null;

  const handleAuthAction = () => {
    navigate(`/login?redirect=/post/${id}`);
  };

  const headerBar = (
    <header className="border-b border-border px-4 py-3 flex items-center justify-between sticky top-0 bg-background z-50">
      <Link to="/"><img src={nuruLogo} alt="Nuru" className="h-8" /></Link>
      <div className="flex gap-2">
        <Button variant="outline" size="sm" asChild><Link to="/login">{t("sign_in")}</Link></Button>
        <Button size="sm" className="bg-[hsl(var(--nuru-yellow))] hover:bg-[hsl(var(--nuru-yellow))]/90 text-foreground" asChild><Link to="/register">{t("sign_up")}</Link></Button>
      </div>
    </header>
  );

  if (loading) {
    return (
      <div className="min-h-screen bg-background">
        {headerBar}
        <div className="max-w-2xl mx-auto p-4 space-y-4">
          <Skeleton className="h-12 w-2/3" />
          <Skeleton className="h-64 w-full rounded-lg" />
          <Skeleton className="h-6 w-1/2" />
        </div>
      </div>
    );
  }

  if (error || !post) {
    return (
      <div className="min-h-screen bg-background">
        {headerBar}
        <div className="max-w-2xl mx-auto p-4 text-center py-16">
          <p className="text-muted-foreground text-lg mb-4">{error || 'This post is not available'}</p>
          <p className="text-sm text-muted-foreground mb-6">Sign in to see more content on Nuru</p>
          <div className="flex gap-3 justify-center">
            <Button asChild><Link to="/login">{t("sign_in")}</Link></Button>
            <Button variant="outline" asChild><Link to="/register">Create Account</Link></Button>
          </div>
        </div>
      </div>
    );
  }

  const authorName = post.author?.name || 'Anonymous';
  const authorAvatar = post.author?.avatar || '';
  const authorVerified = post.author?.is_verified || post.user?.is_identity_verified || false;
  const postContent = post.content || '';
  const postImages = post.images || [];
  const postTimeAgo = post.created_at ? getTimeAgo(post.created_at) : 'Recently';
  const postLocation = post.location || '';

  return (
    <div className="min-h-screen bg-background">
      {headerBar}

      <div className="max-w-2xl mx-auto p-3 md:p-4">
        {/* Post card */}
        <div className="bg-card rounded-lg shadow-sm border border-border overflow-hidden">
          {/* Author */}
          <div className="p-3 md:p-4 flex items-center gap-3">
            {authorAvatar ? (
              <img src={authorAvatar} alt={authorName} className="w-10 h-10 rounded-full object-cover" />
            ) : (
              <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center text-primary font-semibold">
                {getInitials(authorName)}
              </div>
            )}
            <div>
              <h3 className="font-semibold text-foreground text-sm md:text-base flex items-center gap-1.5">
                {authorName}

              </h3>
              <p className="text-xs text-muted-foreground">
                {postTimeAgo}
                {postLocation && <span className="inline-flex items-center gap-0.5"> - <MapPin className="w-3 h-3 inline" /> {postLocation}</span>}
              </p>
            </div>
          </div>

          {/* Images */}
          {postImages.length > 0 && (
            <div className="px-3 md:px-4">
              {postImages.length === 1 ? (
                (() => {
                  const url = getImageUrl(postImages[0]);
                  if (!url) return null;
                  return isVideoMedia(postImages[0]) ? (
                    <video src={url} controls className="w-full max-h-[500px] rounded-lg bg-muted/30" />
                  ) : (
                    <img
                      src={url}
                      alt="Post"
                      className="w-full max-h-[500px] object-contain rounded-lg bg-muted/30 cursor-pointer hover:opacity-95 transition-opacity"
                      onClick={() => {
                        const allUrls = postImages.map(getImageUrl).filter((u): u is string => !!u && !isVideoMedia(postImages[postImages.indexOf(postImages.find(p => getImageUrl(p) === u)!)]));
                        guestLightbox.openLightbox(allUrls, 0);
                      }}
                    />
                  );
                })()
              ) : (
                <div className="flex gap-2 overflow-x-auto py-1">
                  {postImages.map((img: any, idx: number) => {
                    const url = getImageUrl(img);
                    if (!url) return null;
                    return isVideoMedia(img) ? (
                      <video key={idx} src={url} muted playsInline preload="metadata" className="w-40 h-32 md:w-48 md:h-40 flex-shrink-0 object-cover rounded-lg" />
                    ) : (
                      <img
                        key={idx}
                        src={url}
                        alt={`Post ${idx + 1}`}
                        className="w-40 h-32 md:w-48 md:h-40 flex-shrink-0 object-cover rounded-lg cursor-pointer hover:opacity-90 transition-opacity"
                        onClick={() => {
                          const allUrls = postImages.map(getImageUrl).filter((u): u is string => !!u);
                          const imageOnlyUrls = allUrls.filter((_, i) => !isVideoMedia(postImages[i]));
                          const imgIdx = imageOnlyUrls.indexOf(url);
                          guestLightbox.openLightbox(imageOnlyUrls, imgIdx >= 0 ? imgIdx : 0);
                        }}
                      />
                    );
                  })}
                </div>
              )}
            </div>
          )}

          {/* Content */}
          <div className="px-3 md:px-4 py-3">
            {postContent && <p className="text-foreground text-sm md:text-base whitespace-pre-wrap break-words">{postContent}</p>}
          </div>

          {/* Actions - disabled for guests */}
          <div className="px-3 md:px-4 py-3 border-t border-border flex flex-wrap items-center justify-between gap-2">
            <div className="flex gap-2 flex-wrap">
              <button onClick={handleAuthAction} className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-muted/50 text-muted-foreground text-xs md:text-sm">
                <span className="text-sm">❤️</span> <span>Glow</span>
              </button>
              <button onClick={handleAuthAction} className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-muted/50 text-muted-foreground text-xs md:text-sm">
                <MessageCircle className="w-3.5 h-3.5 md:w-4 md:h-4" /> <span>Echo</span>
              </button>
              <button onClick={handleAuthAction} className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-muted/50 text-muted-foreground text-xs md:text-sm">
                <img src={ShareIcon} alt="" className="w-3.5 h-3.5 md:w-4 md:h-4 dark:invert opacity-70" /> <span>Spark</span>
              </button>
            </div>
            <div className="flex items-center gap-3 text-xs text-muted-foreground">
              <span>{post.glow_count || 0} Glows</span>
              <span>{post.comment_count || 0} Echoes</span>
            </div>
          </div>
        </div>

        {/* Sign in prompt */}
        <div className="mt-6 p-6 bg-card rounded-lg border border-border text-center">
          <h2 className="text-lg font-semibold mb-2">Join Nuru to interact</h2>
          <p className="text-sm text-muted-foreground mb-4">
            Sign in or create an account to glow, echo, and share this post.
          </p>
          <div className="flex gap-3 justify-center flex-wrap">
            <Button asChild><Link to={`/login?redirect=/post/${id}`}>{t("sign_in")}</Link></Button>
            <Button className="bg-[hsl(var(--nuru-yellow))] hover:bg-[hsl(var(--nuru-yellow))]/90 text-foreground" asChild><Link to="/register">Create Account</Link></Button>
          </div>
        </div>
      </div>
      <ImageLightbox
        images={guestLightbox.images}
        initialIndex={guestLightbox.index}
        open={guestLightbox.open}
        onClose={guestLightbox.closeLightbox}
      />
    </div>
  );
};

export default GuestPost;
