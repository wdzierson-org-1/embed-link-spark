import { supabase } from '@/integrations/supabase/client';
import { generateDescription } from './aiOperations';

interface MediaProcessingResult {
  title?: string;
  description?: string;
  content?: string;
}

export const processMediaAttachment = async (
  filePath: string,
  type: string,
  originalFileName?: string
): Promise<MediaProcessingResult> => {
  try {
    // Get public URL for the file
    const { data: urlData } = supabase.storage
      .from('stash-media')
      .getPublicUrl(filePath);

    if (!urlData?.publicUrl) {
      throw new Error('Failed to get file URL');
    }

    const publicUrl = urlData.publicUrl;
    console.log(`Processing ${type} media:`, publicUrl);

    switch (type) {
      case 'image':
        return await processImageAttachment(publicUrl, originalFileName);
      
      case 'audio':
        return await processAudioAttachment(publicUrl, originalFileName);
      
      case 'video':
        // For now, return basic info - video processing can be enhanced later
        return {
          title: originalFileName || 'Video file',
          description: 'Video content - transcription not yet available',
          content: originalFileName || 'Video file'
        };
      
      default:
        return {
          title: originalFileName || 'File',
          description: `${type} file`,
          content: originalFileName || 'File'
        };
    }
  } catch (error) {
    console.error(`Error processing ${type} attachment:`, error);
    return {
      title: originalFileName || 'File',
      description: `Error processing ${type} file`,
      content: originalFileName || 'File'
    };
  }
};

const processImageAttachment = async (
  publicUrl: string,
  originalFileName?: string
): Promise<MediaProcessingResult> => {
  try {
    // Use AI to describe the image
    const aiDescription = await generateDescription('image', {
      fileData: publicUrl,
      content: originalFileName || 'Image file'
    });

    const title = originalFileName || 'Image';
    const description = aiDescription || 'Image content';

    return {
      title,
      description,
      content: `${title}: ${description}`
    };
  } catch (error) {
    console.error('Error processing image attachment:', error);
    return {
      title: originalFileName || 'Image',
      description: 'Image content',
      content: originalFileName || 'Image'
    };
  }
};

const processAudioAttachment = async (
  publicUrl: string,
  originalFileName?: string
): Promise<MediaProcessingResult> => {
  try {
    // Call transcription function
    const { data: result, error } = await supabase.functions.invoke('transcribe-audio', {
      body: {
        audioUrl: publicUrl,
        fileName: originalFileName || 'audio.mp3'
      }
    });

    if (error) {
      console.error('Transcription error:', error);
      throw error;
    }

    const transcription = result?.transcription || '';
    const summary = result?.description || '';
    
    const title = originalFileName || 'Audio recording';
    const description = summary || transcription || 'Audio content';

    return {
      title,
      description,
      content: `${title}: ${transcription}`
    };
  } catch (error) {
    console.error('Error processing audio attachment:', error);
    return {
      title: originalFileName || 'Audio recording',
      description: 'Audio content - transcription not available',
      content: originalFileName || 'Audio recording'
    };
  }
};

export const extractTextFromMediaResult = (result: MediaProcessingResult): string => {
  return result.content || result.description || result.title || '';
};