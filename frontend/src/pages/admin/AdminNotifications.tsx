import { useState } from "react";
import { Loader2, Send, Beaker } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { adminApi } from "@/lib/api/admin";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";
import { toast } from "sonner";

const DEEP_LINK_TYPES = [
  "system",
  "message",
  "payment_received",
  "payment_failed",
  "withdrawal",
  "event_invite",
  "committee_invite",
  "rsvp_update",
  "circle_request",
  "circle_accepted",
  "follow",
  "glow",
  "comment",
  "booking_request",
  "booking_accepted",
  "contribution_received",
];

export default function AdminNotifications() {
  const [title, setTitle] = useState("");
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const { confirm, ConfirmDialog } = useConfirmDialog();

  // Test push state
  const [testUserId, setTestUserId] = useState("");
  const [testTitle, setTestTitle] = useState("Nuru test push");
  const [testMessage, setTestMessage] = useState("This is a test notification from admin.");
  const [testType, setTestType] = useState("system");
  const [testRef, setTestRef] = useState("");
  const [testSending, setTestSending] = useState(false);
  const [testResult, setTestResult] = useState<any>(null);

  const handleBroadcast = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !message.trim()) { toast.error("Title and message are required"); return; }
    const ok = await confirm({
      title: "Send Broadcast Notification?",
      description: `This will send "${title}" to ALL active Nuru users. This cannot be undone.`,
      confirmLabel: "Send to All Users",
      destructive: true,
    });
    if (!ok) return;
    setSending(true);
    const res = await adminApi.broadcastNotification(title.trim(), message.trim());
    if (res.success) {
      toast.success(res.message || "Notification sent!");
      setTitle("");
      setMessage("");
    } else toast.error(res.message || "Failed to send notification");
    setSending(false);
  };

  const handleTestPush = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!testUserId.trim()) { toast.error("User ID is required"); return; }
    setTestSending(true);
    setTestResult(null);
    const res = await adminApi.sendTestPush({
      user_id: testUserId.trim(),
      title: testTitle.trim() || undefined,
      message: testMessage.trim() || undefined,
      deep_link_type: testType,
      reference_id: testRef.trim() || undefined,
    });
    if (res.success) {
      toast.success(res.message || "Test push dispatched");
      setTestResult(res.data);
    } else {
      toast.error(res.message || "Failed to send test push");
      setTestResult(res.data || null);
    }
    setTestSending(false);
  };

  return (
    <div className="space-y-6">
      <ConfirmDialog />
      <div>
        <h2 className="text-xl font-bold text-foreground">Broadcast Notification</h2>
        <p className="text-sm text-muted-foreground mt-0.5">Send a system notification to all active Nuru users</p>
      </div>

      <div className="bg-card border border-border rounded-xl p-6">
        <form onSubmit={handleBroadcast} className="space-y-5">
          <div className="space-y-1.5">
            <Label>Title *</Label>
            <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Platform maintenance scheduled" maxLength={100} />
            <p className="text-xs text-muted-foreground">{title.length}/100 characters</p>
          </div>
          <div className="space-y-1.5">
            <Label>Message *</Label>
            <Textarea value={message} onChange={(e) => setMessage(e.target.value)} rows={4} placeholder="Write the notification content here..." maxLength={500} />
            <p className="text-xs text-muted-foreground">{message.length}/500 characters</p>
          </div>
          <div className="bg-muted border border-border rounded-lg p-3 text-sm text-muted-foreground">
            ⚠️ This notification will be sent to <strong>all active users</strong>. Use this for important platform announcements only.
          </div>
          <Button type="submit" disabled={sending || !title.trim() || !message.trim()} className="w-full">
            {sending ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <Send className="w-4 h-4 mr-2" />}
            Send to All Users
          </Button>
        </form>
      </div>

      <div>
        <h2 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Beaker className="w-5 h-5" /> Send Test Push
        </h2>
        <p className="text-sm text-muted-foreground mt-0.5">
          Target a single user to verify FCM payload and deep-link routing.
        </p>
      </div>

      <div className="bg-card border border-border rounded-xl p-6">
        <form onSubmit={handleTestPush} className="space-y-5">
          <div className="space-y-1.5">
            <Label>User ID (UUID) *</Label>
            <Input value={testUserId} onChange={(e) => setTestUserId(e.target.value)} placeholder="e.g. 3f2c… recipient user UUID" />
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label>Title</Label>
              <Input value={testTitle} onChange={(e) => setTestTitle(e.target.value)} maxLength={100} />
            </div>
            <div className="space-y-1.5">
              <Label>Deep-link type</Label>
              <select
                value={testType}
                onChange={(e) => setTestType(e.target.value)}
                className="w-full h-10 px-3 rounded-md border border-input bg-background text-sm"
              >
                {DEEP_LINK_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
              </select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Message</Label>
            <Textarea value={testMessage} onChange={(e) => setTestMessage(e.target.value)} rows={3} maxLength={300} />
          </div>
          <div className="space-y-1.5">
            <Label>Reference ID (optional)</Label>
            <Input value={testRef} onChange={(e) => setTestRef(e.target.value)} placeholder="conversation_id / event_id / payment_id" />
            <p className="text-xs text-muted-foreground">
              For <code>message</code>, this is sent as <code>conversation_id</code> so the app can deep-link to the chat.
            </p>
          </div>
          <Button type="submit" disabled={testSending || !testUserId.trim()} className="w-full">
            {testSending ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <Send className="w-4 h-4 mr-2" />}
            Send Test Push
          </Button>
        </form>

        {testResult && (
          <div className="mt-5 bg-muted border border-border rounded-lg p-4 space-y-2">
            <div className="text-sm font-semibold text-foreground">Result</div>
            <div className="text-xs text-muted-foreground">
              Devices: <strong>{testResult.devices ?? 0}</strong> - Sent:{" "}
              <strong>{testResult.sent ?? 0}</strong> - Failed:{" "}
              <strong>{testResult.failed ?? 0}</strong>
            </div>
            <pre className="text-xs bg-background border border-border rounded p-3 overflow-auto max-h-72">
{JSON.stringify(testResult.payload ?? testResult, null, 2)}
            </pre>
          </div>
        )}
      </div>
    </div>
  );
}
