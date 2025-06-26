import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Initialize Supabase client with service role for admin operations
const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Twilio credentials
const twilioAccountSid = Deno.env.get('TWILIO_ACCOUNT_SID');
const twilioAuthToken = Deno.env.get('TWILIO_AUTH_TOKEN');
const twilioWebhookUrl = Deno.env.get('TWILIO_WEBHOOK_URL');
const openaiApiKey = Deno.env.get('OPENAI_API_KEY');

const successMessages = [
  "Got it! ✓",
  "Saved! 📝",
  "Noted! ✨",
  "Added to your stash! 🗂️",
  "Captured! 💾"
];

serve(async (req) => {
  console.log('Twilio webhook called:', req.method);
  
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Parse form data from Twilio
    const formData = await req.formData();
    const body = Object.fromEntries(formData.entries());
    
    console.log('Received Twilio webhook:', body);

    // Extract Twilio parameters
    const {
      Body: messageBody,
      From: from,
      To: to,
      MediaUrl0: mediaUrl,
      MediaContentType0: mediaContentType
    } = body;

    // Determine channel and clean phone number
    const channel = to.toString().includes('whatsapp') ? 'whatsapp' : 'sms';
    const phoneNumber = from.toString().replace('whatsapp:', '').replace('+', '');
    
    console.log(`Message from ${phoneNumber} via ${channel}: ${messageBody}`);

    // Find user by phone number
    const { data: phoneRecord, error: phoneError } = await supabase
      .from('user_phone_numbers')
      .select('user_id')
      .eq('phone_number', phoneNumber)
      .single();

    if (phoneError || !phoneRecord) {
      console.log('User not found for phone number:', phoneNumber);
      return createTwilioResponse('Hi! To use this service, please first register your phone number in the app at your account settings.', channel);
    }

    const userId = phoneRecord.user_id;
    console.log('Found user:', userId);

    // Store incoming message
    await supabase
      .from('sms_conversations')
      .insert({
        user_id: userId,
        phone_number: phoneNumber,
        channel,
        message_type: 'user',
        content: messageBody || '',
        media_url: mediaUrl || null,
        media_type: mediaContentType || null
      });

    // Classify intent using AI
    const intent = await classifyIntent(messageBody || '');
    console.log('Classified intent:', intent);

    let responseMessage = '';

    if (intent === 'note') {
      // Handle as a note to save
      responseMessage = await handleNoteIntent(messageBody, mediaUrl, mediaContentType, userId);
    } else if (intent === 'question') {
      // Handle as a question to answer
      responseMessage = await handleQuestionIntent(messageBody, userId);
    } else {
      // Handle as command or unclear intent
      responseMessage = await handleCommandIntent(messageBody, userId);
    }

    // Store assistant response
    await supabase
      .from('sms_conversations')
      .insert({
        user_id: userId,
        phone_number: phoneNumber,
        channel,
        message_type: 'assistant',
        content: responseMessage,
        intent
      });

    return createTwilioResponse(responseMessage, channel);

  } catch (error) {
    console.error('Error processing Twilio webhook:', error);
    return createTwilioResponse('Sorry, something went wrong. Please try again later.', 'sms');
  }
});

async function classifyIntent(message: string): Promise<string> {
  if (!message || !openaiApiKey) return 'note';

  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `You are an intent classifier for a personal knowledge management system. Classify the user's message into one of these categories:

- "note": User wants to save information (e.g., "remember to call Dr. Green", "buy milk tomorrow", "meeting at 3pm")
- "question": User is asking about previously saved information (e.g., "what did I say about the meeting?", "when is my appointment?")
- "command": User wants to perform an action (e.g., "delete my last note", "show me my tasks")

Respond with only the category name: note, question, or command.`
          },
          {
            role: 'user',
            content: message
          }
        ],
        max_tokens: 10,
        temperature: 0.1
      }),
    });

    const data = await response.json();
    const intent = data.choices[0]?.message?.content?.trim().toLowerCase();
    
    return ['note', 'question', 'command'].includes(intent) ? intent : 'note';
  } catch (error) {
    console.error('Error classifying intent:', error);
    return 'note'; // Default to note if classification fails
  }
}

async function handleNoteIntent(message: string, mediaUrl: string | null, mediaContentType: string | null, userId: string): Promise<string> {
  try {
    let contentToSave = message || '';
    let processedMedia = '';

    // Handle media if present
    if (mediaUrl && mediaContentType) {
      if (mediaContentType.startsWith('image/')) {
        processedMedia = await processImage(mediaUrl);
      } else if (mediaContentType.startsWith('audio/')) {
        processedMedia = await processAudio(mediaUrl);
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

async function handleQuestionIntent(message: string, userId: string): Promise<string> {
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

async function handleCommandIntent(message: string, userId: string): Promise<string> {
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
  return await handleNoteIntent(message, null, null, userId);
}

async function processImage(imageUrl: string): Promise<string> {
  if (!openaiApiKey) return '';

  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'user',
            content: [
              { 
                type: 'text', 
                text: 'Describe what you see in this image. Extract any text if present. Be concise but thorough.'
              },
              {
                type: 'image_url',
                image_url: { url: imageUrl }
              }
            ]
          }
        ],
        max_tokens: 300
      }),
    });

    const data = await response.json();
    return data.choices[0]?.message?.content || '';
  } catch (error) {
    console.error('Error processing image:', error);
    return 'Image received but could not be processed.';
  }
}

async function processAudio(audioUrl: string): Promise<string> {
  if (!openaiApiKey) {
    return 'Audio received but transcription is not available.';
  }

  try {
    console.log('Processing audio from URL:', audioUrl);

    // Download the audio file
    const audioResponse = await fetch(audioUrl);
    if (!audioResponse.ok) {
      throw new Error(`Failed to download audio: ${audioResponse.status}`);
    }

    const audioArrayBuffer = await audioResponse.arrayBuffer();
    const audioBlob = new Blob([audioArrayBuffer]);
    
    console.log('Audio file downloaded, size:', audioBlob.size);

    // Prepare form data for Whisper API
    const formData = new FormData();
    formData.append('file', audioBlob, 'audio.webm');
    formData.append('model', 'whisper-1');
    formData.append('response_format', 'text');

    // Send to OpenAI Whisper API
    const transcriptionResponse = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
      },
      body: formData,
    });

    if (!transcriptionResponse.ok) {
      const errorText = await transcriptionResponse.text();
      console.error('Whisper API error:', errorText);
      throw new Error(`Whisper API error: ${transcriptionResponse.status}`);
    }

    const transcriptionResult = await transcriptionResponse.text();
    console.log('Transcription result:', transcriptionResult);

    if (!transcriptionResult || transcriptionResult.trim() === '') {
      return 'Audio was processed but no speech was detected.';
    }

    return `Audio transcription: "${transcriptionResult.trim()}"`;

  } catch (error) {
    console.error('Error processing audio:', error);
    return 'Audio received but transcription failed. Please try again.';
  }
}

function generateTitleFromContent(content: string): string {
  if (!content) return 'SMS Note';
  
  // Take first 50 characters and clean up
  const title = content.substring(0, 50).replace(/\n/g, ' ').trim();
  return title + (content.length > 50 ? '...' : '');
}

function createTwilioResponse(message: string, channel: string): Response {
  const twiml = `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Message>${escapeXml(message)}</Message>
</Response>`;

  return new Response(twiml, {
    headers: {
      'Content-Type': 'text/xml',
      ...corsHeaders
    }
  });
}

function escapeXml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
