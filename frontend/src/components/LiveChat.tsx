import React, { useEffect, useRef, useState, useCallback } from 'react';
import { Send, ChevronLeft, Loader2, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { useWorkspaceMeta } from '@/hooks/useWorkspaceMeta';
import { useNavigate } from 'react-router-dom';
import { post, get } from '@/lib/api/helpers';
import { toast } from 'sonner';
import { useLanguage } from '@/lib/i18n/LanguageContext';

type ChatMsg = {
  id: string;
  content: string;
  sender: 'user' | 'agent' | 'system';
  sender_name?: string;
  sent_at: string;
};

const LiveChat = () => {
  const { t } = useLanguage();
  useWorkspaceMeta({
    title: 'Live Chat · Support',
    description: 'Chat with our support team for instant help with your Nuru account.'
  });

  const navigate = useNavigate();
  const [chatId, setChatId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMsg[]>([]);
  const [input, setInput] = useState('');
  const [starting, setStarting] = useState(false);
  const [sending, setSending] = useState(false);
  const [sessionStatus, setSessionStatus] = useState<string>('');
  const messagesRef = useRef<HTMLDivElement | null>(null);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const lastMsgTime = useRef<string | null>(null);

  // Auto-scroll
  useEffect(() => {
    if (messagesRef.current) {
      messagesRef.current.scrollTop = messagesRef.current.scrollHeight;
    }
  }, [messages]);

  // Start chat session on mount
  useEffect(() => {
    startChat();
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  const startChat = async () => {
    setStarting(true);
    try {
      const res = await post<any>('/support/chat/start', {});
      if (res.success && res.data?.chat_id) {
        setChatId(res.data.chat_id);
        setSessionStatus('active');
        // Add system welcome message locally
        setMessages([{
          id: 'welcome',
          content: "Hello! Welcome to Nuru Support. An agent will respond to your messages shortly. How can we help you today?",
          sender: 'system',
          sender_name: 'System',
          sent_at: new Date().toISOString(),
        }]);
        // Start polling for new messages
        startPolling(res.data.chat_id);
      } else {
        toast.error(res.message || 'Failed to start chat session');
      }
    } catch {
      toast.error('Failed to connect to support. Please try again.');
    } finally {
      setStarting(false);
    }
  };

  const startPolling = (id: string) => {
    if (pollRef.current) clearInterval(pollRef.current);
    pollRef.current = setInterval(() => fetchMessages(id), 5000);
  };

  const fetchMessages = useCallback(async (id: string) => {
    try {
      const params = lastMsgTime.current ? `?after=${encodeURIComponent(lastMsgTime.current)}` : '';
      const res = await get<any>(`/support/chat/${id}/messages${params}`);
      if (res.success && res.data) {
        const newMsgs: ChatMsg[] = res.data.messages || [];
        if (newMsgs.length > 0) {
          lastMsgTime.current = newMsgs[newMsgs.length - 1].sent_at;
          setMessages(prev => {
            const existingIds = new Set(prev.map(m => m.id));
            const truly_new = newMsgs.filter(m => !existingIds.has(m.id));
            return truly_new.length > 0 ? [...prev, ...truly_new] : prev;
          });
        }
        if (res.data.session_status) {
          setSessionStatus(res.data.session_status);
          if (res.data.session_status === 'ended' && pollRef.current) {
            clearInterval(pollRef.current);
          }
        }
      }
    } catch { /* silent poll failure */ }
  }, []);

  const sendMessage = async () => {
    if (!input.trim() || !chatId || sending) return;
    const text = input.trim();
    setInput('');
    setSending(true);

    // Optimistic add
    const tempId = `temp-${Date.now()}`;
    const tempMsg: ChatMsg = {
      id: tempId,
      content: text,
      sender: 'user',
      sender_name: 'You',
      sent_at: new Date().toISOString(),
    };
    setMessages(prev => [...prev, tempMsg]);

    try {
      const res = await post<any>(`/support/chat/${chatId}/message`, { content: text });
      if (res.success && res.data) {
        // Replace temp message with real one
        setMessages(prev => prev.map(m => m.id === tempId ? { ...res.data, sender_name: 'You' } : m));
        lastMsgTime.current = res.data.sent_at;
      } else {
        toast.error(res.message || 'Failed to send message');
        setMessages(prev => prev.filter(m => m.id !== tempId));
      }
    } catch {
      toast.error('Failed to send message');
      setMessages(prev => prev.filter(m => m.id !== tempId));
    } finally {
      setSending(false);
    }
  };

  const endChatSession = async () => {
    if (!chatId) return;
    try {
      await post<any>(`/support/chat/${chatId}/end`, {});
      setSessionStatus('ended');
      if (pollRef.current) clearInterval(pollRef.current);
      toast.success('Chat session ended');
    } catch {
      toast.error('Failed to end chat');
    }
  };

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  const formatTime = (iso: string) => {
    try {
      // Normalize UTC timestamps that lack timezone suffix
      const normalized = iso.endsWith('Z') || iso.includes('+') ? iso : iso + 'Z';
      return new Date(normalized).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } catch { return ''; }
  };

  if (starting) {
    return (
      <div className="h-[calc(100vh-8rem)] flex flex-col bg-card">
        <div className="p-4 border-b border-border flex items-center gap-3">
          <Skeleton className="w-8 h-8 rounded-md" />
          <Skeleton className="w-10 h-10 rounded-full" />
          <div className="flex-1 space-y-1.5">
            <Skeleton className="h-4 w-32" />
            <Skeleton className="h-3 w-24" />
          </div>
        </div>
        <div className="flex-1 p-4 space-y-4">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className={`flex ${i % 2 === 0 ? 'justify-start' : 'justify-end'}`}>
              <Skeleton className={`h-12 rounded-lg ${i % 2 === 0 ? 'w-48' : 'w-40'}`} />
            </div>
          ))}
        </div>
        <div className="p-4 border-t border-border">
          <Skeleton className="h-10 w-full rounded-lg" />
        </div>
      </div>
    );
  }

  return (
    <div className="h-[calc(100vh-8rem)] flex flex-col bg-card">
      {/* Header */}
      <div className="p-4 border-b border-border flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={() => navigate('/help')}>
          <ChevronLeft className="w-5 h-5" />
        </Button>
        <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
          <span className="text-lg">💬</span>
        </div>
        <div className="flex-1">
          <h3 className="font-semibold">Nuru Support</h3>
          <p className="text-sm text-muted-foreground">
            {sessionStatus === 'ended' ? 'Session ended' : 'Live · Messages are saved'}
          </p>
        </div>
        {sessionStatus !== 'ended' && (
          <Button variant="ghost" size="sm" className="text-destructive" onClick={endChatSession}>
            <X className="w-4 h-4 mr-1" /> End
          </Button>
        )}
      </div>

      {/* Messages */}
      <div ref={messagesRef} className="flex-1 p-4 overflow-y-auto space-y-3">
        {messages.map((msg) => (
          <div key={msg.id} className={`flex ${msg.sender === 'user' ? 'justify-end' : 'justify-start'}`}>
            <div className={`max-w-[75%] md:max-w-md px-4 py-2.5 rounded-2xl text-sm ${
              msg.sender === 'user'
                ? 'bg-primary text-primary-foreground rounded-br-sm'
                : msg.sender === 'system'
                  ? 'bg-muted/60 border border-border text-muted-foreground italic rounded-bl-sm'
                  : 'bg-muted text-foreground rounded-bl-sm'
            }`}>
              {msg.sender !== 'user' && (
                <p className={`text-xs font-semibold mb-1 ${msg.sender === 'system' ? 'text-muted-foreground' : 'text-primary'}`}>
                  {msg.sender === 'system' ? 'System' : 'Support Team'}
                </p>
              )}
              <p className="break-words">{msg.content}</p>
              <p className={`text-xs mt-1 ${msg.sender === 'user' ? 'opacity-70' : 'text-muted-foreground'}`}>
                {formatTime(msg.sent_at)}
              </p>
            </div>
          </div>
        ))}
      </div>

      {/* Input */}
      {sessionStatus !== 'ended' ? (
        <div className="p-4 border-t border-border">
          <div className="flex items-end gap-2">
            <div className="flex items-end gap-2 bg-transparent rounded-lg px-3 py-2 flex-1 border border-border">
              <textarea
                placeholder={t('type_your_message')}
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={onKeyDown}
                rows={1}
                className="flex-1 bg-transparent text-foreground text-sm outline-none placeholder:text-muted-foreground resize-none overflow-hidden"
                style={{ maxHeight: '120px' }}
                onInput={(e) => { const t = e.target as HTMLTextAreaElement; t.style.height = 'auto'; t.style.height = Math.min(t.scrollHeight, 120) + 'px'; }}
                aria-label="Type a message"
              />
            </div>
            <Button
              size="sm"
              className="px-4 py-2 rounded-lg bg-primary text-primary-foreground hover:bg-primary/95"
              onClick={sendMessage}
              disabled={!input.trim() || sending}
              aria-label="Send message"
            >
              {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
            </Button>
          </div>
        </div>
      ) : (
        <div className="p-4 border-t border-border text-center">
          <p className="text-sm text-muted-foreground mb-2">This chat session has ended.</p>
          <Button variant="outline" size="sm" onClick={startChat}>Start New Chat</Button>
        </div>
      )}
    </div>
  );
};

export default LiveChat;
