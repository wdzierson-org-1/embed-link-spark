
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { fileUrl, itemId } = await req.json();
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');

    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Missing Supabase configuration');
    }

    if (!openAIApiKey) {
      throw new Error('Missing OpenAI API key');
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    console.log('Starting PDF processing for item:', itemId, 'with URL:', fileUrl);

    // Fetch the PDF file
    const response = await fetch(fileUrl);
    if (!response.ok) {
      throw new Error('Failed to fetch PDF file');
    }

    const pdfBuffer = await response.arrayBuffer();
    console.log('PDF fetched successfully, size:', pdfBuffer.byteLength, 'bytes');
    
    // Convert to base64 safely for large files
    const uint8Array = new Uint8Array(pdfBuffer);
    let base64String = '';
    const chunkSize = 1024;
    
    for (let i = 0; i < uint8Array.length; i += chunkSize) {
      const chunk = uint8Array.slice(i, i + chunkSize);
      base64String += btoa(String.fromCharCode.apply(null, Array.from(chunk)));
    }
    
    console.log('Using OpenAI PDF input API to analyze document content...');
    
    // Use OpenAI's new PDF input API with the responses endpoint
    const extractionResponse = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        input: [
          {
            role: 'user',
            content: [
              {
                type: 'input_file',
                filename: 'document.pdf',
                file_data: `data:application/pdf;base64,${base64String}`
              },
              {
                type: 'input_text',
                text: 'Please extract and analyze the complete content from this PDF document. Provide:\n1. Document type and main purpose\n2. Key sections and topics covered\n3. Important details, terms, or data points\n4. Main conclusions or outcomes\n\nBase your analysis ONLY on the actual content visible in the document. Be comprehensive and accurate.'
              }
            ]
          }
        ]
      }),
    });

    if (!extractionResponse.ok) {
      const errorData = await extractionResponse.json();
      console.error('OpenAI API error:', errorData);
      throw new Error(`OpenAI API error: ${errorData.error?.message || 'Unknown error'}`);
    }

    const extractionData = await extractionResponse.json();
    const extractedText = extractionData.output_text;

    console.log('PDF content extracted successfully, length:', extractedText.length);

    // Generate a concise description based on the extracted content
    const descriptionResponse = await fetch('https://api.openai.com/v1/chat/completions', {
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
            content: 'You are a document summarization expert. Create concise, accurate descriptions based on actual document content.'
          },
          {
            role: 'user',
            content: `Based on this document analysis, create a brief 2-3 line description that accurately describes what this document contains:\n\n${extractedText}`
          }
        ],
        max_tokens: 150,
        temperature: 0.1
      }),
    });

    let aiDescription = '';
    if (descriptionResponse.ok) {
      const descriptionData = await descriptionResponse.json();
      aiDescription = descriptionData.choices[0].message.content;
    } else {
      // Fallback description if description generation fails
      aiDescription = `PDF document processed - content extracted and analyzed (${Math.round(pdfBuffer.byteLength / 1024)}KB)`;
    }

    console.log('Generated description:', aiDescription);

    // Update the item with extracted content and description
    const { error: updateError } = await supabase
      .from('items')
      .update({
        content: extractedText,
        description: aiDescription
      })
      .eq('id', itemId);

    if (updateError) {
      console.error('Error updating item:', updateError);
      throw updateError;
    }

    console.log('Item updated successfully with extracted content');

    // Generate embeddings for the extracted text
    const { error: embeddingError } = await supabase.functions.invoke('generate-embeddings', {
      body: {
        itemId,
        textContent: extractedText
      }
    });

    if (embeddingError) {
      console.error('Failed to generate embeddings:', embeddingError);
    } else {
      console.log('Embeddings generated successfully');
    }

    return new Response(JSON.stringify({ 
      success: true, 
      extractedText,
      textLength: extractedText.length,
      message: 'PDF processed successfully with actual content extraction'
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error extracting PDF text:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
