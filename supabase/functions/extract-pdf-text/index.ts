
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { generateSummary, stripPreamble, NO_PREAMBLE_RULES } from '../_shared/summarize.ts';

const MAX_BODY_LENGTH = 50_000;

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
    
    // Create a FormData object for file upload to OpenAI
    const formData = new FormData();
    const pdfBlob = new Blob([pdfBuffer], { type: 'application/pdf' });
    formData.append('file', pdfBlob, 'document.pdf');
    formData.append('purpose', 'user_data');

    console.log('Uploading PDF to OpenAI Files API...');

    // Upload file to OpenAI Files API
    const uploadResponse = await fetch('https://api.openai.com/v1/files', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
      },
      body: formData,
    });

    if (!uploadResponse.ok) {
      const errorData = await uploadResponse.json();
      console.error('OpenAI file upload error:', errorData);
      throw new Error(`OpenAI file upload error: ${errorData.error?.message || 'Unknown error'}`);
    }

    const uploadData = await uploadResponse.json();
    const fileId = uploadData.id;
    console.log('File uploaded successfully with ID:', fileId);

    console.log('Using OpenAI Responses API to analyze document content...');
    
    // Use OpenAI's responses API with the uploaded file ID
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
                file_id: fileId
              },
              {
                type: 'input_text',
                text: 'Extract the complete text content of this document, as close to verbatim as possible. Preserve the reading order and use markdown headings/lists only where the document itself has them. Include table contents as text. ' + NO_PREAMBLE_RULES + ' Output nothing but the document\'s own text.'
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
    console.log('OpenAI response data:', JSON.stringify(extractionData, null, 2));
    
    // Parse the OpenAI responses API structure correctly
    let extractedText = '';
    
    if (extractionData.output && Array.isArray(extractionData.output) && extractionData.output.length > 0) {
      // Handle responses API format: output[0].content[0].text
      const firstOutput = extractionData.output[0];
      if (firstOutput.content && Array.isArray(firstOutput.content) && firstOutput.content.length > 0) {
        const firstContent = firstOutput.content[0];
        if (firstContent.text) {
          extractedText = firstContent.text;
        }
      }
    } else if (extractionData.output_text) {
      // Handle direct output_text format
      extractedText = extractionData.output_text;
    } else if (extractionData.choices && extractionData.choices[0] && extractionData.choices[0].message) {
      // Handle chat completions format
      extractedText = extractionData.choices[0].message.content;
    }

    if (!extractedText || extractedText.length === 0) {
      console.error('Unable to extract text from OpenAI response. Response structure:', extractionData);
      throw new Error('No text content extracted from PDF');
    }

    extractedText = stripPreamble(extractedText).slice(0, MAX_BODY_LENGTH);
    console.log('PDF content extracted successfully, length:', extractedText.length);

    // Clean up the uploaded file (optional)
    try {
      await fetch(`https://api.openai.com/v1/files/${fileId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${openAIApiKey}`,
        },
      });
      console.log('Uploaded file cleaned up successfully');
    } catch (cleanupError) {
      console.warn('Failed to cleanup uploaded file:', cleanupError);
    }

    // Generate the full summary for the edit panel's Summary tab
    let summary: string | null = null;
    try {
      summary = await generateSummary(openAIApiKey, {
        sourceText: extractedText,
        kind: 'document',
      });
    } catch (summaryError) {
      console.error('Document summary generation failed (non-fatal):', summaryError);
    }

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
            content: 'You write short factual descriptions of documents for a card in a personal library. Describe what the document is and contains in 1-2 sentences. ' + NO_PREAMBLE_RULES
          },
          {
            role: 'user',
            content: `Document content:\n\n${extractedText.slice(0, 12_000)}`
          }
        ],
        max_tokens: 150,
        temperature: 0.1
      }),
    });

    let aiDescription = '';
    if (descriptionResponse.ok) {
      const descriptionData = await descriptionResponse.json();
      aiDescription = stripPreamble(descriptionData.choices[0].message.content ?? '');
    }
    if (!aiDescription) {
      // Fallback description if description generation fails
      aiDescription = `PDF document processed - content extracted (${Math.round(pdfBuffer.byteLength / 1024)}KB)`;
    }

    console.log('Generated description:', aiDescription);

    // Store extraction in page_body and the summary in summary. content is the
    // user's own notes and is deliberately left untouched. summary also acts as
    // the "extraction finished" marker for the processing overlay, so fall back
    // to the description if summarization failed.
    const { data: updatedItem, error: updateError } = await supabase
      .from('items')
      .update({
        page_body: extractedText,
        summary: summary || aiDescription,
        description: aiDescription,
      })
      .eq('id', itemId)
      .select('title, content, supplemental_note')
      .single();

    if (updateError) {
      console.error('Error updating item:', updateError);
      throw updateError;
    }

    console.log('Item updated successfully with extracted content');

    // Re-embed the whole item, not just the extraction — generate-embeddings
    // replaces prior chunks, so the text must carry everything searchable
    const textForEmbedding = [
      updatedItem?.title,
      aiDescription,
      summary,
      updatedItem?.content,
      updatedItem?.supplemental_note,
      extractedText,
    ].filter(Boolean).join(' ');

    const { error: embeddingError } = await supabase.functions.invoke('generate-embeddings', {
      body: {
        itemId,
        textContent: textForEmbedding
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
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
