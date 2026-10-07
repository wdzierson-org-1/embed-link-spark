import React, { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';

/** Reprocessing replaces captured source, never the user's notes. */
export default function TranscriptContent({ itemId, filePath, transcript }: {
  itemId: string; filePath?: string; transcript: string | null;
}) {
  const [working, setWorking] = useState(false);
  const [error, setError] = useState('');
  const text = transcript;
  // The transcript is the server's to write. Persisting it from here would run as
  // `authenticated`, and protect_enrichment_edits records any authenticated change
  // to page_body as a user edit — which permanently locks enrichment out of the
  // field. So hand the rebuild to the job that already owns every write for the
  // item; it replaces page_body, description, summary, title and the embeddings as
  // one coherent step, and the progress strip above reads its status.
  const retranscribe = async () => {
    if (!filePath || working) return;
    setWorking(true);
    setError('');
    try {
      const { error: jobError } = await supabase.functions.invoke('transcribe-audio', {
        body: { itemId },
      });
      if (jobError) throw jobError;
    } catch {
      setError('Couldn’t update the transcript. The original is preserved. Please try again.');
    } finally { setWorking(false); }
  };
  return (
    <div className="space-y-4">
      {filePath && <div className="flex flex-wrap items-center gap-3">
        <Button variant="outline" size="sm" disabled={working} onClick={() => void retranscribe()}>
          {working ? 'Transcribing…' : 'Transcribe again'}
        </Button>
        <span className="text-[13px] text-muted-foreground">{working ? 'You can keep reading while this runs.' : 'Rebuild from the original recording.'}</span>
      </div>}
      {error && <p role="alert" className="text-[14px] text-error">{error}</p>}
      {text ? <div className="prose prose-sm max-h-[420px] max-w-none overflow-y-auto whitespace-pre-wrap pr-1 text-[15px] leading-[1.6] text-ink"><ReactMarkdown>{text}</ReactMarkdown></div>
        : <p className="py-6 text-sm text-muted-foreground">No transcript available for this recording.</p>}
    </div>
  );
}
