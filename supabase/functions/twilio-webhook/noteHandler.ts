
import { processImage } from './imageProcessor.ts';
import { processAudio } from './audioProcessor.ts';
import { saveMediaToStorage } from './mediaStorage.ts';
import { successMessages } from './constants.ts';

export async function handleNoteIntent(
  message: string, 
  mediaUrl: string | null, 
  mediaContentType: string | null, 
  userId: string,
  supabase: any,
  openaiApiKey: string
): Promise<string> {
  try {
    let contentToSave = message || '';
    let processedMedia = '';
    let savedMediaPath = null;

    // Handle media if present
    if (mediaUrl && mediaContentType) {
      console.log('Processing media:', mediaContentType, mediaUrl);
      
      // Save original media to storage
      savedMediaPath = await saveMediaToStorage(mediaUrl, mediaContentType, userId, supabase);
      
      // Process media with AI
      if (mediaContentType.startsWith('image/')) {
        processedMedia = await processImage(mediaUrl, openaiApiKey);
      } else if (mediaContentType.startsWith('audio/')) {
        processedMedia = await processAudio(mediaUrl, openaiApiKey);
      }
      
      if (processedMedia) {
        contentToSave = contentToSave ? `${contentToSave}\n\n${processedMedia}` : processedMedia;
      }
    }

    // Determine item type based on media
    let itemType = 'text';
    if (mediaContentType?.startsWith('image/')) {
      itemType = 'image';
    } else if (mediaContentType?.startsWith('audio/')) {
      itemType = 'audio';
    }

    // Save to items table
    const { data: item, error } = await supabase
      .from('items')
      .insert({
        user_id: userId,
        type: itemType,
        content: contentToSave,
        title: generateTitleFromContent(contentToSave),
        file_path: savedMediaPath,
        mime_type: mediaContentType || null,
        description: processedMedia || null
      })
      .select()
      .single();

    if (error) throw error;

    // Generate embeddings for the content
    if (contentToSave.trim()) {
      try {
        await supabase.functions.invoke('generate-embeddings', {
          body: {
            itemId: item.id,
            textContent: contentToSave
          }
        });
      } catch (embeddingError) {
        console.error('Error generating embeddings:', embeddingError);
      }
    }

    const randomMessage = successMessages[Math.floor(Math.random() * successMessages.length)];
    
    if (processedMedia) {
      return `${randomMessage} ${processedMedia.substring(0, 100)}...`;
    } else if (savedMediaPath) {
      return `${randomMessage} Media saved successfully!`;
    } else {
      return randomMessage;
    }

  } catch (error) {
    console.error('Error handling note intent:', error);
    return 'Sorry, I couldn\'t save that note. Please try again.';
  }
}

function generateTitleFromContent(content: string): string {
  if (!content) return 'SMS Note';
  
  // Take first 50 characters and clean up
  const title = content.substring(0, 50).replace(/\n/g, ' ').trim();
  return title + (content.length > 50 ? '...' : '');
}
