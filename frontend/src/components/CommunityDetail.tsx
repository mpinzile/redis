import { useState, useEffect, useRef } from 'react';
import ImageLightbox, { useLightbox } from '@/components/ui/image-lightbox';
import { useParams, useNavigate } from 'react-router-dom';
import { ChevronLeft, Users, Crown, Plus, Loader2, Heart, Send, X, Search, Trash2, Camera } from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import CustomImageIcon from '@/assets/icons/image-icon.svg';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Textarea } from '@/components/ui/textarea';
import { Input } from '@/components/ui/input';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import { toast } from 'sonner';
import { socialApi } from '@/lib/api/social';
import { useCurrentUser } from '@/hooks/useCurrentUser';
import { getTimeAgo } from '@/utils/getTimeAgo';
import { useUserSearch } from '@/hooks/useUserSearch';
import { useLanguage } from '@/lib/i18n/LanguageContext';

const getInitials = (name: string) => {
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
  return name.charAt(0).toUpperCase();
};

const CommunityDetail = () => {
  const { id } = useParams();
  const navigate = useNavigate();
  const currentUserQuery = useCurrentUser();
  const currentUser = currentUserQuery.data as any;

  const [community, setCommunity] = useState<any>(null);
  const [members, setMembers] = useState<any[]>([]);
  const [posts, setPosts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [joining, setJoining] = useState(false);
  const communityLightbox = useLightbox();

  // Creator post form
  const [postContent, setPostContent] = useState('');
  const [postImages, setPostImages] = useState<File[]>([]);
  const [postPreviews, setPostPreviews] = useState<string[]>([]);
  const [posting, setPosting] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const coverFileRef = useRef<HTMLInputElement>(null);
  const [uploadingCover, setUploadingCover] = useState(false);

  // Add member dialog
  const [addMemberOpen, setAddMemberOpen] = useState(false);
  const [addingMember, setAddingMember] = useState(false);
  const [memberSearchQuery, setMemberSearchQuery] = useState('');
  const { results: memberSearchResults, loading: memberSearchLoading, search: searchUsers } = useUserSearch();

  useEffect(() => {
    searchUsers(memberSearchQuery);
  }, [memberSearchQuery, searchUsers]);

  const fetchMembers = async () => {
    if (!id) return;
    try {
      const mRes = await socialApi.getCommunityMembers(id);
      if (mRes.success) {
        const md = mRes.data as any;
        setMembers(md?.members || (Array.isArray(md) ? md : []));
      }
    } catch { /* silent */ }
  };

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    setLoading(true);
    // Reset stale data when switching communities
    setMembers([]); setPosts([]);

    // Essential: community details first — this unblocks the page render
    socialApi.getCommunity(id).then((cRes) => {
      if (cancelled) return;
      if (cRes.success) setCommunity(cRes.data);
    }).catch(() => {}).finally(() => { if (!cancelled) setLoading(false); });

    // Secondary data loads in parallel without blocking the main UI
    socialApi.getCommunityMembers(id).then((mRes) => {
      if (cancelled || !mRes.success) return;
      const md = mRes.data as any;
      setMembers(md?.members || (Array.isArray(md) ? md : []));
    }).catch(() => {});

    socialApi.getCommunityPosts(id).then((pRes) => {
      if (cancelled || !pRes.success) return;
      const pd = pRes.data as any;
      setPosts(pd?.posts || (Array.isArray(pd) ? pd : []));
    }).catch(() => {});

    return () => { cancelled = true; };
  }, [id]);

  const handleJoin = async () => {
    if (!id) return;
    setJoining(true);
    const tid = 'cd-join';
    toast.loading('Joining community…', { id: tid });
    try {
      const res = await socialApi.joinCommunity(id);
      if (res.success) {
        toast.success('Joined community!', { id: tid });
        setCommunity((prev: any) => prev ? { ...prev, is_member: true, member_count: (prev.member_count || 0) + 1 } : prev);
        await fetchMembers();
      } else {
        toast.error('Failed to join', { id: tid });
      }
    } catch { toast.error('Failed to join', { id: tid }); }
    finally { setJoining(false); }
  };

  const handleAddMember = async (userId: string) => {
    if (!id) return;
    setAddingMember(true);
    const tid = `cd-add-${userId}`;
    toast.loading('Adding member…', { id: tid });
    try {
      const res = await socialApi.addCommunityMember(id, userId);
      if (res.success) {
        toast.success('Member added!', { id: tid });
        await fetchMembers();
        setCommunity((prev: any) => prev ? { ...prev, member_count: (prev.member_count || 0) + 1 } : prev);
        setMemberSearchQuery('');
      } else {
        toast.error(res.message || 'Failed to add member', { id: tid });
      }
    } catch { toast.error('Failed to add member', { id: tid }); }
    finally { setAddingMember(false); }
  };

  const handleRemoveMember = async (userId: string) => {
    if (!id) return;
    const tid = `cd-rm-${userId}`;
    toast.loading('Removing member…', { id: tid });
    try {
      const res = await socialApi.removeCommunityMember(id, userId);
      if (res.success) {
        toast.success('Member removed', { id: tid });
        await fetchMembers();
        setCommunity((prev: any) => prev ? { ...prev, member_count: Math.max(0, (prev.member_count || 0) - 1) } : prev);
      } else {
        toast.error(res.message || 'Failed to remove member', { id: tid });
      }
    } catch { toast.error('Failed to remove member', { id: tid }); }
  };

  const handleImageSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files) return;
    const files = Array.from(e.target.files).slice(0, 10 - postImages.length);
    setPostImages(prev => [...prev, ...files]);
    setPostPreviews(prev => [...prev, ...files.map(f => URL.createObjectURL(f))]);
  };

  const removeImage = (idx: number) => {
    setPostImages(prev => prev.filter((_, i) => i !== idx));
    setPostPreviews(prev => prev.filter((_, i) => i !== idx));
  };

  const handleCreatePost = async () => {
    if (!id || (!postContent.trim() && postImages.length === 0)) return;
    setPosting(true);
    const tid = 'cd-post';
    toast.loading('Sharing post…', { id: tid });
    try {
      const formData = new FormData();
      if (postContent.trim()) formData.append('content', postContent.trim());
      postImages.forEach(f => formData.append('images', f));
      const res = await socialApi.createCommunityPost(id, formData);
      if (res.success) {
        toast.success('Post shared!', { id: tid });
        setPostContent('');
        setPostImages([]);
        setPostPreviews([]);
        const pRes = await socialApi.getCommunityPosts(id);
        if (pRes.success) {
          const pd = pRes.data as any;
          setPosts(pd?.posts || (Array.isArray(pd) ? pd : []));
        }
      } else {
        toast.error(res.message || 'Failed to post', { id: tid });
      }
    } catch { toast.error('Failed to create post', { id: tid }); }
    finally { setPosting(false); }
  };

  const handleGlow = async (postId: string, hasGlowed: boolean) => {
    if (!id) return;
    setPosts(prev => prev.map(p =>
      p.id === postId
        ? { ...p, has_glowed: !hasGlowed, glow_count: (p.glow_count || 0) + (hasGlowed ? -1 : 1) }
        : p
    ));
    try {
      if (hasGlowed) {
        await socialApi.unglowCommunityPost(id, postId);
      } else {
        await socialApi.glowCommunityPost(id, postId);
      }
    } catch {
      setPosts(prev => prev.map(p =>
        p.id === postId
          ? { ...p, has_glowed: hasGlowed, glow_count: (p.glow_count || 0) + (hasGlowed ? 1 : -1) }
          : p
      ));
      toast.error('Failed to update glow');
    }
  };

  const isCreator = community?.is_creator && currentUser && community.created_by
    ? String(community.created_by) === String(currentUser.id)
    : community?.is_creator;

  // Existing member IDs for filtering search results
  const memberIds = new Set(members.map((m: any) => m.id || m.user_id));

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-40 w-full rounded-lg" />
        <Skeleton className="h-6 w-1/3" />
        <Skeleton className="h-4 w-2/3" />
        <div className="grid grid-cols-1 gap-4">
          {[1,2,3].map(i => <Skeleton key={i} className="h-32 w-full" />)}
        </div>
      </div>
    );
  }

  if (!community) {
    return <div className="text-center py-12 text-muted-foreground">Community not found</div>;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center gap-2 mb-3">
          <h1 className="flex-1 min-w-0 text-lg sm:text-2xl font-bold text-foreground break-words leading-tight">
            {community.name}
          </h1>
          <Button variant="ghost" size="icon" className="flex-shrink-0" onClick={() => navigate('/communities')} aria-label="Back">
            <ChevronLeft className="w-5 h-5" />
          </Button>
        </div>
        
        <div className="relative h-40 w-full overflow-hidden rounded-lg bg-muted flex items-center justify-center group">
          {community.image ? (
            <img src={community.image} alt={community.name} className="w-full h-full object-cover" />
          ) : (
            <Users className="w-16 h-16 text-muted-foreground" />
          )}
          {isCreator && (
            <>
              <button
                onClick={() => coverFileRef.current?.click()}
                className="absolute bottom-2 right-2 bg-black/60 text-white rounded-full p-2 opacity-0 group-hover:opacity-100 transition-opacity hover:bg-black/80"
                title="Change cover image"
                disabled={uploadingCover}
              >
                {uploadingCover ? <Loader2 className="w-4 h-4 animate-spin" /> : <Camera className="w-4 h-4" />}
              </button>
              <input
                ref={coverFileRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={async (e) => {
                  const file = e.target.files?.[0];
                  if (!file || !id) return;
                  setUploadingCover(true);
                  try {
                    const res = await socialApi.updateCommunityCover(id, file);
                    if (res.success) {
                      setCommunity((prev: any) => prev ? { ...prev, image: res.data?.image || prev.image } : prev);
                      toast.success('Cover image updated!');
                    } else {
                      toast.error(res.message || 'Failed to update cover');
                    }
                  } catch { toast.error('Failed to upload cover image'); }
                  finally { setUploadingCover(false); }
                }}
              />
            </>
          )}
        </div>

        <div className="flex items-start justify-between mt-4 gap-3">
          <div>
            <div className="flex items-center gap-2">
              {isCreator && <Badge className="bg-nuru-yellow text-foreground"><Crown className="w-3 h-3 mr-1" />Creator</Badge>}
            </div>
            <p className="text-muted-foreground mt-1">{community.description || 'No description'}</p>
            <p className="text-sm text-muted-foreground mt-1 flex items-center gap-1">
              <Users className="w-4 h-4" /> {members.length || community.member_count || 0} members
            </p>
          </div>
          {!community.is_member && (
            <Button onClick={handleJoin} disabled={joining} className="bg-nuru-yellow hover:bg-nuru-yellow/90 text-foreground">
              {joining ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <Plus className="w-4 h-4 mr-2" />}
              Join
            </Button>
          )}
        </div>
      </div>

      {/* Members preview */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <CardTitle className="text-lg">Members ({members.length})</CardTitle>
            {isCreator && (
              <Button size="sm" variant="outline" onClick={() => setAddMemberOpen(true)}>
                <Plus className="w-4 h-4 mr-1" /> Add Member
              </Button>
            )}
          </div>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-3">
            {members.slice(0, 10).map((m: any) => {
              const mName = m.first_name 
                ? `${m.first_name} ${m.last_name || ''}`.trim() 
                : m.name || m.username || 'User';
              const mUserId = m.user_id || m.id;
              return (
                <div key={m.id || mUserId} className="flex items-center gap-2 group">
                  <Avatar className="w-8 h-8">
                    <AvatarImage src={m.avatar} />
                    <AvatarFallback className="text-xs">{getInitials(mName)}</AvatarFallback>
                  </Avatar>
                  <span className="text-sm">{mName}</span>
                  {m.role === 'admin' && <Badge variant="outline" className="text-xs">Admin</Badge>}
                  {isCreator && String(mUserId) !== String(currentUser?.id) && (
                    <button
                      onClick={(e) => { e.stopPropagation(); handleRemoveMember(mUserId); }}
                      className="opacity-0 group-hover:opacity-100 transition-opacity text-destructive hover:text-destructive/80"
                      title="Remove member"
                    >
                      <X className="w-3.5 h-3.5" />
                    </button>
                  )}
                </div>
              );
            })}
            {members.length > 10 && (
              <span className="text-sm text-muted-foreground self-center">+{members.length - 10} more</span>
            )}
            {members.length === 0 && <p className="text-sm text-muted-foreground">No members yet</p>}
          </div>
        </CardContent>
      </Card>

      {/* Add Member Dialog */}
      <Dialog open={addMemberOpen} onOpenChange={setAddMemberOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Add Member</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                placeholder="Search by name, phone, or email..."
                value={memberSearchQuery}
                onChange={(e) => setMemberSearchQuery(e.target.value)}
                className="pl-9"
              />
            </div>
            <div className="max-h-60 overflow-y-auto space-y-2">
              {memberSearchLoading && <p className="text-sm text-muted-foreground text-center py-4">Searching...</p>}
              {!memberSearchLoading && memberSearchQuery.length >= 2 && memberSearchResults.length === 0 && (
                <p className="text-sm text-muted-foreground text-center py-4">No users found</p>
              )}
              {memberSearchResults
                .filter((u: any) => !memberIds.has(u.id))
                .map((user: any) => {
                  const uName = `${user.first_name || ''} ${user.last_name || ''}`.trim() || user.username || 'User';
                  return (
                    <div key={user.id} className="flex items-center justify-between p-2 rounded-lg hover:bg-muted/50">
                      <div className="flex items-center gap-3">
                        <Avatar className="w-9 h-9">
                          <AvatarImage src={user.avatar} />
                          <AvatarFallback className="text-xs">{getInitials(uName)}</AvatarFallback>
                        </Avatar>
                        <div>
                          <p className="text-sm font-medium">{uName}</p>
                          <p className="text-xs text-muted-foreground">@{user.username}</p>
                        </div>
                      </div>
                      <Button size="sm" onClick={() => handleAddMember(user.id)} disabled={addingMember}>
                        {addingMember ? <Loader2 className="w-3 h-3 animate-spin" /> : <Plus className="w-3 h-3 mr-1" />}
                        Add
                      </Button>
                    </div>
                  );
                })}
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Creator post input */}
      {isCreator && (
        <Card>
          <CardContent className="pt-4">
            <textarea
              placeholder="Share something with your community..."
              value={postContent}
              onChange={(e) => setPostContent(e.target.value)}
              rows={2}
              maxLength={2000}
              className="w-full bg-transparent text-foreground text-sm outline-none placeholder:text-muted-foreground resize-none overflow-hidden border border-border rounded-lg px-3 py-2 mb-3"
              onInput={(e) => { const t = e.target as HTMLTextAreaElement; t.style.height = 'auto'; t.style.height = Math.min(t.scrollHeight, 200) + 'px'; }}
            />
            {postPreviews.length > 0 && (
              <div className="flex gap-2 overflow-x-auto mb-3">
                {postPreviews.map((src, idx) => (
                  <div key={idx} className="relative w-20 h-20 flex-shrink-0 rounded-lg overflow-hidden border border-border">
                    <img src={src} alt="" className="w-full h-full object-cover" />
                    <button onClick={() => removeImage(idx)} className="absolute top-0.5 right-0.5 bg-black/60 text-white rounded-full w-5 h-5 flex items-center justify-center text-xs">×</button>
                  </div>
                ))}
              </div>
            )}
            <div className="flex items-center justify-between">
              <Button type="button" variant="ghost" size="sm" onClick={() => fileRef.current?.click()} disabled={postImages.length >= 10}>
                <img src={CustomImageIcon} alt="Photo" className="w-4 h-4 mr-1 inline" /> Photo
              </Button>
              <input ref={fileRef} type="file" accept="image/*" multiple className="hidden" onChange={handleImageSelect} />
              <Button size="sm" onClick={handleCreatePost} disabled={posting || (!postContent.trim() && postImages.length === 0)} className="bg-nuru-yellow hover:bg-nuru-yellow/90 text-foreground">
                {posting ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : <Send className="w-4 h-4 mr-1" />}
                Post
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Community Posts */}
      <div>
        <h2 className="text-xl font-semibold mb-4">Community Posts</h2>
        {posts.length > 0 ? (
          <div className="space-y-4">
            {posts.map((post: any) => {
              const author = post.author || {};
              const authorName = author.name || `${author.first_name || ''} ${author.last_name || ''}`.trim() || 'Unknown';
              const authorAvatar = author.avatar;
              const isPlaceholderAvatar = !authorAvatar;
              const images = post.images || [];
              return (
                <div key={post.id} className="bg-card rounded-lg shadow-sm border border-border overflow-hidden">
                  {/* Post Header */}
                  <div className="p-3 md:p-4 flex items-center justify-between">
                    <div className="flex items-center gap-2 md:gap-3">
                      {!isPlaceholderAvatar ? (
                        <img
                          src={authorAvatar}
                          alt={authorName}
                          className="w-9 h-9 md:w-10 md:h-10 rounded-full object-cover"
                        />
                      ) : (
                        <div className="w-9 h-9 md:w-10 md:h-10 rounded-full bg-primary/10 flex items-center justify-center text-primary font-semibold text-sm">
                          {getInitials(authorName)}
                        </div>
                      )}
                      <div>
                        <h3 className="font-semibold text-sm md:text-base text-foreground flex items-center gap-1.5">
                          {authorName}

                        </h3>
                        <p className="text-xs md:text-sm text-muted-foreground">{post.created_at ? getTimeAgo(post.created_at) : ''}</p>
                      </div>
                    </div>
                  </div>

                  {/* Images */}
                  {images.length > 0 && (
                    <div className={`px-3 md:px-4 ${images.length > 1 ? 'flex gap-2 overflow-x-auto py-1' : ''}`}>
                      {images.length === 1 ? (
                        <img
                          src={images[0]}
                          alt=""
                          className="w-full max-h-[500px] object-contain rounded-lg bg-muted/30 cursor-pointer hover:opacity-95 transition-opacity"
                          onClick={() => communityLightbox.openLightbox(images, 0)}
                        />
                      ) : (
                        images.map((img: string, idx: number) => (
                          <img
                            key={idx}
                            src={img}
                            alt={`Post ${idx + 1}`}
                            className="w-40 h-32 md:w-48 md:h-40 flex-shrink-0 object-cover rounded-lg cursor-pointer hover:opacity-90 transition-opacity"
                            onClick={() => communityLightbox.openLightbox(images, idx)}
                          />
                        ))
                      )}
                    </div>
                  )}

                  {/* Text content */}
                  {post.content && (
                    <div className="px-3 md:px-4 py-3">
                      <p className="text-foreground text-sm md:text-base whitespace-pre-wrap break-words">{post.content}</p>
                    </div>
                  )}

                  {/* Action Buttons */}
                  <div className="px-3 md:px-4 py-2 md:py-3 border-t border-border flex items-center justify-between">
                    <div className="flex gap-2">
                      <button
                        onClick={() => handleGlow(post.id, post.has_glowed || false)}
                        className={`flex items-center justify-center gap-1.5 px-3 py-1.5 md:px-4 md:py-2 rounded-lg transition-colors text-xs md:text-sm min-w-[60px] md:min-w-[80px] ${
                          post.has_glowed ? 'bg-red-100 text-red-600' : 'bg-muted/50 text-muted-foreground hover:bg-muted hover:text-foreground'
                        }`}
                      >
                        <span className="text-sm flex-shrink-0">❤️</span>
                        <span className="hidden sm:inline whitespace-nowrap">{post.has_glowed ? 'Glowed' : 'Glow'}</span>
                      </button>
                    </div>
                    <div className="flex items-center gap-3 md:gap-4 text-xs md:text-sm text-muted-foreground">
                      <span>{post.glow_count || 0} {(post.glow_count || 0) === 1 ? 'Glow' : 'Glows'}</span>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        ) : (
          <Card className="p-8 text-center">
            <p className="text-muted-foreground">
              {isCreator
                ? 'No posts yet. Share something with your community!' 
                : 'No posts yet.'}
            </p>
          </Card>
        )}
      </div>
      <ImageLightbox
        images={communityLightbox.images}
        initialIndex={communityLightbox.index}
        open={communityLightbox.open}
        onClose={communityLightbox.closeLightbox}
      />
    </div>
  );
};

export default CommunityDetail;
