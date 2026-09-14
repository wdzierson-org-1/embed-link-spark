import { supabase } from '@/integrations/supabase/client';

export async function settleEnrichment(itemId: string, complete: boolean): Promise<void> {
  const { error } = await supabase.rpc('set_item_enrichment', {
    target_id: itemId, next_status: complete ? 'complete' : 'partial',
  });
  if (error) console.error('Could not settle enrichment status:', error);
}
