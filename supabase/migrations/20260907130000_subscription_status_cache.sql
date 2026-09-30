-- Server-side paywall (punch list B5).
--
-- The capture endpoints (add-note / add-url / add-file) and Ask used to trust
-- the client's gate; a lapsed account could keep writing through the API.
-- This table is the server's view of each user's Stripe subscription status.
-- It is written by check-subscription (the client already polls it every
-- 30 s), by the entitlement gate when it has to ask Stripe itself, and by the
-- stripe-webhook function on subscription events. Nothing else may touch it:
-- RLS is on with no policies, so only the service role (which bypasses RLS)
-- can read or write — a client cannot promote itself to "active".

CREATE TABLE IF NOT EXISTS public.subscription_status_cache (
  user_id            uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  status             text NOT NULL,            -- Stripe subscription.status, or 'none'
  stripe_customer_id text,
  checked_at         timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.subscription_status_cache ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.subscription_status_cache FROM anon, authenticated;

CREATE INDEX IF NOT EXISTS subscription_status_cache_customer_idx
  ON public.subscription_status_cache (stripe_customer_id);
