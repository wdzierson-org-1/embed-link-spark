// src/components/auth/ProviderButtons.test.tsx
import { act, render, screen, waitFor } from '@testing-library/react';
import { webcrypto } from 'node:crypto';
import { GOOGLE_WEB_CLIENT_ID, APPLE_SERVICES_ID } from '@/integrations/auth/providers';
import { ProviderButtons, type ProviderIdToken } from './ProviderButtons';

if (!globalThis.crypto?.subtle) vi.stubGlobal('crypto', webcrypto);

const scripts = vi.hoisted(() => ({ google: 'ready', apple: 'ready' }));
vi.mock('./useProviderScripts', () => ({ useProviderScripts: () => scripts }));

type GoogleInit = { client_id: string; nonce: string; callback: (r: { credential: string }) => void };
const google = { init: null as GoogleInit | null, render: vi.fn() };
const apple = { init: null as null | { clientId: string; nonce: string; redirectURI: string; usePopup: boolean }, render: vi.fn() };

beforeEach(() => {
  scripts.google = 'ready';
  scripts.apple = 'ready';
  google.init = null;
  google.render.mockClear();
  apple.init = null;
  apple.render.mockClear();
  window.google = { accounts: { id: { initialize: (cfg: GoogleInit) => { google.init = cfg; }, renderButton: google.render } } };
  window.AppleID = { auth: { init: (cfg: typeof apple.init) => { apple.init = cfg; }, renderButton: apple.render } };
});

const sha256 = async (s: string) =>
  Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))).map((b) => b.toString(16).padStart(2, '0')).join('');

const setup = (onToken = vi.fn(async (_t: ProviderIdToken) => {}), onError = vi.fn()) => {
  render(<ProviderButtons onToken={onToken} onError={onError} />);
  return { onToken, onError };
};

describe('ProviderButtons', () => {
  it('initializes Google with the hashed nonce and delivers the credential with the raw one', async () => {
    const { onToken } = setup();
    await waitFor(() => expect(google.init).not.toBeNull());
    const live = google.init!; // the config this credential belongs to: an attempt re-initializes with a fresh nonce
    expect(google.init!.client_id).toBe(GOOGLE_WEB_CLIENT_ID);
    expect(google.render).toHaveBeenCalledWith(expect.any(HTMLElement), expect.objectContaining({ theme: 'outline', shape: 'rectangular', text: 'continue_with', width: 356 }));
    await act(async () => { google.init!.callback({ credential: 'g.jwt' }); });
    expect(onToken).toHaveBeenCalledTimes(1);
    const t = onToken.mock.calls[0][0];
    expect(t).toMatchObject({ provider: 'google', token: 'g.jwt' });
    expect(live.nonce).toBe(await sha256(t.nonce));
    await waitFor(() => expect(google.init).not.toBe(live));
    expect(google.init!.nonce).not.toBe(live.nonce);
  });

  it('ignores a second credential while one is in flight', async () => {
    let release: () => void = () => {};
    const onToken = vi.fn(() => new Promise<void>((r) => { release = r; }));
    setup(onToken);
    await waitFor(() => expect(google.init).not.toBeNull());
    act(() => { google.init!.callback({ credential: 'one' }); });
    act(() => { google.init!.callback({ credential: 'two' }); });
    expect(onToken).toHaveBeenCalledTimes(1);
    await act(async () => { release(); });
  });

  it('reports a failing onToken through onError and takes the next credential', async () => {
    const onToken = vi.fn().mockRejectedValueOnce(new Error('exchange refused')).mockRejectedValueOnce('plain refusal').mockResolvedValue(undefined);
    const { onError } = setup(onToken);
    await waitFor(() => expect(google.init).not.toBeNull());
    const armed = google.init!;
    await act(async () => { armed.callback({ credential: 'one' }); });
    expect(onError).toHaveBeenLastCalledWith('exchange refused');
    await waitFor(() => expect(google.init).not.toBe(armed)); // a failed attempt re-arms the pair with a fresh nonce
    const rearmed = google.init!;
    await act(async () => { rearmed.callback({ credential: 'two' }); });
    expect(onError).toHaveBeenLastCalledWith('plain refusal'); // a throw that is not an Error is reported by its string form
    await waitFor(() => expect(google.init).not.toBe(rearmed));
    await act(async () => { google.init!.callback({ credential: 'three' }); });
    expect(onToken).toHaveBeenCalledTimes(3);
    expect(onToken.mock.calls[2][0]).toMatchObject({ provider: 'google', token: 'three' });
    expect(onError).toHaveBeenCalledTimes(2);
  });

  it('initializes Apple as a popup against /auth and delivers the token, code and name', async () => {
    const { onToken } = setup();
    await waitFor(() => expect(apple.init).not.toBeNull());
    const live = apple.init!; // the config this token belongs to: an attempt re-initializes with a fresh nonce
    expect(apple.init).toMatchObject({ clientId: APPLE_SERVICES_ID, usePopup: true, redirectURI: `${window.location.origin}/auth` });
    expect(apple.render).toHaveBeenCalled();
    await act(async () => {
      document.dispatchEvent(new CustomEvent('AppleIDSignInOnSuccess', { detail: { authorization: { id_token: 'a.jwt', code: 'c0de' }, user: { name: { firstName: 'Will', lastName: 'D' } } } }));
    });
    const t = onToken.mock.calls[0][0];
    expect(t).toMatchObject({ provider: 'apple', token: 'a.jwt', appleCode: 'c0de', appleName: { firstName: 'Will', lastName: 'D' } });
    expect(live.nonce).toBe(await sha256(t.nonce));
    await waitFor(() => expect(apple.init).not.toBe(live));
    expect(apple.init!.nonce).not.toBe(live.nonce);
  });

  it('is silent when the Apple popup is closed or cancelled, loud on any other failure', async () => {
    const { onError } = setup();
    await waitFor(() => expect(apple.init).not.toBeNull());
    await act(async () => { document.dispatchEvent(new CustomEvent('AppleIDSignInOnFailure', { detail: { error: 'popup_closed_by_user' } })); });
    expect(onError).not.toHaveBeenCalled();
    await act(async () => { document.dispatchEvent(new CustomEvent('AppleIDSignInOnFailure', { detail: { error: 'user_cancelled_authorize' } })); });
    expect(onError).not.toHaveBeenCalled();
    await act(async () => { document.dispatchEvent(new CustomEvent('AppleIDSignInOnFailure', { detail: { error: 'invalid_request' } })); });
    expect(onError).toHaveBeenCalledWith('invalid_request');
  });

  it('collapses a slot whose script failed and keeps the other', async () => {
    scripts.apple = 'failed';
    setup();
    await waitFor(() => expect(google.init).not.toBeNull());
    expect(document.getElementById('appleid-signin')).toBeNull();
    expect(screen.getByTestId('google-slot')).toBeInTheDocument();
  });

  it('shows its children under the buttons', async () => {
    render(<ProviderButtons onToken={vi.fn()} onError={vi.fn()}><p>one account per email.</p></ProviderButtons>);
    await waitFor(() => expect(apple.init).not.toBeNull());
    const footnote = screen.getByText('one account per email.');
    expect(document.getElementById('appleid-signin')!.compareDocumentPosition(footnote) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('renders nothing, children included, when both scripts failed', () => {
    scripts.google = 'failed';
    scripts.apple = 'failed';
    const { container } = render(<ProviderButtons onToken={vi.fn()} onError={vi.fn()}><p>one account per email.</p></ProviderButtons>);
    expect(container).toBeEmptyDOMElement();
    expect(screen.queryByText('one account per email.')).toBeNull();
  });
});
