
import { handleNoteIntent } from './noteHandler.ts';

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
