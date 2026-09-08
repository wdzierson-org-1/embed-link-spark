import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import StashWordmark from '@/components/StashWordmark';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useToast } from '@/hooks/use-toast';

// Landing page for the password-recovery email link. supabase-js turns the
// `#access_token…&type=recovery` hash into a session on load; once that session
// exists the user sets a new password with updateUser and is signed in.
//
// Visual tokens mirror Auth.tsx (DESIGN.md quiet inputs, violet-600 CTA).
const quietInput =
  'h-11 rounded-xl border-black/[0.07] bg-white px-3.5 text-[15px] text-[#22262f] placeholder:text-[#959ba6] focus-visible:ring-2 focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0';
const primaryCta =
  'h-11 w-full rounded-xl bg-[#6d5bd0] text-[15px] font-medium text-white hover:bg-[#5f4ec2] focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0';
const textLink =
  'rounded text-sm text-[#646b76] underline-offset-4 hover:text-[#22262f] hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#b6a8ef]';

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

  return (
    <div className="relative min-h-screen overflow-hidden bg-[#f7f7f9] font-montreal">
      <div className="animated-gradient pointer-events-none absolute inset-0 opacity-30" />
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-transparent via-[#f7f7f9]/60 to-[#f7f7f9]" />

      <div className="relative z-10 flex min-h-screen items-center justify-center p-4">
        <div className="w-full max-w-[400px] rounded-[20px] border border-black/[0.07] bg-white px-7 py-8 shadow-[0_2px_6px_rgba(20,22,30,0.05),0_24px_70px_rgba(30,33,44,0.16)] sm:px-8">
          <div className="flex justify-center">
            <StashWordmark className="h-6 text-[#22262f]" />
          </div>

          {status === 'checking' && (
            <p className="mt-4 text-center text-sm text-[#646b76]">Checking your reset link…</p>
          )}

          {status === 'expired' && (
            <div className="mt-4 space-y-4 text-center">
              <p className="text-[15px] font-medium text-[#22262f]">This reset link has expired</p>
              <p className="text-sm text-[#646b76]">
                Links work once and only for an hour. Ask for a fresh one and try again.
              </p>
              <Link to="/auth?mode=reset" className={textLink}>
                Request a new link
              </Link>
            </div>
          )}

          {(status === 'ready' || status === 'saving') && (
            <>
              <p className="mt-4 text-center text-sm text-[#646b76]">Choose a new password.</p>
              <form onSubmit={handleSubmit} className="mt-6 space-y-4">
                <div className="space-y-2.5">
                  <Input
                    type="password"
                    placeholder="New password"
                    autoComplete="new-password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    autoFocus
                    className={quietInput}
                  />
                  <Input
                    type="password"
                    placeholder="Confirm new password"
                    autoComplete="new-password"
                    value={confirm}
                    onChange={(e) => setConfirm(e.target.value)}
                    required
                    className={quietInput}
                  />
                </div>
                {formError && <p className="text-xs text-[#c93a3a]">{formError}</p>}
                <Button type="submit" className={primaryCta} disabled={status === 'saving'}>
                  {status === 'saving' ? 'Updating…' : 'Update password'}
                </Button>
              </form>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default ResetPassword;
