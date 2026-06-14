import { useState, useEffect, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Checkbox } from '@/components/ui/checkbox';
import {
  ListOrdered, FileText, Plus, Trash2, GripVertical, Clock, User, Check,
  Edit2, Save, Loader2, Sparkles, Download, ChevronDown, ChevronUp,
  BookOpen, Lightbulb, Target, AlertCircle
} from 'lucide-react';
import { meetingDocsApi, AgendaItem, MeetingMinutesData } from '@/lib/api/meeting-documents';
import { showCaughtError } from '@/lib/api';
import { toast } from 'sonner';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import nuruLogoUrl from '@/assets/nuru-logo.png';

interface MeetingDocumentsProps {
  eventId: string;
  meetingId: string;
  meetingTitle: string;
  meetingDescription?: string;
  meetingDate: string;
  isCreator: boolean;
  eventName?: string;
}

const MeetingDocuments = ({ eventId, meetingId, meetingTitle, meetingDescription, meetingDate, isCreator, eventName }: MeetingDocumentsProps) => {
  const { t } = useLanguage();

  // Agenda state
  const [agendaItems, setAgendaItems] = useState<AgendaItem[]>([]);
  const [loadingAgenda, setLoadingAgenda] = useState(true);
  const [showAddAgenda, setShowAddAgenda] = useState(false);
  const [editingAgenda, setEditingAgenda] = useState<AgendaItem | null>(null);
  const [agendaTitle, setAgendaTitle] = useState('');
  const [agendaDesc, setAgendaDesc] = useState('');
  const [agendaDuration, setAgendaDuration] = useState('');
  const [savingAgenda, setSavingAgenda] = useState(false);

  // Minutes state
  const [minutes, setMinutes] = useState<MeetingMinutesData | null>(null);
  const [loadingMinutes, setLoadingMinutes] = useState(true);
  const [editingMinutes, setEditingMinutes] = useState(false);
  const [minutesContent, setMinutesContent] = useState('');
  const [minutesSummary, setMinutesSummary] = useState('');
  const [minutesDecisions, setMinutesDecisions] = useState('');
  const [minutesActions, setMinutesActions] = useState('');
  const [savingMinutes, setSavingMinutes] = useState(false);

  const loadAgenda = useCallback(async () => {
    try {
      const res = await meetingDocsApi.listAgenda(eventId, meetingId);
      if (res.success) setAgendaItems((res.data as AgendaItem[]) || []);
    } catch { /* silent */ }
    finally { setLoadingAgenda(false); }
  }, [eventId, meetingId]);

  const loadMinutes = useCallback(async () => {
    try {
      const res = await meetingDocsApi.getMinutes(eventId, meetingId);
      if (res.success && res.data) {
        const data = res.data as MeetingMinutesData;
        setMinutes(data);
        setMinutesContent(data.content || '');
        setMinutesSummary(data.summary || '');
        setMinutesDecisions(data.decisions || '');
        setMinutesActions(data.action_items || '');
      }
    } catch { /* silent */ }
    finally { setLoadingMinutes(false); }
  }, [eventId, meetingId]);

  useEffect(() => {
    loadAgenda();
    loadMinutes();
  }, [loadAgenda, loadMinutes]);

  const handleAddAgenda = async () => {
    if (!agendaTitle.trim()) return;
    setSavingAgenda(true);
    try {
      const res = await meetingDocsApi.createAgendaItem(eventId, meetingId, {
        title: agendaTitle.trim(),
        description: agendaDesc.trim() || undefined,
        duration_minutes: agendaDuration ? parseInt(agendaDuration) : undefined,
      });
      if (res.success) {
        toast.success(t('agenda_item_added'));
        setShowAddAgenda(false);
        setAgendaTitle(''); setAgendaDesc(''); setAgendaDuration('');
        loadAgenda();
      }
    } catch (err: any) { showCaughtError(err); }
    finally { setSavingAgenda(false); }
  };

  const handleUpdateAgenda = async () => {
    if (!editingAgenda || !agendaTitle.trim()) return;
    setSavingAgenda(true);
    try {
      const res = await meetingDocsApi.updateAgendaItem(eventId, meetingId, editingAgenda.id, {
        title: agendaTitle.trim(),
        description: agendaDesc.trim() || undefined,
        duration_minutes: agendaDuration ? parseInt(agendaDuration) : undefined,
      });
      if (res.success) {
        toast.success(t('agenda_item_updated'));
        setEditingAgenda(null);
        setAgendaTitle(''); setAgendaDesc(''); setAgendaDuration('');
        loadAgenda();
      }
    } catch (err: any) { showCaughtError(err); }
    finally { setSavingAgenda(false); }
  };

  const handleToggleComplete = async (item: AgendaItem) => {
    try {
      await meetingDocsApi.updateAgendaItem(eventId, meetingId, item.id, {
        is_completed: !item.is_completed,
      });
      loadAgenda();
    } catch (err: any) { showCaughtError(err); }
  };

  const handleDeleteAgenda = async (itemId: string) => {
    try {
      const res = await meetingDocsApi.deleteAgendaItem(eventId, meetingId, itemId);
      if (res.success) {
        toast.success(t('agenda_item_removed'));
        loadAgenda();
      }
    } catch (err: any) { showCaughtError(err); }
  };

  const handleSaveMinutes = async () => {
    if (!minutesContent.trim()) return;
    setSavingMinutes(true);
    try {
      const data = {
        content: minutesContent.trim(),
        summary: minutesSummary.trim() || undefined,
        decisions: minutesDecisions.trim() || undefined,
        action_items: minutesActions.trim() || undefined,
      };
      let res;
      if (minutes) {
        res = await meetingDocsApi.updateMinutes(eventId, meetingId, data);
      } else {
        res = await meetingDocsApi.createMinutes(eventId, meetingId, data);
      }
      if (res.success) {
        toast.success(t('minutes_saved'));
        setEditingMinutes(false);
        loadMinutes();
      }
    } catch (err: any) { showCaughtError(err); }
    finally { setSavingMinutes(false); }
  };

  const handlePrintPDF = () => {
    const printWindow = window.open('', '_blank');
    if (!printWindow) return;

    const totalDuration = agendaItems.reduce((sum, item) => sum + (item.duration_minutes || 0), 0);
    const completedItems = agendaItems.filter(i => i.is_completed).length;
    const logoAbsoluteUrl = (() => { try { return new URL(nuruLogoUrl, window.location.origin).href; } catch { return ''; } })();

    printWindow.document.write(`
      <!DOCTYPE html>
      <html>
      <head>
        <title>${meetingTitle} - Agenda & Minutes</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { font-family: Arial, sans-serif; color: #333; background: white; padding: 40px; }
          .accent-bar { width: 100%; height: 3px; background: #FF7145; margin-bottom: 20px; }
          .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 20px; padding-bottom: 16px; border-bottom: 1px solid #E8ECF2; }
          .brand { display: flex; flex-direction: column; align-items: flex-start; }
          .brand img { height: 40px; margin-bottom: 6px; }
          .brand .slogan { font-size: 11px; color: #9EADC2; font-style: italic; }
          .header-right { text-align: right; }
          .header-right h1 { font-size: 18px; margin: 0 0 4px 0; color: #0A1C40; }
          .header-right h2 { font-size: 12px; color: #6B7F9E; margin: 0; font-weight: normal; }
          .summary { display: flex; gap: 12px; margin-bottom: 24px; flex-wrap: wrap; }
          .metric-card { flex: 1; min-width: 100px; border: 1px solid #E8ECF2; border-radius: 6px; overflow: hidden; display: flex; }
          .metric-accent { width: 3px; flex-shrink: 0; }
          .metric-body { padding: 10px 12px; }
          .metric-label { font-size: 9px; color: #9EADC2; text-transform: uppercase; letter-spacing: 0.8px; }
          .metric-value { font-size: 16px; font-weight: bold; margin-top: 2px; color: #0A1C40; }
          .section-heading { display: flex; align-items: center; gap: 8px; margin: 24px 0 12px; }
          .section-heading .accent { width: 3px; height: 14px; background: #FF7145; border-radius: 1.5px; }
          .section-heading span { font-size: 10px; font-weight: bold; color: #3A4D6A; text-transform: uppercase; letter-spacing: 1.5px; }
          .agenda-item { display: flex; gap: 12px; padding: 12px 14px; margin-bottom: 6px; background: #F6F7F9; border-radius: 6px; border-left: 3px solid #6366f1; }
          .agenda-item.completed { border-left-color: #22C55E; opacity: 0.75; }
          .agenda-number { width: 24px; height: 24px; background: #6366f1; color: white; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700; flex-shrink: 0; }
          .agenda-item.completed .agenda-number { background: #22C55E; }
          .agenda-content h3 { font-size: 13px; font-weight: 600; margin-bottom: 3px; color: #0A1C40; }
          .agenda-content p { font-size: 11px; color: #6B7F9E; line-height: 1.5; }
          .agenda-meta { font-size: 10px; color: #9EADC2; margin-top: 4px; }
          .minutes-content { font-size: 13px; line-height: 1.8; color: #333; white-space: pre-wrap; }
          .highlight-box { border: 1px solid #E8ECF2; border-radius: 6px; padding: 14px 16px; margin-bottom: 12px; border-left: 3px solid; overflow: hidden; }
          .highlight-box h4 { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.8px; margin-bottom: 8px; }
          .highlight-box p { font-size: 12px; line-height: 1.7; color: #3A4D6A; white-space: pre-wrap; }
          .highlight-summary { background: #FFFBEB; border-left-color: #F59E0B; }
          .highlight-summary h4 { color: #F59E0B; }
          .highlight-decisions { background: #F0FDF4; border-left-color: #22C55E; }
          .highlight-decisions h4 { color: #22C55E; }
          .highlight-actions { background: #F0F5FF; border-left-color: #2471E7; }
          .highlight-actions h4 { color: #2471E7; }
          .footer { margin-top: 40px; padding-top: 12px; border-top: 1px solid #F0F2F5; display: flex; justify-content: space-between; font-size: 8px; color: #9EADC2; letter-spacing: 0.3px; }
          @media print { body { padding: 20px; } }
        </style>
      </head>
      <body>
        <div class="accent-bar"></div>
        <div class="header">
          <div class="brand">
            ${logoAbsoluteUrl ? `<img src="${logoAbsoluteUrl}" alt="Nuru" />` : ''}
            <span class="slogan">Plan Smarter</span>
          </div>
          <div class="header-right">
            <h1>Meeting Report</h1>
            ${eventName ? `<h2 style="font-size:13px;color:#3A4D6A;margin:0 0 2px 0;font-weight:600">${eventName}</h2>` : ''}
            <h2>${meetingTitle}</h2>
            ${meetingDescription ? `<p style="font-size:10px;color:#9EADC2;margin:4px 0 0 0;max-width:300px;line-height:1.4">${meetingDescription}</p>` : ''}
          </div>
        </div>

        <div class="summary">
          <div class="metric-card">
            <div class="metric-accent" style="background:#2471E7"></div>
            <div class="metric-body">
              <div class="metric-label">Date</div>
              <div class="metric-value" style="font-size:13px">${new Date(meetingDate).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })}</div>
            </div>
          </div>
          <div class="metric-card">
            <div class="metric-accent" style="background:#7C3AED"></div>
            <div class="metric-body">
              <div class="metric-label">Time</div>
              <div class="metric-value" style="font-size:13px">${new Date(meetingDate).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}</div>
            </div>
          </div>
          <div class="metric-card">
            <div class="metric-accent" style="background:#FF7145"></div>
            <div class="metric-body">
              <div class="metric-label">Agenda Items</div>
              <div class="metric-value">${agendaItems.length}</div>
            </div>
          </div>
          ${totalDuration > 0 ? `
          <div class="metric-card">
            <div class="metric-accent" style="background:#F59E0B"></div>
            <div class="metric-body">
              <div class="metric-label">Est. Duration</div>
              <div class="metric-value">${totalDuration} min</div>
            </div>
          </div>` : ''}
          <div class="metric-card">
            <div class="metric-accent" style="background:#22C55E"></div>
            <div class="metric-body">
              <div class="metric-label">Completed</div>
              <div class="metric-value" style="color:#22C55E">${completedItems}/${agendaItems.length}</div>
            </div>
          </div>
        </div>

        ${agendaItems.length > 0 ? `
        <div class="section-heading"><div class="accent"></div><span>Agenda</span></div>
        ${agendaItems.map((item, i) => `
          <div class="agenda-item ${item.is_completed ? 'completed' : ''}">
            <div class="agenda-number">${i + 1}</div>
            <div class="agenda-content">
              <h3>${item.title}${item.is_completed ? ' <span style="font-size:10px;color:#22C55E;font-weight:bold">✓ DONE</span>' : ''}</h3>
              ${item.description ? `<p>${item.description}</p>` : ''}
              <div class="agenda-meta">
                ${item.duration_minutes ? `⏱ ${item.duration_minutes} min` : ''}
                ${item.presenter ? ` - 👤 ${item.presenter.name}` : ''}
              </div>
            </div>
          </div>
        `).join('')}
        ` : ''}

        ${minutes ? `
        <div class="section-heading"><div class="accent"></div><span>Meeting Minutes</span></div>
        <div class="minutes-content">${minutes.content}</div>

        ${minutes.summary ? `
        <div class="highlight-box highlight-summary" style="margin-top:16px">
          <h4>Summary</h4>
          <p>${minutes.summary}</p>
        </div>` : ''}

        ${minutes.decisions ? `
        <div class="highlight-box highlight-decisions">
          <h4>Key Decisions</h4>
          <p>${minutes.decisions}</p>
        </div>` : ''}

        ${minutes.action_items ? `
        <div class="highlight-box highlight-actions">
          <h4>Action Items</h4>
          <p>${minutes.action_items}</p>
        </div>` : ''}
        ` : ''}

        <div class="footer">
          <span>Generated by Nuru Events Workspace &middot; &copy; ${new Date().getFullYear()} Nuru | SEWMR TECHNOLOGIES</span>
        </div>
      </body>
      </html>
    `);
    printWindow.document.close();
    setTimeout(() => printWindow.print(), 500);
  };

  const totalEstimatedDuration = agendaItems.reduce((sum, item) => sum + (item.duration_minutes || 0), 0);
  const completedCount = agendaItems.filter(i => i.is_completed).length;

  return (
    <div className="space-y-6">
      <Tabs defaultValue="agenda" className="w-full">
        <div className="flex items-center justify-between flex-wrap gap-3 mb-4">
          <TabsList className="rounded-xl">
            <TabsTrigger value="agenda" className="gap-1.5 rounded-lg">
              <ListOrdered className="w-4 h-4" /> {t('agenda')}
            </TabsTrigger>
            <TabsTrigger value="minutes" className="gap-1.5 rounded-lg">
              <FileText className="w-4 h-4" /> {t('minutes')}
            </TabsTrigger>
          </TabsList>

          <Button variant="outline" size="sm" className="gap-1.5 rounded-xl" onClick={handlePrintPDF}>
            <Download className="w-3.5 h-3.5" /> {t('export_pdf')}
          </Button>
        </div>

        {/* ── Agenda Tab ── */}
        <TabsContent value="agenda" className="space-y-4">
          {/* Stats bar */}
          {agendaItems.length > 0 && (
            <div className="flex items-center gap-4 text-sm">
              <Badge variant="outline" className="rounded-lg gap-1.5 px-3 py-1">
                <ListOrdered className="w-3.5 h-3.5" /> {agendaItems.length} {t('items')}
              </Badge>
              {totalEstimatedDuration > 0 && (
                <Badge variant="outline" className="rounded-lg gap-1.5 px-3 py-1">
                  <Clock className="w-3.5 h-3.5" /> {totalEstimatedDuration} {t('min_suffix')}
                </Badge>
              )}
              <Badge variant="outline" className={`rounded-lg gap-1.5 px-3 py-1 ${completedCount === agendaItems.length ? 'border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-800 dark:bg-emerald-950 dark:text-emerald-300' : ''}`}>
                <Check className="w-3.5 h-3.5" /> {completedCount}/{agendaItems.length}
              </Badge>
            </div>
          )}

          {loadingAgenda ? (
            <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 animate-spin text-muted-foreground" /></div>
          ) : agendaItems.length === 0 ? (
            <Card className="border-dashed border-2">
              <CardContent className="flex flex-col items-center justify-center py-16 text-center">
                <div className="w-16 h-16 bg-gradient-to-br from-primary/10 to-primary/5 rounded-2xl flex items-center justify-center mb-4">
                  <ListOrdered className="w-8 h-8 text-primary" />
                </div>
                <h4 className="font-bold text-lg mb-1">{t('no_agenda_yet')}</h4>
                <p className="text-muted-foreground text-sm max-w-sm">{t('no_agenda_desc')}</p>
                {isCreator && (
                  <Button className="mt-4 gap-2 rounded-xl" onClick={() => setShowAddAgenda(true)}>
                    <Plus className="w-4 h-4" /> {t('add_agenda_item')}
                  </Button>
                )}
              </CardContent>
            </Card>
          ) : (
            <div className="space-y-3">
              {agendaItems.map((item, idx) => (
                <Card key={item.id} className={`group rounded-xl transition-all ${item.is_completed ? 'opacity-70' : 'hover:shadow-md'}`}>
                  <CardContent className="p-4">
                    <div className="flex items-start gap-3">
                      <div className="flex items-center gap-2 pt-0.5">
                        <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0 ${
                          item.is_completed
                            ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900 dark:text-emerald-300'
                            : 'bg-primary/10 text-primary'
                        }`}>
                          {item.is_completed ? <Check className="w-3.5 h-3.5" /> : idx + 1}
                        </div>
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-start justify-between gap-2">
                          <div>
                            <h4 className={`font-semibold text-sm ${item.is_completed ? 'line-through text-muted-foreground' : ''}`}>
                              {item.title}
                            </h4>
                            {item.description && (
                              <p className="text-xs text-muted-foreground mt-1 line-clamp-2">{item.description}</p>
                            )}
                          </div>
                          {isCreator && (
                            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                              <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleToggleComplete(item)}>
                                <Check className={`w-3.5 h-3.5 ${item.is_completed ? 'text-emerald-600' : 'text-muted-foreground'}`} />
                              </Button>
                              <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => {
                                setEditingAgenda(item);
                                setAgendaTitle(item.title);
                                setAgendaDesc(item.description || '');
                                setAgendaDuration(item.duration_minutes?.toString() || '');
                              }}>
                                <Edit2 className="w-3.5 h-3.5 text-muted-foreground" />
                              </Button>
                              <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleDeleteAgenda(item.id)}>
                                <Trash2 className="w-3.5 h-3.5 text-destructive" />
                              </Button>
                            </div>
                          )}
                        </div>
                        <div className="flex items-center gap-3 mt-2">
                          {item.duration_minutes && (
                            <span className="text-xs text-muted-foreground flex items-center gap-1">
                              <Clock className="w-3 h-3" /> {item.duration_minutes} {t('min_suffix')}
                            </span>
                          )}
                          {item.presenter && (
                            <span className="text-xs text-muted-foreground flex items-center gap-1">
                              <User className="w-3 h-3" /> {item.presenter.name}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}

              {isCreator && (
                <Button variant="outline" className="w-full gap-2 rounded-xl border-dashed" onClick={() => setShowAddAgenda(true)}>
                  <Plus className="w-4 h-4" /> {t('add_agenda_item')}
                </Button>
              )}
            </div>
          )}
        </TabsContent>

        {/* ── Minutes Tab ── */}
        <TabsContent value="minutes" className="space-y-4">
          {loadingMinutes ? (
            <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 animate-spin text-muted-foreground" /></div>
          ) : !minutes && !editingMinutes ? (
            <Card className="border-dashed border-2">
              <CardContent className="flex flex-col items-center justify-center py-16 text-center">
                <div className="w-16 h-16 bg-gradient-to-br from-primary/10 to-primary/5 rounded-2xl flex items-center justify-center mb-4">
                  <FileText className="w-8 h-8 text-primary" />
                </div>
                <h4 className="font-bold text-lg mb-1">{t('no_minutes_yet')}</h4>
                <p className="text-muted-foreground text-sm max-w-sm">{t('no_minutes_desc')}</p>
                {isCreator && (
                  <Button className="mt-4 gap-2 rounded-xl" onClick={() => setEditingMinutes(true)}>
                    <Edit2 className="w-4 h-4" /> {t('record_minutes')}
                  </Button>
                )}
              </CardContent>
            </Card>
          ) : editingMinutes ? (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label className="flex items-center gap-1.5 text-sm font-semibold">
                  <BookOpen className="w-4 h-4 text-primary" /> {t('meeting_notes')}
                </Label>
                <Textarea
                  className="rounded-xl min-h-[200px] resize-none"
                  placeholder={t('minutes_placeholder')}
                  value={minutesContent}
                  onChange={(e) => setMinutesContent(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label className="flex items-center gap-1.5 text-sm font-semibold">
                  <Lightbulb className="w-4 h-4 text-amber-500" /> {t('summary')}
                </Label>
                <Textarea
                  className="rounded-xl min-h-[80px] resize-none"
                  placeholder={t('summary_placeholder')}
                  value={minutesSummary}
                  onChange={(e) => setMinutesSummary(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label className="flex items-center gap-1.5 text-sm font-semibold">
                  <Target className="w-4 h-4 text-emerald-500" /> {t('key_decisions')}
                </Label>
                <Textarea
                  className="rounded-xl min-h-[80px] resize-none"
                  placeholder={t('decisions_placeholder')}
                  value={minutesDecisions}
                  onChange={(e) => setMinutesDecisions(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label className="flex items-center gap-1.5 text-sm font-semibold">
                  <AlertCircle className="w-4 h-4 text-blue-500" /> {t('action_items')}
                </Label>
                <Textarea
                  className="rounded-xl min-h-[80px] resize-none"
                  placeholder={t('action_items_placeholder')}
                  value={minutesActions}
                  onChange={(e) => setMinutesActions(e.target.value)}
                />
              </div>
              <div className="flex gap-2 pt-2">
                <Button className="gap-2 rounded-xl" onClick={handleSaveMinutes} disabled={savingMinutes || !minutesContent.trim()}>
                  {savingMinutes ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                  {t('save_minutes')}
                </Button>
                <Button variant="outline" className="rounded-xl" onClick={() => setEditingMinutes(false)}>
                  {t('cancel')}
                </Button>
              </div>
            </div>
          ) : minutes ? (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Badge variant="outline" className="rounded-lg gap-1.5 px-3 py-1">
                    <FileText className="w-3.5 h-3.5" /> {t('recorded_by')} {minutes.recorded_by.name}
                  </Badge>
                  {minutes.is_published && (
                    <Badge className="bg-emerald-500 text-white rounded-lg">{t('published')}</Badge>
                  )}
                </div>
                {isCreator && (
                  <Button variant="outline" size="sm" className="gap-1.5 rounded-xl" onClick={() => setEditingMinutes(true)}>
                    <Edit2 className="w-3.5 h-3.5" /> {t('edit')}
                  </Button>
                )}
              </div>

              <Card className="rounded-xl">
                <CardContent className="p-5">
                  <h4 className="font-semibold text-sm mb-3 flex items-center gap-1.5">
                    <BookOpen className="w-4 h-4 text-primary" /> {t('meeting_notes')}
                  </h4>
                  <p className="text-sm text-foreground/80 whitespace-pre-wrap leading-relaxed">{minutes.content}</p>
                </CardContent>
              </Card>

              {minutes.summary && (
                <Card className="rounded-xl border-amber-200 dark:border-amber-800 bg-amber-50/50 dark:bg-amber-950/20">
                  <CardContent className="p-5">
                    <h4 className="font-semibold text-sm mb-2 flex items-center gap-1.5 text-amber-700 dark:text-amber-400">
                      <Lightbulb className="w-4 h-4" /> {t('summary')}
                    </h4>
                    <p className="text-sm text-foreground/80 whitespace-pre-wrap leading-relaxed">{minutes.summary}</p>
                  </CardContent>
                </Card>
              )}

              {minutes.decisions && (
                <Card className="rounded-xl border-emerald-200 dark:border-emerald-800 bg-emerald-50/50 dark:bg-emerald-950/20">
                  <CardContent className="p-5">
                    <h4 className="font-semibold text-sm mb-2 flex items-center gap-1.5 text-emerald-700 dark:text-emerald-400">
                      <Target className="w-4 h-4" /> {t('key_decisions')}
                    </h4>
                    <p className="text-sm text-foreground/80 whitespace-pre-wrap leading-relaxed">{minutes.decisions}</p>
                  </CardContent>
                </Card>
              )}

              {minutes.action_items && (
                <Card className="rounded-xl border-blue-200 dark:border-blue-800 bg-blue-50/50 dark:bg-blue-950/20">
                  <CardContent className="p-5">
                    <h4 className="font-semibold text-sm mb-2 flex items-center gap-1.5 text-blue-700 dark:text-blue-400">
                      <AlertCircle className="w-4 h-4" /> {t('action_items')}
                    </h4>
                    <p className="text-sm text-foreground/80 whitespace-pre-wrap leading-relaxed">{minutes.action_items}</p>
                  </CardContent>
                </Card>
              )}
            </div>
          ) : null}
        </TabsContent>
      </Tabs>

      {/* Add/Edit Agenda Dialog */}
      <Dialog open={showAddAgenda || !!editingAgenda} onOpenChange={(open) => {
        if (!open) { setShowAddAgenda(false); setEditingAgenda(null); setAgendaTitle(''); setAgendaDesc(''); setAgendaDuration(''); }
      }}>
        <DialogContent className="max-w-md rounded-2xl">
          <DialogHeader>
            <DialogTitle className="text-lg font-bold flex items-center gap-2">
              <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
                <ListOrdered className="w-4 h-4 text-primary" />
              </div>
              {editingAgenda ? t('edit_agenda_item') : t('add_agenda_item')}
            </DialogTitle>
            <DialogDescription>{t('agenda_item_desc')}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 pt-2">
            <div className="space-y-1.5">
              <Label className="text-sm font-medium">{t('title')}</Label>
              <Input className="rounded-xl" placeholder={t('agenda_title_placeholder')} value={agendaTitle} onChange={(e) => setAgendaTitle(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label className="text-sm font-medium">{t('description')}</Label>
              <Textarea className="rounded-xl resize-none" placeholder={t('agenda_desc_placeholder')} value={agendaDesc} onChange={(e) => setAgendaDesc(e.target.value)} rows={2} />
            </div>
            <div className="space-y-1.5">
              <Label className="text-sm font-medium">{t('estimated_duration')}</Label>
              <Input className="rounded-xl" type="number" placeholder={t('duration_placeholder')} value={agendaDuration} onChange={(e) => setAgendaDuration(e.target.value)} />
            </div>
            <Button className="w-full gap-2 rounded-xl" onClick={editingAgenda ? handleUpdateAgenda : handleAddAgenda} disabled={savingAgenda || !agendaTitle.trim()}>
              {savingAgenda ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              {editingAgenda ? t('save_changes') : t('add_item')}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default MeetingDocuments;
