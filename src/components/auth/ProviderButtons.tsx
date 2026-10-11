// src/components/auth/ProviderButtons.tsx
import { useEffect, useRef, useState } from 'react';
import { APPLE_SERVICES_ID, GOOGLE_WEB_CLIENT_ID, appleRedirectUri } from '@/integrations/auth/providers';
import { makeNonce } from '@/utils/nonce';
import { useProviderScripts } from './useProviderScripts';

/** What a provider handed us: its identity token, the RAW nonce whose hash it signed, and Apple's extras */
export type ProviderIdToken = {
  provider: 'google' | 'apple';
  token: string;
  nonce: string;
  /** Apple's one-shot authorization code, exchanged server-side so deletion can revoke (spec §5.3) */
  appleCode?: string;
  /** Apple sends the name once, on first authorization, and never again (spec §4.4) */
  appleName?: { firstName?: string; lastName?: string };
};

type GoogleCredential = { credential: string };
declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (cfg: { client_id: string; nonce: string; callback: (r: GoogleCredential) => void; use_fedcm_for_prompt?: boolean; auto_select?: boolean }) => void;
          renderButton: (el: HTMLElement, opts: Record<string, string | number>) => void;
        };
      };
    };
    AppleID?: {
      auth: {
        init: (cfg: { clientId: string; scope: string; redirectURI: string; usePopup: boolean; nonce: string }) => void;
        renderButton: () => void;
      };
    };
  }
}

const BUTTON_HEIGHT = 40; // GIS "large" is fixed at 40 px; Apple's is set to match (spec §6.1)
const clampWidth = (w: number) => Math.min(400, Math.max(200, w || 356));

/**
 * The provider pair (DESIGN-v2 §12.14): Google's rendered button, then Apple's, both square,
 * both "Continue with …", at the window body's measured width. Each attempt gets its own nonce.
 */
export const ProviderButtons = ({ onToken, onError }: { onToken: (t: ProviderIdToken) => Promise<void> | void; onError: (message: string) => void }) => {
  const scripts = useProviderScripts();
  const wrapRef = useRef<HTMLDivElement>(null);
  const googleRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const [attempt, setAttempt] = useState(0);
  const inFlight = useRef(false);

  // One credential at a time: a double-click or a second tab can't start a second sign-in
  const deliver = async (t: ProviderIdToken) => {
    if (inFlight.current) return;
    inFlight.current = true;
    try {
      await onToken(t);
    } finally {
      inFlight.current = false;
      setAttempt((a) => a + 1); // fresh nonces for the next try
    }
  };

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const measure = () => setWidth(clampWidth(el.clientWidth));
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    if (scripts.google !== 'ready' || !width || !googleRef.current || !window.google) return;
    let cancelled = false;
    const slot = googleRef.current;
    void makeNonce().then((nonce) => {
      if (cancelled) return;
      window.google!.accounts.id.initialize({
        client_id: GOOGLE_WEB_CLIENT_ID,
        nonce: nonce.hashed,
        callback: (r) => void deliver({ provider: 'google', token: r.credential, nonce: nonce.raw }),
        use_fedcm_for_prompt: true,
        auto_select: false,
      });
      slot.innerHTML = '';
      window.google!.accounts.id.renderButton(slot, {
        type: 'standard', theme: 'outline', size: 'large', text: 'continue_with', shape: 'rectangular', logo_alignment: 'left', width,
      });
    });
    return () => { cancelled = true; };
  }, [scripts.google, width, attempt]);

  useEffect(() => {
    if (scripts.apple !== 'ready' || !width || !window.AppleID) return;
    let cancelled = false;
    let raw = '';
    const onSuccess = (e: Event) => {
      const d = (e as CustomEvent).detail ?? {};
      void deliver({ provider: 'apple', token: d.authorization?.id_token, nonce: raw, appleCode: d.authorization?.code, appleName: d.user?.name });
    };
    const onFailure = (e: Event) => {
      const err = (e as CustomEvent).detail?.error;
      if (err !== 'popup_closed_by_user') onError(String(err ?? 'Apple sign-in failed'));
    };
    void makeNonce().then((nonce) => {
      if (cancelled) return;
      raw = nonce.raw;
      window.AppleID!.auth.init({ clientId: APPLE_SERVICES_ID, scope: 'name email', redirectURI: appleRedirectUri(), usePopup: true, nonce: nonce.hashed });
      const slot = document.getElementById('appleid-signin');
      if (slot) slot.innerHTML = '';
      window.AppleID!.auth.renderButton();
      document.addEventListener('AppleIDSignInOnSuccess', onSuccess);
      document.addEventListener('AppleIDSignInOnFailure', onFailure);
    });
    return () => {
      cancelled = true;
      document.removeEventListener('AppleIDSignInOnSuccess', onSuccess);
      document.removeEventListener('AppleIDSignInOnFailure', onFailure);
    };
  }, [scripts.apple, width, attempt]);

  if (scripts.google === 'failed' && scripts.apple === 'failed') return null;
  return (
    <div ref={wrapRef} className="space-y-3">
      {scripts.google !== 'failed' && <div ref={googleRef} data-testid="google-slot" style={{ minHeight: BUTTON_HEIGHT }} />}
      {scripts.apple !== 'failed' && (
        <div
          id="appleid-signin"
          data-mode="center-align"
          data-type="continue"
          data-color="black"
          data-border="false"
          data-border-radius="0"
          data-width={String(width || 356)}
          data-height={String(BUTTON_HEIGHT)}
          style={{ minHeight: BUTTON_HEIGHT }}
        />
      )}
    </div>
  );
};
