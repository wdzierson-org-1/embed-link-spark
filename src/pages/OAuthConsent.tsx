// src/pages/OAuthConsent.tsx
//
// Supabase Auth redirects here (site URL + authorization path) with
// ?authorization_id=… when an OAuth client (an MCP agent) asks for access.
// Signed-out visitors bounce through /auth and come back. Approving writes
// our agent_grants row FIRST (the mcp function refuses tokens without one),
// then tells Supabase to issue the code. Spec: docs/superpowers/specs/
// 2026-09-05-mcp-server-design.md → "Web surfaces".
import { useEffect, useState } from 'react';
import { Navigate, useSearchParams } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import StashWordmark from '@/components/StashWordmark';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import {
  consentReturnTo, decideAuthorization, fetchAuthorizationDetails, hostOf, isLoopbackHost, isRedirect,
  type AuthorizationDetails, type OAuthClient,
} from '@/utils/oauthConsent';

const card =
  'w-full max-w-[440px] rounded-[20px] border border-black/[0.07] bg-white px-7 py-8 shadow-[0_2px_6px_rgba(20,22,30,0.05),0_24px_70px_rgba(30,33,44,0.16)] sm:px-8';
const primaryCta =
  'h-11 w-full rounded-xl bg-[#6d5bd0] text-[15px] font-medium text-white hover:bg-[#5f4ec2] focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0';
const secondaryCta =
  'h-11 w-full rounded-xl border border-black/[0.07] bg-white text-[15px] font-medium text-[#22262f] hover:bg-[rgba(20,22,30,0.04)] focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0';

const CAN = ['Search your stash', 'Read saved items in full'];
const CANNOT = ['Add, edit or delete anything', 'Export your stash', 'See your account or billing'];

const Shell = ({ children }: { children: React.ReactNode }) => (
  <div className="relative min-h-screen overflow-hidden bg-[#f7f7f9] font-montreal">
    <div className="relative z-10 flex min-h-screen items-center justify-center p-4">
      <div className={card}>
        <div className="flex justify-center">
          <StashWordmark className="h-6 text-[#22262f]" />
        </div>
        {children}
      </div>
    </div>
  </div>
);

const OAuthConsent = () => {
  const [searchParams] = useSearchParams();
  const authorizationId = searchParams.get('authorization_id');
  const { user, session, loading } = useAuth();
  const [details, setDetails] = useState<AuthorizationDetails | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<'approve' | 'deny' | null>(null);

  const isRealUser = !!user && !(user as { is_anonymous?: boolean }).is_anonymous;
  const accessToken = session?.access_token;

  const ensureGrant = async (client: OAuthClient) => {
    if (!user) throw new Error('Not signed in');
    const { error: upsertError } = await supabase.from('agent_grants').upsert(
      {
        user_id: user.id,
        client_id: client.id,
        client_name: client.name || 'Unnamed agent',
        client_uri: client.uri ?? null,
        scopes: ['read'],
        revoked_at: null,
      },
      { onConflict: 'user_id,client_id' },
    );
    if (upsertError) throw new Error('Could not record this connection. Try again.');
  };

  useEffect(() => {
    if (!authorizationId || !isRealUser || !accessToken) return;
    let cancelled = false;
    (async () => {
      try {
        const res = await fetchAuthorizationDetails(authorizationId, accessToken);
        if (cancelled) return;
        if (isRedirect(res)) {
          // Supabase already holds consent for this client. That response has
          // no client info, so we can't touch agent_grants here — and needn't:
          // revocation deletes the Supabase grant before marking ours, so an
          // auto-approve implies our row is still active.
          window.location.assign(res.redirect_url);
          return;
        }
        setDetails(res);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : 'This connection request is no longer valid.');
      }
    })();
    return () => { cancelled = true; };
  }, [authorizationId, isRealUser, accessToken]);

  const decide = async (action: 'approve' | 'deny') => {
    if (!details || !accessToken) return;
    setBusy(action);
    setError(null);
    try {
      if (action === 'approve') await ensureGrant(details.client);
      const { redirect_url } = await decideAuthorization(details.authorization_id, accessToken, action);
      window.location.assign(redirect_url);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong. Start again from your agent.');
      setBusy(null);
    }
  };

  if (!authorizationId) {
    return (
      <Shell>
        <p className="mt-6 text-center text-[15px] text-[#22262f]">This link is missing its authorization request.</p>
        <p className="mt-2 text-center text-sm text-[#646b76]">Start again from your agent and it will bring you back here.</p>
      </Shell>
    );
  }

  if (loading) {
    return (
      <Shell>
        <div className="mt-8 flex justify-center"><Loader2 className="h-5 w-5 animate-spin text-[#6d5bd0]" /></div>
      </Shell>
    );
  }

  if (!isRealUser) return <Navigate to={consentReturnTo(authorizationId)} replace />;

  if (error && !details) {
    return (
      <Shell>
        <p className="mt-6 text-center text-[15px] text-[#22262f]">{error}</p>
        <p className="mt-2 text-center text-sm text-[#646b76]">Start again from your agent.</p>
      </Shell>
    );
  }

  if (!details) {
    return (
      <Shell>
        <div className="mt-8 flex justify-center"><Loader2 className="h-5 w-5 animate-spin text-[#6d5bd0]" /></div>
      </Shell>
    );
  }

  const clientHost = hostOf(details.client.uri);
  const returnHost = hostOf(details.redirect_uri);
  const loopback = isLoopbackHost(returnHost);

  return (
    <Shell>
      <h1 className="mt-5 text-center text-[20px] leading-tight text-[#22262f]">
        <span className="font-medium">{details.client.name || 'An agent'}</span> wants to connect to your Stash
      </h1>
      {clientHost && <p className="mt-1 text-center text-sm text-[#646b76]">{clientHost}</p>}

      <div className="mt-6 space-y-4 text-[15px]">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-[#646b76]">It can</p>
          <ul className="mt-1.5 space-y-1 text-[#22262f]">
            {CAN.map((line) => <li key={line}>· {line}</li>)}
          </ul>
        </div>
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-[#646b76]">It can't</p>
          <ul className="mt-1.5 space-y-1 text-[#22262f]">
            {CANNOT.map((line) => <li key={line}>· {line}</li>)}
          </ul>
        </div>
      </div>

      <p className="mt-6 text-sm text-[#646b76]">
        Signed in as <span className="text-[#22262f]">{user?.email}</span>.
        {returnHost && <> Returns to <span className="text-[#22262f]">{returnHost}</span>.</>}
      </p>
      {loopback && (
        <p className="mt-2 rounded-xl bg-[#fff7e6] px-3 py-2 text-sm text-[#7a4b00]">
          This connection returns to a program running on your computer. Continue only if you started it from an app you trust.
        </p>
      )}
      {error && <p className="mt-3 text-sm text-[#c93a3a]">{error}</p>}

      <div className="mt-6 space-y-2.5">
        <Button className={primaryCta} onClick={() => decide('approve')} disabled={busy !== null}>
          {busy === 'approve' ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Allow access'}
        </Button>
        <Button variant="outline" className={secondaryCta} onClick={() => decide('deny')} disabled={busy !== null}>
          {busy === 'deny' ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Deny'}
        </Button>
      </div>
      <p className="mt-4 text-center text-xs text-[#959ba6]">You can revoke this any time in Settings → Connected agents.</p>
    </Shell>
  );
};

export default OAuthConsent;
