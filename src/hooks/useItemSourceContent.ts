import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';

// Loads the heavyweight per-item fields (summary, page_body) that the item
// list query deliberately leaves out, and exposes on-demand summary generation
// for items captured before summaries existed.
export const useItemSourceContent = (itemId: string | undefined, enabled: boolean) => {
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
  }, [itemId, enabled]);

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
        setGenerateError("There's no captured content to summarize yet.");
      } else {
        setGenerateError("Couldn't generate a summary. Please try again.");
      }
    } catch (err) {
      console.error('Summary generation failed:', err);
      setGenerateError("Couldn't generate a summary. Please try again.");
    } finally {
      setIsGenerating(false);
    }
  }, [itemId, isGenerating]);

  return { summary, pageBody, isLoading, isGenerating, generateError, generateSummary };
};
