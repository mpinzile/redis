import { useState } from 'react';
import { 
  UserPlus, Send, Search, Filter, CheckCircle, Clock, X,
  QrCode, Mail, Phone, MoreVertical, Trash, Loader2, BookUser, Download, Image as ImageIcon, Upload
} from 'lucide-react';

import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
  DropdownMenuSub, DropdownMenuSubTrigger, DropdownMenuSubContent, DropdownMenuSeparator,
  DropdownMenuLabel,
} from '@/components/ui/dropdown-menu';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useEventGuests } from '@/data/useEvents';
import { usePolling } from '@/hooks/usePolling';
import { useConfirmDialog } from '@/hooks/useConfirmDialog';
import { toast } from 'sonner';
import { showCaughtError } from '@/lib/api';
import UserSearchInput from './UserSearchInput';
import MemberImportDialog from './MemberImportDialog';

import ContributorSearchInput from './ContributorSearchInput';
import GuestListSkeletonLoader from './GuestListSkeletonLoader';
import type { EventGuest } from '@/lib/api/types';
import type { SearchedUser } from '@/hooks/useUserSearch';
import type { UserContributor } from '@/lib/api/contributors';
import type { EventPermissions } from '@/hooks/useEventPermissions';
import { useLanguage } from '@/lib/i18n/LanguageContext';

interface EventGuestListProps {
  eventId: string;
  permissions?: EventPermissions;
}

const EventGuestList = ({ eventId, permissions }: EventGuestListProps) => {
  const { t } = useLanguage();
  const canManage = permissions?.can_manage_guests || permissions?.is_creator;
  const canSendInvites = permissions?.can_send_invitations || permissions?.is_creator;
  const canCheckin = permissions?.can_check_in_guests || permissions?.is_creator;
  const { guests, summary, loading, error, refetch, addGuest, updateGuest, deleteGuest, sendInvitation, checkinGuest } = useEventGuests(eventId);
  
  const { confirm, ConfirmDialog } = useConfirmDialog();

  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [inviteDialogOpen, setInviteDialogOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);

  const [selectedGuest, setSelectedGuest] = useState<EventGuest | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  // Tracks which invitation send button is in flight so only that one spins.
  const [sendingMethod, setSendingMethod] = useState<null | 'email' | 'sms' | 'whatsapp' | 'card'>(null);
  const [selectedUser, setSelectedUser] = useState<SearchedUser | null>(null);
  const [selectedContributor, setSelectedContributor] = useState<UserContributor | null>(null);
  const [guestSourceTab, setGuestSourceTab] = useState<string>('user');
  

  const [newGuest, setNewGuest] = useState({
    plus_ones: 0,
    dietary_requirements: '',
    notes: '',
    common_name: '',
  });

  // Pause polling when any dialog is open to prevent form disruption
  const anyDialogOpen = addDialogOpen || inviteDialogOpen || importOpen;
  usePolling(refetch, 15000, !anyDialogOpen);

  const resetDialog = () => {
    setSelectedUser(null);
    setSelectedContributor(null);
    setNewGuest({ plus_ones: 0, dietary_requirements: '', notes: '', common_name: '' });
  };

  const handleAddGuest = async () => {
    if (guestSourceTab === 'contributor') {
      if (!selectedContributor) {
        toast.error('Please search and select a contributor');
        return;
      }

      setIsSubmitting(true);
      try {
        await addGuest({
          guest_type: 'contributor',
          contributor_id: selectedContributor.id,
          name: selectedContributor.name,
          phone: selectedContributor.phone || undefined,
          email: selectedContributor.email || undefined,
          common_name: newGuest.common_name.trim() || undefined,
          dietary_requirements: newGuest.dietary_requirements || undefined,
          notes: newGuest.notes || undefined,
          rsvp_status: 'pending'
        });
        toast.success('Contributor added as guest');
        setAddDialogOpen(false);
        resetDialog();
      } catch (err: any) {
        showCaughtError(err, 'Failed to add guest');
      } finally {
        setIsSubmitting(false);
      }
      return;
    }

    if (!selectedUser) {
      toast.error('Please search and select a user');
      return;
    }

    setIsSubmitting(true);
    try {
      await addGuest({
        guest_type: 'user',
        user_id: selectedUser.id,
        name: `${selectedUser.first_name} ${selectedUser.last_name}`,
        email: selectedUser.email,
        phone: selectedUser.phone || undefined,
        common_name: newGuest.common_name.trim() || undefined,
        plus_ones: newGuest.plus_ones,
        dietary_requirements: newGuest.dietary_requirements || undefined,
        notes: newGuest.notes || undefined,
        rsvp_status: 'pending'
      });
      toast.success('Guest added successfully');
      setAddDialogOpen(false);
      resetDialog();
    } catch (err: any) {
      showCaughtError(err, 'Failed to add guest');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleSendInvitation = async (method: "email" | "sms" | "whatsapp" | "whatsapp_text") => {
    if (!selectedGuest) return;
    setSendingMethod(method === 'whatsapp_text' ? 'whatsapp' : method);
    try {
      await sendInvitation(selectedGuest.id, method);
      toast.success(`Invitation sent via ${method === 'whatsapp_text' ? 'WhatsApp' : method}`);
      setInviteDialogOpen(false);
      setSelectedGuest(null);
    } catch (err: any) {
      showCaughtError(err, 'Failed to send invitation');
    } finally {
      setSendingMethod(null);
    }
  };

  const handleSendInvitationCard = async () => {
    if (!selectedGuest?.phone) {
      toast.error('Guest phone number is required');
      return;
    }
    setSendingMethod('card');
    try {
      await sendInvitation(selectedGuest.id, 'whatsapp');
      toast.success('Invitation card sent via WhatsApp');
      setInviteDialogOpen(false);
      setSelectedGuest(null);
    } catch (err: any) {
      showCaughtError(err, 'Failed to send invitation card');
    } finally {
      setSendingMethod(null);
    }
  };

  const handleCheckin = async (guestId: string) => {
    try {
      await checkinGuest(guestId);
      toast.success('Guest checked in successfully');
    } catch (err: any) {
      showCaughtError(err, 'Failed to check in guest');
    }
  };

  const handleUpdateRsvp = async (
    guest: EventGuest,
    status: 'confirmed' | 'pending' | 'declined' | 'maybe',
  ) => {
    if (guest.rsvp_status === status) return;
    try {
      await updateGuest(guest.id, { rsvp_status: status } as Partial<EventGuest>);
      const label =
        status === 'confirmed' ? 'Confirmed' :
        status === 'declined' ? 'Declined' :
        status === 'maybe' ? 'Maybe' : 'Pending';
      toast.success(`RSVP updated to ${label}`);
    } catch (err: any) {
      showCaughtError(err, 'Failed to update RSVP');
    }
  };

  const handleDeleteGuest = async (guestId: string) => {
    const confirmed = await confirm({
      title: 'Remove Guest',
      description: 'Are you sure you want to remove this guest? This action cannot be undone.',
      confirmLabel: 'Remove',
      destructive: true,
    });
    if (!confirmed) return;
    try {
      await deleteGuest(guestId);
      toast.success('Guest removed');
    } catch (err: any) {
      showCaughtError(err, 'Failed to remove guest');
    }
  };

  const filteredGuests = guests.filter(guest => {
    const name = guest.name || '';
    const matchesSearch = name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      guest.email?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      guest.phone?.includes(searchQuery);
    const matchesStatus = statusFilter === 'all' || guest.rsvp_status === statusFilter;
    return matchesSearch && matchesStatus;
  });

  const getStatusBadge = (status: string) => {
    const base = "rounded-full px-2.5 py-0.5 text-[11px] font-medium border";
    switch (status) {
      case 'confirmed':
        return (
          <Badge className={`${base} bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-300 dark:border-emerald-500/30`}>
            <CheckCircle className="w-3 h-3 mr-1" />Confirmed
          </Badge>
        );
      case 'pending':
        return (
          <Badge className={`${base} bg-muted/60 text-muted-foreground border-border`}>
            <span className="inline-block w-1.5 h-1.5 rounded-full bg-muted-foreground/60 mr-1.5" />
            Awaiting reply
          </Badge>
        );
      case 'declined':
        return (
          <Badge className={`${base} bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-500/10 dark:text-rose-300 dark:border-rose-500/30`}>
            <X className="w-3 h-3 mr-1" />Declined
          </Badge>
        );
      case 'maybe':
        return (
          <Badge className={`${base} bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-500/10 dark:text-amber-300 dark:border-amber-500/30`}>
            Maybe
          </Badge>
        );
      default:
        return <Badge variant="outline" className={base}>{status}</Badge>;
    }
  };

  const getInitials = (name: string) => {
    const parts = (name || '').trim().split(/\s+/);
    return parts.length >= 2
      ? `${parts[0].charAt(0)}${parts[parts.length - 1].charAt(0)}`.toUpperCase()
      : (name || 'G').charAt(0).toUpperCase();
  };

  if (loading) return <GuestListSkeletonLoader />;
  if (error) return <div className="p-6 text-center text-destructive">{error}</div>;

  return (
    <div className="space-y-6">
      <ConfirmDialog />

      {summary && (
        <div className="grid grid-cols-2 md:grid-cols-6 gap-4">
          <Card><CardContent className="p-4 text-center"><p className="text-base font-semibold">{summary.total}</p><p className="text-xs text-muted-foreground">Total</p></CardContent></Card>
          <Card><CardContent className="p-4 text-center"><p className="text-base font-semibold text-green-600">{summary.confirmed}</p><p className="text-xs text-muted-foreground">Confirmed</p></CardContent></Card>
          <Card><CardContent className="p-4 text-center"><p className="text-base font-semibold text-yellow-600">{summary.pending}</p><p className="text-xs text-muted-foreground">Pending</p></CardContent></Card>
          <Card><CardContent className="p-4 text-center"><p className="text-base font-semibold text-amber-600">{summary.maybe || 0}</p><p className="text-xs text-muted-foreground">Maybe</p></CardContent></Card>
          <Card><CardContent className="p-4 text-center"><p className="text-base font-semibold text-red-600">{summary.declined}</p><p className="text-xs text-muted-foreground">Declined</p></CardContent></Card>
          <Card><CardContent className="p-4 text-center"><p className="text-base font-semibold text-blue-600">{summary.checked_in}</p><p className="text-xs text-muted-foreground">Checked In</p></CardContent></Card>
        </div>
      )}


      <div className="flex flex-col md:flex-row gap-4">
        <div className="flex-1 flex gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input placeholder="Search guests..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} className="pl-9" />
          </div>
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger className="w-40"><Filter className="w-4 h-4 mr-2" /><SelectValue placeholder={t("filter")} /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Status</SelectItem>
              <SelectItem value="confirmed">Confirmed</SelectItem>
              <SelectItem value="pending">Pending</SelectItem>
              <SelectItem value="declined">Declined</SelectItem>
              <SelectItem value="maybe">Maybe</SelectItem>
            </SelectContent>
          </Select>
        </div>
        {canManage && (
          <Button variant="outline" onClick={() => setImportOpen(true)}>
            <Upload className="w-4 h-4 mr-2" />Import
          </Button>
        )}
        {canManage && (
          <Button onClick={() => setAddDialogOpen(true)}>
            <UserPlus className="w-4 h-4 mr-2" />Add Guest
          </Button>
        )}

      </div>

      <Card>
        <CardContent className="p-0">
          <div className="divide-y">
            {filteredGuests.length === 0 ? (
              <div className="p-6 text-center text-muted-foreground">No guests found</div>
            ) : (
              filteredGuests.map((guest) => (
                <div key={guest.id} className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-muted/50">
                  <div className="flex items-center gap-3 min-w-0">
                    <Avatar className="flex-shrink-0">
                      <AvatarImage src={guest.avatar || undefined} />
                      <AvatarFallback>{getInitials(guest.name)}</AvatarFallback>
                    </Avatar>
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="font-medium truncate">{guest.name || 'Unknown'}</p>
                        {guest.guest_type === 'contributor' && <Badge variant="outline" className="text-xs"><BookUser className="w-3 h-3 mr-1" />Contributor</Badge>}
                        {guest.plus_ones > 0 && <Badge variant="outline" className="text-xs">+{guest.plus_ones}</Badge>}
                      </div>
                      {guest.common_name && (
                        <p className="text-xs text-muted-foreground italic truncate">
                          Card name: {guest.common_name}
                        </p>
                      )}
                      <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                        {guest.email && <span className="flex items-center gap-1 truncate"><Mail className="w-3 h-3 flex-shrink-0" /><span className="truncate max-w-[150px]">{guest.email}</span></span>}
                        {guest.phone && <span className="flex items-center gap-1"><Phone className="w-3 h-3 flex-shrink-0" />{guest.phone}</span>}
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 flex-shrink-0 ml-auto sm:ml-0">
                    {getStatusBadge(guest.rsvp_status)}
                    {guest.checked_in && <Badge className="bg-blue-100 text-blue-800 whitespace-nowrap"><QrCode className="w-3 h-3 mr-1" />Checked In</Badge>}
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild><Button variant="ghost" size="icon"><MoreVertical className="w-4 h-4" /></Button></DropdownMenuTrigger>
                      <DropdownMenuContent align="end" className="w-56">
                        {canManage && (
                          <>
                            <DropdownMenuLabel className="text-[11px] uppercase tracking-wide text-muted-foreground">
                              Set RSVP
                            </DropdownMenuLabel>
                            <DropdownMenuSub>
                              <DropdownMenuSubTrigger>
                                <CheckCircle className="w-4 h-4 mr-2" />
                                Update RSVP status
                              </DropdownMenuSubTrigger>
                              <DropdownMenuSubContent className="w-48">
                                <DropdownMenuItem
                                  disabled={guest.rsvp_status === 'confirmed'}
                                  onClick={() => handleUpdateRsvp(guest, 'confirmed')}
                                >
                                  <CheckCircle className="w-4 h-4 mr-2 text-emerald-600" />
                                  Confirmed
                                </DropdownMenuItem>
                                <DropdownMenuItem
                                  disabled={guest.rsvp_status === 'maybe'}
                                  onClick={() => handleUpdateRsvp(guest, 'maybe')}
                                >
                                  <Clock className="w-4 h-4 mr-2 text-amber-600" />
                                  Maybe
                                </DropdownMenuItem>
                                <DropdownMenuItem
                                  disabled={guest.rsvp_status === 'pending'}
                                  onClick={() => handleUpdateRsvp(guest, 'pending')}
                                >
                                  <Clock className="w-4 h-4 mr-2 text-muted-foreground" />
                                  Pending
                                </DropdownMenuItem>
                                <DropdownMenuItem
                                  disabled={guest.rsvp_status === 'declined'}
                                  onClick={() => handleUpdateRsvp(guest, 'declined')}
                                >
                                  <X className="w-4 h-4 mr-2 text-rose-600" />
                                  Declined
                                </DropdownMenuItem>
                              </DropdownMenuSubContent>
                            </DropdownMenuSub>
                            <DropdownMenuSeparator />
                          </>
                        )}
                        {canSendInvites && (
                          <DropdownMenuItem onClick={() => { setSelectedGuest(guest); setInviteDialogOpen(true); }}>
                            <Send className="w-4 h-4 mr-2" />{guest.invitation_sent ? 'Resend Invitation' : 'Send Invitation'}
                          </DropdownMenuItem>
                        )}
                         {canCheckin && !guest.checked_in && guest.rsvp_status === 'confirmed' && (
                          <DropdownMenuItem onClick={() => handleCheckin(guest.id)}><CheckCircle className="w-4 h-4 mr-2" />Check In</DropdownMenuItem>
                         )}
                         {canManage && (
                           <>
                             <DropdownMenuSeparator />
                             <DropdownMenuItem className="text-destructive" onClick={() => handleDeleteGuest(guest.id)}>
                               <Trash className="w-4 h-4 mr-2" />Remove
                             </DropdownMenuItem>
                           </>
                         )}
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </div>
                </div>
              ))
            )}
          </div>
        </CardContent>
      </Card>

      {/* Add Guest Dialog */}
      <Dialog open={addDialogOpen} onOpenChange={(open) => { setAddDialogOpen(open); if (!open) resetDialog(); }}>
        <DialogContent>
          <DialogHeader><DialogTitle>{t("add_guest")}</DialogTitle></DialogHeader>
          <div className="space-y-4 py-4">
            <Tabs value={guestSourceTab} onValueChange={(v) => { setGuestSourceTab(v); resetDialog(); }}>
              <TabsList className="w-full">
                <TabsTrigger value="user" className="flex-1"><UserPlus className="w-4 h-4 mr-1" />Nuru User</TabsTrigger>
                <TabsTrigger value="contributor" className="flex-1"><BookUser className="w-4 h-4 mr-1" />Contributor</TabsTrigger>
              </TabsList>
            </Tabs>

            {guestSourceTab === 'user' ? (
              <div className="space-y-2">
                <Label>Search User *</Label>
                {selectedUser ? (
                  <div className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg">
                    <Avatar className="w-8 h-8">
                      <AvatarImage src={selectedUser.avatar || undefined} />
                      <AvatarFallback>{selectedUser.first_name?.charAt(0)}{selectedUser.last_name?.charAt(0)}</AvatarFallback>
                    </Avatar>
                    <div className="flex-1">
                      <p className="text-sm font-medium">{selectedUser.first_name} {selectedUser.last_name}</p>
                      <p className="text-xs text-muted-foreground">{selectedUser.email}</p>
                    </div>
                    <Button variant="ghost" size="sm" onClick={() => setSelectedUser(null)}>Change</Button>
                  </div>
                ) : (
                  <UserSearchInput onSelect={setSelectedUser} />
                )}
              </div>
            ) : (
              <div className="space-y-2">
                <Label>Search Contributor *</Label>
                {selectedContributor ? (
                  <div className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg">
                    <Avatar className="w-8 h-8">
                      <AvatarFallback className="text-xs">{getInitials(selectedContributor.name)}</AvatarFallback>
                    </Avatar>
                    <div className="flex-1">
                      <p className="text-sm font-medium">{selectedContributor.name}</p>
                      <p className="text-xs text-muted-foreground">{selectedContributor.phone || selectedContributor.email || 'No contact'}</p>
                    </div>
                    <Button variant="ghost" size="sm" onClick={() => setSelectedContributor(null)}>Change</Button>
                  </div>
                ) : (
                  <ContributorSearchInput onSelect={setSelectedContributor} />
                )}
              </div>
            )}

            <div className="space-y-2">
              <Label>Card display name (optional)</Label>
              <Input
                value={newGuest.common_name}
                onChange={(e) => setNewGuest(prev => ({ ...prev, common_name: e.target.value }))}
                placeholder='e.g. "Mr & Mrs Doe"'
                maxLength={255}
              />
              <p className="text-xs text-muted-foreground">
                Used on invitation cards instead of the legal name. Leave blank to use the full name.
              </p>
            </div>
            <div className="space-y-2">
              <Label>Dietary Requirements</Label>
              <Input value={newGuest.dietary_requirements} onChange={(e) => setNewGuest(prev => ({ ...prev, dietary_requirements: e.target.value }))} placeholder="Vegetarian, halal, allergies..." />
            </div>
            <div className="space-y-2">
              <Label>Notes</Label>
              <Textarea value={newGuest.notes} onChange={(e) => setNewGuest(prev => ({ ...prev, notes: e.target.value }))} placeholder="Additional notes..." rows={2} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAddDialogOpen(false)}>Cancel</Button>
            <Button onClick={handleAddGuest} disabled={isSubmitting}>
              {isSubmitting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Adding...</> : 'Add Guest'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Send Invitation Dialog */}
      <Dialog open={inviteDialogOpen} onOpenChange={setInviteDialogOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Send Invitation</DialogTitle></DialogHeader>
          <div className="py-4">
            <p className="text-muted-foreground mb-4">
              How would you like to send the invitation to <strong>{selectedGuest?.name}</strong>?
            </p>
            <div className="grid gap-3">
              {selectedGuest?.email && (
                <Button variant="outline" className="justify-start" onClick={() => handleSendInvitation('email')} disabled={sendingMethod !== null}>
                  {sendingMethod === 'email' ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Mail className="w-4 h-4 mr-2" />}Send via Email
                </Button>
              )}
              {selectedGuest?.phone && (
                <>
                  <Button variant="outline" className="justify-start" onClick={() => handleSendInvitation('sms')} disabled={sendingMethod !== null}>
                    {sendingMethod === 'sms' ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Phone className="w-4 h-4 mr-2" />}Send via SMS
                  </Button>
                  <Button variant="outline" className="justify-start" onClick={() => handleSendInvitation('whatsapp_text')} disabled={sendingMethod !== null}>
                    {sendingMethod === 'whatsapp' ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Send className="w-4 h-4 mr-2" />}Send via WhatsApp (text)
                  </Button>
                  <Button variant="outline" className="justify-start" onClick={handleSendInvitationCard} disabled={sendingMethod !== null}>
                    {sendingMethod === 'card' ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <ImageIcon className="w-4 h-4 mr-2" />}Send Invitation Card (WhatsApp image)
                  </Button>
                </>
              )}
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <MemberImportDialog
        eventId={eventId}
        mode="guests"
        open={importOpen}
        onClose={() => setImportOpen(false)}
        onCompleted={() => refetch()}
      />

    </div>

  );
};

export default EventGuestList;
