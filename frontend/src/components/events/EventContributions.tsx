import { useState, useRef, useEffect } from 'react';
import readXlsxFile from 'read-excel-file';
import { format } from 'date-fns';
import { FormattedNumberInput } from '@/components/ui/formatted-number-input';
import { WhatsAppStatusBadge } from '@/components/whatsapp/WhatsAppStatusBadge';
import { 
  DollarSign, Plus, Search, Filter, MoreVertical, Edit, Trash, Send, Download, TrendingUp, Users, Clock, Loader2, Eye, ChevronLeft, ChevronRight, UserPlus, Upload, FileSpreadsheet, AlertCircle, CheckCircle2, ShieldCheck, UserCheck, CalendarIcon, Link as LinkIcon, BellRing
} from 'lucide-react';
import ShareContributorLinkDialog from './ShareContributorLinkDialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Checkbox } from '@/components/ui/checkbox';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/utils';
import { useEventContributors } from '@/data/useContributors';
import { invalidateUserContributorsCache } from '@/data/useUserContributors';
import { useContributorSearch } from '@/hooks/useContributorSearch';
import { usePolling } from '@/hooks/usePolling';
import { toast } from 'sonner';
import { useConfirmDialog } from '@/hooks/useConfirmDialog';
import { showCaughtError } from '@/lib/api';
import { useCurrency } from '@/hooks/useCurrency';
import { formatDateMedium } from '@/utils/formatDate';
import ContributionsSkeletonLoader from './ContributionsSkeletonLoader';
import ContributorDetailDialog from './ContributorDetailDialog';
import { generateContributionReportHtml } from '@/utils/generatePdf';
import ReportPreviewDialog from '@/components/ReportPreviewDialog';
import { contributorsApi } from '@/lib/api/contributors';
import { eventsApi } from '@/lib/api/events';
import type { EventContributorSummary } from '@/lib/api/contributors';
import { validateInternationalPhone } from '@/lib/validators/phone';
import { getActiveRegion } from '@/lib/region/host';
import type { EventPermissions } from '@/hooks/useEventPermissions';
import ContributorMessaging from './ContributorMessaging';
import SvgIcon from '@/components/ui/svg-icon';
import ChatIcon from '@/assets/icons/chat-icon.svg';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import ReceivedPaymentsPanel from '@/components/payments/ReceivedPaymentsPanel';
import ContributorInvitationsPanel from './ContributorInvitationsPanel';
import { startTask, updateTask, appendDetail, finishTask } from '@/lib/backgroundTasks/store';
import DismissibleHint from '@/components/background/DismissibleHint';

interface EventContributionsProps {
  eventId: string;
  eventTitle?: string;
  eventBudget?: number;
  eventEndDate?: string;
  /** event.reminder_contact_phone — used as default in bulk reminder dialog */
  reminderContactPhone?: string;
  isCreator?: boolean;
  permissions?: EventPermissions;
}

// EventContributions needs eventBudget for display

const PAYMENT_METHODS = [
  { id: 'cash', name: 'Cash' },
  { id: 'mobile', name: 'Mobile Money' },
  { id: 'bank_transfer', name: 'Bank Transfer' },
  { id: 'card', name: 'Card' },
  { id: 'cheque', name: 'Cheque' },
  { id: 'other', name: 'Other' }
];

const ITEMS_PER_PAGE = 10;

const EventContributions = ({ eventId, eventTitle, eventBudget, eventEndDate, reminderContactPhone, isCreator = true, permissions }: EventContributionsProps) => {
  const { format: formatPrice } = useCurrency();
  const { t } = useLanguage();
  const canManage = permissions?.can_manage_contributions || permissions?.is_creator;
  const canView = permissions?.can_view_contributions || permissions?.is_creator;
  // New contributor-based hooks
  const { 
    eventContributors, summary: ecSummary, loading: ecLoading, error: ecError, 
    refetch: refetchEC, addToEvent, updateEventContributor, removeFromEvent, recordPayment, getPaymentHistory 
  } = useEventContributors(eventId);

  
  const { confirm, ConfirmDialog } = useConfirmDialog();

  const [searchQuery, setSearchQuery] = useState('');
  const [addContributorDialogOpen, setAddContributorDialogOpen] = useState(false);
  const [paymentDialogOpen, setPaymentDialogOpen] = useState(false);
  const [editPledgeDialogOpen, setEditPledgeDialogOpen] = useState(false);
  const [thankYouDialogOpen, setThankYouDialogOpen] = useState(false);
  const [thankYouTarget, setThankYouTarget] = useState<EventContributorSummary | null>(null);
  const [thankYouMessage, setThankYouMessage] = useState('');
  const [detailContributor, setDetailContributor] = useState<EventContributorSummary | null>(null);
  const [paymentTarget, setPaymentTarget] = useState<EventContributorSummary | null>(null);
  const [editTarget, setEditTarget] = useState<EventContributorSummary | null>(null);
  const [shareLinkTarget, setShareLinkTarget] = useState<EventContributorSummary | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [activeSubTab, setActiveSubTab] = useState('contributors');
  const [currentPage, setCurrentPage] = useState(1);

  // Add contributor form
  const [addMode, setAddMode] = useState<'existing' | 'new'>('new');
  const [newContributor, setNewContributor] = useState({ name: '', email: '', phone: '', pledge_amount: '', notes: '', secondary_phone: '', notify_target: 'primary' as 'primary' | 'secondary' | 'both' });
  const [selectedExistingId, setSelectedExistingId] = useState<string | null>(null);
  const [existingPledgeAmount, setExistingPledgeAmount] = useState('');
  
  // Search existing contributors
  const { results: searchResults, loading: searchLoading, search: searchContributors, clear: clearSearch } = useContributorSearch();
  const searchInputRef = useRef<HTMLInputElement>(null);

  // Payment form
  const [payment, setPayment] = useState({ amount: '', payment_method: 'cash', payment_reference: '' });

  // Edit pledge
  const [editAmount, setEditAmount] = useState('');
  const [editDisplayName, setEditDisplayName] = useState('');
  const [editSecondaryPhone, setEditSecondaryPhone] = useState('');
  const [editNotifyTarget, setEditNotifyTarget] = useState<'primary' | 'secondary' | 'both'>('primary');

  // Payment history dialog
  const [historyDialogOpen, setHistoryDialogOpen] = useState(false);
  const [historyData, setHistoryData] = useState<any>(null);
  const [historyLoading, setHistoryLoading] = useState(false);

  // Report preview
  const [reportPreviewOpen, setReportPreviewOpen] = useState(false);
  const [reportHtml, setReportHtml] = useState('');
  const [reportDateDialogOpen, setReportDateDialogOpen] = useState(false);
  const [reportDateFrom, setReportDateFrom] = useState<Date | undefined>(undefined);
  const [reportDateTo, setReportDateTo] = useState<Date | undefined>(undefined);
  const [reportLoading, setReportLoading] = useState(false);
  const [reportFromOpen, setReportFromOpen] = useState(false);
  const [reportToOpen, setReportToOpen] = useState(false);

  // Bulk upload
  const [bulkDialogOpen, setBulkDialogOpen] = useState(false);
  const [bulkMode, setBulkMode] = useState<'targets' | 'contributions'>('targets');
  const [bulkSendSms, setBulkSendSms] = useState(false);
  const [bulkRows, setBulkRows] = useState<{ name: string; phone: string; amount: number }[]>([]);
  const [bulkFileName, setBulkFileName] = useState('');
  const [bulkErrors, setBulkErrors] = useState<string[]>([]);
  const [bulkUploading, setBulkUploading] = useState(false);
  const [bulkResult, setBulkResult] = useState<{ processed: number; errors_count: number; errors: { row: number; message: string }[]; job_id?: string; status?: string; summary?: { inserted?: number; updated?: number; duplicates_in_file?: number; notified?: number; notify_failed?: number } } | null>(null);
  const bulkFileRef = useRef<HTMLInputElement>(null);

  // Pending contributions (creator only)
  const [pendingContributions, setPendingContributions] = useState<any[]>([]);
  const [pendingLoading, setPendingLoading] = useState(false);
  const [selectedPending, setSelectedPending] = useState<string[]>([]);
  const [confirmingPending, setConfirmingPending] = useState(false);

  // Batch add-as-guest
  const [selectedForGuest, setSelectedForGuest] = useState<string[]>([]);
  const [guestBatchSendSms, setGuestBatchSendSms] = useState(false);
  const [addingAsGuests, setAddingAsGuests] = useState(false);
  const [guestBatchDialogOpen, setGuestBatchDialogOpen] = useState(false);
  const [messagingOpen, setMessagingOpen] = useState(false);
  const [paymentsOpen, setPaymentsOpen] = useState(false);
  const [invitationsOpen, setInvitationsOpen] = useState(false);

  // Pause polling when any dialog is open to prevent form disruption
  const anyDialogOpen = addContributorDialogOpen || paymentDialogOpen || editPledgeDialogOpen || thankYouDialogOpen || reportDateDialogOpen || reportPreviewOpen || historyDialogOpen || bulkDialogOpen || guestBatchDialogOpen;
  usePolling(() => { refetchEC(); }, 15000, !anyDialogOpen);

  const fetchPending = async () => {
    if (!isCreator) return;
    setPendingLoading(true);
    try {
      const res = await contributorsApi.getPendingContributions(eventId);
      if (res.success) setPendingContributions(res.data.contributions || []);
    } catch { /* silent */ }
    finally { setPendingLoading(false); }
  };

  // Fetch pending on mount for creator
  useEffect(() => { if (isCreator) fetchPending(); }, [isCreator, eventId]);

  const handleConfirmPending = async () => {
    if (selectedPending.length === 0) return;
    setConfirmingPending(true);
    try {
      const res = await contributorsApi.confirmContributions(eventId, selectedPending);
      if (res.success) {
        toast.success(`${res.data.confirmed} contributions confirmed`);
        setSelectedPending([]);
        fetchPending();
        refetchEC();
      }
    } catch (err: any) { showCaughtError(err, 'Failed to confirm'); }
    finally { setConfirmingPending(false); }
  };

  const handleRejectPending = async () => {
    if (selectedPending.length === 0) return;
    const confirmed = await confirm({
      title: 'Reject Contributions',
      description: `Are you sure you want to reject ${selectedPending.length} pending contribution(s)? The contributor(s) will be notified via SMS that their payment record was removed because the amount could not be verified.`,
      confirmLabel: 'Reject',
      destructive: true,
    });
    if (!confirmed) return;
    setConfirmingPending(true);
    try {
      const res = await contributorsApi.rejectContributions(eventId, selectedPending);
      if (res.success) {
        toast.success(`${res.data.rejected} contributions rejected`);
        setSelectedPending([]);
        fetchPending();
        refetchEC();
      }
    } catch (err: any) { showCaughtError(err, 'Failed to reject'); }
    finally { setConfirmingPending(false); }
  };

  // Computed
  const summary = ecSummary || { total_pledged: 0, total_paid: 0, total_balance: 0, count: 0, currency: 'TZS' };
  const currency = summary.currency || 'TZS';

  // Outstanding Pledge — match the Contributors Report logic exactly:
  // sum of each contributor's positive (pledged - paid) balance. Using the
  // event-wide (total_pledged - total_paid) understates the true outstanding
  // because contributors who overpay would cancel out those still owing.
  const outstandingPledge = eventContributors.reduce(
    (s, ec) => s + Math.max(0, (ec as any).balance ?? Math.max(0, (ec.pledge_amount || 0) - (ec.total_paid || 0))),
    0,
  );

  // Filter event contributors
  const filteredContributors = eventContributors.filter(ec => {
    if (!searchQuery) return true;
    const q = searchQuery.toLowerCase();
    return (
      ec.contributor?.name?.toLowerCase().includes(q) ||
      ec.contributor?.email?.toLowerCase().includes(q) ||
      ec.contributor?.phone?.includes(q)
    );
  }).sort((a, b) => (a.contributor?.name || '').localeCompare(b.contributor?.name || ''));
  const totalPages = Math.ceil(filteredContributors.length / ITEMS_PER_PAGE);
  const paginatedContributors = filteredContributors.slice((currentPage - 1) * ITEMS_PER_PAGE, currentPage * ITEMS_PER_PAGE);

  // --- Handlers ---

  const handleAddContributor = async () => {
    setIsSubmitting(true);
    try {
      if (addMode === 'existing' && selectedExistingId) {
        await addToEvent({
          contributor_id: selectedExistingId,
          pledge_amount: existingPledgeAmount ? parseFloat(existingPledgeAmount) : 0,
        });
      } else {
        if (!newContributor.name.trim()) { toast.error('Name is required'); setIsSubmitting(false); return; }
        if (!newContributor.phone.trim()) { toast.error('Phone number is required'); setIsSubmitting(false); return; }
        const primaryCheck = validateInternationalPhone(newContributor.phone, getActiveRegion().code);
        if (!primaryCheck.ok) { toast.error(primaryCheck.message); setIsSubmitting(false); return; }
        let normalizedSecondary: string | undefined;
        if (newContributor.secondary_phone.trim()) {
          const secCheck = validateInternationalPhone(newContributor.secondary_phone, getActiveRegion().code);
          if (!secCheck.ok) { toast.error(secCheck.message); setIsSubmitting(false); return; }
          normalizedSecondary = secCheck.e164;
        }
        await addToEvent({
          name: newContributor.name,
          email: newContributor.email || undefined,
          phone: primaryCheck.e164 || newContributor.phone,
          pledge_amount: newContributor.pledge_amount ? parseFloat(newContributor.pledge_amount) : 0,
          notes: newContributor.notes || undefined,
          secondary_phone: normalizedSecondary,
          notify_target: newContributor.notify_target,
        });
      }
      toast.success('Contributor added to event');
      setAddContributorDialogOpen(false);
      resetAddForm();
    } catch (err: any) {
      showCaughtError(err, 'Failed to add contributor');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRecordPayment = async () => {
    if (!paymentTarget) return;
    if (!payment.amount || parseFloat(payment.amount) <= 0) { toast.error('Enter a valid amount'); return; }
    setIsSubmitting(true);
    try {
      await recordPayment(paymentTarget.id, {
        amount: parseFloat(payment.amount),
        payment_method: payment.payment_method,
        payment_reference: payment.payment_reference || undefined,
      });
      toast.success('Payment recorded');
      setPaymentDialogOpen(false);
      setPaymentTarget(null);
      setPayment({ amount: '', payment_method: 'cash', payment_reference: '' });
    } catch (err: any) {
      showCaughtError(err, 'Failed to record payment');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleUpdatePledge = async () => {
    if (!editTarget) return;
    if (!editAmount || parseFloat(editAmount) < 0) { toast.error('Enter valid amount'); return; }
    setIsSubmitting(true);
    try {
      let normalizedSecondary: string | null = null;
      if (editSecondaryPhone.trim()) {
        const check = validateInternationalPhone(editSecondaryPhone, getActiveRegion().code);
        if (!check.ok) { toast.error(check.message); setIsSubmitting(false); return; }
        normalizedSecondary = check.e164 || editSecondaryPhone.trim();
      }
      // Only send fields that actually changed so the backend won't trigger an
      // SMS/WhatsApp notification when only the display name (or contact prefs)
      // were edited — the backend gates notifications on pledge_amount diffs.
      const payload: Record<string, any> = {};
      const newPledge = parseFloat(editAmount);
      if (newPledge !== Number(editTarget.pledge_amount || 0)) {
        payload.pledge_amount = newPledge;
      }
      const currentDisplay = (editTarget.display_name ?? '') || '';
      const nextDisplay = (editDisplayName || '').trim();
      if (nextDisplay !== currentDisplay) {
        payload.display_name = nextDisplay; // empty string clears override
      }
      if ((normalizedSecondary || '') !== ((editTarget.secondary_phone as string | null) || '')) {
        payload.secondary_phone = normalizedSecondary;
      }
      if (editNotifyTarget !== ((editTarget.notify_target as any) || 'primary')) {
        payload.notify_target = editNotifyTarget;
      }
      if (Object.keys(payload).length === 0) {
        toast.success('No changes');
        setEditPledgeDialogOpen(false);
        setEditTarget(null);
        setIsSubmitting(false);
        return;
      }
      await updateEventContributor(editTarget.id, payload);
      toast.success('Contributor updated');
      setEditPledgeDialogOpen(false);
      setEditTarget(null);
    } catch (err: any) {
      showCaughtError(err, 'Failed to update');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRemove = async (ecId: string) => {
    const confirmed = await confirm({
      title: 'Remove Contributor',
      description: 'Are you sure you want to remove this contributor from the event? This action cannot be undone.',
      confirmLabel: 'Remove',
      destructive: true,
    });
    if (!confirmed) return;
    try {
      await removeFromEvent(ecId);
      toast.success('Removed');
    } catch (err: any) {
      showCaughtError(err, 'Failed to remove');
    }
  };

  const [bulkRemoving, setBulkRemoving] = useState(false);
  const handleBulkRemove = async (all: boolean) => {
    const ids = all ? filteredContributors.map(ec => ec.id) : [...selectedForGuest];
    const count = ids.length;
    if (count === 0) return;
    const confirmed = await confirm({
      title: `Remove ${count} contributor${count > 1 ? 's' : ''}`,
      description: `This removes the selected contributor${count > 1 ? 's' : ''} from this event only. They stay in your contributor address book. This cannot be undone.`,
      confirmLabel: 'Remove',
      destructive: true,
    });
    if (!confirmed) return;
    setBulkRemoving(true);
    // Optimistic: clear selection immediately so the UI feels instant.
    setSelectedForGuest([]);
    const taskId = startTask({
      title: `Removing ${count} contributor${count > 1 ? 's' : ''} from event`,
      subtitle: all ? 'All contributors on this event' : `${count} selected`,
      kind: 'bulk-remove',
      total: count,
      progress: 0,
      href: `/event-management/${eventId}?tab=contributions`,
    });
    try {
      const res = await contributorsApi.bulkRemoveFromEvent(eventId, { ids });
      if (res.success) {
        const removed = res.data?.removed ?? count;
        appendDetail(taskId, { level: 'info', message: `Removed ${removed} contributor(s)` });
        updateTask(taskId, { processed: removed, total: removed, progress: 1 });
        finishTask(taskId, 'success');
        toast.success(`Removed ${removed} contributor(s)`);
        refetchEC();
      } else {
        finishTask(taskId, 'failed', res.message || 'Failed to remove');
        toast.error(res.message || 'Failed to remove');
      }
    } catch (err: any) {
      finishTask(taskId, 'failed', err?.message || 'Failed to remove contributors');
      showCaughtError(err, 'Failed to remove contributors');
    } finally {
      setBulkRemoving(false);
    }
  };


  /** Resend the same "target / contribution recorded" notification using the
   *  exact same Celery worker the bulk upload uses, so template and channels
   *  stay 1:1 identical. Progress is streamed into the background-task tracker. */
  const handleResendTargetNotification = async (ids: string[]) => {
    if (!ids.length) return;
    const taskId = startTask({
      title: `Resend target notification — ${ids.length} contributor${ids.length > 1 ? 's' : ''}`,
      subtitle: 'Sending WhatsApp + SMS',
      kind: 'notify',
      total: ids.length,
      progress: 0,
      href: `/event-management/${eventId}?tab=contributions`,
    });
    try {
      const res = ids.length === 1
        ? await contributorsApi.resendTargetNotification(eventId, ids[0])
        : await contributorsApi.bulkResendTargetNotification(eventId, ids);
      if (!res.success || !res.data?.job_id) {
        finishTask(taskId, 'failed', res.message || 'Failed to queue resend');
        toast.error(res.message || 'Failed to queue resend');
        return;
      }
      const jobId = res.data.job_id;
      toast.success(`Resend queued for ${res.data.total_rows} contributor${res.data.total_rows > 1 ? 's' : ''}`);
      appendDetail(taskId, { level: 'info', message: `Job queued (${res.data.total_rows} recipients).` });
      setSelectedForGuest([]);

      let finished = false;
      for (let attempt = 0; attempt < 240 && !finished; attempt++) {
        await new Promise((r) => setTimeout(r, 2000));
        const statusRes = await contributorsApi.getImportJobStatus(eventId, jobId);
        if (!statusRes.success || !statusRes.data) continue;
        const s = statusRes.data;
        const processed = s.processed_rows ?? 0;
        updateTask(taskId, {
          processed,
          total: s.total_rows,
          progress: s.total_rows ? processed / s.total_rows : undefined,
        });
        if (s.status === 'completed' || s.status === 'failed' || s.status === 'partially_completed') {
          finished = true;
          const sum = s.summary || {};
          appendDetail(taskId, {
            level: (sum.notify_failed || 0) > 0 ? 'warn' : 'info',
            message: `Sent: ${sum.notified ?? s.successful_rows} · Failed: ${sum.notify_failed ?? s.failed_rows}`,
          });
          (sum.notify_errors || []).slice(0, 30).forEach((e) =>
            appendDetail(taskId, {
              level: 'error',
              message: `Failed — ${e.name || e.ec_id}: ${(e.errors || []).join('; ')}`,
            }),
          );
          if (s.status === 'failed') finishTask(taskId, 'failed', s.error_message || 'Resend failed');
          else finishTask(taskId, 'success');
        }
      }
      if (!finished) finishTask(taskId, 'failed', 'Timed out waiting for resend.');
    } catch (err: any) {
      finishTask(taskId, 'failed', err?.message || 'Resend failed');
      showCaughtError(err, 'Resend failed');
    }
  };


  const handleAddAsGuest = async (ecId: string) => {
    setAddingAsGuests(true);
    try {
      const res = await eventsApi.addContributorsAsGuests(eventId, { contributor_ids: [ecId], send_sms: true });
      if (res.success) {
        if (res.data.skipped > 0) toast.info('Contributor is already on the guest list');
        else toast.success('Contributor added as guest');
      } else {
        toast.error(res.message || 'Failed to add as guest');
      }
    } catch (err: any) { showCaughtError(err, 'Failed to add as guest'); }
    finally { setAddingAsGuests(false); }
  };

  const handleBatchAddAsGuests = async () => {
    if (selectedForGuest.length === 0) return;
    setAddingAsGuests(true);
    try {
      const res = await eventsApi.addContributorsAsGuests(eventId, {
        contributor_ids: selectedForGuest,
        send_sms: guestBatchSendSms,
      });
      if (res.success) {
        toast.success(`${res.data.added} contributor(s) added as guests${res.data.skipped > 0 ? `, ${res.data.skipped} already on list` : ''}`);
        setSelectedForGuest([]);
        setGuestBatchDialogOpen(false);
      } else {
        toast.error(res.message || 'Failed');
      }
    } catch (err: any) { showCaughtError(err, 'Batch add failed'); }
    finally { setAddingAsGuests(false); }
  };

  const handleViewHistory = async (ec: EventContributorSummary) => {
    setHistoryLoading(true);
    setHistoryDialogOpen(true);
    setDetailContributor(ec);
    try {
      const data = await getPaymentHistory(ec.id);
      setHistoryData(data);
    } catch {
      setHistoryData(null);
    } finally {
      setHistoryLoading(false);
    }
  };

  const handleDeleteTransaction = async (paymentId: string) => {
    if (!detailContributor) return;
    const confirmed = await confirm({
      title: 'Delete Transaction',
      description: 'Are you sure you want to delete this transaction? This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    });
    if (!confirmed) return;
    try {
      const res = await contributorsApi.deleteTransaction(eventId, detailContributor.id, paymentId);
      if (res.success) {
        toast.success('Transaction deleted');
        // Refresh history
        const data = await getPaymentHistory(detailContributor.id);
        setHistoryData(data);
        refetchEC();
      } else {
        toast.error(res.message || 'Failed to delete');
      }
    } catch (err: any) {
      showCaughtError(err, 'Failed to delete transaction');
    }
  };

  const handleDownloadReport = async () => {
    setReportLoading(true);
    try {
      const params: { date_from?: string; date_to?: string } = {};
      if (reportDateFrom) params.date_from = format(reportDateFrom, 'yyyy-MM-dd');
      if (reportDateTo) params.date_to = format(reportDateTo, 'yyyy-MM-dd');

      const res = await contributorsApi.getContributionReport(eventId, params);
      if (!res.success) { toast.error(res.message || 'Failed to fetch report'); return; }

      const { contributors: reportContribs, full_summary: fullSummary } = res.data;
      const isFiltered = res.data.is_filtered;

      const dateRangeLabel = isFiltered
        ? `${reportDateFrom ? format(reportDateFrom, 'dd MMM yyyy') : 'Start'} - ${reportDateTo ? format(reportDateTo, 'dd MMM yyyy') : 'Present'}`
        : 'All Time';

      const html = generateContributionReportHtml(
        eventTitle || 'Event',
        reportContribs.map(c => ({
          name: c.name,
          pledged: c.pledged,
          paid: c.paid,
          balance: c.balance,
        })),
        {
          total_amount: fullSummary.total_paid,
          target_amount: fullSummary.total_pledged,
          currency: fullSummary.currency || currency,
          budget: eventBudget,
        },
        isFiltered ? dateRangeLabel : undefined,
        isFiltered ? { total_paid: fullSummary.total_paid, total_pledged: fullSummary.total_pledged, total_balance: fullSummary.total_balance } : undefined,
        eventEndDate
      );
      setReportHtml(html);
      setReportDateDialogOpen(false);
      setReportPreviewOpen(true);
    } catch (err: any) {
      showCaughtError(err, 'Failed to generate report');
    } finally {
      setReportLoading(false);
    }
  };

  const handleDownloadExcel = async () => {
    const writeXlsxFile = (await import('write-excel-file')).default;
    const sortedContributors = [...filteredContributors].sort((a, b) =>
      (a.contributor?.name || '').localeCompare(b.contributor?.name || '')
    );

    const HEADER_ROW = [
      { value: 'S/N', type: String, fontWeight: 'bold' as const },
      { value: 'Contributor', type: String, fontWeight: 'bold' as const },
      { value: 'Phone', type: String, fontWeight: 'bold' as const },
      { value: 'Pledged', type: String, fontWeight: 'bold' as const },
      { value: 'Paid', type: String, fontWeight: 'bold' as const },
      { value: 'Balance', type: String, fontWeight: 'bold' as const },
    ];

    const dataRows = sortedContributors.map((ec, i) => [
      { value: String(i + 1), type: String },
      { value: ec.contributor?.name || 'Unknown', type: String },
      { value: ec.contributor?.phone || '—', type: String },
      { value: ec.pledge_amount || 0, type: Number },
      { value: ec.total_paid || 0, type: Number },
      { value: ec.balance || 0, type: Number },
    ]);
    const rowTotals = sortedContributors.reduce(
      (totals, ec) => ({
        pledged: totals.pledged + (ec.pledge_amount || 0),
        paid: totals.paid + (ec.total_paid || 0),
        balance: totals.balance + Math.max(0, ec.balance ?? Math.max(0, (ec.pledge_amount || 0) - (ec.total_paid || 0))),
      }),
      { pledged: 0, paid: 0, balance: 0 }
    );

    const totalsRow = [
      { value: '', type: String },
      { value: `Total (${sortedContributors.length})`, type: String, fontWeight: 'bold' as const },
      { value: '', type: String },
      { value: rowTotals.pledged, type: Number, fontWeight: 'bold' as const },
      { value: rowTotals.paid, type: Number, fontWeight: 'bold' as const },
      { value: rowTotals.balance, type: Number, fontWeight: 'bold' as const },
    ];

    await writeXlsxFile([HEADER_ROW, ...dataRows, totalsRow] as any, {
      fileName: `${(eventTitle || 'Event').replace(/\s+/g, '_')}_Contributions.xlsx`,
      columns: [
        { width: 6 },
        { width: 25 },
        { width: 18 },
        { width: 18 },
        { width: 18 },
        { width: 18 },
      ],
    });
  };

  const resetAddForm = () => {
    setNewContributor({ name: '', email: '', phone: '', pledge_amount: '', notes: '', secondary_phone: '', notify_target: 'primary' });
    setSelectedExistingId(null);
    setExistingPledgeAmount('');
    setAddMode('new');
    clearSearch();
  };

  const resetBulkForm = () => {
    setBulkRows([]);
    setBulkFileName('');
    setBulkErrors([]);
    setBulkResult(null);
    setBulkSendSms(false);
    if (bulkFileRef.current) bulkFileRef.current.value = '';
  };

  const formatTanzanianPhone = (raw: string): string => {
    let phone = raw.toString().replace(/[\s\-\+]/g, '');
    if (phone.startsWith('0') && phone.length === 10) phone = phone.slice(1);
    if (/^[67]/.test(phone)) phone = '255' + phone;
    if (/^255[67]\d{8}$/.test(phone)) return phone;
    throw new Error(`Invalid phone: ${raw}`);
  };

  const handleBulkFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setBulkFileName(file.name);
    setBulkErrors([]);
    setBulkRows([]);
    setBulkResult(null);

    try {
      const rows = await readXlsxFile(file);
      // Expect header row: s/n, name, phone, amount
      if (rows.length < 2) { setBulkErrors(['File must have a header row and at least one data row']); return; }
      
      const header = rows[0].map(h => String(h || '').toLowerCase().trim());
      if (header.length < 3) { setBulkErrors(['File must have at least 3 columns: S/N, Name, Phone']); return; }

      const parsed: { name: string; phone: string; amount: number }[] = [];
      const parseErrors: string[] = [];

      for (let i = 1; i < rows.length; i++) {
        const row = rows[i];
        const name = String(row[1] || '').trim();
        const phoneRaw = String(row[2] || '').trim();
        const amountRaw = row[3];

        if (!name && !phoneRaw) continue; // skip empty rows

        if (!name) { parseErrors.push(`Row ${i + 1}: Name is missing`); continue; }
        if (!phoneRaw) { parseErrors.push(`Row ${i + 1}: Phone is missing for ${name}`); continue; }

        let phone: string;
        try {
          phone = formatTanzanianPhone(phoneRaw);
        } catch {
          parseErrors.push(`Row ${i + 1}: Invalid phone "${phoneRaw}" for ${name}`);
          continue;
        }

        const amount = amountRaw ? parseFloat(String(amountRaw).replace(/,/g, '')) : 0;
        if (isNaN(amount) || amount < 0) { parseErrors.push(`Row ${i + 1}: Invalid amount for ${name}`); continue; }

        parsed.push({ name, phone, amount });
      }

      setBulkRows(parsed);
      if (parseErrors.length > 0) setBulkErrors(parseErrors);
    } catch {
      setBulkErrors(['Failed to parse file. Please ensure it is a valid .xlsx file.']);
    }
  };


  const handleBulkUpload = async () => {
    if (bulkRows.length === 0) return;
    setBulkUploading(true);
    setBulkResult(null);
    const rowCount = bulkRows.length;
    const taskId = startTask({
      title: `Bulk upload — ${rowCount} contributor${rowCount > 1 ? 's' : ''}`,
      subtitle: bulkMode === 'targets' ? 'Setting pledge targets' : 'Recording contributions',
      kind: 'upload',
      total: rowCount,
      progress: 0,
      href: `/event-management/${eventId}?tab=contributions`,
    });
    try {
      const res = await contributorsApi.bulkAddToEvent(eventId, {
        contributors: bulkRows,
        send_sms: bulkSendSms,
        mode: bulkMode,
      });
      if (!res.success || !res.data?.job_id) {
        finishTask(taskId, 'failed', res.message || 'Bulk upload failed');
        toast.error(res.message || 'Bulk upload failed');
        return;
      }

      const jobId = res.data.job_id;
      appendDetail(taskId, { level: 'info', message: `Job queued (${res.data.total_rows} rows). Processing…` });
      toast.success(`Upload received. Processing ${res.data.total_rows} contributors in the background…`);
      setBulkRows([]);
      setBulkFileName('');
      setBulkErrors([]);
      if (bulkFileRef.current) bulkFileRef.current.value = '';
      // The user can now safely close the dialog — work continues below.
      setBulkUploading(false);

      // Poll job status until it finishes
      let finished = false;
      for (let attempt = 0; attempt < 240 && !finished; attempt++) {
        await new Promise((r) => setTimeout(r, 2000));
        const statusRes = await contributorsApi.getImportJobStatus(eventId, jobId);
        if (!statusRes.success || !statusRes.data) continue;
        const s = statusRes.data;
        const processed = s.processed_rows ?? 0;
        updateTask(taskId, {
          processed,
          total: s.total_rows,
          progress: s.total_rows ? processed / s.total_rows : undefined,
        });
        if (s.status === 'completed' || s.status === 'failed' || s.status === 'partially_completed') {
          finished = true;
          let errs: { row: number; message: string }[] = [];
          if (s.failed_rows > 0) {
            const errRes = await contributorsApi.getImportJobErrors(eventId, jobId);
            if (errRes.success && errRes.data?.errors) errs = errRes.data.errors;
          }
          setBulkResult({
            processed: s.successful_rows,
            errors_count: s.failed_rows,
            errors: errs,
            job_id: jobId,
            status: s.status,
            summary: s.summary,
          });
          const sum = s.summary || {};
          appendDetail(taskId, {
            level: s.failed_rows > 0 ? 'warn' : 'info',
            message: `${s.successful_rows} processed, ${s.failed_rows} errors`,
          });
          if (sum.inserted !== undefined || sum.updated !== undefined || sum.duplicates_in_file !== undefined) {
            appendDetail(taskId, {
              level: 'info',
              message: `${sum.inserted ?? 0} new · ${sum.updated ?? 0} updated · ${sum.duplicates_in_file ?? 0} duplicates in file`,
            });
          }
          if (sum.notified !== undefined || sum.notify_failed !== undefined) {
            appendDetail(taskId, {
              level: (sum.notify_failed || 0) > 0 ? 'warn' : 'info',
              message: `Notifications sent: ${sum.notified ?? 0} · failed: ${sum.notify_failed ?? 0}`,
            });
            (sum.notify_errors || []).slice(0, 20).forEach((e) =>
              appendDetail(taskId, {
                level: 'error',
                message: `Notify failed — ${e.name || e.phone || 'row ' + e.row}: ${(e.errors || []).join('; ')}`,
              }),
            );
          }
          errs.slice(0, 20).forEach((e) =>
            appendDetail(taskId, { level: 'error', message: `Row ${e.row}: ${e.message}` }),
          );
          if (s.status === 'completed' || s.status === 'partially_completed') {
            finishTask(taskId, 'success');
            toast.success(`${s.successful_rows} contributors processed${s.failed_rows ? `, ${s.failed_rows} errors` : ''}`);
          } else {
            finishTask(taskId, 'failed', s.error_message || 'Bulk import failed');
            toast.error(s.error_message || 'Bulk import failed');
          }
          refetchEC();
          invalidateUserContributorsCache();
        }
      }
      if (!finished) {
        finishTask(taskId, 'failed', 'Timed out waiting for the import to finish.');
      }
    } catch (err: any) {
      finishTask(taskId, 'failed', err?.message || 'Bulk upload failed');
      showCaughtError(err, 'Bulk upload failed');
    } finally {
      setBulkUploading(false);
    }
  };

  // legacy placeholder lines below intentionally removed

  const downloadSampleXlsx = async () => {
    const writeXlsxFile = (await import('write-excel-file')).default;

    const sampleData = [
      { sn: 1, name: 'Amina Juma', phone: '255654321098', amount: 50000 },
      { sn: 2, name: 'Baraka Mushi', phone: '255712345678', amount: 100000 },
      { sn: 3, name: 'Catherine Lyimo', phone: '255687654321', amount: 75000 },
      { sn: 4, name: 'David Mwakasege', phone: '255763219876', amount: 200000 },
      { sn: 5, name: 'Esther Kimaro', phone: '255655432109', amount: 30000 },
      { sn: 6, name: 'Fadhili Hassan', phone: '255714567890', amount: 150000 },
      { sn: 7, name: 'Grace Shirima', phone: '255689012345', amount: 0 },
      { sn: 8, name: 'Hussein Bakari', phone: '255768901234', amount: 80000 },
      { sn: 9, name: 'Irene Massawe', phone: '255651234567', amount: 60000 },
      { sn: 10, name: 'Joseph Mlay', phone: '255719876543', amount: 120000 },
      { sn: 11, name: 'Khadija Omary', phone: '255682345678', amount: 45000 },
      { sn: 12, name: 'Linus Mwanga', phone: '255767890123', amount: 90000 },
      { sn: 13, name: 'Mariam Salum', phone: '255658765432', amount: 25000 },
      { sn: 14, name: 'Noel Urassa', phone: '255710987654', amount: 110000 },
      { sn: 15, name: 'Penina Mbwilo', phone: '255685678901', amount: 70000 },
    ];

    const HEADER_ROW = [
      { value: 'S/N', fontWeight: 'bold' as const },
      { value: 'Contributor Name', fontWeight: 'bold' as const },
      { value: 'Phone', fontWeight: 'bold' as const },
      { value: 'Target Amount', fontWeight: 'bold' as const },
    ];

    const dataRows = sampleData.map(d => [
      { type: Number as any, value: d.sn },
      { type: String as any, value: d.name },
      { type: String as any, value: d.phone },
      { type: Number as any, value: d.amount },
    ]);

    const data = [HEADER_ROW, ...dataRows];

    await writeXlsxFile(data as any, {
      fileName: 'contributors_template.xlsx',
      columns: [
        { width: 6 },
        { width: 25 },
        { width: 18 },
        { width: 18 },
      ],
    });
  };

  if (ecLoading) return <ContributionsSkeletonLoader />;
  if (ecError) return <div className="p-6 text-center text-destructive">{ecError}</div>;

  return (
    <div className="space-y-6">
      <ConfirmDialog />
      {/* Row 1: Event Budget | Total Collected | Budget Shortfall */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        {eventBudget ? (
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-xs text-muted-foreground">Event Budget</p><p className="text-base font-semibold">{formatPrice(eventBudget)}</p></div><div className="w-7 h-7 bg-blue-100 rounded-lg flex items-center justify-center"><DollarSign className="w-3.5 h-3.5 text-blue-600" /></div></div></CardContent></Card>
        ) : null}
        <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-xs text-muted-foreground">Total Collected</p><p className="text-base font-semibold text-green-600">{formatPrice(summary.total_paid)}</p></div><div className="w-7 h-7 bg-green-100 rounded-lg flex items-center justify-center"><DollarSign className="w-3.5 h-3.5 text-green-600" /></div></div></CardContent></Card>
        {eventBudget ? (
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-xs text-muted-foreground">Budget Shortfall</p><p className="text-base font-semibold text-destructive">{formatPrice(Math.max(0, eventBudget - summary.total_paid))}</p></div><div className="w-7 h-7 bg-red-100 rounded-lg flex items-center justify-center"><DollarSign className="w-3.5 h-3.5 text-red-600" /></div></div></CardContent></Card>
        ) : null}
      </div>

      {/* Row 2: Total Pledged | Outstanding Pledge | Unpledged */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-xs text-muted-foreground">Total Pledged</p><p className="text-base font-semibold text-yellow-600">{formatPrice(summary.total_pledged)}</p></div><div className="w-7 h-7 bg-yellow-100 rounded-lg flex items-center justify-center"><TrendingUp className="w-3.5 h-3.5 text-yellow-600" /></div></div></CardContent></Card>
        <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-xs text-muted-foreground">Outstanding Pledge</p><p className="text-base font-semibold text-orange-600">{formatPrice(outstandingPledge)}</p></div><div className="w-7 h-7 bg-orange-100 rounded-lg flex items-center justify-center"><Clock className="w-3.5 h-3.5 text-orange-600" /></div></div></CardContent></Card>
        {eventBudget ? (
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-xs text-muted-foreground">Unpledged</p><p className="text-base font-semibold text-purple-600">{formatPrice(Math.max(0, eventBudget - summary.total_pledged))}</p></div><div className="w-7 h-7 bg-purple-100 rounded-lg flex items-center justify-center"><TrendingUp className="w-3.5 h-3.5 text-purple-600" /></div></div></CardContent></Card>
        ) : null}
      </div>

      {/* WhatsApp reachability rollup */}
      {(summary as any).whatsapp && (
        <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
          <span className="font-medium">WhatsApp reach:</span>
          <span className="inline-flex items-center gap-1.5"><WhatsAppStatusBadge status="available" />{((summary as any).whatsapp.whatsapp || 0) + ((summary as any).whatsapp.available || 0)}</span>
          <span className="inline-flex items-center gap-1.5"><WhatsAppStatusBadge status="unavailable" />{((summary as any).whatsapp.not_whatsapp || 0) + ((summary as any).whatsapp.unavailable || 0)}</span>
          <span className="inline-flex items-center gap-1.5"><WhatsAppStatusBadge status="unknown" showUnknown />{((summary as any).whatsapp.unknown || 0) + ((summary as any).whatsapp.failed || 0) + ((summary as any).whatsapp.error || 0)}</span>
          {((summary as any).whatsapp.checking || 0) > 0 && (
            <span className="inline-flex items-center gap-1.5"><WhatsAppStatusBadge status="checking" />{(summary as any).whatsapp.checking}</span>
          )}
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {eventBudget && eventBudget > 0 && (
          <Card><CardContent className="p-4">
            <div className="flex items-center justify-between mb-2"><span className="text-xs font-medium">Budget vs Raised</span><span className="text-xs text-muted-foreground">{formatPrice(summary.total_paid)} / {formatPrice(eventBudget)}</span></div>
            <Progress value={eventBudget > 0 ? (summary.total_paid / eventBudget * 100) : 0} className="h-3" />
            <p className="text-xs text-muted-foreground mt-1">Budget coverage: <span className="text-green-600 font-semibold">{eventBudget > 0 ? Math.min(summary.total_paid / eventBudget * 100, 100).toFixed(1) : 0}%</span> of event budget raised so far.</p>
          </CardContent></Card>
        )}

        {summary.total_pledged > 0 && (
          <Card><CardContent className="p-4">
            <div className="flex items-center justify-between mb-2"><span className="text-xs font-medium">Collection Progress</span><span className="text-xs text-muted-foreground">{formatPrice(summary.total_paid)} / {formatPrice(summary.total_pledged)}</span></div>
            <Progress value={summary.total_pledged > 0 ? (summary.total_paid / summary.total_pledged * 100) : 0} className="h-3" />
            <p className="text-xs text-muted-foreground mt-1">{summary.total_pledged > 0 ? (summary.total_paid / summary.total_pledged * 100).toFixed(1) : 0}% collected</p>
          </CardContent></Card>
        )}
      </div>

      {/* Actions Bar */}
      <div className="flex flex-col md:flex-row gap-4">
        <div className="flex gap-2 flex-wrap">
          <Button variant="outline" size="sm" onClick={() => { setReportDateFrom(undefined); setReportDateTo(undefined); setReportDateDialogOpen(true); }}>
            <Download className="w-4 h-4 mr-2" />Report
          </Button>
          {isCreator && (
            <Button variant="outline" size="sm" onClick={() => { resetBulkForm(); setBulkDialogOpen(true); }}>
              <Upload className="w-4 h-4 mr-2" />Bulk Upload
            </Button>
          )}
          {canManage && (
            <Button onClick={() => { resetAddForm(); setAddContributorDialogOpen(true); }}>
              <UserPlus className="w-4 h-4 mr-2" />Add Contributor
            </Button>
          )}
          {isCreator && eventContributors.length > 0 && (
            <Button variant="outline" size="sm" onClick={() => {
              setMessagingOpen(v => { const next = !v; if (next) setInvitationsOpen(false); return next; });
            }}>
              <SvgIcon src={ChatIcon} alt={t("messages")} className="w-4 h-4 mr-2" />{messagingOpen ? 'Hide' : ''} Messaging
            </Button>
          )}
          {canManage && eventContributors.length > 0 && (
            <Button variant="outline" size="sm" onClick={() => {
              setInvitationsOpen(v => { const next = !v; if (next) setMessagingOpen(false); return next; });
            }}>
              <Send className="w-4 h-4 mr-2" />{invitationsOpen ? 'Hide ' : ''}Invitations
            </Button>
          )}
          {isCreator && (
            <Button variant="outline" size="sm" onClick={() => setPaymentsOpen(!paymentsOpen)}>
              <DollarSign className="w-4 h-4 mr-2" />{paymentsOpen ? 'Hide ' : ''}Payments
            </Button>
          )}
        </div>
      </div>

      {/* Share payment link with a single contributor */}
      <ShareContributorLinkDialog
        open={!!shareLinkTarget}
        onOpenChange={(v) => { if (!v) setShareLinkTarget(null); }}
        eventId={eventId}
        contributor={shareLinkTarget}
        onChanged={refetchEC}
      />

      {/* Contributor Messaging */}
      {isCreator && messagingOpen && (
        <ContributorMessaging
          eventId={eventId}
          eventTitle={eventTitle}
          eventContributors={eventContributors}
          defaultContactPhone={reminderContactPhone}
        />
      )}

      {/* Contributor Invitations */}
      {canManage && invitationsOpen && (
        <ContributorInvitationsPanel
          eventId={eventId}
          eventContributors={eventContributors}
          onChanged={refetchEC}
        />
      )}

      {/* Received contribution payments */}
      {isCreator && paymentsOpen && (
        <ReceivedPaymentsPanel
          source={{ kind: 'event-contributions', eventId }}
          title="Contribution payments received"
        />
      )}

      {/* Pending Contributions Tab (Creator only) */}
      {isCreator && pendingContributions.length > 0 && (
        <Card className="border-amber-200 bg-amber-50/50">
          <CardContent className="p-4">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-3">
              <div className="flex items-center gap-2 min-w-0">
                <ShieldCheck className="w-5 h-5 text-amber-600 flex-shrink-0" />
                <h3 className="font-semibold text-amber-800 text-sm sm:text-base truncate">Awaiting Confirmation ({pendingContributions.length})</h3>
              </div>
              <div className="grid grid-cols-3 sm:flex gap-2 w-full sm:w-auto">
                <Button size="sm" variant="outline" className="px-2 sm:px-3" onClick={() => setSelectedPending(selectedPending.length === pendingContributions.length ? [] : pendingContributions.map(p => p.id))}>
                  <span className="truncate text-xs sm:text-sm">{selectedPending.length === pendingContributions.length ? 'Deselect' : 'Select All'}</span>
                </Button>
                <Button size="sm" variant="destructive" className="px-2 sm:px-3" onClick={handleRejectPending} disabled={selectedPending.length === 0 || confirmingPending}>
                  {confirmingPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Trash className="w-4 h-4 sm:mr-1" /><span className="hidden sm:inline">Reject </span><span className="text-xs sm:text-sm">({selectedPending.length})</span></>}
                </Button>
                <Button size="sm" className="px-2 sm:px-3" onClick={handleConfirmPending} disabled={selectedPending.length === 0 || confirmingPending}>
                  {confirmingPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <><CheckCircle2 className="w-4 h-4 sm:mr-1" /><span className="hidden sm:inline">Confirm </span><span className="text-xs sm:text-sm">({selectedPending.length})</span></>}
                </Button>
              </div>
            </div>
            <div className="divide-y border rounded-lg bg-white">
              {pendingContributions.map((pc: any) => (
                <div key={pc.id} className="p-3 flex items-start gap-3">
                  <Checkbox checked={selectedPending.includes(pc.id)} onCheckedChange={(checked) => setSelectedPending(prev => checked ? [...prev, pc.id] : prev.filter(id => id !== pc.id))} className="mt-1" />
                  <div className="flex-1 min-w-0 space-y-1">
                    <p className="font-medium text-sm">{pc.contributor_name}</p>
                    <p className="text-xs text-muted-foreground">
                      Recorded by {pc.recorded_by || 'Unknown'} {pc.created_at ? `on ${formatDateMedium(pc.created_at)} at ${new Date(pc.created_at.endsWith('Z') || pc.created_at.includes('+') ? pc.created_at : pc.created_at + 'Z').toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : ''}
                    </p>
                    {/* Offline-claim audit trail (when present) */}
                    {(pc.payment_channel || pc.provider_name || pc.transaction_ref || pc.payer_account) && (
                      <div className="flex flex-wrap items-center gap-1.5 pt-1">
                        {pc.payment_channel && (
                          <Badge variant="outline" className="text-[10px] capitalize">
                            {pc.payment_channel.replace('_', ' ')}
                          </Badge>
                        )}
                        {pc.provider_name && (
                          <Badge variant="secondary" className="text-[10px]">{pc.provider_name}</Badge>
                        )}
                        {pc.transaction_ref && (
                          <span className="text-[10px] font-mono text-muted-foreground">Ref: {pc.transaction_ref}</span>
                        )}
                        {pc.payer_account && (
                          <span className="text-[10px] text-muted-foreground">From: {pc.payer_account}</span>
                        )}
                      </div>
                    )}
                  </div>
                  {pc.receipt_image_url && (
                    <a
                      href={pc.receipt_image_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="block h-12 w-12 rounded-md overflow-hidden border border-border bg-muted flex-shrink-0 hover:ring-2 hover:ring-primary transition-all"
                      title="Open receipt"
                    >
                      <img src={pc.receipt_image_url} alt="Receipt" className="w-full h-full object-cover" />
                    </a>
                  )}
                  <div className="text-right flex-shrink-0">
                    <p className="font-bold text-amber-700">{formatPrice(pc.amount)}</p>
                    {pc.payment_method && <p className="text-xs text-muted-foreground capitalize">{pc.payment_method}</p>}
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Search */}
      <div className="flex gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input placeholder="Search contributors..." value={searchQuery} onChange={(e) => { setSearchQuery(e.target.value); setCurrentPage(1); }} className="pl-9" />
        </div>
      </div>

      {/* Batch Action Bar */}
      {canManage && (selectedForGuest.length > 0 || filteredContributors.length > paginatedContributors.length) && selectedForGuest.length > 0 && (
        <Card className="border-blue-200 bg-blue-50/50">
          <CardContent className="p-3 flex flex-wrap items-center justify-between gap-2">
            <div className="flex flex-wrap items-center gap-3 text-sm">
              <p className="font-medium text-blue-800">
                {selectedForGuest.length} contributor{selectedForGuest.length > 1 ? 's' : ''} selected
              </p>
              {selectedForGuest.length < filteredContributors.length && (
                <button
                  type="button"
                  className="text-xs font-medium text-blue-700 hover:underline"
                  onClick={() => setSelectedForGuest(filteredContributors.map(ec => ec.id))}
                >
                  Select all {filteredContributors.length} across pages
                </button>
              )}
            </div>
            <div className="flex flex-wrap gap-2">
              <Button variant="outline" size="sm" onClick={() => setSelectedForGuest([])}>Clear</Button>
              <Button size="sm" variant="outline" onClick={() => handleResendTargetNotification(selectedForGuest)}>
                <BellRing className="w-4 h-4 mr-1" />Target Notification
              </Button>
              <Button size="sm" onClick={() => setGuestBatchDialogOpen(true)} disabled={addingAsGuests}>
                <UserCheck className="w-4 h-4 mr-1" />Add as Guest{selectedForGuest.length > 1 ? 's' : ''}
              </Button>
              <Button size="sm" variant="destructive" onClick={() => handleBulkRemove(false)} disabled={bulkRemoving}>
                {bulkRemoving ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : <Trash className="w-4 h-4 mr-1" />}
                Remove {selectedForGuest.length}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}



      {/* Contributors Table */}
      <Card><CardContent className="p-0">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b bg-muted/50">
                {canManage && (
                  <th className="p-4 w-16">
                    <div className="flex items-center gap-1.5">
                      <Checkbox
                        checked={filteredContributors.length > 0 && filteredContributors.every(ec => selectedForGuest.includes(ec.id))}
                        onCheckedChange={(checked) => {
                          const allIds = filteredContributors.map(ec => ec.id);
                          setSelectedForGuest(prev => checked
                            ? Array.from(new Set([...prev, ...allIds]))
                            : prev.filter(id => !allIds.includes(id)));
                        }}
                      />
                      {totalPages > 1 && (
                        <button
                          type="button"
                          title={selectedForGuest.length === filteredContributors.length ? 'Clear selection' : `Select all ${filteredContributors.length} across all pages`}
                          className="text-[10px] font-medium text-blue-700 hover:underline whitespace-nowrap"
                          onClick={() => {
                            if (selectedForGuest.length === filteredContributors.length) setSelectedForGuest([]);
                            else setSelectedForGuest(filteredContributors.map(ec => ec.id));
                          }}
                        >
                          {selectedForGuest.length === filteredContributors.length ? 'Clear' : `All ${filteredContributors.length}`}
                        </button>
                      )}
                    </div>
                  </th>
                )}
                <th className="text-left p-4 text-sm font-medium">Contributor</th>
                <th className="text-right p-4 text-sm font-medium">Pledged</th>
                <th className="text-right p-4 text-sm font-medium">Paid</th>
                <th className="text-right p-4 text-sm font-medium">Balance</th>
                {canManage && <th className="text-right p-4 text-sm font-medium">Actions</th>}
              </tr>
            </thead>
            <tbody className="divide-y">
              {paginatedContributors.length === 0 ? (
                <tr><td colSpan={canManage ? 7 : 4} className="p-6 text-center text-muted-foreground">No contributors added yet. Click "Add Contributor" to get started.</td></tr>
              ) : (
                paginatedContributors.map((ec) => (
                  <tr key={ec.id} className={`hover:bg-muted/50 ${selectedForGuest.includes(ec.id) ? 'bg-blue-50/50' : ''}`}>
                    {canManage && (
                      <td className="p-4 w-10">
                        <Checkbox
                          checked={selectedForGuest.includes(ec.id)}
                          onCheckedChange={(checked) => setSelectedForGuest(prev => checked ? [...prev, ec.id] : prev.filter(id => id !== ec.id))}
                        />
                      </td>
                    )}
                    <td className="p-4">
                      <p className="font-medium">{ec.contributor?.name || 'Unknown'}</p>
                      {ec.contributor?.global_name && ec.display_name && ec.contributor.global_name !== ec.display_name && (
                        <p className="text-[11px] text-muted-foreground italic mt-0.5">
                          also known as {ec.contributor.global_name}
                        </p>
                      )}
                      {ec.contributor?.email && <p className="text-xs text-muted-foreground">{ec.contributor.email}</p>}
                      {ec.contributor?.phone && (
                        <p className="text-xs text-muted-foreground flex items-center gap-1.5 mt-0.5">
                          <span>{ec.contributor.phone}</span>
                          <WhatsAppStatusBadge status={ec.contributor.whatsapp_status} />
                        </p>
                      )}
                    </td>
                    <td className="p-4 text-right text-yellow-600 font-medium">{formatPrice(ec.pledge_amount)}</td>
                    <td className="p-4 text-right text-green-600 font-medium">{formatPrice(ec.total_paid)}</td>
                    <td className="p-4 text-right font-semibold">
                      <span className={ec.balance > 0 ? 'text-destructive' : 'text-green-600'}>{formatPrice(ec.balance)}</span>
                    </td>
                    {canManage && (
                      <td className="p-4 text-right">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild><Button variant="ghost" size="icon"><MoreVertical className="w-4 h-4" /></Button></DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuItem onClick={() => { setPaymentTarget(ec); setPayment({ amount: '', payment_method: 'cash', payment_reference: '' }); setPaymentDialogOpen(true); }}>
                              <DollarSign className="w-4 h-4 mr-2" />Record Payment
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => {
                              setEditTarget(ec);
                              setEditAmount(String(ec.pledge_amount));
                              setEditDisplayName(ec.display_name || '');
                              setEditSecondaryPhone(ec.secondary_phone || '');
                              setEditNotifyTarget((ec.notify_target as any) || 'primary');
                              setEditPledgeDialogOpen(true);
                            }}>
                              <Edit className="w-4 h-4 mr-2" />Edit Contributor
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => handleViewHistory(ec)}>
                              <Eye className="w-4 h-4 mr-2" />Payment History
                            </DropdownMenuItem>
                            {ec.total_paid > 0 && (
                              <DropdownMenuItem onClick={() => { setThankYouTarget(ec); setThankYouMessage(''); setThankYouDialogOpen(true); }}>
                                <Send className="w-4 h-4 mr-2" />Send Thank You
                              </DropdownMenuItem>
                            )}
                            <DropdownMenuItem onClick={() => setShareLinkTarget(ec)}>
                              <LinkIcon className="w-4 h-4 mr-2" />Share payment link
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => handleResendTargetNotification([ec.id])}>
                              <BellRing className="w-4 h-4 mr-2" />Target Notification
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => handleAddAsGuest(ec.id)}>
                              <UserCheck className="w-4 h-4 mr-2" />Add as Guest
                            </DropdownMenuItem>
                            <DropdownMenuItem className="text-destructive" onClick={() => handleRemove(ec.id)}>
                              <Trash className="w-4 h-4 mr-2" />Remove
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </td>
                    )}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        {totalPages > 1 && (
          <div className="flex items-center justify-between p-4 border-t">
            <p className="text-sm text-muted-foreground">
              Showing {((currentPage - 1) * ITEMS_PER_PAGE) + 1}–{Math.min(currentPage * ITEMS_PER_PAGE, filteredContributors.length)} of {filteredContributors.length}
            </p>
            <div className="flex items-center gap-1">
              <Button variant="outline" size="icon" className="h-8 w-8" disabled={currentPage === 1} onClick={() => setCurrentPage(p => p - 1)}><ChevronLeft className="w-4 h-4" /></Button>
              {Array.from({ length: Math.min(totalPages, 5) }, (_, i) => {
                const page = totalPages <= 5 ? i + 1 : Math.max(1, Math.min(currentPage - 2, totalPages - 4)) + i;
                return <Button key={page} variant={page === currentPage ? 'default' : 'outline'} size="icon" className="h-8 w-8" onClick={() => setCurrentPage(page)}>{page}</Button>;
              })}
              <Button variant="outline" size="icon" className="h-8 w-8" disabled={currentPage === totalPages} onClick={() => setCurrentPage(p => p + 1)}><ChevronRight className="w-4 h-4" /></Button>
            </div>
          </div>
        )}
      </CardContent></Card>

      {/* Add Contributor Dialog */}
      <Dialog open={addContributorDialogOpen} onOpenChange={(open) => { setAddContributorDialogOpen(open); if (!open) resetAddForm(); }}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Add Contributor to Event</DialogTitle></DialogHeader>
          <Tabs value={addMode} onValueChange={(v) => setAddMode(v as 'existing' | 'new')}>
            <TabsList className="w-full">
              <TabsTrigger value="new" className="flex-1">New Contributor</TabsTrigger>
              <TabsTrigger value="existing" className="flex-1">From Address Book</TabsTrigger>
            </TabsList>
            <TabsContent value="new">
              <div className="space-y-4 py-2">
                <div className="space-y-2"><Label>Name *</Label><Input value={newContributor.name} onChange={(e) => setNewContributor(p => ({ ...p, name: e.target.value }))} placeholder="Full name" /></div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2"><Label>Email</Label><Input type="email" value={newContributor.email} onChange={(e) => setNewContributor(p => ({ ...p, email: e.target.value }))} placeholder="email@example.com" /></div>
                  <div className="space-y-2"><Label>Phone *</Label><Input value={newContributor.phone} onChange={(e) => setNewContributor(p => ({ ...p, phone: e.target.value }))} placeholder="+255..." required /></div>
                </div>
                <div className="space-y-2"><Label>Pledge Amount ({currency})</Label><FormattedNumberInput value={newContributor.pledge_amount} onChange={(v) => setNewContributor(p => ({ ...p, pledge_amount: v }))} placeholder="e.g. 20,000" /></div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2"><Label>Secondary phone <span className="text-xs text-muted-foreground">(optional)</span></Label><Input value={newContributor.secondary_phone} onChange={(e) => setNewContributor(p => ({ ...p, secondary_phone: e.target.value }))} placeholder="+255..." /></div>
                  <div className="space-y-2">
                    <Label>Notify</Label>
                    <Select value={newContributor.notify_target} onValueChange={(v) => setNewContributor(p => ({ ...p, notify_target: v as any }))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="primary">Primary only</SelectItem>
                        <SelectItem value="secondary">Secondary only</SelectItem>
                        <SelectItem value="both">Both numbers</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
                <p className="text-[11px] text-muted-foreground -mt-2">Secondary phone is for notifications only — it won't link to a Nuru account.</p>
                <div className="space-y-2"><Label>Notes</Label><Textarea value={newContributor.notes} onChange={(e) => setNewContributor(p => ({ ...p, notes: e.target.value }))} rows={2} /></div>
              </div>
            </TabsContent>
            <TabsContent value="existing">
              <div className="space-y-4 py-2">
                <div className="space-y-2">
                  <Label>Search Your Contributors</Label>
                  <div className="relative">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                    <Input
                      ref={searchInputRef}
                      placeholder="Search by name, email, or phone..."
                      className="pl-9"
                      onChange={(e) => searchContributors(e.target.value)}
                    />
                  </div>
                  {searchLoading && <p className="text-sm text-muted-foreground">Searching...</p>}
                  {searchResults.length > 0 && (
                    <div className="border rounded-lg divide-y max-h-48 overflow-y-auto">
                      {searchResults.map(c => (
                        <div
                          key={c.id}
                          className={`p-3 cursor-pointer hover:bg-muted/50 ${selectedExistingId === c.id ? 'bg-primary/10 border-l-2 border-primary' : ''}`}
                          onClick={() => setSelectedExistingId(c.id)}
                        >
                          <p className="font-medium">{c.name}</p>
                          <p className="text-xs text-muted-foreground">{[c.email, c.phone].filter(Boolean).join(' - ')}</p>
                        </div>
                      ))}
                    </div>
                  )}
                  {selectedExistingId && (
                    <div className="space-y-2 pt-2">
                      <Label>Pledge Amount ({currency})</Label>
                      <FormattedNumberInput value={existingPledgeAmount} onChange={(v) => setExistingPledgeAmount(v)} placeholder="e.g. 20,000" />
                    </div>
                  )}
                </div>
              </div>
            </TabsContent>
          </Tabs>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setAddContributorDialogOpen(false); resetAddForm(); }}>Cancel</Button>
            <Button onClick={handleAddContributor} disabled={isSubmitting || (addMode === 'existing' && !selectedExistingId)}>
              {isSubmitting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Adding...</> : 'Add Contributor'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Record Payment Dialog */}
      <Dialog open={paymentDialogOpen} onOpenChange={(open) => { setPaymentDialogOpen(open); if (!open) setPaymentTarget(null); }}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Record Payment for {paymentTarget?.contributor?.name}</DialogTitle></DialogHeader>
          {paymentTarget && (
            <div className="text-sm text-muted-foreground mb-2">
              Pledge: {formatPrice(paymentTarget.pledge_amount)} - Paid so far: {formatPrice(paymentTarget.total_paid)} - Balance: {formatPrice(paymentTarget.balance)}
            </div>
          )}
          <div className="space-y-4 py-2">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Amount ({currency}) *</Label>
                <FormattedNumberInput value={payment.amount} onChange={(v) => setPayment(p => ({ ...p, amount: v }))} placeholder="0" />
              </div>
              <div className="space-y-2">
                <Label>Payment Method</Label>
                <Select value={payment.payment_method} onValueChange={(v) => setPayment(p => ({ ...p, payment_method: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{PAYMENT_METHODS.map(m => <SelectItem key={m.id} value={m.id}>{m.name}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-2"><Label>Payment Reference</Label><Input value={payment.payment_reference} onChange={(e) => setPayment(p => ({ ...p, payment_reference: e.target.value }))} placeholder="Transaction ID..." /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setPaymentDialogOpen(false); setPaymentTarget(null); }}>Cancel</Button>
            <Button onClick={handleRecordPayment} disabled={isSubmitting}>
              {isSubmitting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</> : 'Record Payment'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Edit Contributor Dialog */}
      <Dialog open={editPledgeDialogOpen} onOpenChange={setEditPledgeDialogOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Edit {editTarget?.contributor?.global_name || editTarget?.contributor?.name}</DialogTitle></DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Display name for this event <span className="text-xs text-muted-foreground">(optional)</span></Label>
              <Input
                value={editDisplayName}
                onChange={(e) => setEditDisplayName(e.target.value)}
                placeholder={editTarget?.contributor?.global_name || editTarget?.contributor?.name || 'e.g. Mr & Mrs Mpinzile'}
                autoComplete="off"
              />
              <p className="text-[11px] text-muted-foreground">
                Shown only on this event. Leave blank to use the address-book name
                {editTarget?.contributor?.global_name ? ` (${editTarget.contributor.global_name})` : ''}.
                Changing only the name will not send an SMS.
              </p>
            </div>
            <div className="space-y-2">
              <Label>Pledge Amount ({currency})</Label>
              <FormattedNumberInput value={editAmount} onChange={(v) => setEditAmount(v)} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Secondary phone <span className="text-xs text-muted-foreground">(optional)</span></Label>
                <Input
                  value={editSecondaryPhone}
                  onChange={(e) => setEditSecondaryPhone(e.target.value)}
                  placeholder="+255..."
                  autoComplete="off"
                />
              </div>
              <div className="space-y-2">
                <Label>Notify</Label>
                <Select value={editNotifyTarget} onValueChange={(v) => setEditNotifyTarget(v as any)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="primary">Primary only</SelectItem>
                    <SelectItem value="secondary">Secondary only</SelectItem>
                    <SelectItem value="both">Both numbers</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <p className="text-xs text-muted-foreground">
              The secondary number is used only for contribution notifications. It is never linked to a Nuru account or used elsewhere.
            </p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditPledgeDialogOpen(false)}>Cancel</Button>
            <Button onClick={handleUpdatePledge} disabled={isSubmitting}>
              {isSubmitting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</> : 'Save Changes'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Payment History Dialog */}
      <Dialog open={historyDialogOpen} onOpenChange={setHistoryDialogOpen}>
        <DialogContent className="max-w-lg max-h-[80vh] overflow-y-auto">
          <DialogHeader><DialogTitle>{historyData?.contributor?.name} — Payment History</DialogTitle></DialogHeader>
          {historyLoading ? (
            <div className="flex justify-center p-8"><Loader2 className="w-6 h-6 animate-spin" /></div>
          ) : historyData ? (
            <div className="space-y-4 py-2">
              <div className="grid grid-cols-3 gap-3">
                <div className="p-3 rounded-lg bg-yellow-50 text-center">
                  <p className="text-xs text-muted-foreground">Pledged</p>
                  <p className="font-bold text-yellow-700">{formatPrice(historyData.pledge_amount)}</p>
                </div>
                <div className="p-3 rounded-lg bg-green-50 text-center">
                  <p className="text-xs text-muted-foreground">Paid</p>
                  <p className="font-bold text-green-700">{formatPrice(historyData.total_paid)}</p>
                </div>
                <div className="p-3 rounded-lg bg-red-50 text-center">
                  <p className="text-xs text-muted-foreground">Balance</p>
                  <p className="font-bold text-red-700">{formatPrice(Math.max(0, historyData.pledge_amount - historyData.total_paid))}</p>
                </div>
              </div>
              <div className="divide-y border rounded-lg">
                {historyData.payments?.length === 0 ? (
                  <div className="p-4 text-center text-muted-foreground text-sm">No payments recorded yet</div>
                ) : (
                  historyData.payments?.map((p: any) => (
                    <div key={p.id} className="p-3 flex items-center justify-between">
                      <div>
                        <div className="flex items-center gap-2">
                          <Badge className={p.confirmation_status === 'pending' ? 'bg-amber-100 text-amber-800' : 'bg-green-100 text-green-800'}>
                            {p.confirmation_status === 'pending' ? 'Pending' : 'Payment'}
                          </Badge>
                          {p.payment_method && <span className="text-xs text-muted-foreground capitalize">{p.payment_method.replace('_', ' ')}</span>}
                        </div>
                        <p className="text-xs text-muted-foreground mt-1">{formatDateMedium(p.created_at)}</p>
                        {p.payment_reference && <p className="text-xs text-muted-foreground">Ref: {p.payment_reference}</p>}
                        {p.recorded_by_name && <p className="text-xs text-muted-foreground">By: {p.recorded_by_name}</p>}
                      </div>
                      <div className="flex items-center gap-2">
                        <p className="font-bold text-green-600">{formatPrice(p.amount)}</p>
                        {isCreator && (
                          <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive hover:text-destructive" onClick={() => handleDeleteTransaction(p.id)}>
                            <Trash className="w-3.5 h-3.5" />
                          </Button>
                        )}
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>
          ) : (
            <div className="p-4 text-center text-muted-foreground">Failed to load history</div>
          )}
        </DialogContent>
      </Dialog>

      {/* Send Thank You Dialog */}
      <Dialog open={thankYouDialogOpen} onOpenChange={(open) => { setThankYouDialogOpen(open); if (!open) setThankYouTarget(null); }}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Send Thank You to {thankYouTarget?.contributor?.name}</DialogTitle></DialogHeader>
          <div className="space-y-4 py-2">
            <p className="text-sm text-muted-foreground">
              A thank you SMS will be sent to {thankYouTarget?.contributor?.phone || 'the contributor'}.
            </p>
            <div className="space-y-2">
              <Label>Custom Message (optional)</Label>
              <Textarea
                value={thankYouMessage}
                onChange={(e) => setThankYouMessage(e.target.value)}
                placeholder="Add a personal thank you message..."
                rows={3}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setThankYouDialogOpen(false)}>Cancel</Button>
            <Button 
              onClick={async () => {
                if (!thankYouTarget) return;
                setIsSubmitting(true);
                try {
                  const { contributorsApi } = await import('@/lib/api/contributors');
                  const res = await contributorsApi.sendThankYou(eventId, thankYouTarget.id, { custom_message: thankYouMessage || undefined });
                  if (res.success) {
                    toast.success('Thank you sent!');
                    setThankYouDialogOpen(false);
                    setThankYouTarget(null);
                  } else {
                    toast.error(res.message || 'Failed to send');
                  }
                } catch (err: any) {
                  showCaughtError(err, 'Failed to send thank you');
                } finally {
                  setIsSubmitting(false);
                }
              }}
              disabled={isSubmitting}
            >
              {isSubmitting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Sending...</> : <><Send className="w-4 h-4 mr-2" />Send Thank You</>}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Bulk Upload Dialog */}
      <Dialog open={bulkDialogOpen} onOpenChange={(open) => { setBulkDialogOpen(open); if (!open) resetBulkForm(); }}>
        <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
          <DialogHeader><DialogTitle>Bulk Upload Contributors</DialogTitle></DialogHeader>
          <div className="space-y-4 py-2">
            {/* Mode Selection */}
            <div className="space-y-2">
              <Label>Upload Mode</Label>
              <Select value={bulkMode} onValueChange={(v) => setBulkMode(v as 'targets' | 'contributions')}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="targets">Set Pledge Targets</SelectItem>
                  <SelectItem value="contributions">Record Contributions</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                {bulkMode === 'targets' 
                  ? 'Set or update pledge targets for multiple contributors at once.' 
                  : 'Record actual payments/contributions for multiple contributors at once.'}
              </p>
            </div>

            {/* Sample Download */}
            <div className="flex items-center gap-3 p-3 rounded-lg border border-dashed bg-muted/30">
              <FileSpreadsheet className="w-8 h-8 text-primary shrink-0" />
              <div className="flex-1">
                <p className="text-sm font-medium">Download Sample Template</p>
                <p className="text-xs text-muted-foreground">Columns: S/N, Name, Phone (255 format), Amount</p>
              </div>
              <Button variant="outline" size="sm" onClick={downloadSampleXlsx}>
                <Download className="w-4 h-4 mr-1" />Template
              </Button>
            </div>

            {/* File Input */}
            <div className="space-y-2">
              <Label>Upload File (.xlsx, .xls, .csv)</Label>
              <input
                ref={bulkFileRef}
                type="file"
                accept=".xlsx,.xls,.csv"
                onChange={handleBulkFileChange}
                className="block w-full text-sm text-muted-foreground file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-medium file:bg-primary file:text-primary-foreground hover:file:bg-primary/90 cursor-pointer"
              />
            </div>

            {/* Parse Results */}
            {bulkFileName && (
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-green-600" />
                  <span className="text-sm font-medium">{bulkFileName}</span>
                  <Badge variant="secondary">{bulkRows.length} valid rows</Badge>
                </div>
                {bulkRows.length > 0 && (
                  <div className="border rounded-lg overflow-hidden max-h-40 overflow-y-auto">
                    <table className="w-full text-xs">
                      <thead><tr className="bg-muted/50 border-b">
                        <th className="p-2 text-left">#</th>
                        <th className="p-2 text-left">Name</th>
                        <th className="p-2 text-left">Phone</th>
                        <th className="p-2 text-right">Amount</th>
                      </tr></thead>
                      <tbody className="divide-y">
                        {bulkRows.slice(0, 20).map((r, i) => (
                          <tr key={i}><td className="p-2">{i + 1}</td><td className="p-2">{r.name}</td><td className="p-2">{r.phone}</td><td className="p-2 text-right">{formatPrice(r.amount)}</td></tr>
                        ))}
                        {bulkRows.length > 20 && <tr><td colSpan={4} className="p-2 text-center text-muted-foreground">...and {bulkRows.length - 20} more</td></tr>}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {/* Parse Errors */}
            {bulkErrors.length > 0 && (
              <div className="border border-destructive/30 rounded-lg p-3 bg-destructive/5 space-y-1 max-h-32 overflow-y-auto">
                <div className="flex items-center gap-2 text-destructive text-sm font-medium"><AlertCircle className="w-4 h-4" />Parsing Issues</div>
                {bulkErrors.map((err, i) => <p key={i} className="text-xs text-destructive/80">• {err}</p>)}
              </div>
            )}

            {/* SMS Checkbox */}
            <div className="flex items-start gap-3 p-3 rounded-lg border bg-muted/20">
              <Checkbox
                id="bulk-sms"
                checked={bulkSendSms}
                onCheckedChange={(v) => setBulkSendSms(v === true)}
                className="mt-0.5"
              />
              <div>
                <label htmlFor="bulk-sms" className="text-sm font-medium cursor-pointer">Send SMS notifications</label>
                <p className="text-xs text-muted-foreground">
                  {bulkSendSms 
                    ? '⚠️ SMS will be sent to each contributor. This may take longer for large uploads.' 
                    : 'No SMS will be sent. You can notify contributors later individually.'}
                </p>
              </div>
            </div>

            {/* Upload Result */}
            {bulkResult && (
              <div className="border rounded-lg p-3 bg-green-50 space-y-1">
                <div className="flex items-center gap-2 text-green-700 text-sm font-medium"><CheckCircle2 className="w-4 h-4" />Upload Complete</div>
                <p className="text-xs text-green-600">{bulkResult.processed} contributors processed, {bulkResult.errors_count} errors</p>
                {bulkResult.summary && (
                  <p className="text-xs text-green-700/80">
                    {(bulkResult.summary.inserted ?? 0)} new · {(bulkResult.summary.updated ?? 0)} updated
                    {(bulkResult.summary.duplicates_in_file ?? 0) > 0 && (
                      <> · <span className="text-amber-700">{bulkResult.summary.duplicates_in_file} duplicate{(bulkResult.summary.duplicates_in_file ?? 0) > 1 ? 's' : ''} in file (merged)</span></>
                    )}
                  </p>
                )}
                {bulkResult.summary && (bulkResult.summary.notified !== undefined || bulkResult.summary.notify_failed !== undefined) && (
                  <p className={`text-xs ${(bulkResult.summary.notify_failed || 0) > 0 ? 'text-amber-700' : 'text-green-700/80'}`}>
                    Notifications: {bulkResult.summary.notified ?? 0} sent · {bulkResult.summary.notify_failed ?? 0} failed
                    {(bulkResult.summary.notify_failed || 0) > 0 && ' — open Background Tasks for details'}
                  </p>
                )}
                {bulkResult.errors.length > 0 && (
                  <div className="mt-2 space-y-1 max-h-24 overflow-y-auto">
                    {bulkResult.errors.map((e, i) => <p key={i} className="text-xs text-destructive">Row {e.row}: {e.message}</p>)}
                  </div>
                )}
              </div>
            )}
            <DismissibleHint />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setBulkDialogOpen(false); resetBulkForm(); }}>
              {bulkUploading ? 'Dismiss (keep running)' : bulkResult ? 'Close' : 'Cancel'}
            </Button>
            {!bulkResult && (
              <Button onClick={handleBulkUpload} disabled={bulkUploading || bulkRows.length === 0}>
                {bulkUploading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Uploading...</> : <><Upload className="w-4 h-4 mr-2" />Upload {bulkRows.length} Contributors</>}
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Batch Add as Guests Confirmation Dialog */}
      <Dialog open={guestBatchDialogOpen} onOpenChange={setGuestBatchDialogOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Add Contributors as Guests</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              You are about to add <span className="font-semibold text-foreground">{selectedForGuest.length}</span> contributor{selectedForGuest.length > 1 ? 's' : ''} to the guest list. Duplicate entries will be automatically skipped.
            </p>

            <div className="flex items-start gap-3 p-3 rounded-lg border bg-muted/20">
              <Checkbox
                id="guest-batch-sms"
                checked={guestBatchSendSms}
                onCheckedChange={(v) => setGuestBatchSendSms(v === true)}
                className="mt-0.5"
              />
              <div>
                <label htmlFor="guest-batch-sms" className="text-sm font-medium cursor-pointer">Send SMS notifications</label>
                <p className="text-xs text-muted-foreground">
                  {guestBatchSendSms 
                    ? '⚠️ An invitation SMS will be sent to each contributor. This may take longer for large batches.' 
                    : 'No SMS will be sent. Guests will be added silently.'}
                </p>
              </div>
            </div>

            {selectedForGuest.length > 10 && (
              <div className="flex items-start gap-2 p-3 rounded-lg border border-amber-200 bg-amber-50/50">
                <AlertCircle className="w-4 h-4 text-amber-600 mt-0.5 flex-shrink-0" />
                <p className="text-xs text-amber-700">
                  You have selected a large number of contributors. Processing may take a moment{guestBatchSendSms ? ', especially with SMS notifications enabled' : ''}.
                </p>
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setGuestBatchDialogOpen(false)}>Cancel</Button>
            <Button onClick={handleBatchAddAsGuests} disabled={addingAsGuests}>
              {addingAsGuests ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Adding...</> : <><UserCheck className="w-4 h-4 mr-2" />Add {selectedForGuest.length} as Guest{selectedForGuest.length > 1 ? 's' : ''}</>}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Date Range Picker Dialog */}
      <Dialog open={reportDateDialogOpen} onOpenChange={setReportDateDialogOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Select Report Period</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-xs text-muted-foreground">
              Choose a date range to filter payments. Leave empty for all-time data.
            </p>
            <div className="space-y-3">
              <div>
                <Label className="text-xs">From</Label>
                <Popover open={reportFromOpen} onOpenChange={setReportFromOpen}>
                  <PopoverTrigger asChild>
                    <Button variant="outline" className={cn("w-full justify-start text-left font-normal", !reportDateFrom && "text-muted-foreground")}>
                      <CalendarIcon className="mr-2 h-4 w-4" />
                      {reportDateFrom ? format(reportDateFrom, 'dd MMM yyyy') : 'Start date'}
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0" align="start">
                    <Calendar mode="single" selected={reportDateFrom} onSelect={d => { setReportDateFrom(d); setReportFromOpen(false); }} initialFocus className="p-3 pointer-events-auto" />
                  </PopoverContent>
                </Popover>
              </div>
              <div>
                <Label className="text-xs">To</Label>
                <Popover open={reportToOpen} onOpenChange={setReportToOpen}>
                  <PopoverTrigger asChild>
                    <Button variant="outline" className={cn("w-full justify-start text-left font-normal", !reportDateTo && "text-muted-foreground")}>
                      <CalendarIcon className="mr-2 h-4 w-4" />
                      {reportDateTo ? format(reportDateTo, 'dd MMM yyyy') : 'End date'}
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0" align="start">
                    <Calendar mode="single" selected={reportDateTo} onSelect={d => { setReportDateTo(d); setReportToOpen(false); }} initialFocus className="p-3 pointer-events-auto" />
                  </PopoverContent>
                </Popover>
              </div>
            </div>
            {reportDateFrom && reportDateTo && reportDateFrom > reportDateTo && (
              <p className="text-xs text-destructive">Start date must be before end date</p>
            )}
            <p className="text-[11px] text-muted-foreground italic">
              ⚠ Filtered reports show only payments within the selected period. Overall balances may not match full event totals.
            </p>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReportDateDialogOpen(false)}>Cancel</Button>
            <Button
              onClick={handleDownloadReport}
              disabled={reportLoading || (reportDateFrom && reportDateTo && reportDateFrom > reportDateTo ? true : false)}
            >
              {reportLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Generating...</> : <><Download className="w-4 h-4 mr-2" />Generate Report</>}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Report Preview */}
      <ReportPreviewDialog
        open={reportPreviewOpen}
        onOpenChange={setReportPreviewOpen}
        title="Contribution Report"
        html={reportHtml}
        onDownloadExcel={handleDownloadExcel}
      />
    </div>
  );
};

export default EventContributions;
