/**
 * Bulk import dialog for Committee members and Guests.
 *
 * Accepts CSV/XLSX. Backend de-dupes by normalized phone and creates new
 * Nuru users for any missing phone numbers. Optionally notifies new members
 * via SMS. Polls the job until completion and surfaces a per-row summary.
 */
import { useEffect, useRef, useState } from "react";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/hooks/use-toast";
import { toast as sonnerToast } from "sonner";
import { showApiErrors } from "@/lib/api/showApiErrors";
import { memberImportsApi, type MemberImportJob, type MemberImportMode } from "@/lib/api/memberImports";
import readXlsxFile from "read-excel-file";
import { Upload, Loader2, FileSpreadsheet, CheckCircle2, XCircle, Eye, EyeOff, Download, Info } from "lucide-react";
import { startTask, updateTask, appendDetail, finishTask } from "@/lib/backgroundTasks/store";
import DismissibleHint from "@/components/background/DismissibleHint";

// Read a CSV or XLSX file in the browser into a 2D array of strings.
// We always normalise to text rows so the same preview + CSV upload code
// works for both formats. The backend only ever sees CSV.
async function readSpreadsheet(file: File): Promise<string[][]> {
  const isExcel = /\.(xlsx|xlsm|xls)$/i.test(file.name);
  if (isExcel) {
    const rows = await readXlsxFile(file);
    return rows.map((r) => r.map((c) => (c === null || c === undefined ? "" : String(c))));
  }
  const text = await file.text();
  // Minimal CSV parser that handles quoted fields with commas/newlines.
  const out: string[][] = [];
  let cur: string[] = [];
  let field = "";
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else { inQuotes = false; }
      } else { field += ch; }
    } else if (ch === '"') { inQuotes = true; }
    else if (ch === ",") { cur.push(field); field = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      cur.push(field); field = "";
      out.push(cur); cur = [];
    } else { field += ch; }
  }
  if (field.length || cur.length) { cur.push(field); out.push(cur); }
  return out.filter((r) => r.some((c) => (c || "").trim().length > 0));
}

function rowsToCsvFile(rows: string[][], baseName: string): File {
  const escape = (v: unknown) => {
    const s = v === null || v === undefined ? "" : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csv = rows.map((r) => r.map(escape).join(",")).join("\n");
  return new File([csv], `${baseName.replace(/\.(csv|xlsx|xlsm|xls)$/i, "")}.csv`, { type: "text/csv" });
}

interface Props {
  eventId: string;
  mode: MemberImportMode;
  open: boolean;
  onClose: () => void;
  onCompleted?: () => void;
}

interface TemplateSpec {
  columns: { name: string; required: boolean; hint: string }[];
  rows: string[][];
}

const TEMPLATES: Record<MemberImportMode, TemplateSpec> = {
  committee: {
    columns: [
      { name: "S/N", required: false, hint: "Optional row number" },
      { name: "Full Name", required: true, hint: "Member's full name" },
      { name: "Phone", required: true, hint: "International format only (e.g. +255712345678)" },
    ],
    rows: [
      ["1", "John Doe", "+255712345678"],
      ["2", "Jane Doe", "+255754000111"],
      ["3", "John Smith", "+254711222333"],
    ],
  },
  guests: {
    columns: [
      { name: "S/N", required: false, hint: "Optional row number" },
      { name: "Full Name", required: true, hint: "Guest's full name" },
      { name: "Phone", required: true, hint: "International format only (e.g. +255712345678)" },
      { name: "Common Name", required: false, hint: "How to address on card (optional)" },
    ],
    rows: [
      ["1", "John Doe", "+255712345678", "Mr & Mrs Doe"],
      ["2", "Jane Doe", "+255754000111", ""],
      ["3", "John Smith", "+254700111222", "Mr Smith"],
    ],
  },
};

export default function MemberImportDialog({ eventId, mode, open, onClose, onCompleted }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [previewRows, setPreviewRows] = useState<string[][]>([]);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [parsing, setParsing] = useState(false);
  const [notifySms, setNotifySms] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [job, setJob] = useState<MemberImportJob | null>(null);
  const [showGuide, setShowGuide] = useState(false);
  const [previewPage, setPreviewPage] = useState(1);
  const PREVIEW_PAGE_SIZE = 20;
  const pollRef = useRef<number | null>(null);
  const taskIdRef = useRef<string | null>(null);

  useEffect(() => {
    if (!open) {
      setFile(null);
      setPreviewRows([]);
      setPreviewError(null);
      setParsing(false);
      setNotifySms(false);
      setUploading(false);
      setJob(null);
      setShowGuide(false);
      if (pollRef.current) { window.clearInterval(pollRef.current); pollRef.current = null; }
    }
  }, [open]);

  useEffect(() => () => { if (pollRef.current) window.clearInterval(pollRef.current); }, []);

  // Parse the chosen file in the browser so the organiser can preview it
  // before sending. Works for both CSV and XLSX.
  useEffect(() => {
    setPreviewPage(1);
    if (!file) { setPreviewRows([]); setPreviewError(null); return; }
    let cancelled = false;
    (async () => {
      setParsing(true);
      setPreviewError(null);
      try {
        const rows = await readSpreadsheet(file);
        if (cancelled) return;
        if (!rows.length) {
          setPreviewRows([]);
          setPreviewError("That file looks empty.");
        } else {
          setPreviewRows(rows);
        }
      } catch {
        if (!cancelled) {
          setPreviewRows([]);
          setPreviewError("Could not read that file. Make sure it's a valid CSV or XLSX.");
        }
      } finally {
        if (!cancelled) setParsing(false);
      }
    })();
    return () => { cancelled = true; };
  }, [file]);

  const tpl = TEMPLATES[mode];
  const isDone = job?.status === "completed" || job?.status === "failed" || job?.status === "partially_completed";
  const dataRowCount = Math.max(0, previewRows.length - 1);

  const startPolling = (jobId: string) => {
    if (pollRef.current) window.clearInterval(pollRef.current);
    pollRef.current = window.setInterval(async () => {
      try {
        const r = await memberImportsApi.getJob(eventId, jobId);
        if (r.success && r.data) {
          setJob(r.data);
          const tid = taskIdRef.current;
          if (tid) {
            updateTask(tid, {
              processed: r.data.processed_rows,
              total: r.data.total_rows,
              progress: r.data.total_rows ? r.data.processed_rows / r.data.total_rows : undefined,
            });
          }
          if (r.data.status === "completed" || r.data.status === "failed" || r.data.status === "partially_completed") {
            if (pollRef.current) { window.clearInterval(pollRef.current); pollRef.current = null; }
            if (tid) {
              const s = r.data.summary || ({} as MemberImportJob["summary"]);
              appendDetail(tid, {
                level: r.data.status === "failed" ? "error" : (s.failed ? "warn" : "info"),
                message: `${s.successful ?? 0} added · ${s.reused ?? 0} reused · ${s.duplicates ?? 0} dup · ${s.invalid_phone ?? 0} bad phone · ${s.failed ?? 0} failed`,
              });
              (r.data.errors || []).slice(0, 20).forEach((e) =>
                appendDetail(tid, { level: "error", message: `Row ${e.row ?? "?"}: ${e.reason || e.message || "error"}` }),
              );
              finishTask(tid, r.data.status === "failed" ? "failed" : "success");
              taskIdRef.current = null;
            }
            onCompleted?.();
          }
        }
      } catch {/* swallow — next tick will retry */}
    }, 2000);
  };

  const handleUpload = async () => {
    if (!file) {
      toast({ title: "Pick a file", description: "Choose a CSV or XLSX file to import." });
      return;
    }
    if (previewError || !previewRows.length) {
      sonnerToast.error(previewError || "Nothing to import · the file looks empty.");
      return;
    }
    setUploading(true);
    try {
      // Always send the parsed rows back up as CSV — the backend's CSV path
      // doesn't need openpyxl, so XLSX works without any server change.
      const toUpload = rowsToCsvFile(previewRows, file.name);
      const res = mode === "committee"
        ? await memberImportsApi.importCommittee(eventId, toUpload, notifySms)
        : await memberImportsApi.importGuests(eventId, toUpload, notifySms);
      const jobId: string | undefined = (res as any)?.job_id;
      if (!jobId) {
        sonnerToast.error("Server did not return a job id.");
        return;
      }
      const totalRows = (res as any)?.total_rows ?? dataRowCount;
      setJob({
        job_id: jobId,
        mode,
        status: "queued",
        notify_sms: notifySms,
        total_rows: totalRows,
        processed_rows: 0,
        summary: { total: 0, successful: 0, reused: 0, duplicates: 0, invalid_phone: 0, failed: 0 },
      });
      taskIdRef.current = startTask({
        title: `${mode === "committee" ? "Committee" : "Guest"} import — ${totalRows || dataRowCount} row${(totalRows || dataRowCount) === 1 ? "" : "s"}`,
        subtitle: notifySms ? "Notifying new members via SMS" : "No SMS",
        kind: "import",
        total: totalRows,
        progress: 0,
        meta: { jobId, mode },
        href: `/event-management/${eventId}`,
      });
      startPolling(jobId);
    } catch (err) {
      sonnerToast.error((err as Error)?.message || "Upload failed");
    } finally {
      setUploading(false);
    }
  };

  const downloadTemplate = () => {
    const header = tpl.columns.map((c) => c.name).join(",");
    const body = tpl.rows.map((r) => r.join(",")).join("\n");
    const csv = `${header}\n${body}\n`;
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${mode}-import-template.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            Import {mode === "committee" ? "committee members" : "guests"}
          </DialogTitle>
          <DialogDescription>
            Upload a CSV or XLSX file. Existing Nuru users are matched by phone number;
            missing users are created automatically.
          </DialogDescription>
        </DialogHeader>

        {!job && (
          <div className="space-y-4">
            <div className="rounded-md border bg-muted/30">
              <div className="flex flex-wrap items-center justify-between gap-2 p-3">
                <div className="flex items-center gap-2 text-sm font-medium">
                  <Info className="w-4 h-4 text-primary" />
                  File format
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setShowGuide((s) => !s)}
                    className="h-8 px-2 text-xs"
                  >
                    {showGuide
                      ? (<><EyeOff className="w-3.5 h-3.5 mr-1" /> Hide guide</>)
                      : (<><Eye className="w-3.5 h-3.5 mr-1" /> See guide</>)}
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={downloadTemplate}
                    className="h-8 px-2 text-xs"
                  >
                    <Download className="w-3.5 h-3.5 mr-1" /> Template
                  </Button>
                </div>
              </div>

              {showGuide && (
                <div className="border-t p-3 space-y-3">
                  <div>
                    <p className="text-xs font-medium mb-2">Columns</p>
                    <ul className="space-y-1.5">
                      {tpl.columns.map((c) => (
                        <li key={c.name} className="flex items-start gap-2 text-xs">
                          <Badge
                            variant={c.required ? "default" : "outline"}
                            className="shrink-0 text-[10px] px-1.5 py-0"
                          >
                            {c.required ? "Required" : "Optional"}
                          </Badge>
                          <div className="min-w-0">
                            <span className="font-medium">{c.name}</span>
                            <span className="text-muted-foreground"> — {c.hint}</span>
                          </div>
                        </li>
                      ))}
                    </ul>
                  </div>

                  <div>
                    <p className="text-xs font-medium mb-2">Example rows</p>
                    <div className="overflow-x-auto rounded-md border bg-background -mx-1 px-1">
                      <table className="w-full text-xs min-w-[420px]">
                        <thead>
                          <tr className="bg-muted/50">
                            {tpl.columns.map((c) => (
                              <th key={c.name} className="text-left font-medium px-2 py-1.5 whitespace-nowrap">
                                {c.name}
                                {c.required && <span className="text-destructive ml-0.5">*</span>}
                              </th>
                            ))}
                          </tr>
                        </thead>
                        <tbody>
                          {tpl.rows.map((row, i) => (
                            <tr key={i} className="border-t">
                              {row.map((cell, j) => (
                                <td key={j} className="px-2 py-1.5 whitespace-nowrap text-muted-foreground">
                                  {cell || <span className="italic opacity-50">—</span>}
                                </td>
                              ))}
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                    <p className="text-[11px] text-muted-foreground mt-1.5 sm:hidden">
                      Swipe sideways to see more columns.
                    </p>
                  </div>

                  <ul className="text-[11px] text-muted-foreground space-y-1 list-disc pl-4">
                    <li>Phone numbers must be in international format with country code (e.g. +255712345678, 254711222333). Local formats like 0712… are not accepted.</li>
                    <li>First row must be the header. Extra columns are ignored.</li>
                    <li>Duplicates by phone are skipped automatically.</li>
                    <li>Accepted file types: <span className="font-mono">.csv</span>, <span className="font-mono">.xlsx</span>.</li>
                  </ul>
                </div>
              )}
            </div>

            <FileDropzone file={file} onFile={setFile} />

            {file && (
              <div className="rounded-md border">
                <div className="flex items-center justify-between gap-2 px-3 py-2 border-b bg-muted/30">
                  <div className="text-sm font-medium flex items-center gap-2">
                    <FileSpreadsheet className="w-4 h-4 text-primary" />
                    Preview
                  </div>
                  <div className="text-xs text-muted-foreground">
                    {parsing
                      ? "Reading…"
                      : previewError
                        ? "Could not read file"
                        : `${dataRowCount} row${dataRowCount === 1 ? "" : "s"} detected`}
                  </div>
                </div>

                {parsing && (
                  <div className="p-4 flex items-center gap-2 text-sm text-muted-foreground">
                    <Loader2 className="w-4 h-4 animate-spin" /> Parsing file…
                  </div>
                )}

                {!parsing && previewError && (
                  <div className="p-3 text-xs text-destructive">{previewError}</div>
                )}

                {!parsing && !previewError && previewRows.length > 0 && (() => {
                  const totalPages = Math.max(1, Math.ceil(dataRowCount / PREVIEW_PAGE_SIZE));
                  const page = Math.min(previewPage, totalPages);
                  const startIdx = (page - 1) * PREVIEW_PAGE_SIZE;
                  const endIdx = startIdx + PREVIEW_PAGE_SIZE;
                  const pageRows = previewRows.slice(1 + startIdx, 1 + endIdx);
                  const fromRow = dataRowCount === 0 ? 0 : startIdx + 1;
                  const toRow = Math.min(endIdx, dataRowCount);
                  return (
                    <>
                      <div className="overflow-x-auto max-h-64">
                        <table className="w-full text-xs">
                          <thead className="sticky top-0 bg-background">
                            <tr className="border-b">
                              <th className="text-left font-medium px-2 py-1.5 whitespace-nowrap w-10 text-muted-foreground">#</th>
                              {previewRows[0].map((h, i) => (
                                <th key={i} className="text-left font-medium px-2 py-1.5 whitespace-nowrap">
                                  {h || <span className="italic text-muted-foreground">col {i + 1}</span>}
                                </th>
                              ))}
                            </tr>
                          </thead>
                          <tbody>
                            {pageRows.map((row, i) => (
                              <tr key={startIdx + i} className="border-t">
                                <td className="px-2 py-1.5 whitespace-nowrap text-muted-foreground tabular-nums">
                                  {startIdx + i + 1}
                                </td>
                                {row.map((cell, j) => (
                                  <td key={j} className="px-2 py-1.5 whitespace-nowrap text-muted-foreground">
                                    {cell || <span className="italic opacity-50">—</span>}
                                  </td>
                                ))}
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                      {totalPages > 1 && (
                        <div className="flex items-center justify-between gap-2 px-3 py-2 text-[11px] border-t bg-muted/20">
                          <span className="text-muted-foreground">
                            Rows {fromRow}–{toRow} of {dataRowCount} - page {page} of {totalPages}
                          </span>
                          <div className="flex items-center gap-1">
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              className="h-7 px-2 text-xs"
                              onClick={() => setPreviewPage(1)}
                              disabled={page === 1}
                            >
                              First
                            </Button>
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              className="h-7 px-2 text-xs"
                              onClick={() => setPreviewPage((p) => Math.max(1, p - 1))}
                              disabled={page === 1}
                            >
                              Prev
                            </Button>
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              className="h-7 px-2 text-xs"
                              onClick={() => setPreviewPage((p) => Math.min(totalPages, p + 1))}
                              disabled={page === totalPages}
                            >
                              Next
                            </Button>
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              className="h-7 px-2 text-xs"
                              onClick={() => setPreviewPage(totalPages)}
                              disabled={page === totalPages}
                            >
                              Last
                            </Button>
                          </div>
                        </div>
                      )}
                    </>
                  );
                })()}
              </div>
            )}




            <div className="flex items-start sm:items-center justify-between gap-3 rounded-md border p-3">
              <div className="min-w-0">
                <Label htmlFor="notify-sms" className="text-sm">Notify new members via SMS</Label>
                <p className="text-xs text-muted-foreground">
                  Only sent to newly created accounts. Existing users are skipped.
                </p>
              </div>
              <Switch id="notify-sms" checked={notifySms} onCheckedChange={setNotifySms} />
            </div>
          </div>
        )}



        {job && (
          <div className="space-y-3">
            <div className="flex items-center gap-2 text-sm">
              {isDone
                ? (job.status === "completed"
                    ? <CheckCircle2 className="w-4 h-4 text-green-600" />
                    : <XCircle className="w-4 h-4 text-destructive" />)
                : <Loader2 className="w-4 h-4 animate-spin" />}
              <span className="font-medium capitalize">{job.status}</span>
              {job.total_rows > 0 && (
                <span className="text-muted-foreground">
                  - {job.processed_rows}/{job.total_rows} rows
                </span>
              )}
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 text-xs">
              <SummaryStat label="Added" value={job.summary.successful} tone="success" />
              <SummaryStat label="Reused" value={job.summary.reused} />
              <SummaryStat label="Duplicates" value={job.summary.duplicates} />
              <SummaryStat label="Invalid phone" value={job.summary.invalid_phone} tone="warn" />
              <SummaryStat label="Failed" value={job.summary.failed} tone="error" />
              <SummaryStat label="Total" value={job.summary.total} />
            </div>

            {!!job.errors?.length && (
              <div className="rounded-md border p-2 max-h-40 overflow-auto text-xs space-y-1">
                <p className="font-medium">Issues</p>
                {job.errors.slice(0, 50).map((e, i) => (
                  <div key={i} className="text-muted-foreground">
                    Row {e.row ?? "?"}{e.name ? ` - ${e.name}` : ""}{e.phone ? ` - ${e.phone}` : ""} — {e.reason || e.message || "unknown"}
                  </div>
                ))}
                {job.errors.length > 50 && (
                  <p className="text-muted-foreground">+{job.errors.length - 50} more</p>
                )}
              </div>
            )}
          </div>
        )}

        {(uploading || (job && !isDone)) && (
          <div className="px-1 pt-2"><DismissibleHint /></div>
        )}

        <DialogFooter>
          {!job ? (
            <>
              <Button variant="outline" onClick={onClose} disabled={uploading}>
                {uploading ? "Dismiss (keep running)" : "Cancel"}
              </Button>
              <Button onClick={handleUpload} disabled={!file || uploading || parsing || !!previewError || previewRows.length === 0}>
                {uploading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" /> Uploading</> : <><Upload className="w-4 h-4 mr-2" /> Start import</>}
              </Button>
            </>
          ) : (
            <Button onClick={onClose}>{isDone ? "Done" : "Dismiss (keep running)"}</Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}



const ACCEPTED_EXT = [".csv", ".xlsx"];
const ACCEPT_ATTR = ".csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

function FileDropzone({ file, onFile }: { file: File | null; onFile: (f: File | null) => void }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragOver, setDragOver] = useState(false);

  const validate = (f: File) => {
    const name = f.name.toLowerCase();
    return ACCEPTED_EXT.some((ext) => name.endsWith(ext));
  };

  const pick = (f: File | null) => {
    if (!f) return onFile(null);
    if (!validate(f)) {
      sonnerToast.error("Unsupported file. Use .csv or .xlsx.");
      return;
    }
    onFile(f);
  };

  const ext = file?.name.split(".").pop()?.toUpperCase() || "";

  return (
    <div>
      <Label className="text-sm">Upload file</Label>
      <input
        ref={inputRef}
        type="file"
        accept={ACCEPT_ATTR}
        onChange={(e) => pick(e.target.files?.[0] || null)}
        className="sr-only"
      />

      {!file ? (
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
          onDragLeave={() => setDragOver(false)}
          onDrop={(e) => {
            e.preventDefault();
            setDragOver(false);
            pick(e.dataTransfer.files?.[0] || null);
          }}
          className={`mt-1 w-full rounded-lg border-2 border-dashed px-4 py-6 sm:py-8 flex flex-col items-center justify-center gap-2 text-center transition-colors cursor-pointer
            ${dragOver
              ? "border-primary bg-primary/5"
              : "border-border hover:border-primary/50 hover:bg-muted/30"}`}
        >
          <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
            <Upload className="w-5 h-5 text-primary" />
          </div>
          <div className="space-y-0.5">
            <p className="text-sm font-medium">
              <span className="text-primary">Click to upload</span>
              <span className="hidden sm:inline"> or drag and drop</span>
            </p>
            <p className="text-[11px] text-muted-foreground">CSV or XLSX - up to ~5 MB</p>
          </div>
        </button>
      ) : (
        <div className="mt-1 flex items-center gap-3 rounded-lg border p-3 bg-muted/20">
          <div className="w-10 h-10 rounded-md bg-primary/10 flex items-center justify-center shrink-0">
            <FileSpreadsheet className="w-5 h-5 text-primary" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-medium truncate">{file.name}</p>
            <p className="text-[11px] text-muted-foreground">
              {ext} - {Math.max(1, Math.round(file.size / 1024))} KB
            </p>
          </div>
          <div className="flex items-center gap-1 shrink-0">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="h-8 px-2 text-xs"
              onClick={() => inputRef.current?.click()}
            >
              Replace
            </Button>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="h-8 w-8 p-0 text-muted-foreground hover:text-destructive"
              onClick={() => onFile(null)}
              aria-label="Remove file"
            >
              <XCircle className="w-4 h-4" />
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}


function SummaryStat({ label, value, tone }: { label: string; value: number; tone?: "success" | "warn" | "error" }) {
  const cls = tone === "success" ? "text-green-700 bg-green-50 border-green-200"
    : tone === "warn" ? "text-amber-700 bg-amber-50 border-amber-200"
    : tone === "error" ? "text-red-700 bg-red-50 border-red-200"
    : "text-foreground bg-muted/30";
  return (
    <div className={`rounded-md border px-2 py-1 ${cls}`}>
      <div className="text-[10px] uppercase tracking-wide">{label}</div>
      <div className="text-base font-semibold">{value}</div>
    </div>
  );
}
