import { useState } from 'react';
import { CheckCircle, X, Clock, Users, Mail, Phone, Search, Filter, FileText } from 'lucide-react';
import { Button } from '@/components/ui/button';
import ReportPreviewDialog from '@/components/ReportPreviewDialog';
import nuruLogoUrl from '@/assets/nuru-logo.png';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { useEventGuests } from '@/data/useEvents';
import { usePolling } from '@/hooks/usePolling';
import RSVPSkeletonLoader from './events/RSVPSkeletonLoader';
import type { EventPermissions } from '@/hooks/useEventPermissions';
import { useLanguage } from '@/lib/i18n/LanguageContext';

/** Convert 255xxxxxxxxx to 0xxxxxxxxx for display */
const formatPhoneDisplay = (phone?: string | null): string => {
  if (!phone) return '';
  const cleaned = phone.replace(/\s+/g, '');
  if (cleaned.startsWith('+255')) return '0' + cleaned.slice(4);
  if (cleaned.startsWith('255') && cleaned.length >= 12) return '0' + cleaned.slice(3);
  return cleaned;
};

interface EventRSVPProps {
  eventId: string;
  eventTitle?: string;
  permissions?: EventPermissions;
}

const EventRSVP = ({ eventId, eventTitle, permissions }: EventRSVPProps) => {
  const { t } = useLanguage();
  const { guests, summary, loading, refetch } = useEventGuests(eventId || null);
  usePolling(refetch, 15000);

  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [showReport, setShowReport] = useState(false);

  const stats = {
    attending: summary?.confirmed || 0,
    declined: summary?.declined || 0,
    pending: summary?.pending || 0,
    maybe: summary?.maybe || 0,
    total: summary?.total || 0,
    checked_in: summary?.checked_in || 0,
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
        return <Badge className={`${base} bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-300 dark:border-emerald-500/30`}><CheckCircle className="w-3 h-3 mr-1" />Attending</Badge>;
      case 'declined':
        return <Badge className={`${base} bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-500/10 dark:text-rose-300 dark:border-rose-500/30`}><X className="w-3 h-3 mr-1" />Declined</Badge>;
      case 'maybe':
        return <Badge className={`${base} bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-500/10 dark:text-amber-300 dark:border-amber-500/30`}><Clock className="w-3 h-3 mr-1" />Maybe</Badge>;
      case 'pending':
      default:
        return <Badge className={`${base} bg-muted/60 text-muted-foreground border-border`}><span className="inline-block w-1.5 h-1.5 rounded-full bg-muted-foreground/60 mr-1.5" />Awaiting reply</Badge>;
    }
  };

  const getInitials = (name: string) => {
    const parts = (name || '').trim().split(/\s+/);
    return parts.length >= 2
      ? `${parts[0].charAt(0)}${parts[parts.length - 1].charAt(0)}`.toUpperCase()
      : (name || 'G').charAt(0).toUpperCase();
  };

  const getStatusLabel = (status: string) => {
    switch (status) {
      case 'confirmed': return 'Attending';
      case 'declined': return 'Declined';
      case 'maybe': return 'Maybe';
      case 'pending': default: return 'Pending';
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'confirmed': return '#16a34a';
      case 'declined': return '#dc2626';
      case 'maybe': return '#ca8a04';
      case 'pending': default: return '#64748b';
    }
  };

  const generateRsvpReportHtml = (): string => {
    const logoAbsoluteUrl = new URL(nuruLogoUrl, window.location.origin).href;
    const now = new Date();
    const dateStr = now.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
    const timeStr = now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });

    const sortedGuests = [...guests].sort((a, b) => (a.name || '').localeCompare(b.name || ''));

    const guestRows = sortedGuests.map((g, i) => `
      <tr style="${i % 2 === 0 ? '' : 'background:#f8fafc'}">
        <td style="padding:10px 12px;font-size:13px">${i + 1}</td>
        <td style="padding:10px 12px;font-size:13px;font-weight:500">${g.name || '—'}</td>
        <td style="padding:10px 12px;font-size:13px">${formatPhoneDisplay(g.phone) || '—'}</td>
        <td style="padding:10px 12px;font-size:13px">
          <span style="display:inline-block;padding:3px 10px;border-radius:12px;font-size:11px;font-weight:600;color:white;background:${getStatusColor(g.rsvp_status)}">${getStatusLabel(g.rsvp_status)}</span>
        </td>
        <td style="padding:10px 12px;font-size:13px">${g.plus_ones > 0 ? '+' + g.plus_ones : '—'}</td>
      </tr>
    `).join('');

    return `
      <!DOCTYPE html>
      <html><head><title>RSVP Report - ${eventTitle || 'Event'}</title>
      <style>
        body { font-family: Arial, sans-serif; padding: 40px; color: #333; max-width: 900px; margin: 0 auto; }
        .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 32px; border-bottom: 3px solid #2563eb; padding-bottom: 20px; }
        .brand { display: flex; flex-direction: column; align-items: flex-start; }
        .brand img { height: 40px; margin-bottom: 6px; }
        .brand .slogan { font-size: 11px; color: #888; font-style: italic; }
        .header-right { text-align: right; }
        .header-right h1 { font-size: 22px; margin: 0 0 4px 0; color: #1e293b; }
        .header-right h2 { font-size: 13px; color: #666; margin: 0; font-weight: normal; }
        .section { margin-bottom: 28px; }
        .section-title { font-size: 14px; font-weight: bold; color: #2563eb; text-transform: uppercase; letter-spacing: 1px; border-bottom: 1px solid #e5e7eb; padding-bottom: 8px; margin-bottom: 16px; }
        .stats-row { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 24px; }
        .stat-card { background: #f0f9ff; border-radius: 8px; padding: 14px 18px; flex: 1; min-width: 80px; text-align: center; border: 1px solid #e0f2fe; }
        .stat-card .num { font-size: 24px; font-weight: bold; color: #2563eb; }
        .stat-card .lbl { font-size: 11px; color: #64748b; margin-top: 4px; text-transform: uppercase; }
        table { width: 100%; border-collapse: collapse; }
        th { background: #1e293b; color: white; padding: 10px 12px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; text-align: left; }
        td { border-bottom: 1px solid #e5e7eb; }
        .footer { margin-top: 40px; font-size: 11px; color: #999; text-align: center; border-top: 1px solid #eee; padding-top: 12px; }
        @media print { body { padding: 20px; } }
      </style></head>
      <body>
        <div class="header">
          <div class="brand">
            <img src="${logoAbsoluteUrl}" alt="Nuru" />
            <span class="slogan">Plan Smarter</span>
          </div>
          <div class="header-right">
            <h1>RSVP Report</h1>
            <h2>${dateStr}, ${timeStr}</h2>
            ${eventTitle ? `<h2 style="margin-top:4px;font-weight:600;color:#1e293b">${eventTitle}</h2>` : ''}
          </div>
        </div>

        <div class="section">
          <div class="section-title">Attendance Summary</div>
          <div class="stats-row">
            <div class="stat-card"><div class="num">${stats.total}</div><div class="lbl">Total Invited</div></div>
            <div class="stat-card"><div class="num" style="color:#16a34a">${stats.attending}</div><div class="lbl">Attending</div></div>
            <div class="stat-card"><div class="num" style="color:#ca8a04">${stats.pending}</div><div class="lbl">Pending</div></div>
            <div class="stat-card"><div class="num" style="color:#dc2626">${stats.declined}</div><div class="lbl">Declined</div></div>
            <div class="stat-card"><div class="num" style="color:#2563eb">${stats.checked_in}</div><div class="lbl">Checked In</div></div>
          </div>
          ${stats.total > 0 ? `
            <div style="font-size:13px;color:#475569;line-height:1.8">
              <strong>Attendance Rate:</strong> ${stats.total > 0 ? Math.round((stats.attending / stats.total) * 100) : 0}% of invited guests confirmed attendance.<br/>
              <strong>Response Rate:</strong> ${stats.total > 0 ? Math.round(((stats.attending + stats.declined + (stats.maybe || 0)) / stats.total) * 100) : 0}% of guests have responded to the invitation.<br/>
              <strong>Pending Action:</strong> ${stats.pending} guest${stats.pending !== 1 ? 's' : ''} ${stats.pending === 1 ? 'has' : 'have'} not yet responded.
            </div>
          ` : ''}
        </div>

        <div class="section">
          <div class="section-title">Guest List (${guests.length})</div>
          <table>
            <thead>
              <tr>
                <th>#</th>
                <th>Full Name</th>
                <th>Phone</th>
                <th>Status</th>
                <th>Plus Ones</th>
              </tr>
            </thead>
            <tbody>
              ${guestRows || '<tr><td colspan="5" style="padding:20px;text-align:center;color:#94a3b8">No guests found</td></tr>'}
            </tbody>
          </table>
        </div>

        <div class="footer">Generated by Nuru Events Workspace - © ${now.getFullYear()} Nuru | SEWMR TECHNOLOGIES</div>
      </body></html>
    `;
  };

  if (loading) return <RSVPSkeletonLoader />;

  return (
    <div className="space-y-6">
      {/* Header with Report button */}
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-muted-foreground">RSVP Tracking</h3>
        <Button variant="outline" size="sm" onClick={() => setShowReport(true)}>
          <FileText className="w-4 h-4 mr-2" />
          RSVP Report
        </Button>
      </div>

      {/* Summary Stats */}
      <div className="grid grid-cols-2 md:grid-cols-6 gap-4">
        <Card><CardContent className="p-4 text-center"><div className="text-base font-semibold text-green-600">{stats.attending}</div><p className="text-xs text-muted-foreground">Attending</p></CardContent></Card>
        <Card><CardContent className="p-4 text-center"><div className="text-base font-semibold text-orange-600">{stats.pending}</div><p className="text-xs text-muted-foreground">Pending</p></CardContent></Card>
        <Card><CardContent className="p-4 text-center"><div className="text-base font-semibold text-amber-600">{stats.maybe}</div><p className="text-xs text-muted-foreground">{t('maybe')}</p></CardContent></Card>
        <Card><CardContent className="p-4 text-center"><div className="text-base font-semibold text-red-600">{stats.declined}</div><p className="text-xs text-muted-foreground">{t('declined')}</p></CardContent></Card>
        <Card><CardContent className="p-4 text-center"><div className="text-base font-semibold text-blue-600">{stats.checked_in}</div><p className="text-xs text-muted-foreground">{t('checked_in')}</p></CardContent></Card>
        <Card><CardContent className="p-4 text-center"><div className="text-base font-semibold">{stats.total}</div><p className="text-xs text-muted-foreground">{t('total_invited')}</p></CardContent></Card>
      </div>


      {/* Search & Filter */}
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input placeholder={t('search_guests')} value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} className="pl-9" />
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-40"><Filter className="w-4 h-4 mr-2" /><SelectValue placeholder={t("filter")} /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">{t('all_status')}</SelectItem>
            <SelectItem value="confirmed">{t('attending')}</SelectItem>
            <SelectItem value="pending">{t('pending')}</SelectItem>
            <SelectItem value="declined">{t('declined')}</SelectItem>
            <SelectItem value="maybe">{t('maybe')}</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Guest RSVP List */}
      <Card>
        <CardContent className="p-0">
          <div className="divide-y">
            {filteredGuests.length === 0 ? (
              <div className="p-6 text-center text-muted-foreground">
                <Users className="w-8 h-8 mx-auto mb-2 opacity-40" />
                <p>No guests found</p>
              </div>
            ) : (
              filteredGuests.map((guest) => (
                <div key={guest.id} className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-muted/50">
                  <div className="flex items-center gap-3 min-w-0">
                    <Avatar className="flex-shrink-0">
                      <AvatarImage src={guest.avatar || undefined} />
                      <AvatarFallback>{getInitials(guest.name)}</AvatarFallback>
                    </Avatar>
                    <div className="min-w-0">
                      <p className="font-medium truncate">{guest.name}</p>
                      <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                        {guest.phone && <span className="flex items-center gap-1"><Phone className="w-3 h-3 flex-shrink-0" />{formatPhoneDisplay(guest.phone)}</span>}
                        {guest.email && <span className="flex items-center gap-1 truncate"><Mail className="w-3 h-3 flex-shrink-0" /><span className="truncate max-w-[150px]">{guest.email}</span></span>}
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 flex-shrink-0 ml-auto sm:ml-0">
                    {getStatusBadge(guest.rsvp_status)}
                    {guest.plus_ones > 0 && <Badge variant="outline" className="text-xs">+{guest.plus_ones}</Badge>}
                  </div>
                </div>
              ))
            )}
          </div>
        </CardContent>
      </Card>

      {/* Attendance note */}
      <p className="text-xs text-muted-foreground text-center">
        {stats.total} guest{stats.total !== 1 ? 's' : ''} invited • {stats.attending} attending • {stats.declined} declined • {stats.pending} awaiting response
      </p>

      {/* RSVP Report Dialog */}
      <ReportPreviewDialog
        open={showReport}
        onOpenChange={setShowReport}
        title="RSVP Report"
        html={showReport ? generateRsvpReportHtml() : ''}
      />
    </div>
  );
};

export default EventRSVP;
