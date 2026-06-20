import { useState, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, Users, Search, LogOut, Crown, Loader2, ImageIcon } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogFooter } from '@/components/ui/dialog';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { useWorkspaceMeta } from '@/hooks/useWorkspaceMeta';
import { useCommunities } from '@/data/useSocial';
import { useLanguage } from '@/lib/i18n/LanguageContext';

const Communities = () => {
  const { t } = useLanguage();
  const navigate = useNavigate();
  useWorkspaceMeta({
    title: 'Communities',
    description: 'Join communities and connect with like-minded people for events, weddings, and celebrations.'
  });

  const { 
    communities, 
    myCommunities,
    loading, 
    error,
    createCommunity, 
    joinCommunity, 
    leaveCommunity 
  } = useCommunities();
  
  const [searchQuery, setSearchQuery] = useState('');
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [newCommunity, setNewCommunity] = useState({
    name: '',
    description: ''
  });
  const [coverImage, setCoverImage] = useState<File | null>(null);
  const [coverPreview, setCoverPreview] = useState<string | null>(null);
  const coverFileRef = useRef<HTMLInputElement>(null);

  const handleCoverSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setCoverImage(file);
      setCoverPreview(URL.createObjectURL(file));
    }
  };

  const handleCreateCommunity = async () => {
    if (!newCommunity.name.trim() || !newCommunity.description.trim()) {
      toast.error('Please fill in all fields');
      return;
    }

    setIsSubmitting(true);
    const tid = 'create-community';
    toast.loading('Creating community…', { id: tid });
    try {
      await createCommunity({
        name: newCommunity.name,
        description: newCommunity.description
      }, coverImage || undefined);
      toast.success('Community created successfully!', { id: tid });
      setNewCommunity({ name: '', description: '' });
      setCoverImage(null);
      setCoverPreview(null);
      setIsCreateDialogOpen(false);
    } catch (err) {
      toast.error('Failed to create community', { id: tid });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleJoinCommunity = async (id: string) => {
    const tid = `join-${id}`;
    toast.loading('Joining community…', { id: tid });
    try {
      await joinCommunity(id);
      toast.success('Joined community successfully!', { id: tid });
    } catch (err) {
      toast.error('Failed to join community', { id: tid });
    }
  };

  const handleLeaveCommunity = async (id: string) => {
    const tid = `leave-${id}`;
    toast.loading('Leaving community…', { id: tid });
    try {
      await leaveCommunity(id);
      toast.success('Left community', { id: tid });
    } catch (err) {
      toast.error('Failed to leave community', { id: tid });
    }
  };

  const filteredCommunities = communities.filter(c =>
    c.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    c.description?.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const myFilteredCommunities = myCommunities.filter(c =>
    c.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    c.description?.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const otherCommunities = filteredCommunities.filter(
    c => !myCommunities.find(m => m.id === c.id)
  );

  // Loading state
  if (loading) {
    return (
      <div className="space-y-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-2xl md:text-3xl font-bold text-foreground flex items-center gap-2">
              <Users className="w-7 h-7 md:w-8 md:h-8" />
              Communities
            </h1>
            <p className="text-sm md:text-base text-muted-foreground mt-1">
              Join communities and connect with like-minded people
            </p>
          </div>
          <Skeleton className="h-10 w-40" />
        </div>
        <Skeleton className="h-10 w-full" />
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <Card key={i}>
              <Skeleton className="h-32 w-full rounded-t-lg" />
              <CardHeader>
                <Skeleton className="h-6 w-3/4" />
                <Skeleton className="h-4 w-full" />
              </CardHeader>
              <CardContent>
                <Skeleton className="h-8 w-full" />
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-foreground flex items-center gap-2">
            <Users className="w-7 h-7 md:w-8 md:h-8" />
            Communities
          </h1>
          <p className="text-sm md:text-base text-muted-foreground mt-1">
            Join communities and connect with like-minded people
          </p>
        </div>

        <Dialog open={isCreateDialogOpen} onOpenChange={(open) => {
          setIsCreateDialogOpen(open);
          if (!open) { setCoverImage(null); setCoverPreview(null); }
        }}>
          <DialogTrigger asChild>
            <Button className="bg-nuru-yellow hover:bg-nuru-yellow/90 text-foreground w-full md:w-auto">
              <Plus className="w-4 h-4 mr-2" />
              Create Community
            </Button>
          </DialogTrigger>
          <DialogContent className="max-w-md">
            <DialogHeader>
              <DialogTitle>Create New Community</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 mt-4">
              {/* Cover Image Upload */}
              <div>
                <Label>Cover Image</Label>
                <div
                  className="mt-1 relative h-32 w-full rounded-lg border-2 border-dashed border-border bg-muted/30 flex items-center justify-center cursor-pointer hover:bg-muted/50 transition-colors overflow-hidden"
                  onClick={() => coverFileRef.current?.click()}
                >
                  {coverPreview ? (
                    <img src={coverPreview} alt="Cover preview" className="w-full h-full object-cover" />
                  ) : (
                    <div className="text-center">
                      <ImageIcon className="w-8 h-8 mx-auto text-muted-foreground mb-1" />
                      <p className="text-xs text-muted-foreground">Click to add cover image</p>
                    </div>
                  )}
                </div>
                <input
                  ref={coverFileRef}
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={handleCoverSelect}
                  disabled={isSubmitting}
                />
              </div>
              <div>
                <Label htmlFor="name">{t('community_name')}</Label>
                <Input
                  id="name"
                  placeholder={t('community_name_placeholder')}
                  value={newCommunity.name}
                  onChange={(e) => setNewCommunity({ ...newCommunity, name: e.target.value })}
                  disabled={isSubmitting}
                />
              </div>
              <div>
                <Label htmlFor="description">{t('description')}</Label>
                <Textarea
                  id="description"
                  placeholder={t('describe_community')}
                  value={newCommunity.description}
                  onChange={(e) => setNewCommunity({ ...newCommunity, description: e.target.value })}
                  rows={4}
                  disabled={isSubmitting}
                />
              </div>
            </div>
            <DialogFooter>
              <Button
                onClick={handleCreateCommunity}
                className="bg-nuru-yellow hover:bg-nuru-yellow/90 text-foreground w-full"
                disabled={isSubmitting}
              >
                {isSubmitting ? (
                  <>
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    {t('creating')}
                  </>
                ) : (
                  t('create_community')
                )}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground w-4 h-4" />
        <Input
          placeholder={t('search_communities')}
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="pl-10"
        />
      </div>

      {/* My Communities */}
      {myFilteredCommunities.length > 0 && (
        <div>
          <h2 className="text-xl font-semibold text-foreground mb-4">{t('my_communities')}</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {myFilteredCommunities.map((community) => (
              <Card key={community.id} className="hover:shadow-md transition-shadow cursor-pointer" onClick={() => navigate(`/communities/${community.id}`)}>
                <div className="relative h-32 w-full overflow-hidden rounded-t-lg bg-muted flex items-center justify-center">
                  {community.image ? (
                    <img
                      src={community.image}
                      alt={community.name}
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <Users className="w-12 h-12 text-muted-foreground" />
                  )}
                  {community.is_creator && (
                    <Badge className="absolute top-2 right-2 bg-nuru-yellow text-foreground">
                      <Crown className="w-3 h-3 mr-1" />
                      Creator
                    </Badge>
                  )}
                </div>
                <CardHeader>
                  <CardTitle className="text-lg">{community.name}</CardTitle>
                  <p className="text-sm text-muted-foreground line-clamp-2">
                    {community.description || 'No description'}
                  </p>
                </CardHeader>
                <CardContent className="space-y-3">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-muted-foreground flex items-center gap-1">
                      <Users className="w-4 h-4" />
                      {community.member_count || 0} members
                    </span>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={(e) => { e.stopPropagation(); handleLeaveCommunity(community.id); }}
                    className="w-full"
                    disabled={community.is_creator}
                  >
                    <LogOut className="w-4 h-4 mr-2" />
                    {community.is_creator ? 'You own this' : 'Leave'}
                  </Button>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}

      {/* Discover Communities */}
      {otherCommunities.length > 0 && (
        <div>
          <h2 className="text-xl font-semibold text-foreground mb-4">Discover Communities</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {otherCommunities.map((community) => (
              <Card key={community.id} className="hover:shadow-md transition-shadow cursor-pointer" onClick={() => navigate(`/communities/${community.id}`)}>
                <div className="relative h-32 w-full overflow-hidden rounded-t-lg bg-muted flex items-center justify-center">
                  {community.image ? (
                    <img
                      src={community.image}
                      alt={community.name}
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <Users className="w-12 h-12 text-muted-foreground" />
                  )}
                </div>
                <CardHeader>
                  <CardTitle className="text-lg">{community.name}</CardTitle>
                  <p className="text-sm text-muted-foreground line-clamp-2">
                    {community.description || 'No description'}
                  </p>
                </CardHeader>
                <CardContent className="space-y-3">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-muted-foreground flex items-center gap-1">
                      <Users className="w-4 h-4" />
                      {community.member_count || 0} members
                    </span>
                  </div>
                  <Button
                    onClick={(e) => { e.stopPropagation(); handleJoinCommunity(community.id); }}
                    className="w-full bg-nuru-yellow hover:bg-nuru-yellow/90 text-foreground"
                  >
                    <Plus className="w-4 h-4 mr-2" />
                    Join Community
                  </Button>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}

      {/* Empty State */}
      {filteredCommunities.length === 0 && myCommunities.length === 0 && (
        <Card className="p-8 md:p-12 text-center">
          <Users className="w-16 h-16 mx-auto text-muted-foreground mb-4" />
          <h3 className="text-xl font-semibold text-foreground mb-2">
            {searchQuery ? 'No communities found' : 'No communities yet'}
          </h3>
          <p className="text-muted-foreground mb-6">
            {searchQuery
              ? 'Try a different search term'
              : 'Create the first community and invite others to join'
            }
          </p>
          {!searchQuery && (
            <Button
              onClick={() => setIsCreateDialogOpen(true)}
              className="bg-nuru-yellow hover:bg-nuru-yellow/90 text-foreground"
            >
              <Plus className="w-4 h-4 mr-2" />
              Create Community
            </Button>
          )}
        </Card>
      )}
    </div>
  );
};

export default Communities;
