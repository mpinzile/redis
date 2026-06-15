/**
 * Full Event Report PDF using browser print
 * Generates a branded comprehensive event summary report
 */

import nuruLogoUrl from '@/assets/nuru-logo.png';
import * as XLSX from 'xlsx';
interface EventReportData {
  title: string;
  description?: string;
  event_type?: string;
  start_date?: string;
  end_date?: string;
  start_time?: string;
  end_time?: string;
  location?: string;
  venue?: string;
  status?: string;
  budget?: number;
  currency?: string;
  expected_guests?: number;
  guest_count?: number;
  confirmed_guest_count?: number;
  pending_guest_count?: number;
  declined_guest_count?: number;
  maybe_guest_count?: number;
  checked_in_count?: number;
  committee_count?: number;
  contribution_total?: number;
  contribution_count?: number;
  contribution_target?: number;
  tickets_sold?: number;
  tickets_capacity?: number;
  invitations_sent?: number;
  invitations_total?: number;
  service_booking_count?: number;
  vendor_count?: number;
  expense_total?: number;
  budget_item_total?: number;
  dress_code?: string;
  special_instructions?: string;
}

export const generateEventReportHtml = (event: EventReportData): string => {
  const currency = event.currency || 'TZS';
  const fmt = (n: number) => `${currency} ${n.toLocaleString()}`;
  const logoAbsoluteUrl = new URL(nuruLogoUrl, window.location.origin).href;

  const formatDate = (d?: string) => {
    if (!d) return '—';
    return new Date(d).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  };

  const budgetShortfall = event.budget ? Math.max(0, event.budget - (event.contribution_total || 0)) : 0;
  const pledgeShortfall = event.budget ? Math.max(0, event.budget - (event.contribution_target || 0)) : 0;
  const budgetCoverage = event.budget && event.budget > 0
    ? ((event.contribution_total || 0) / event.budget * 100).toFixed(1)
    : null;

  return `
    <!DOCTYPE html>
    <html><head><title>Event Report - ${event.title}</title>
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
      .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
      .info-item { background: #f8fafc; border-radius: 8px; padding: 12px 16px; }
      .info-item .label { font-size: 11px; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.5px; }
      .info-item .value { font-size: 15px; font-weight: 600; margin-top: 4px; color: #1e293b; }
      .stats-row { display: flex; gap: 12px; flex-wrap: wrap; }
      .stat-card { background: #f0f9ff; border-radius: 8px; padding: 14px 18px; flex: 1; min-width: 100px; text-align: center; border: 1px solid #e0f2fe; }
      .stat-card .num { font-size: 24px; font-weight: bold; color: #2563eb; }
      .stat-card .lbl { font-size: 11px; color: #64748b; margin-top: 4px; text-transform: uppercase; }
      .budget-bar { background: #e5e7eb; border-radius: 8px; height: 12px; margin-top: 8px; overflow: hidden; }
      .budget-bar-fill { height: 100%; background: linear-gradient(90deg, #22c55e, #16a34a); border-radius: 8px; }
      .status-badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; text-transform: uppercase; }
      .status-draft { background: #f1f5f9; color: #64748b; }
      .status-published { background: #dbeafe; color: #2563eb; }
      .status-cancelled { background: #fef2f2; color: #dc2626; }
      .status-completed { background: #dcfce7; color: #16a34a; }
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
          <h1>Event Report</h1>
          <h2>${new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })}, ${new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}</h2>
        </div>
      </div>

      <!-- Event Overview -->
      <div class="section">
        <div class="section-title">Event Overview</div>
        <h2 style="margin:0 0 8px 0;font-size:20px;color:#1e293b">${event.title}</h2>
        <span class="status-badge status-${event.status || 'draft'}">${event.status || 'Draft'}</span>
        ${event.description ? `<p style="margin-top:12px;color:#475569;line-height:1.6">${event.description}</p>` : ''}
      </div>

      <!-- Event Details -->
      <div class="section">
        <div class="section-title">Event Details</div>
        <div class="info-grid">
          <div class="info-item"><div class="label">Event Type</div><div class="value">${event.event_type || '—'}</div></div>
          <div class="info-item"><div class="label">Status</div><div class="value" style="text-transform:capitalize">${event.status || 'Draft'}</div></div>
          <div class="info-item"><div class="label">Start Date</div><div class="value">${formatDate(event.start_date)}</div></div>
          <div class="info-item"><div class="label">End Date</div><div class="value">${formatDate(event.end_date)}</div></div>
          <div class="info-item"><div class="label">Time</div><div class="value">${event.start_time || '—'}${event.end_time ? ' - ' + event.end_time : ''}</div></div>
          <div class="info-item"><div class="label">Location</div><div class="value">${event.location || event.venue || '—'}</div></div>
          ${event.dress_code ? `<div class="info-item"><div class="label">Dress Code</div><div class="value">${event.dress_code}</div></div>` : ''}
          ${event.special_instructions ? `<div class="info-item"><div class="label">Special Instructions</div><div class="value">${event.special_instructions}</div></div>` : ''}
        </div>
      </div>

      <!-- Guest Summary -->
      <div class="section">
        <div class="section-title">Guest Summary</div>
        <div class="stats-row">
          <div class="stat-card"><div class="num">${event.expected_guests || 0}</div><div class="lbl">Expected</div></div>
          <div class="stat-card"><div class="num">${event.guest_count || 0}</div><div class="lbl">Total RSVPs</div></div>
          <div class="stat-card"><div class="num" style="color:#16a34a">${event.confirmed_guest_count || 0}</div><div class="lbl">Confirmed</div></div>
          <div class="stat-card"><div class="num" style="color:#2563eb">${event.maybe_guest_count || 0}</div><div class="lbl">Maybe</div></div>
          <div class="stat-card"><div class="num" style="color:#ca8a04">${event.pending_guest_count || 0}</div><div class="lbl">Pending</div></div>
          <div class="stat-card"><div class="num" style="color:#dc2626">${event.declined_guest_count || 0}</div><div class="lbl">Declined</div></div>
          <div class="stat-card"><div class="num" style="color:#2563eb">${event.checked_in_count || 0}</div><div class="lbl">Checked In</div></div>
        </div>
      </div>

      <!-- Financial Summary -->
      <div class="section">
        <div class="section-title">Financial Summary</div>
        <div class="info-grid">
          <div class="info-item"><div class="label">Event Budget</div><div class="value">${event.budget ? fmt(event.budget) : '—'}</div></div>
          <div class="info-item"><div class="label">Total Collected</div><div class="value" style="color:#16a34a">${fmt(event.contribution_total || 0)}</div></div>
          <div class="info-item"><div class="label">Budget Shortfall</div><div class="value" style="color:${budgetShortfall > 0 ? '#dc2626' : '#16a34a'}">${fmt(budgetShortfall)}</div></div>
          <div class="info-item"><div class="label">Pledge Shortfall</div><div class="value">${fmt(pledgeShortfall)}</div></div>
          <div class="info-item"><div class="label">Unique Contributors</div><div class="value">${event.contribution_count || 0}</div></div>
          <div class="info-item"><div class="label">Committee Members</div><div class="value">${event.committee_count || 0}</div></div>
          <div class="info-item"><div class="label">Vendors</div><div class="value">${event.vendor_count ?? event.service_booking_count ?? 0}</div></div>
          <div class="info-item"><div class="label">Tickets</div><div class="value">${event.tickets_sold || 0}${event.tickets_capacity ? ` / ${event.tickets_capacity}` : ''}</div></div>
          <div class="info-item"><div class="label">Invitations Sent</div><div class="value">${event.invitations_sent || 0}${event.invitations_total ? ` / ${event.invitations_total}` : ''}</div></div>
        </div>
        ${budgetCoverage ? `
          <div style="margin-top:16px">
            <div style="display:flex;justify-content:space-between;font-size:12px;color:#64748b;margin-bottom:4px">
              <span>Budget Coverage</span>
              <span style="font-weight:bold;color:#1e293b">${budgetCoverage}%</span>
            </div>
            <div class="budget-bar">
              <div class="budget-bar-fill" style="width:${Math.min(parseFloat(budgetCoverage), 100)}%"></div>
            </div>
          </div>
        ` : ''}
      </div>

      <div class="footer">Generated by Nuru Events Workspace - © ${new Date().getFullYear()} Nuru | SEWMR TECHNOLOGIES</div>
    </body></html>
  `;
};

export const exportEventReportXlsx = (event: EventReportData) => {
  const currency = event.currency || 'TZS';
  const wb = XLSX.utils.book_new();
  const rows = [
    ['EVENT SUMMARY REPORT'],
    ['Generated', new Date().toLocaleString()],
    [],
    ['Event Overview'],
    ['Title', event.title], ['Type', event.event_type || ''], ['Status', event.status || ''],
    ['Start Date', event.start_date || ''], ['End Date', event.end_date || ''], ['Location', event.location || event.venue || ''],
    [],
    ['RSVP Summary'],
    ['Expected Guests', event.expected_guests || 0], ['Total RSVPs', event.guest_count || 0], ['Confirmed', event.confirmed_guest_count || 0], ['Maybe', event.maybe_guest_count || 0], ['Pending', event.pending_guest_count || 0], ['Declined', event.declined_guest_count || 0], ['Checked In', event.checked_in_count || 0], ['Invitations Sent', event.invitations_sent || 0],
    [],
    ['Financial Summary'],
    [`Budget (${currency})`, event.budget || 0], [`Collected (${currency})`, event.contribution_total || 0], [`Budget Shortfall (${currency})`, event.budget ? Math.max(0, event.budget - (event.contribution_total || 0)) : 0], [`Pledge Shortfall (${currency})`, event.budget ? Math.max(0, event.budget - (event.contribution_target || 0)) : 0], ['Contributors', event.contribution_count || 0], ['Vendors', event.vendor_count ?? event.service_booking_count ?? 0], ['Committee Members', event.committee_count || 0], ['Tickets Sold', event.tickets_sold || 0], ['Ticket Capacity', event.tickets_capacity || 0],
  ];
  const ws = XLSX.utils.aoa_to_sheet(rows);
  ws['!cols'] = [{ wch: 24 }, { wch: 28 }];
  XLSX.utils.book_append_sheet(wb, ws, 'Event Summary');
  XLSX.writeFile(wb, `${(event.title || 'event').replace(/\s+/g, '_')}_report.xlsx`);
};

/** @deprecated Use generateEventReportHtml + ReportPreviewDialog instead */
export const generateEventReport = (event: EventReportData) => {
  const html = generateEventReportHtml(event);
  const printWindow = window.open('', '_blank');
  if (printWindow) {
    printWindow.document.write(html);
    printWindow.document.close();
    setTimeout(() => printWindow.print(), 500);
  }
};
