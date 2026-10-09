import { supabase } from '@/integrations/supabase/client';

export const generateDescription = async (type: string, data: any) => {
  try {
    console.log('aiOperations: Generating description', { type, data });
    
    const { data: result, error } = await supabase.functions.invoke('generate-description', {
      body: {
        content: data.content,
        type,
        url: data.url,
        fileData: data.fileData,
        ogData: data.ogData
      }
    });

    if (error) {
      console.error('aiOperations: Error from generate-description function:', error);
      throw error;
    }
    
    console.log('aiOperations: Description generated successfully:', result?.description);
    return result?.description;
  } catch (error) {
    console.error('aiOperations: Error generating description:', error);
    return null;
  }
};

/**
 * Ask the server to (re)index a save. The function rebuilds the index with a compare-and-swap:
 * when the row changed while it was embedding (enrichment landing right after an insert, the
 * items trigger reassessing an edit), it answers `409 {"success":false,"reason":"item_changed"}`
 * and whoever changed the row re-indexes it. That is deferred, not failed; iOS's
 * EmbeddingRefresher treats it the same way. Anything else is a real failure and throws.
 */
export const generateEmbeddings = async (itemId: string, textContent: string): Promise<{ deferred: boolean }> => {
  console.log('Generating embeddings for item:', itemId, 'with text length:', textContent.length);
  const { error } = await supabase.functions.invoke('generate-embeddings', {
    body: {
      itemId,
      textContent: textContent.trim()
    }
  });
  if (!error) {
    console.log('Embeddings generated successfully for item:', itemId);
    return { deferred: false };
  }
  if (isIndexDeferred(error)) {
    console.log('Embedding index deferred for item:', itemId, '(the save changed while indexing; its changer re-indexes)');
    return { deferred: true };
  }
  console.error('Error generating embeddings:', error);
  throw error;
};

// supabase-js carries the function's Response as `context` on a FunctionsHttpError
const isIndexDeferred = (error: unknown): boolean =>
  (error as { context?: { status?: number } } | null)?.context?.status === 409;

export const getSuggestedTags = async (content: any) => {
  try {
    console.log('aiOperations: Getting suggested tags', { content });
    
    const { data: result, error } = await supabase.functions.invoke('get-relevant-tags', {
      body: {
        content: content.content || content.title || content.description || '',
        type: 'suggestion'
      }
    });

    if (error) {
      console.error('aiOperations: Error from get-relevant-tags function:', error);
      return [];
    }
    
    console.log('aiOperations: Suggested tags retrieved:', result?.tags);
    return result?.tags || [];
  } catch (error) {
    console.error('aiOperations: Error getting suggested tags:', error);
    return [];
  }
};
