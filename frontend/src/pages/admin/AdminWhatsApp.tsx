import { useEffect, useState, useCallback, useRef } from "react";
import {
  Search, Send, Loader2, Phone, Check, CheckCheck,
  RefreshCw, ChevronLeft, Smile, Clock, Wifi, WifiOff,
} from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import SvgIcon from '@/components/ui/svg-icon';
import ChatUnreadIcon from "@/assets/icons/chat-unread-icon.svg";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { ScrollArea } from "@/components/ui/scroll-area";
import { adminApi } from "@/lib/api/admin";
import { usePolling } from "@/hooks/usePolling";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { getTimeAgo } from "@/utils/getTimeAgo";

type WAConversation = {
  id: string;
  phone: string;
  contact_name: string;
  last_message: string;
  last_activity_at: string | null;
  unread_count: number;
  avatar_url?: string | null;
};

type WAMessage = {
  id: string;
  direction: "inbound" | "outbound";
  content: string;
  media_url?: string | null;
  media_type?: string | null;
  status: "sent" | "delivered" | "read" | "failed";
  wa_message_id?: string;
  created_at: string;
};

/* ── Status tick icons ── */
const StatusIcon = ({ status }: { status: string }) => {
  if (status === "read") return <CheckCheck className="w-3.5 h-3.5 text-sky-500" />;
  if (status === "delivered") return <CheckCheck className="w-3.5 h-3.5 text-muted-foreground/60" />;
  if (status === "sent") return <Check className="w-3.5 h-3.5 text-muted-foreground/60" />;
  if (status === "failed") return <span className="text-destructive text-[10px] font-bold">!</span>;
  return null;
};

const formatTime = (iso: string) => {
  try {
    const normalized = iso.endsWith("Z") || iso.includes("+") ? iso : iso + "Z";
    return new Date(normalized).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  } catch {
    return "";
  }
};

const formatDateSeparator = (iso: string) => {
  try {
    const normalized = iso.endsWith("Z") || iso.includes("+") ? iso : iso + "Z";
    const date = new Date(normalized);
    const today = new Date();
    const yesterday = new Date();
    yesterday.setDate(today.getDate() - 1);
    if (date.toDateString() === today.toDateString()) return "Today";
    if (date.toDateString() === yesterday.toDateString()) return "Yesterday";
    return date.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
  } catch {
    return "";
  }
};

const formatPhoneDisplay = (phone: string) => {
  if (!phone) return "";
  if (phone.startsWith("255")) return "+255 " + phone.slice(3, 6) + " " + phone.slice(6, 9) + " " + phone.slice(9);
  return phone;
};

const getInitials = (name: string) => {
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
  return name.charAt(0).toUpperCase();
};

// Random pastel avatar colors based on phone hash
const AVATAR_COLORS = [
  "from-emerald-500 to-teal-600",
  "from-sky-500 to-blue-600",
  "from-violet-500 to-purple-600",
  "from-amber-500 to-orange-600",
  "from-rose-500 to-pink-600",
  "from-cyan-500 to-sky-600",
  "from-fuchsia-500 to-pink-600",
  "from-lime-500 to-green-600",
];

const getAvatarColor = (id: string) => {
  let hash = 0;
  for (let i = 0; i < id.length; i++) hash = id.charCodeAt(i) + ((hash << 5) - hash);
  return AVATAR_COLORS[Math.abs(hash) % AVATAR_COLORS.length];
};

// Module-level cache to prevent flash on re-mount / polls
let _waConvCache: WAConversation[] | null = null;

export default function AdminWhatsApp() {
  useAdminMeta("WhatsApp");

  const [conversations, setConversations] = useState<WAConversation[]>(_waConvCache || []);
  const [convLoading, setConvLoading] = useState(!_waConvCache);
  const [activeConv, setActiveConv] = useState<WAConversation | null>(null);
  const [messages, setMessages] = useState<WAMessage[]>([]);
  const [msgLoading, setMsgLoading] = useState(false);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [showMobileChat, setShowMobileChat] = useState(false);
  const [isOnline, setIsOnline] = useState(true);
  const [lastSync, setLastSync] = useState<Date>(new Date());

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const activeConvRef = useRef<string | null>(null);
  const chatContainerRef = useRef<HTMLDivElement>(null);
  const hasFetchedRef = useRef(false);

  const scrollToBottom = (smooth = true) => {
    messagesEndRef.current?.scrollIntoView({ behavior: smooth ? "smooth" : "instant" });
  };

  // ── Load conversations ──
  const loadConversations = useCallback(async () => {
    try {
      const res = await adminApi.getWAConversations({ q: searchQuery || undefined });
      if (res.success && res.data) {
        const list = Array.isArray(res.data) ? res.data : [];
        _waConvCache = list;
        setConversations(list);
        setLastSync(new Date());
        if (!isOnline) setIsOnline(true);
      }
    } catch {
      setIsOnline(false);
    }
    setConvLoading(false);
    hasFetchedRef.current = true;
  }, [searchQuery, isOnline]);

  // Initial load — always fetch on mount regardless of cache
  useEffect(() => {
    setConvLoading(!_waConvCache);
    loadConversations();
  }, [loadConversations]);

  usePolling(loadConversations, 4000);

  // ── Load messages with async SMS updates ──
  const loadMessages = useCallback(async () => {
    if (!activeConvRef.current) return;
    try {
      const res = await adminApi.getWAMessages(activeConvRef.current);
      if (res.success && res.data) {
        const newMsgs = Array.isArray(res.data) ? res.data : [];
        setMessages(prev => {
          const tempMsgs = prev.filter(m => m.id.startsWith("temp-"));
          const serverIds = new Set(newMsgs.map((m: WAMessage) => m.id));
          const remainingTemp = tempMsgs.filter(m => !serverIds.has(m.id));
          const merged = [...newMsgs, ...remainingTemp];
          // Only update if data actually changed
          if (JSON.stringify(prev) === JSON.stringify(merged)) return prev;
          return merged;
        });
      }
    } catch {
      setIsOnline(false);
    }
  }, []);

  useEffect(() => {
    if (!activeConv) {
      setMessages([]);
      activeConvRef.current = null;
      return;
    }
    activeConvRef.current = activeConv.id;
    setMsgLoading(true);
    adminApi.getWAMessages(activeConv.id).then((res) => {
      if (res.success && res.data) setMessages(Array.isArray(res.data) ? res.data : []);
      setMsgLoading(false);
      adminApi.markWAConversationRead(activeConv.id);
      setTimeout(() => scrollToBottom(false), 100);
    });
  }, [activeConv?.id]);

  // Faster polling for active chat (2s), slower for conversations (4s)
  usePolling(activeConv ? loadMessages : undefined, 2000);

  useEffect(() => {
    scrollToBottom();
  }, [messages.length]);

  // ── Send message ──
  const handleSend = async () => {
    if (!input.trim() || !activeConv || sending) return;
    const text = input.trim();
    setInput("");
    setSending(true);

    const tempMsg: WAMessage = {
      id: `temp-${Date.now()}`,
      direction: "outbound",
      content: text,
      status: "sent",
      created_at: new Date().toISOString(),
    };
    setMessages(prev => [...prev, tempMsg]);
    scrollToBottom();

    try {
      const res = await adminApi.sendWAMessage(activeConv.id, text);
      if (res.success && res.data) {
        setMessages(prev =>
          prev.map(m => m.id === tempMsg.id ? { ...res.data, direction: "outbound" as const } : m)
        );
        // Update conversation list optimistically
        setConversations(prev =>
          prev.map(c => c.id === activeConv.id
            ? { ...c, last_message: text, last_activity_at: new Date().toISOString(), unread_count: 0 }
            : c
          ).sort((a, b) => new Date(b.last_activity_at || 0).getTime() - new Date(a.last_activity_at || 0).getTime())
        );
      } else {
        toast.error(res.message || "Failed to send message");
        setMessages(prev => prev.filter(m => m.id !== tempMsg.id));
      }
    } catch {
      toast.error("Failed to send message");
      setMessages(prev => prev.filter(m => m.id !== tempMsg.id));
    } finally {
      setSending(false);
    }
  };

  const selectConversation = (conv: WAConversation) => {
    setActiveConv(conv);
    setShowMobileChat(true);
  };

  // Group messages by date
  const groupedMessages: { date: string; msgs: WAMessage[] }[] = [];
  let currentDate = "";
  for (const msg of messages) {
    const dateStr = formatDateSeparator(msg.created_at);
    if (dateStr !== currentDate) {
      currentDate = dateStr;
      groupedMessages.push({ date: dateStr, msgs: [msg] });
    } else {
      groupedMessages[groupedMessages.length - 1].msgs.push(msg);
    }
  }

  // Total unread across all conversations
  const totalUnread = conversations.reduce((sum, c) => sum + (c.unread_count || 0), 0);

  // ── Conversation List ──
  const conversationListJsx = (
    <div className="flex flex-col h-full bg-card">
      {/* Header */}
      <div className="px-4 py-3 border-b border-border bg-card">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-emerald-500 to-green-600 flex items-center justify-center">
              <img src={ChatUnreadIcon} alt="" className="w-4 h-4 invert" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-foreground">Chats</h2>
              <div className="flex items-center gap-1.5">
                {isOnline ? (
                  <Wifi className="w-2.5 h-2.5 text-emerald-500" />
                ) : (
                  <WifiOff className="w-2.5 h-2.5 text-destructive" />
                )}
                <span className="text-[10px] text-muted-foreground">
                  {isOnline ? "Connected" : "Reconnecting..."}
                </span>
              </div>
            </div>
          </div>
          {totalUnread > 0 && (
            <span className="bg-emerald-500 text-white text-[10px] font-bold rounded-full min-w-[20px] h-5 flex items-center justify-center px-1.5">
              {totalUnread}
            </span>
          )}
        </div>
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-muted-foreground" />
          <Input
            placeholder="Search or start new chat"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9 h-8 text-xs bg-muted/50 border-0 rounded-lg focus-visible:ring-1 focus-visible:ring-emerald-500/30"
          />
        </div>
      </div>

      {/* Conversation list */}
      <ScrollArea className="flex-1">
        {convLoading ? (
          <div className="p-2 space-y-0.5">
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} className="flex items-center gap-3 p-3">
                <Skeleton className="w-12 h-12 rounded-full shrink-0" />
                <div className="flex-1 space-y-2">
                  <div className="flex justify-between">
                    <Skeleton className="h-3.5 w-28" />
                    <Skeleton className="h-3 w-10" />
                  </div>
                  <Skeleton className="h-3 w-44" />
                </div>
              </div>
            ))}
          </div>
        ) : conversations.length === 0 ? (
          <div className="text-center py-20 text-muted-foreground">
            <div className="w-16 h-16 rounded-full bg-muted/50 flex items-center justify-center mx-auto mb-4">
              <img src={ChatUnreadIcon} alt="" className="w-7 h-7 opacity-30 dark:invert" />
            </div>
            <p className="text-sm font-medium mb-1">No conversations yet</p>
            <p className="text-xs text-muted-foreground/70">Messages will appear here</p>
          </div>
        ) : (
          <div>
            {conversations.map((conv) => (
              <button
                key={conv.id}
                onClick={() => selectConversation(conv)}
                className={cn(
                  "w-full flex items-center gap-3 px-4 py-3 text-left transition-all duration-200 border-b border-border/40",
                  activeConv?.id === conv.id
                    ? "bg-emerald-500/8 border-l-2 border-l-emerald-500"
                    : "hover:bg-muted/40 border-l-2 border-l-transparent"
                )}
              >
                {/* Avatar */}
                {conv.avatar_url ? (
                  <img
                    src={conv.avatar_url}
                    alt={conv.contact_name}
                    className="w-12 h-12 rounded-full object-cover shrink-0 shadow-sm"
                  />
                ) : (
                  <div className={cn(
                    "w-12 h-12 rounded-full bg-gradient-to-br flex items-center justify-center shrink-0 shadow-sm",
                    getAvatarColor(conv.id)
                  )}>
                    <span className="text-sm font-bold text-white drop-shadow-sm">
                      {getInitials(conv.contact_name || conv.phone)}
                    </span>
                  </div>
                )}

                {/* Content */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <span className={cn(
                      "text-sm truncate",
                      conv.unread_count > 0 ? "font-bold text-foreground" : "font-medium text-foreground"
                    )}>
                      {conv.contact_name || formatPhoneDisplay(conv.phone)}
                    </span>
                    <span className={cn(
                      "text-[10px] shrink-0",
                      conv.unread_count > 0 ? "text-emerald-500 font-semibold" : "text-muted-foreground"
                    )}>
                      {conv.last_activity_at ? getTimeAgo(conv.last_activity_at) : ""}
                    </span>
                  </div>
                  <div className="flex items-center justify-between mt-0.5 gap-2">
                    <p className={cn(
                      "text-xs truncate",
                      conv.unread_count > 0 ? "text-foreground/80 font-medium" : "text-muted-foreground"
                    )}>
                      {conv.last_message || "No messages"}
                    </p>
                    {conv.unread_count > 0 && (
                      <motion.span
                        initial={{ scale: 0 }}
                        animate={{ scale: 1 }}
                        className="bg-emerald-500 text-white text-[10px] font-bold rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1 shrink-0 shadow-sm"
                      >
                        {conv.unread_count}
                      </motion.span>
                    )}
                  </div>
                </div>
              </button>
            ))}
          </div>
        )}
      </ScrollArea>

      {/* Sync status footer */}
      <div className="px-4 py-2 border-t border-border/50 flex items-center justify-between">
        <div className="flex items-center gap-1.5">
          <Clock className="w-3 h-3 text-muted-foreground/50" />
          <span className="text-[10px] text-muted-foreground/60">
            Synced {getTimeAgo(lastSync.toISOString())}
          </span>
        </div>
        <button
          onClick={loadConversations}
          className="text-[10px] text-emerald-600 hover:text-emerald-500 font-medium transition-colors"
        >
          Refresh
        </button>
      </div>
    </div>
  );

  // ── Chat Area ──
  const chatAreaJsx = (
    <div className="flex flex-col h-full bg-background relative">
      {!activeConv ? (
        <div className="flex-1 flex items-center justify-center text-center">
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.4 }}
          >
            <div className="w-24 h-24 rounded-full bg-gradient-to-br from-emerald-500/10 to-green-600/10 flex items-center justify-center mx-auto mb-5">
              <img src={ChatUnreadIcon} alt="" className="w-10 h-10 opacity-40 dark:invert" />
            </div>
            <h3 className="text-lg font-bold text-foreground mb-1.5">Nuru WhatsApp</h3>
            <p className="text-sm text-muted-foreground max-w-xs mx-auto leading-relaxed">
              Send and receive messages directly from your admin panel. Select a conversation to get started.
            </p>
            <div className="mt-6 flex items-center justify-center gap-2 text-[11px] text-muted-foreground/50">
              <span className="inline-flex items-center gap-1">
                {isOnline ? <Wifi className="w-3 h-3 text-emerald-500" /> : <WifiOff className="w-3 h-3 text-destructive" />}
                {isOnline ? "Real-time sync active" : "Reconnecting..."}
              </span>
            </div>
          </motion.div>
        </div>
      ) : (
        <>
          {/* Chat Header */}
          <div className="px-2 md:px-4 py-3 border-b border-border flex items-center gap-2 md:gap-3 bg-card shrink-0 shadow-sm">
            <Button
              variant="ghost" size="icon"
              className="md:hidden shrink-0 h-8 w-8"
              onClick={() => setShowMobileChat(false)}
            >
              <ChevronLeft className="w-5 h-5" />
            </Button>
            {activeConv.avatar_url ? (
              <img
                src={activeConv.avatar_url}
                alt={activeConv.contact_name}
                className="w-9 h-9 md:w-10 md:h-10 rounded-full object-cover shrink-0 shadow-sm"
              />
            ) : (
              <div className={cn(
                "w-9 h-9 md:w-10 md:h-10 rounded-full bg-gradient-to-br flex items-center justify-center shrink-0 shadow-sm",
                getAvatarColor(activeConv.id)
              )}>
                <span className="text-xs md:text-sm font-bold text-white drop-shadow-sm">
                  {getInitials(activeConv.contact_name || activeConv.phone)}
                </span>
              </div>
            )}
            <div className="flex-1 min-w-0">
              <h3 className="font-bold text-sm truncate text-foreground">
                {activeConv.contact_name || formatPhoneDisplay(activeConv.phone)}
              </h3>
              <p className="text-[11px] text-muted-foreground flex items-center gap-1 md:gap-1.5 truncate">
                <Phone className="w-3 h-3 shrink-0" />
                <span className="truncate">{formatPhoneDisplay(activeConv.phone)}</span>
                <span className="text-muted-foreground/40 hidden md:inline">•</span>
                <span className="hidden md:flex items-center gap-0.5">
                  {isOnline ? (
                    <><span className="w-1.5 h-1.5 rounded-full bg-emerald-500 inline-block" /> online</>
                  ) : "offline"}
                </span>
              </p>
            </div>
            <Button
              variant="ghost" size="icon"
              onClick={loadMessages}
              title="Refresh messages"
              className="text-muted-foreground hover:text-foreground"
            >
              <RefreshCw className="w-4 h-4" />
            </Button>
          </div>

          {/* Messages Area */}
          <div
            ref={chatContainerRef}
            className="flex-1 overflow-y-auto px-3 md:px-6 py-4"
            style={{
              backgroundImage: `radial-gradient(circle at 20% 50%, hsl(var(--muted)/0.3) 0%, transparent 50%),
                radial-gradient(circle at 80% 20%, hsl(var(--muted)/0.2) 0%, transparent 40%)`,
            }}
          >
            {msgLoading ? (
              <div className="space-y-4 max-w-xl mx-auto">
                {Array.from({ length: 6 }).map((_, i) => (
                  <div key={i} className={cn("flex", i % 2 === 0 ? "justify-start" : "justify-end")}>
                    <Skeleton className={cn("h-14 rounded-2xl", i % 2 === 0 ? "w-52" : "w-44")} />
                  </div>
                ))}
              </div>
            ) : messages.length === 0 ? (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="text-center py-20 text-muted-foreground"
              >
                <Smile className="w-10 h-10 mx-auto mb-3 opacity-20" />
                <p className="text-sm font-medium">Start the conversation</p>
                <p className="text-xs text-muted-foreground/60 mt-1">Say hello 👋</p>
              </motion.div>
            ) : (
              <div className="max-w-2xl mx-auto">
                {groupedMessages.map((group, gi) => (
                  <div key={gi}>
                    {/* Date separator */}
                    <div className="flex justify-center my-4">
                      <motion.span
                        initial={{ opacity: 0, y: -5 }}
                        animate={{ opacity: 1, y: 0 }}
                        className="bg-card text-muted-foreground text-[10px] font-semibold px-4 py-1.5 rounded-full shadow-sm border border-border/50 uppercase tracking-wider"
                      >
                        {group.date}
                      </motion.span>
                    </div>
                    <AnimatePresence mode="popLayout">
                      {group.msgs.map((msg) => (
                        <motion.div
                          key={msg.id}
                          initial={{ opacity: 0, y: 8, scale: 0.97 }}
                          animate={{ opacity: 1, y: 0, scale: 1 }}
                          exit={{ opacity: 0, scale: 0.95 }}
                          transition={{ duration: 0.2, ease: "easeOut" }}
                          className={cn(
                            "flex mb-1",
                            msg.direction === "outbound" ? "justify-end" : "justify-start"
                          )}
                        >
                          <div
                            className={cn(
                              "max-w-[80%] md:max-w-[70%] px-3.5 py-2 text-sm relative group",
                              msg.direction === "outbound"
                                ? "bg-emerald-500/10 dark:bg-emerald-900/30 text-foreground rounded-2xl rounded-tr-sm"
                                : "bg-card text-foreground border border-border/60 rounded-2xl rounded-tl-sm shadow-sm"
                            )}
                          >
                            {msg.media_url && (msg.media_type === "image" || /\.(png|jpe?g|webp|gif)(\?|$)/i.test(msg.media_url)) ? (
                              <a href={msg.media_url} target="_blank" rel="noopener noreferrer" className="block mb-1">
                                <img
                                  src={msg.media_url}
                                  alt={msg.content || "Attachment"}
                                  className="rounded-xl max-h-72 w-auto object-cover border border-border/40"
                                  loading="lazy"
                                />
                              </a>
                            ) : msg.media_url ? (
                              <a
                                href={msg.media_url}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="block mb-1 text-xs underline text-primary"
                              >
                                Open attachment
                              </a>
                            ) : null}
                            {msg.content && (
                              <p className="break-words whitespace-pre-wrap leading-relaxed">
                                {msg.content}
                              </p>
                            )}
                            <div className="flex items-center justify-end gap-1 mt-1 -mb-0.5">
                              <span className="text-[10px] text-muted-foreground/70">
                                {formatTime(msg.created_at)}
                              </span>
                              {msg.direction === "outbound" && (
                                <motion.span
                                  key={msg.status}
                                  initial={{ scale: 0.5 }}
                                  animate={{ scale: 1 }}
                                  transition={{ type: "spring", stiffness: 400, damping: 15 }}
                                >
                                  <StatusIcon status={msg.status} />
                                </motion.span>
                              )}
                            </div>
                          </div>
                        </motion.div>
                      ))}
                    </AnimatePresence>
                  </div>
                ))}
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>

          {/* Message Input */}
          <div className="px-3 md:px-6 py-3 border-t border-border bg-card shrink-0">
            <div className="flex gap-2.5 items-end max-w-2xl mx-auto">
              <div className="flex-1 relative">
                <textarea
                  value={input}
                  onChange={(e) => setInput(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && !e.shiftKey) {
                      e.preventDefault();
                      handleSend();
                    }
                  }}
                  placeholder="Type a message..."
                  rows={1}
                  className="w-full bg-muted/40 rounded-2xl px-4 py-2.5 pr-4 text-sm outline-none resize-none text-foreground placeholder:text-muted-foreground/60 border border-border/40 focus:border-emerald-500/40 focus:ring-1 focus:ring-emerald-500/20 transition-all"
                  style={{ maxHeight: "120px" }}
                  onInput={(e) => {
                    const t = e.target as HTMLTextAreaElement;
                    t.style.height = "auto";
                    t.style.height = Math.min(t.scrollHeight, 120) + "px";
                  }}
                />
              </div>
              <motion.div whileTap={{ scale: 0.92 }}>
                <Button
                  onClick={handleSend}
                  disabled={!input.trim() || sending}
                  size="icon"
                  className={cn(
                    "rounded-full w-10 h-10 shrink-0 shadow-md transition-all duration-200",
                    input.trim()
                      ? "bg-emerald-500 hover:bg-emerald-600 shadow-emerald-500/25"
                      : "bg-muted text-muted-foreground"
                  )}
                >
                  {sending ? (
                    <Loader2 className="w-4 h-4 animate-spin text-white" />
                  ) : (
                    <Send className="w-4 h-4 text-white" />
                  )}
                </Button>
              </motion.div>
            </div>
            <p className="text-[10px] text-muted-foreground/40 text-center mt-1.5">
              Press Enter to send - Shift+Enter for new line
            </p>
          </div>
        </>
      )}
    </div>
  );

  return (
    <div className="h-[calc(100vh-8rem)] border border-border rounded-2xl overflow-hidden flex shadow-sm bg-card">
      {/* Sidebar */}
      <div className={cn(
        "w-full md:w-[360px] shrink-0 border-r border-border",
        showMobileChat && "hidden md:flex md:flex-col"
      )}>
        {conversationListJsx}
      </div>
      {/* Main chat */}
      <div className={cn(
        "flex-1 min-w-0",
        !showMobileChat && "hidden md:flex md:flex-col"
      )}>
        {chatAreaJsx}
      </div>
    </div>
  );
}
