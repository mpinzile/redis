import { useState, useEffect, useCallback } from 'react';
import Moment from '@/components/Moment';
import { getTimeAgo } from '@/utils/getTimeAgo';
import { Button } from '@/components/ui/button';
import { MoreHorizontal, Edit, Trash2, Globe, Users } from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
import { useNavigate } from 'react-router-dom';
import { useWorkspaceMeta } from '@/hooks/useWorkspaceMeta';
import { useCurrentUser } from '@/hooks/useCurrentUser';
import { socialApi } from '@/lib/api/social';
import { toast } from 'sonner';
import { useLanguage } from '@/lib/i18n/LanguageContext';

// Module-level cache for my moments/posts
let _myPostsCache: any[] = [];
let _myPostsHasLoaded = false;

const MyMoments = () => {
  const { t } = useLanguage();
  const navigate = useNavigate();
  const { data: currentUser } = useCurrentUser();
  const [posts, setPosts] = useState<any[]>(_myPostsCache);
  const [loading, setLoading] = useState(!_myPostsHasLoaded);
  const [error, setError] = useState<string | null>(null);

  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [editingPost, setEditingPost] = useState<any>(null);
  const [editText, setEditText] = useState('');
  const [editVisibility, setEditVisibility] = useState<string>('public');

  useWorkspaceMeta({
    title: "Your Moments",
    description: "Manage your moments, edit, delete, or change their visibility."
  });

  const fetchMyPosts = useCallback(async () => {
    if (!currentUser?.id) return;
    if (!_myPostsHasLoaded) setLoading(true);
    setError(null);
    try {
      const response = await socialApi.getUserPosts(currentUser.id);
      if (response.success) {
        const data = response.data as any;
        const postsList = data?.posts || data?.items || (Array.isArray(data) ? data : []);
        _myPostsCache = postsList;
        _myPostsHasLoaded = true;
        setPosts(postsList);
      } else {
        setError(response.message || 'Failed to load posts');
      }
    } catch {
      setError('Failed to load your moments');
    } finally {
      setLoading(false);
    }
  }, [currentUser?.id]);

  useEffect(() => {
    fetchMyPosts();
  }, [fetchMyPosts]);

  // getTimeAgo imported from shared utility

  const handleDelete = async (postId: string) => {
    const tid = `del-moment-${postId}`;
    toast.loading('Deleting moment…', { id: tid });
    try {
      const response = await socialApi.deletePost(postId);
      if (response.success) {
        setPosts(posts.filter(p => p.id !== postId));
        toast.success('Moment deleted successfully', { id: tid });
      } else {
        toast.error('Failed to delete moment', { id: tid });
      }
    } catch {
      toast.error('Failed to delete moment', { id: tid });
    }
  };

  const handleEdit = (post: any) => {
    setEditingPost(post);
    setEditText(post.content || '');
    setEditVisibility(post.visibility || 'public');
    setEditDialogOpen(true);
  };

  const handleVisibilityChange = async (postId: string, newVisibility: string) => {
    const tid = `vis-${postId}`;
    toast.loading('Updating visibility…', { id: tid });
    try {
      const response = await socialApi.updatePost(postId, { visibility: newVisibility });
      if (response.success) {
        setPosts(posts.map(p => p.id === postId ? { ...p, visibility: newVisibility } : p));
        toast.success(`Visibility changed to ${newVisibility === 'circle' ? 'My Circle' : 'Public'}`, { id: tid });
      } else {
        toast.error('Failed to change visibility', { id: tid });
      }
    } catch {
      toast.error('Failed to change visibility', { id: tid });
    }
  };

  const saveEdit = async () => {
    if (!editingPost) return;
    const tid = `edit-moment-${editingPost.id}`;
    toast.loading('Saving changes…', { id: tid });
    try {
      const response = await socialApi.updatePost(editingPost.id, { content: editText, visibility: editVisibility });
      if (response.success) {
        toast.success('Moment updated', { id: tid });
        setEditDialogOpen(false);
        fetchMyPosts();
      } else {
        toast.error('Failed to update', { id: tid });
      }
    } catch {
      toast.error('Failed to update moment', { id: tid });
    }
  };

  const viewPost = (post: any) => {
    navigate(`/post/${post.id}`);
  };

  if (loading) {
    return (
      <div className="space-y-4 md:space-y-6 pb-4">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl md:text-3xl font-bold">Your Moments</h1>
        </div>
        {[1, 2].map((i) => (
          <div key={i} className="bg-card rounded-lg shadow-sm border border-border p-4">
            <div className="flex items-center gap-3 mb-4">
              <Skeleton className="w-10 h-10 rounded-full" />
              <div className="space-y-2">
                <Skeleton className="h-4 w-32" />
                <Skeleton className="h-3 w-24" />
              </div>
            </div>
            <Skeleton className="h-48 w-full rounded-lg mb-4" />
            <Skeleton className="h-4 w-full" />
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-4 md:space-y-6 pb-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl md:text-3xl font-bold">Your Moments</h1>
        <Button onClick={() => navigate('/')} variant="outline">
          Share New Moment
        </Button>
      </div>

      {error && (
        <div className="bg-card rounded-lg shadow-sm border border-border p-8 text-center">
          <p className="text-destructive mb-4">{error}</p>
          <Button onClick={fetchMyPosts}>Retry</Button>
        </div>
      )}

      {!error && posts.length === 0 && (
        <div className="bg-card rounded-lg shadow-sm border border-border p-8 text-center">
          <p className="text-muted-foreground mb-4">You haven't shared any moments yet.</p>
          <Button onClick={() => navigate('/')}>Share Your First Moment</Button>
        </div>
      )}

      {posts.map((post) => {
        const authorName = post.author?.name || `${currentUser?.first_name || ''} ${currentUser?.last_name || ''}`.trim() || 'You';
        const authorAvatar = post.author?.avatar || currentUser?.avatar || '';
        const rawMedia = post.images || post.media || [];
        const imageUrls = rawMedia.map((m: any) => typeof m === 'string' ? m : (m?.image_url || m?.url)).filter(Boolean);
        const mediaTypesList = rawMedia.map((m: any) => typeof m === 'string' ? undefined : (m?.media_type || m?.type));

        const momentPost = {
          id: post.id,
          type: post.post_type || 'moment',
          author: {
            name: authorName,
            avatar: authorAvatar,
            timeAgo: post.created_at ? getTimeAgo(post.created_at) : 'Recently',
            is_verified: post.user?.is_identity_verified || post.author?.is_verified || false,
          },
          content: {
            title: post.title || '',
            text: post.content || '',
            images: imageUrls,
            media_types: mediaTypesList,
          },
          likes: post.glow_count || 0,
          comments: post.comment_count || post.echo_count || 0,
          has_glowed: post.has_glowed || false,
          has_saved: post.has_saved || false,
          shared_event: post.shared_event || null,
          share_expires_at: post.share_expires_at || null,
        };

        return (
          <div key={post.id} className="relative">
            {/* Management dropdown overlay */}
            <div className="absolute top-2 right-2 z-10">
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="secondary" size="sm" className="h-8 w-8 p-0 rounded-full shadow-sm">
                    <MoreHorizontal className="w-4 h-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="bg-background z-50">
                  <DropdownMenuItem onClick={() => handleEdit(post)}>
                    <Edit className="w-4 h-4 mr-2" />
                    Edit
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onClick={() => handleVisibilityChange(post.id, post.visibility === 'circle' ? 'public' : 'circle')}>
                    {post.visibility === 'circle' ? (
                      <><Globe className="w-4 h-4 mr-2" /> Make Public</>
                    ) : (
                      <><Users className="w-4 h-4 mr-2" /> Circle Only</>
                    )}
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem
                    onClick={() => handleDelete(post.id)}
                    className="text-destructive focus:text-destructive"
                  >
                    <Trash2 className="w-4 h-4 mr-2" />
                    Delete
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
            <Moment post={momentPost} />
          </div>
        );
      })}

      {/* Edit Dialog */}
      <Dialog open={editDialogOpen} onOpenChange={setEditDialogOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Edit Moment</DialogTitle>
            <DialogDescription>Make changes to your moment.</DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="text">{t('content')}</Label>
              <Textarea
                id="text"
                value={editText}
                onChange={(e) => setEditText(e.target.value)}
                placeholder={t('whats_on_your_mind')}
                rows={4}
              />
            </div>
            <div className="space-y-2">
              <Label>{t('visibility')}</Label>
              <Select value={editVisibility} onValueChange={setEditVisibility}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="public">
                    <span className="flex items-center gap-2"><Globe className="w-4 h-4" /> {t('public')}</span>
                  </SelectItem>
                  <SelectItem value="circle">
                    <span className="flex items-center gap-2"><Users className="w-4 h-4" /> {t('my_circle')}</span>
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setEditDialogOpen(false)}>{t("cancel")}</Button>
            <Button onClick={saveEdit}>{t("save_changes")}</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default MyMoments;
