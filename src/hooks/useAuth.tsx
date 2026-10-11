
import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { AuthError, User, Session } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';

export type HandleState = { username: string; confirmed: boolean };
export type IdTokenArgs = { provider: 'google' | 'apple'; token: string; nonce: string };

interface AuthContextType {
  user: User | null;
  session: Session | null;
  signUp: (email: string, password: string, username: string) => Promise<{ error: any }>;
  signIn: (email: string, password: string) => Promise<{ error: any }>;
  /** Google / Apple: the provider's identity token plus the RAW nonce (its hash went to the provider) */
  signInWithIdToken: (args: IdTokenArgs) => Promise<{ error: AuthError | null }>;
  signOut: () => Promise<void>;
  loading: boolean;
  /** The person's @handle and whether they confirmed it; null while signed out, anonymous, or unknown */
  handle: HandleState | null;
  /** Re-read the handle row (the confirm step calls this after writing) */
  refreshHandle: () => Promise<void>;
}

const isRealUser = (u: User | null) => !!u && !(u as { is_anonymous?: boolean }).is_anonymous;
const HANDLE_RETRY_MS = 500;

async function fetchHandle(userId: string): Promise<HandleState | null> {
  const { data, error } = await supabase
    .from('user_profiles')
    .select('username, handle_confirmed')
    .eq('id', userId)
    .maybeSingle();
  if (error) {
    console.warn('[auth] handle lookup failed:', error.message);
    return null;
  }
  return data ? { username: data.username, confirmed: data.handle_confirmed } : null;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [handle, setHandle] = useState<HandleState | null>(null);

  // Key the handle on the person, not on the `user` object: supabase-js re-emits SIGNED_IN with a
  // freshly parsed session on every tab refocus (and again on token refresh), so the object changes
  // while the person does not. Null while signed out or anonymous.
  const userId = isRealUser(user) ? user!.id : null;
  const liveUserId = useRef<string | null>(null);
  useEffect(() => {
    liveUserId.current = userId;
  }, [userId]);

  const refreshHandle = useCallback(async () => {
    if (!userId) {
      setHandle(null);
      return;
    }
    let next = await fetchHandle(userId);
    if (!next) {
      // The row is written by the sign-up trigger in the same transaction as the auth user, but a
      // replica or a slow round can make it miss once. Try again, then fail open: nobody gets stuck
      // on the way in because of a lookup; the step simply shows next time.
      await new Promise((resolve) => setTimeout(resolve, HANDLE_RETRY_MS));
      next = await fetchHandle(userId);
    }
    // Signed out, or switched account, while we were looking: drop the answer
    if (liveUserId.current !== userId) return;
    setHandle(next ?? { username: '', confirmed: true });
  }, [userId]);

  useEffect(() => {
    setHandle(null);
    void refreshHandle();
  }, [refreshHandle]);

  const signInWithIdToken = async ({ provider, token, nonce }: IdTokenArgs) => {
    const { error } = await supabase.auth.signInWithIdToken({ provider, token, nonce });
    return { error };
  };

  useEffect(() => {
    // Set up auth state listener
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        setSession(session);
        setUser(session?.user ?? null);
        setLoading(false);
      }
    );

    // Check for existing session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setUser(session?.user ?? null);
      setLoading(false);
    });

    return () => subscription.unsubscribe();
  }, []);

  const signUp = async (email: string, password: string, username: string) => {
    // Into the app, not "/": that's the static marketing site now, which can't finish a sign-in
    // from a confirmation link (if email confirmation is ever switched on)
    const redirectUrl = `${window.location.origin}/home`;
    
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: redirectUrl,
        data: {
          username: username,
          display_name: username
        }
      }
    });
    
    // Trial creation happens in SubscriptionProvider.checkSubscription, which
    // self-heals any account with no subscription — a single path avoids the
    // signup/Stripe race that used to block the first save.
    return { error };
  };

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password
    });

    return { error };
  };

  const signOut = async () => {
    // Local scope: sign out this device only. The default 'global' scope
    // deletes every session for the account, leaving other devices with a
    // valid-looking JWT whose session row is gone — all authed edge calls
    // fail while the UI still shows the user as signed in.
    await supabase.auth.signOut({ scope: 'local' });
  };

  return (
    <AuthContext.Provider value={{
      user,
      session,
      signUp,
      signIn,
      signInWithIdToken,
      signOut,
      loading,
      handle,
      refreshHandle
    }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
