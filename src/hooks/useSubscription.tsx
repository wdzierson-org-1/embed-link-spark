import { createContext, useContext, useEffect, useRef, useState, ReactNode } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

interface SubscriptionContextType {
  subscribed: boolean;
  subscriptionStatus: string | null;
  onTrial: boolean;
  trialEnd: string | null;
  daysLeftInTrial: number;
  productId: string | null;
  subscriptionEnd: string | null;
  hasStripeCustomer: boolean;
  loading: boolean;
  checkSubscription: () => Promise<void>;
  createCheckoutSession: () => Promise<void>;
  openCustomerPortal: () => Promise<void>;
  canAddContent: boolean;
  canUseAI: boolean;
  canSearch: boolean;
  canAccessFullFeatures: boolean;
}

const SubscriptionContext = createContext<SubscriptionContextType | undefined>(undefined);

// Product mapping
const SUBSCRIPTION_TIERS = {
  premium: {
    price_id: "price_1SEFK4DjmsxBFAFefosv28h2",
    product_id: "prod_TAaVGlswi6ss1o",
    name: "Premium",
    price: "$4.99/month"
  }
};

export const SubscriptionProvider = ({ children }: { children: ReactNode }) => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [subscribed, setSubscribed] = useState(false);
  const [subscriptionStatus, setSubscriptionStatus] = useState<string | null>(null);
  const [onTrial, setOnTrial] = useState(false);
  const [trialEnd, setTrialEnd] = useState<string | null>(null);
  const [daysLeftInTrial, setDaysLeftInTrial] = useState(0);
  const [productId, setProductId] = useState<string | null>(null);
  const [subscriptionEnd, setSubscriptionEnd] = useState<string | null>(null);
  const [hasStripeCustomer, setHasStripeCustomer] = useState(false);
  const [loading, setLoading] = useState(true);
  // True once the server has given a definitive answer this session. Errors
  // (expired-JWT race, network blip, Stripe hiccup) never flip this — an
  // errored check means "unknown", not "unsubscribed".
  const [statusKnown, setStatusKnown] = useState(false);
  const trialEnsuredRef = useRef(false);

  const checkSubscription = async () => {
    // Anonymous try-stash sessions have no subscription and never should —
    // treat them like signed-out (no polling, no trial creation)
    if (!user || (user as { is_anonymous?: boolean }).is_anonymous) {
      setSubscribed(false);
      setSubscriptionStatus(null);
      setOnTrial(false);
      setTrialEnd(null);
      setDaysLeftInTrial(0);
      setProductId(null);
      setSubscriptionEnd(null);
      setHasStripeCustomer(false);
      setStatusKnown(false);
      setLoading(false);
      return;
    }

    try {
      let { data, error } = await supabase.functions.invoke('check-subscription');

      // A user with no subscription at all is a fresh account whose trial hasn't
      // been created yet — create it now and re-check, so the first save is never
      // blocked by the signup/Stripe race. Attempted once per session.
      if (!error && data && !data.subscriptionStatus && !trialEnsuredRef.current) {
        trialEnsuredRef.current = true;
        const { error: trialError } = await supabase.functions.invoke('create-trial-subscription');
        if (!trialError) {
          ({ data, error } = await supabase.functions.invoke('check-subscription'));
        }
      }

      if (error) {
        // Fail open: keep the last known state. The next 30s poll (or the
        // re-check fired by a token refresh) will get the real answer.
        console.warn('Subscription check failed, keeping last known state:', error);
      } else {
        setSubscribed(data.subscribed || false);
        setSubscriptionStatus(data.subscriptionStatus);
        setOnTrial(data.onTrial || false);
        setTrialEnd(data.trialEnd);
        setDaysLeftInTrial(data.daysLeftInTrial || 0);
        setProductId(data.productId);
        setSubscriptionEnd(data.subscriptionEnd);
        setHasStripeCustomer(data.hasStripeCustomer || false);
        setStatusKnown(true);
      }
    } catch (error) {
      console.warn('Subscription check failed, keeping last known state:', error);
    } finally {
      setLoading(false);
    }
  };

  const createCheckoutSession = async () => {
    if (!user) {
      toast({
        title: "Authentication Required",
        description: "Please sign in to subscribe",
        variant: "destructive",
      });
      return;
    }

    try {
      const { data, error } = await supabase.functions.invoke('create-checkout');
      
      if (error) {
        toast({
          title: "Error",
          description: "Failed to create checkout session",
          variant: "destructive",
        });
        return;
      }

      if (data?.url) {
        window.open(data.url, '_blank');
      }
    } catch (error) {
      console.error('Error creating checkout session:', error);
      toast({
        title: "Error",
        description: "Failed to start checkout process",
        variant: "destructive",
      });
    }
  };

  const openCustomerPortal = async () => {
    if (!user) return;

    try {
      const { data, error } = await supabase.functions.invoke('customer-portal');
      
      if (error) {
        toast({
          title: "Error",
          description: "Failed to open customer portal",
          variant: "destructive",
        });
        return;
      }

      if (data?.url) {
        window.open(data.url, '_blank');
      }
    } catch (error) {
      console.error('Error opening customer portal:', error);
      toast({
        title: "Error",
        description: "Failed to open subscription management",
        variant: "destructive",
      });
    }
  };

  useEffect(() => {
    checkSubscription();
  }, [user]);

  // Auto-refresh subscription status every 30 seconds
  useEffect(() => {
    if (!user) return;

    const interval = setInterval(checkSubscription, 30000);
    return () => clearInterval(interval);
  }, [user]);

  // Feature access based on subscription status. Block only on a definitive
  // "not subscribed" answer from the server: while the first check (and trial
  // self-heal) is in flight — or if no check has succeeded yet this session —
  // stay permissive. Blocking a subscribed user over a transient error (the
  // 2026-08-10 zombie-session incident, expired-JWT poll races after laptop
  // wake) is worse than letting a lapsed one through briefly.
  const hasAccess = loading || !statusKnown ||
    subscriptionStatus === 'trialing' || subscriptionStatus === 'active';
  const canAddContent = hasAccess;
  const canUseAI = hasAccess;
  const canSearch = hasAccess;
  const canAccessFullFeatures = hasAccess;

  return (
    <SubscriptionContext.Provider value={{
      subscribed,
      subscriptionStatus,
      onTrial,
      trialEnd,
      daysLeftInTrial,
      productId,
      subscriptionEnd,
      hasStripeCustomer,
      loading,
      checkSubscription,
      createCheckoutSession,
      openCustomerPortal,
      canAddContent,
      canUseAI,
      canSearch,
      canAccessFullFeatures
    }}>
      {children}
    </SubscriptionContext.Provider>
  );
};

export const useSubscription = () => {
  const context = useContext(SubscriptionContext);
  if (context === undefined) {
    throw new Error('useSubscription must be used within a SubscriptionProvider');
  }
  return context;
};