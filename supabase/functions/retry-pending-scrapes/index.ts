import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { isBlockedPageTitle, verifyRemoteImage } from '../_shared/blockedContentFallbacks.ts';

// Scheduled worker (pg_cron, every 2 hours): re-attempts content extraction
// for link items that still have no page_body — blocked sites often become
// readable later via the Wayback snapshot we commissioned at save time, a
// paid tier key being added, or the site simply letting the next attempt
// through. Small batches with per-item backoff; gives up after 5 attempts.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const BATCH_SIZE = 5;
const MAX_ATTEMPTS = 5;
const RETRY_WINDOW_DAYS = 30;
const MIN_HOURS_BETWEEN_ATTEMPTS = 2;

const isPlaceholderMetadata = (title: string | null, description: string | null, url: string): boolean => {
  try {
    const hostname = new URL(url).hostname.replace(/^www\./, '').toLowerCase();
    const normalizedTitle = (title || '').trim().toLowerCase();
    if (!normalizedTitle || normalizedTitle === hostname || normalizedTitle === `www.${hostname}`) return true;
    if (isBlockedPageTitle(normalizedTitle)) return true;
  } catch {
    return true;
  }
  return (description || '').includes('Inferred from the link');
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const windowStart = new Date(Date.now() - RETRY_WINDOW_DAYS * 24 * 3600 * 1000).toISOString();
    const attemptCutoff = new Date(Date.now() - MIN_HOURS_BETWEEN_ATTEMPTS * 3600 * 1000).toISOString();

    const { data: pending, error } = await supabase
      .from('items')
      .select('id, url, title, description, file_path, scrape_attempts')
      .eq('type', 'link')
      .not('url', 'is', null)
      .or('page_body.is.null,page_body.eq.')
      .lt('scrape_attempts', MAX_ATTEMPTS)
      .gt('created_at', windowStart)
      .or(`last_scrape_attempt.is.null,last_scrape_attempt.lt.${attemptCutoff}`)
      .order('created_at', { ascending: false })
      .limit(BATCH_SIZE);

    if (error) throw error;

    let succeeded = 0;
    const results: Array<{ id: string; scraped: boolean }> = [];

    for (const item of pending || []) {
      // Count the attempt up front so failures still back off
      await supabase
        .from('items')
        .update({
          scrape_attempts: (item.scrape_attempts || 0) + 1,
          last_scrape_attempt: new Date().toISOString(),
        })
        .eq('id', item.id);

      const { data: scrapeResult } = await supabase.functions.invoke('scrape-page-content', {
        body: { itemId: item.id, url: item.url },
      });

      const scraped = Boolean(scrapeResult?.success);
      if (scraped) succeeded += 1;
      results.push({ id: item.id, scraped });

      // If the card is still wearing placeholder metadata, try to upgrade the
      // title/description now that a tier may have opened up
      if (isPlaceholderMetadata(item.title, item.description, item.url)) {
        try {
          const { data: meta } = await supabase.functions.invoke('extract-link-metadata', {
            body: { url: item.url, fastOnly: false },
          });
          const updates: Record<string, string> = {};
          if (meta?.title && !isPlaceholderMetadata(meta.title, null, item.url)) {
            updates.title = meta.title;
            if (meta.description) updates.description = meta.description;
          }
          let bestImage = meta?.previewImagePath || meta?.previewImagePublicUrl || null;
          if (!bestImage && meta?.image && await verifyRemoteImage(meta.image)) {
            bestImage = meta.image;
          }
          if (bestImage && !item.file_path) {
            updates.file_path = bestImage;
          }
          if (Object.keys(updates).length > 0) {
            await supabase.from('items').update(updates).eq('id', item.id);
          }
        } catch (metaError) {
          console.error('Metadata upgrade failed for', item.id, metaError);
        }
      }
    }

    console.log(`retry-pending-scrapes: ${pending?.length || 0} attempted, ${succeeded} scraped`);

    return new Response(
      JSON.stringify({ attempted: pending?.length || 0, succeeded, results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('retry-pending-scrapes error:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
