import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
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

  const checkSubscription = async () => {
    if (!user) {
      setSubscribed(false);
      setOnTrial(false);
      setProductId(null);
      setSubscriptionEnd(null);
      setLoading(false);
      return;
    }

    try {
      const { data, error } = await supabase.functions.invoke('check-subscription');
      
      if (error) {
        console.error('Error checking subscription:', error);
        setSubscribed(false);
        setSubscriptionStatus(null);
        setOnTrial(false);
        setTrialEnd(null);
        setDaysLeftInTrial(0);
        setProductId(null);
        setSubscriptionEnd(null);
        setHasStripeCustomer(false);
      } else {
        setSubscribed(data.subscribed || false);
        setSubscriptionStatus(data.subscriptionStatus);
        setOnTrial(data.onTrial || false);
        setTrialEnd(data.trialEnd);
        setDaysLeftInTrial(data.daysLeftInTrial || 0);
        setProductId(data.productId);
        setSubscriptionEnd(data.subscriptionEnd);
        setHasStripeCustomer(data.hasStripeCustomer || false);
      }
    } catch (error) {
      console.error('Exception checking subscription:', error);
      setSubscribed(false);
      setSubscriptionStatus(null);
      setOnTrial(false);
      setTrialEnd(null);
      setDaysLeftInTrial(0);
      setProductId(null);
      setSubscriptionEnd(null);
      setHasStripeCustomer(false);
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
  // Auto-refresh subscription status every 30 seconds
  useEffect(() => {
    if (!user) return;

    const interval = setInterval(checkSubscription, 30000);
    return () => clearInterval(interval);
  }, [user]);

  // Calculate feature access based on subscription status
  const canAddContent = subscriptionStatus === 'trialing' || subscriptionStatus === 'active';
  const canUseAI = subscriptionStatus === 'trialing' || subscriptionStatus === 'active';
  const canSearch = subscriptionStatus === 'trialing' || subscriptionStatus === 'active';
  const canAccessFullFeatures = subscriptionStatus === 'trialing' || subscriptionStatus === 'active';

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