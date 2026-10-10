import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ArrowUp, Mic, Minus, Volume2, Square, Maximize2, Minimize2 } from 'lucide-react';
import { St4shSymbol } from '@/components/brand/St4sh';
import { Spinner, StatusLine } from '@/components/machine/Machine';
import { useToast } from '@/hooks/use-toast';
import { useSubscription } from '@/hooks/useSubscription';
import { useAuth } from '@/hooks/useAuth';
import { supabase, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from '@/integrations/supabase/client';
import { useVoiceInput } from '@/hooks/useVoiceInput';
import ReactMarkdown from 'react-markdown';
import ChatMessageSources from './ChatMessageSources';
import ChatMessageFeedback from './ChatMessageFeedback';
import { bakeCitationLinks, extractLinkedItemIds, itemIdFromHref } from '@/utils/chatCitations';
import CitationLink from '@/components/chat/CitationLink';
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
  // A loaded-then-let-go conversation, restorable with one click
  const [lastLoaded, setLastLoaded] = useState<{ id: string; title: string | null } | null>(null);
  const historyLoadedRef = useRef(false);

  const isExpanded = pinned || open;

  const loadConversationMessages = async (conversationId: string) => {
    // Newest 200 (descending), reversed to chronological — ascending+limit
    // would return the OLDEST 200 of a long conversation
    const { data: history } = await supabase
      .from('messages')
      .select('id, role, content, source_items, created_at')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: false })
      .limit(200);
    const restored: MoleMessage[] = (history ?? [])
      .filter(m => m.role === 'user' || m.role === 'assistant')
      .map(m => ({
        id: m.id,
        role: m.role as 'user' | 'assistant',
        content: m.content,
        sourceItemIds: m.source_items ?? undefined,
      }))
      .reverse();
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
    setLastLoaded(null); // a fresh explicit load supersedes any remembered one
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

  // Collapsing the mole "lets go" of an explicitly loaded old conversation:
  // the thread clears so reopening shows a mostly clean mole, and the loaded
  // conversation is remembered so it can be restored with one click.
  useEffect(() => {
    if (isExpanded) return;
    if (sessionRef.current.explicit && sessionRef.current.id) {
      setLastLoaded({ id: sessionRef.current.id, title: sessionTitleRef.current });
      setMessages([]);
      sessionRef.current = { id: null, lastMessageAt: 0, explicit: false };
      setSessionTitle(null);
    } else {
      sessionRef.current.explicit = false;
    }
  }, [isExpanded]);

  // Fresh context on demand — the old thread stays reachable in Earlier
  // conversations (and via the restore link if it was an explicit load)
  const startNewChat = () => {
    if (sessionRef.current.explicit && sessionRef.current.id) {
      setLastLoaded({ id: sessionRef.current.id, title: sessionTitleRef.current });
    }
    setMessages([]);
    sessionRef.current = { id: null, lastMessageAt: 0, explicit: false };
    setSessionTitle(null);
  };

  const restorePreviousConversation = () => {
    const prev = lastLoaded;
    if (!prev) return;
    setLastLoaded(null);
    sessionRef.current = { id: prev.id, lastMessageAt: Date.now(), explicit: true };
    setSessionTitle(prev.title);
    void loadConversationMessages(prev.id);
  };

  // Returns the conversation id to persist into, creating a new session when
  // the 3h gap elapsed (isNew: true). Explicitly resumed sessions are exempt
  // from the gap.
  const ensureSessionForSend = async (): Promise<{ id: string | null; isNew: boolean }> => {
    const s = sessionRef.current;
    const now = Date.now();
    if (s.id && (s.explicit || now - s.lastMessageAt < SESSION_GAP_MS)) {
      return { id: s.id, isNew: false };
    }
    if (s.id) setMessages([]); // stale session on screen — new session starts a fresh thread
    const id = await createConversation();
    sessionRef.current = { id, lastMessageAt: now, explicit: false };
    setSessionTitle(null);
    return { id, isNew: true };
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

    const { isNew } = await ensureSessionForSend();

    const userMessage: MoleMessage = { id: `u-${Date.now()}`, role: 'user', content: question };
    pushMessage(userMessage);
    persistMessage('user', question);

    const assistantId = `a-${Date.now()}`;

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error('Not signed in');

      // A brand-new session has no prior turns; messagesRef can still hold the
      // stale thread here (setMessages([]) may not have flushed yet), so don't
      // read it — the old session's messages must not leak into the request
      const history = isNew
        ? []
        : messagesRef.current
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

  /* ── minimized: the ask bar ──
     A black machine bar, bottom-left. Hover wakes a terminal cursor after its words. */
  if (!isExpanded) {
    return (
      <div className="group/ask fixed bottom-5 left-5 z-50 flex items-stretch bg-ink text-white shadow-print-sm">
        <button
          onClick={() => setOpen(true)}
          className="flex h-11 items-center gap-2.5 pl-3.5 pr-3 transition-colors hover:bg-ink-soft focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-spot"
          aria-label="Open Ask Stash"
        >
          <St4shSymbol className="h-[15px] w-[14px] text-spot-on-ink" />
          <span className="text-[15px] font-medium tracking-[-0.01em] group-hover/ask:v2-caret">Ask Stash</span>
          <span className="border border-white/40 px-1 pb-[2px] pt-[3px] font-pixel text-pixel leading-none text-white/80">⌘K</span>
        </button>
        <button
          type="button"
          aria-label="Ask by voice"
          className="grid w-11 place-items-center border-l border-white/20 transition-colors hover:bg-spot hover:text-spot-on focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-spot"
          onClick={() => {
            setOpen(true);
            if (voice.isSupported) setTimeout(() => voice.start(), 250);
          }}
        >
          <Mic className="h-4 w-4" />
        </button>
      </div>
    );
  }

  const iconButton =
    'grid h-7 w-7 place-items-center text-white/75 transition-colors hover:bg-white hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-spot';

  /* ── expanded: a window (floating) or a docked side panel (pinned) ── */
  return (
    <div
      className={
        pinned
          ? 'fixed bottom-0 left-0 top-0 z-40 flex w-full flex-col border-r border-ink bg-white sm:w-[384px]'
          : 'fixed bottom-0 left-0 right-0 z-50 flex h-[72vh] max-h-[calc(100vh-96px)] w-full flex-col border border-ink bg-white shadow-print sm:bottom-5 sm:left-5 sm:right-auto sm:h-[560px] sm:w-[384px]'
      }
    >
      {/* The window bar: the machine's name for this place, and its controls */}
      <div className="flex h-9 flex-none items-center gap-2 bg-ink pl-3 pr-1 text-white">
        <St4shSymbol className="h-[13px] w-[12px] flex-none text-spot-on-ink" />
        <span className="font-pixel text-pixel leading-none">ask stash</span>
        <div className="ml-auto flex gap-0.5">
          {pinned ? (
            <button
              onClick={() => { onPinnedChange(false); setOpen(true); }}
              title="Restore to floating"
              aria-label="Restore to floating"
              className={iconButton}
            >
              <Minimize2 className="h-3.5 w-3.5" />
            </button>
          ) : (
            <button
              onClick={() => { onPinnedChange(true); setOpen(true); }}
              title="Maximize — pin open as a sidebar"
              aria-label="Pin open as a sidebar"
              className={iconButton}
            >
              <Maximize2 className="h-3.5 w-3.5" />
            </button>
          )}
          <button
            onClick={() => { setOpen(false); if (pinned) onPinnedChange(false); }}
            title="Minimize"
            aria-label="Minimize"
            className={iconButton}
          >
            <Minus className="h-4 w-4" />
          </button>
        </div>
      </div>
      <div className="flex-none border-b border-line px-4 pb-2.5 pt-3">
        <div className="truncate text-[15px] font-medium leading-tight tracking-[-0.01em]">{sessionTitle ?? 'Ask Stash'}</div>
        <div className="mt-1 truncate font-pixel text-pixel text-muted-foreground">
          answers from your {itemCount} {itemCount === 1 ? 'save' : 'saves'}
        </div>
      </div>

      <div className="flex-1 space-y-5 overflow-y-auto px-4 py-4">
        {messages.length === 0 && lastLoaded && (
          <button
            onClick={restorePreviousConversation}
            className="block w-full border border-ink bg-white px-3 py-2.5 text-left text-[13px] hover:bg-ink hover:text-white"
          >
            Load previous conversation
            {lastLoaded.title ? <span className="opacity-70"> — {lastLoaded.title}</span> : null}
          </button>
        )}
        {messages.length === 0 && (
          // An empty thread is a small stage: the dot grid, and what this place is for
          <div className="v2-dots border border-line-soft px-4 py-5">
            <p className="max-w-[28em] bg-white/80 text-[15px] leading-[1.45] text-ink">
              Ask anything about what you've saved — answers cite the cards they came from.
            </p>
            <p className="mt-3 font-pixel text-pixel text-muted-foreground">⌘K opens this from anywhere</p>
          </div>
        )}
        {messages.map(message => {
          if (message.role === 'user') {
            return (
              <div key={message.id} className="ml-auto w-fit max-w-[86%] whitespace-pre-wrap rounded-object bg-fill px-3.5 py-2.5 text-[15px] leading-[1.45] text-ink">
                {message.content}
              </div>
            );
          }
          // Cited cards are linked inline (baked `#item=` hrefs); the bottom
          // sources row only lists whatever wasn't already linked in the text
          const inlineItemIds = extractLinkedItemIds(message.content);
          const extraSources = (message.sources ?? []).filter(s => !inlineItemIds.has(s.id));
          const focusIds = message.sources?.map(s => s.id) ?? message.sourceItemIds ?? [];
          const streaming = isBusy && message.id === messages[messages.length - 1]?.id && !message.sources;
          const focusActive =
            Boolean(focusedSourceIds) &&
            focusIds.every(id => focusedSourceIds!.includes(id)) &&
            focusedSourceIds!.length === focusIds.length;
          return (
            <div key={message.id} className="max-w-full">
              {/* The tool step, in the machine voice: what Stash did before it answered */}
              <div className="mb-2 flex items-center gap-2">
                <St4shSymbol className="h-[11px] w-[10px] flex-none text-ink" />
                {streaming ? (
                  <StatusLine tone="busy">writing the answer…</StatusLine>
                ) : (
                  <StatusLine tone="done" live={false}>
                    searched your stash{focusIds.length > 0 ? ` · ${focusIds.length} ${focusIds.length === 1 ? 'save' : 'saves'}` : ''}
                  </StatusLine>
                )}
              </div>
              <div className={`prose prose-sm max-w-none text-[15px] leading-[1.5] text-ink prose-p:my-1.5 prose-strong:font-medium prose-strong:text-ink prose-li:my-0.5 ${streaming ? '[&>*:last-child]:v2-caret-bar' : ''}`}>
                <ReactMarkdown
                  components={{
                    a: ({ href, children }) => {
                      const itemId = itemIdFromHref(href);
                      if (itemId) {
                        return (
                          <CitationLink href={href!} itemId={itemId} onOpen={(id) => onSourceClick?.(id)}>
                            {children}
                          </CitationLink>
                        );
                      }
                      // Mid-stream (#n) targets aren't resolvable yet — show as text
                      if (href?.startsWith('#')) {
                        return <span>{children}</span>;
                      }
                      return (
                        <a href={href} target="_blank" rel="noreferrer" className="text-ink underline underline-offset-[3px]">
                          {children}
                        </a>
                      );
                    },
                  }}
                >
                  {message.content}
                </ReactMarkdown>
              </div>
              {extraSources.length > 0 && (
                <ChatMessageSources
                  sources={extraSources}
                  onSourceClick={(id) => onSourceClick?.(id)}
                  onViewAllSources={() => {}}
                />
              )}
              <div className="mt-2.5 flex flex-wrap items-center gap-1.5">
                {focusIds.length > 0 && onFocusSources && (
                  <button
                    onClick={() => onFocusSources(focusActive ? null : focusIds)}
                    aria-pressed={focusActive}
                    className={`inline-flex h-7 items-center gap-1.5 px-2 font-pixel text-pixel leading-none transition-colors ${
                      focusActive
                        ? 'bg-spot text-spot-on shadow-[inset_0_0_0_1px_var(--ink)]'
                        : 'bg-white text-ink shadow-[inset_0_0_0_1px_var(--ink)] hover:bg-ink hover:text-white'
                    }`}
                  >
                    <span aria-hidden>⌖</span> {focusActive ? 'showing' : 'show'} {focusIds.length} {focusIds.length === 1 ? 'source' : 'sources'}
                  </button>
                )}
                {message.content && (
                  <button
                    onClick={() => toggleSpeak(message)}
                    title={speakingId === message.id ? 'Stop reading' : 'Read aloud'}
                    aria-label={speakingId === message.id ? 'Stop reading' : 'Read aloud'}
                    className={`grid h-7 w-7 place-items-center transition-colors ${
                      speakingId === message.id ? 'bg-ink text-white' : 'text-muted-foreground hover:bg-fill hover:text-ink'
                    }`}
                  >
                    {speakingId === message.id ? <Square className="h-3 w-3" /> : <Volume2 className="h-3.5 w-3.5" />}
                  </button>
                )}
                {message.sources && (
                  <ChatMessageFeedback
                    question={message.question || ''}
                    answer={message.content}
                    sourceItemIds={message.sources.map(s => s.id)}
                  />
                )}
              </div>
            </div>
          );
        })}
        {isBusy && messages[messages.length - 1]?.role === 'user' && (
          // Before the first word streams: the machine says what it's doing
          <div className="flex items-center gap-2">
            <St4shSymbol className="h-[11px] w-[10px] flex-none text-ink" />
            <StatusLine tone="busy">searching your stash…</StatusLine>
          </div>
        )}
        <div ref={threadEndRef} />
      </div>

      <div className="flex-none border-t border-line px-3.5 pb-3 pt-3">
        {voice.isListening ? (
          <div>
            <div className="flex items-center gap-3 border border-ink bg-spot px-3 py-2.5 text-spot-on">
              <button
                onClick={voice.stop}
                className="grid h-9 w-9 flex-none place-items-center bg-ink text-white"
                title="Tap to ask"
                aria-label="Stop listening and ask"
              >
                <Mic className="h-4 w-4" />
              </button>
              <div className="flex h-6 items-center gap-[3px]" aria-hidden>
                {[12, 20, 15, 24, 10, 18, 13].map((h, i) => (
                  <span
                    key={i}
                    className="block w-[3px] animate-pulse bg-current"
                    style={{ height: h, animationDelay: `${i * 110}ms` }}
                  />
                ))}
              </div>
              <div className="flex-1 truncate text-[14px] italic">
                {voice.interimTranscript || 'Listening…'}
              </div>
            </div>
            <div className="mt-2 font-pixel text-pixel text-muted-foreground">
              listening · tap the mic to ask · esc to cancel
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
                className="h-10 min-w-0 flex-1 border border-line bg-white px-3 text-[15px] outline-none transition-shadow placeholder:text-muted-foreground focus:border-ink focus:shadow-[0_0_0_3px_rgb(var(--spot-rgb))]"
              />
              {voice.isSupported && (
                <button
                  type="button"
                  className="grid h-10 w-10 flex-none place-items-center border border-line bg-white text-ink transition-colors hover:border-ink hover:bg-fill"
                  onClick={voice.start}
                  title="Ask by voice"
                  aria-label="Ask by voice"
                >
                  <Mic className="h-4 w-4" />
                </button>
              )}
              <button
                type="button"
                className="grid h-10 w-10 flex-none place-items-center bg-ink text-white transition-opacity hover:bg-ink-soft disabled:opacity-25"
                onClick={() => void handleSend()}
                disabled={isBusy || !input.trim()}
                title="Send"
                aria-label="Send"
              >
                {isBusy ? <Spinner className="font-pixel text-pixel-md leading-none" /> : <ArrowUp className="h-4 w-4" />}
              </button>
            </div>
            <div className="mt-2.5 flex items-center gap-2 text-[13px]">
              <button
                onClick={startNewChat}
                className="text-muted-foreground underline-offset-[3px] hover:text-ink hover:underline"
              >
                Start new chat
              </button>
              <span className="text-muted-foreground/50" aria-hidden>·</span>
              <button
                onClick={onToggleConversations}
                className={`underline-offset-[3px] hover:underline ${
                  conversationsOpen ? 'font-medium text-ink' : 'text-muted-foreground hover:text-ink'
                }`}
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
