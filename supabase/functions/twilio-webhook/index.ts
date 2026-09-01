
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { corsHeaders } from './constants.ts';
import { classifyInbound } from '../_shared/intentGate.ts';
import { handleNoteIntent, handleQuestionIntent, handleCommandIntent } from './intentHandlers.ts';
import { createTwilioResponse } from './responseUtils.ts';
import type { TwilioWebhookBody } from './types.ts';

// Intent gate reply tokens (spec G2/G3). Matched against the whole message,
// normalized — a message that merely contains "save" is NOT a token.
const SAVE_TOKENS = new Set(['1', 'save', 'save it', 'keep', 'keep it', 'store', 'store it', 'note', 'note it', 'yes save']);
const ASK_TOKENS = new Set(['2', 'ask', 'answer', 'answer it', 'ask it']);
const UNDO_TOKENS = new Set(['undo', 'undo it', 'remove', 'remove it', 'delete', 'delete it']);
const PENDING_TTL_MS = 15 * 60 * 1000;

const normalizeToken = (text: string): string =>
  (text || '').trim().toLowerCase().replace(/[.!?,]+$/, '').replace(/\s+/g, ' ');

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

    // Recent exchange for the classifier (G5) — fetched BEFORE storing the
    // current message so it doesn't include itself.
    const { data: recentRows } = await supabase
      .from('sms_conversations')
      .select('message_type, content')
      .eq('user_id', userId)
      .eq('channel', channel)
      .order('created_at', { ascending: false })
      .limit(4);
    const recentMessages = (recentRows ?? [])
      .reverse()
      .map((r: { message_type: string; content: string | null }) => ({
        role: r.message_type === 'assistant' ? 'assistant' as const : 'user' as const,
        content: r.content || '',
      }));

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

    const text = messageBody || '';
    const token = normalizeToken(text);
    let responseMessage = '';
    let intent = '';
    let responsePrefix = '';

    // --- Pending round-trips (G2 confirm / G3 undo) ---------------------
    const { data: pending } = await supabase
      .from('pending_intents')
      .select('*')
      .eq('user_id', userId)
      .eq('channel', channel)
      .maybeSingle();
    const pendingFresh = pending &&
      Date.now() - new Date(pending.created_at).getTime() < PENDING_TTL_MS;
    const clearPending = async () => {
      if (pending) await supabase.from('pending_intents').delete().eq('id', pending.id);
    };

    if (pendingFresh && !mediaUrl) {
      if (pending.kind === 'confirm') {
        if (SAVE_TOKENS.has(token)) {
          await clearPending();
          const saved = await handleNoteIntent(pending.payload.text, null, null, userId, supabase, openaiApiKey || '');
          responseMessage = saved.message;
          intent = 'note';
        } else if (ASK_TOKENS.has(token)) {
          await clearPending();
          responseMessage = await handleQuestionIntent(pending.payload.text, userId, supabase, openaiApiKey || '');
          intent = 'question';
        } else {
          // They moved on. Apply the classifier's lean to the old message so
          // it isn't silently dropped (only for save-leaning content —
          // answering a stale question unprompted is noise), then fall
          // through to handle the new message normally.
          await clearPending();
          if (pending.payload.lean === 'save' && pending.payload.text) {
            await handleNoteIntent(pending.payload.text, null, null, userId, supabase, openaiApiKey || '');
            responsePrefix = '(Saved your earlier message as a note.)\n\n';
          }
        }
      } else if (pending.kind === 'undo') {
        if (UNDO_TOKENS.has(token)) {
          await clearPending();
          await supabase.from('embeddings').delete().eq('item_id', pending.payload.item_id);
          await supabase.from('items').delete().eq('id', pending.payload.item_id).eq('user_id', userId);
          responseMessage = 'Removed — it\'s gone from your stash.';
          intent = 'command';
        } else if (ASK_TOKENS.has(token) && pending.payload.original_text) {
          await clearPending();
          responseMessage = await handleQuestionIntent(pending.payload.original_text, userId, supabase, openaiApiKey || '');
          intent = 'question';
        } else {
          await clearPending(); // one-shot window; new message proceeds normally
        }
      }
    } else if (pending && !pendingFresh) {
      await clearPending();
    }

    // --- Fresh message: gate, then act (G1) ------------------------------
    if (!responseMessage) {
      const decision = await classifyInbound({
        text,
        hasMedia: Boolean(mediaUrl),
        recentMessages,
        openaiApiKey: openaiApiKey || '',
      });
      console.log('Intent gate decision:', JSON.stringify(decision));

      if (decision.intent === 'command' && decision.confidence === 'high') {
        responseMessage = await handleCommandIntent(text, userId, supabase, openaiApiKey || '');
        intent = 'command';
      } else if (decision.confidence === 'low' && !mediaUrl) {
        // Genuinely ambiguous text → ask once instead of guessing (G2).
        await supabase.from('pending_intents').upsert({
          user_id: userId,
          channel,
          phone_number: phoneNumber,
          kind: 'confirm',
          payload: { text, lean: decision.intent === 'save' ? 'save' : 'ask' },
          created_at: new Date().toISOString(),
        }, { onConflict: 'user_id,channel' });
        responseMessage = decision.intent === 'save'
          ? 'That looks like a note to save. Reply 1 to save it, or 2 if you wanted an answer.'
          : 'Not sure if you want that saved or answered. Reply 1 to save it, or 2 for an answer.';
        intent = 'clarify';
      } else if (decision.intent === 'save' || (decision.confidence === 'low' && mediaUrl)) {
        const saved = await handleNoteIntent(text, mediaUrl ?? null, mediaContentType ?? null, userId, supabase, openaiApiKey || '');
        responseMessage = saved.message;
        intent = 'note';
        // Escape hatch (G3): one word undoes or flips a wrong guess.
        if (saved.itemId) {
          await supabase.from('pending_intents').upsert({
            user_id: userId,
            channel,
            phone_number: phoneNumber,
            kind: 'undo',
            payload: { item_id: saved.itemId, original_text: text },
            created_at: new Date().toISOString(),
          }, { onConflict: 'user_id,channel' });
          responseMessage += '\n\n(Reply "undo" to remove it, or "ask" if you wanted an answer.)';
        }
      } else {
        responseMessage = await handleQuestionIntent(text, userId, supabase, openaiApiKey || '');
        intent = 'question';
        if (decision.source === 'fallback') {
          // Classifier was down; leave a path back to saving (G3 mirror).
          await supabase.from('pending_intents').upsert({
            user_id: userId,
            channel,
            phone_number: phoneNumber,
            kind: 'confirm',
            payload: { text, lean: 'save' },
            created_at: new Date().toISOString(),
          }, { onConflict: 'user_id,channel' });
          responseMessage += '\n\n(Say "save" if you wanted to keep that as a note.)';
        }
      }
    }

    responseMessage = responsePrefix + responseMessage;

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
