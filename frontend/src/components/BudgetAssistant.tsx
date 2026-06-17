import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Download, Loader2, Send, Import } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Dialog, DialogPortal, DialogOverlay } from '@/components/ui/dialog';
import * as DialogPrimitive from '@radix-ui/react-dialog';
import { motion, AnimatePresence } from 'framer-motion';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';
import { useCurrentUser } from '@/hooks/useCurrentUser';
import SvgIcon from '@/components/ui/svg-icon';
import closeIcon from '@/assets/icons/close-icon.svg';
import PackageIcon from '@/assets/icons/package-icon.svg';
import { generateBudgetReportHtml } from '@/utils/generateBudgetReport';
import { useLanguage } from '@/lib/i18n/LanguageContext';

interface EventContext {
  eventType: string;
  eventTypeName?: string;
  title: string;
  location: string;
  expectedGuests: string;
  budget: string;
}

export interface BudgetAssistantItem {
  category: string;
  item_name: string;
  estimated_cost: number;
}

interface BudgetAssistantProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  eventContext: EventContext;
  onSaveBudget: (amount: string) => void;
  onImportItems?: (items: BudgetAssistantItem[]) => void;
}

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

const INITIAL_SYSTEM = (ctx: EventContext, firstName?: string) => {
  const parts: string[] = [];
  if (ctx.eventTypeName || ctx.eventType) parts.push(`Event type: ${ctx.eventTypeName || ctx.eventType}`);
  if (ctx.title) parts.push(`Event name: ${ctx.title}`);
  if (ctx.location) parts.push(`Location: ${ctx.location}`);
  if (ctx.expectedGuests) parts.push(`Expected guests: ${ctx.expectedGuests}`);
  if (ctx.budget) parts.push(`Current budget estimate: TZS ${parseInt(ctx.budget).toLocaleString()}`);

  return `You are the Nuru Budget Assistant — an expert event budget planner for Tanzania.

Your job: Have a SHORT, focused conversation to understand the user's event needs, then generate a detailed budget breakdown.

USER NAME: ${firstName || 'there'}

KNOWN CONTEXT:
${parts.length ? parts.join('\n') : 'No details provided yet.'}

CONVERSATION RULES:
- Greet the user by their first name naturally and warmly (e.g. "Hello ${firstName || 'there'}! Let's plan your budget."). Do NOT use "Shikamoo" or overly formal/cultural greetings.
- Then ask 2-3 focused questions about what matters most for their budget (venue type, catering style, entertainment, decor level, etc.)
- Ask ONE round of questions maximum. Do NOT keep asking — after the user responds, generate the budget.
- If the user says "generate" or "go ahead" or similar, generate immediately with what you know.
- Keep questions SHORT — use bullet points.
- NEVER use emoji icons like 💰📍👥💚 in your responses. Use plain text only.

BUDGET FORMAT (when generating):
- Use a markdown table with columns: Category | Description | Estimated Cost (TZS)
- Include categories: Venue, Catering, Decor, Entertainment, Photography/Video, Transportation, Attire, Stationery/Invitations, Miscellaneous, Contingency (10%)
- End with a **TOTAL** row
- After the table, add a brief 2-line tip about where they can save or splurge.
- Costs must be realistic for Tanzania in TZS.`;
};

/** Parse a markdown budget table into structured items */
const parseBudgetTable = (content: string): BudgetAssistantItem[] => {
  const items: BudgetAssistantItem[] = [];
  const lines = content.split('\n');
  for (const line of lines) {
    if (!line.includes('|')) continue;
    const cells = line.split('|').map(c => c.trim()).filter(Boolean);
    if (cells.length < 3) continue;
    // Skip header/separator rows
    if (cells[0].includes('---') || cells[0].toLowerCase() === 'category') continue;
    // Skip TOTAL row
    if (cells[0].replace(/\*/g, '').trim().toLowerCase() === 'total') continue;
    const category = cells[0].replace(/\*/g, '').trim();
    const description = cells[1].replace(/\*/g, '').trim();
    const costStr = cells[2].replace(/\*/g, '').replace(/[^\d]/g, '');
    const cost = parseInt(costStr);
    if (category && description && cost > 0) {
      items.push({ category, item_name: description, estimated_cost: cost });
    }
  }
  return items;
};

const BudgetAssistant: React.FC<BudgetAssistantProps> = ({
  open,
  onOpenChange,
  eventContext,
  onSaveBudget,
  onImportItems,
}) => {
  const { t } = useLanguage();
  const { data: currentUser } = useCurrentUser();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [extractedTotal, setExtractedTotal] = useState<string | null>(null);
  const [hasBudget, setHasBudget] = useState(false);
  const abortRef = useRef<AbortController | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // Reset on open
  useEffect(() => {
    if (open) {
      setMessages([]);
      setInput('');
      setExtractedTotal(null);
      setHasBudget(false);
      // Trigger initial AI greeting
      setTimeout(() => sendToAI([]), 200);
    }
    return () => { abortRef.current?.abort(); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const scrollToBottom = useCallback(() => {
    requestAnimationFrame(() => {
      if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    });
  }, []);

  const extractTotal = (content: string): string | null => {
    const totalMatch = content.match(/\*\*TOTAL\*\*\s*\|\s*\*\*([0-9,]+)\*\*/i);
    if (totalMatch) return totalMatch[1].replace(/,/g, '');
    const fallback = content.match(/TOTAL[^0-9]*([0-9,]{4,})/i);
    if (fallback) return fallback[1].replace(/,/g, '');
    return null;
  };

  const sendToAI = async (conversationHistory: ChatMessage[], userMsg?: string) => {
    setIsStreaming(true);

    const apiMessages = [
      { role: 'system', content: INITIAL_SYSTEM(eventContext, currentUser?.first_name) },
      ...conversationHistory.map(m => ({ role: m.role, content: m.content })),
    ];
    if (userMsg) apiMessages.push({ role: 'user', content: userMsg });

    try {
      const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
      if (!supabaseUrl) { toast.error('Backend not ready'); setIsStreaming(false); return; }

      abortRef.current = new AbortController();
      const resp = await fetch(`${supabaseUrl}/functions/v1/nuru-chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: apiMessages, skipTools: true }),
        signal: abortRef.current.signal,
      });

      if (!resp.ok || !resp.body) {
        toast.error('Failed to get response');
        setIsStreaming(false);
        return;
      }

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let fullContent = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });

        let idx: number;
        while ((idx = buffer.indexOf('\n')) !== -1) {
          let line = buffer.slice(0, idx);
          buffer = buffer.slice(idx + 1);
          if (line.endsWith('\r')) line = line.slice(0, -1);
          if (!line.startsWith('data: ')) continue;
          const json = line.slice(6).trim();
          if (json === '[DONE]') break;
          try {
            const parsed = JSON.parse(json);
            if (parsed.tool_status) continue;
            const delta = parsed.choices?.[0]?.delta?.content;
            if (delta) {
              fullContent += delta;
              setMessages(prev => {
                const last = prev[prev.length - 1];
                if (last?.role === 'assistant') {
                  return prev.map((m, i) => i === prev.length - 1 ? { ...m, content: fullContent } : m);
                }
                return [...prev, { role: 'assistant', content: fullContent }];
              });
              scrollToBottom();
            }
          } catch {
            buffer = line + '\n' + buffer;
            break;
          }
        }
      }

      // Check for budget total
      const total = extractTotal(fullContent);
      if (total) {
        setExtractedTotal(total);
        setHasBudget(true);
      }
    } catch (e: any) {
      if (e.name !== 'AbortError') toast.error('Something went wrong');
    } finally {
      setIsStreaming(false);
    }
  };

  const handleSend = () => {
    const text = input.trim();
    if (!text || isStreaming) return;
    const userMsg: ChatMessage = { role: 'user', content: text };
    const newHistory = [...messages, userMsg];
    setMessages(newHistory);
    setInput('');
    scrollToBottom();
    sendToAI(newHistory, text);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleSaveBudget = () => {
    if (extractedTotal) {
      onSaveBudget(extractedTotal);
      toast.success('Budget saved to your event!');
      onOpenChange(false);
    }
  };

  const handleDownloadPdf = () => {
    const lastAssistant = [...messages].reverse().find(m => m.role === 'assistant' && m.content.includes('TOTAL'));
    if (!lastAssistant) { toast.error('No budget to download'); return; }

    const html = generateBudgetReportHtml({
      content: lastAssistant.content,
      eventTitle: eventContext.title || 'My Event',
      eventType: eventContext.eventTypeName || eventContext.eventType || 'Event',
      location: eventContext.location,
      guests: eventContext.expectedGuests,
    });

    const printWindow = window.open('', '_blank');
    if (printWindow) {
      printWindow.document.write(html);
      printWindow.document.close();
      setTimeout(() => printWindow.print(), 500);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogPortal>
        <DialogOverlay />
        <DialogPrimitive.Content
          className="fixed left-[50%] top-[50%] z-50 w-full max-w-[540px] translate-x-[-50%] translate-y-[-50%] border-0 outline-none bg-background shadow-lg duration-200 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[state=closed]:slide-out-to-left-1/2 data-[state=closed]:slide-out-to-top-[48%] data-[state=open]:slide-in-from-left-1/2 data-[state=open]:slide-in-from-top-[48%] sm:rounded-lg overflow-hidden flex flex-col"
          style={{ maxHeight: '90vh' }}
        >
          {/* Header */}
          <div className="relative bg-foreground text-background px-4 py-3 overflow-hidden flex-shrink-0">
            <div className="absolute inset-0 opacity-20">
              <div className="absolute -top-10 -right-10 w-40 h-40 rounded-full bg-[hsl(var(--nuru-yellow))] blur-3xl" />
              <div className="absolute -bottom-10 -left-10 w-32 h-32 rounded-full bg-[hsl(var(--nuru-blue))] blur-3xl" />
            </div>
            <div className="relative z-10 flex items-center justify-between">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-full bg-background/10 flex items-center justify-center backdrop-blur-sm">
                  <SvgIcon src={PackageIcon} alt="" className="w-5 h-5" forceWhite />
                </div>
                <div>
                  <h2 className="text-sm font-semibold text-background">Nuru Budget Assistant</h2>
                  <p className="text-[10px] text-background/60">Budget planning</p>
                </div>
              </div>
              <DialogPrimitive.Close className="w-7 h-7 flex items-center justify-center rounded-full hover:bg-background/10 transition-colors">
                <img src={closeIcon} alt={t("close")} className="w-4 h-4 invert" />
              </DialogPrimitive.Close>
            </div>
          </div>

          {/* Chat messages */}
          <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3 min-h-0" style={{ maxHeight: 'calc(90vh - 140px)' }}>
            <AnimatePresence initial={false}>
              {messages.map((msg, i) => (
                <motion.div
                  key={i}
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.2 }}
                  className={cn(
                    'flex gap-2',
                    msg.role === 'user' ? 'justify-end' : 'justify-start'
                  )}
                >
                  {msg.role === 'assistant' && (
                    <Avatar className="w-7 h-7 flex-shrink-0 mt-0.5">
                      <AvatarFallback className="bg-foreground text-background flex items-center justify-center text-[10px] font-bold">
                        N
                      </AvatarFallback>
                    </Avatar>
                  )}
                  <div className={cn(
                    'max-w-[80%] rounded-2xl px-3.5 py-2.5 text-sm',
                    msg.role === 'user'
                      ? 'bg-foreground text-background rounded-br-md'
                      : 'bg-muted text-foreground rounded-bl-md'
                  )}>
                    {msg.role === 'assistant' ? (
                      <div className="text-[13px] leading-relaxed nuru-chat-prose text-foreground">
                        <ReactMarkdown
                          remarkPlugins={[remarkGfm]}
                          components={{
                            table: ({ children }) => (
                              <div className="my-2 -mx-1 overflow-x-auto rounded-lg border border-border">
                                <table className="min-w-full text-[11px]">{children}</table>
                              </div>
                            ),
                            thead: ({ children }) => (
                              <thead className="bg-muted/60">{children}</thead>
                            ),
                            th: ({ children }) => (
                              <th className="px-2 py-1.5 text-left font-semibold text-foreground/80 whitespace-nowrap border-b border-border">{children}</th>
                            ),
                            td: ({ children }) => (
                              <td className="px-2 py-1.5 text-foreground/70 whitespace-nowrap border-b border-border/50">{children}</td>
                            ),
                            p: ({ children }) => <p className="my-1">{children}</p>,
                            ul: ({ children }) => <ul className="my-1 ml-3 list-disc space-y-0.5">{children}</ul>,
                            ol: ({ children }) => <ol className="my-1 ml-3 list-decimal space-y-0.5">{children}</ol>,
                            li: ({ children }) => <li className="text-[13px]">{children}</li>,
                            strong: ({ children }) => <strong className="font-semibold">{children}</strong>,
                          }}
                        >
                          {msg.content}
                        </ReactMarkdown>
                      </div>
                    ) : (
                      <p className="leading-relaxed">{msg.content}</p>
                    )}
                  </div>
                  {msg.role === 'user' && (
                    <Avatar className="w-7 h-7 flex-shrink-0 mt-0.5">
                      {currentUser?.avatar && <AvatarImage src={currentUser.avatar} alt={currentUser.first_name} />}
                      <AvatarFallback className="bg-muted text-foreground flex items-center justify-center text-[10px] font-medium">
                        {currentUser
                          ? `${currentUser.first_name?.[0] || ''}${currentUser.last_name?.[0] || ''}`.toUpperCase()
                          : '?'}
                      </AvatarFallback>
                    </Avatar>
                  )}
                </motion.div>
              ))}
            </AnimatePresence>

            {isStreaming && messages.length === 0 && (
              <div className="flex gap-2 justify-start">
                <Avatar className="w-7 h-7 flex-shrink-0">
                  <AvatarFallback className="bg-foreground text-background flex items-center justify-center text-[10px] font-bold">
                    N
                  </AvatarFallback>
                </Avatar>
                <div className="bg-muted rounded-2xl rounded-bl-md px-4 py-3 flex items-center gap-2">
                  <Loader2 className="w-3.5 h-3.5 animate-spin text-muted-foreground" />
                  <span className="text-xs text-muted-foreground">Thinking...</span>
                </div>
              </div>
            )}
          </div>

          {/* Action bar when budget is ready */}
          {hasBudget && !isStreaming && (
            <motion.div
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              className="px-4 py-2.5 border-t border-border flex gap-2 flex-wrap flex-shrink-0 bg-muted/30"
            >
              <Button
                variant="outline"
                size="sm"
                onClick={handleDownloadPdf}
                className="flex-1 h-9 rounded-xl text-xs gap-1.5"
              >
                <Download className="w-3.5 h-3.5" />
                Download PDF
              </Button>
              {onImportItems && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    const lastAssistant = [...messages].reverse().find(m => m.role === 'assistant' && m.content.includes('|'));
                    if (!lastAssistant) { toast.error('No budget table found'); return; }
                    const parsed = parseBudgetTable(lastAssistant.content);
                    if (parsed.length === 0) { toast.error('Could not parse budget items'); return; }
                    onImportItems(parsed);
                    onOpenChange(false);
                  }}
                  className="flex-1 h-9 rounded-xl text-xs gap-1.5"
                >
                  <Import className="w-3.5 h-3.5" />
                  Import Items ({(() => {
                    const lastAssistant = [...messages].reverse().find(m => m.role === 'assistant' && m.content.includes('|'));
                    return lastAssistant ? parseBudgetTable(lastAssistant.content).length : 0;
                  })()})
                </Button>
              )}
              {extractedTotal && (
                <Button
                  size="sm"
                  onClick={handleSaveBudget}
                  className="flex-1 h-9 rounded-xl text-xs gap-1.5 bg-foreground text-background hover:bg-foreground/90"
                >
                  <SvgIcon src={PackageIcon} alt="" className="w-4 h-4" />
                   Save TZS {parseInt(extractedTotal).toLocaleString()}
                </Button>
              )}
            </motion.div>
          )}

          {/* Input area */}
          <div className="p-3 border-t border-border flex-shrink-0 bg-background">
            <div className="flex items-end gap-2">
              <textarea
                ref={inputRef}
                value={input}
                onChange={e => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder={isStreaming ? 'Waiting for response...' : 'Tell me about your event...'}
                disabled={isStreaming}
                rows={1}
                autoComplete="off"
                className="flex-1 resize-none bg-muted/50 border border-border rounded-xl px-3.5 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-foreground/20 placeholder:text-muted-foreground disabled:opacity-50"
                style={{ maxHeight: '80px' }}
                onInput={(e) => {
                  const el = e.currentTarget;
                  el.style.height = 'auto';
                  el.style.height = Math.min(el.scrollHeight, 80) + 'px';
                }}
              />
              <Button
                size="icon"
                onClick={handleSend}
                disabled={!input.trim() || isStreaming}
                className="h-10 w-10 rounded-xl bg-foreground text-background hover:bg-foreground/90 flex-shrink-0"
              >
                <Send className="w-4 h-4" />
              </Button>
            </div>
          </div>
        </DialogPrimitive.Content>
      </DialogPortal>
    </Dialog>
  );
};

export default BudgetAssistant;
