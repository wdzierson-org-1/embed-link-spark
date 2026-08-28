
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { encode as encodeBase64 } from "https://deno.land/std@0.168.0/encoding/base64.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// OpenAI Vision only accepts png/jpeg/gif/webp. Clients legitimately store
// other formats (avif from the extension, heic from iOS, svg, …); for those,
// Supabase Storage's render endpoint transcodes on the fly — fetch the
// rendition with an explicit Accept and inline it as a data URL so OpenAI
// never sees the original format. Falls back to the original URL on any
// failure, which fails the vision pass the same honest way it does today.
const VISION_SAFE_EXT_RE = /\.(png|jpe?g|jfif|gif|webp)(\?.*)?$/i;
const VISION_SAFE_MIMES = ['image/png', 'image/jpeg', 'image/gif', 'image/webp'];

const toVisionImageUrl = async (imageUrl: string): Promise<string> => {
  if (VISION_SAFE_EXT_RE.test(imageUrl) || imageUrl.startsWith('data:')) return imageUrl;
  const renderUrl = imageUrl.replace('/storage/v1/object/public/', '/storage/v1/render/image/public/');
  if (renderUrl === imageUrl) return imageUrl; // not our storage — nothing to transcode with
  try {
    const res = await fetch(`${renderUrl}?width=1024&quality=85`, {
      headers: { 'Accept': 'image/jpeg' },
      signal: AbortSignal.timeout(20_000),
    });
    if (!res.ok) {
      console.error('Image transcode fetch failed:', res.status, 'for', imageUrl);
      return imageUrl;
    }
    const contentType = res.headers.get('content-type')?.split(';')[0].trim() ?? '';
    if (!VISION_SAFE_MIMES.includes(contentType)) {
      console.error('Image transcode returned unusable type:', contentType, 'for', imageUrl);
      return imageUrl;
    }
    const bytes = new Uint8Array(await res.arrayBuffer());
    console.log(`Transcoded image for vision: ${imageUrl} -> ${contentType}, ${bytes.length} bytes`);
    return `data:${contentType};base64,${encodeBase64(bytes)}`;
  } catch (e) {
    console.error('Image transcode failed (falling back to original URL):', e);
    return imageUrl;
  }
};

const parseVisionResponse = (text: string): { title: string; description: string; detected_text: string; tags: string[] } => {
  const lines = text.split('\n').map((l) => l.trim()).filter(Boolean);

  let title = '';
  let description = '';
  let detected_text = 'none';
  let tags: string[] = [];

  for (const line of lines) {
    if (line.startsWith('TITLE:')) {
      title = line.replace('TITLE:', '').trim();
    } else if (line.startsWith('DESCRIPTION:')) {
      description = line.replace('DESCRIPTION:', '').trim();
    } else if (line.startsWith('TEXT:')) {
      detected_text = line.replace('TEXT:', '').trim();
    } else if (line.startsWith('TAGS:')) {
      tags = line
        .replace('TAGS:', '')
        .split(',')
        .map((t) => t.trim())
        .filter(Boolean);
    }
  }

  // Fallback: if structured parsing fails, use the full text as description
  if (!description) {
    description = text.trim();
  }

  return { title, description, detected_text, tags };
};

// ---- Title policy (ui-changes.md 2026-08-26) -------------------------------
// Image titles are AI-derived ("Screenshot of X" / "Image of X"); the original
// filename is metadata and lives in attributes.media.file_name. A title that
// is still a filename (or empty) is a placeholder we replace; anything else is
// the user's and is never touched.

const IMAGE_EXT_RE = /\.(png|jpe?g|jfif|gif|webp|avif|svg|bmp|ico|tiff?|heic|heif)$/i;

// Storage object names our clients generate (`${Date.now()}.ext`) carry no
// meaning — they get replaced but are never worth preserving as file_name.
const isStorageTimestampName = (name: string) => /^\d{10,17}\.[a-z0-9]+$/i.test(name.trim());

const fileBasename = (path: string | null | undefined) => path?.split('/').pop() ?? null;

const isPlaceholderTitle = (title: string | null | undefined, filePath: string | null | undefined): boolean => {
  const t = (title ?? '').trim();
  if (!t) return true;
  if (t === fileBasename(filePath)) return true;
  return IMAGE_EXT_RE.test(t);
};

const capTitle = (title: string) => {
  const t = title.trim().replace(/^["']|["']$/g, '');
  return t.length > 90 ? `${t.slice(0, 90).trimEnd()}…` : t;
};

// Fallback for saves whose vision pass predates the TITLE line (precomputed
// chip results from an older client/deploy): compose the title from the
// description we already have. Non-fatal — null leaves the title alone.
const composeTitleFromDescription = async (
  openAIApiKey: string,
  description: string,
  detectedText: string,
): Promise<string | null> => {
  try {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${openAIApiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content:
              'You write ultra-short titles (3-7 words) for saved images from their descriptions. If the description depicts a screenshot of an app, website, chat, code, or any other UI, start with "Screenshot of"; otherwise start with "Image of". Return only the title.',
          },
          {
            role: 'user',
            content: `Description: ${description}\n\nText visible in the image: ${detectedText || 'none'}`,
          },
        ],
        max_tokens: 40,
      }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    const title = data.choices?.[0]?.message?.content?.trim();
    return title ? capTitle(title) : null;
  } catch (e) {
    console.error('composeTitleFromDescription failed (non-fatal):', e);
    return null;
  }
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { itemId, imageUrl, precomputed } = await req.json();

    // Modes: chip-time (imageUrl only → vision, no DB writes), save-time reuse
    // (itemId + precomputed → DB writes without re-running vision), and the
    // original full mode (itemId + imageUrl).
    if (!imageUrl && !(itemId && precomputed)) {
      return new Response(JSON.stringify({ success: false, error: 'imageUrl or (itemId + precomputed) is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Missing Supabase configuration');
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    let title: string;
    let description: string;
    let detected_text: string;
    let tags: string[];

    if (precomputed && typeof precomputed.description === 'string') {
      title = typeof precomputed.title === 'string' ? precomputed.title : '';
      description = precomputed.description;
      detected_text = typeof precomputed.detected_text === 'string' && precomputed.detected_text.trim()
        ? precomputed.detected_text
        : 'none';
      tags = Array.isArray(precomputed.tags) ? precomputed.tags : [];
      console.log('Using precomputed vision results for item:', itemId);
    } else {
      console.log('Starting Vision analysis for item:', itemId ?? '(chip-time, no item)', 'image:', imageUrl);

      const visionImageUrl = await toVisionImageUrl(imageUrl);

      // Call OpenAI Vision
      const visionResponse = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${openAIApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gpt-4o',
          messages: [
            {
              role: 'user',
              content: [
                {
                  type: 'image_url',
                  image_url: { url: visionImageUrl, detail: 'high' },
                },
                {
                  type: 'text',
                  text: 'Analyze this image and provide:\n1. TITLE: An ultra-short title of 3-7 words. If the image is a screenshot of an app, website, chat, code, document, or any other UI, start with "Screenshot of"; otherwise start with "Image of". Examples: "Screenshot of a flight booking form", "Image of a golden retriever on a beach"\n2. DESCRIPTION: A 2-3 sentence description of what this image shows, stated directly with no preamble or meta-commentary (never "Certainly", "Here is", "This image shows...it appears" style filler)\n3. TEXT: Any text visible in the image (verbatim, or \'none\' if no text)\n4. TAGS: 3-5 relevant topic tags as comma-separated words\n\nRespond with ONLY these four lines, formatted exactly as:\nTITLE: <title>\nDESCRIPTION: <description>\nTEXT: <detected text or \'none\'>\nTAGS: <tag1>, <tag2>, <tag3>',
                },
              ],
            },
          ],
          max_tokens: 500,
        }),
      });

      if (!visionResponse.ok) {
        const errData = await visionResponse.json();
        throw new Error(`OpenAI Vision error: ${errData.error?.message || 'Unknown error'}`);
      }

      const visionData = await visionResponse.json();
      const rawContent = visionData.choices?.[0]?.message?.content;

      if (!rawContent) {
        throw new Error('No content returned from Vision API');
      }

      console.log('Vision API raw response:', rawContent);

      const parsed = parseVisionResponse(rawContent);
      title = parsed.title;
      description = parsed.description;
      detected_text = parsed.detected_text;
      tags = parsed.tags;

      console.log('Parsed — title:', title, '| description:', description, '| detected_text:', detected_text, '| tags:', tags);
    }

    // Chip-time calls carry no itemId: return the analysis without touching the DB
    if (itemId) {
      const hasOcrText = detected_text.toLowerCase() !== 'none' && detected_text.trim().length > 0;

      // Read the item first: the title guard and the attributes merge both
      // need current state (attributes are whole-blob — preserve every key).
      const { data: current, error: fetchError } = await supabase
        .from('items')
        .select('title, content, supplemental_note, file_path, attributes')
        .eq('id', itemId)
        .single();
      if (fetchError) {
        console.error('Error fetching item before Vision write:', fetchError);
      }

      const updates: Record<string, unknown> = {
        description,
        page_body: hasOcrText ? detected_text : null,
      };

      const attributes = (current?.attributes ?? {}) as Record<string, unknown>;
      const media = (attributes.media ?? {}) as Record<string, unknown>;
      let fileNameForEmbed = typeof media.file_name === 'string' ? media.file_name : null;

      if (current && isPlaceholderTitle(current.title, current.file_path)) {
        let aiTitle = title ? capTitle(title) : null;
        // A precomputed "title" that is itself a filename doesn't count
        if (aiTitle && isPlaceholderTitle(aiTitle, current.file_path)) aiTitle = null;
        if (!aiTitle && description) {
          aiTitle = await composeTitleFromDescription(openAIApiKey, description, hasOcrText ? detected_text : '');
        }
        if (aiTitle) {
          updates.title = aiTitle;
          // The filename the title used to carry is metadata worth keeping —
          // but only a real filename, not our own storage timestamp names.
          const oldTitle = (current.title ?? '').trim();
          if (!fileNameForEmbed && oldTitle && IMAGE_EXT_RE.test(oldTitle) && !isStorageTimestampName(oldTitle)) {
            fileNameForEmbed = oldTitle;
            updates.attributes = { ...attributes, media: { ...media, file_name: oldTitle } };
          }
        }
      }

      const { error: updateError } = await supabase
        .from('items')
        .update(updates)
        .eq('id', itemId);

      if (updateError) {
        console.error('Error updating item after Vision analysis:', updateError);
      } else {
        console.log('Item updated successfully with Vision analysis');
      }

      // Re-embed the full item: generate-embeddings replaces prior chunks, so the
      // text must carry the title/note too, not just the Vision output. Mirrors
      // extract-pdf-text/extract-office-text's composition order: title,
      // description, content (the user's own note), supplemental_note, filename,
      // body text.
      const textContent = [
        (updates.title as string | undefined) ?? current?.title,
        description,
        current?.content,
        current?.supplemental_note,
        fileNameForEmbed,
        hasOcrText ? detected_text : null,
      ].filter(Boolean).join(' ');

      // Invoke generate-embeddings
      const { error: embeddingError } = await supabase.functions.invoke('generate-embeddings', {
        body: { itemId, textContent },
      });

      if (embeddingError) {
        console.error('Failed to generate embeddings after Vision analysis:', embeddingError);
      } else {
        console.log('Embeddings generated successfully after Vision analysis');
      }
    }

    return new Response(
      JSON.stringify({ success: true, title, description, detected_text, tags }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in analyze-image:', error);
    // Return 200 with success: false so the caller treats this as non-fatal
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Unknown error' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
