import { act, renderHook } from '@testing-library/react';
import { mergeItemRows, useItems } from './useItems';

/**
 * Realtime keeps the library current by re-reading only the rows that changed, instead of
 * refetching every save on every enrichment write.
 */
const { handlers, mockIn, mockOrder, mockFrom } = vi.hoisted(() => {
  const handlers: Array<(payload: unknown) => void> = [];
  const order = vi.fn(() =>
    Promise.resolve({
      data: [
        { id: 'b', title: 'Bravo', created_at: '2026-10-02T00:00:00Z' },
        { id: 'a', title: 'Alpha', created_at: '2026-10-01T00:00:00Z' },
      ],
      error: null,
    }),
  );
  const inFn = vi.fn(() => Promise.resolve({ data: [{ id: 'a', title: 'Alpha, named', created_at: '2026-10-01T00:00:00Z' }], error: null }));
  const eq = vi.fn(() => ({ order, in: inFn }));
  const select = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ select }));
  return { handlers, mockIn: inFn, mockOrder: order, mockFrom: from };
});

vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'u1' } }) }));
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: vi.fn() }) }));
vi.mock('@/integrations/supabase/client', () => {
  const channel = {
    on: vi.fn(function (this: unknown, _event: string, _filter: unknown, handler: (payload: unknown) => void) {
      handlers.push(handler);
      return channel;
    }),
    subscribe: vi.fn(() => channel),
  };
  return { supabase: { from: mockFrom, channel: vi.fn(() => channel), removeChannel: vi.fn() } };
});

describe('mergeItemRows', () => {
  it('replaces changed rows, adds new ones, and keeps newest first', () => {
    const current = [
      { id: 'b', created_at: '2026-10-02T00:00:00Z', title: 'Bravo' },
      { id: 'a', created_at: '2026-10-01T00:00:00Z', title: 'Alpha' },
    ];
    const merged = mergeItemRows(current, [
      { id: 'a', created_at: '2026-10-01T00:00:00Z', title: 'Alpha, named' },
      { id: 'c', created_at: '2026-10-03T00:00:00Z', title: 'Charlie' },
    ]);
    expect(merged.map((row) => `${row.id}:${row.title}`)).toEqual(['c:Charlie', 'b:Bravo', 'a:Alpha, named']);
  });

  it('is the same list when nothing came back', () => {
    const current = [{ id: 'a', created_at: '2026-10-01T00:00:00Z' }];
    expect(mergeItemRows(current, [])).toBe(current);
  });
});

describe('useItems realtime', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    handlers.length = 0;
    mockIn.mockClear();
    mockOrder.mockClear();
  });
  afterEach(() => vi.useRealTimers());

  it('re-reads only the rows an update named, and merges them in', async () => {
    const { result } = renderHook(() => useItems());
    await act(async () => {
      await vi.runOnlyPendingTimersAsync();
    });
    expect(result.current.items.map((item) => item.title)).toEqual(['Bravo', 'Alpha']);
    expect(mockOrder).toHaveBeenCalledTimes(1);

    act(() => {
      handlers[0]({ eventType: 'UPDATE', new: { id: 'a' }, old: { id: 'a' } });
      handlers[0]({ eventType: 'UPDATE', new: { id: 'a' }, old: { id: 'a' } });
    });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(500);
    });
    expect(mockIn).toHaveBeenCalledTimes(1);
    expect(mockIn).toHaveBeenCalledWith('id', ['a']);
    expect(mockOrder).toHaveBeenCalledTimes(1); // no full refetch
    expect(result.current.items.map((item) => item.title)).toEqual(['Bravo', 'Alpha, named']);
  });

  it('drops a deleted row without any read', async () => {
    const { result } = renderHook(() => useItems());
    await act(async () => {
      await vi.runOnlyPendingTimersAsync();
    });
    act(() => {
      handlers[0]({ eventType: 'DELETE', new: null, old: { id: 'b' } });
    });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(500);
    });
    expect(result.current.items.map((item) => item.id)).toEqual(['a']);
    expect(mockIn).not.toHaveBeenCalled();
  });

  it('falls back to the full refetch when an event names no row', async () => {
    renderHook(() => useItems());
    await act(async () => {
      await vi.runOnlyPendingTimersAsync();
    });
    act(() => {
      handlers[0]({ eventType: 'UPDATE', new: {}, old: {} });
    });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(500);
    });
    expect(mockOrder).toHaveBeenCalledTimes(2);
  });
});
