/**
 * Event Reminder Automations workspace page.
 *
 * Single-file UI for the organiser to create/edit/preview/send reminders.
 * Uses the existing Nuru shadcn primitives. No new dependencies.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import { useParams } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from "@/components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useToast } from "@/hooks/use-toast";
import {
  reminderAutomationsApi,
  type Automation,
  type AutomationType,
  type LanguageCode,
  type ScheduleKind,
  type ReminderRun,
  type ReminderRecipient,
} from "@/lib/api/reminderAutomations";

const TYPE_LABELS: Record<AutomationType, string> = {
  fundraise_attend: "Fundraising attendance",
  pledge_remind: "Contribution payment reminder",
  guest_remind: "Guest event reminder",
};

const STATUS_BADGES: Record<string, string> = {
  sent: "bg-emerald-100 text-emerald-700",
  failed: "bg-red-100 text-red-700",
  skipped: "bg-slate-100 text-slate-700",
  pending: "bg-amber-100 text-amber-700",
  running: "bg-blue-100 text-blue-700",
  completed: "bg-emerald-100 text-emerald-700",
  cancelled: "bg-slate-100 text-slate-700",
};

function detectTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "Africa/Nairobi";
  } catch {
    return "Africa/Nairobi";
  }
}

export default function EventAutomationsPage({ eventId: eventIdProp, embedded = false }: { eventId?: string; embedded?: boolean } = {}) {
  const params = useParams<{ id?: string; eventId?: string }>();
  const eventId = eventIdProp || params.eventId || params.id;
  const { toast } = useToast();
  const [items, setItems] = useState<Automation[]>([]);
  const [loading, setLoading] = useState(true);
  const [editorOpen, setEditorOpen] = useState(false);
  const [editing, setEditing] = useState<Automation | null>(null);
  const [detail, setDetail] = useState<Automation | null>(null);

  async function refresh() {
    if (!eventId) {
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const res = await reminderAutomationsApi.list(eventId);
      if (res.success === false) throw new Error(res.message || "Failed to load automations");
      setItems(extractItems<Automation>(res.data));
    } catch (e: any) {
      toast({ title: "Failed to load automations", description: e?.message, variant: "destructive" });
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { refresh(); /* eslint-disable-next-line */ }, [eventId]);

  return (
    <div className={embedded ? "space-y-6" : "space-y-6 p-6 max-w-6xl mx-auto"}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className={embedded ? "text-xl font-semibold tracking-tight" : "text-3xl font-semibold tracking-tight"}>Keep your event on track</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            Send friendly WhatsApp reminders so your guests do not miss key updates and contributors complete their pledges on time.
          </p>
        </div>
        <Button onClick={() => { setEditing(null); setEditorOpen(true); }}>
          New automation
        </Button>
      </div>

      {loading && <Card><CardContent className="py-12 text-center text-muted-foreground">Loading…</CardContent></Card>}

      {!loading && items.length === 0 && (
        <Card>
          <CardContent className="py-16 text-center">
            <p className="text-muted-foreground">No automations yet. Create one to start reminding people.</p>
          </CardContent>
        </Card>
      )}

      <div className="grid gap-4">
        {items.map((a) => (
          <AutomationRow
            key={a.id}
            a={a}
            onEdit={() => { setEditing(a); setEditorOpen(true); }}
            onDetail={() => setDetail(a)}
            onChanged={refresh}
          />
        ))}
      </div>

      {editorOpen && eventId && (
        <AutomationEditor
          eventId={eventId}
          automation={editing}
          onClose={() => setEditorOpen(false)}
          onSaved={() => { setEditorOpen(false); refresh(); }}
        />
      )}

      {detail && eventId && (
        <AutomationDetailDialog
          eventId={eventId}
          automation={detail}
          onClose={() => setDetail(null)}
        />
      )}
    </div>
  );
}

function extractItems<T>(data: unknown): T[] {
  const value = data as any;
  const items = Array.isArray(value?.items)
    ? value.items
    : Array.isArray(value?.data?.items)
      ? value.data.items
      : Array.isArray(value?.automations)
        ? value.automations
        : Array.isArray(value)
          ? value
          : [];
  return items as T[];
}

function AutomationRow({ a, onEdit, onDetail, onChanged }: {
  a: Automation; onEdit: () => void; onDetail: () => void; onChanged: () => void;
}) {
  const { toast } = useToast();
  const [busy, setBusy] = useState(false);

  async function toggle() {
    if (!a.event_id) return;
    setBusy(true);
    try {
      if (a.enabled) await reminderAutomationsApi.disable(a.event_id, a.id);
      else await reminderAutomationsApi.enable(a.event_id, a.id);
      onChanged();
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" });
    } finally {
      setBusy(false);
    }
  }

  async function sendNow() {
    setBusy(true);
    try {
      await reminderAutomationsApi.sendNow(a.event_id, a.id);
      const isGuest = a.automation_type === "guest_remind";
      toast({
        title: "Reminders sent",
        description: isGuest
          ? "Guest reminders are being sent. We will notify your guests using the available contact details."
          : "Payment reminders are being sent to contributors with outstanding pledges.",
      });
      onChanged();
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card>
      <CardContent className="p-5 flex items-center gap-4 flex-wrap">
        <div className="flex-1 min-w-[260px]">
          <div className="flex items-center gap-2 flex-wrap">
            <h3 className="font-semibold">{a.name || TYPE_LABELS[a.automation_type]}</h3>
            <Badge variant="outline" className="uppercase text-[10px]">{a.language}</Badge>
            <Badge className={STATUS_BADGES[a.enabled ? "sent" : "skipped"]}>
              {a.enabled ? "Enabled" : "Disabled"}
            </Badge>
          </div>
          <p className="text-sm text-muted-foreground mt-1">
            {scheduleSummary(a)}
            {a.last_run && ` - last run ${formatTime(a.last_run.started_at)} (${a.last_run.sent_count} sent / ${a.last_run.failed_count} failed)`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Switch checked={a.enabled} onCheckedChange={toggle} disabled={busy} />
          <Button variant="outline" size="sm" onClick={onEdit}>Edit</Button>
          <Button variant="outline" size="sm" onClick={onDetail}>History</Button>
          <Button size="sm" onClick={sendNow} disabled={busy}>Send now</Button>
        </div>
      </CardContent>
    </Card>
  );
}

function scheduleSummary(a: Automation): string {
  switch (a.schedule_kind) {
    case "now": return "Manual send";
    case "datetime": return `On ${formatTime(a.schedule_at)}`;
    case "days_before": return `${a.days_before ?? 0} day(s) before event`;
    case "hours_before": return `${a.hours_before ?? 0} hour(s) before event`;
    case "repeat": return `Every ${a.repeat_interval_hours ?? 24}h (min gap ${a.min_gap_hours}h)`;
    default: return a.schedule_kind;
  }
}

function formatTime(iso: string | null): string {
  if (!iso) return "—";
  try { return new Date(iso).toLocaleString(); } catch { return iso; }
}

function editableRequiredPlaceholders(type: AutomationType): string[] {
  return [];
}

function AutomationEditor({ eventId, automation, onClose, onSaved }: {
  eventId: string; automation: Automation | null; onClose: () => void; onSaved: () => void;
}) {
  const { toast } = useToast();
  const [type, setType] = useState<AutomationType>(automation?.automation_type || "fundraise_attend");
  const [language, setLanguage] = useState<LanguageCode>(automation?.language || "en");
  const [name, setName] = useState(automation?.name || "");
  const [body, setBody] = useState(automation?.body_override ?? "");
  const [scheduleKind, setScheduleKind] = useState<ScheduleKind>(automation?.schedule_kind || "now");
  const [scheduleAt, setScheduleAt] = useState(automation?.schedule_at?.slice(0, 16) || "");
  const [daysBefore, setDaysBefore] = useState(String(automation?.days_before ?? 1));
  const [hoursBefore, setHoursBefore] = useState(String(automation?.hours_before ?? 6));
  const [repeatInterval, setRepeatInterval] = useState(String(automation?.repeat_interval_hours ?? 24));
  const [minGap, setMinGap] = useState(String(automation?.min_gap_hours ?? 24));
  const [enabled, setEnabled] = useState(automation?.enabled ?? true);
  const [preview, setPreview] = useState<string>("");
  const [saving, setSaving] = useState(false);
  const [templateInfo, setTemplateInfo] = useState<{ prefix: string; suffix: string; required: string[]; defaultBody: string } | null>(null);
  const dateTimeRef = useRef<HTMLInputElement | null>(null);
  const previewRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (scheduleKind !== "datetime") return;
    const timer = window.setTimeout(() => dateTimeRef.current?.focus(), 80);
    return () => window.clearTimeout(timer);
  }, [scheduleKind]);

  useEffect(() => {
    if (!preview) return;
    const timer = window.setTimeout(() => previewRef.current?.scrollIntoView({ behavior: "smooth", block: "center" }), 80);
    return () => window.clearTimeout(timer);
  }, [preview]);

  // Load template defaults when type or language changes.
  useEffect(() => {
    (async () => {
      try {
        const res = await reminderAutomationsApi.listTemplates({ automation_type: type, language });
        const t = res.data?.items?.[0];
        if (t) {
          setTemplateInfo({
            prefix: t.protected_prefix,
            suffix: t.protected_suffix,
            required: editableRequiredPlaceholders(type),
            defaultBody: t.body_default,
          });
          if (!automation && type !== "fundraise_attend") setBody("");
        }
      } catch { /* ignore */ }
    })();
  }, [type, language]); // eslint-disable-line

  async function previewMessage() {
    try {
      // Need an automation id to call preview — use a temporary if creating.
      if (!automation) {
        // Render locally as a simple substitution preview.
        const sample = {
          "{{1}}": "Asha",
          "{{2}}": "Your event",
          "{{3}}": new Date().toLocaleDateString(),
        };
        const previewBody = type === "fundraise_attend" ? body : templateInfo?.defaultBody || "";
        let out = `${templateInfo?.prefix || ""}\n${previewBody}\n${templateInfo?.suffix || ""}`;
        for (const [k, v] of Object.entries(sample)) out = out.split(k).join(v);
        setPreview(out.trim());
        return;
      }
      const res = await reminderAutomationsApi.preview(eventId, automation.id, type === "fundraise_attend" ? body : undefined, language);
      if (res.success === false) throw new Error(res.message || "Preview failed");
      setPreview(res.data?.rendered || "");
    } catch (e: any) {
      toast({ title: "Preview failed", description: e?.message, variant: "destructive" });
    }
  }

  async function save() {
    setSaving(true);
    try {
      const payload = {
        automation_type: type,
        language,
        name: name || undefined,
        body_override: type === "fundraise_attend" ? body || undefined : undefined,
        schedule_kind: scheduleKind,
        schedule_at: scheduleKind === "datetime" && scheduleAt ? new Date(scheduleAt).toISOString() : undefined,
        days_before: scheduleKind === "days_before" ? Number(daysBefore) : undefined,
        hours_before: scheduleKind === "hours_before" ? Number(hoursBefore) : undefined,
        repeat_interval_hours: scheduleKind === "repeat" ? Number(repeatInterval) : undefined,
        min_gap_hours: Number(minGap),
        timezone: detectTimezone(),
        enabled,
      };
      if (automation) {
        const res = await reminderAutomationsApi.update(eventId, automation.id, payload);
        if (res.success === false) throw new Error(res.message || "Save failed");
      } else {
        const res = await reminderAutomationsApi.create(eventId, payload);
        if (res.success === false) throw new Error(res.message || "Save failed");
      }
      onSaved();
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" });
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{automation ? "Edit automation" : "New automation"}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Type</Label>
              <Select value={type} onValueChange={(v) => setType(v as AutomationType)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="fundraise_attend">Fundraising attendance</SelectItem>
                  <SelectItem value="pledge_remind">Payment reminder</SelectItem>
                  <SelectItem value="guest_remind">Guest reminder</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Language</Label>
              <Select value={language} onValueChange={(v) => setLanguage(v as LanguageCode)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="en">English</SelectItem>
                  <SelectItem value="sw">Kiswahili</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div>
            <Label>Internal name (optional)</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} autoComplete="off" />
          </div>

          {templateInfo && templateInfo.required.length > 0 && (
            <div className="rounded-md bg-muted/50 p-3 space-y-2 text-sm">
              <div className="font-medium">Protected wrapper (cannot be edited):</div>
              <div className="text-muted-foreground">Prefix: <span className="font-mono text-xs">{templateInfo.prefix}</span></div>
              <div className="text-muted-foreground">Suffix: <span className="font-mono text-xs">{templateInfo.suffix}</span></div>
              <div className="text-muted-foreground">Required placeholders: {templateInfo.required.map((p) => (
                <Badge key={p} variant="outline" className="ml-1 font-mono text-[10px]">{`{{${p}}}`}</Badge>
              ))}</div>
            </div>
          )}

          {type === "fundraise_attend" ? (
            <div>
              <Label>Message body</Label>
              <Textarea
                value={body}
                onChange={(e) => setBody(e.target.value)}
                rows={6}
                placeholder="Write the message body here..."
                autoComplete="off"
              />
              <p className="text-xs text-muted-foreground mt-1">
                Cannot start or end with a placeholder. Required placeholders must remain.
              </p>
            </div>
          ) : templateInfo ? (
            <div>
              <Label>Message template</Label>
              <div className="rounded-md border bg-muted/30 p-3 mt-1">
                <pre className="text-sm whitespace-pre-wrap font-sans text-foreground/90">{`${templateInfo.prefix ? templateInfo.prefix + "\n" : ""}${templateInfo.defaultBody || ""}${templateInfo.suffix ? "\n" + templateInfo.suffix : ""}`}</pre>
              </div>
              <p className="text-xs text-muted-foreground mt-1">
                This template is pre-approved and cannot be edited. Use Preview to see it with sample details filled in.
              </p>
            </div>
          ) : null}

          <div>
            <Label>Schedule</Label>
            <Select value={scheduleKind} onValueChange={(v) => setScheduleKind(v as ScheduleKind)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="now">Send now (manual)</SelectItem>
                <SelectItem value="datetime">Specific date & time</SelectItem>
                <SelectItem value="days_before">N days before event</SelectItem>
                <SelectItem value="hours_before">N hours before event</SelectItem>
                <SelectItem value="repeat">Repeating</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {scheduleKind === "datetime" && (
            <div>
              <Label>When</Label>
              <Input ref={dateTimeRef} type="datetime-local" value={scheduleAt} onChange={(e) => setScheduleAt(e.target.value)} />
            </div>
          )}
          {scheduleKind === "days_before" && (
            <div><Label>Days before event</Label>
              <Input type="number" min={0} value={daysBefore} onChange={(e) => setDaysBefore(e.target.value)} /></div>
          )}
          {scheduleKind === "hours_before" && (
            <div><Label>Hours before event</Label>
              <Input type="number" min={0} value={hoursBefore} onChange={(e) => setHoursBefore(e.target.value)} /></div>
          )}
          {scheduleKind === "repeat" && (
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Interval (hours)</Label>
                <Input type="number" min={1} value={repeatInterval} onChange={(e) => setRepeatInterval(e.target.value)} /></div>
              <div><Label>Min gap per recipient (hours)</Label>
                <Input type="number" min={1} value={minGap} onChange={(e) => setMinGap(e.target.value)} /></div>
            </div>
          )}

          <div className="flex items-center gap-2">
            <Switch checked={enabled} onCheckedChange={setEnabled} />
            <Label>Enabled</Label>
          </div>

          {preview && (
            <div ref={previewRef} className="rounded-md border p-3 bg-background">
              <div className="text-xs text-muted-foreground mb-2">Preview</div>
              <pre className="text-sm whitespace-pre-wrap font-sans">{preview}</pre>
            </div>
          )}
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={previewMessage}>Preview</Button>
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button onClick={save} disabled={saving}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AutomationDetailDialog({ eventId, automation, onClose }: {
  eventId: string; automation: Automation; onClose: () => void;
}) {
  const { toast } = useToast();
  const [runs, setRuns] = useState<ReminderRun[]>([]);
  const [activeRun, setActiveRun] = useState<ReminderRun | null>(null);
  const [recipients, setRecipients] = useState<ReminderRecipient[]>([]);
  const [filter, setFilter] = useState<string>("");

  async function loadRuns() {
    try {
      const res = await reminderAutomationsApi.listRuns(eventId, automation.id);
      if (res.success === false) throw new Error(res.message || "Failed to load runs");
      const items = extractItems<ReminderRun>(res.data);
      setRuns(items);
      setActiveRun((current) => {
        if (!current) return items[0] || null;
        return items.find((item) => item.id === current.id) || items[0] || null;
      });
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" });
    }
  }

  async function loadRecipients(runId: string) {
    try {
      const res = await reminderAutomationsApi.listRecipients(eventId, automation.id, runId, filter || undefined);
      if (res.success === false) throw new Error(res.message || "Failed to load recipients");
      setRecipients(extractItems<ReminderRecipient>(res.data));
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" });
    }
  }

  useEffect(() => { loadRuns(); /* eslint-disable-next-line */ }, []);
  useEffect(() => { if (activeRun) loadRecipients(activeRun.id); /* eslint-disable-next-line */ }, [activeRun, filter]);

  // Poll while a run is in-flight.
  useEffect(() => {
    if (activeRun?.status !== "running" && activeRun?.status !== "pending") return;
    const t = setInterval(() => { loadRuns(); if (activeRun) loadRecipients(activeRun.id); }, 5000);
    return () => clearInterval(t);
  }, [activeRun?.status]); // eslint-disable-line

  async function resendFailed() {
    if (!activeRun) return;
    try {
      await reminderAutomationsApi.resendFailed(eventId, automation.id, activeRun.id);
      toast({ title: "Resend queued" });
      setTimeout(() => loadRecipients(activeRun.id), 1500);
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" });
    }
  }

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{automation.name || TYPE_LABELS[automation.automation_type]}</DialogTitle>
        </DialogHeader>

        <Tabs defaultValue="runs">
          <TabsList>
            <TabsTrigger value="runs">Runs</TabsTrigger>
            <TabsTrigger value="recipients">Recipients</TabsTrigger>
          </TabsList>
          <TabsContent value="runs">
            <div className="space-y-2">
              {runs.length === 0 && <p className="text-sm text-muted-foreground py-6 text-center">No runs yet.</p>}
              {runs.map((r) => (
                <div
                  key={r.id}
                  className={`rounded-md border p-3 cursor-pointer ${activeRun?.id === r.id ? "border-primary" : ""}`}
                  onClick={() => setActiveRun(r)}
                >
                  <div className="flex items-center justify-between gap-2">
                    <div>
                      <Badge className={STATUS_BADGES[r.status] || ""}>{r.status}</Badge>
                      <span className="ml-2 text-sm text-muted-foreground">{formatTime(r.started_at)}</span>
                    </div>
                    <div className="text-xs text-muted-foreground">
                      {r.sent_count}/{r.total_recipients} sent - {r.failed_count} failed
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </TabsContent>
          <TabsContent value="recipients">
            <div className="flex items-center gap-2 mb-3">
              <Select value={filter || "all"} onValueChange={(v) => setFilter(v === "all" ? "" : v)}>
                <SelectTrigger className="w-[160px]"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All</SelectItem>
                  <SelectItem value="sent">Sent</SelectItem>
                  <SelectItem value="failed">Failed</SelectItem>
                  <SelectItem value="pending">Pending</SelectItem>
                  <SelectItem value="skipped">Skipped</SelectItem>
                </SelectContent>
              </Select>
              <div className="flex-1" />
              <Button size="sm" variant="outline" onClick={resendFailed} disabled={!activeRun}>Resend failed</Button>
            </div>
            <div className="space-y-1 max-h-[400px] overflow-y-auto">
              {recipients.map((r) => (
                <div key={r.id} className="flex items-center justify-between gap-2 p-2 rounded border text-sm">
                  <div>
                    <div className="font-medium">{r.name || r.phone}</div>
                    <div className="text-xs text-muted-foreground">{r.phone} - {r.channel || "—"}{r.error ? ` - ${r.error}` : ""}</div>
                  </div>
                  <Badge className={STATUS_BADGES[r.status] || ""}>{r.status}</Badge>
                </div>
              ))}
              {recipients.length === 0 && <p className="text-sm text-muted-foreground py-6 text-center">No recipients.</p>}
            </div>
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
}
