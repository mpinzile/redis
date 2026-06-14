/**
 * PDF generation using browser print
 * Generates a branded contribution report with Nuru logo
 */

import nuruLogoUrl from '@/assets/nuru-logo.png';

interface ContributorRow {
  name: string;
  pledged: number;
  paid: number;
  balance: number;
}

export const generateContributionReportHtml = (
  eventTitle: string,
  contributors: ContributorRow[],
  summary: { total_amount: number; target_amount?: number; currency?: string; budget?: number },
  dateRangeLabel?: string,
  fullSummary?: { total_paid: number; total_pledged: number; total_balance: number },
  eventEndDate?: string
): string => {
  const currency = summary.currency || 'TZS';
  const fmt = (n: number) => `${currency} ${n.toLocaleString()}`;

  // Sort contributors alphabetically
  const sorted = [...contributors].sort((a, b) => a.name.localeCompare(b.name));

  const totalPledged = sorted.reduce((s, c) => s + c.pledged, 0);
  const totalPaid = sorted.reduce((s, c) => s + c.paid, 0);
  const totalBalance = sorted.reduce((s, c) => s + c.balance, 0);

  // Use full summary for header cards if provided, otherwise fall back to table totals
  const summaryPledged = fullSummary?.total_pledged ?? totalPledged;
  const summaryPaid = fullSummary?.total_paid ?? totalPaid;
  const summaryBalance = fullSummary?.total_balance ?? totalBalance;

  // Outstanding pledge = what's promised but not yet collected
  const outstandingPledge = summaryBalance;

  const logoAbsoluteUrl = new URL(nuruLogoUrl, window.location.origin).href;

  const isFiltered = !!dateRangeLabel;

  // Countdown text based on event START date (only on unfiltered full reports, only if event hasn't started yet)
  let countdownHtml = '';
  if (eventEndDate && !isFiltered) {
    const startDate = new Date(eventEndDate); // param is actually start_date now
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    startDate.setHours(0, 0, 0, 0);
    const diffDays = Math.round((startDate.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));
    if (diffDays > 0) {
      const weeks = Math.floor(diffDays / 7);
      const days = diffDays % 7;
      let countdownText = '';
      if (weeks > 0 && days > 0) {
        countdownText = `${weeks} week${weeks !== 1 ? 's' : ''} and ${days} day${days !== 1 ? 's' : ''} remaining`;
      } else if (weeks > 0) {
        countdownText = `${weeks} week${weeks !== 1 ? 's' : ''} remaining`;
      } else {
        countdownText = `${days} day${days !== 1 ? 's' : ''} remaining`;
      }
      countdownHtml = `<div style="display:inline-flex;align-items:center;background:#eff6ff;border:1px solid #bfdbfe;border-radius:20px;padding:6px 14px;margin-bottom:20px"><span style="font-size:13px;font-weight:600;color:#1d4ed8">${countdownText}</span></div>`;
    } else if (diffDays === 0) {
      countdownHtml = `<div style="display:inline-flex;align-items:center;background:#fefce8;border:1px solid #fde047;border-radius:20px;padding:6px 14px;margin-bottom:20px"><span style="font-size:13px;font-weight:600;color:#854d0e">Event is Today!</span></div>`;
    }
    // If diffDays < 0, event has already started — show no countdown
  }

  const rows = sorted.map((c, i) => isFiltered ? `
    <tr>
      <td style="padding:8px;border-bottom:1px solid #eee">${i + 1}</td>
      <td style="padding:8px;border-bottom:1px solid #eee">${c.name}</td>
      <td style="padding:8px;border-bottom:1px solid #eee;text-align:right">${fmt(c.paid)}</td>
    </tr>
  ` : `
    <tr>
      <td style="padding:8px;border-bottom:1px solid #eee">${i + 1}</td>
      <td style="padding:8px;border-bottom:1px solid #eee">${c.name}</td>
      <td style="padding:8px;border-bottom:1px solid #eee;text-align:right">${fmt(c.pledged)}</td>
      <td style="padding:8px;border-bottom:1px solid #eee;text-align:right">${fmt(c.paid)}</td>
      <td style="padding:8px;border-bottom:1px solid #eee;text-align:right;color:${c.balance > 0 ? '#dc2626' : '#16a34a'}">${fmt(c.balance)}</td>
    </tr>
  `).join('');

  return `
    <!DOCTYPE html>
    <html><head><title>Contribution Report - ${eventTitle}</title>
    <style>
      body { font-family: Arial, sans-serif; padding: 40px; color: #333; }
      .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 32px; border-bottom: 2px solid #e5e7eb; padding-bottom: 20px; }
      .brand { display: flex; flex-direction: column; align-items: flex-start; }
      .brand img { height: 40px; margin-bottom: 6px; }
      .brand .slogan { font-size: 11px; color: #888; font-style: italic; }
      .header-right { text-align: right; }
      .header-right h1 { font-size: 20px; margin: 0 0 4px 0; }
      .header-right h2 { font-size: 13px; color: #666; margin: 0; font-weight: normal; }
      table { width: 100%; border-collapse: collapse; margin-top: 16px; }
      th { background: #f8f8f8; padding: 10px 8px; text-align: left; border-bottom: 2px solid #ddd; font-size: 13px; }
      td { font-size: 13px; }
      .summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 24px; }
      .summary-card { background: #f9fafb; border-radius: 8px; padding: 14px 18px; }
      .summary-card .label { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; }
      .summary-card .value { font-size: 17px; font-weight: bold; margin-top: 4px; }
      tfoot td { font-weight: bold; border-top: 2px solid #333; padding: 10px 8px; }
      .footer { margin-top: 32px; font-size: 11px; color: #999; text-align: center; border-top: 1px solid #eee; padding-top: 12px; }
      .coverage-pct { color: #16a34a; font-weight: bold; }
      @media print { body { padding: 20px; } }
    </style></head>
    <body>
      <div class="header">
        <div class="brand">
          <img src="${logoAbsoluteUrl}" alt="Nuru" />
          <span class="slogan">Plan Smarter</span>
        </div>
        <div class="header-right">
          <h1>Contribution Report</h1>
          <h2>${eventTitle} &mdash; ${new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })}, ${new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}</h2>
          ${dateRangeLabel ? `<h2 style="color:#ca8a04;margin-top:4px">Period: ${dateRangeLabel}</h2>` : ''}
        </div>
      </div>

      ${countdownHtml}
      
      <div class="summary" style="display:grid;grid-template-columns:repeat(3,1fr);gap:16px">
        ${summary.budget ? `<div class="summary-card"><div class="label">Event Budget</div><div class="value">${fmt(summary.budget)}</div></div>` : ''}
        <div class="summary-card"><div class="label">Total Collected</div><div class="value" style="color:#16a34a">${fmt(summaryPaid)}</div></div>
        ${summary.budget ? `<div class="summary-card" style="background:#fef2f2"><div class="label" style="color:#991b1b">Budget Shortfall</div><div class="value" style="color:${Math.max(0, summary.budget - summaryPaid) > 0 ? '#dc2626' : '#16a34a'}">${fmt(Math.max(0, summary.budget - summaryPaid))}</div></div>` : ''}
        <div class="summary-card"><div class="label">Total Pledged</div><div class="value" style="color:#7c3aed">${fmt(summaryPledged)}</div></div>
        <div class="summary-card"><div class="label">Outstanding Pledge</div><div class="value" style="color:#ca8a04">${fmt(outstandingPledge)}</div></div>
        ${summary.budget ? `<div class="summary-card"><div class="label">Unpledged</div><div class="value" style="color:#6b7280">${fmt(Math.max(0, summary.budget - summaryPledged))}</div></div>` : ''}
      </div>

      ${summary.budget ? `<p style="font-size:12px;color:#666;margin-bottom:16px">Budget coverage: <span class="coverage-pct">${((summaryPaid / summary.budget) * 100).toFixed(1)}%</span> of event budget collected so far.${summary.budget ? `<span style="float:right">Pledge coverage: <strong style="color:#7c3aed">${((summaryPledged / summary.budget) * 100).toFixed(1)}%</strong> of event budget.</span>` : ''}</p>` : ''}
      ${dateRangeLabel ? `<p style="font-size:11px;color:#7c3aed;margin-bottom:16px;font-style:italic">The table below shows payments recorded within the selected period (${dateRangeLabel}). Summary cards above reflect all-time totals.</p>` : ''}

      <table>
        <thead>
          <tr>
            <th>S/N</th>
            <th>Contributor</th>
            ${isFiltered ? `
            <th style="text-align:right">Collected</th>
            ` : `
            <th style="text-align:right">Pledged</th>
            <th style="text-align:right">Paid</th>
            <th style="text-align:right">Balance</th>
            `}
          </tr>
        </thead>
        <tbody>${rows}</tbody>
        <tfoot>
          <tr>
            <td colspan="2">Total (${sorted.length} contributors)</td>
            ${isFiltered ? `
            <td style="text-align:right">${fmt(totalPaid)}</td>
            ` : `
            <td style="text-align:right">${fmt(totalPledged)}</td>
            <td style="text-align:right">${fmt(totalPaid)}</td>
            <td style="text-align:right">${fmt(totalBalance)}</td>
            `}
          </tr>
        </tfoot>
      </table>
      
      <div class="footer">Generated by Nuru Events Workspace &middot; &copy; ${new Date().getFullYear()} Nuru | SEWMR TECHNOLOGIES</div>
    </body></html>
  `;
};


/** @deprecated Use generateContributionReportHtml + ReportPreviewDialog instead */
export const generateContributionReport = (
  eventTitle: string,
  contributors: ContributorRow[],
  summary: { total_amount: number; target_amount?: number; currency?: string; budget?: number }
) => {
  const html = generateContributionReportHtml(eventTitle, contributors, summary);
  const printWindow = window.open('', '_blank');
  if (printWindow) {
    printWindow.document.write(html);
    printWindow.document.close();
    setTimeout(() => printWindow.print(), 500);
  }
};

/**
 * Expense Report HTML
 */
interface ExpenseRow {
  category: string;
  description: string;
  amount: number;
  vendor_name?: string;
  expense_date: string;
  recorded_by_name?: string;
}

export const generateExpenseReportHtml = (
  eventTitle: string,
  expenses: ExpenseRow[],
  summary: { total_expenses: number; category_breakdown: Array<{ category: string; total: number; count: number }>; currency?: string; budget?: number; total_raised?: number },
  dateRangeLabel?: string
): string => {
  const currency = summary.currency || 'TZS';
  const fmt = (n: number) => `${currency} ${n.toLocaleString()}`;

  const sorted = [...expenses].sort((a, b) => new Date(a.expense_date).getTime() - new Date(b.expense_date).getTime());

  const totalExpenses = sorted.reduce((s, e) => s + e.amount, 0);

  const logoAbsoluteUrl = new URL(nuruLogoUrl, window.location.origin).href;

  const rows = sorted.map((e, i) => `
    <tr>
      <td style="padding:8px;border-bottom:1px solid #eee">${i + 1}</td>
      <td style="padding:8px;border-bottom:1px solid #eee">${e.expense_date ? new Date(e.expense_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '&mdash;'}</td>
      <td style="padding:8px;border-bottom:1px solid #eee">${e.vendor_name || '&mdash;'}</td>
      <td style="padding:8px;border-bottom:1px solid #eee">${e.category}</td>
      <td style="padding:8px;border-bottom:1px solid #eee">${e.description}</td>
      <td style="padding:8px;border-bottom:1px solid #eee;text-align:right">${fmt(e.amount)}</td>
    </tr>
  `).join('');

  const categoryRows = (summary.category_breakdown || []).map((c, i) => `
    <tr>
      <td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:center">${i + 1}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee">${c.category}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:center">${c.count}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:right">${fmt(c.total)}</td>
    </tr>
  `).join('');

  const remaining = (summary.total_raised || 0) - summary.total_expenses;

  const budgetCard = summary.budget
    ? `<div class="summary-card"><div class="label">Event Budget</div><div class="value">${fmt(summary.budget)}</div></div>`
    : '';

  const dateHeader = dateRangeLabel
    ? `<h2 style="color:#ca8a04;margin-top:4px">Period: ${dateRangeLabel}</h2>`
    : '';

  const catSection = categoryRows
    ? `<h3 style="font-size:14px;margin-bottom:8px">Category Summary</h3>
      <table style="margin-bottom:24px">
        <thead><tr><th style="text-align:center">S/N</th><th>Category</th><th style="text-align:center">Items</th><th style="text-align:right">Total</th></tr></thead>
        <tbody>${categoryRows}</tbody>
      </table>`
    : '';

  const balColor = remaining >= 0 ? '#16a34a' : '#dc2626';

  return `
    <!DOCTYPE html>
    <html><head><title>Expense Report - ${eventTitle}</title>
    <style>
      body { font-family: Arial, sans-serif; padding: 40px; color: #333; }
      .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 32px; border-bottom: 2px solid #e5e7eb; padding-bottom: 20px; }
      .brand { display: flex; flex-direction: column; align-items: flex-start; }
      .brand img { height: 40px; margin-bottom: 6px; }
      .brand .slogan { font-size: 11px; color: #888; font-style: italic; }
      .header-right { text-align: right; }
      .header-right h1 { font-size: 20px; margin: 0 0 4px 0; }
      .header-right h2 { font-size: 13px; color: #666; margin: 0; font-weight: normal; }
      table { width: 100%; border-collapse: collapse; margin-top: 16px; }
      th { background: #f8f8f8; padding: 10px 8px; text-align: left; border-bottom: 2px solid #ddd; font-size: 13px; }
      td { font-size: 13px; }
      .summary { display: flex; gap: 16px; margin-bottom: 24px; flex-wrap: wrap; }
      .summary-card { background: #f9fafb; border-radius: 8px; padding: 14px 18px; flex:1; min-width: 120px; }
      .summary-card .label { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; }
      .summary-card .value { font-size: 17px; font-weight: bold; margin-top: 4px; }
      tfoot td { font-weight: bold; border-top: 2px solid #333; padding: 10px 8px; }
      .footer { margin-top: 32px; font-size: 11px; color: #999; text-align: center; border-top: 1px solid #eee; padding-top: 12px; }
      @media print { body { padding: 20px; } }
    </style></head>
    <body>
      <div class="header">
        <div class="brand">
          <img src="${logoAbsoluteUrl}" alt="Nuru" />
          <span class="slogan">Plan Smarter</span>
        </div>
        <div class="header-right">
          <h1>Expense Report</h1>
          <h2>${eventTitle} &mdash; ${new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })}, ${new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}</h2>
          ${dateHeader}
        </div>
      </div>
      
      <div class="summary">
        ${budgetCard}
        <div class="summary-card"><div class="label">Total Collected</div><div class="value" style="color:#16a34a">${fmt(summary.total_raised || 0)}</div></div>
        <div class="summary-card"><div class="label">Total Expenses</div><div class="value" style="color:#dc2626">${fmt(summary.total_expenses)}</div></div>
        <div class="summary-card"><div class="label">Remaining Balance</div><div class="value" style="color:${balColor}">${fmt(remaining)}</div></div>
      </div>

      ${catSection}

      <h3 style="font-size:14px;margin-bottom:8px">Expense Details</h3>
      <table>
        <thead>
          <tr>
            <th>S/N</th>
            <th>Date</th>
            <th>Vendor</th>
            <th>Category</th>
            <th>Description</th>
            <th style="text-align:right">Amount</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
        <tfoot>
          <tr>
            <td colspan="5">Total (${sorted.length} expenses)</td>
            <td style="text-align:right">${fmt(totalExpenses)}</td>
          </tr>
        </tfoot>
      </table>
      
      <div class="footer">Generated by Nuru Events Workspace &middot; &copy; ${new Date().getFullYear()} Nuru | SEWMR TECHNOLOGIES</div>
    </body></html>
  `;
};

// ─────────────────────────────────────────────────────────────────────────────
// Admin Payments Operations Report
// Used by AdminPaymentsReports for all 10 finance reports (collections,
// commissions, settlements, country mix, etc.). Renders branded HTML for
// ReportPreviewDialog → Print → PDF, matching the contribution/expense look.
// ─────────────────────────────────────────────────────────────────────────────

export interface PaymentsReportColumn {
  key: string;
  label: string;
  align?: "left" | "right" | "center";
  format?: (v: unknown, row: Record<string, unknown>) => string;
}

export interface PaymentsReportSummaryCard {
  label: string;
  value: string;
  tone?: "primary" | "success" | "danger" | "warning" | "muted";
}

export const generatePaymentsReportHtml = (
  reportTitle: string,
  rows: Record<string, unknown>[],
  columns: PaymentsReportColumn[],
  summary: PaymentsReportSummaryCard[],
  dateRangeLabel?: string,
  footerNote?: string,
): string => {
  const logoAbsoluteUrl = new URL(nuruLogoUrl, window.location.origin).href;
  const generatedAt = `${new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })}, ${new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })}`;

  const toneToColor = (tone?: PaymentsReportSummaryCard["tone"]) => {
    switch (tone) {
      case "success": return "#16a34a";
      case "danger":  return "#dc2626";
      case "warning": return "#ca8a04";
      case "primary": return "#2563eb";
      default:        return "#111827";
    }
  };

  const summaryCards = summary.map((c) => `
    <div class="summary-card">
      <div class="label">${c.label}</div>
      <div class="value" style="color:${toneToColor(c.tone)}">${c.value}</div>
    </div>
  `).join('');

  const headerCells = columns.map((c) => `
    <th style="text-align:${c.align ?? 'left'}">${c.label}</th>
  `).join('');

  const bodyRows = rows.map((r, i) => `
    <tr>
      <td style="padding:8px;border-bottom:1px solid #eee">${i + 1}</td>
      ${columns.map((c) => {
        const raw = r[c.key];
        const text = c.format ? c.format(raw, r) : (raw ?? '—');
        return `<td style="padding:8px;border-bottom:1px solid #eee;text-align:${c.align ?? 'left'}">${text}</td>`;
      }).join('')}
    </tr>
  `).join('');

  return `
    <!DOCTYPE html>
    <html><head><title>${reportTitle}</title>
    <style>
      body { font-family: Arial, sans-serif; padding: 36px; color: #333; }
      .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 28px; border-bottom: 2px solid #e5e7eb; padding-bottom: 18px; }
      .brand { display: flex; flex-direction: column; align-items: flex-start; }
      .brand img { height: 38px; margin-bottom: 6px; }
      .brand .slogan { font-size: 11px; color: #888; font-style: italic; }
      .header-right { text-align: right; }
      .header-right h1 { font-size: 19px; margin: 0 0 4px 0; }
      .header-right h2 { font-size: 12px; color: #666; margin: 0; font-weight: normal; }
      .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 22px; }
      .summary-card { background: #f9fafb; border-radius: 8px; padding: 12px 16px; border: 1px solid #f1f5f9; }
      .summary-card .label { font-size: 10px; color: #888; text-transform: uppercase; letter-spacing: 0.6px; }
      .summary-card .value { font-size: 16px; font-weight: bold; margin-top: 4px; }
      table { width: 100%; border-collapse: collapse; margin-top: 10px; }
      th { background: #f8f8f8; padding: 9px 8px; text-align: left; border-bottom: 2px solid #ddd; font-size: 12px; }
      td { font-size: 12px; }
      .footer { margin-top: 28px; font-size: 10.5px; color: #999; text-align: center; border-top: 1px solid #eee; padding-top: 12px; }
      @media print { body { padding: 18px; } }
    </style></head>
    <body>
      <div class="header">
        <div class="brand">
          <img src="${logoAbsoluteUrl}" alt="Nuru" />
          <span class="slogan">Plan Smarter</span>
        </div>
        <div class="header-right">
          <h1>${reportTitle}</h1>
          <h2>Generated ${generatedAt}</h2>
          ${dateRangeLabel ? `<h2 style="color:#ca8a04;margin-top:4px">Period: ${dateRangeLabel}</h2>` : ''}
        </div>
      </div>

      ${summary.length ? `<div class="summary">${summaryCards}</div>` : ''}

      <table>
        <thead><tr><th>S/N</th>${headerCells}</tr></thead>
        <tbody>${bodyRows || `<tr><td colspan="${columns.length + 1}" style="padding:24px;text-align:center;color:#888">No data for the selected period.</td></tr>`}</tbody>
      </table>

      ${footerNote ? `<p style="font-size:11px;color:#666;margin-top:14px;font-style:italic">${footerNote}</p>` : ''}

      <div class="footer">Nuru Finance Operations &middot; Generated by Admin Console &middot; &copy; ${new Date().getFullYear()} Nuru | SEWMR TECHNOLOGIES</div>
    </body></html>
  `;
};

// ─────────────────────────────────────────────────────────────────────────────
// Single Transaction Receipt
// Renders a Nuru-branded printable HTML receipt — same look & feel as the
// contribution & expense reports so PDF/print works identically across web
// and mobile.
// ─────────────────────────────────────────────────────────────────────────────

export interface ReceiptTransactionLike {
  transaction_code: string;
  status: string;
  target_type: string;
  gross_amount: number;
  net_amount?: number;
  commission_amount?: number;
  currency_code?: string;
  payment_description?: string | null;
  description?: string | null;
  provider_name?: string | null;
  method_type?: string | null;
  external_reference?: string | null;
  initiated_at?: string | null;
  completed_at?: string | null;
  created_at?: string | null;
  failure_reason?: string | null;
}

export const generateReceiptHtml = (tx: ReceiptTransactionLike): string => {
  const currency = tx.currency_code || 'TZS';
  const fmt = (n: number) => `${currency} ${(n || 0).toLocaleString()}`;
  const logoAbsoluteUrl = new URL(nuruLogoUrl, window.location.origin).href;
  const logoSquareAbsoluteUrl = new URL(nuruLogoUrl, window.location.origin).href;

  const dateStr = (iso?: string | null) => iso
    ? new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })
    : '—';

  const purpose = tx.target_type
    ? tx.target_type.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
    : 'Payment';

  const statusLabel = (tx.status || '').toLowerCase();
  const isPaid = ['succeeded', 'paid', 'credited'].includes(statusLabel);
  const isFail = ['failed', 'cancelled'].includes(statusLabel);
  const statusBg = isPaid ? '#ECFDF5' : isFail ? '#FEF2F2' : '#FFFBEB';
  const statusFg = isPaid ? '#065F46' : isFail ? '#991B1B' : '#92400E';
  const statusText = isPaid ? 'Paid' : statusLabel ? statusLabel.charAt(0).toUpperCase() + statusLabel.slice(1) : 'Unknown';

  const fee = typeof tx.commission_amount === 'number'
    ? tx.commission_amount
    : Math.max(0, (tx.gross_amount || 0) - (tx.net_amount || tx.gross_amount || 0));
  const subtotal = typeof tx.net_amount === 'number' ? tx.net_amount : (tx.gross_amount || 0) - fee;

  const host = (typeof window !== 'undefined' && window.location.hostname.endsWith('nuru.ke')) ? 'nuru.ke' : 'nuru.tz';
  const verifyUrl = `https://${host}/shared/receipt/${tx.transaction_code}`;
  const qrSrc = `https://api.qrserver.com/v1/create-qr-code/?size=180x180&margin=0&ecc=H&data=${encodeURIComponent(verifyUrl)}`;

  const description = tx.payment_description || tx.description || `Nuru - ${purpose}`;
  const methodLabel = tx.provider_name || tx.method_type || '—';

  // ── Mobile-app inspired dark-navy receipt ──
  // Mirrors mobile/nuru/lib/screens/wallet/receipt_screen.dart:
  //   • Dark gradient hero (#1F1F2E → #111827) with white "RECEIPT" tag + status pill
  //   • Big amount with currency caption + description line
  //   • Inline-SVG icon rows for Reference / Date / Completed / Status / Method
  //   • Soft-bordered totals card with Subtotal / Service fee / Total
  //   • QR with embedded Nuru mark, "Scan to verify" caption
  return `
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><title>Receipt ${tx.transaction_code}</title>
    <style>
      @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=Space+Mono:wght@400;700&display=swap');
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body { display: flex; justify-content: center; align-items: flex-start; min-height: 100vh; background: #F7F7F8; font-family: 'Inter', sans-serif; padding: 24px 16px; color: #0F172A; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      .receipt { width: 720px; max-width: 100%; background: #fff; border-radius: 20px; overflow: hidden; border: 1px solid #EDEDF2; }
      .hero { padding: 28px 32px 26px; background: linear-gradient(135deg, #1F1F2E 0%, #111827 100%); color: #fff; }
      .hero-top { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
      .tag { display: inline-block; padding: 5px 11px; border-radius: 6px; background: rgba(255,255,255,0.15); font-size: 10px; letter-spacing: 0.18em; font-weight: 800; }
      .status-pill { display: inline-flex; align-items: center; gap: 6px; padding: 5px 12px; border-radius: 999px; font-size: 11px; font-weight: 700; background: ${statusBg}; color: ${statusFg}; }
      .status-pill::before { content: '●'; font-size: 8px; }
      .amount-block { margin-top: 22px; }
      .amount-block .label { font-size: 10px; letter-spacing: 0.16em; color: rgba(255,255,255,0.65); font-weight: 700; text-transform: uppercase; }
      .amount-block h1 { margin-top: 6px; font-size: 32px; font-weight: 800; letter-spacing: -0.02em; line-height: 1.05; }
      .amount-block .desc { margin-top: 6px; font-size: 13px; color: rgba(255,255,255,0.72); }
      .perforation { position: relative; height: 22px; background: #fff; }
      .perforation::before, .perforation::after { content: ''; position: absolute; top: 50%; transform: translateY(-50%); width: 22px; height: 22px; border-radius: 50%; background: #F7F7F8; }
      .perforation::before { left: -11px; }
      .perforation::after { right: -11px; }
      .perforation .dash { position: absolute; left: 22px; right: 22px; top: 50%; border-top: 2px dashed #E5E7EB; }
      .body { padding: 6px 32px 8px; }
      .body-row { display: grid; grid-template-columns: 1fr auto; gap: 28px; align-items: flex-start; }
      .rows { display: flex; flex-direction: column; gap: 14px; }
      .row { display: flex; align-items: center; gap: 12px; }
      .row .icon { width: 32px; height: 32px; border-radius: 10px; background: #F4F4F7; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; color: #6B7280; }
      .row .icon svg { width: 16px; height: 16px; }
      .row .meta { flex: 1; min-width: 0; }
      .row .k { font-size: 10px; letter-spacing: 0.14em; color: #9CA3AF; font-weight: 600; text-transform: uppercase; }
      .row .v { margin-top: 2px; font-size: 14px; font-weight: 600; color: #0F172A; word-break: break-word; }
      .row .v.mono { font-family: 'Space Mono', monospace; letter-spacing: 0.06em; font-size: 13px; }
      .qr { text-align: center; }
      .qr-box { padding: 8px; background: #fff; border: 1px solid #EDEDF2; border-radius: 14px; display: inline-block; line-height: 0; position: relative; }
      .qr-box img.code { width: 110px; height: 110px; display: block; }
      .qr-box img.logo { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); width: 26px; height: 26px; object-fit: contain; background: #fff; padding: 2px; border-radius: 6px; }
      .qr .scan { margin-top: 8px; font-size: 10px; letter-spacing: 0.14em; color: #9CA3AF; font-weight: 700; text-transform: uppercase; }
      .totals { margin: 22px 32px 0; border: 1px solid #EDEDF2; border-radius: 14px; overflow: hidden; }
      .totals .trow { display: flex; justify-content: space-between; align-items: center; padding: 13px 18px; font-size: 14px; border-bottom: 1px solid #F3F4F7; }
      .totals .trow:last-child { border-bottom: none; font-weight: 700; background: #FAFAFB; }
      .totals .muted { color: #9CA3AF; }
      .reason { margin: 18px 32px 0; padding: 12px 14px; background: #FEF2F2; border: 1px solid #FECACA; border-radius: 12px; font-size: 12px; color: #991B1B; }
      .reason b { display: block; margin-bottom: 2px; font-weight: 700; }
      .gateway { margin: 14px 32px 0; font-size: 11px; color: #9CA3AF; }
      .gateway span { font-family: 'Space Mono', monospace; color: #6B7280; }
      .footer { margin-top: 22px; padding: 16px 32px; border-top: 1px solid #F0F0F4; display: flex; justify-content: space-between; align-items: center; gap: 12px; font-size: 11px; color: #9CA3AF; background: #FAFAFB; }
      .footer .badge { padding: 4px 10px; border: 1px solid #EDEDF2; border-radius: 999px; font-size: 10px; color: #6B7280; background: #fff; }
      @media print {
        body { background: #fff; padding: 0; }
        .receipt { border: none; border-radius: 0; width: 100%; }
      }
      @page { size: A4; margin: 12mm; }
    </style></head>
    <body>
      <div class="receipt">
        <div class="hero">
          <div class="hero-top">
            <span class="tag">RECEIPT</span>
            <span class="status-pill">${statusText}</span>
          </div>
          <div class="amount-block">
            <div class="label">${isPaid ? 'Amount paid' : 'Amount'}</div>
            <h1>${fmt(tx.gross_amount || 0)}</h1>
            <div class="desc">${description}</div>
          </div>
        </div>

        <div class="perforation"><div class="dash"></div></div>

        <div class="body">
          <div class="body-row">
            <div class="rows">
              <div class="row">
                <span class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg></span>
                <div class="meta"><div class="k">Reference</div><div class="v mono">${tx.transaction_code}</div></div>
              </div>
              <div class="row">
                <span class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg></span>
                <div class="meta"><div class="k">Date</div><div class="v">${dateStr(tx.initiated_at || tx.created_at)}</div></div>
              </div>
              ${tx.completed_at ? `
              <div class="row">
                <span class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg></span>
                <div class="meta"><div class="k">Completed</div><div class="v">${dateStr(tx.completed_at)}</div></div>
              </div>` : ''}
              <div class="row">
                <span class="icon" style="color:${statusFg};background:${statusBg}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M9 12l2 2 4-4"/></svg></span>
                <div class="meta"><div class="k">Status</div><div class="v" style="color:${statusFg};text-transform:capitalize">${statusText}</div></div>
              </div>
              <div class="row">
                <span class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="5" width="20" height="14" rx="2"/><line x1="2" y1="10" x2="22" y2="10"/></svg></span>
                <div class="meta"><div class="k">Method</div><div class="v" style="text-transform:capitalize">${methodLabel}</div></div>
              </div>
            </div>
            <div class="qr">
              <div class="qr-box"><img class="code" src="${qrSrc}" alt="QR" /><img class="logo" src="${logoSquareAbsoluteUrl}" alt="Nuru" /></div>
              <div class="scan">Scan to verify</div>
            </div>
          </div>
        </div>

        <div class="totals">
          <div class="trow"><span class="muted">Subtotal</span><span>${fmt(subtotal)}</span></div>
          <div class="trow"><span class="muted">Service fee</span><span class="muted">${fee > 0 ? fmt(fee) : 'Free'}</span></div>
          <div class="trow"><span>Total</span><span>${fmt(tx.gross_amount || 0)}</span></div>
        </div>

        ${tx.failure_reason ? `<div class="reason"><b>Reason</b>${tx.failure_reason}</div>` : ''}
        ${tx.external_reference ? `<p class="gateway">Gateway reference: <span>${tx.external_reference}</span></p>` : ''}

        <div class="footer">
          <span>Verify at ${host}/shared/receipt/${tx.transaction_code}</span>
          <span class="badge"><img src="${logoAbsoluteUrl}" alt="Nuru" style="height:10px;vertical-align:middle;margin-right:4px"/>© ${new Date().getFullYear()} Nuru</span>
        </div>
      </div>
    </body></html>
  `;
};

