import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { runObjectIntelligenceWorker } from '../_shared/objectIntelligenceWorker.ts';
import { rebuildItemIndex } from '../_shared/enrichmentIndex.ts';

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const bounded = (name: string, fallback: number, max: number) => Math.max(0, Math.min(max, Number(Deno.env.get(name) ?? fallback) || 0));
serve(async req => {
  if (req.method !== 'POST') return json(405, { error: 'POST only' });
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const cron = Deno.env.get('CRON_SECRET');
  if (!(cron && req.headers.get('x-cron-secret') === cron) && !(service && req.headers.get('authorization') === `Bearer ${service}`)) return json(401, { error: 'unauthorized' });
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  const db = createClient(Deno.env.get('SUPABASE_URL')!, service!);
  try {
    return json(200, await runObjectIntelligenceWorker({ db,
      config: { enabled: Deno.env.get('OBJECT_INTELLIGENCE_ENABLED') === 'true', apiKey,
        dailyLimit: bounded('OBJECT_INTELLIGENCE_DAILY_LIMIT', 200, 500), hourlyLimit: bounded('OBJECT_INTELLIGENCE_HOURLY_LIMIT', 24, 24) },
      index: item => rebuildItemIndex(db, item, apiKey!),
    }));
  } catch {
    console.error('object-intelligence-worker failed');
    return json(500, { error: 'Object intelligence worker failed' });
  }
});
