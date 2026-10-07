import { HOLD_MS, LOADING_LINES, OUT_MS, cycleFrame, decryptMs, settledFrame, takeLoadingLine } from './decryptCycle';

const text = (cells: { ch: string }[]) => cells.map((cell) => cell.ch).join('');
const span = (line: string) => decryptMs(Array.from(line).length) + HOLD_MS + OUT_MS;

describe('cycleFrame', () => {
  it('opens on cipher the same length as the line, with the spot head on its first cell', () => {
    const { index, cells } = cycleFrame(LOADING_LINES, 0, 0);
    expect(index).toBe(0);
    expect(cells).toHaveLength(Array.from(LOADING_LINES[0]).length);
    expect(cells.filter((cell) => cell.ch !== ' ').every((cell) => !cell.settled)).toBe(true);
    expect(cells.findIndex((cell) => cell.head)).toBe(0);
    expect(cells.filter((cell) => cell.head)).toHaveLength(1);
  });

  it('reads exactly as the line while it holds, with no head', () => {
    const line = LOADING_LINES[0];
    const { cells } = cycleFrame(LOADING_LINES, 0, decryptMs(Array.from(line).length) + HOLD_MS / 2);
    expect(text(cells)).toBe(line);
    expect(cells.every((cell) => cell.settled && !cell.head)).toBe(true);
  });

  it('moves to the next line after a full span, and wraps past the last', () => {
    expect(cycleFrame(LOADING_LINES, 0, span(LOADING_LINES[0]) + 1).index).toBe(1);
    const last = LOADING_LINES.length - 1;
    expect(cycleFrame(LOADING_LINES, last, span(LOADING_LINES[last]) + 1).index).toBe(0);
  });

  it('keeps an ellipsis or curly quote as one cell', () => {
    const line = 'you’re my favorite… shhh';
    const lines = [line];
    const { cells } = cycleFrame(lines, 0, decryptMs(Array.from(line).length) + 10);
    expect(cells).toHaveLength(Array.from(line).length);
    expect(text(cells)).toBe(line);
  });

  it('is the same frame for the same moment', () => {
    expect(cycleFrame(LOADING_LINES, 3, 412)).toEqual(cycleFrame(LOADING_LINES, 3, 412));
  });
});

describe('settledFrame', () => {
  it('is the plain line', () => {
    expect(text(settledFrame(LOADING_LINES, 4).cells)).toBe(LOADING_LINES[4]);
  });
});

describe('takeLoadingLine', () => {
  // Node 25 ships its own (file-less, method-less) localStorage global, which wins over jsdom's
  beforeEach(() => {
    const store = new Map<string, string>();
    vi.stubGlobal('localStorage', {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => void store.set(key, value),
    });
  });
  afterEach(() => vi.unstubAllGlobals());

  it('opens on the first line, then one further each load, wrapping', () => {
    expect(takeLoadingLine(3)).toBe(0);
    expect(takeLoadingLine(3)).toBe(1);
    expect(takeLoadingLine(3)).toBe(2);
    expect(takeLoadingLine(3)).toBe(0);
  });

  it('falls back to the first line when storage holds nonsense', () => {
    localStorage.setItem('stash_loading_line', 'banana');
    expect(takeLoadingLine(3)).toBe(0);
  });
});
