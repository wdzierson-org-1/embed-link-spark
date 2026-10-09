import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';

// summarize-content refuses a source under 50 characters (no_source_content),
// so the panel only offers the button when the server can act on it
export const MIN_SUMMARY_SOURCE_CHARS = 50;

export const canSummarizeSource = (pageBody: string | null | undefined): boolean =>
  (pageBody?.trim().length ?? 0) >= MIN_SUMMARY_SOURCE_CHARS;

// Loads the heavyweight per-item fields (summary, page_body) that the item
// list query deliberately leaves out, and exposes on-demand summary generation
// for items captured before summaries existed. `refreshKey` re-runs the load
// when the caller knows the source changed server-side (a transcript job
// landing another chunk) — the list's realtime refetch carries the key.
export const useItemSourceContent = (itemId: string | undefined, enabled: boolean, refreshKey?: string) => {
  const [summary, setSummary] = useState<string | null>(null);
  const [pageBody, setPageBody] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isGenerating, setIsGenerating] = useState(false);
  const [generateError, setGenerateError] = useState<string | null>(null);

  useEffect(() => {
    setSummary(null);
    setPageBody(null);
    setGenerateError(null);

    if (!itemId || !enabled) return;

    let cancelled = false;
    setIsLoading(true);

    (async () => {
      const { data, error } = await supabase
        .from('items')
        .select('summary, page_body')
        .eq('id', itemId)
        .single();

      if (cancelled) return;
      if (error) {
        console.error('Failed to load item source content:', error);
      } else {
        setSummary(data?.summary ?? null);
        setPageBody(data?.page_body ?? null);
      }
      setIsLoading(false);
    })();

    return () => {
      cancelled = true;
    };
  }, [itemId, enabled, refreshKey]);

  const generateSummary = useCallback(async () => {
    if (!itemId || isGenerating) return;
    setIsGenerating(true);
    setGenerateError(null);
    try {
      const { data, error } = await supabase.functions.invoke('summarize-content', {
        body: { itemId },
      });
      if (error) throw error;
      if (data?.success && data.summary) {
        setSummary(data.summary);
      } else if (data?.reason === 'no_source_content') {
        setGenerateError('nothing captured to summarize yet');
      } else {
        console.error('Summary generation failed:', data?.reason);
        setGenerateError("couldn't summarize this. try again");
      }
    } catch (err) {
      console.error('Summary generation failed:', err);
      setGenerateError("couldn't summarize this. try again");
    } finally {
      setIsGenerating(false);
    }
  }, [itemId, isGenerating]);

  return { summary, pageBody, isLoading, isGenerating, generateError, generateSummary, setSummary };
};
