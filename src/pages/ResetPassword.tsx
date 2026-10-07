import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ArrowRight } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { AuthShell, FieldError } from '@/components/auth/AuthShell';
import { Spinner, StatusLine } from '@/components/machine/Machine';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';

// Landing page for the password-recovery email link. supabase-js turns the
// `#access_token…&type=recovery` hash into a session on load; once that session
// exists the user sets a new password with updateUser and is signed in.
//
// Wears the sign-in shell (AuthShell, DESIGN-v2 §12.14): Montreal labels over square fields,
// one ink button, errors as machine lines.
const field = 'h-11 text-[15px] md:text-[15px]';

const MIN_LENGTH = 8;

type Status = 'checking' | 'ready' | 'saving' | 'expired';

interface ResetPasswordProps {
  /** How long to wait for supabase-js to turn the recovery hash into a session before calling the link dead. */
  expiryGraceMs?: number;
}

// A dead link arrives as `#error=access_denied&error_code=otp_expired&…`; no
// session will ever follow, so there is nothing to wait for.
const readHashError = (): string | null => {
  const hash = window.location.hash.replace(/^#/, '');
  if (!hash) return null;
  const params = new URLSearchParams(hash);
  return params.get('error_description') ?? params.get('error_code');
};

const ResetPassword = ({ expiryGraceMs = 2500 }: ResetPasswordProps) => {
  const [status, setStatus] = useState<Status>('checking');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [formError, setFormError] = useState('');
  const navigate = useNavigate();
  const { toast } = useToast();

  useEffect(() => {
    if (readHashError()) {
      setStatus('expired');
      return;
    }

    let cancelled = false;
    let timer: number | undefined;
    const becomeReady = () => setStatus((current) => (current === 'checking' ? 'ready' : current));

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      if (cancelled) return;
      if (event === 'PASSWORD_RECOVERY' || session) {
        window.clearTimeout(timer);
        becomeReady();
      }
    });

    supabase.auth.getSession().then(({ data }) => {
      if (cancelled) return;
      if (data.session) {
        becomeReady();
        return;
      }
      timer = window.setTimeout(() => {
        if (!cancelled) setStatus((current) => (current === 'checking' ? 'expired' : current));
      }, expiryGraceMs);
    });

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      subscription.unsubscribe();
    };
  }, [expiryGraceMs]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password.length < MIN_LENGTH) {
      setFormError(`Use at least ${MIN_LENGTH} characters.`);
      return;
    }
    if (password !== confirm) {
      setFormError("Those passwords don't match.");
      return;
    }
    setFormError('');
    setStatus('saving');

    const { error } = await supabase.auth.updateUser({ password });
    if (error) {
      setStatus('ready');
      toast({ title: "Couldn't update your password", description: error.message, variant: 'destructive' });
      return;
    }

    toast({ title: 'Password updated', description: "You're signed in with your new password." });
    navigate('/home');
  };

  const copy =
    status === 'checking'
      ? { title: 'Checking your link.', prompt: 'one moment…' }
      : status === 'expired'
        ? { title: 'This reset link has expired.', prompt: 'links work once, and only for an hour.' }
        : { title: 'Choose a new password.', prompt: 'make it a good one.' };

  return (
    <AuthShell address="stash://new-password" title={copy.title} prompt={copy.prompt}>
      {status === 'checking' && <StatusLine tone="busy">checking your reset link…</StatusLine>}

      {status === 'expired' && (
        <div className="space-y-5">
          <p className="text-[15px] leading-[1.55] text-muted-foreground">
            Links work once and only for an hour. Ask for a fresh one and try again.
          </p>
          <Link
            to="/auth?mode=reset"
            className="font-pixel text-pixel text-ink underline underline-offset-[3px] hover:bg-ink hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink"
          >
            Request a new link
          </Link>
        </div>
      )}

      {(status === 'ready' || status === 'saving') && (
        <form onSubmit={handleSubmit} className="space-y-5">
          <div className="space-y-2">
            <Label htmlFor="new-password">New password</Label>
            <Input
              id="new-password"
              type="password"
              placeholder="At least 8 characters"
              autoComplete="new-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoFocus
              className={field}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="confirm-password">Confirm new password</Label>
            <Input
              id="confirm-password"
              type="password"
              placeholder="The same again"
              autoComplete="new-password"
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              required
              className={field}
            />
          </div>
          {formError && <FieldError>{formError}</FieldError>}
          <Button type="submit" disabled={status === 'saving'} className="h-11 w-full justify-between px-4 text-[15px] font-medium">
            {status === 'saving' ? (
              <span className="flex items-baseline gap-[0.5ch] font-pixel text-pixel">
                <Spinner />
                updating…
              </span>
            ) : (
              <>
                <span>Update password</span>
                <ArrowRight className="h-4 w-4" />
              </>
            )}
          </Button>
        </form>
      )}
    </AuthShell>
  );
};

export default ResetPassword;
