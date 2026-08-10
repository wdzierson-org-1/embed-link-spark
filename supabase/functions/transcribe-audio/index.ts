import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { stripPreamble, NO_PREAMBLE_RULES } from '../_shared/summarize.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { audioUrl, fileName } = await req.json();
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');

    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }

    if (!audioUrl) {
      throw new Error('Audio URL is required');
    }

    console.log('Transcribing audio from URL:', audioUrl);

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
    formData.append('file', audioBlob, fileName || 'audio.webm');
    formData.append('model', 'whisper-1');
    formData.append('response_format', 'text');

    // Send to OpenAI Whisper API
    const transcriptionResponse = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
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
      return new Response(JSON.stringify({ 
        transcription: '',
        description: 'Audio was processed but no speech was detected.'
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Generate a summary description of the audio content
    const summaryResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: 'You summarize transcribed recordings (audio or video) for a card in a personal library. Keep the summary under 100 words, covering the main topics and key points. ' + NO_PREAMBLE_RULES
          },
          {
            role: 'user',
            content: `Transcript:\n\n${transcriptionResult.trim()}`
          }
        ],
        max_tokens: 150,
        temperature: 0.3,
      }),
    });

    const summaryData = await summaryResponse.json();
    const rawDescription = summaryData.choices?.[0]?.message?.content?.trim();
    const description = rawDescription ? stripPreamble(rawDescription) : 'Transcription available';

    return new Response(JSON.stringify({ 
      transcription: transcriptionResult.trim(),
      description 
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Error transcribing audio:', error);
    return new Response(JSON.stringify({ 
      error: error instanceof Error ? error.message : 'Unknown error',
      transcription: '',
      description: 'Audio received but transcription failed. Please try again.'
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});