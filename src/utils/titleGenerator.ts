
import { supabase } from '@/integrations/supabase/client';

export const generateTitle = async (content: string, type: string): Promise<string> => {
  try {
    const { data: result, error } = await supabase.functions.invoke('generate-title', {
      body: { content }
    });

    if (error) throw error;
    return result.title || 'Untitled Note';
  } catch (error) {
    console.error('Error generating title:', error);
    // Fallback to a simple title based on content
    if (type === 'text' && content) {
      const plainText = content.length > 50 ? content.substring(0, 47) + '...' : content;
      return plainText || 'Untitled Note';
    }
    return 'Untitled Note';
  }
};
