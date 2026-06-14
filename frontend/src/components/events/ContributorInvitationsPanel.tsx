import { useEffect, useMemo, useState } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Loader2, Search, Send, UserPlus, CheckCircle2, Clock, Mail, MessageSquare } from 'lucide-react';
import { toast } from 'sonner';
import { showCaughtError } from '@/lib/api';
import { eventsApi } from '@/lib/api/events';
import type { EventGuest } from '@/lib/api/types';
import type { EventContributorSummary } from '@/lib/api/contributors';
import { formatDateMedium } from '@/utils/formatDate';

type Method = 'whatsapp' | 'sms' | 'email';

interface Props {
  eventId: string;
  eventContributors: EventContributorSummary[];
  /** Refetch contributor list (when add-as-guest mutates them). */
  onChanged?: () => void;
}

const normalizePhone = (p?: string | null) =>
  (p || '').replace(/\D+/g, '').replace(/^0+/, '').slice(-9);

// Module-level cache so toggling the panel doesn't refetch from scratch
// and so initial mount can paint correct counts immediately.
const _guestsCache: Record<string, { guests: EventGuest[]; loadedAt: number }> = {};

const ContributorInvitationsPanel = ({ eventId, eventContributors, onChanged }: Props) => {
  const cached = _guestsCache[eventId];
  const [guests, setGuests] = useState<EventGuest[]>(cached?.guests || []);
  const [loading, setLoading] = useState(!cached);
  const [hasLoaded, setHasLoaded] = useState(!!cached);
  const [search, setSearch] = useState('');
  const [tab, setTab] = useState<'not_invited' | 'invited'>('not_invited');
  const [selected, setSelected] = useState<string[]>([]);
  const [method, setMethod] = useState<Method>('whatsapp');
  const [sendNow, setSendNow] = useState(true);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [working, setWorking] = useState(false);
  const [resendingId, setResendingId] = useState<string | null>(null);

  const fetchGuests = async (silent = false) => {
    if (!silent && !_guestsCache[eventId]) setLoading(true);
    try {
      const res = await eventsApi.getGuests(eventId, { limit: 500 });
      if (res.success) {
        const next = res.data.guests || [];
        _guestsCache[eventId] = { guests: next, loadedAt: Date.now() };
        setGuests(next);
        setHasLoaded(true);
      }
    } catch (err: any) {
      if (!silent) showCaughtError(err, 'Unable to load guest list');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    // Paint cached counts instantly; refresh quietly in the background.
    fetchGuests(!!_guestsCache[eventId]);
  }, [eventId]);


  /** Build a quick lookup of invited contributors by contributor_id + phone. */
  const guestIndex = useMemo(() => {
    const byContribId = new Map<string, EventGuest>();
    const byPhone = new Map<string, EventGuest>();
    for (const g of guests) {
      if (g.contributor_id) byContribId.set(g.contributor_id, g);
      const np = normalizePhone(g.phone);
      if (np) byPhone.set(np, g);
    }
    return { byContribId, byPhone };
  }, [guests]);

  const rows = useMemo(() => {
    return eventContributors.map((ec) => {
      const c = ec.contributor;
      const name = c?.name || 'Contributor';
      const phone = c?.phone || '';
      const np = normalizePhone(phone);
      const guest =
        guestIndex.byContribId.get(ec.contributor_id) ||
        (np ? guestIndex.byPhone.get(np) : undefined);
      return { ec, name, phone, email: c?.email || '', guest };
    });
  }, [eventContributors, guestIndex]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    const base = tab === 'invited' ? rows.filter(r => r.guest) : rows.filter(r => !r.guest);
    if (!q) return base;
    return base.filter(r =>
      r.name.toLowerCase().includes(q) ||
      r.phone.toLowerCase().includes(q) ||
      r.email.toLowerCase().includes(q),
    );
  }, [rows, tab, search]);

  const notInvitedCount = rows.filter(r => !r.guest).length;
  const invitedCount = rows.filter(r => r.guest).length;

  const allFilteredIds = filtered.map(r => r.ec.contributor_id);
  const allSelected = allFilteredIds.length > 0 && allFilteredIds.every(id => selected.includes(id));

  const toggleAll = () => {
    if (allSelected) setSelected(prev => prev.filter(id => !allFilteredIds.includes(id)));
    else setSelected(prev => Array.from(new Set([...prev, ...allFilteredIds])));
  };

  const toggleOne = (id: string) =>
    setSelected(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);

  useEffect(() => { setSelected([]); }, [tab]);

  const handleAddAndInvite = async () => {
    if (selected.length === 0) return;
    setWorking(true);
    try {
      const addRes = await eventsApi.addContributorsAsGuests(eventId, {
        contributor_ids: selected,
        send_sms: false,
      });
      if (!addRes.success) throw new Error('Failed to add as guests');
      const added = addRes.data.added || 0;
      const skipped = addRes.data.skipped || 0;

      // Refresh guest list so we can target the new guest_ids for invitations.
      await fetchGuests();
      onChanged?.();

      if (sendNow) {
        const fresh = await eventsApi.getGuests(eventId, { limit: 500 });
        const freshGuests = fresh.success ? fresh.data.guests : guests;
        const targetGuestIds = freshGuests
          .filter(g => g.contributor_id && selected.includes(g.contributor_id))
          .map(g => g.id);

        if (targetGuestIds.length > 0) {
          const sendRes = await eventsApi.sendBulkInvitations(eventId, {
            method,
            guest_ids: targetGuestIds,
          });
          if (sendRes.success) {
            toast.success(
              `Added ${added}${skipped ? ` (${skipped} already on list)` : ''}. Invitations sent: ${sendRes.data.sent_count}/${sendRes.data.total_selected}.`,
            );
          } else {
            toast.success(`Added ${added} guest${added === 1 ? '' : 's'}.`);
          }
        } else {
          toast.success(`Added ${added} guest${added === 1 ? '' : 's'}.`);
        }
      } else {
        toast.success(`Added ${added} guest${added === 1 ? '' : 's'}${skipped ? ` (${skipped} already on list)` : ''}.`);
      }

      setSelected([]);
      setConfirmOpen(false);
      setTab('invited');
    } catch (err: any) {
      showCaughtError(err, 'Failed to add contributors as guests');
    } finally {
      setWorking(false);
    }
  };

  const handleResend = async (guestId: string) => {
    setResendingId(guestId);
    try {
      const res = await eventsApi.resendInvitation(eventId, guestId, { method });
      if (res.success) {
        toast.success(`Invitation re-sent via ${method}.`);
        fetchGuests();
      }
    } catch (err: any) {
      showCaughtError(err, 'Failed to resend invitation');
    } finally {
      setResendingId(null);
    }
  };

  return (
    <Card>
      <CardContent className="p-4 sm:p-5 space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div className="min-w-0">
            <h3 className="text-base sm:text-lg font-semibold flex items-center gap-2">
              <Send className="w-4 h-4 text-primary" />
              Invitations
            </h3>
            <p className="text-xs text-muted-foreground mt-0.5">
              Add contributors to the guest list and send invitations in one place.
            </p>
          </div>
          <div className="flex items-center gap-2 text-xs">
            {hasLoaded ? (
              <>
                <Badge variant="secondary" className="gap-1"><CheckCircle2 className="w-3 h-3" />{invitedCount} invited</Badge>
                <Badge variant="outline" className="gap-1"><Clock className="w-3 h-3" />{notInvitedCount} pending</Badge>
              </>
            ) : (
              <span className="text-muted-foreground">Loading invitations…</span>
            )}
          </div>
        </div>

        <Tabs value={tab} onValueChange={(v) => setTab(v as any)}>
          <TabsList className="w-full">
            <TabsTrigger value="not_invited" className="flex-1">
              Not invited{hasLoaded && <span className="ml-1 text-muted-foreground">({notInvitedCount})</span>}
            </TabsTrigger>
            <TabsTrigger value="invited" className="flex-1">
              Invited{hasLoaded && <span className="ml-1 text-muted-foreground">({invitedCount})</span>}
            </TabsTrigger>
          </TabsList>


          <div className="flex flex-col sm:flex-row gap-2 mt-3">
            <div className="relative flex-1">
              <Search className="w-4 h-4 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <Input
                placeholder="Search by name, phone or email"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="pl-9"
                autoComplete="off"
              />
            </div>
            <Select value={method} onValueChange={(v) => setMethod(v as Method)}>
              <SelectTrigger
                className="w-full sm:w-48"
                title="Channel used when sending or resending invitations"
              >
                <span className="text-xs text-muted-foreground mr-2">Send via</span>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="whatsapp"><span className="inline-flex items-center gap-2"><MessageSquare className="w-3.5 h-3.5" />WhatsApp</span></SelectItem>
                <SelectItem value="sms"><span className="inline-flex items-center gap-2"><MessageSquare className="w-3.5 h-3.5" />SMS</span></SelectItem>
                <SelectItem value="email"><span className="inline-flex items-center gap-2"><Mail className="w-3.5 h-3.5" />Email</span></SelectItem>
              </SelectContent>
            </Select>
          </div>

          <TabsContent value="not_invited" className="mt-3 space-y-3">
            {filtered.length > 0 && (
              <div className="flex items-center justify-between gap-2 p-2 rounded-lg border bg-muted/30">
                <label className="flex items-center gap-2 text-sm cursor-pointer">
                  <Checkbox checked={allSelected} onCheckedChange={toggleAll} />
                  <span>{allSelected ? 'Deselect all' : 'Select all'} ({filtered.length})</span>
                </label>
                <div className="flex items-center gap-2">
                  <label className="hidden sm:flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer">
                    <Checkbox checked={sendNow} onCheckedChange={(v) => setSendNow(v === true)} />
                    Send invitation now
                  </label>
                  <Button
                    size="sm"
                    disabled={selected.length === 0}
                    onClick={() => setConfirmOpen(true)}
                  >
                    <UserPlus className="w-4 h-4 mr-1.5" />
                    Invite {selected.length || ''}
                  </Button>
                </div>
              </div>
            )}

            {loading ? (
              <div className="flex items-center justify-center py-10 text-sm text-muted-foreground">
                <Loader2 className="w-4 h-4 animate-spin mr-2" /> Loading...
              </div>
            ) : filtered.length === 0 ? (
              <div className="text-center py-10 text-sm text-muted-foreground">
                {notInvitedCount === 0
                  ? 'Every contributor is already on the guest list.'
                  : 'No contributors match your search.'}
              </div>
            ) : (
              <div className="divide-y border rounded-lg bg-background">
                {filtered.map(({ ec, name, phone, email }) => {
                  const id = ec.contributor_id;
                  const checked = selected.includes(id);
                  return (
                    <label
                      key={ec.id}
                      className="flex items-center gap-3 p-3 cursor-pointer hover:bg-muted/40 transition-colors"
                    >
                      <Checkbox checked={checked} onCheckedChange={() => toggleOne(id)} />
                      <div className="flex-1 min-w-0">
                        <p className="font-medium text-sm truncate">{name}</p>
                        <p className="text-xs text-muted-foreground truncate">
                          {phone || email || 'No contact'}
                        </p>
                      </div>
                    </label>
                  );
                })}
              </div>
            )}
          </TabsContent>

          <TabsContent value="invited" className="mt-3 space-y-3">
            {loading ? (
              <div className="flex items-center justify-center py-10 text-sm text-muted-foreground">
                <Loader2 className="w-4 h-4 animate-spin mr-2" /> Loading...
              </div>
            ) : filtered.length === 0 ? (
              <div className="text-center py-10 text-sm text-muted-foreground">
                {invitedCount === 0
                  ? 'No contributors have been added as guests yet.'
                  : 'No invited contributors match your search.'}
              </div>
            ) : (
              <div className="divide-y border rounded-lg bg-background">
                {filtered.map(({ ec, name, phone, guest }) => (
                  <div key={ec.id} className="flex items-center gap-3 p-3">
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-sm truncate">{name}</p>
                      <p className="text-xs text-muted-foreground truncate">{phone}</p>
                      <div className="flex flex-wrap items-center gap-1.5 mt-1">
                        {guest?.invitation_sent ? (
                          <Badge variant="secondary" className="text-[10px] gap-1">
                            <CheckCircle2 className="w-3 h-3" />
                            Sent {guest?.invitation_sent_at ? `· ${formatDateMedium(guest.invitation_sent_at)}` : ''}
                            {guest?.invitation_method ? ` - ${guest.invitation_method}` : ''}
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="text-[10px] gap-1">
                            <Clock className="w-3 h-3" /> Added, not sent
                          </Badge>
                        )}
                        {guest?.rsvp_status && guest.rsvp_status !== 'pending' && (
                          <Badge variant="outline" className="text-[10px] capitalize">
                            RSVP: {guest.rsvp_status}
                          </Badge>
                        )}
                      </div>
                    </div>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={!guest || resendingId === guest.id}
                      onClick={() => guest && handleResend(guest.id)}
                    >
                      {resendingId === guest?.id ? (
                        <Loader2 className="w-4 h-4 animate-spin" />
                      ) : (
                        <>
                          <Send className="w-4 h-4 mr-1.5" />
                          {guest?.invitation_sent ? 'Resend' : 'Send'}
                        </>
                      )}
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </TabsContent>
        </Tabs>
      </CardContent>

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Invite {selected.length} contributor{selected.length === 1 ? '' : 's'}</DialogTitle>
          </DialogHeader>
          <div className="space-y-3 text-sm">
            <p className="text-muted-foreground">
              These contributors will be added to your guest list. Duplicates are skipped automatically.
            </p>
            <label className="flex items-start gap-2 p-3 rounded-lg border bg-muted/20 cursor-pointer">
              <Checkbox checked={sendNow} onCheckedChange={(v) => setSendNow(v === true)} className="mt-0.5" />
              <div>
                <p className="font-medium">Send invitation now via {method}</p>
                <p className="text-xs text-muted-foreground">
                  {sendNow
                    ? `Each new guest will receive an invitation through ${method}.`
                    : 'They will only be added to the guest list. You can send invitations later.'}
                </p>
              </div>
            </label>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConfirmOpen(false)} disabled={working}>Cancel</Button>
            <Button onClick={handleAddAndInvite} disabled={working}>
              {working ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Working...</> : <><UserPlus className="w-4 h-4 mr-2" />Confirm</>}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
};

export default ContributorInvitationsPanel;
