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

export const generateEmbeddings = async (itemId: string, textContent: string) => {
  try {
    console.log('Generating embeddings for item:', itemId, 'with text length:', textContent.length);
    
    const { error } = await supabase.functions.invoke('generate-embeddings', {
      body: {
        itemId,
        textContent: textContent.trim()
      }
    });

    if (error) {
      console.error('Error generating embeddings:', error);
      throw error;
    }
    
    console.log('Embeddings generated successfully for item:', itemId);
  } catch (error) {
    console.error('Error generating embeddings:', error);
    throw error;
  }
};

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
