import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

const DEBOUNCE_MS = 300;
const MIN_QUERY_LENGTH = 2;
const RESULT_LIMIT = 50;

// Debounced server-side hybrid search via the `search-items` edge function
// (semantic + keyword, reaches page_body/summary — fields the client filter
// can't see). Returns relevance-ordered item ids for the CURRENT query, or
// null while unavailable (query too short, response pending, or request
// failed) so the caller can fall back to the instant client-side filter.
export function useServerSearch(query: string): { serverResultIds: string[] | null } {
  const [results, setResults] = useState<{ forQuery: string; ids: string[] } | null>(null);
  const cacheRef = useRef(new Map<string, string[]>());

  const trimmed = query.trim();

  useEffect(() => {
    if (trimmed.length < MIN_QUERY_LENGTH) return;

    const cached = cacheRef.current.get(trimmed);
    if (cached) {
      setResults({ forQuery: trimmed, ids: cached });
      return;
    }

    let cancelled = false;
    const timer = setTimeout(async () => {
      try {
        const { data, error } = await supabase.functions.invoke('search-items', {
          body: { query: trimmed, limit: RESULT_LIMIT },
        });
        if (cancelled || error || !Array.isArray(data?.results)) return;
        const ids = data.results.map((r: { id: string }) => r.id);
        cacheRef.current.set(trimmed, ids);
        setResults({ forQuery: trimmed, ids });
      } catch {
        // Network failure — the client-side filter keeps working
      }
    }, DEBOUNCE_MS);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [trimmed]);

  return {
    serverResultIds:
      trimmed.length >= MIN_QUERY_LENGTH && results?.forQuery === trimmed
        ? results.ids
        : null,
  };
}
