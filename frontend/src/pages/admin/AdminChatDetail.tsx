import { useEffect, useState, useCallback, useRef } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { ChevronLeft, Loader2, Send, X, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { adminApi } from "@/lib/api/admin";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";

type ChatMsg = { id: string; content: string; sender: "user" | "agent" | "system"; sender_name?: string; sent_at: string };
type SessionUser = { name: string; avatar: string | null } | null;

const getInitials = (name: string) => {
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
  return name.charAt(0).toUpperCase();
};

export default function AdminChatDetail() {
  const { chatId } = useParams<{ chatId: string }>();
  const navigate = useNavigate();
  const { confirm, ConfirmDialog } = useConfirmDialog();
  const [messages, setMessages] = useState<ChatMsg[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [sessionStatus, setSessionStatus] = useState("");
  const [sessionUser, setSessionUser] = useState<SessionUser>(null);
  const messagesRef = useRef<HTMLDivElement>(null);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const lastMsgTime = useRef<string | null>(null);

  const scrollToBottom = () => {
    if (messagesRef.current) messagesRef.current.scrollTop = messagesRef.current.scrollHeight;
  };

  const fetchMessages = useCallback(async (after?: string) => {
    if (!chatId) return;
    const res = await adminApi.getChatMessages(chatId, after || undefined);
    if (res.success && res.data) {
      const msgs: ChatMsg[] = res.data.messages || [];
      if (!after) {
        setMessages(msgs);
        if (msgs.length > 0) lastMsgTime.current = msgs[msgs.length - 1].sent_at;
        if (res.data.user) setSessionUser(res.data.user);
      } else if (msgs.length > 0) {
        lastMsgTime.current = msgs[msgs.length - 1].sent_at;
        setMessages((prev) => {
          const ids = new Set(prev.map((m) => m.id));
          const fresh = msgs.filter((m) => m.id && !ids.has(m.id));
          return fresh.length > 0 ? [...prev, ...fresh] : prev;
        });
      }
      if (res.data.session_status) setSessionStatus(res.data.session_status);
    }
    setLoading(false);
  }, [chatId]);

  useEffect(() => {
    fetchMessages();
    pollRef.current = setInterval(() => fetchMessages(lastMsgTime.current || undefined), 5000);
    return () => { if (pollRef.current) clearInterval(pollRef.current); };
  }, [fetchMessages]);

  useEffect(() => { scrollToBottom(); }, [messages]);

  const sendReply = async () => {
    if (!input.trim() || !chatId || sending) return;
    const text = input.trim();
    setInput("");
    setSending(true);
    try {
      const res = await adminApi.replyToChat(chatId, text);
      if (res.success && res.data) {
        setMessages((prev) => [...prev, { ...res.data, sender: "agent" }]);
        lastMsgTime.current = res.data.sent_at;
      } else toast.error(res.message || "Failed to send reply");
    } catch { toast.error("Failed to send reply"); }
    finally { setSending(false); }
  };

  const handleClose = async () => {
    if (!chatId) return;
    const ok = await confirm({
      title: "Close this chat session?",
      description: "The user will see this conversation as closed and won't be able to reply unless they start a new one.",
      confirmLabel: "Close session",
      destructive: true,
    });
    if (!ok) return;
    await adminApi.closeChat(chatId);
    toast.success("Chat closed");
    navigate("/admin/chats");
  };

  const fmt = (iso: string) => { try { const normalized = iso.endsWith('Z') || iso.includes('+') ? iso : iso + 'Z'; return new Date(normalized).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }); } catch { return ""; } };

  return (
    <div className="h-[calc(100vh-8rem)] flex flex-col bg-card border border-border rounded-xl overflow-hidden">
      <ConfirmDialog />
      {/* Header */}
      <div className="p-4 border-b border-border flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={() => navigate("/admin/chats")}>
          <ChevronLeft className="w-5 h-5" />
        </Button>
        {loading ? (
          <div className="flex items-center gap-3 flex-1">
            <Skeleton className="w-9 h-9 rounded-full shrink-0" />
            <div className="space-y-1.5">
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-3 w-20" />
            </div>
          </div>
        ) : (
          <>
            <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center shrink-0 overflow-hidden">
              {sessionUser?.avatar ? (
                <img src={sessionUser.avatar} alt={sessionUser.name} className="w-full h-full object-cover" />
              ) : (
                <span className="text-sm font-bold text-primary">
                  {sessionUser?.name ? getInitials(sessionUser.name) : "?"}
                </span>
              )}
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-sm">{sessionUser?.name || "Unknown User"}</h3>
              <p className="text-xs text-muted-foreground capitalize">{sessionStatus || "Loading..."}</p>
            </div>
          </>
        )}
        <Button variant="ghost" size="icon" onClick={() => fetchMessages()} title="Refresh">
          <RefreshCw className="w-4 h-4" />
        </Button>
        {sessionStatus !== "ended" && (
          <Button variant="ghost" size="sm" className="text-destructive" onClick={handleClose}>
            <X className="w-4 h-4 mr-1" /> Close Chat
          </Button>
        )}
      </div>

      {/* Messages */}
      <div ref={messagesRef} className="flex-1 overflow-y-auto p-4 space-y-3">
        {loading && (
          <div className="space-y-3">
            {Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className={cn("flex", i % 2 === 0 ? "justify-start" : "justify-end")}>
                <Skeleton className={cn("h-12 rounded-xl", i % 2 === 0 ? "w-48" : "w-40")} />
              </div>
            ))}
          </div>
        )}
        {messages.map((msg) => (
          <div key={msg.id} className={cn("flex", msg.sender === "agent" ? "justify-end" : "justify-start")}>
            <div className={cn("max-w-[75%] px-4 py-2 rounded-xl text-sm", msg.sender === "agent" ? "bg-primary text-primary-foreground" : msg.sender === "system" ? "bg-muted border border-border text-muted-foreground italic" : "bg-muted text-foreground")}>
              {msg.sender !== "agent" && msg.sender !== "system" && (
                <p className="text-xs font-semibold text-primary mb-1">{msg.sender_name || sessionUser?.name || "User"}</p>
              )}
              <p className="break-words">{msg.content}</p>
              <p className="text-xs mt-1 opacity-60">{fmt(msg.sent_at)}</p>
            </div>
          </div>
        ))}
      </div>

      {/* Input */}
      {sessionStatus !== "ended" ? (
        <div className="p-4 border-t border-border">
          <div className="flex gap-2">
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendReply(); } }}
              placeholder="Type a reply as support agent..."
              rows={1}
              className="flex-1 bg-muted rounded-lg px-3 py-2 text-sm outline-none resize-none text-foreground placeholder:text-muted-foreground"
              style={{ maxHeight: "120px" }}
              onInput={(e) => { const t = e.target as HTMLTextAreaElement; t.style.height = "auto"; t.style.height = Math.min(t.scrollHeight, 120) + "px"; }}
            />
            <Button onClick={sendReply} disabled={!input.trim() || sending} size="sm" className="px-4">
              {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
            </Button>
          </div>
        </div>
      ) : (
        <div className="p-4 border-t border-border text-center text-sm text-muted-foreground">
          This chat session has ended.
        </div>
      )}
    </div>
  );
}
