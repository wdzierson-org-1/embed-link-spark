// src/components/auth/HandleStep.tsx
import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { FieldError } from '@/components/auth/AuthShell';
import { SubmitButton, field } from '@/components/auth/AuthControls';
import { USERNAME_RE, isFallbackDisplayName, isUsernameTaken, sanitizeUsername } from '@/components/auth/usernameAvailability';

const TAKEN = 'that username is taken. try another.';
const FORMAT = '3–20 letters and numbers.';

type HandleStepProps = {
  userId: string;
  /** The handle the server generated: this person's current user_profiles.username, possibly a guest shape */
  serverUsername: string;
  /** What the field starts with: the parent's suggestion (it may be serverUsername), or '' when nothing usable exists */
  initialUsername: string;
  /** The sign-in email: a display name that is only its local part is still the server's fallback (spec §4.4) */
  email?: string | null;
  onClaimed: () => void;
};

/**
 * The one-time confirm for a server-generated handle (spec §4.3): one ink Continue. Writes
 * username + handle_confirmed in one update; the DB lock trigger makes this the only moment a
 * handle can ever change. The display name follows the claim while it is still a server
 * fallback (spec §4.4); a name the person chose is left alone.
 */
export const HandleStep = ({ userId, serverUsername, initialUsername, email, onClaimed }: HandleStepProps) => {
  const [username, setUsername] = useState(initialUsername);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const typed = useRef(false);
  const { toast } = useToast();

  // Live availability, debounced. The server's own handle is already this person's, so it is never
  // probed; an answer that lands after the field has moved on is dropped. A prefill the person has
  // not touched that turns out to be taken (the server deduped it: johnsmith → johnsmith2) gives way
  // to the server's handle, silently, when the forms would accept that handle (never a guest-… one);
  // a handle the person typed keeps the error. Until they type, the field can only hold the prefill:
  // typing and this fallback are the only writes, and the server's handle is never probed.
  useEffect(() => {
    if (username.length < 3 || username === serverUsername) return;
    let cancelled = false;
    const t = setTimeout(async () => {
      const taken = await isUsernameTaken(username, userId);
      if (cancelled || !taken) return;
      if (!typed.current && USERNAME_RE.test(serverUsername)) setUsername(serverUsername);
      else setError(TAKEN);
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [username, serverUsername, userId]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!USERNAME_RE.test(username)) {
      setError(FORMAT);
      return;
    }
    setBusy(true);
    // The display name follows the claim only while it is still a server fallback; a name the person
    // has is never overwritten. If the lookup fails we cannot tell which it is, so we do not guess:
    // the claim (the point of this step) goes ahead and the name stays as it is.
    const { data: profile, error: readError } = await supabase.from('user_profiles').select('display_name').eq('id', userId).maybeSingle();
    if (readError) console.warn('[handle] display name lookup failed:', readError.message);
    const nameFollowsHandle = !readError && isFallbackDisplayName(profile?.display_name, serverUsername, email);
    const { error: dbError } = await supabase
      .from('user_profiles')
      .update({ username, handle_confirmed: true, ...(nameFollowsHandle ? { display_name: username } : {}) })
      .eq('id', userId);
    setBusy(false);
    if (dbError) {
      if (dbError.code === '23505') setError(TAKEN);
      else toast({ title: "That didn't take.", description: dbError.message, variant: 'destructive' });
      return;
    }
    onClaimed();
  };

  return (
    <form onSubmit={submit} className="space-y-5">
      <div className="space-y-2">
        <Label htmlFor="handle-username">Username</Label>
        <div className="relative">
          <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 font-code text-[14px] text-muted-foreground">@</span>
          <Input
            id="handle-username"
            type="text"
            autoComplete="off"
            value={username}
            onChange={(e) => { typed.current = true; setUsername(sanitizeUsername(e.target.value)); setError(''); }}
            readOnly={busy}
            required
            minLength={3}
            maxLength={20}
            autoFocus
            aria-invalid={Boolean(error)}
            aria-describedby={error ? 'handle-username-error' : undefined}
            className={`${field} pl-7 font-code md:text-[14px] text-[14px] ${error ? 'v2:border-error' : ''}`}
          />
        </div>
        {error ? (
          <FieldError id="handle-username-error">{error}</FieldError>
        ) : (
          <p className="text-[13px] leading-snug text-muted-foreground">
            Your public feed: <span className="font-code text-[12.5px] text-ink">gostash.it/feed/{username || 'you'}</span>
          </p>
        )}
      </div>
      <SubmitButton busy={busy} busyLabel="claiming…" disabled={!!error || username.length < 3}>
        Continue
      </SubmitButton>
    </form>
  );
};
