
import { processImage } from './imageProcessor.ts';
import { processAudio } from './audioProcessor.ts';
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

    // Handle media if present
    if (mediaUrl && mediaContentType) {
      if (mediaContentType.startsWith('image/')) {
        processedMedia = await processImage(mediaUrl, openaiApiKey);
      } else if (mediaContentType.startsWith('audio/')) {
        processedMedia = await processAudio(mediaUrl, openaiApiKey);
      }
      
      if (processedMedia) {
        contentToSave = contentToSave ? `${contentToSave}\n\n${processedMedia}` : processedMedia;
      }
    }

    // Save to items table using the existing content processor pattern
    const { data: item, error } = await supabase
      .from('items')
      .insert({
        user_id: userId,
        type: 'text',
        content: contentToSave,
        title: generateTitleFromContent(contentToSave),
        file_path: mediaUrl || null,
        mime_type: mediaContentType || null
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
    return processedMedia ? `${randomMessage} ${processedMedia.substring(0, 100)}...` : randomMessage;

  } catch (error) {
    console.error('Error handling note intent:', error);
    return 'Sorry, I couldn\'t save that note. Please try again.';
  }
}

export async function handleQuestionIntent(message: string, supabase: any): Promise<string> {
  try {
    // Use the existing chat function to search and respond
    const { data, error } = await supabase.functions.invoke('chat-with-all-content', {
      body: {
        message,
        conversationId: null // New conversation for each SMS
      }
    });

    if (error) throw error;

    return data.response || "I couldn't find relevant information to answer your question.";

  } catch (error) {
    console.error('Error handling question intent:', error);
    return 'Sorry, I couldn\'t search your content right now. Please try again later.';
  }
}

export async function handleCommandIntent(
  message: string, 
  userId: string,
  supabase: any,
  openaiApiKey: string
): Promise<string> {
  const lowerMessage = message.toLowerCase();

  if (lowerMessage.includes('help')) {
    return `Hi! I can help you save notes and answer questions about your saved content.

💾 To save: Just tell me what to remember
❓ To search: Ask me questions about your saved content
📱 I can also process images and audio you send!

Try saying "remember to call mom" or "what did I save about meetings?"`;
  }

  if (lowerMessage.includes('delete') || lowerMessage.includes('remove')) {
    return 'I can\'t delete specific items via SMS yet, but you can manage your content in the web app.';
  }

  // Default: treat unclear commands as notes
  return await handleNoteIntent(message, null, null, userId, supabase, openaiApiKey);
}

function generateTitleFromContent(content: string): string {
  if (!content) return 'SMS Note';
  
  // Take first 50 characters and clean up
  const title = content.substring(0, 50).replace(/\n/g, ' ').trim();
  return title + (content.length > 50 ? '...' : '');
}
