// src/components/auth/HandleStep.tsx
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { FieldError } from '@/components/auth/AuthShell';
import { SubmitButton, field } from '@/components/auth/AuthControls';
import { USERNAME_RE, isUsernameTaken, sanitizeUsername } from '@/components/auth/usernameAvailability';

const TAKEN = 'that username is taken. try another.';
const FORMAT = '3–20 letters and numbers.';

type HandleStepProps = {
  userId: string;
  /** The handle the server generated: this person's current user_profiles.username, possibly a guest shape */
  serverUsername: string;
  /** What the field starts with: the parent's suggestion (it may be serverUsername), or '' when nothing usable exists */
  initialUsername: string;
  onClaimed: () => void;
};

/**
 * The one-time confirm for a server-generated handle (spec §4.3): one ink Continue. Writes
 * username + handle_confirmed in one update; the DB lock trigger makes this the only moment a
 * handle can ever change. The display name follows the claim while it is still the server's
 * fallback; a name the person chose is left alone.
 */
export const HandleStep = ({ userId, serverUsername, initialUsername, onClaimed }: HandleStepProps) => {
  const [username, setUsername] = useState(initialUsername);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const { toast } = useToast();

  // Live availability, debounced. The server's own handle is already this person's, so it is never
  // probed; an answer that lands after the field has moved on is dropped.
  useEffect(() => {
    if (username.length < 3 || username === serverUsername) return;
    let cancelled = false;
    const t = setTimeout(async () => {
      const taken = await isUsernameTaken(username, userId);
      if (!cancelled && taken) setError(TAKEN);
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [username, serverUsername, userId]);

  const failed = (message: string) => toast({ title: "That didn't take.", description: message, variant: 'destructive' });

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!USERNAME_RE.test(username)) {
      setError(FORMAT);
      return;
    }
    setBusy(true);
    // The display name follows the claim only while it is still the server's fallback (empty, or the
    // generated handle itself); a name the person has is never overwritten, so an unreadable profile
    // stops here rather than guessing.
    const { data: profile, error: readError } = await supabase.from('user_profiles').select('display_name').eq('id', userId).maybeSingle();
    if (readError) {
      setBusy(false);
      failed(readError.message);
      return;
    }
    const nameFollowsHandle = !profile?.display_name || profile.display_name === serverUsername;
    const { error: dbError } = await supabase
      .from('user_profiles')
      .update({ username, handle_confirmed: true, ...(nameFollowsHandle ? { display_name: username } : {}) })
      .eq('id', userId);
    setBusy(false);
    if (dbError) {
      if (dbError.code === '23505') setError(TAKEN);
      else failed(dbError.message);
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
            onChange={(e) => { setUsername(sanitizeUsername(e.target.value)); setError(''); }}
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
