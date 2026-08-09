
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

// Validate that the request genuinely came from Twilio (HMAC-SHA1 over the
// webhook URL + sorted form params, signed with the auth token). Without this,
// anyone who knows a user's phone number could inject items into their stash.
const validateTwilioSignature = async (
  req: Request,
  params: Record<string, string>
): Promise<boolean> => {
  const authToken = Deno.env.get('TWILIO_AUTH_TOKEN');
  const signature = req.headers.get('X-Twilio-Signature');
  if (!authToken || !signature) return false;

  // Twilio signs the URL as configured in the console; fall back to the
  // request URL in case they differ (proxies, trailing slashes)
  const candidateUrls = [Deno.env.get('TWILIO_WEBHOOK_URL'), req.url]
    .filter((u): u is string => Boolean(u));

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(authToken),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign']
  );

  const sortedKeys = Object.keys(params).sort();
  for (const url of candidateUrls) {
    let data = url;
    for (const k of sortedKeys) {
      data += k + params[k];
    }
    const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(data));
    const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));
    if (expected === signature) return true;
  }

  console.error('Twilio signature validation failed for URL candidates:', candidateUrls.length);
  return false;
};

serve(async (req) => {
  console.log('Twilio webhook called:', req.method);

  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Parse form data from Twilio
    const formData = await req.formData();
    const body = Object.fromEntries(formData.entries()) as unknown as TwilioWebhookBody;

    console.log('Received Twilio webhook:', body);

    const params = Object.fromEntries(
      [...formData.entries()].map(([k, v]) => [k, String(v)])
    );
    if (!(await validateTwilioSignature(req, params))) {
      return new Response('Forbidden', { status: 403 });
    }

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
      responseMessage = await handleNoteIntent(messageBody, mediaUrl ?? null, mediaContentType ?? null, userId, supabase, openaiApiKey || '');
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
