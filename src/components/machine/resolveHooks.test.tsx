import React, { useLayoutEffect, useRef } from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { usePixelImage } from './usePixelImage';
import { useBoil } from './useBoil';

// jsdom has no 2D canvas: give the painter a context that accepts every call
const fakeContext = new Proxy({} as Record<string, unknown>, {
  get: (target, key) => (key in target ? target[key as string] : () => undefined),
  set: (target, key, value) => {
    target[key as string] = value;
    return true;
  },
});

// A matchMedia whose reduced-motion answer can change mid-session, firing `change` like a browser
let reduce = false;
const mediaListeners = new Set<() => void>();
const setReduceMotion = (value: boolean) => {
  reduce = value;
  act(() => mediaListeners.forEach((notify) => notify()));
};

beforeEach(() => {
  reduce = false;
  mediaListeners.clear();
  vi.useFakeTimers();
  vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => fakeContext as never);
  vi.stubGlobal('matchMedia', (query: string) => ({
    get matches() {
      return query.includes('reduce') ? reduce : false;
    },
    media: query,
    addEventListener: (_type: string, notify: () => void) => mediaListeners.add(notify),
    removeEventListener: (_type: string, notify: () => void) => mediaListeners.delete(notify),
  }));
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

const Picture = ({ reading, arriving }: { reading: boolean; arriving: boolean }) => {
  const frameRef = useRef<HTMLDivElement>(null);
  const imgRef = useRef<HTMLImageElement>(null);
  const pixel = usePixelImage({ frameRef, imgRef, reading, arriving });
  return (
    <div ref={frameRef} style={{ position: 'relative' }}>
      <img ref={imgRef} alt="cover" style={pixel.active ? { opacity: 0 } : undefined} onLoad={pixel.onLoad} />
      {pixel.active && <canvas ref={pixel.canvasRef} data-testid="resolve" />}
    </div>
  );
};

const beats = (count: number) =>
  act(() => {
    vi.advanceTimersByTime(110 * count);
  });

describe('usePixelImage', () => {
  it('resolves an arriving picture and hands back the real <img>', () => {
    render(<Picture reading={false} arriving />);
    fireEvent.load(screen.getByAltText('cover'));
    expect(screen.getByTestId('resolve')).toBeInTheDocument();
    beats(12);
    expect(screen.queryByTestId('resolve')).not.toBeInTheDocument();
    expect(screen.getByAltText('cover').style.opacity).toBe('');
  });

  it('holds while Stash reads, then sharpens when it stops', () => {
    const { rerender } = render(<Picture reading arriving={false} />);
    fireEvent.load(screen.getByAltText('cover'));
    beats(40);
    expect(screen.getByTestId('resolve')).toBeInTheDocument();
    rerender(<Picture reading={false} arriving={false} />);
    beats(8);
    expect(screen.queryByTestId('resolve')).not.toBeInTheDocument();
  });

  it('shows the picture sharp at once when reduced motion is switched on mid-read', () => {
    render(<Picture reading arriving={false} />);
    fireEvent.load(screen.getByAltText('cover'));
    expect(screen.getByTestId('resolve')).toBeInTheDocument();
    setReduceMotion(true);
    expect(screen.queryByTestId('resolve')).not.toBeInTheDocument();
    expect(screen.getByAltText('cover').style.opacity).toBe('');
  });

  it('never starts when reduced motion was switched on before the picture loaded', () => {
    render(<Picture reading={false} arriving />);
    setReduceMotion(true);
    fireEvent.load(screen.getByAltText('cover'));
    expect(screen.queryByTestId('resolve')).not.toBeInTheDocument();
  });

  it('lets go of its observer when the first paint fails', () => {
    const disconnect = vi.fn();
    const observe = vi.fn();
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        observe = observe;
        disconnect = disconnect;
      },
    );
    // A context that exists but whose first paint throws (after the observer is set up)
    const throwingContext = new Proxy({} as Record<string, unknown>, {
      get: (target, key) =>
        key === 'clearRect'
          ? () => {
              throw new Error('paint failed');
            }
          : key in target
            ? target[key as string]
            : () => undefined,
      set: (target, key, value) => {
        target[key as string] = value;
        return true;
      },
    });
    vi.mocked(HTMLCanvasElement.prototype.getContext).mockImplementation(() => throwingContext as never);
    render(<Picture reading={false} arriving />);
    fireEvent.load(screen.getByAltText('cover'));
    expect(screen.queryByTestId('resolve')).not.toBeInTheDocument();
    expect(observe.mock.calls.length).toBe(disconnect.mock.calls.length);
  });
});

// Records what each committed render showed (a render React discards is never painted)
const Boil = ({ reading, seen }: { reading: boolean; seen: number[] }) => {
  const { amount } = useBoil(reading);
  useLayoutEffect(() => {
    seen.push(amount);
  });
  return <span data-testid="amount">{amount}</span>;
};

describe('useBoil', () => {
  it('settles over three beats when reading ends, never flashing sharp first', () => {
    const seen: number[] = [];
    const { rerender } = render(<Boil reading seen={seen} />);
    seen.length = 0;
    rerender(<Boil reading={false} seen={seen} />);
    // The renders for "reading just ended" all show it still unsettled
    expect(seen.every((amount) => amount > 0)).toBe(true);
    beats(4);
    expect(screen.getByTestId('amount').textContent).toBe('0');
  });

  it('stills at once when reduced motion is switched on mid-settle', () => {
    const { rerender } = render(<Boil reading seen={[]} />);
    rerender(<Boil reading={false} seen={[]} />);
    setReduceMotion(true);
    expect(screen.getByTestId('amount').textContent).toBe('0');
  });
});
