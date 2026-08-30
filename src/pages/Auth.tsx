
import { useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import StashWordmark from '@/components/StashWordmark';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useToast } from '@/hooks/use-toast';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useEffect } from 'react';
import { usePhoneNumber } from '@/hooks/usePhoneNumber';
import { supabase } from '@/integrations/supabase/client';

// Visual tokens (DESIGN.md): quiet inputs — hairline border, radius 12,
// 2px violet-300 focus ring — and a solid violet-600 primary CTA.
const quietInput =
  'h-11 rounded-xl border-black/[0.07] bg-white px-3.5 text-[15px] text-[#22262f] placeholder:text-[#959ba6] focus-visible:ring-2 focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0';
const primaryCta =
  'h-11 w-full rounded-xl bg-[#6d5bd0] text-[15px] font-medium text-white hover:bg-[#5f4ec2] focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0';

const Auth = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [username, setUsername] = useState('');
  const [phoneNumber, setPhoneNumber] = useState('');
  const [loading, setLoading] = useState(false);
  const [usernameError, setUsernameError] = useState('');
  const [phoneError, setPhoneError] = useState('');
  const [searchParams] = useSearchParams();

  // Get URL parameters for return flow
  const mode = searchParams.get('mode') || 'signin';
  const returnTo = searchParams.get('returnTo');
  const commentItem = searchParams.get('commentItem');

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
      setUsernameError('This username is already taken. Please choose another.');
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
      setPhoneError('This phone number is already registered. Please use a different number.');
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

  return (
    <div className="relative min-h-screen overflow-hidden bg-[#f7f7f9] font-montreal">
      {/* Page wash: the app's ambient animated gradient (same class the
          library uses; sanctioned exception in DESIGN.md, reduced-motion
          guarded in index.css), faded down toward the card */}
      <div className="animated-gradient pointer-events-none absolute inset-0 opacity-30" />
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-transparent via-[#f7f7f9]/60 to-[#f7f7f9]" />

      <div className="relative z-10 flex min-h-screen items-center justify-center p-4">
        {/* One centered surface: white card, radius 20, neutral sheet shadow */}
        <div className="w-full max-w-[400px] rounded-[20px] border border-black/[0.07] bg-white px-7 py-8 shadow-[0_2px_6px_rgba(20,22,30,0.05),0_24px_70px_rgba(30,33,44,0.16)] sm:px-8">
          <div className="flex justify-center">
            <StashWordmark className="h-6 text-[#22262f]" />
          </div>
          <p className="mt-4 text-center text-sm text-[#646b76]">
            Sign in or create your account.
          </p>

          <div className="mt-6">
            <Tabs defaultValue={mode} className="w-full">
              <TabsList className="grid h-10 w-full grid-cols-2 rounded-full bg-[rgba(20,22,30,0.05)] p-1 text-[#646b76]">
                <TabsTrigger
                  value="signin"
                  className="rounded-full text-sm focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0 data-[state=active]:text-[#22262f]"
                >
                  Sign in
                </TabsTrigger>
                <TabsTrigger
                  value="signup"
                  className="rounded-full text-sm focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0 data-[state=active]:text-[#22262f]"
                >
                  Sign up
                </TabsTrigger>
              </TabsList>

              <TabsContent value="signin" className="mt-5">
                <form onSubmit={handleSignIn} className="space-y-4">
                  <div className="space-y-2.5">
                    <Input
                      type="email"
                      placeholder="Email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      required
                      className={quietInput}
                    />
                    <Input
                      type="password"
                      placeholder="Password"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      required
                      className={quietInput}
                    />
                  </div>
                  <Button type="submit" className={primaryCta} disabled={loading}>
                    {loading ? "Signing in..." : "Sign in"}
                  </Button>
                </form>
              </TabsContent>

              <TabsContent value="signup" className="mt-5">
                <form onSubmit={handleSignUp} className="space-y-4">
                  <div className="space-y-2.5">
                    <Input
                      type="email"
                      placeholder="Email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      required
                      className={quietInput}
                    />
                    <Input
                      type="password"
                      placeholder="Password"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      required
                      className={quietInput}
                    />
                    <div className="space-y-1.5">
                      <div className="relative">
                        <span className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-[15px] text-[#959ba6]">@</span>
                        <Input
                          type="text"
                          placeholder="username"
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
                          className={`${quietInput} pl-8 ${usernameError ? 'border-[#c93a3a]' : ''}`}
                        />
                      </div>
                      {usernameError && (
                        <p className="text-xs text-[#c93a3a]">{usernameError}</p>
                      )}
                      {username && !usernameError && username.length >= 3 ? (
                        <p className="text-xs text-[#646b76]">
                          You'll be <span className="font-medium text-[#22262f]">@{username}</span> on Stash —
                          your public feed lives at gostash.it/feed/{username}
                        </p>
                      ) : (
                        <p className="text-xs text-[#646b76]">
                          Your username becomes your @handle and your public feed address.
                        </p>
                      )}
                    </div>
                    <div className="space-y-1.5">
                      <Input
                        type="tel"
                        placeholder="Phone number (optional)"
                        value={phoneNumber}
                        onChange={(e) => {
                          setPhoneNumber(e.target.value);
                          if (e.target.value.trim()) {
                            checkPhoneUniqueness(e.target.value);
                          } else {
                            setPhoneError('');
                          }
                        }}
                        className={`${quietInput} ${phoneError ? 'border-[#c93a3a]' : ''}`}
                      />
                      {phoneError && (
                        <p className="text-xs text-[#c93a3a]">{phoneError}</p>
                      )}
                      <p className="text-xs text-[#646b76]">
                        Add your phone number to use WhatsApp for sending notes, voice messages, and asking questions about your content.
                      </p>
                    </div>
                  </div>
                  <Button type="submit" className={primaryCta} disabled={loading || !!usernameError || !!phoneError}>
                    {loading ? "Creating account..." : "Create account"}
                  </Button>
                </form>
              </TabsContent>
            </Tabs>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Auth;
