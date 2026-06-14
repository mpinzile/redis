import { useRef } from 'react';
import { QRCodeCanvas } from 'qrcode.react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent } from '@/components/ui/dialog';
import { CheckCircle2, Clock, Info, MapPin, Printer } from 'lucide-react';
import NuruLogo from '@/assets/nuru-logo.png';

/**
 * Premium "digital pass" ticket — mirrors the mobile YourTicketScreen aesthetic:
 *   • Dark hero (uses event cover when supplied) with Nuru logo + class pill
 *   • Perforated edge: notch + dashed dividers between sections
 *   • Large QR with status circle and reference code in mono
 *   • Info row (Ticket for / Entry type / Amount paid)
 *   • Venue + Important blocks at the bottom
 *
 * Same look on screen (Dialog) and on the printed HTML so saving as PDF
 * matches what the buyer just saw.
 */

interface TicketData {
  ticket_code: string;
  event_title: string;
  event_date?: string;
  event_time?: string;
  event_location?: string;
  ticket_class?: string;
  quantity?: number;
  buyer_name?: string;
  total_amount?: number;
  currency?: string;
  status?: string;
  cover_image_url?: string;
  checked_in?: boolean;
  checked_in_at?: string;
}

interface PrintableTicketProps {
  ticket: TicketData;
  open: boolean;
  onClose: () => void;
}

const formatDate = (dateStr: string) => {
  try {
    return new Date(dateStr).toLocaleDateString('en-GB', {
      weekday: 'short', day: 'numeric', month: 'short', year: 'numeric',
    });
  } catch {
    return dateStr;
  }
};

// Tier accent color for the class pill — matches mobile _classColor
const classColor = (cls?: string) => {
  const c = (cls || '').toLowerCase();
  if (c.includes('vip')) return '#7C3AED';
  if (c.includes('premium') || c.includes('platinum')) return '#B45309';
  if (c.includes('gold')) return '#CA8A04';
  return '#E85A30';
};

const PrintableTicket = ({ ticket, open, onClose }: PrintableTicketProps) => {
  const qrRef = useRef<HTMLDivElement>(null);
  const accent = classColor(ticket.ticket_class);
  const isConfirmed = ['confirmed', 'approved', 'paid'].includes((ticket.status || '').toLowerCase());
  const isUsed = ticket.checked_in === true;
  const qrValue = `https://nuru.tz/ticket/${ticket.ticket_code}`;

  const usedLabel = (() => {
    if (!isUsed) return '';
    const at = ticket.checked_in_at;
    if (!at) return 'Used at the gate';
    try {
      const d = new Date(at);
      return `Used - ${d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}, ${d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })}`;
    } catch {
      return 'Used at the gate';
    }
  })();

  const statusText = isUsed
    ? usedLabel
    : isConfirmed ? 'This ticket is valid for entry.'
    : 'Awaiting confirmation.';

  const statusColor = isUsed
    ? '#6B7280'
    : isConfirmed ? '#15803D' : '#D97706';

  const statusLabel = isUsed
    ? 'Used'
    : (ticket.status || 'Pending').replace(/^./, c => c.toUpperCase());

  const getQrDataUrl = (): string => {
    const canvas = qrRef.current?.querySelector('canvas');
    return canvas ? canvas.toDataURL('image/png') : '';
  };

  const handlePrint = () => {
    const qrImg = getQrDataUrl();
    const cover = ticket.cover_image_url || '';
    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Ticket - ${ticket.event_title}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=Space+Mono:wght@400;700&display=swap');
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { display: flex; justify-content: center; align-items: flex-start; min-height: 100vh; background: #F7F7F8; font-family: 'Inter', sans-serif; padding: 24px 16px; color: #0F172A; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .ticket { width: 480px; max-width: 100%; background: #fff; border-radius: 20px; overflow: hidden; position: relative; }
  .hero { position: relative; height: 180px; background: linear-gradient(135deg, #1F1F2E 0%, #111827 100%); ${cover ? `background-image: linear-gradient(rgba(0,0,0,0.45), rgba(0,0,0,0.78)), url('${cover}'); background-size: cover; background-position: center;` : ''} color: #fff; padding: 18px 22px; display: flex; flex-direction: column; justify-content: space-between; }
  .hero-top { display: flex; align-items: center; justify-content: space-between; }
  .hero-top img { height: 22px; }
  .class-pill { padding: 6px 12px; background: ${accent}; border-radius: 8px; font-size: 11px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #fff; }
  .hero h1 { font-size: 19px; font-weight: 700; line-height: 1.25; margin-bottom: 6px; }
  .hero .when { font-size: 12.5px; font-weight: 500; color: rgba(255,255,255,0.85); }
  /* perforation notches */
  .notch { position: relative; height: 0; }
  .notch::before, .notch::after { content: ''; position: absolute; top: -12px; width: 24px; height: 24px; background: #F7F7F8; border-radius: 50%; }
  .notch::before { left: -12px; }
  .notch::after { right: -12px; }
  .qr-section { padding: 24px 20px 18px; text-align: center; }
  .qr-box { display: inline-block; padding: 14px; background: #fff; border: 1px solid #EDEDF2; border-radius: 14px; line-height: 0; position: relative; }
  .qr-box img { width: 180px; height: 180px; display: block; ${isUsed ? 'opacity:0.35;' : ''} }
  .used-stamp { position: absolute; top: 50%; left: 50%; transform: translate(-50%,-50%) rotate(-20deg); padding: 6px 16px; background: #6B7280; color: #fff; font-weight: 900; letter-spacing: 0.25em; border-radius: 6px; font-size: 18px; }
  .ticket-code { margin-top: 14px; font-family: 'Space Mono', monospace; font-size: 13px; color: #6B7280; letter-spacing: 0.16em; font-weight: 600; }
  .status-line { margin-top: 14px; display: flex; align-items: center; justify-content: center; gap: 8px; font-size: 14px; font-weight: 700; color: ${statusColor}; }
  .status-sub { margin-top: 4px; font-size: 12px; color: #9CA3AF; }
  .dashed { border-top: 2px dashed #E5E7EB; margin: 18px 20px; }
  .info-row { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; padding: 0 20px; }
  .info-row .k { font-size: 9.5px; font-weight: 700; color: #9CA3AF; letter-spacing: 0.12em; text-transform: uppercase; }
  .info-row .v { margin-top: 6px; font-size: 14px; font-weight: 700; color: #0F172A; }
  .blk { display: flex; gap: 12px; padding: 0 20px 14px; align-items: flex-start; }
  .blk svg { width: 16px; height: 16px; color: #9CA3AF; flex-shrink: 0; margin-top: 1px; }
  .blk .k { font-size: 9.5px; font-weight: 700; color: #9CA3AF; letter-spacing: 0.12em; text-transform: uppercase; }
  .blk .v { margin-top: 4px; font-size: 13.5px; color: #0F172A; line-height: 1.45; font-weight: 600; }
  .blk.muted .v { color: #6B7280; font-weight: 500; font-size: 12.5px; }
  .pad-bottom { padding-bottom: 28px; }
  @media print { body { background: #fff; padding: 0; } .ticket { border-radius: 0; width: 100%; } .notch::before, .notch::after { background: #fff; } }
  @page { size: auto; margin: 12mm; }
</style></head><body>
<div class="ticket">
  <div class="hero">
    <div class="hero-top">
      <img src="${new URL(NuruLogo, window.location.origin).href}" alt="Nuru" />
      ${ticket.ticket_class ? `<span class="class-pill">${ticket.ticket_class}</span>` : ''}
    </div>
    <div>
      <h1>${ticket.event_title}</h1>
      <div class="when">${ticket.event_date ? formatDate(ticket.event_date) : ''}${ticket.event_time ? `  •  ${ticket.event_time}` : ''}</div>
    </div>
  </div>

  <div class="notch"></div>

  <div class="qr-section">
    <div class="qr-box">
      ${qrImg ? `<img src="${qrImg}" alt="QR" />` : ''}
      ${isUsed ? `<div class="used-stamp">USED</div>` : ''}
    </div>
    <div class="ticket-code">${ticket.ticket_code}</div>
    <div class="status-line">
      <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">${isUsed ? '<circle cx="12" cy="12" r="10"/><line x1="8" y1="12" x2="16" y2="12"/>' : isConfirmed ? '<circle cx="12" cy="12" r="10"/><path d="M9 12l2 2 4-4"/>' : '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>'}</svg>
      ${statusLabel}
    </div>
    <div class="status-sub">${statusText}</div>
  </div>

  <div class="dashed"></div>

  <div class="info-row">
    <div><div class="k">Ticket for</div><div class="v">${ticket.quantity || 1} ${(ticket.quantity || 1) > 1 ? 'People' : 'Person'}</div></div>
    ${ticket.ticket_class ? `<div><div class="k">Entry type</div><div class="v">${ticket.ticket_class}</div></div>` : ''}
    ${ticket.total_amount ? `<div><div class="k">Amount paid</div><div class="v">${ticket.currency || 'TZS'} ${ticket.total_amount.toLocaleString()}</div></div>` : ''}
  </div>

  <div class="dashed"></div>

  ${ticket.event_location ? `
  <div class="blk">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
    <div><div class="k">Venue</div><div class="v">${ticket.event_location}</div></div>
  </div>` : ''}

  <div class="blk muted pad-bottom">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
    <div><div class="k">Important</div><div class="v">Please arrive early and present this ticket at the entrance. Non-transferable.</div></div>
  </div>
</div>
</body></html>`;

    const w = window.open('', '_blank');
    if (w) {
      w.document.write(html);
      w.document.close();
      setTimeout(() => w.print(), 500);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-md p-0 overflow-hidden bg-[#F7F7F8] border-0">
        <div className="bg-background rounded-2xl overflow-hidden m-0">
          {/* HERO */}
          <div
            className="relative h-44 px-5 pt-4 pb-5 flex flex-col justify-between text-white"
            style={{
              backgroundImage: ticket.cover_image_url
                ? `linear-gradient(rgba(0,0,0,0.45), rgba(0,0,0,0.78)), url('${ticket.cover_image_url}')`
                : 'linear-gradient(135deg, #1F1F2E 0%, #111827 100%)',
              backgroundSize: 'cover',
              backgroundPosition: 'center',
            }}
          >
            <div className="flex items-center justify-between">
              <img src={NuruLogo} alt="Nuru" className="h-5" />
              {ticket.ticket_class && (
                <span
                  className="px-3 py-1.5 rounded-lg text-[11px] font-bold tracking-wide uppercase text-white"
                  style={{ background: accent }}
                >
                  {ticket.ticket_class}
                </span>
              )}
            </div>
            <div>
              <h1 className="text-[19px] font-bold leading-tight line-clamp-2">{ticket.event_title}</h1>
              <p className="text-xs font-medium text-white/85 mt-1.5">
                {ticket.event_date ? formatDate(ticket.event_date) : ''}
                {ticket.event_time ? `  •  ${ticket.event_time}` : ''}
              </p>
            </div>
          </div>

          {/* perforation notches */}
          <div className="relative h-0">
            <div className="absolute -top-3 -left-3 w-6 h-6 rounded-full bg-[#F7F7F8]" />
            <div className="absolute -top-3 -right-3 w-6 h-6 rounded-full bg-[#F7F7F8]" />
          </div>

          {/* QR + STATUS */}
          <div className="px-5 pt-6 pb-4 text-center">
            <div ref={qrRef} className="inline-block p-3.5 bg-white border border-[#EDEDF2] rounded-2xl relative">
              <QRCodeCanvas
                value={qrValue}
                size={180}
                level="M"
                fgColor="#0F172A"
                bgColor="#ffffff"
                style={{ opacity: isUsed ? 0.35 : 1 }}
              />
              {isUsed && (
                <span
                  className="absolute top-1/2 left-1/2 px-3.5 py-1.5 bg-muted-foreground text-white text-lg font-black tracking-[0.25em] rounded"
                  style={{ transform: 'translate(-50%,-50%) rotate(-20deg)' }}
                >
                  USED
                </span>
              )}
            </div>
            <div className="mt-3.5 font-mono text-[13px] font-semibold text-muted-foreground tracking-[0.16em]">
              {ticket.ticket_code}
            </div>
            <div
              className="mt-3.5 flex items-center justify-center gap-2 text-sm font-bold"
              style={{ color: statusColor }}
            >
              {isUsed
                ? <Info size={18} />
                : isConfirmed
                  ? <CheckCircle2 size={18} />
                  : <Clock size={18} />}
              {statusLabel}
            </div>
            <div className="mt-1 text-xs text-muted-foreground">{statusText}</div>
          </div>

          <div className="border-t-2 border-dashed border-border mx-5 my-4" />

          {/* INFO ROW */}
          <div className="grid grid-cols-3 gap-3 px-5">
            <Cell label="Ticket for" value={`${ticket.quantity || 1} ${(ticket.quantity || 1) > 1 ? 'People' : 'Person'}`} />
            {ticket.ticket_class && <Cell label="Entry type" value={ticket.ticket_class} />}
            {ticket.total_amount ? (
              <Cell label="Amount paid" value={`${ticket.currency || 'TZS'} ${ticket.total_amount.toLocaleString()}`} />
            ) : null}
          </div>

          <div className="border-t-2 border-dashed border-border mx-5 my-4" />

          {ticket.event_location && (
            <div className="px-5 pb-3.5 flex gap-3">
              <MapPin className="w-4 h-4 text-muted-foreground flex-shrink-0 mt-0.5" />
              <div>
                <div className="text-[9.5px] font-bold text-muted-foreground tracking-[0.12em] uppercase">Venue</div>
                <div className="text-[13.5px] font-semibold text-foreground leading-snug mt-1">{ticket.event_location}</div>
              </div>
            </div>
          )}

          <div className="px-5 pb-5 flex gap-3">
            <Info className="w-4 h-4 text-muted-foreground flex-shrink-0 mt-0.5" />
            <div>
              <div className="text-[9.5px] font-bold text-muted-foreground tracking-[0.12em] uppercase">Important</div>
              <div className="text-[12.5px] text-muted-foreground leading-snug mt-1">
                Please arrive early and present this ticket at the entrance. Non-transferable.
              </div>
            </div>
          </div>

          <div className="px-5 py-4 border-t border-border bg-muted/30 flex justify-end">
            <Button size="sm" onClick={handlePrint} className="gap-2">
              <Printer className="w-4 h-4" /> Print / Save PDF
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};

const Cell = ({ label, value }: { label: string; value: string }) => (
  <div>
    <div className="text-[9.5px] font-bold text-muted-foreground tracking-[0.12em] uppercase">{label}</div>
    <div className="text-sm font-bold text-foreground mt-1.5 break-words">{value}</div>
  </div>
);

export default PrintableTicket;
