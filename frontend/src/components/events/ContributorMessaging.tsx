/**
 * ContributorMessaging - Premium messaging section for sending targeted SMS to contributors
 * Supports: No Contribution, Partial Contribution, Completed Contribution cases
 */
import { useState, useMemo, useEffect } from 'react';
import { Send, Users, Loader2, Eye, Edit3, CheckCircle2, Clock, AlertCircle, Search } from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import ChatIcon from '@/assets/icons/chat-icon.svg';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';

import { ScrollArea } from '@/components/ui/scroll-area';
import { Separator } from '@/components/ui/separator';
import { toast } from 'sonner';
import { contributorsApi } from '@/lib/api/contributors';
import { showCaughtError } from '@/lib/api';
import { useCurrency } from '@/hooks/useCurrency';
import type { EventContributorSummary } from '@/lib/api/contributors';
import { useLanguage } from '@/lib/i18n/LanguageContext';

interface ContributorMessagingProps {
  eventId: string;
  eventTitle?: string;
  eventContributors: EventContributorSummary[];
  paymentInfo?: string;
  /** Per-event default fallback contact phone (event.reminder_contact_phone) */
  defaultContactPhone?: string;
}

type ContributorCase = 'no_contribution' | 'partial' | 'completed' | 'not_pledged';

interface MessageTemplate {
  id: string;
  case: ContributorCase;
  label: string;
  template: string;
}

const DEFAULT_TEMPLATES: MessageTemplate[] = [
  {
    id: 'no_contribution_default',
    case: 'no_contribution',
    label: 'Reminder · No Contribution',
    template: `{event_title}
Habari {name},
Tunakukumbusha kutoa mchango wako kwa ajili ya {event_name}.
Namba ya malipo: {payment}`,
  },
  {
    id: 'partial_default',
    case: 'partial',
    label: 'Reminder · Partial Contribution',
    template: `{event_title}
Habari {name},
Tunakukumbusha kumalizia mchango wako kwa ajili ya {event_name}.
Namba ya malipo: {payment}`,
  },
  {
    id: 'completed_default',
    case: 'completed',
    label: 'Thank You · Completed',
    template: `{event_title}
Habari {name},
Asante kwa kukamilisha mchango wako kwa ajili ya {event_name}. Tunathamini sana ushiriki wako.`,
  },
  {
    id: 'not_pledged_default',
    case: 'not_pledged',
    label: 'Invite · Not Pledged',
    template: `{event_title}
Habari {name},
Tunakukaribisha kushiriki katika {event_name}. Tafadhali toa ahadi yako ya mchango.
Namba ya malipo: {payment}`,
  },
];

const CASE_CONFIG: Record<ContributorCase, { label: string; description: string; icon: React.ReactNode; color: string }> = {
  not_pledged: {
    label: 'Not Pledged',
    description: 'Contributors added without a pledge yet',
    icon: <Users className="w-4 h-4" />,
    color: 'text-muted-foreground',
  },
  no_contribution: {
    label: 'No Contribution',
    description: 'Contributors with pledges but no payment yet',
    icon: <AlertCircle className="w-4 h-4" />,
    color: 'text-destructive',
  },
  partial: {
    label: 'Partial Contribution',
    description: 'Contributors who have paid but not completed their pledge',
    icon: <Clock className="w-4 h-4" />,
    color: 'text-yellow-600',
  },
  completed: {
    label: 'Completed',
    description: 'Contributors who have fully paid their pledge',
    icon: <CheckCircle2 className="w-4 h-4" />,
    color: 'text-green-600',
  },
};

const ContributorMessaging = ({ eventId, eventTitle = '', eventContributors, paymentInfo = '', defaultContactPhone = '' }: ContributorMessagingProps) => {
  const { format: formatPrice } = useCurrency();
  const { t } = useLanguage();
  const [selectedCase, setSelectedCase] = useState<ContributorCase>('no_contribution');
  const [messageText, setMessageText] = useState('');
  const [isEditing, setIsEditing] = useState(false);
  const [previewOpen, setPreviewOpen] = useState(false);
  const [sending, setSending] = useState(false);
  const [sendResult, setSendResult] = useState<{ sent: number; failed: number; queued: number; errors: string[]; batch_id?: string; mode?: string; idempotent_replay?: boolean } | null>(null);
  const [resultOpen, setResultOpen] = useState(false);
  const [customPaymentInfo, setCustomPaymentInfo] = useState(paymentInfo);
  const [contactPhoneOverride, setContactPhoneOverride] = useState(defaultContactPhone);
  const [searchQuery, setSearchQuery] = useState('');
  // Explicit selection model. `null` = "all in current filter selected"
  // (default when the user hasn't manually deselected anything).
  const [selectedIds, setSelectedIds] = useState<Set<string> | null>(null);

  // Saved per-event customisations, keyed by case_type.
  const [savedTemplates, setSavedTemplates] = useState<Partial<Record<ContributorCase, {
    message_template: string | null;
    payment_info: string | null;
    contact_phone: string | null;
  }>>>({});
  const [templatesLoaded, setTemplatesLoaded] = useState(false);
  const [savingTemplate, setSavingTemplate] = useState(false);

  // Filter contributors by case
  const caseFiltered = useMemo(() => {
    return eventContributors.filter(ec => {
      const pledge = ec.pledge_amount || 0;
      const paid = ec.total_paid || 0;
      const hasPhone = !!ec.contributor?.phone;

      if (!hasPhone) return false;

      switch (selectedCase) {
        case 'not_pledged':
          return pledge === 0 && paid === 0;
        case 'no_contribution':
          return pledge > 0 && paid === 0;
        case 'partial':
          return pledge > 0 && paid > 0 && paid < pledge;
        case 'completed':
          return pledge > 0 && paid >= pledge;
        default:
          return false;
      }
    }).sort((a, b) => (a.contributor?.name || '').localeCompare(b.contributor?.name || ''));
  }, [eventContributors, selectedCase]);

  // Search filter
  const filteredContributors = useMemo(() => {
    if (!searchQuery.trim()) return caseFiltered;
    const q = searchQuery.toLowerCase();
    return caseFiltered.filter(ec => 
      (ec.contributor?.name || '').toLowerCase().includes(q) ||
      (ec.contributor?.phone || '').includes(q)
    );
  }, [caseFiltered, searchQuery]);

  // Selected contributors to send to. `null` = everyone in current filter.
  const sendTargets = useMemo(() => {
    if (selectedIds === null) return filteredContributors;
    return filteredContributors.filter(ec => selectedIds.has(ec.id));
  }, [filteredContributors, selectedIds]);

  const isRowSelected = (id: string) =>
    selectedIds === null ? true : selectedIds.has(id);

  const toggleSelect = (id: string) => {
    setSelectedIds(prev => {
      // First manual toggle: materialise the current "all" state, then flip.
      const base = prev === null
        ? new Set(filteredContributors.map(ec => ec.id))
        : new Set(prev);
      if (base.has(id)) base.delete(id);
      else base.add(id);
      return base;
    });
  };

  const allSelected = selectedIds === null
    || (filteredContributors.length > 0 && filteredContributors.every(ec => selectedIds.has(ec.id)));

  const toggleSelectAll = () => {
    if (allSelected) {
      // Deselect everything explicitly.
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filteredContributors.map(ec => ec.id)));
    }
  };

  // Get default template for selected case
  const defaultTemplate = DEFAULT_TEMPLATES.find(t => t.case === selectedCase);

  // Apply a case's saved values (or fall back to defaults) to the form fields.
  const applyCaseValues = (caseKey: ContributorCase, saved = savedTemplates) => {
    const def = DEFAULT_TEMPLATES.find(t => t.case === caseKey);
    const s = saved[caseKey];
    setMessageText(s?.message_template ?? def?.template ?? '');
    if (s?.payment_info != null) setCustomPaymentInfo(s.payment_info);
    if (s?.contact_phone != null) setContactPhoneOverride(s.contact_phone);
  };

  // Load saved templates once per event
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await contributorsApi.getMessagingTemplates(eventId);
        if (cancelled) return;
        const tpls = (res?.data?.templates || {}) as typeof savedTemplates;
        setSavedTemplates(tpls);
        applyCaseValues(selectedCase, tpls);
      } catch { /* silent */ }
      finally { if (!cancelled) setTemplatesLoaded(true); }
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [eventId]);

  // Set template when case changes — prefer saved, else default
  const handleCaseChange = (value: ContributorCase) => {
    setSelectedCase(value);
    applyCaseValues(value);
    setIsEditing(false);
    setSendResult(null);
    setSearchQuery('');
    setSelectedIds(null);
  };

  // Initialize message on first render (default; replaced once saved templates load).
  useEffect(() => {
    if (defaultTemplate && !templatesLoaded) {
      setMessageText(defaultTemplate.template);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Manual "Save" — persists the current case's customisation without sending.
  const handleSaveTemplate = async () => {
    setSavingTemplate(true);
    try {
      const res = await contributorsApi.saveMessagingTemplate(eventId, selectedCase, {
        message_template: messageText,
        payment_info: customPaymentInfo,
        contact_phone: contactPhoneOverride,
      });
      if (res.success) {
        setSavedTemplates(prev => ({
          ...prev,
          [selectedCase]: {
            message_template: res.data.message_template,
            payment_info: res.data.payment_info,
            contact_phone: res.data.contact_phone,
          },
        }));
        toast.success('Template saved for this event');
      }
    } catch (err) {
      showCaughtError(err, 'Failed to save template');
    } finally {
      setSavingTemplate(false);
    }
  };

  // Resolve template variables for preview
  const resolveTemplate = (template: string, contributor: EventContributorSummary): string => {
    const name = contributor.contributor?.name || 'Contributor';
    let resolved = template
      .replace(/\{name\}/g, name)
      .replace(/\{event_name\}/g, eventTitle)
      .replace(/\{event_title\}/g, (eventTitle || '').toUpperCase());

    // Handle {payment} - if not present in template, payment line is already excluded
    if (resolved.includes('{payment}')) {
      if (customPaymentInfo) {
        resolved = resolved.replace(/\{payment\}/g, customPaymentInfo);
      } else {
        // Remove the entire line containing {payment}
        resolved = resolved.split('\n').filter(line => !line.includes('{payment}')).join('\n');
      }
    }

    return resolved.trim();
  };

  const handleSend = async () => {
    if (sendTargets.length === 0) {
      toast.error('No contributors selected to message');
      return;
    }

    if (!messageText.trim()) {
      toast.error('Message template cannot be empty');
      return;
    }

    setSending(true);
    setSendResult(null);

    try {
      const response = await contributorsApi.sendBulkReminder(eventId, {
        case_type: selectedCase,
        message_template: messageText,
        payment_info: customPaymentInfo || undefined,
        contact_phone: contactPhoneOverride.trim() || undefined,
        contributor_ids: sendTargets.map(ec => ec.id),
      });

      if (response.success) {
        const raw: any = response.data || {};
        const skippedInvalid = Array.isArray(raw.skipped_invalid_phone)
          ? raw.skipped_invalid_phone
          : (typeof raw.skipped_invalid_phone === 'number' ? [] : []);
        const normalized = {
          sent: typeof raw.sent === 'number' ? raw.sent : 0,
          failed: typeof raw.failed === 'number' ? raw.failed : 0,
          queued: typeof raw.queued === 'number' ? raw.queued : 0,
          errors: Array.isArray(raw.errors) ? raw.errors : skippedInvalid.map((n: string) => `Invalid phone: ${n}`),
          batch_id: raw.batch_id,
          mode: raw.mode,
          idempotent_replay: !!raw.idempotent_replay,
        };
        setSendResult(normalized);
        setResultOpen(true);
        if (normalized.idempotent_replay) {
          toast.info('Already sent to these contributors in the last hour · skipped to avoid duplicates.');
        } else if (normalized.queued > 0 && normalized.sent === 0 && normalized.failed === 0) {
          toast.success(`Queued ${normalized.queued} message${normalized.queued !== 1 ? 's' : ''} for delivery`);
        } else if (normalized.sent === 0 && normalized.failed === 0 && normalized.queued === 0) {
          toast.warning('No messages were sent. Check phone numbers or try again later.');
        } else if (normalized.failed === 0) {
          toast.success(`Messages sent to ${normalized.sent} contributor${normalized.sent !== 1 ? 's' : ''}`);
        } else {
          toast.warning(`Sent: ${normalized.sent}, Failed: ${normalized.failed}`);
        }
      } else {
        toast.error(response.message || 'Failed to send messages');
      }
    } catch (err) {
      showCaughtError(err, 'Failed to send messages');
    } finally {
      setSending(false);
    }
  };

  const caseConfig = CASE_CONFIG[selectedCase];
  const sampleContributor = sendTargets[0];
  

  return (
    <Card className="border-primary/20 overflow-hidden">
      <div className="bg-gradient-to-r from-primary/10 via-primary/5 to-transparent p-4 md:p-5 border-b border-primary/10">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-primary/15 flex items-center justify-center">
            <SvgIcon src={ChatIcon} alt={t("messages")} className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h3 className="font-semibold text-base">Contributor Messaging</h3>
            <p className="text-xs text-muted-foreground">Send targeted reminders based on contribution status</p>
          </div>
        </div>
      </div>

      <CardContent className="p-4 md:p-5 space-y-5">
        {/* Case Selector */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          {(Object.entries(CASE_CONFIG) as [ContributorCase, typeof CASE_CONFIG['no_contribution']][]).map(([key, config]) => {
            const count = eventContributors.filter(ec => {
              const pledge = ec.pledge_amount || 0;
              const paid = ec.total_paid || 0;
              const hasPhone = !!ec.contributor?.phone;
              if (!hasPhone) return false;
              if (key === 'not_pledged') return pledge === 0 && paid === 0;
              if (key === 'no_contribution') return pledge > 0 && paid === 0;
              if (key === 'partial') return pledge > 0 && paid > 0 && paid < pledge;
              if (key === 'completed') return pledge > 0 && paid >= pledge;
              return false;
            }).length;

            return (
              <button
                key={key}
                onClick={() => handleCaseChange(key)}
                className={`p-3 rounded-xl border-2 text-left transition-all duration-200 ${
                  selectedCase === key
                    ? 'border-primary bg-primary/5 shadow-sm'
                    : 'border-border hover:border-primary/30 hover:bg-muted/50'
                }`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <span className={config.color}>{config.icon}</span>
                  <span className="text-sm font-medium">{config.label}</span>
                </div>
                <div className="flex items-center justify-between">
                  <p className="text-xs text-muted-foreground">{config.description}</p>
                  <Badge variant="secondary" className="ml-2 text-xs">{count}</Badge>
                </div>
              </button>
            );
          })}
        </div>

        <Separator />

        {/* Search & Select Contributors */}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <Label className="text-xs font-medium">Select Recipients ({sendTargets.length} of {filteredContributors.length})</Label>
            <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={toggleSelectAll}>
              {allSelected && filteredContributors.length > 0 ? 'Deselect All' : 'Select All'}
            </Button>
          </div>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              placeholder="Search contributors..."
              className="pl-9 text-sm"
            />
          </div>
          {filteredContributors.length > 0 && (
            <ScrollArea className="h-[160px]">
              <div className="space-y-1">
                {filteredContributors.map(ec => {
                  const isSelected = isRowSelected(ec.id);
                  return (
                    <button
                      key={ec.id}
                      onClick={() => toggleSelect(ec.id)}
                      className={`w-full flex items-center justify-between py-2 px-3 rounded-lg text-left transition-colors ${
                        isSelected
                          ? 'bg-primary/10 border border-primary/20'
                          : 'opacity-60 hover:opacity-90'
                      }`}
                    >
                      <div className="flex items-center gap-2 min-w-0">
                        <Checkbox checked={isSelected} className="pointer-events-none" />
                        <div className="min-w-0">
                          <p className="text-sm font-medium truncate">{ec.contributor?.name}</p>
                          <p className="text-xs text-muted-foreground">{ec.contributor?.phone}</p>
                        </div>
                      </div>
                      <div className="text-right text-xs flex-shrink-0 ml-2">
                        <p>Pledged: {formatPrice(ec.pledge_amount)}</p>
                        <p>Paid: {formatPrice(ec.total_paid)}</p>
                      </div>
                    </button>
                  );
                })}
              </div>
            </ScrollArea>
          )}
        </div>

        <Separator />

        {/* Contact phone (per-send override; defaults to event default, then organiser phone) */}
        <div className="space-y-2">
          <Label className="text-xs font-medium">Contact phone shown in message</Label>
          <Input
            type="tel"
            value={contactPhoneOverride}
            onChange={e => setContactPhoneOverride(e.target.value)}
            placeholder={defaultContactPhone || 'e.g. 0712 345 678 - leave empty to use organiser phone'}
            className="text-sm"
          />
          <p className="text-[11px] text-muted-foreground">
            {defaultContactPhone
              ? `Defaults to the event's reminder contact (${defaultContactPhone}). Override here for this batch.`
              : 'Falls back to your account phone if left blank. Override here for this batch.'}
          </p>
        </div>

        {/* Payment Info */}
        <div className="space-y-2">
          <Label className="text-xs font-medium">Payment Information (used for {'{payment}'} variable)</Label>
          <Input
            value={customPaymentInfo}
            onChange={e => setCustomPaymentInfo(e.target.value)}
            placeholder="e.g. M-Pesa: 0712345678 (John Doe)"
            className="text-sm"
          />
          <p className="text-[11px] text-muted-foreground">
            Leave empty to omit the payment line from the message entirely.
          </p>
        </div>

        {/* Persistent save block — always visible so users can persist payment
            info / contact phone / template without entering edit mode. */}
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-dashed bg-muted/30 px-3 py-2">
          <div className="text-[11px] text-muted-foreground">
            {savedTemplates[selectedCase]
              ? 'Saved customisation in use for this case. Update and re-save anytime.'
              : 'Save these values so you do not have to retype them next time.'}
          </div>
          <Button
            variant="default"
            size="sm"
            className="text-xs gap-1"
            onClick={handleSaveTemplate}
            disabled={savingTemplate || !messageText.trim()}
          >
            {savingTemplate ? <Loader2 className="w-3 h-3 animate-spin" /> : null}
            Save for this event
          </Button>
        </div>

        {/* Message Template */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <Label className="text-xs font-medium">Message Template</Label>
            <Button
              variant="ghost"
              size="sm"
              className="h-7 text-xs gap-1"
              onClick={() => setIsEditing(!isEditing)}
            >
              <Edit3 className="w-3 h-3" />
              {isEditing ? 'Done Editing' : 'Customize'}
            </Button>
          </div>

          {isEditing ? (
            <div className="space-y-2">
              <Textarea
                value={messageText}
                onChange={e => setMessageText(e.target.value)}
                rows={8}
                className="text-sm font-mono leading-relaxed"
                placeholder="Write your message template..."
              />
              <div className="flex flex-wrap gap-1">
                <span className="text-[11px] text-muted-foreground">Variables:</span>
                {['{name}', '{event_name}', '{event_title}', '{payment}'].map(v => (
                  <Badge key={v} variant="outline" className="text-[10px] cursor-pointer hover:bg-primary/10"
                    onClick={() => setMessageText(prev => prev + ' ' + v)}
                  >
                    {v}
                  </Badge>
                ))}
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  className="text-xs"
                  onClick={() => {
                    if (defaultTemplate) setMessageText(defaultTemplate.template);
                  }}
                >
                  Reset to Default
                </Button>
                <Button
                  variant="default"
                  size="sm"
                  className="text-xs gap-1"
                  onClick={handleSaveTemplate}
                  disabled={savingTemplate || !messageText.trim()}
                >
                  {savingTemplate ? <Loader2 className="w-3 h-3 animate-spin" /> : null}
                  Save for this event
                </Button>
                {savedTemplates[selectedCase] && (
                  <span className="text-[11px] text-muted-foreground">
                    ✓ Saved customisation in use
                  </span>
                )}
              </div>
            </div>
          ) : (
            <div className="bg-muted/50 rounded-lg p-4 border">
              <pre className="text-sm whitespace-pre-wrap font-sans leading-relaxed text-foreground/80">
                {messageText || 'No template selected'}
              </pre>
            </div>
          )}
        </div>

        {/* Preview & Send */}
        <div className="flex flex-col sm:flex-row gap-3">
          <Button
            variant="outline"
            className="flex-1 gap-2"
            onClick={() => setPreviewOpen(true)}
            disabled={sendTargets.length === 0}
          >
            <Eye className="w-4 h-4" />
            Preview ({sendTargets.length} recipient{sendTargets.length !== 1 ? 's' : ''})
          </Button>
          <Button
            className="flex-1 gap-2"
            onClick={handleSend}
            disabled={sending || sendTargets.length === 0 || !messageText.trim()}
          >
            {sending ? (
              <><Loader2 className="w-4 h-4 animate-spin" />Sending...</>
            ) : (
              <><Send className="w-4 h-4" />Send to {sendTargets.length} Contributor{sendTargets.length !== 1 ? 's' : ''}</>
            )}
          </Button>
        </div>

        {sendTargets.length === 0 && (
          <p className="text-xs text-muted-foreground text-center italic">
            No contributors with phone numbers match this category.
          </p>
        )}
      </CardContent>

      {/* Preview Dialog */}
      <Dialog open={previewOpen} onOpenChange={setPreviewOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Eye className="w-5 h-5" />
              Message Preview
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Users className="w-4 h-4" />
              <span>{sendTargets.length} recipient{sendTargets.length !== 1 ? 's' : ''} ({caseConfig.label})</span>
            </div>

            {sampleContributor && (
              <div className="space-y-2">
                <Label className="text-xs">Sample message for: <strong>{sampleContributor.contributor?.name}</strong></Label>
                <div className="bg-muted/50 rounded-lg p-4 border">
                  <pre className="text-sm whitespace-pre-wrap font-sans leading-relaxed">
                    {resolveTemplate(messageText, sampleContributor)}
                  </pre>
                </div>
              </div>
            )}

            <Separator />

            <div>
              <Label className="text-xs mb-2 block">All recipients:</Label>
              <ScrollArea className="h-[200px]">
                <div className="space-y-1">
                  {sendTargets.map(ec => (
                    <div key={ec.id} className="flex items-center justify-between py-1.5 px-2 rounded hover:bg-muted/50">
                      <div>
                        <p className="text-sm font-medium">{ec.contributor?.name}</p>
                        <p className="text-xs text-muted-foreground">{ec.contributor?.phone}</p>
                      </div>
                      <div className="text-right text-xs">
                        <p>Pledged: {formatPrice(ec.pledge_amount)}</p>
                        <p>Paid: {formatPrice(ec.total_paid)}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </ScrollArea>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPreviewOpen(false)}>Close</Button>
            <Button onClick={() => { setPreviewOpen(false); handleSend(); }} disabled={sending}>
              <Send className="w-4 h-4 mr-2" />Confirm & Send
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Result Dialog */}
      <Dialog open={resultOpen} onOpenChange={setResultOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Send Results</DialogTitle>
          </DialogHeader>
          {sendResult && (
            <div className="space-y-3">
              {sendResult.idempotent_replay ? (
                <Card className="border-yellow-500/30 bg-yellow-500/5">
                  <CardContent className="p-3 text-center">
                    <p className="text-sm font-semibold text-yellow-700 dark:text-yellow-400">Duplicate batch skipped</p>
                    <p className="text-[11px] text-muted-foreground mt-1">
                      The same message was already sent to these contributors in the last hour. Wait a bit or change the recipients/message to send again.
                    </p>
                  </CardContent>
                </Card>
              ) : sendResult.queued > 0 && sendResult.sent === 0 && sendResult.failed === 0 ? (
                <Card>
                  <CardContent className="p-3 text-center">
                    <p className="text-2xl font-bold text-primary">{sendResult.queued}</p>
                    <p className="text-xs text-muted-foreground">Queued for delivery</p>
                    <p className="text-[10px] text-muted-foreground mt-1">Messages are sent in the background — recipients will receive them shortly.</p>
                  </CardContent>
                </Card>
              ) : (
              <div className="grid grid-cols-2 gap-3">
                <Card>
                  <CardContent className="p-3 text-center">
                    <p className="text-2xl font-bold text-green-600">{sendResult.sent}</p>
                    <p className="text-xs text-muted-foreground">Sent</p>
                  </CardContent>
                </Card>
                <Card>
                  <CardContent className="p-3 text-center">
                    <p className="text-2xl font-bold text-destructive">{sendResult.failed}</p>
                    <p className="text-xs text-muted-foreground">Failed</p>
                  </CardContent>
                </Card>
              </div>
              )}
              {(sendResult.errors?.length ?? 0) > 0 && (
                <div className="bg-destructive/5 rounded-lg p-3 border border-destructive/20">
                  <p className="text-xs font-medium text-destructive mb-1">Errors:</p>
                  {sendResult.errors.slice(0, 5).map((err, i) => (
                    <p key={i} className="text-xs text-destructive/80">{err}</p>
                  ))}
                  {sendResult.errors.length > 5 && (
                    <p className="text-xs text-muted-foreground mt-1">...and {sendResult.errors.length - 5} more</p>
                  )}
                </div>
              )}
            </div>
          )}
          <DialogFooter>
            <Button onClick={() => setResultOpen(false)}>Close</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
};

export default ContributorMessaging;
