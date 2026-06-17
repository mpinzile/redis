import { useEffect, useState, useCallback } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { CheckCircle, XCircle, Clock, Package } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { FormattedNumberInput } from '@/components/ui/formatted-number-input';
import CalendarIcon from '@/assets/icons/calendar-icon.svg';
import { eventsApi } from '@/lib/api/events';
import { useCurrency } from '@/hooks/useCurrency';
import { toast } from 'sonner';
import { showCaughtError } from '@/lib/api';

interface SponsorReq {
  id: string;
  status: 'pending' | 'accepted' | 'declined';
  message?: string | null;
  contribution_amount?: number | null;
  created_at?: string;
  responded_at?: string | null;
  service?: { id: string; title: string; image?: string | null } | null;
  event?: { id: string; title: string; start_date?: string | null } | null;
}

const Skel = () => (
  <div className="space-y-3">
    {[1, 2, 3].map((i) => (
      <Card key={i}>
        <CardContent className="p-4 flex gap-4">
          <Skeleton className="w-14 h-14 rounded-xl" />
          <div className="flex-1 space-y-2">
            <Skeleton className="h-4 w-48" />
            <Skeleton className="h-3 w-32" />
            <Skeleton className="h-3 w-24" />
          </div>
          <Skeleton className="h-7 w-20 rounded-full" />
        </CardContent>
      </Card>
    ))}
  </div>
);

const StatusBadge = ({ status }: { status: string }) => {
  switch (status) {
    case 'pending':
      return (
        <Badge className="bg-yellow-100 text-yellow-800 hover:bg-yellow-100">
          <Clock className="w-3 h-3 mr-1" />Pending
        </Badge>
      );
    case 'accepted':
      return (
        <Badge className="bg-green-100 text-green-800 hover:bg-green-100">
          <CheckCircle className="w-3 h-3 mr-1" />Accepted
        </Badge>
      );
    case 'declined':
      return (
        <Badge className="bg-red-100 text-red-800 hover:bg-red-100">
          <XCircle className="w-3 h-3 mr-1" />Declined
        </Badge>
      );
    default:
      return <Badge variant="outline">{status}</Badge>;
  }
};

const SponsorRequestsTab = () => {
  const { format: formatPrice } = useCurrency();
  const [requests, setRequests] = useState<SponsorReq[]>([]);
  const [loading, setLoading] = useState(true);
  const [pendingCount, setPendingCount] = useState(0);

  const [dialogOpen, setDialogOpen] = useState(false);
  const [selected, setSelected] = useState<SponsorReq | null>(null);
  const [action, setAction] = useState<'accept' | 'decline'>('accept');
  const [note, setNote] = useState('');
  const [amount, setAmount] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await eventsApi.getMySponsorRequests();
      if (res.success) {
        setRequests(res.data?.items || []);
        setPendingCount(res.data?.pending_count || 0);
      }
    } catch (err: any) {
      showCaughtError(err, 'Failed to load sponsor requests');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const openRespond = (req: SponsorReq, act: 'accept' | 'decline') => {
    setSelected(req);
    setAction(act);
    setNote('');
    setAmount(req.contribution_amount ? String(req.contribution_amount) : '');
    setDialogOpen(true);
  };

  const submit = async () => {
    if (!selected) return;
    setSubmitting(true);
    try {
      await eventsApi.respondToSponsorRequest(selected.id, {
        action,
        response_note: note.trim() || undefined,
        contribution_amount:
          action === 'accept' && amount ? parseFloat(amount) : undefined,
      });
      toast.success(
        action === 'accept'
          ? 'Sponsorship accepted'
          : 'Sponsorship declined'
      );
      setDialogOpen(false);
      setSelected(null);
      await load();
    } catch (err: any) {
      showCaughtError(err, 'Failed to respond');
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) return <Skel />;

  if (requests.length === 0) {
    return (
      <Card>
        <CardContent className="p-10 text-center">
          <div className="mx-auto w-14 h-14 rounded-full bg-muted flex items-center justify-center mb-4">
            <Package className="w-6 h-6 text-muted-foreground" />
          </div>
          <h3 className="font-semibold mb-1">No sponsorship requests</h3>
          <p className="text-sm text-muted-foreground">
            When organizers invite your services as event sponsors, the
            requests will appear here.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {pendingCount > 0 && (
        <div className="rounded-2xl border border-border bg-muted/30 px-4 py-3 text-sm">
          You have <span className="font-semibold">{pendingCount}</span> pending
          sponsorship {pendingCount === 1 ? 'request' : 'requests'}.
        </div>
      )}

      <div className="space-y-3">
        {requests.map((r) => (
          <Card key={r.id} className="overflow-hidden">
            <CardContent className="p-4">
              <div className="flex flex-col md:flex-row gap-4 md:items-center">
                <div className="flex items-center gap-3 flex-1 min-w-0">
                  <Avatar className="w-14 h-14 rounded-xl">
                    <AvatarImage src={r.service?.image || undefined} />
                    <AvatarFallback className="rounded-xl">
                      {(r.service?.title || 'S').slice(0, 2).toUpperCase()}
                    </AvatarFallback>
                  </Avatar>
                  <div className="min-w-0 flex-1">
                    <h3 className="font-semibold truncate">
                      {r.service?.title || 'Service'}
                    </h3>
                    <p className="text-sm text-muted-foreground truncate">
                      Invited to sponsor:{' '}
                      <span className="font-medium text-foreground">
                        {r.event?.title || 'Event'}
                      </span>
                    </p>
                    <div className="flex flex-wrap gap-3 mt-1.5 text-xs text-muted-foreground">
                      {r.event?.start_date && (
                        <span className="flex items-center gap-1">
                          <img
                            src={CalendarIcon}
                            alt=""
                            className="w-3.5 h-3.5"
                          />
                          {new Date(r.event.start_date).toLocaleDateString()}
                        </span>
                      )}
                      {r.contribution_amount != null && (
                        <span>
                          Suggested:{' '}
                          <span className="font-semibold text-foreground">
                            {formatPrice(Number(r.contribution_amount))}
                          </span>
                        </span>
                      )}
                    </div>
                  </div>
                </div>

                <div className="flex flex-col items-end gap-3">
                  <StatusBadge status={r.status} />
                  {r.status === 'pending' && (
                    <div className="flex gap-2">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => openRespond(r, 'decline')}
                      >
                        Decline
                      </Button>
                      <Button
                        size="sm"
                        onClick={() => openRespond(r, 'accept')}
                      >
                        Accept
                      </Button>
                    </div>
                  )}
                </div>
              </div>

              {r.message && (
                <div className="mt-3 pt-3 border-t text-sm text-muted-foreground">
                  <span className="font-medium text-foreground">Message: </span>
                  {r.message}
                </div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {action === 'accept'
                ? 'Accept sponsorship'
                : 'Decline sponsorship'}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            {selected && (
              <div className="rounded-xl bg-muted/40 p-3 text-sm">
                <div className="font-semibold">{selected.service?.title}</div>
                <div className="text-muted-foreground">
                  for {selected.event?.title}
                </div>
              </div>
            )}
            {action === 'accept' && (
              <div className="space-y-2">
                <Label htmlFor="amount">Confirmed contribution (TZS)</Label>
                <FormattedNumberInput
                  id="amount"
                  value={amount}
                  onChange={(v) => setAmount(v)}
                  placeholder="e.g., 500,000"
                  autoComplete="off"
                />
                <p className="text-xs text-muted-foreground">
                  Optional. Adjust if different from the suggested amount.
                </p>
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="note">
                {action === 'accept' ? 'Message to organizer' : 'Reason'}
              </Label>
              <Textarea
                id="note"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                rows={3}
                placeholder={
                  action === 'accept'
                    ? "Glad to be part of your event..."
                    : 'Thanks for the invitation, however...'
                }
                autoComplete="off"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              Cancel
            </Button>
            <Button
              variant={action === 'accept' ? 'default' : 'destructive'}
              onClick={submit}
              disabled={submitting}
            >
              {submitting
                ? 'Sending...'
                : action === 'accept'
                ? 'Accept'
                : 'Decline'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default SponsorRequestsTab;
