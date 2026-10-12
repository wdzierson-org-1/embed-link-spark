import { act, render, screen } from '@testing-library/react';
import { GIS_SRC, APPLE_JS_SRC } from '@/integrations/auth/providers';
import { resetScriptCacheForTests, useProviderScripts } from './useProviderScripts';

const Probe = () => {
  const s = useProviderScripts();
  return <span data-testid="s">{`${s.google}/${s.apple}`}</span>;
};
const tag = (src: string) => document.querySelector<HTMLScriptElement>(`script[src="${src}"]`)!;

describe('useProviderScripts', () => {
  beforeEach(() => {
    resetScriptCacheForTests();
    document.head.querySelectorAll('script').forEach((el) => el.remove());
  });

  it('injects each script once and reports load and failure separately', async () => {
    render(<Probe />);
    render(<Probe />);
    expect(document.querySelectorAll(`script[src="${GIS_SRC}"]`)).toHaveLength(1);
    expect(screen.getAllByTestId('s')[0]).toHaveTextContent('loading/loading');
    await act(async () => { tag(GIS_SRC).dispatchEvent(new Event('load')); });
    await act(async () => { tag(APPLE_JS_SRC).dispatchEvent(new Event('error')); });
    expect(screen.getAllByTestId('s')[0]).toHaveTextContent('ready/failed');
  });

  it('re-fetches a blocked script on the next mount', async () => {
    const first = render(<Probe />);
    const blocked = tag(APPLE_JS_SRC);
    await act(async () => { blocked.dispatchEvent(new Event('error')); });
    expect(screen.getByTestId('s')).toHaveTextContent('loading/failed');
    first.unmount();
    render(<Probe />);
    const retried = document.querySelectorAll(`script[src="${APPLE_JS_SRC}"]`);
    expect(retried).toHaveLength(1);
    expect(retried[0]).not.toBe(blocked);
    expect(screen.getByTestId('s')).toHaveTextContent('loading/loading');
    await act(async () => { retried[0].dispatchEvent(new Event('load')); });
    expect(screen.getByTestId('s')).toHaveTextContent('loading/ready');
  });
});
