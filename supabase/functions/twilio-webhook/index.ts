
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { corsHeaders } from './constants.ts';
import { classifyIntent } from './intentClassifier.ts';
import { handleNoteIntent, handleQuestionIntent, handleCommandIntent } from './intentHandlers.ts';
import { createTwilioResponse } from './responseUtils.ts';
import type { TwilioWebhookBody } from './types.ts';

// Initialize Supabase client with service role for admin operations
const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// API keys
const openaiApiKey = Deno.env.get('OPENAI_API_KEY');

serve(async (req) => {
  console.log('Twilio webhook called:', req.method);
  
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Parse form data from Twilio
    const formData = await req.formData();
    const body = Object.fromEntries(formData.entries()) as TwilioWebhookBody;
    
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
    const intent = await classifyIntent(messageBody || '', openaiApiKey || '');
    console.log('Classified intent:', intent);

    let responseMessage = '';

    if (intent === 'note') {
      // Handle as a note to save
      responseMessage = await handleNoteIntent(messageBody, mediaUrl, mediaContentType, userId, supabase, openaiApiKey || '');
    } else if (intent === 'question') {
      // Handle as a question to answer - now with proper implementation
      responseMessage = await handleQuestionIntent(messageBody, userId, supabase, openaiApiKey || '');
    } else {
      // Handle as command or unclear intent
      responseMessage = await handleCommandIntent(messageBody, userId, supabase, openaiApiKey || '');
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
