import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Mic, Minus, Send, Volume2, Square, Maximize2, Minimize2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useSubscription } from '@/hooks/useSubscription';
import { useAuth } from '@/hooks/useAuth';
import { supabase, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from '@/integrations/supabase/client';
import { useVoiceInput } from '@/hooks/useVoiceInput';
import ReactMarkdown from 'react-markdown';
import ChatMessageSources from './ChatMessageSources';
import ChatMessageFeedback from './ChatMessageFeedback';
import { bakeCitationLinks, extractLinkedItemIds, itemIdFromHref } from '@/utils/chatCitations';
import { resolveSessionTarget, SESSION_GAP_MS } from '@/utils/chatSessions';

interface MoleSource {
  id: string;
  title: string;
  type: string;
  url?: string;
  // Citation number in the answer text ([n] / (#n)) — used once at stream end
  // to bake item links into the markdown; absent on history reloads
  n?: number;
}

interface MoleMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  question?: string;
  sources?: MoleSource[];
  sourceItemIds?: string[];
}

interface ChatMoleProps {
  pinned: boolean;
  onPinnedChange: (pinned: boolean) => void;
  onSourceClick?: (sourceId: string) => void;
  itemCount: number;
  openConversationRequest?: { id: string; title: string | null; token: number } | null;
  conversationsOpen?: boolean;
  onToggleConversations?: () => void;
  focusedSourceIds?: string[] | null;
  onFocusSources?: (ids: string[] | null) => void;
}

const MoleGlyph = ({ className }: { className?: string }) => (
  <svg viewBox="586 424 134 176" fill="currentColor" className={className} aria-hidden>
    <path d="M662.882 436.064C660.343 432.928 652.745 424.888 648.723 425.218C631.503 426.662 614.854 432.253 603.262 445.753C587.108 464.564 587.541 499.498 607.725 515.435C615.558 521.669 623.683 525.093 633.184 527.935L634.778 523.356C639.443 510.591 644.431 500.28 652.078 488.924C644.276 486.269 634.138 482.096 638.038 471.185C641.257 462.176 655.336 460.522 662.77 464.389C666.655 466.247 668.705 468.967 670.798 472.548C672.22 459.272 671.626 446.857 662.882 436.064Z"/>
    <path d="M701.56 506.142C694.717 501.845 686.051 496.885 678.015 495.281C673.407 508.547 667.021 522.648 659.27 534.412C664.95 536.676 667.754 537.589 671.562 542.6C675.651 562.928 651.251 565.37 638.727 554.86C638.034 568.698 639.823 579.499 649.517 590.156C652.59 593.542 656.178 596.422 660.149 598.688C664.733 598.313 669.741 597.863 674.224 596.763C705.395 589.088 725.754 563.456 717.527 530.886C716.39 526.275 714.58 521.857 712.154 517.775C703.796 517.693 695.437 517.714 687.079 517.837L687.093 506.374C691.914 506.247 696.737 506.17 701.56 506.142Z"/>
    <path d="M628.769 543.112L588.243 543.022C588.414 557.656 591.566 570.552 602.516 581.451C612.06 590.951 625.245 596.47 638.715 598.022C638.888 598.042 639.484 597.986 639.808 597.956C639.858 597.951 639.902 597.947 639.937 597.944L640.233 597.562C628.187 581.492 625.166 567.991 628.011 547.91C628.242 546.307 628.495 544.708 628.769 543.112Z"/>
    <path d="M714.734 466.665C711.179 443.064 693.24 430.046 670.275 426.354C682.455 442.656 684.321 457.169 681.496 477.28L681.406 477.898L715.346 477.83C716.012 474.525 715.529 471.575 715.016 468.439C714.921 467.855 714.824 467.265 714.734 466.665Z"/>
    <path d="M666.79 493.036C665.719 492.082 665.19 492.111 663.779 491.769C658.701 499.095 643.4 522.413 644.212 530.405C645.32 531.227 646.065 531.28 647.401 531.585C652.576 523.86 666.33 502.329 666.79 493.036Z"/>
  </svg>
);

const stripForSpeech = (markdown: string): string =>
  markdown
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1') // flatten links to their text
    .replace(/\[(\d+)\]/g, '')
    .replace(/[*_#`>]/g, '')
    .replace(/\s+/g, ' ')
    .trim();

const ChatMole = ({
  pinned,
  onPinnedChange,
  onSourceClick,
  itemCount,
  openConversationRequest,
  conversationsOpen = false,
  onToggleConversations,
  focusedSourceIds,
  onFocusSources,
}: ChatMoleProps) => {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<MoleMessage[]>([]);
  const [input, setInput] = useState('');
  const [isBusy, setIsBusy] = useState(false);
  const [speakingId, setSpeakingId] = useState<string | null>(null);
  const threadEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const messagesRef = useRef<MoleMessage[]>([]);
  messagesRef.current = messages;
  const { toast } = useToast();
  const { canUseAI } = useSubscription();
  const { user } = useAuth();
  const sessionRef = useRef<{ id: string | null; lastMessageAt: number; explicit: boolean }>(
    { id: null, lastMessageAt: 0, explicit: false }
  );
  const [sessionTitle, setSessionTitle] = useState<string | null>(null);
  const sessionTitleRef = useRef<string | null>(null);
  sessionTitleRef.current = sessionTitle;
  const historyLoadedRef = useRef(false);

  const isExpanded = pinned || open;

  const loadConversationMessages = async (conversationId: string) => {
    const { data: history } = await supabase
      .from('messages')
      .select('id, role, content, source_items, created_at')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: true })
      .limit(200);
    const restored: MoleMessage[] = (history ?? [])
      .filter(m => m.role === 'user' || m.role === 'assistant')
      .map(m => ({
        id: m.id,
        role: m.role as 'user' | 'assistant',
        content: m.content,
        sourceItemIds: m.source_items ?? undefined,
      }));
    setMessages(restored);
  };

  // First-class memory: the thread lives in the conversations/messages tables
  // and survives sessions. Loaded once, on first expand. Targets the latest
  // session and applies the 3h gap rule; never creates a row here (rows are
  // created lazily on first send).
  useEffect(() => {
    if (!isExpanded || !user?.id || historyLoadedRef.current) return;
    historyLoadedRef.current = true;

    const loadHistory = async () => {
      try {
        const { data: latest } = await supabase
          .from('conversations')
          .select('id, title, last_message_at')
          .eq('user_id', user.id)
          .order('last_message_at', { ascending: false, nullsFirst: false })
          .limit(1)
          .maybeSingle();

        const target = resolveSessionTarget(latest ?? null, new Date());
        if (target.kind === 'new') {
          // Fresh thread; the conversation row is created on first send
          sessionRef.current = { id: null, lastMessageAt: 0, explicit: false };
          return;
        }

        sessionRef.current = {
          id: target.id,
          lastMessageAt: new Date(latest!.last_message_at!).getTime(),
          explicit: false,
        };
        setSessionTitle(target.title);
        await loadConversationMessages(target.id);
      } catch (error) {
        console.error('Failed to load chat history (non-fatal):', error);
      }
    };

    void loadHistory();
  }, [isExpanded, user?.id]);

  // Open a specific conversation from the Conversations view. The token
  // forces re-fire even when re-opening the same id.
  useEffect(() => {
    const req = openConversationRequest;
    if (!req) return;
    sessionRef.current = { id: req.id, lastMessageAt: Date.now(), explicit: true };
    setSessionTitle(req.title);
    void loadConversationMessages(req.id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [openConversationRequest?.token]);

  const persistMessage = (role: 'user' | 'assistant', content: string, sourceItemIds?: string[]) => {
    const conversationId = sessionRef.current.id;
    if (!conversationId || !content.trim()) return;
    void supabase
      .from('messages')
      .insert({
        conversation_id: conversationId,
        role,
        content,
        source_items: sourceItemIds && sourceItemIds.length > 0 ? sourceItemIds : null,
      })
      .then(({ error }) => {
        if (error) console.error('Failed to persist chat message (non-fatal):', error);
        else sessionRef.current.lastMessageAt = Date.now();
      });
  };

  const createConversation = async (): Promise<string | null> => {
    if (!user?.id) return null;
    const { data, error } = await supabase
      .from('conversations')
      .insert({ user_id: user.id, title: null })
      .select('id')
      .single();
    if (error) {
      console.error('Failed to create conversation (non-fatal):', error);
      return null;
    }
    return data.id;
  };

  // Returns the conversation id to persist into, creating a new session when
  // the 3h gap elapsed. Explicitly resumed sessions are exempt from the gap.
  const ensureSessionForSend = async (): Promise<string | null> => {
    const s = sessionRef.current;
    const now = Date.now();
    if (s.id && (s.explicit || now - s.lastMessageAt < SESSION_GAP_MS)) return s.id;
    if (s.id) setMessages([]); // stale session on screen — new session starts a fresh thread
    const id = await createConversation();
    sessionRef.current = { id, lastMessageAt: now, explicit: false };
    setSessionTitle(null);
    return id;
  };

  const sendTranscript = useCallback((text: string) => {
    void handleSend(text);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const voice = useVoiceInput({ onFinalTranscript: sendTranscript });

  useEffect(() => {
    threadEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isExpanded]);

  // ⌘K / Ctrl+K toggles the mole from anywhere
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        if (pinned) {
          inputRef.current?.focus();
        } else {
          setOpen(prev => !prev);
        }
      }
      if (e.key === 'Escape' && voice.isListening) {
        voice.cancel();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [pinned, voice]);

  useEffect(() => {
    if (isExpanded) {
      setTimeout(() => inputRef.current?.focus(), 80);
    }
  }, [isExpanded]);

  const pushMessage = (message: MoleMessage) => {
    setMessages(prev => [...prev, message]);
  };

  const ask = async (question: string) => {
    if (!canUseAI) {
      toast({ title: 'Subscription needed', description: 'AI chat needs an active trial or subscription.', variant: 'destructive' });
      return;
    }

    await ensureSessionForSend();

    const userMessage: MoleMessage = { id: `u-${Date.now()}`, role: 'user', content: question };
    pushMessage(userMessage);
    persistMessage('user', question);

    const assistantId = `a-${Date.now()}`;

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error('Not signed in');

      const history = messagesRef.current
        .filter(m => m.role === 'user' || m.role === 'assistant')
        .map(m => ({ role: m.role, content: m.content }));

      const response = await fetch(`${SUPABASE_URL}/functions/v1/chat-with-all-content`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`,
          'apikey': SUPABASE_PUBLISHABLE_KEY,
        },
        body: JSON.stringify({ message: question, conversationHistory: history }),
      });

      if (!response.ok || !response.body) throw new Error(`Chat failed (${response.status})`);

      pushMessage({ id: assistantId, role: 'assistant', content: '', question });

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let streamed = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';
        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed.startsWith('data:')) continue;
          const payload = JSON.parse(trimmed.slice(5).trim());
          if (payload.delta) {
            streamed += payload.delta;
            setMessages(prev => prev.map(m => (m.id === assistantId ? { ...m, content: streamed } : m)));
          } else if (payload.done) {
            const sources: MoleSource[] = payload.sources || [];
            // Bake (#n) citation targets into stable item links so titles are
            // clickable now AND after a history reload (which restores only
            // the message text)
            const baked = bakeCitationLinks(streamed, sources);
            setMessages(prev => prev.map(m => (m.id === assistantId ? { ...m, content: baked, sources } : m)));
            persistMessage('assistant', baked, sources.map((s: MoleSource) => s.id));

            // Auto-title the conversation after the first exchange
            if (!sessionTitleRef.current && sessionRef.current.id) {
              const conversationId = sessionRef.current.id;
              void supabase.functions
                .invoke('generate-title', { body: { content: question } })
                .then(async ({ data }) => {
                  const title = (data?.title || question).trim().slice(0, 80);
                  setSessionTitle(title);
                  await supabase.from('conversations').update({ title }).eq('id', conversationId);
                })
                .catch((e: unknown) => console.error('Title generation failed (non-fatal):', e));
            }
          } else if (payload.error) {
            throw new Error(payload.error);
          }
        }
      }

      if (!streamed) throw new Error('Empty response');
    } catch (error) {
      console.error('Mole chat error:', error);
      setMessages(prev => prev.filter(m => m.id !== assistantId && m.id !== userMessage.id));
      setInput(question);
      toast({ title: 'Error', description: 'Failed to get a response.', variant: 'destructive' });
    }
  };

  const handleSend = async (raw?: string) => {
    const text = (raw ?? input).trim();
    if (!text || isBusy) return;
    setInput('');
    setIsBusy(true);
    try {
      await ask(text);
    } finally {
      setIsBusy(false);
    }
  };

  const toggleSpeak = (message: MoleMessage) => {
    if (speakingId === message.id) {
      window.speechSynthesis?.cancel();
      setSpeakingId(null);
      return;
    }
    window.speechSynthesis?.cancel();
    const utterance = new SpeechSynthesisUtterance(stripForSpeech(message.content));
    utterance.onend = () => setSpeakingId(null);
    setSpeakingId(message.id);
    window.speechSynthesis?.speak(utterance);
  };

  /* ── minimized pill ── */
  if (!isExpanded) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="fixed left-5 bottom-5 z-50 flex items-center gap-2.5 rounded-full bg-gradient-to-b from-gray-800 to-gray-950 pl-4 pr-2 py-2.5 text-white shadow-[0_10px_30px_rgba(20,10,40,0.35),0_2px_6px_rgba(0,0,0,0.2)] ring-1 ring-white/10 hover:from-gray-700 hover:to-gray-900 transition-all"
        aria-label="Open Ask Stash"
      >
        <span className="text-sm font-medium">Ask Stash</span>
        <span className="text-[10px] bg-white/15 rounded px-1.5 py-0.5">⌘K</span>
        <span
          className="grid place-items-center h-7 w-7 rounded-full bg-white/15 hover:bg-white/25 transition-colors"
          onClick={(e) => {
            e.stopPropagation();
            setOpen(true);
            if (voice.isSupported) setTimeout(() => voice.start(), 250);
          }}
        >
          <Mic className="h-3.5 w-3.5" />
        </span>
      </button>
    );
  }

  /* ── expanded panel (floating or pinned) ── */
  return (
    <div
      className={
        pinned
          ? 'fixed left-0 top-16 bottom-0 z-40 flex w-full sm:w-[384px] flex-col border-r border-black/5 bg-gradient-to-b from-white to-[#fdf8fd] shadow-[8px_0_24px_rgba(40,20,60,0.10)]'
          : 'fixed left-0 right-0 bottom-0 sm:left-5 sm:right-auto sm:bottom-5 z-50 flex h-[72vh] sm:h-[560px] w-full sm:w-[384px] max-h-[calc(100vh-96px)] flex-col overflow-hidden rounded-t-2xl sm:rounded-2xl bg-gradient-to-b from-white to-[#fdf8fd] shadow-[0_24px_60px_rgba(40,20,60,0.28),0_2px_8px_rgba(0,0,0,0.10)] ring-1 ring-black/5'
      }
    >
      <div className="flex items-center gap-2.5 border-b border-black/5 px-4 py-3">
        <MoleGlyph className="h-5 w-5 text-gray-900" />
        <div className="min-w-0">
          <div className="text-sm font-semibold leading-tight">{sessionTitle ?? 'Ask Stash'}</div>
          <div className="truncate text-xs text-muted-foreground">
            Answers from your {itemCount} items
          </div>
        </div>
        <div className="ml-auto flex gap-1.5">
          {pinned ? (
            <button
              onClick={() => { onPinnedChange(false); setOpen(true); }}
              title="Restore to floating"
              className="grid h-8 w-8 place-items-center rounded-lg border border-black/5 bg-white text-muted-foreground shadow-sm hover:text-foreground hover:shadow transition-all"
            >
              <Minimize2 className="h-3.5 w-3.5" />
            </button>
          ) : (
            <button
              onClick={() => { onPinnedChange(true); setOpen(true); }}
              title="Maximize — pin open as a sidebar"
              className="grid h-8 w-8 place-items-center rounded-lg border border-black/5 bg-white text-muted-foreground shadow-sm hover:text-foreground hover:shadow transition-all"
            >
              <Maximize2 className="h-3.5 w-3.5" />
            </button>
          )}
          <button
            onClick={() => { setOpen(false); if (pinned) onPinnedChange(false); }}
            title="Minimize"
            className="grid h-8 w-8 place-items-center rounded-lg border border-black/5 bg-white text-muted-foreground shadow-sm hover:text-foreground hover:shadow transition-all"
          >
            <Minus className="h-4 w-4" />
          </button>
        </div>
      </div>

      <div className="flex-1 space-y-3.5 overflow-y-auto px-4 py-4">
        {messages.length === 0 && (
          <div className="rounded-xl bg-muted/60 px-4 py-3 text-sm text-muted-foreground">
            Ask anything about what you've saved — or paste a link here and I'll stash it.
            Start a message with <b>remember:</b> to save a quick note.
          </div>
        )}
        {messages.map(message => {
          if (message.role === 'user') {
            return (
              <div key={message.id} className="ml-auto max-w-[86%] rounded-2xl rounded-br-sm bg-gray-900 px-3.5 py-2.5 text-sm text-white">
                {message.content}
              </div>
            );
          }
          // Cited cards are linked inline (baked `#item=` hrefs); the bottom
          // sources row only lists whatever wasn't already linked in the text
          const inlineItemIds = extractLinkedItemIds(message.content);
          const extraSources = (message.sources ?? []).filter(s => !inlineItemIds.has(s.id));
          const focusIds = message.sources?.map(s => s.id) ?? message.sourceItemIds ?? [];
          return (
            <div key={message.id} className="max-w-[92%] rounded-2xl rounded-bl-sm bg-muted/70 px-3.5 py-2.5 text-sm">
              <div className="prose prose-sm max-w-none [&_p]:my-1">
                <ReactMarkdown
                  components={{
                    a: ({ href, children }) => {
                      const itemId = itemIdFromHref(href);
                      if (itemId) {
                        return (
                          <button
                            onClick={() => onSourceClick?.(itemId)}
                            className="inline p-0 font-medium text-violet-700 underline decoration-violet-300 underline-offset-2 hover:decoration-violet-700"
                          >
                            {children}
                          </button>
                        );
                      }
                      // Mid-stream (#n) targets aren't resolvable yet — show as text
                      if (href?.startsWith('#')) {
                        return <span>{children}</span>;
                      }
                      return (
                        <a href={href} target="_blank" rel="noreferrer" className="underline">
                          {children}
                        </a>
                      );
                    },
                  }}
                >
                  {message.content}
                </ReactMarkdown>
              </div>
              {message.content && (
                <button
                  onClick={() => toggleSpeak(message)}
                  title={speakingId === message.id ? 'Stop reading' : 'Read aloud'}
                  className={`mt-1 inline-grid h-6 w-6 place-items-center rounded-md ${speakingId === message.id ? 'bg-violet-200 text-violet-700' : 'bg-black/5 text-muted-foreground hover:bg-black/10'}`}
                >
                  {speakingId === message.id ? <Square className="h-3 w-3" /> : <Volume2 className="h-3.5 w-3.5" />}
                </button>
              )}
              {focusIds.length > 0 && onFocusSources && (
                <button
                  onClick={() => {
                    const isActive =
                      focusedSourceIds?.length === focusIds.length &&
                      focusIds.every(id => focusedSourceIds.includes(id));
                    onFocusSources(isActive ? null : focusIds);
                  }}
                  className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-[11.5px] ${
                    focusedSourceIds && focusIds.every(id => focusedSourceIds.includes(id)) && focusedSourceIds.length === focusIds.length
                      ? 'border-violet-600 bg-violet-600 text-white'
                      : 'border-violet-200 bg-white text-violet-700 hover:bg-violet-50'
                  }`}
                >
                  ⌖ Focus sources ({focusIds.length})
                </button>
              )}
              {extraSources.length > 0 && (
                <ChatMessageSources
                  sources={extraSources}
                  onSourceClick={(id) => onSourceClick?.(id)}
                  onViewAllSources={() => {}}
                />
              )}
              {message.sources && (
                <ChatMessageFeedback
                  question={message.question || ''}
                  answer={message.content}
                  sourceItemIds={message.sources.map(s => s.id)}
                />
              )}
            </div>
          );
        })}
        {isBusy && (
          <div className="flex gap-1.5 px-1 py-1">
            <span className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/50" />
            <span className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/50 [animation-delay:120ms]" />
            <span className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/50 [animation-delay:240ms]" />
          </div>
        )}
        <div ref={threadEndRef} />
      </div>

      <div className="border-t border-border px-3.5 py-3">
        {voice.isListening ? (
          <div>
            <div className="flex items-center gap-3 rounded-xl border border-violet-200 bg-violet-50 px-3 py-2.5">
              <button
                onClick={voice.stop}
                className="grid h-9 w-9 flex-none animate-pulse place-items-center rounded-full bg-violet-500 text-white shadow-[0_0_0_6px_rgba(139,92,246,0.18)]"
                title="Tap to ask"
              >
                <Mic className="h-4 w-4" />
              </button>
              <div className="flex h-6 items-center gap-[3px]" aria-hidden>
                {[12, 20, 15, 24, 10, 18, 13].map((h, i) => (
                  <span
                    key={i}
                    className="block w-[3.5px] animate-pulse rounded-full bg-violet-500"
                    style={{ height: h, animationDelay: `${i * 110}ms` }}
                  />
                ))}
              </div>
              <div className="flex-1 truncate text-[13px] italic text-gray-600">
                {voice.interimTranscript || 'Listening…'}
              </div>
            </div>
            <div className="mt-2 text-[11.5px] text-muted-foreground">
              Listening — tap the mic to ask · <b>esc</b> to cancel
            </div>
          </div>
        ) : (
          <>
            <div className="flex items-center gap-2">
              <input
                ref={inputRef}
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') void handleSend(); }}
                placeholder="Ask your stash…"
                className="h-10 flex-1 rounded-xl border border-border bg-gray-50 px-3 text-sm outline-none focus:border-violet-300"
              />
              {voice.isSupported && (
                <Button
                  variant="outline"
                  size="icon"
                  className="h-10 w-10 rounded-xl"
                  onClick={voice.start}
                  title="Ask by voice"
                >
                  <Mic className="h-4 w-4" />
                </Button>
              )}
              <Button
                size="icon"
                className="h-10 w-10 rounded-xl bg-violet-500 hover:bg-violet-600"
                onClick={() => void handleSend()}
                disabled={isBusy || !input.trim()}
                title="Send"
              >
                <Send className="h-4 w-4" />
              </Button>
            </div>
            <div className="mt-2 text-[11.5px]">
              <button
                onClick={onToggleConversations}
                className={
                  conversationsOpen
                    ? 'font-medium text-violet-700 hover:underline underline-offset-2'
                    : 'text-muted-foreground hover:text-violet-700 hover:underline underline-offset-2'
                }
              >
                {conversationsOpen ? 'Back to your stash' : 'Earlier conversations'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
};

export default ChatMole;
