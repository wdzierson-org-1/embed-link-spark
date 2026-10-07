
import { useState } from 'react';
import { ArrowRight } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { AuthShell, AuthTextAction, FieldError } from '@/components/auth/AuthShell';
import { Spinner } from '@/components/machine/Machine';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useToast } from '@/hooks/use-toast';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useEffect } from 'react';
import { usePhoneNumber } from '@/hooks/usePhoneNumber';
import { supabase } from '@/integrations/supabase/client';

// DESIGN-v2 forms: Montreal labels over square white fields (ink edge and spot ring on focus,
// from the shared Input), one ink button, quiet machine-voice text actions
const field = 'h-11 text-[15px] md:text-[15px]';

/** The one ink button: its label, or the machine at work with the spinner */
const SubmitButton = ({ busy, busyLabel, children, disabled }: { busy: boolean; busyLabel: string; children: React.ReactNode; disabled?: boolean }) => (
  <Button type="submit" disabled={busy || disabled} className="h-11 w-full justify-between px-4 text-[15px] font-medium">
    {busy ? (
      <span className="flex items-baseline gap-[0.5ch] font-pixel text-pixel">
        <Spinner />
        {busyLabel}
      </span>
    ) : (
      <>
        <span>{children}</span>
        <ArrowRight className="h-4 w-4" />
      </>
    )}
  </Button>
);

// The person's line and the machine's prompt, per view
const COPY = {
  signin: { address: 'stash://sign-in', title: 'Welcome back.', prompt: 'knock knock. who’s there?' },
  signup: { address: 'stash://sign-up', title: 'Start your stash.', prompt: 'new here? pull up a chair.' },
  reset: { address: 'stash://reset', title: 'Forgot your password?', prompt: 'happens to the best of us.' },
  sent: { address: 'stash://reset', title: 'Check your email.', prompt: 'a link is on its way to you.' },
} as const;

const Auth = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [username, setUsername] = useState('');
  const [phoneNumber, setPhoneNumber] = useState('');
  const [loading, setLoading] = useState(false);
  const [usernameError, setUsernameError] = useState('');
  const [phoneError, setPhoneError] = useState('');
  const [searchParams] = useSearchParams();

  // Get URL parameters for return flow. `mode=reset` (extension + iOS deep
  // link) opens the forgot-password form directly.
  const mode = searchParams.get('mode') || 'signin';
  const returnTo = searchParams.get('returnTo');
  const commentItem = searchParams.get('commentItem');
  const [view, setView] = useState<'tabs' | 'reset'>(mode === 'reset' ? 'reset' : 'tabs');
  const [tab, setTab] = useState<'signin' | 'signup'>(mode === 'signup' ? 'signup' : 'signin');
  const [resetSent, setResetSent] = useState(false);
  const [resetLoading, setResetLoading] = useState(false);

  const { signIn, signUp, user } = useAuth();
  const { registerPhoneNumber } = usePhoneNumber();
  const { toast } = useToast();
  const navigate = useNavigate();

  // Redirect if already authenticated — but only for real accounts. A
  // lingering try-stash anonymous session must stay on the form (Index
  // bounces anonymous users to "/", so redirecting here would loop
  // /auth → /home → / and lock the visitor out of signing in); signing in
  // simply replaces the anonymous session.
  const isRealUser = !!user && !(user as { is_anonymous?: boolean }).is_anonymous;
  useEffect(() => {
    if (isRealUser) {
      if (returnTo && commentItem) {
        // Redirect back to the original page with comment panel open
        navigate(`${returnTo}?openComment=${commentItem}`);
      } else if (returnTo) {
        navigate(returnTo);
      } else {
        navigate('/home');
      }
    }
  }, [isRealUser, navigate, returnTo, commentItem]);

  const handleSignIn = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    
    const { error } = await signIn(email, password);
    
    if (error) {
      toast({
        title: "Sign in failed",
        description: error.message,
        variant: "destructive",
      });
    } else {
      toast({
        title: "Welcome back!",
        description: "You've been signed in successfully.",
      });
      
      if (returnTo && commentItem) {
        navigate(`${returnTo}?openComment=${commentItem}`);
      } else if (returnTo) {
        navigate(returnTo);
      } else {
        navigate('/home');
      }
    }
    
    setLoading(false);
  };

  const checkUsernameUniqueness = async (username: string) => {
    if (!username || username.length < 3) return;
    
    const { data, error } = await supabase
      .from('user_profiles')
      .select('username')
      .eq('username', username.toLowerCase())
      .single();
    
    if (error && error.code !== 'PGRST116') {
      // PGRST116 means no rows returned, which is what we want
      console.error('Error checking username:', error);
      return;
    }
    
    if (data) {
      setUsernameError('that username is taken. try another.');
    } else {
      setUsernameError('');
    }
  };

  const checkPhoneUniqueness = async (phone: string) => {
    if (!phone || phone.trim().length === 0) {
      setPhoneError('');
      return;
    }
    
    const cleanPhone = phone.replace(/\D/g, '');
    if (cleanPhone.length === 0) return;
    
    const { data, error } = await supabase
      .from('user_phone_numbers')
      .select('phone_number')
      .eq('phone_number', cleanPhone)
      .single();
    
    if (error && error.code !== 'PGRST116') {
      console.error('Error checking phone:', error);
      return;
    }
    
    if (data) {
      setPhoneError('that number is already on an account. use another.');
    } else {
      setPhoneError('');
    }
  };

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    
    // Reset errors
    setUsernameError('');
    setPhoneError('');
    
    // Validate uniqueness before proceeding
    await checkUsernameUniqueness(username);
    if (phoneNumber.trim()) {
      await checkPhoneUniqueness(phoneNumber);
    }
    
    // Check if there are validation errors
    if (usernameError || phoneError) {
      return;
    }
    
    setLoading(true);
    
    const { error } = await signUp(email, password, username);
    
    if (error) {
      toast({
        title: "Sign up failed",
        description: error.message,
        variant: "destructive",
      });
    } else {
      // If phone number was provided, register it
      if (phoneNumber.trim()) {
        await registerPhoneNumber(phoneNumber);
      }
      
      toast({
        title: "Account created!",
        description: "You've been signed up successfully.",
      });
      
      if (returnTo && commentItem) {
        navigate(`${returnTo}?openComment=${commentItem}`);
      } else if (returnTo) {
        navigate(returnTo);
      } else {
        navigate('/home');
      }
    }
    
    setLoading(false);
  };

  const handleResetRequest = async (e: React.FormEvent) => {
    e.preventDefault();
    setResetLoading(true);
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/reset-password`,
    });
    setResetLoading(false);
    if (error) {
      // GoTrue throttles reset mail per address and per project; say so
      // plainly instead of surfacing "For security purposes…".
      const throttled =
        error.status === 429 || /rate limit|security purposes|too many/i.test(error.message);
      toast({
        title: throttled ? 'Wait a moment before trying again' : "Couldn't send the reset link",
        description: throttled
          ? 'Reset links are limited to a few per hour. Check your inbox for one we already sent.'
          : error.message,
        variant: 'destructive',
      });
      return;
    }
    // Same confirmation whether or not the address exists — no account enumeration.
    setResetSent(true);
  };

  const showReset = () => {
    setResetSent(false);
    setView('reset');
  };
  const showTabs = () => setView('tabs');

  const copy = view === 'reset' ? (resetSent ? COPY.sent : COPY.reset) : COPY[tab];

  return (
    <AuthShell address={copy.address} title={copy.title} prompt={copy.prompt}>
      {view === 'reset' ? (
        resetSent ? (
          <div className="space-y-5">
            <p className="text-[15px] leading-[1.55] text-ink">
              If an account exists for <span className="font-code text-[14px]">{email}</span>, a reset link is
              on its way. It expires in an hour.
            </p>
            <AuthTextAction onClick={showTabs}>back to sign in</AuthTextAction>
          </div>
        ) : (
          <form onSubmit={handleResetRequest} className="space-y-5">
            <p className="text-[15px] leading-[1.55] text-muted-foreground">
              Enter your email and we'll send a link to choose a new password.
            </p>
            <div className="space-y-2">
              <Label htmlFor="reset-email">Email</Label>
              <Input
                id="reset-email"
                type="email"
                placeholder="you@example.com"
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoFocus
                className={field}
              />
            </div>
            <SubmitButton busy={resetLoading} busyLabel="sending…">
              Send reset link
            </SubmitButton>
            <AuthTextAction onClick={showTabs}>back to sign in</AuthTextAction>
          </form>
        )
      ) : (
        <Tabs value={tab} onValueChange={(value) => setTab(value === 'signup' ? 'signup' : 'signin')} className="w-full">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="signin">Sign in</TabsTrigger>
            <TabsTrigger value="signup">Sign up</TabsTrigger>
          </TabsList>

          <TabsContent value="signin" className="mt-6">
            <form onSubmit={handleSignIn} className="space-y-5">
              <div className="space-y-2">
                <Label htmlFor="signin-email">Email</Label>
                <Input
                  id="signin-email"
                  type="email"
                  placeholder="you@example.com"
                  autoComplete="username"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  className={field}
                />
              </div>
              <div className="space-y-2">
                <div className="flex items-baseline justify-between gap-3">
                  <Label htmlFor="signin-password">Password</Label>
                  <AuthTextAction onClick={showReset}>forgot password?</AuthTextAction>
                </div>
                <Input
                  id="signin-password"
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  className={field}
                />
              </div>
              <SubmitButton busy={loading} busyLabel="signing in…">
                Sign in
              </SubmitButton>
            </form>
          </TabsContent>

          <TabsContent value="signup" className="mt-6">
            <form onSubmit={handleSignUp} className="space-y-5">
              <div className="space-y-2">
                <Label htmlFor="signup-email">Email</Label>
                <Input
                  id="signup-email"
                  type="email"
                  placeholder="you@example.com"
                  autoComplete="username"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  className={field}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="signup-password">Password</Label>
                <Input
                  id="signup-password"
                  type="password"
                  placeholder="At least 8 characters"
                  autoComplete="new-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  className={field}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="signup-username">Username</Label>
                <div className="relative">
                  <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 font-code text-[14px] text-muted-foreground">
                    @
                  </span>
                  <Input
                    id="signup-username"
                    type="text"
                    placeholder="username"
                    autoComplete="off"
                    value={username}
                    onChange={(e) => {
                      const cleanUsername = e.target.value.toLowerCase().replace(/[^a-z0-9]/g, '');
                      setUsername(cleanUsername);
                      if (cleanUsername.length >= 3) {
                        checkUsernameUniqueness(cleanUsername);
                      } else {
                        setUsernameError('');
                      }
                    }}
                    required
                    minLength={3}
                    maxLength={20}
                    aria-invalid={Boolean(usernameError)}
                    aria-describedby={usernameError ? 'signup-username-error' : undefined}
                    className={`${field} pl-7 font-code md:text-[14px] text-[14px] ${usernameError ? 'v2:border-error' : ''}`}
                  />
                </div>
                {usernameError ? (
                  <FieldError id="signup-username-error">{usernameError}</FieldError>
                ) : (
                  // Your handle is also an address: say it in the code voice
                  <p className="text-[13px] leading-snug text-muted-foreground">
                    Your public feed:{' '}
                    <span className="font-code text-[12.5px] text-ink">gostash.it/feed/{username || 'you'}</span>
                  </p>
                )}
              </div>
              <div className="space-y-2">
                <Label htmlFor="signup-phone">
                  Phone <span className="font-normal text-muted-foreground">(optional)</span>
                </Label>
                <Input
                  id="signup-phone"
                  type="tel"
                  placeholder="+1 555 010 0100"
                  autoComplete="tel"
                  value={phoneNumber}
                  onChange={(e) => {
                    setPhoneNumber(e.target.value);
                    if (e.target.value.trim()) {
                      checkPhoneUniqueness(e.target.value);
                    } else {
                      setPhoneError('');
                    }
                  }}
                  aria-invalid={Boolean(phoneError)}
                  aria-describedby={phoneError ? 'signup-phone-error' : undefined}
                  className={`${field} ${phoneError ? 'v2:border-error' : ''}`}
                />
                {phoneError ? (
                  <FieldError id="signup-phone-error">{phoneError}</FieldError>
                ) : (
                  <p className="text-[13px] leading-snug text-muted-foreground">
                    Add your phone number to use WhatsApp for sending notes, voice messages, and asking questions
                    about your content.
                  </p>
                )}
              </div>
              <SubmitButton busy={loading} busyLabel="creating your stash…" disabled={!!usernameError || !!phoneError}>
                Create account
              </SubmitButton>
            </form>
          </TabsContent>
        </Tabs>
      )}
    </AuthShell>
  );
};

export default Auth;
