
import { processImage } from './imageProcessor.ts';
import { processAudio } from './audioProcessor.ts';
import { processVideo } from './videoProcessor.ts';
import { saveMediaToStorage } from './mediaStorage.ts';
import { successMessages } from './constants.ts';

export interface NoteResult {
  message: string;
  itemId: string | null;
}

const BARE_URL_RE = /(https?:\/\/[^\s]+)/i;

export async function handleNoteIntent(
  message: string,
  mediaUrl: string | null,
  mediaContentType: string | null,
  userId: string,
  supabase: any,
  openaiApiKey: string
): Promise<NoteResult> {
  try {
    let contentToSave = message || '';
    let processedMedia = '';
    let savedMediaPath = null;

    // A texted link becomes a real link item (title/page text/embeddings via
    // scrape-page-content), not a plain text note — same object the web
    // paste-capture produces. Any short caption around the URL is kept as the
    // user's own words in `content`.
    const urlMatch = !mediaUrl ? (message || '').match(BARE_URL_RE) : null;
    if (urlMatch) {
      const url = urlMatch[0].replace(/[)\].,!?;:]+$/, '');
      const caption = (message || '').replace(urlMatch[0], ' ').replace(/\s+/g, ' ').trim();
      if (caption.length < 200) {
        const { data: linkItem, error: linkError } = await supabase
          .from('items')
          .insert({
            user_id: userId,
            type: 'link',
            url,
            title: caption || url,
            content: caption || null,
          })
          .select()
          .single();
        if (!linkError && linkItem) {
          try {
            await supabase.functions.invoke('scrape-page-content', {
              body: { itemId: linkItem.id, url },
            });
          } catch (scrapeError) {
            console.error('SMS link scrape failed (item still saved):', scrapeError);
          }
          return { message: 'Link saved! 🔗 I\'m fetching the page details now.', itemId: linkItem.id };
        }
        console.error('SMS link item insert failed, falling back to text note:', linkError);
      }
    }

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
      } else if (mediaContentType.startsWith('video/')) {
        processedMedia = await processVideo(mediaUrl, openaiApiKey);
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
    } else if (mediaContentType?.startsWith('video/')) {
      itemType = 'video';
    }

    // Save to items table
    const { data: item, error } = await supabase
      .from('items')
      .insert({
        user_id: userId,
        type: itemType,
        content: contentToSave,
        title: generateTitleFromContent(contentToSave, itemType),
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
      return { message: `${randomMessage} ${processedMedia.substring(0, 100)}...`, itemId: item.id };
    } else if (savedMediaPath) {
      return { message: `${randomMessage} Media saved successfully!`, itemId: item.id };
    } else {
      return { message: randomMessage, itemId: item.id };
    }

  } catch (error) {
    console.error('Error handling note intent:', error);
    return { message: 'Sorry, I couldn\'t save that note. Please try again.', itemId: null };
  }
}

function generateTitleFromContent(content: string, itemType: string = 'text'): string {
  if (!content) {
    // Generate appropriate default titles based on type
    switch (itemType) {
      case 'video':
        return 'Video Note';
      case 'audio':
        return 'Audio Note';
      case 'image':
        return 'Image Note';
      default:
        return 'SMS Note';
    }
  }
  
  // Take first 50 characters and clean up
  const title = content.substring(0, 50).replace(/\n/g, ' ').trim();
  return title + (content.length > 50 ? '...' : '');
}
