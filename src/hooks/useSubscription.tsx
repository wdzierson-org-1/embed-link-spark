import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

interface SubscriptionContextType {
  subscribed: boolean;
  onTrial: boolean;
  productId: string | null;
  subscriptionEnd: string | null;
  trialStatus: 'active' | 'expired' | 'complete';
  accountStatus: 'active' | 'read_only' | 'expired';
  daysSinceCreation: number;
  loading: boolean;
  checkSubscription: () => Promise<void>;
  createCheckoutSession: () => Promise<void>;
  openCustomerPortal: () => Promise<void>;
  canAddContent: boolean;
  canUseAI: boolean;
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
  const [onTrial, setOnTrial] = useState(false);
  const [productId, setProductId] = useState<string | null>(null);
  const [subscriptionEnd, setSubscriptionEnd] = useState<string | null>(null);
  const [trialStatus, setTrialStatus] = useState<'active' | 'expired' | 'complete'>('active');
  const [accountStatus, setAccountStatus] = useState<'active' | 'read_only' | 'expired'>('active');
  const [daysSinceCreation, setDaysSinceCreation] = useState(0);
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
        setOnTrial(false);
        setProductId(null);
        setSubscriptionEnd(null);
        setTrialStatus('active');
        setAccountStatus('active');
        setDaysSinceCreation(0);
      } else {
        setSubscribed(data.subscribed || false);
        setOnTrial(data.onTrial || false);
        setProductId(data.product_id);
        setSubscriptionEnd(data.subscription_end);
        setTrialStatus(data.trial_status || 'active');
        setAccountStatus(data.account_status || 'active');
        setDaysSinceCreation(data.days_since_creation || 0);
      }
    } catch (error) {
      console.error('Exception checking subscription:', error);
      setSubscribed(false);
      setOnTrial(false);
      setProductId(null);
      setSubscriptionEnd(null);
      setTrialStatus('active');
      setAccountStatus('active');
      setDaysSinceCreation(0);
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

  // Calculate feature access based on subscription and trial status
  const canAddContent = subscribed || accountStatus === 'active';
  const canUseAI = subscribed || accountStatus === 'active';
  const canAccessFullFeatures = subscribed || accountStatus === 'active';

  return (
    <SubscriptionContext.Provider value={{
      subscribed,
      onTrial,
      productId,
      subscriptionEnd,
      trialStatus,
      accountStatus,
      daysSinceCreation,
      loading,
      checkSubscription,
      createCheckoutSession,
      openCustomerPortal,
      canAddContent,
      canUseAI,
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