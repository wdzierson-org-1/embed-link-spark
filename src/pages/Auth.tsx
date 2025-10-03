
import { useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useToast } from '@/hooks/use-toast';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useEffect, useMemo } from 'react';
import { usePhoneNumber } from '@/hooks/usePhoneNumber';
import { getGradientPlaceholder } from '@/utils/gradientPlaceholders';
import { supabase } from '@/integrations/supabase/client';

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
  
  // Get a random gradient background
  const backgroundGradient = useMemo(() => {
    const randomId = Math.random().toString(36);
    return getGradientPlaceholder(randomId);
  }, []);
  
  const { signIn, signUp, user } = useAuth();
  const { registerPhoneNumber } = usePhoneNumber();
  const { toast } = useToast();
  const navigate = useNavigate();

  // Redirect if already authenticated
  useEffect(() => {
    if (user) {
      if (returnTo && commentItem) {
        // Redirect back to the original page with comment panel open
        navigate(`${returnTo}?openComment=${commentItem}`);
      } else if (returnTo) {
        navigate(returnTo);
      } else {
        navigate('/home');
      }
    }
  }, [user, navigate, returnTo, commentItem]);

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
    <div className="min-h-screen relative animated-gradient">
      {/* Overlay for better text readability */}
      <div className="absolute inset-0 bg-black/30"></div>
      <div className="relative z-10">
        {/* Logo in upper left */}
        <div className="absolute top-6 left-6">
          <div className="flex items-center space-x-2">
            <img 
              src="/lovable-uploads/b93db9a2-7dba-4a6c-b36a-a9f982356ff6.png" 
              alt="Stash"
              className="w-10 h-10"
            />
            <span className="text-xl font-editorial text-white">Stash</span>
          </div>
        </div>

        <div className="min-h-screen flex items-center justify-center p-4">
          <Card className="w-full max-w-md bg-white/95 backdrop-blur-sm">
            <CardHeader className="text-center">
              <CardTitle className="text-2xl font-editorial font-semibold">Welcome to Stash</CardTitle>
              <CardDescription>
                Your smart content companion for capturing, organizing, and discovering insights
              </CardDescription>
            </CardHeader>
          <CardContent>
            <Tabs defaultValue={mode} className="w-full">
              <TabsList className="grid w-full grid-cols-2">
                <TabsTrigger value="signin">Sign In</TabsTrigger>
                <TabsTrigger value="signup">Sign Up</TabsTrigger>
              </TabsList>
              
              <TabsContent value="signin">
                <form onSubmit={handleSignIn} className="space-y-4">
                  <div className="space-y-2">
                    <Input
                      type="email"
                      placeholder="Email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      required
                    />
                    <Input
                      type="password"
                      placeholder="Password"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      required
                    />
                  </div>
                  <Button type="submit" className="w-full bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700" disabled={loading}>
                    {loading ? "Signing in..." : "Sign In"}
                  </Button>
                </form>
              </TabsContent>
              
              <TabsContent value="signup">
                <form onSubmit={handleSignUp} className="space-y-4">
                  <div className="space-y-2">
                    <Input
                      type="email"
                      placeholder="Email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      required
                    />
                    <Input
                      type="password"
                      placeholder="Password"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      required
                    />
                    <div className="space-y-1">
                      <Input
                        type="text"
                        placeholder="Username"
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
                        className={usernameError ? 'border-red-500' : ''}
                      />
                      {usernameError && (
                        <p className="text-xs text-red-600">{usernameError}</p>
                      )}
                      {username && !usernameError && username.length >= 3 && (
                        <p className="text-xs text-muted-foreground">
                          Your Stash feed URL: https://gostash.it/feed/{username}
                        </p>
                      )}
                    </div>
                    <div className="space-y-1">
                      <Input
                        type="tel"
                        placeholder="Phone Number (optional)"
                        value={phoneNumber}
                        onChange={(e) => {
                          setPhoneNumber(e.target.value);
                          if (e.target.value.trim()) {
                            checkPhoneUniqueness(e.target.value);
                          } else {
                            setPhoneError('');
                          }
                        }}
                        className={phoneError ? 'border-red-500' : ''}
                      />
                      {phoneError && (
                        <p className="text-xs text-red-600">{phoneError}</p>
                      )}
                      <p className="text-xs text-muted-foreground">
                        Add your phone number to use WhatsApp for sending notes, voice messages, and asking questions about your content.
                      </p>
                    </div>
                  </div>
                  <Button type="submit" className="w-full bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700" disabled={loading || !!usernameError || !!phoneError}>
                    {loading ? "Creating account..." : "Sign Up"}
                  </Button>
                </form>
              </TabsContent>
            </Tabs>
          </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
};

export default Auth;
