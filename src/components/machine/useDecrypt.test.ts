import { renderHook, waitFor } from '@testing-library/react';
import { useDecrypt } from './useDecrypt';

describe('useDecrypt', () => {
  let frame = 0;

  beforeEach(() => {
    frame = 0;
    // Frames 50 ms apart, delivered quickly, so a whole decrypt runs in the test
    vi.stubGlobal('requestAnimationFrame', (cb: FrameRequestCallback) => setTimeout(() => cb((frame += 50)), 0) as unknown as number);
    vi.stubGlobal('cancelAnimationFrame', (id: number) => clearTimeout(id));
    vi.spyOn(performance, 'now').mockReturnValue(0);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('settles on the exact title, emoji included', async () => {
    const title = 'Ramen 🍜 counters worth the line';
    const { result } = renderHook(() => useDecrypt(title, true));
    await waitFor(() => expect(result.current.scrambling).toBe(false), { timeout: 3000 });
    expect(result.current.display).toBe(title);
  });

  it('shows static text as it is when nothing is arriving', () => {
    const { result } = renderHook(() => useDecrypt('A title already on screen', false));
    expect(result.current).toEqual({ display: 'A title already on screen', scrambling: false });
  });
});
