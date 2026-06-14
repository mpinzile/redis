/**
 * WhatsApp Logs export helpers
 * -----------------------------
 * Generates the user-facing Excel and PDF reports for the WhatsApp Logs
 * page. The PDF is branded with the Nuru logo and a clean tabular layout;
 * the Excel uses tidy column widths and frozen headers so it is the
 * "best ever" report for ops review.
 */
import * as XLSX from "xlsx";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import nuruLogo from "@/assets/nuru-logo.png";
import type { WaLog } from "@/lib/api/whatsappLogs";

/** Human-readable Meta error codes — kept in sync with the backend. */
export const WA_ERROR_LABELS: Record<string, string> = {
  "131026": "Recipient is not on WhatsApp",
  "131047": "Outside 24-hour window · template required",
  "131051": "Unsupported message type",
  "131053": "Image rejected · convert PNG to JPG",
  "131056": "Pair rate limit reached",
  "132000": "Template parameter count mismatch",
  "132001": "Template missing in chosen language",
  "132005": "Translated text too long",
  "132007": "Template paused (low quality)",
  "132012": "Template parameter format invalid",
  "132015": "Template paused",
  "132016": "Template disabled",
  "133010": "Number not registered with WhatsApp Business",
  "1":      "Meta-side error (billing / template review)",
  "2":      "Temporary Meta API outage",
  "470":    "Outside 24-hour customer window",
};

export function labelForErrorCode(code: string | null | undefined): string {
  if (!code) return "—";
  return WA_ERROR_LABELS[code] ? `${code} - ${WA_ERROR_LABELS[code]}` : code;
}

function fmt(d: string | null | undefined) {
  if (!d) return "";
  try { return new Date(d).toLocaleString(); } catch { return d; }
}

function rows(logs: WaLog[]) {
  return logs.map((l) => ({
    Recipient: l.recipient_name || "",
    Phone: l.recipient_phone || "",
    "On WhatsApp":
      l.whatsapp_available === true ? "Yes"
      : l.whatsapp_available === false ? "No" : "Unknown",
    Event: l.event_name_snapshot || "",
    Purpose: l.message_purpose || l.category || "",
    Template: l.template_name || l.action || "",
    Type: l.message_type || "",
    Status: l.status,
    "Error code": l.error_code || "",
    "Failure reason": l.failure_reason || "",
    "Fallback": l.fallback_attempted ? (l.fallback_status || "attempted") : "",
    Created: fmt(l.created_at),
    Updated: fmt(l.updated_at),
  }));
}

export function exportLogsToExcel(logs: WaLog[], filename = "whatsapp-logs") {
  const data = rows(logs);
  const ws = XLSX.utils.json_to_sheet(data);
  // Column widths sized to typical content.
  ws["!cols"] = [
    { wch: 26 }, { wch: 14 }, { wch: 11 }, { wch: 28 }, { wch: 18 },
    { wch: 24 }, { wch: 10 }, { wch: 11 }, { wch: 10 }, { wch: 44 },
    { wch: 14 }, { wch: 20 }, { wch: 20 },
  ];
  ws["!freeze"] = { xSplit: 0, ySplit: 1 } as any;
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, "WhatsApp Logs");
  XLSX.writeFile(wb, `${filename}-${new Date().toISOString().slice(0,10)}.xlsx`);
}

async function loadLogo(): Promise<{ dataUrl: string; w: number; h: number } | null> {
  try {
    const res = await fetch(nuruLogo);
    const blob = await res.blob();
    const dataUrl: string = await new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onloadend = () => resolve(r.result as string);
      r.onerror = () => reject(new Error("logo read failed"));
      r.readAsDataURL(blob);
    });
    const dims: { w: number; h: number } = await new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve({ w: img.naturalWidth, h: img.naturalHeight });
      img.onerror = () => resolve({ w: 1, h: 1 });
      img.src = dataUrl;
    });
    return { dataUrl, w: dims.w, h: dims.h };
  } catch { return null; }
}

const STATUS_COLOR: Record<string, [number, number, number]> = {
  delivered: [16, 185, 129],
  read:      [139, 92, 246],
  sent:      [56, 189, 248],
  queued:    [148, 163, 184],
  pending:   [148, 163, 184],
  failed:    [244, 63, 94],
  rejected:  [245, 158, 11],
  unknown:   [148, 163, 184],
};

export async function exportLogsToPdf(
  logs: WaLog[],
  filters: { label: string; value: string }[] = [],
  filename = "whatsapp-logs",
) {
  const doc = new jsPDF({ orientation: "landscape", unit: "pt", format: "a4" });
  const pageWidth = doc.internal.pageSize.getWidth();
  const pageHeight = doc.internal.pageSize.getHeight();

  // ── Clean header (no background fill, logo preserved) ──────────
  const margin = 32;
  const logo = await loadLogo();
  let textX = margin;
  if (logo) {
    const targetH = 36;
    const targetW = Math.max(8, (logo.w / Math.max(1, logo.h)) * targetH);
    try { doc.addImage(logo.dataUrl, "PNG", margin, 24, targetW, targetH); } catch { /* ignore */ }
    textX = margin + targetW + 12;
  }

  doc.setTextColor(15, 23, 42);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(16);
  doc.text("WhatsApp Logs", textX, 42);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(9.5);
  doc.setTextColor(100, 116, 139);
  doc.text(
    `Generated ${new Date().toLocaleString()}  -  ${logs.length} record${logs.length === 1 ? "" : "s"}`,
    textX,
    58,
  );

  // Thin hairline rule under header.
  doc.setDrawColor(226, 232, 240);
  doc.setLineWidth(0.5);
  doc.line(margin, 74, pageWidth - margin, 74);

  // ── Active filters chip line ─────────────────────────────────
  let cursorY = 84;
  if (filters.length) {
    doc.setTextColor(71, 85, 105);
    doc.setFontSize(9);
    const line = filters.map((f) => `${f.label}: ${f.value}`).join("   •   ");
    doc.text(line, 24, cursorY);
    cursorY += 14;
  }

  // ── Table ────────────────────────────────────────────────────
  const head = [[
    "Recipient", "Phone", "WA?", "Event", "Purpose",
    "Template", "Type", "Status", "Code", "Failure", "Time",
  ]];
  const body = logs.map((l) => [
    l.recipient_name || "—",
    l.recipient_phone || "—",
    l.whatsapp_available === true ? "Yes" : l.whatsapp_available === false ? "No" : "?",
    l.event_name_snapshot || "—",
    l.message_purpose || l.category || "—",
    l.template_name || l.action || "—",
    l.message_type || "—",
    l.status,
    l.error_code || "",
    l.failure_reason || "",
    fmt(l.created_at),
  ]);

  autoTable(doc, {
    head,
    body,
    startY: cursorY + 4,
    margin: { left: 24, right: 24, bottom: 36 },
    styles: { font: "helvetica", fontSize: 8, cellPadding: 4, overflow: "linebreak", valign: "middle" },
    headStyles: { fillColor: [241, 245, 249], textColor: [15, 23, 42], fontStyle: "bold", lineWidth: 0 },
    alternateRowStyles: { fillColor: [250, 250, 252] },
    columnStyles: {
      0: { cellWidth: 90 },
      1: { cellWidth: 70 },
      2: { cellWidth: 30, halign: "center" },
      3: { cellWidth: 110 },
      4: { cellWidth: 70 },
      5: { cellWidth: 85 },
      6: { cellWidth: 38 },
      7: { cellWidth: 50 },
      8: { cellWidth: 36 },
      9: { cellWidth: 140 },
      10: { cellWidth: 70 },
    },
    didParseCell: (data) => {
      if (data.section === "body" && data.column.index === 7) {
        const c = STATUS_COLOR[String(data.cell.raw || "").toLowerCase()];
        if (c) {
          data.cell.styles.textColor = c;
          data.cell.styles.fontStyle = "bold";
        }
      }
      if (data.section === "body" && data.column.index === 9 && data.cell.raw) {
        data.cell.styles.textColor = [185, 28, 28];
      }
    },
    didDrawPage: () => {
      const pageNum = (doc as any).internal.getNumberOfPages();
      doc.setFontSize(8);
      doc.setTextColor(148, 163, 184);
      doc.text(
        `Page ${pageNum}  -  WhatsApp Logs`,
        pageWidth / 2,
        pageHeight - 18,
        { align: "center" },
      );
    },
  });

  doc.save(`${filename}-${new Date().toISOString().slice(0,10)}.pdf`);
}
