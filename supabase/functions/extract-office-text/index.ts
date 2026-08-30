import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { unzipSync } from 'https://esm.sh/fflate@0.8.2';
import { generateSummary, stripPreamble, NO_PREAMBLE_RULES } from '../_shared/summarize.ts';
import { capTitle, isPlaceholderTitle } from '../_shared/titlePolicy.ts';

// Office Open XML files (pptx/docx/xlsx) are ZIP archives of XML — text
// extraction needs no external parser: unzip, collect the text runs, done.
// Mirrors extract-pdf-text's contract: writes page_body + summary +
// description, then re-embeds the whole item.

const MAX_BODY_LENGTH = 50_000;
const MAX_FILE_BYTES = 40 * 1024 * 1024;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

type OfficeKind = 'pptx' | 'docx' | 'xlsx';

const KIND_BY_MIME: Record<string, OfficeKind> = {
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
};

const detectKind = (mimeType?: string, fileName?: string): OfficeKind | null => {
  if (mimeType && KIND_BY_MIME[mimeType]) return KIND_BY_MIME[mimeType];
  const ext = fileName?.toLowerCase().split('.').pop();
  if (ext === 'pptx' || ext === 'docx' || ext === 'xlsx') return ext;
  return null;
};

const decodeEntities = (text: string): string =>
  text
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');

const collectRuns = (xml: string, tagPattern: RegExp): string => {
  const runs: string[] = [];
  let match: RegExpExecArray | null;
  while ((match = tagPattern.exec(xml)) !== null) {
    const run = decodeEntities(match[1]);
    if (run.trim().length > 0) runs.push(run);
  }
  return runs.join(' ').replace(/\s+/g, ' ').trim();
};

const numberedEntries = (files: Record<string, Uint8Array>, pattern: RegExp): string[] => {
  const decoder = new TextDecoder('utf-8');
  return Object.keys(files)
    .filter((name) => pattern.test(name))
    .sort((a, b) => {
      const numA = parseInt(a.match(/(\d+)\.xml$/)?.[1] ?? '0', 10);
      const numB = parseInt(b.match(/(\d+)\.xml$/)?.[1] ?? '0', 10);
      return numA - numB;
    })
    .map((name) => decoder.decode(files[name]));
};

const extractPptx = (files: Record<string, Uint8Array>): string => {
  const slideXmls = numberedEntries(files, /^ppt\/slides\/slide\d+\.xml$/);
  const noteXmls = numberedEntries(files, /^ppt\/notesSlides\/notesSlide\d+\.xml$/);

  const slides = slideXmls
    .map((xml, index) => {
      const text = collectRuns(xml, /<a:t[^>]*>([\s\S]*?)<\/a:t>/g);
      return text ? `Slide ${index + 1}: ${text}` : '';
    })
    .filter(Boolean);

  const notes = noteXmls
    .map((xml, index) => {
      const text = collectRuns(xml, /<a:t[^>]*>([\s\S]*?)<\/a:t>/g)
        // Notes slides embed the slide number as a text run; drop pure numbers
        .replace(/\s*\b\d+\b\s*$/, '')
        .trim();
      return text ? `Slide ${index + 1} notes: ${text}` : '';
    })
    .filter(Boolean);

  return [...slides, ...(notes.length ? ['', 'Speaker notes:', ...notes] : [])].join('\n');
};

const extractDocx = (files: Record<string, Uint8Array>): string => {
  const xml = files['word/document.xml']
    ? new TextDecoder('utf-8').decode(files['word/document.xml'])
    : '';
  if (!xml) return '';
  return xml
    .split(/<\/w:p>/)
    .map((paragraph) => collectRuns(paragraph, /<w:t[^>]*>([\s\S]*?)<\/w:t>/g))
    .filter(Boolean)
    .join('\n');
};

const extractXlsx = (files: Record<string, Uint8Array>): string => {
  const decoder = new TextDecoder('utf-8');
  const workbookXml = files['xl/workbook.xml'] ? decoder.decode(files['xl/workbook.xml']) : '';
  const sheetNames: string[] = [];
  let sheetMatch: RegExpExecArray | null;
  const sheetPattern = /<sheet[^>]*name="([^"]+)"/g;
  while ((sheetMatch = sheetPattern.exec(workbookXml)) !== null) {
    sheetNames.push(decodeEntities(sheetMatch[1]));
  }

  const sharedXml = files['xl/sharedStrings.xml'] ? decoder.decode(files['xl/sharedStrings.xml']) : '';
  const strings = collectRuns(sharedXml, /<t[^>]*>([\s\S]*?)<\/t>/g);

  return [sheetNames.length ? `Sheets: ${sheetNames.join(', ')}` : '', strings]
    .filter(Boolean)
    .join('\n');
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { fileUrl, itemId, fileName, mimeType } = await req.json();
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');

    if (!supabaseUrl || !supabaseKey) throw new Error('Missing Supabase configuration');
    if (!openAIApiKey) throw new Error('Missing OpenAI API key');
    if (!fileUrl || !itemId) throw new Error('fileUrl and itemId are required');

    const kind = detectKind(mimeType, fileName);
    if (!kind) {
      return new Response(JSON.stringify({ success: false, reason: 'unsupported-format' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    console.log('Extracting office text:', { itemId, kind, fileName });

    const response = await fetch(fileUrl);
    if (!response.ok) throw new Error('Failed to fetch office file');
    const buffer = await response.arrayBuffer();
    if (buffer.byteLength > MAX_FILE_BYTES) throw new Error('File too large to extract');

    const files = unzipSync(new Uint8Array(buffer));
    const rawText =
      kind === 'pptx' ? extractPptx(files) : kind === 'docx' ? extractDocx(files) : extractXlsx(files);

    const extractedText = rawText.slice(0, MAX_BODY_LENGTH).trim();
    if (!extractedText) {
      // Image-only decks etc. — leave the item as the client settled it
      console.log('No text runs found in file:', { itemId, kind });
      return new Response(JSON.stringify({ success: false, reason: 'no-text' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    console.log('Office text extracted:', { itemId, kind, length: extractedText.length });

    // Full summary for the edit panel's Summary tab
    let summary: string | null = null;
    try {
      summary = await generateSummary(openAIApiKey, {
        sourceText: extractedText,
        kind: 'document',
      });
    } catch (summaryError) {
      console.error('Office summary generation failed (non-fatal):', summaryError);
    }

    // Concise card description from the real content
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
          { role: 'user', content: `Document content:\n\n${extractedText.slice(0, 12_000)}` }
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

    // Title policy (_shared/titlePolicy.ts): clients pre-write the filename as
    // the title. When it is still that placeholder (filename-shaped/empty),
    // derive a real title from the extracted content; a real user title is
    // never touched. If the pre-check fetch fails, be conservative and skip
    // the title write.
    let aiTitle: string | null = null;
    const { data: currentItem, error: currentError } = await supabase
      .from('items')
      .select('title, file_path')
      .eq('id', itemId)
      .single();
    if (currentError) {
      console.error('Error fetching item before office title write (skipping title):', currentError);
    } else if (isPlaceholderTitle(currentItem?.title, currentItem?.file_path)) {
      try {
        const titleResponse = await fetch('https://api.openai.com/v1/chat/completions', {
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
                content:
                  "You title documents for the user's personal library from their extracted text. " +
                  'Write a specific, descriptive title of 5-10 words. ' +
                  NO_PREAMBLE_RULES,
              },
              { role: 'user', content: `Document content:\n\n${extractedText.slice(0, 1500)}` },
            ],
            max_tokens: 40,
            temperature: 0.2,
          }),
        });
        if (titleResponse.ok) {
          const titleData = await titleResponse.json();
          const raw = stripPreamble(titleData.choices?.[0]?.message?.content?.trim() ?? '');
          if (raw) aiTitle = capTitle(raw);
        } else {
          console.error('Office title generation failed:', titleResponse.status, await titleResponse.text());
        }
      } catch (titleError) {
        console.error('Office title generation failed (non-fatal):', titleError);
      }
    }

    // Store extraction in page_body and the summary in summary. content is the
    // user's own notes and is deliberately left untouched. Only overwrite the
    // description when we produced a content-based one.
    const updates: Record<string, string> = {
      page_body: extractedText,
      summary: summary || aiDescription || extractedText.slice(0, 300),
    };
    if (aiDescription) updates.description = aiDescription;
    if (aiTitle) updates.title = aiTitle;

    const { data: updatedItem, error: updateError } = await supabase
      .from('items')
      .update(updates)
      .eq('id', itemId)
      .select('title, content, supplemental_note, description')
      .single();

    if (updateError) throw updateError;

    // Re-embed the whole item, not just the extraction — generate-embeddings
    // replaces prior chunks, so the text must carry everything searchable
    const textForEmbedding = [
      updatedItem?.title,
      updatedItem?.description,
      summary,
      updatedItem?.content,
      updatedItem?.supplemental_note,
      extractedText,
    ].filter(Boolean).join(' ');

    const { error: embeddingError } = await supabase.functions.invoke('generate-embeddings', {
      body: { itemId, textContent: textForEmbedding }
    });

    if (embeddingError) {
      console.error('Failed to generate embeddings:', embeddingError);
    }

    return new Response(JSON.stringify({
      success: true,
      kind,
      textLength: extractedText.length,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error extracting office text:', error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
