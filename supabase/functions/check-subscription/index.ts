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
      logStep("No customer found, calculating trial status based on account age");
      
      // Calculate trial status based on user creation date
      const userCreatedAt = new Date(user.created_at);
      const now = new Date();
      const daysSinceCreation = Math.floor((now.getTime() - userCreatedAt.getTime()) / (1000 * 60 * 60 * 24));
      
      let trialStatus = 'active';
      let accountStatus = 'active';
      
      if (daysSinceCreation <= 7) {
        trialStatus = 'active';
        accountStatus = 'active';
      } else if (daysSinceCreation <= 37) {
        trialStatus = 'expired';
        accountStatus = 'read_only';
      } else {
        trialStatus = 'expired';
        accountStatus = 'expired';
      }

      logStep("Trial status calculated", { daysSinceCreation, trialStatus, accountStatus });
      
      return new Response(JSON.stringify({ 
        subscribed: false,
        onTrial: false,
        product_id: null,
        subscription_end: null,
        trial_status: trialStatus,
        account_status: accountStatus,
        days_since_creation: daysSinceCreation
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    const customerId = customers.data[0].id;
    logStep("Found Stripe customer", { customerId });

    // Check for active subscriptions (including trials)
    const subscriptions = await stripe.subscriptions.list({
      customer: customerId,
      status: "active",
      limit: 1,
    });

    // Also check for trialing subscriptions
    const trialSubscriptions = await stripe.subscriptions.list({
      customer: customerId,
      status: "trialing",
      limit: 1,
    });

    const allActiveSubscriptions = [...subscriptions.data, ...trialSubscriptions.data];
    const hasActiveSub = allActiveSubscriptions.length > 0;
    
    let productId = null;
    let subscriptionEnd = null;
    let onTrial = false;

    if (hasActiveSub) {
      const subscription = allActiveSubscriptions[0];
      subscriptionEnd = new Date(subscription.current_period_end * 1000).toISOString();
      onTrial = subscription.status === "trialing";
      productId = subscription.items.data[0].price.product;
      logStep("Active subscription found", { 
        subscriptionId: subscription.id, 
        endDate: subscriptionEnd,
        onTrial,
        productId,
        status: subscription.status
      });
    } else {
      logStep("No active subscription found");
    }

    // Calculate trial status based on user creation date
    const userCreatedAt = new Date(user.created_at);
    const now = new Date();
    const daysSinceCreation = Math.floor((now.getTime() - userCreatedAt.getTime()) / (1000 * 60 * 60 * 24));
    
    let trialStatus = 'active'; // active, read_only, expired
    let accountStatus = 'active'; // active, read_only, expired
    
    if (!hasActiveSub) {
      if (daysSinceCreation <= 7) {
        trialStatus = 'active';
        accountStatus = 'active';
      } else if (daysSinceCreation <= 37) {
        trialStatus = 'expired';
        accountStatus = 'read_only';
      } else {
        trialStatus = 'expired';
        accountStatus = 'expired';
      }
    } else {
      trialStatus = onTrial ? 'active' : 'complete';
      accountStatus = 'active';
    }

    logStep("Calculated trial and account status", { 
      daysSinceCreation, 
      trialStatus, 
      accountStatus,
      hasActiveSub,
      onTrial 
    });

    return new Response(JSON.stringify({
      subscribed: hasActiveSub,
      onTrial,
      product_id: productId,
      subscription_end: subscriptionEnd,
      trial_status: trialStatus,
      account_status: accountStatus,
      days_since_creation: daysSinceCreation
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