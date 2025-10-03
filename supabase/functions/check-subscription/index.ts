import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@18.5.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const logStep = (step: string, details?: any) => {
  const detailsStr = details ? ` - ${JSON.stringify(details)}` : '';
  console.log(`[CHECK-SUBSCRIPTION] ${step}${detailsStr}`);
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  try {
    logStep("Function started");

    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) throw new Error("STRIPE_SECRET_KEY is not set");
    logStep("Stripe key verified");

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("No authorization header provided");
    
    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await supabaseClient.auth.getUser(token);
    if (userError) throw new Error(`Authentication error: ${userError.message}`);
    const user = userData.user;
    if (!user?.email) throw new Error("User not authenticated or email not available");
    logStep("User authenticated", { userId: user.id, email: user.email });

    const stripe = new Stripe(stripeKey, { apiVersion: "2025-08-27.basil" });
    const customers = await stripe.customers.list({ email: user.email, limit: 1 });
    
    if (customers.data.length === 0) {
      logStep("No Stripe customer found - user needs trial subscription");
      return new Response(JSON.stringify({ 
        subscribed: false,
        subscriptionStatus: null,
        onTrial: false,
        trialEnd: null,
        daysLeftInTrial: 0,
        subscriptionEnd: null,
        productId: null,
        hasStripeCustomer: false,
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    const customerId = customers.data[0].id;
    logStep("Found Stripe customer", { customerId });

    // Get all subscriptions (active, trialing, paused, etc.)
    const subscriptions = await stripe.subscriptions.list({
      customer: customerId,
      status: 'all',
      limit: 1,
    });

    if (subscriptions.data.length === 0) {
      logStep("Customer exists but no subscription found");
      return new Response(JSON.stringify({
        subscribed: false,
        subscriptionStatus: null,
        onTrial: false,
        trialEnd: null,
        daysLeftInTrial: 0,
        subscriptionEnd: null,
        productId: null,
        hasStripeCustomer: true,
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    const subscription = subscriptions.data[0];
    const status = subscription.status;
    const isTrialing = status === 'trialing';
    const isActive = status === 'active';
    const isPaused = status === 'paused';
    
    // Calculate days left in trial
    let daysLeftInTrial = 0;
    let trialEnd: string | null = null;
    if (subscription.trial_end) {
      trialEnd = new Date(subscription.trial_end * 1000).toISOString();
      const now = Math.floor(Date.now() / 1000);
      const secondsLeft = Math.max(0, subscription.trial_end - now);
      daysLeftInTrial = Math.ceil(secondsLeft / (60 * 60 * 24));
    }

    const subscriptionEnd = subscription.current_period_end 
      ? new Date(subscription.current_period_end * 1000).toISOString()
      : null;

    const productId = subscription.items.data[0]?.price.product as string || null;

    logStep("Subscription details", { 
      status,
      isTrialing,
      isActive,
      isPaused,
      daysLeftInTrial,
      trialEnd,
      subscriptionEnd,
      productId,
    });

    return new Response(JSON.stringify({
      subscribed: isActive,
      subscriptionStatus: status,
      onTrial: isTrialing,
      trialEnd,
      daysLeftInTrial,
      subscriptionEnd,
      productId,
      hasStripeCustomer: true,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logStep("ERROR in check-subscription", { message: errorMessage });
    return new Response(JSON.stringify({ error: errorMessage }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
