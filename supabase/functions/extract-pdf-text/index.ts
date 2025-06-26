
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
    console.log('OpenAI response data:', JSON.stringify(extractionData, null, 2));
    
    // Check if the response has the expected structure
    let extractedText = '';
    if (extractionData.output_text) {
      extractedText = extractionData.output_text;
    } else if (extractionData.output && extractionData.output.text) {
      extractedText = extractionData.output.text;
    } else if (extractionData.choices && extractionData.choices[0] && extractionData.choices[0].message) {
      extractedText = extractionData.choices[0].message.content;
    } else {
      console.error('Unexpected response structure from OpenAI:', extractionData);
      throw new Error('Unable to extract text from OpenAI response');
    }

    if (!extractedText || extractedText.length === 0) {
      throw new Error('No text content extracted from PDF');
    }

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
