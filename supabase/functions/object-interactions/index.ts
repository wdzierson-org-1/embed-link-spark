import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { requireEntitlement } from '../_shared/entitlementGate.ts';
import { buildObjectInteractionDraft } from '../_shared/objectInteractionDraft.ts';
import { createObjectInteractionsHandler, objectInteractionsHeaders } from './handler.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(createObjectInteractionsHandler({
  db: admin,
  requireEntitlement: user => requireEntitlement(admin, user, objectInteractionsHeaders),
  buildDraft: buildObjectInteractionDraft,
}));
