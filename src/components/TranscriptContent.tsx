import React, { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import { supabase } from '@/integrations/supabase/client';
import { scheduleEmbeddingRefresh } from '@/utils/itemOperations';
import { Button } from '@/components/ui/button';

/** Reprocessing replaces captured source, never the user's notes. */
export default function TranscriptContent({ itemId, filePath, transcript }: {
  itemId: string; filePath?: string; transcript: string | null;
}) {
  const [replacement, setReplacement] = useState<string | null>(null);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState('');
  const text = replacement ?? transcript;
  const retranscribe = async () => {
    if (!filePath || working) return;
    setWorking(true);
    setError('');
    try {
      const audioUrl = supabase.storage.from('stash-media').getPublicUrl(filePath).data.publicUrl;
      const { data, error: transcriptionError } = await supabase.functions.invoke('transcribe-audio', {
        body: { audioUrl, fileName: filePath.split('/').pop() },
      });
      if (transcriptionError || !data?.transcription?.trim()) throw new Error('No transcript returned');
      const { data: updated, error: saveError } = await supabase.from('items')
        .update({ page_body: data.transcription, description: data.description })
        .eq('id', itemId).select().single();
      if (saveError) throw saveError;
      setReplacement(data.transcription);
      if (updated) scheduleEmbeddingRefresh(updated);
    } catch {
      setError('Couldn’t update the transcript. The original is preserved. Please try again.');
    } finally { setWorking(false); }
  };
  return (
    <div className="space-y-4">
      {filePath && <div className="flex flex-wrap items-center gap-3">
        <Button variant="outline" size="sm" disabled={working} onClick={() => void retranscribe()}>
          {working ? 'Separating speakers…' : 'Transcribe with speakers'}
        </Button>
        <span className="text-xs text-muted-foreground">{working ? 'You can keep reading while this runs.' : 'Rebuild from the original recording.'}</span>
      </div>}
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      {text ? <div className="prose prose-sm max-h-[420px] max-w-none overflow-y-auto whitespace-pre-wrap pr-1 text-foreground/90"><ReactMarkdown>{text}</ReactMarkdown></div>
        : <p className="py-6 text-sm text-muted-foreground">No transcript available for this recording.</p>}
    </div>
  );
}
