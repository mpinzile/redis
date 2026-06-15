/**
 * Smart RSVP Calls dashboard (Phase 8 of nuru_voice.md).
 *
 * Single-page UI for the Nuru Voice Assistant — organiser view:
 *  - List + create voice campaigns (RSVP, contribution, etc.)
 *  - Inspect a campaign's jobs (live status, AI outcome, confidence)
 *  - Add recipients manually (bulk paste or single row)
 *  - Drill into a job for transcript + per-attempt logs
 *  - Manage the global opt-out list
 *
 * Stays self-contained and uses the existing design tokens. No business-
 * logic changes to RSVP/Invitation/Guest modules — this is a thin client
 * on top of /voice-calls/* endpoints.
 */
import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { PhoneCall } from "lucide-react";
import { toast } from "sonner";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Sheet, SheetContent, SheetHeader, SheetTitle,
} from "@/components/ui/sheet";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  Tabs, TabsList, TabsTrigger, TabsContent,
} from "@/components/ui/tabs";
import {
  voiceCallsApi,
  type VoiceCampaign,
  type VoiceCallJob,
  type VoiceCallLog,
  type VoiceOptOut,
  type VoicePurpose,
  type CampaignStatus,
} from "@/lib/api/voiceCalls";
import { showApiErrors } from "@/lib/api";

const STATUS_TONE: Record<string, string> = {
  draft: "bg-muted text-muted-foreground",
  queued: "bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-300",
  running: "bg-emerald-100 text-emerald-800 dark:bg-emerald-500/15 dark:text-emerald-300",
  paused: "bg-orange-100 text-orange-800 dark:bg-orange-500/15 dark:text-orange-300",
  completed: "bg-blue-100 text-blue-800 dark:bg-blue-500/15 dark:text-blue-300",
  cancelled: "bg-muted text-muted-foreground",
  pending: "bg-muted text-muted-foreground",
  in_progress: "bg-emerald-100 text-emerald-800 dark:bg-emerald-500/15 dark:text-emerald-300",
  failed: "bg-red-100 text-red-800 dark:bg-red-500/15 dark:text-red-300",
  no_answer: "bg-orange-100 text-orange-800 dark:bg-orange-500/15 dark:text-orange-300",
  busy: "bg-orange-100 text-orange-800 dark:bg-orange-500/15 dark:text-orange-300",
  opted_out: "bg-red-100 text-red-800 dark:bg-red-500/15 dark:text-red-300",
  blocked: "bg-red-100 text-red-800 dark:bg-red-500/15 dark:text-red-300",
};

function StatusPill({ value }: { value: string | null | undefined }) {
  const v = value || "—";
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium uppercase tracking-wide ${
        STATUS_TONE[v] ?? "bg-muted text-muted-foreground"
      }`}
    >
      {v.replace(/_/g, " ")}
    </span>
  );
}

function fmtDate(s: string | null | undefined) {
  if (!s) return "—";
  try {
    return new Date(s).toLocaleString();
  } catch {
    return s;
  }
}

export default function VoiceCalls() {
  const [searchParams] = useSearchParams();
  const scopedEventId = searchParams.get("event_id") || "";
  const [tab, setTab] = useState<"campaigns" | "opt-outs">("campaigns");
  const [campaigns, setCampaigns] = useState<VoiceCampaign[]>([]);
  const [loading, setLoading] = useState(true);
  const [createOpen, setCreateOpen] = useState(false);
  const [callOneOpen, setCallOneOpen] = useState(false);
  const [activeCampaign, setActiveCampaign] = useState<VoiceCampaign | null>(null);
  const [jobDetail, setJobDetail] = useState<{
    job: VoiceCallJob;
    logs: VoiceCallLog[];
  } | null>(null);

  async function loadCampaigns() {
    setLoading(true);
    const res = await voiceCallsApi.listCampaigns({
      page: 1,
      page_size: 50,
      ...(scopedEventId ? { event_id: scopedEventId } : {}),
    });
    if (res.success) setCampaigns(res.data || []);
    else showApiErrors(res);
    setLoading(false);
  }

  useEffect(() => {
    loadCampaigns();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scopedEventId]);

  return (
    <div className="bg-white min-h-screen">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        <header className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
          <div>
            <p className="text-xs uppercase tracking-[0.18em] text-muted-foreground">
              Nuru Voice Assistant
            </p>
            <h1 className="text-3xl font-semibold tracking-tight mt-1">
              Smart RSVP Calls
            </h1>
            <p className="text-sm text-muted-foreground mt-2 max-w-2xl">
              Reach your guests by phone in Swahili or English and write
              their answers straight back to your event. Nothing is dialled
              until you start a campaign.
            </p>
            {scopedEventId && (
              <p className="text-xs text-muted-foreground mt-2">
                Scoped to event <span className="font-mono">{scopedEventId.slice(0, 8)}…</span>
              </p>
            )}
          </div>
          {tab === "campaigns" && (
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setCallOneOpen(true)}>
                <PhoneCall className="h-4 w-4 mr-2" />
                Call one person
              </Button>
              <Button onClick={() => setCreateOpen(true)}>New campaign</Button>
            </div>
          )}
        </header>

        <Tabs value={tab} onValueChange={(v) => setTab(v as typeof tab)}>
          <TabsList>
            <TabsTrigger value="campaigns">Campaigns</TabsTrigger>
            <TabsTrigger value="opt-outs">Opt-outs</TabsTrigger>
          </TabsList>

          <TabsContent value="campaigns" className="mt-6">
            <CampaignsTable
              loading={loading}
              campaigns={campaigns}
              onOpen={(c) => setActiveCampaign(c)}
              onChanged={loadCampaigns}
            />
          </TabsContent>

          <TabsContent value="opt-outs" className="mt-6">
            <OptOutsPanel />
          </TabsContent>
        </Tabs>

        <CreateCampaignDialog
          open={createOpen}
          onOpenChange={setCreateOpen}
          defaultEventId={scopedEventId}
          onCreated={async () => {
            setCreateOpen(false);
            await loadCampaigns();
          }}
        />

        <CallOnePersonDialog
          open={callOneOpen}
          onOpenChange={setCallOneOpen}
          defaultEventId={scopedEventId}
          onPlaced={async () => {
            setCallOneOpen(false);
            await loadCampaigns();
          }}
        />

        <CampaignSheet
          campaign={activeCampaign}
          onClose={() => setActiveCampaign(null)}
          onChanged={loadCampaigns}
          onOpenJob={(detail) => setJobDetail(detail)}
        />

        <JobDetailDialog
          detail={jobDetail}
          onClose={() => setJobDetail(null)}
        />
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// Campaigns
// ────────────────────────────────────────────────────────────────

function CampaignsTable({
  loading,
  campaigns,
  onOpen,
  onChanged,
}: {
  loading: boolean;
  campaigns: VoiceCampaign[];
  onOpen: (c: VoiceCampaign) => void;
  onChanged: () => void;
}) {
  if (loading) {
    return (
      <Card className="p-10 text-sm text-muted-foreground text-center">
        Loading campaigns…
      </Card>
    );
  }
  if (!campaigns.length) {
    return (
      <Card className="p-10 text-center">
        <p className="text-base font-medium">No voice campaigns yet</p>
        <p className="text-sm text-muted-foreground mt-1">
          Create one to call your guests for RSVP, contribution follow-ups,
          or vendor confirmations.
        </p>
      </Card>
    );
  }
  return (
    <Card className="overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-muted/40 text-xs uppercase tracking-wide text-muted-foreground">
            <tr>
              <th className="text-left px-4 py-3 font-medium">Title</th>
              <th className="text-left px-4 py-3 font-medium">Purpose</th>
              <th className="text-left px-4 py-3 font-medium">Lang</th>
              <th className="text-left px-4 py-3 font-medium">Status</th>
              <th className="text-left px-4 py-3 font-medium">Jobs</th>
              <th className="text-left px-4 py-3 font-medium">Created</th>
              <th className="px-4 py-3" />
            </tr>
          </thead>
          <tbody>
            {campaigns.map((c) => {
              const total = c.counts?.total ?? 0;
              const done = (c.counts?.completed ?? 0) + (c.counts?.failed ?? 0);
              return (
                <tr key={c.id} className="border-t border-border/60 hover:bg-muted/30">
                  <td className="px-4 py-3 font-medium">
                    {c.title || <span className="text-muted-foreground">Untitled</span>}
                  </td>
                  <td className="px-4 py-3 capitalize">{c.purpose}</td>
                  <td className="px-4 py-3 uppercase text-xs">{c.language}</td>
                  <td className="px-4 py-3"><StatusPill value={c.status} /></td>
                  <td className="px-4 py-3 text-xs">
                    {done}/{total}
                  </td>
                  <td className="px-4 py-3 text-xs text-muted-foreground">
                    {fmtDate(c.created_at)}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <Button variant="ghost" size="sm" onClick={() => onOpen(c)}>
                      Open
                    </Button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function CreateCampaignDialog({
  open, onOpenChange, onCreated, defaultEventId,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  onCreated: () => void;
  defaultEventId?: string;
}) {
  const [title, setTitle] = useState("");
  const [purpose, setPurpose] = useState<VoicePurpose>("rsvp");
  const [language, setLanguage] = useState("sw");
  const [eventId, setEventId] = useState(defaultEventId || "");
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open) {
      setTitle(""); setPurpose("rsvp"); setLanguage("sw");
      setEventId(defaultEventId || ""); setNotes("");
    }
  }, [open, defaultEventId]);

  async function submit() {
    setSaving(true);
    const res = await voiceCallsApi.createCampaign({
      title: title.trim() || null,
      purpose,
      language,
      event_id: eventId.trim() || null,
      notes: notes.trim() || null,
    });
    setSaving(false);
    if (res.success) {
      toast.success("Campaign created");
      onCreated();
    } else {
      showApiErrors(res);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>New voice campaign</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <label className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Title</label>
            <Input
              autoComplete="off"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Harusi ya Asha · RSVP calls"
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Purpose</label>
              <Select value={purpose} onValueChange={(v) => setPurpose(v as VoicePurpose)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="rsvp">RSVP</SelectItem>
                  <SelectItem value="contribution">Contribution</SelectItem>
                  <SelectItem value="verification">Verification</SelectItem>
                  <SelectItem value="committee">Committee</SelectItem>
                  <SelectItem value="vendor">Vendor</SelectItem>
                  <SelectItem value="feedback">Feedback</SelectItem>
                  <SelectItem value="general">General</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <label className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Language</label>
              <Select value={language} onValueChange={setLanguage}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="sw">Swahili</SelectItem>
                  <SelectItem value="en">English</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div>
            <label className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Event ID (optional)</label>
            <Input
              autoComplete="off"
              value={eventId}
              onChange={(e) => setEventId(e.target.value)}
              placeholder="Paste the event UUID to scope this campaign"
            />
          </div>
          <div>
            <label className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Notes</label>
            <Textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={3}
              placeholder="Notes only your team can see"
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Creating…" : "Create campaign"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ────────────────────────────────────────────────────────────────
// Campaign sheet — jobs + add recipients + lifecycle controls
// ────────────────────────────────────────────────────────────────

function CampaignSheet({
  campaign, onClose, onChanged, onOpenJob,
}: {
  campaign: VoiceCampaign | null;
  onClose: () => void;
  onChanged: () => void;
  onOpenJob: (detail: { job: VoiceCallJob; logs: VoiceCallLog[] }) => void;
}) {
  const [jobs, setJobs] = useState<VoiceCallJob[]>([]);
  const [jobsLoading, setJobsLoading] = useState(false);
  const [paste, setPaste] = useState("");
  const [adding, setAdding] = useState(false);
  const [acting, setActing] = useState(false);

  const open = !!campaign;

  async function loadJobs(id: string) {
    setJobsLoading(true);
    const res = await voiceCallsApi.listJobs(id, { page: 1, page_size: 100 });
    if (res.success) setJobs(res.data || []);
    else showApiErrors(res);
    setJobsLoading(false);
  }

  useEffect(() => {
    if (campaign) loadJobs(campaign.id);
    else setJobs([]);
  }, [campaign?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Light polling while a campaign is active.
  useEffect(() => {
    if (!campaign) return;
    if (!["queued", "running"].includes(campaign.status)) return;
    const id = setInterval(() => loadJobs(campaign.id), 8000);
    return () => clearInterval(id);
  }, [campaign?.id, campaign?.status]); // eslint-disable-line react-hooks/exhaustive-deps

  async function addRecipients() {
    if (!campaign) return;
    const lines = paste
      .split(/\r?\n|,/)
      .map((s) => s.trim())
      .filter(Boolean);
    if (!lines.length) {
      toast.error("Paste at least one phone number");
      return;
    }
    const recipients = lines.map((raw) => {
      // Accept "name | phone" or just phone.
      const [a, b] = raw.split("|").map((s) => s.trim());
      if (b) return { recipient_name: a, phone: b };
      return { phone: a };
    });
    setAdding(true);
    const res = await voiceCallsApi.addJobs(campaign.id, recipients, true);
    setAdding(false);
    if (res.success) {
      toast.success(`Added ${recipients.length} recipient(s)`);
      setPaste("");
      await loadJobs(campaign.id);
      onChanged();
    } else {
      showApiErrors(res);
    }
  }

  async function lifecycle(action: "start" | "pause" | "cancel") {
    if (!campaign) return;
    setActing(true);
    const fn = action === "start"
      ? voiceCallsApi.startCampaign
      : action === "pause"
        ? voiceCallsApi.pauseCampaign
        : voiceCallsApi.cancelCampaign;
    const res = await fn(campaign.id);
    setActing(false);
    if (res.success) {
      toast.success(`Campaign ${action}d`);
      onChanged();
    } else {
      showApiErrors(res);
    }
  }

  async function openJob(jobId: string) {
    const res = await voiceCallsApi.getJob(jobId);
    if (res.success && res.data) onOpenJob(res.data);
    else showApiErrors(res);
  }

  async function placeCall(jobId: string) {
    const res = await voiceCallsApi.placeCall(jobId);
    if (res.success) {
      toast.success("Dialing…");
      if (campaign) await loadJobs(campaign.id);
    } else {
      showApiErrors(res);
    }
  }

  const summary = useMemo(() => {
    const c = campaign?.counts ?? {};
    return {
      total: c.total ?? 0,
      completed: c.completed ?? 0,
      in_progress: c.in_progress ?? 0,
      failed: c.failed ?? 0,
      blocked: (c.blocked ?? 0) + (c.opted_out ?? 0),
    };
  }, [campaign]);

  return (
    <Sheet open={open} onOpenChange={(v) => { if (!v) onClose(); }}>
      <SheetContent side="right" className="w-full sm:max-w-2xl overflow-y-auto">
        {campaign && (
          <>
            <SheetHeader>
              <SheetTitle className="flex items-center gap-2">
                <span>{campaign.title || "Untitled campaign"}</span>
                <StatusPill value={campaign.status} />
              </SheetTitle>
            </SheetHeader>

            <div className="grid grid-cols-4 gap-3 mt-4">
              <Stat label="Total" value={summary.total} />
              <Stat label="Done" value={summary.completed} />
              <Stat label="Live" value={summary.in_progress} />
              <Stat label="Blocked" value={summary.blocked} />
            </div>

            <div className="flex flex-wrap gap-2 mt-4">
              {(campaign.status === "draft" || campaign.status === "paused") && (
                <Button size="sm" onClick={() => lifecycle("start")} disabled={acting}>
                  Start campaign
                </Button>
              )}
              {(campaign.status === "queued" || campaign.status === "running") && (
                <Button size="sm" variant="outline" onClick={() => lifecycle("pause")} disabled={acting}>
                  Pause
                </Button>
              )}
              {!["completed", "cancelled"].includes(campaign.status) && (
                <Button size="sm" variant="ghost" onClick={() => lifecycle("cancel")} disabled={acting}>
                  Cancel
                </Button>
              )}
            </div>

            <div className="mt-6">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground mb-2">
                Add recipients
              </p>
              <Textarea
                rows={3}
                value={paste}
                onChange={(e) => setPaste(e.target.value)}
                placeholder={"One per line or comma-separated\nFormat: Name | +255712345678"}
              />
              <div className="mt-2 flex justify-end">
                <Button size="sm" onClick={addRecipients} disabled={adding}>
                  {adding ? "Adding…" : "Add to campaign"}
                </Button>
              </div>
            </div>

            <div className="mt-6">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground mb-2">
                Recipients ({jobs.length})
              </p>
              {jobsLoading ? (
                <p className="text-sm text-muted-foreground py-6 text-center">Loading…</p>
              ) : jobs.length === 0 ? (
                <p className="text-sm text-muted-foreground py-6 text-center">
                  No recipients yet.
                </p>
              ) : (
                <div className="space-y-2">
                  {jobs.map((j) => (
                    <button
                      key={j.id}
                      onClick={() => openJob(j.id)}
                      className="w-full text-left rounded-xl border border-border/60 px-3 py-2 hover:bg-muted/40 transition"
                    >
                      <div className="flex items-center justify-between gap-2">
                        <div className="min-w-0">
                          <p className="text-sm font-medium truncate">
                            {j.recipient_name || j.phone_e164}
                          </p>
                          <p className="text-xs text-muted-foreground truncate">
                            {j.phone_e164}
                            {j.ai_outcome ? ` • ${j.ai_outcome}` : ""}
                            {j.block_reason ? ` • ${j.block_reason}` : ""}
                          </p>
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          <StatusPill value={j.status} />
                          {j.status === "pending" && (
                            <Button
                              size="sm"
                              variant="ghost"
                              onClick={(e) => { e.stopPropagation(); placeCall(j.id); }}
                            >
                              Call now
                            </Button>
                          )}
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-xl border border-border/60 px-3 py-2">
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="text-lg font-semibold mt-0.5">{value}</p>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// Job detail
// ────────────────────────────────────────────────────────────────

function JobDetailDialog({
  detail, onClose,
}: {
  detail: { job: VoiceCallJob; logs: VoiceCallLog[] } | null;
  onClose: () => void;
}) {
  const open = !!detail;
  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-xl">
        {detail && (
          <>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                {detail.job.recipient_name || detail.job.phone_e164}
                <StatusPill value={detail.job.status} />
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-3 text-sm">
              <div className="grid grid-cols-2 gap-3">
                <Field label="Phone" value={detail.job.phone_e164} />
                <Field label="Language" value={detail.job.language || "—"} />
                <Field label="Attempts" value={`${detail.job.attempt}/${detail.job.max_attempts}`} />
                <Field
                  label="AI outcome"
                  value={detail.job.ai_outcome
                    ? `${detail.job.ai_outcome}${
                        detail.job.ai_confidence != null
                          ? ` (${Math.round(detail.job.ai_confidence * 100)}%)`
                          : ""
                      }`
                    : "—"}
                />
              </div>
              {detail.job.summary && (
                <div>
                  <p className="text-xs uppercase tracking-wide text-muted-foreground mb-1">Summary</p>
                  <p className="rounded-lg bg-muted/40 px-3 py-2">{detail.job.summary}</p>
                </div>
              )}
              <div>
                <p className="text-xs uppercase tracking-wide text-muted-foreground mb-1">
                  Call attempts ({detail.logs.length})
                </p>
                {detail.logs.length === 0 ? (
                  <p className="text-muted-foreground">No attempts yet.</p>
                ) : (
                  <div className="space-y-2">
                    {detail.logs.map((l) => (
                      <div key={l.id} className="rounded-lg border border-border/60 px-3 py-2">
                        <div className="flex items-center justify-between gap-2">
                          <StatusPill value={l.status} />
                          <span className="text-xs text-muted-foreground">
                            {fmtDate(l.started_at || l.created_at)} • {l.duration_seconds}s
                          </span>
                        </div>
                        {l.transcript && (
                          <pre className="whitespace-pre-wrap text-xs mt-2 max-h-40 overflow-y-auto">
                            {l.transcript}
                          </pre>
                        )}
                        {l.error_message && (
                          <p className="text-xs text-red-600 mt-1">
                            {l.error_code}: {l.error_message}
                          </p>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="text-sm mt-0.5 break-words">{value}</p>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// Opt-outs
// ────────────────────────────────────────────────────────────────

function OptOutsPanel() {
  const [items, setItems] = useState<VoiceOptOut[]>([]);
  const [loading, setLoading] = useState(true);
  const [phone, setPhone] = useState("");
  const [reason, setReason] = useState("");
  const [adding, setAdding] = useState(false);

  async function load() {
    setLoading(true);
    const res = await voiceCallsApi.listOptOuts({ page: 1, page_size: 200 });
    if (res.success) setItems(res.data || []);
    else showApiErrors(res);
    setLoading(false);
  }

  useEffect(() => { load(); }, []);

  async function add() {
    if (!phone.trim()) return;
    setAdding(true);
    const res = await voiceCallsApi.addOptOut(phone.trim(), reason.trim() || undefined);
    setAdding(false);
    if (res.success) {
      toast.success("Number opted out");
      setPhone(""); setReason("");
      load();
    } else {
      showApiErrors(res);
    }
  }

  async function remove(p: string) {
    const res = await voiceCallsApi.removeOptOut(p);
    if (res.success) {
      toast.success("Removed from opt-out list");
      load();
    } else {
      showApiErrors(res);
    }
  }

  return (
    <div className="space-y-6">
      <Card className="p-4">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground mb-3">
          Add to global do-not-call list
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-[1fr_1fr_auto] gap-3">
          <Input
            autoComplete="off"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="+255712345678"
          />
          <Input
            autoComplete="off"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Reason (optional)"
          />
          <Button onClick={add} disabled={adding}>
            {adding ? "Adding…" : "Add opt-out"}
          </Button>
        </div>
      </Card>

      <Card className="overflow-hidden">
        {loading ? (
          <p className="p-6 text-sm text-muted-foreground text-center">Loading…</p>
        ) : items.length === 0 ? (
          <p className="p-6 text-sm text-muted-foreground text-center">
            No opt-outs on record.
          </p>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-muted/40 text-xs uppercase tracking-wide text-muted-foreground">
              <tr>
                <th className="text-left px-4 py-3 font-medium">Phone</th>
                <th className="text-left px-4 py-3 font-medium">Reason</th>
                <th className="text-left px-4 py-3 font-medium">Source</th>
                <th className="text-left px-4 py-3 font-medium">Added</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {items.map((o) => (
                <tr key={o.id} className="border-t border-border/60">
                  <td className="px-4 py-3 font-mono text-xs">{o.phone_e164}</td>
                  <td className="px-4 py-3">{o.reason || "—"}</td>
                  <td className="px-4 py-3">
                    <Badge variant="outline" className="capitalize">{o.source}</Badge>
                  </td>
                  <td className="px-4 py-3 text-xs text-muted-foreground">
                    {fmtDate(o.created_at)}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <Button size="sm" variant="ghost" onClick={() => remove(o.phone_e164)}>
                      Remove
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// Call one person · quick ad-hoc single-recipient call
// ────────────────────────────────────────────────────────────────

function CallOnePersonDialog({
  open, onOpenChange, onPlaced, defaultEventId,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  onPlaced: () => void;
  defaultEventId?: string;
}) {
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [language, setLanguage] = useState("sw");
  const [purpose, setPurpose] = useState<VoicePurpose>("rsvp");
  const [eventId, setEventId] = useState(defaultEventId || "");
  const [busy, setBusy] = useState(false);
  const [guests, setGuests] = useState<Array<{ id: string; name: string; phone: string }>>([]);
  const [guestSearch, setGuestSearch] = useState("");
  const [loadingGuests, setLoadingGuests] = useState(false);

  useEffect(() => {
    if (open) {
      setName(""); setPhone(""); setLanguage("sw");
      setPurpose("rsvp"); setEventId(defaultEventId || "");
      setGuestSearch("");
    }
  }, [open, defaultEventId]);

  // Lazy-load guests when an event is scoped
  useEffect(() => {
    if (!open || !eventId.trim()) { setGuests([]); return; }
    let cancelled = false;
    (async () => {
      setLoadingGuests(true);
      try {
        const { eventsApi } = await import("@/lib/api/events");
        const res = await eventsApi.getGuests(eventId.trim(), { page: 1, page_size: 500 } as any);
        if (cancelled) return;
        const items: any[] = (res?.data as any)?.guests || (res as any)?.data?.items || [];
        setGuests(items.map((g: any) => ({
          id: String(g.id),
          name: (g.name || g.full_name || "").toString(),
          phone: (g.phone || g.phone_number || "").toString(),
        })).filter((g) => g.phone));
      } catch { /* ignore */ }
      finally { if (!cancelled) setLoadingGuests(false); }
    })();
    return () => { cancelled = true; };
  }, [open, eventId]);

  const filteredGuests = useMemo(() => {
    const q = guestSearch.trim().toLowerCase();
    if (!q) return guests.slice(0, 40);
    return guests.filter((g) =>
      g.name.toLowerCase().includes(q) || g.phone.toLowerCase().includes(q)
    ).slice(0, 40);
  }, [guests, guestSearch]);

  function pickGuest(g: { name: string; phone: string }) {
    setName(g.name);
    setPhone(g.phone);
  }

  async function submit() {
    if (!phone.trim()) {
      toast.error("Enter a phone number");
      return;
    }
    setBusy(true);
    try {
      const created = await voiceCallsApi.createCampaign({
        title: `Single call · ${name.trim() || phone.trim()}`,
        purpose,
        language,
        event_id: eventId.trim() || null,
      });
      if (!created.success || !created.data) { showApiErrors(created); return; }
      const campaignId = created.data.id;
      const added = await voiceCallsApi.addJobs(
        campaignId,
        [{ recipient_name: name.trim() || undefined, phone: phone.trim(), language }],
        true,
      );
      if (!added.success) { showApiErrors(added); return; }
      const job = (added.data?.accepted || [])[0];
      if (!job) {
        toast.error("Recipient was rejected (opt-out, blocked, or invalid).");
        return;
      }
      const placed = await voiceCallsApi.placeCall(job.id);
      if (placed.success) {
        toast.success("Dialing now");
        onPlaced();
      } else {
        showApiErrors(placed);
      }
    } finally {
      setBusy(false);
    }
  }

  const initialOf = (s: string) =>
    s.trim() ? s.trim()[0].toUpperCase() : "#";

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg p-0 overflow-hidden gap-0 bg-background">
        {/* Header */}
        <div className="flex items-center gap-3 px-6 pt-6 pb-4">
          <div className="flex items-center justify-center w-11 h-11 rounded-2xl bg-primary/10 text-primary">
            <PhoneCall className="h-5 w-5" />
          </div>
          <div className="flex-1 min-w-0">
            <DialogTitle className="text-lg font-semibold tracking-tight">
              Call one person
            </DialogTitle>
            <p className="text-xs text-muted-foreground mt-0.5">
              Pick a guest or type a number to dial right away.
            </p>
          </div>
        </div>

        <div className="px-6 pb-2 space-y-4">
          {/* Compose card */}
          <div className="rounded-2xl border border-border bg-muted/30 divide-y divide-border/70">
            <div className="flex items-center gap-3 px-4 py-3">
              <div className="w-9 h-9 rounded-full bg-background border border-border flex items-center justify-center text-xs font-semibold text-muted-foreground">
                {initialOf(name || phone)}
              </div>
              <Input
                autoComplete="off"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Name (optional)"
                className="border-0 bg-transparent shadow-none focus-visible:ring-0 px-0 h-8 text-sm font-medium"
              />
            </div>
            <div className="flex items-center gap-3 px-4 py-3">
              <div className="w-9 h-9 rounded-full bg-background border border-border flex items-center justify-center text-primary">
                <PhoneCall className="h-4 w-4" />
              </div>
              <Input
                autoComplete="off"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+255 712 345 678"
                className="border-0 bg-transparent shadow-none focus-visible:ring-0 px-0 h-8 text-sm font-medium tracking-wide"
              />
            </div>
          </div>

          {/* Meta selectors */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Purpose</label>
              <Select value={purpose} onValueChange={(v) => setPurpose(v as VoicePurpose)}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="rsvp">RSVP</SelectItem>
                  <SelectItem value="contribution">Contribution</SelectItem>
                  <SelectItem value="verification">Verification</SelectItem>
                  <SelectItem value="committee">Committee</SelectItem>
                  <SelectItem value="vendor">Vendor</SelectItem>
                  <SelectItem value="feedback">Feedback</SelectItem>
                  <SelectItem value="general">General</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <label className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Language</label>
              <Select value={language} onValueChange={setLanguage}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="sw">Swahili</SelectItem>
                  <SelectItem value="en">English</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          {!defaultEventId && (
            <div>
              <label className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Event ID (optional)</label>
              <Input
                autoComplete="off"
                value={eventId}
                onChange={(e) => setEventId(e.target.value)}
                placeholder="Link this call to an event"
                className="mt-1"
              />
            </div>
          )}

          {/* Primary CTA */}
          <Button
            onClick={submit}
            disabled={busy || !phone.trim()}
            className="w-full h-12 rounded-xl text-sm font-semibold"
          >
            {busy ? "Placing call…" : (
              <span className="inline-flex items-center gap-2">
                <PhoneCall className="h-4 w-4" />
                Call now
              </span>
            )}
          </Button>

          {/* Guest picker */}
          {eventId.trim() && (
            <div className="pt-2">
              <div className="flex items-center gap-3">
                <div className="h-px flex-1 bg-border" />
                <span className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                  Or pick a guest
                </span>
                <div className="h-px flex-1 bg-border" />
              </div>
              <Input
                autoComplete="off"
                value={guestSearch}
                onChange={(e) => setGuestSearch(e.target.value)}
                placeholder="Search guest by name or phone"
                className="mt-3"
              />
              <div className="mt-3 max-h-72 overflow-y-auto pr-1 space-y-2">
                {loadingGuests && (
                  <div className="text-xs text-muted-foreground text-center py-6">
                    Loading guests…
                  </div>
                )}
                {!loadingGuests && filteredGuests.length === 0 && (
                  <div className="text-xs text-muted-foreground text-center py-6">
                    No guests match.
                  </div>
                )}
                {filteredGuests.map((g) => {
                  const selected = phone.trim() === g.phone.trim();
                  return (
                    <button
                      key={g.id}
                      type="button"
                      onClick={() => pickGuest(g)}
                      className={`w-full flex items-center gap-3 rounded-xl border px-3 py-2.5 text-left transition ${
                        selected
                          ? "border-primary/40 bg-primary/5"
                          : "border-border hover:border-primary/30 hover:bg-muted/40"
                      }`}
                    >
                      <div className="w-9 h-9 rounded-full bg-primary/10 text-primary text-xs font-bold flex items-center justify-center">
                        {initialOf(g.name || g.phone)}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="text-sm font-semibold truncate">
                          {g.name || g.phone}
                        </div>
                        <div className="text-[11px] text-muted-foreground tabular-nums truncate">
                          {g.phone}
                        </div>
                      </div>
                      <div className={`w-8 h-8 rounded-full flex items-center justify-center ${
                        selected ? "bg-primary text-primary-foreground" : "bg-primary/10 text-primary"
                      }`}>
                        {selected ? (
                          <svg viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
                            <path fillRule="evenodd" d="M16.7 5.3a1 1 0 010 1.4l-7.5 7.5a1 1 0 01-1.4 0L3.3 9.7A1 1 0 014.7 8.3l3.1 3.1 6.8-6.8a1 1 0 011.4 0z" clipRule="evenodd" />
                          </svg>
                        ) : (
                          <PhoneCall className="w-3.5 h-3.5" />
                        )}
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        <DialogFooter className="px-6 py-4 border-t border-border bg-muted/20">
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={busy}>
            Cancel
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

