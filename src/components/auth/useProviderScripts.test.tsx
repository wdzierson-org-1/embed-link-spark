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

  it('lets a blocked script be retried on the next mount', async () => {
    const first = render(<Probe />);
    await act(async () => { tag(APPLE_JS_SRC).dispatchEvent(new Event('error')); });
    first.unmount();
    document.head.querySelectorAll('script').forEach((el) => el.remove());
    render(<Probe />);
    expect(document.querySelectorAll(`script[src="${APPLE_JS_SRC}"]`)).toHaveLength(1);
  });
});
