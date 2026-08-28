import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import ChatMole from './ChatMole';

const NOW = new Date('2026-08-27T12:00:00Z');

const {
  latestConversation,
  convMaybeSingle,
  convInsertSingle,
  convInsert,
  msgSelectLimit,
  msgInsert,
  mockFrom,
  mockGetSession,
  mockInvoke,
} = vi.hoisted(() => {
  const latest = { current: null as { id: string; title: string | null; last_message_at: string } | null };

  // conversations: select('id, title, last_message_at').eq().order().limit(1).maybeSingle()
  const convMaybeSingleFn = vi.fn(async () => ({ data: latest.current, error: null }));
  const convSelect = vi.fn(() => ({
    eq: vi.fn(() => ({
      order: vi.fn(() => ({
        limit: vi.fn(() => ({ maybeSingle: convMaybeSingleFn })),
      })),
    })),
  }));
  // conversations: insert({...}).select('id').single()
  const convInsertSingleFn = vi.fn(async () => ({ data: { id: 'new-conv' }, error: null }));
  const convInsertFn = vi.fn(() => ({ select: vi.fn(() => ({ single: convInsertSingleFn })) }));
  // conversations: update({title}).eq() (auto-title after first exchange)
  const convUpdate = vi.fn(() => ({ eq: vi.fn(async () => ({ error: null })) }));

  // messages: select().eq().order().limit(200) resolves; insert(...) is thenable
  const msgSelectLimitFn = vi.fn(async () => ({ data: [], error: null }));
  const msgSelect = vi.fn(() => ({
    eq: vi.fn(() => ({
      order: vi.fn(() => ({ limit: msgSelectLimitFn })),
    })),
  }));
  const msgInsertFn = vi.fn(() => Promise.resolve({ error: null }));

  const from = vi.fn((table: string) => {
    if (table === 'conversations') {
      return { select: convSelect, insert: convInsertFn, update: convUpdate };
    }
    return { select: msgSelect, insert: msgInsertFn };
  });

  return {
    latestConversation: latest,
    convMaybeSingle: convMaybeSingleFn,
    convInsertSingle: convInsertSingleFn,
    convInsert: convInsertFn,
    msgSelectLimit: msgSelectLimitFn,
    msgInsert: msgInsertFn,
    mockFrom: from,
    mockGetSession: vi.fn(async () => ({ data: { session: { access_token: 'tok' } } })),
    mockInvoke: vi.fn(async () => ({ data: { title: 'X' }, error: null })),
  };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: mockFrom,
    auth: { getSession: mockGetSession },
    functions: { invoke: mockInvoke },
  },
  SUPABASE_URL: 'http://supabase.test',
  SUPABASE_PUBLISHABLE_KEY: 'pk-test',
}));

vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'u1' } }) }));
vi.mock('@/hooks/useSubscription', () => ({ useSubscription: () => ({ canUseAI: true }) }));
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: vi.fn() }) }));
vi.mock('@/hooks/useVoiceInput', () => ({
  useVoiceInput: () => ({
    isSupported: false,
    isListening: false,
    interimTranscript: '',
    start: vi.fn(),
    stop: vi.fn(),
    cancel: vi.fn(),
  }),
}));

const sseResponse = () => {
  const encoder = new TextEncoder();
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode('data: {"delta":"hi"}\n\n'));
      controller.enqueue(encoder.encode('data: {"done":true,"sources":[]}\n\n'));
      controller.close();
    },
  });
  return { ok: true, status: 200, body } as unknown as Response;
};

const hoursBefore = (h: number) => new Date(NOW.getTime() - h * 60 * 60 * 1000).toISOString();

const renderMoleAndSend = async () => {
  render(<ChatMole pinned onPinnedChange={() => {}} itemCount={1} />);

  // Let the initial history load settle (it decides the session target)
  await waitFor(() => expect(convMaybeSingle).toHaveBeenCalled());

  const input = await screen.findByPlaceholderText('Ask your stash…');
  fireEvent.change(input, { target: { value: 'what did I save?' } });
  fireEvent.keyDown(input, { key: 'Enter' });

  // The send completes when the SSE call has fired
  await waitFor(() => expect(global.fetch).toHaveBeenCalled());
};

describe('ChatMole session gap on send', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Only fake Date — real timers keep async/waitFor working
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(NOW);
    window.HTMLElement.prototype.scrollIntoView = vi.fn();
    global.fetch = vi.fn(async () => sseResponse()) as unknown as typeof fetch;
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('creates a new conversation when the 3h gap has elapsed', async () => {
    latestConversation.current = { id: 'old', title: 'T', last_message_at: hoursBefore(4) };

    await renderMoleAndSend();

    await waitFor(() => expect(convInsert).toHaveBeenCalled());
    expect(convInsertSingle).toHaveBeenCalled();
    // The streamed reply lands in the (new) thread
    await screen.findByText('hi');
    // And persistence targets the new conversation
    await waitFor(() =>
      expect(msgInsert).toHaveBeenCalledWith(
        expect.objectContaining({ conversation_id: 'new-conv', role: 'user' })
      )
    );
  });

  it('"Start new chat" forces a new conversation even inside the gap', async () => {
    latestConversation.current = { id: 'old', title: 'T', last_message_at: hoursBefore(1) };

    render(<ChatMole pinned onPinnedChange={() => {}} itemCount={1} />);
    await waitFor(() => expect(convMaybeSingle).toHaveBeenCalled());

    fireEvent.click(screen.getByText('Start new chat'));

    const input = await screen.findByPlaceholderText('Ask your stash…');
    fireEvent.change(input, { target: { value: 'fresh context please' } });
    fireEvent.keyDown(input, { key: 'Enter' });
    await waitFor(() => expect(global.fetch).toHaveBeenCalled());

    await waitFor(() => expect(convInsert).toHaveBeenCalled());
    await waitFor(() =>
      expect(msgInsert).toHaveBeenCalledWith(
        expect.objectContaining({ conversation_id: 'new-conv', role: 'user' })
      )
    );
  });

  it('continues the existing conversation inside the gap', async () => {
    latestConversation.current = { id: 'old', title: 'T', last_message_at: hoursBefore(1) };

    await renderMoleAndSend();

    await screen.findByText('hi');
    expect(convInsert).not.toHaveBeenCalled();
    // Persistence targets the resumed conversation
    await waitFor(() =>
      expect(msgInsert).toHaveBeenCalledWith(
        expect.objectContaining({ conversation_id: 'old', role: 'user' })
      )
    );
  });
});
