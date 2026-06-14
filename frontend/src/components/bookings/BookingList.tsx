import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { 
  Clock,
  User,
  MessageSquare,
  CheckCircle,
  XCircle,
  Eye,
  MoreVertical,
  Filter,
} from 'lucide-react';
import CalendarIcon from '@/assets/icons/calendar-icon.svg';
import LocationIcon from '@/assets/icons/location-icon.svg';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { FormattedNumberInput } from '@/components/ui/formatted-number-input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent } from '@/components/ui/tabs';
import { PillTabsNav } from '@/components/ui/pill-tabs';
import { useMyBookings, useIncomingBookings } from '@/data/useBookings';
import CancelBookingDialog from './CancelBookingDialog';
import SponsorRequestsTab from './SponsorRequestsTab';
import { toast } from 'sonner';
import { showCaughtError } from '@/lib/api';
import { useCurrency } from '@/hooks/useCurrency';
import type { BookingRequest } from '@/lib/api/types';
import { Skeleton } from '@/components/ui/skeleton';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import SearchHeader from '@/components/ui/search-header';

const BookingListSkeleton = () => (
  <div className="space-y-4">
    <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
      {[1, 2, 3, 4, 5].map(i => (
        <Card key={i}>
          <CardContent className="p-4 text-center space-y-2">
            <Skeleton className="h-8 w-12 mx-auto" />
            <Skeleton className="h-4 w-16 mx-auto" />
          </CardContent>
        </Card>
      ))}
    </div>
    <div className="flex gap-4">
      <Skeleton className="h-10 flex-1" />
      <Skeleton className="h-10 w-40" />
    </div>
    {[1, 2, 3].map(i => (
      <Card key={i}>
        <CardContent className="p-4">
          <div className="flex gap-4">
            <Skeleton className="w-16 h-16 rounded-lg" />
            <div className="flex-1 space-y-2">
              <Skeleton className="h-5 w-48" />
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-4 w-24" />
            </div>
            <Skeleton className="h-6 w-20" />
          </div>
        </CardContent>
      </Card>
    ))}
  </div>
);

const BookingList = () => {
  const { t } = useLanguage();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<'my' | 'incoming' | 'sponsorships'>('my');
  
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Bookings</h1>
        <p className="text-muted-foreground mt-1">Manage your service bookings</p>
      </div>

      <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as any)}>
        <PillTabsNav
          activeTab={activeTab}
          onTabChange={(v) => setActiveTab(v as any)}
          tabs={[
            { value: 'my', label: 'My Bookings' },
            { value: 'incoming', label: 'Incoming Requests' },
            { value: 'sponsorships', label: 'Sponsorships' },
          ]}
        />
        <TabsContent value="my" className="mt-2">
          <MyBookingsTab />
        </TabsContent>
        <TabsContent value="incoming" className="mt-2">
          <IncomingBookingsTab />
        </TabsContent>
        <TabsContent value="sponsorships" className="mt-2">
          <SponsorRequestsTab />
        </TabsContent>
      </Tabs>
    </div>
  );
};

const MyBookingsTab = () => {
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState('accepted');
  const { bookings, summary, loading, error, cancelBooking, refetch } = useMyBookings();
  const [cancelDialogOpen, setCancelDialogOpen] = useState(false);
  const [selectedBooking, setSelectedBooking] = useState<BookingRequest | null>(null);

  // Re-fetch on search/status change (server-side ?search=)
  useEffect(() => {
    refetch({
      ...(searchQuery ? { search: searchQuery } : {}),
      ...(statusFilter !== 'all' ? { status: statusFilter as any } : {}),
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchQuery, statusFilter]);

  const handleCancelConfirm = async (reason: string) => {
    if (!selectedBooking) return;
    try {
      await cancelBooking(selectedBooking.id, reason);
      toast.success('Booking cancelled · refund processed per policy');
      setSelectedBooking(null);
    } catch (err: any) {
      showCaughtError(err, 'Failed to cancel booking');
      throw err;
    }
  };

  const filteredBookings = bookings;

  if (loading) {
    return <BookingListSkeleton />;
  }

  if (error) {
    return <div className="text-center py-8 text-destructive">{error}</div>;
  }

  return (
    <div className="space-y-4">
      {/* Summary */}
      {summary && (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold">{summary.total}</p>
              <p className="text-sm text-muted-foreground">Total</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold text-yellow-600">{summary.pending}</p>
              <p className="text-sm text-muted-foreground">Pending</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold text-green-600">{summary.accepted}</p>
              <p className="text-sm text-muted-foreground">Accepted</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold text-blue-600">{summary.completed}</p>
              <p className="text-sm text-muted-foreground">Completed</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold text-red-600">{summary.cancelled}</p>
              <p className="text-sm text-muted-foreground">Cancelled</p>
            </CardContent>
          </Card>
        </div>
      )}

      {/* Filters */}
      <div className="flex gap-2 items-center">
        <div className="flex-1 flex items-center">
          <SearchHeader value={searchQuery} onChange={setSearchQuery} placeholder="Search bookings…" alwaysOpen />
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-40">
            <Filter className="w-4 h-4 mr-2" />
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
            <SelectItem value="accepted">Accepted</SelectItem>
            <SelectItem value="rejected">Rejected</SelectItem>
            <SelectItem value="completed">Completed</SelectItem>
            <SelectItem value="cancelled">Cancelled</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Booking List */}
      <div className="space-y-4">
        {filteredBookings.length === 0 ? (
          <Card>
            <CardContent className="p-8 text-center">
              <img src={CalendarIcon} alt="Calendar" className="w-12 h-12 mx-auto mb-4" />
              <h3 className="font-medium mb-2">No bookings yet</h3>
              <p className="text-muted-foreground text-sm">
                Browse services and make your first booking
              </p>
            </CardContent>
          </Card>
        ) : (
          filteredBookings.map((booking) => (
            <BookingCard 
              key={booking.id} 
              booking={booking} 
              onCancel={() => { setSelectedBooking(booking); setCancelDialogOpen(true); }}
              onView={() => navigate(`/bookings/${booking.id}`)}
              isVendor={false}
            />
          ))
        )}
      </div>

      {/* Cancel Dialog (Phase 1.2 — refund preview before confirm) */}
      <CancelBookingDialog
        open={cancelDialogOpen}
        onOpenChange={setCancelDialogOpen}
        bookingId={selectedBooking?.id ?? null}
        cancellingParty="organiser"
        onConfirm={handleCancelConfirm}
      />
    </div>
  );
};

const IncomingBookingsTab = () => {
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState('pending');
  const { bookings, summary, loading, error, respondToBooking, completeBooking, refetch } = useIncomingBookings();
  const [responseDialogOpen, setResponseDialogOpen] = useState(false);
  const [selectedBooking, setSelectedBooking] = useState<BookingRequest | null>(null);
  const [responseType, setResponseType] = useState<'accept' | 'reject'>('accept');
  const [responseData, setResponseData] = useState({
    message: '',
    quoted_price: '',
    deposit_required: '',
    reason: ''
  });
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Re-fetch on search/status change (server-side ?search=)
  useEffect(() => {
    refetch({
      ...(searchQuery ? { search: searchQuery } : {}),
      ...(statusFilter !== 'all' ? { status: statusFilter as any } : {}),
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchQuery, statusFilter]);

  const handleRespond = async () => {
    if (!selectedBooking) return;
    if (!responseData.message.trim()) {
      toast.error('Please provide a message');
      return;
    }

    setIsSubmitting(true);
    try {
      await respondToBooking(selectedBooking.id, {
        status: responseType === 'accept' ? 'accepted' : 'rejected',
        message: responseData.message,
        quoted_price: responseData.quoted_price ? parseFloat(responseData.quoted_price) : undefined,
        deposit_required: responseData.deposit_required ? parseFloat(responseData.deposit_required) : undefined,
        reason: responseType === 'reject' ? responseData.reason : undefined
      });
      toast.success(responseType === 'accept' ? 'Booking accepted' : 'Booking rejected');
      setResponseDialogOpen(false);
      setSelectedBooking(null);
      setResponseData({ message: '', quoted_price: '', deposit_required: '', reason: '' });
    } catch (err: any) {
      showCaughtError(err, 'Failed to respond to booking');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleComplete = async (bookingId: string) => {
    try {
      await completeBooking(bookingId);
      toast.success('Booking marked as complete');
    } catch (err: any) {
      showCaughtError(err, 'Failed to complete booking');
    }
  };

  const filteredBookings = bookings;

  if (loading) {
    return <BookingListSkeleton />;
  }

  if (error) {
    return <div className="text-center py-8 text-destructive">{error}</div>;
  }

  return (
    <div className="space-y-4">
      {/* Summary */}
      {summary && (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold">{summary.total}</p>
              <p className="text-sm text-muted-foreground">Total</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold text-yellow-600">{summary.pending}</p>
              <p className="text-sm text-muted-foreground">Pending</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold text-green-600">{summary.accepted}</p>
              <p className="text-sm text-muted-foreground">Accepted</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold text-blue-600">{summary.completed}</p>
              <p className="text-sm text-muted-foreground">Completed</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold text-red-600">{summary.rejected}</p>
              <p className="text-sm text-muted-foreground">Rejected</p>
            </CardContent>
          </Card>
        </div>
      )}

      {/* Filters */}
      <div className="flex gap-2 items-center">
        <div className="flex-1 flex items-center">
          <SearchHeader value={searchQuery} onChange={setSearchQuery} placeholder="Search requests…" alwaysOpen />
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-40">
            <Filter className="w-4 h-4 mr-2" />
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
            <SelectItem value="accepted">Accepted</SelectItem>
            <SelectItem value="rejected">Rejected</SelectItem>
            <SelectItem value="completed">Completed</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Booking List */}
      <div className="space-y-4">
        {filteredBookings.length === 0 ? (
          <Card>
            <CardContent className="p-8 text-center">
              <img src={CalendarIcon} alt="Calendar" className="w-12 h-12 mx-auto mb-4" />
              <h3 className="font-medium mb-2">No booking requests</h3>
              <p className="text-muted-foreground text-sm">
                When clients request your services, they'll appear here
              </p>
            </CardContent>
          </Card>
        ) : (
          filteredBookings.map((booking) => (
            <BookingCard 
              key={booking.id} 
              booking={booking} 
              onAccept={() => { setSelectedBooking(booking); setResponseType('accept'); setResponseDialogOpen(true); }}
              onReject={() => { setSelectedBooking(booking); setResponseType('reject'); setResponseDialogOpen(true); }}
              onComplete={() => handleComplete(booking.id)}
              onView={() => navigate(`/bookings/${booking.id}`)}
              isVendor={true}
            />
          ))
        )}
      </div>

      {/* Response Dialog */}
      <Dialog open={responseDialogOpen} onOpenChange={setResponseDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{responseType === 'accept' ? 'Accept Booking' : 'Reject Booking'}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            {responseType === 'accept' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="quoted-price">Quoted Price (TZS)</Label>
                    <FormattedNumberInput
                      id="quoted-price"
                      value={responseData.quoted_price}
                      onChange={(value) => setResponseData(prev => ({ ...prev, quoted_price: value }))}
                      placeholder="e.g., 500,000"
                      autoComplete="off"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="deposit">Deposit Required (TZS)</Label>
                    <FormattedNumberInput
                      id="deposit"
                      value={responseData.deposit_required}
                      onChange={(value) => setResponseData(prev => ({ ...prev, deposit_required: value }))}
                      placeholder="e.g., 100,000"
                      autoComplete="off"
                    />
                  </div>
                </div>
              </>
            )}
            {responseType === 'reject' && (
              <div className="space-y-2">
                <Label htmlFor="reject-reason">Reason for rejection</Label>
                <Input
                  id="reject-reason"
                  value={responseData.reason}
                  onChange={(e) => setResponseData(prev => ({ ...prev, reason: e.target.value }))}
                  placeholder="e.g., Fully booked on that date"
                />
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="response-message">Message to client *</Label>
              <Textarea
                id="response-message"
                value={responseData.message}
                onChange={(e) => setResponseData(prev => ({ ...prev, message: e.target.value }))}
                placeholder={responseType === 'accept' 
                  ? "Thank you for your booking request! I'm available for your event..."
                  : "Thank you for your interest. Unfortunately..."
                }
                rows={3}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setResponseDialogOpen(false)}>Cancel</Button>
            <Button 
              variant={responseType === 'accept' ? 'default' : 'destructive'}
              onClick={handleRespond} 
              disabled={isSubmitting}
            >
              {isSubmitting ? 'Sending...' : (responseType === 'accept' ? 'Accept' : 'Reject')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

interface BookingCardProps {
  booking: BookingRequest;
  onView: () => void;
  onCancel?: () => void;
  onAccept?: () => void;
  onReject?: () => void;
  onComplete?: () => void;
  isVendor: boolean;
}

const BookingCard = ({ booking, onView, onCancel, onAccept, onReject, onComplete, isVendor }: BookingCardProps) => {
  const { format: formatPrice } = useCurrency();
  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'pending':
        return <Badge className="bg-yellow-100 text-yellow-800"><Clock className="w-3 h-3 mr-1" />Pending</Badge>;
      case 'accepted':
        return <Badge className="bg-green-100 text-green-800"><CheckCircle className="w-3 h-3 mr-1" />Accepted</Badge>;
      case 'rejected':
        return <Badge className="bg-red-100 text-red-800"><XCircle className="w-3 h-3 mr-1" />Rejected</Badge>;
      case 'completed':
        return <Badge className="bg-blue-100 text-blue-800"><CheckCircle className="w-3 h-3 mr-1" />Completed</Badge>;
      case 'cancelled':
        return <Badge variant="outline">Cancelled</Badge>;
      default:
        return <Badge variant="outline">{status}</Badge>;
    }
  };

  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex flex-col md:flex-row gap-4">
          {/* Service/Client Info */}
          <div className="flex items-center gap-4 flex-1">
            <Avatar className="w-12 h-12">
              {isVendor ? (
                <AvatarImage src={booking.client.avatar} />
              ) : (
                <AvatarImage src={booking.service.primary_image} />
              )}
              <AvatarFallback>
                {isVendor 
                  ? booking.client.name.split(/\s+/).map((w: string) => w[0]).join('').slice(0, 2).toUpperCase()
                  : booking.service.title.split(/\s+/).map((w: string) => w[0]).join('').slice(0, 2).toUpperCase()}
              </AvatarFallback>
            </Avatar>
            <div className="flex-1 min-w-0">
              <h3 className="font-semibold truncate">
                {isVendor ? booking.client.name : booking.service.title}
              </h3>
              <p className="text-sm text-muted-foreground truncate">
                {booking.event_name || 'Event Booking'}
              </p>
            </div>
          </div>

          {/* Event Details */}
          <div className="flex flex-wrap gap-4 text-sm text-muted-foreground">
            <div className="flex items-center gap-1">
              <img src={CalendarIcon} alt="Calendar" className="w-4 h-4" />
              <span>{booking.event_date ? new Date(booking.event_date).toLocaleDateString() : 'TBD'}</span>
            </div>
            {booking.location && (
              <div className="flex items-center gap-1">
                <img src={LocationIcon} alt="Location" className="w-4 h-4" />
                <span className="truncate max-w-[150px]">{booking.location}</span>
              </div>
            )}
            {booking.guest_count && (
              <div className="flex items-center gap-1">
                <User className="w-4 h-4" />
                <span>{booking.guest_count} guests</span>
              </div>
            )}
          </div>

          {/* Price & Status */}
          <div className="flex items-center gap-4">
            {(booking.quoted_price || booking.final_price) && (
              <div className="text-right">
                <p className="font-bold text-primary">
                  {formatPrice(booking.final_price || booking.quoted_price || 0)}
                </p>
                {booking.deposit_required && !booking.deposit_paid && (
                  <p className="text-xs text-muted-foreground">
                    Deposit: {formatPrice(booking.deposit_required)}
                  </p>
                )}
              </div>
            )}
            {getStatusBadge(booking.status)}
            
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon">
                  <MoreVertical className="w-4 h-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onClick={onView}>
                  <Eye className="w-4 h-4 mr-2" />View Details
                </DropdownMenuItem>
                {booking.conversation_id && (
                  <DropdownMenuItem>
                    <MessageSquare className="w-4 h-4 mr-2" />Messages
                  </DropdownMenuItem>
                )}
                {isVendor && booking.status === 'pending' && (
                  <>
                    <DropdownMenuItem onClick={onAccept}>
                      <CheckCircle className="w-4 h-4 mr-2" />Accept
                    </DropdownMenuItem>
                    <DropdownMenuItem onClick={onReject} className="text-red-600">
                      <XCircle className="w-4 h-4 mr-2" />Reject
                    </DropdownMenuItem>
                  </>
                )}
                {isVendor && booking.status === 'accepted' && (
                  <DropdownMenuItem onClick={onComplete}>
                    <CheckCircle className="w-4 h-4 mr-2" />Mark Complete
                  </DropdownMenuItem>
                )}
                {!isVendor && booking.status === 'pending' && (
                  <DropdownMenuItem onClick={onCancel} className="text-red-600">
                    <XCircle className="w-4 h-4 mr-2" />Cancel
                  </DropdownMenuItem>
                )}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>

        {/* Message Preview */}
        {booking.message && (
          <div className="mt-4 pt-4 border-t">
            <p className="text-sm text-muted-foreground line-clamp-2">
              <span className="font-medium">Message: </span>{booking.message}
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default BookingList;
