import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { NO_PREAMBLE_RULES, stripPreamble } from '../_shared/summarize.ts';
import {
  KEEP_FILENAME_TOKEN,
  capTitle,
  isPlaceholderTitle,
  isStorageTimestampName,
  isUuidObjectName,
  transcriptTitleSystemPrompt,
} from '../_shared/titlePolicy.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// Mirrors the web's routing: image/* → image, audio/* → audio, video/* → video,
// everything else that reaches this endpoint is a document (pdf, docx, …)
export const deriveItemType = (mime: string): 'image' | 'audio' | 'video' | 'document' => {
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('audio/')) return 'audio';
  if (mime.startsWith('video/')) return 'video';
  return 'document';
};

// Office Open XML formats routed to extract-office-text (c4cbdd0); everything
// else non-PDF settles with a stub description (parity with 83e9809)
const OFFICE_MIMES = new Set([
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
]);

const fileNameFrom = (path: string) => path.split('/').pop() ?? 'file';

// Title policy (ui-changes.md 2026-08-26): audio/video titles are AI-derived
// from the transcript; the original filename is metadata
// (attributes.media.file_name). Returns null whenever there is no usable
// title — missing key, API failure, or the model judged the content deeply
// personal and returned KEEP_FILENAME — and the caller then leaves the
// filename title in place.
const titleFromTranscript = async (transcript: string): Promise<string | null> => {
  const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
  if (!openAIApiKey) return null;
  try {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${openAIApiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: transcriptTitleSystemPrompt(NO_PREAMBLE_RULES) },
          { role: 'user', content: `Transcript:\n\n${transcript.slice(0, 6000)}` },
        ],
        max_tokens: 40,
        temperature: 0.2,
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      console.error('titleFromTranscript: OpenAI error', res.status, await res.text());
      return null;
    }
    const data = await res.json();
    const raw = stripPreamble(data.choices?.[0]?.message?.content?.trim() ?? '');
    if (!raw || raw.includes(KEEP_FILENAME_TOKEN)) return null;
    return capTitle(raw);
  } catch (e) {
    console.error('titleFromTranscript failed (non-fatal):', e);
    return null;
  }
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return json(405, { error: 'Method not allowed' });

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Owner always derived from the verified JWT, never the body
    const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim();
    if (!token) return json(401, { error: 'Missing authorization token' });
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) return json(401, { error: 'Invalid or expired token' });

    const { file_path, mime_type, file_size, content, title, is_public = false, attributes } = await req.json();
    const safeAttributes =
      attributes && typeof attributes === 'object' && !Array.isArray(attributes) ? attributes : {};
    if (!file_path || typeof file_path !== 'string') return json(400, { error: 'file_path is required' });
    if (!mime_type || typeof mime_type !== 'string') return json(400, { error: 'mime_type is required' });
    if (!file_path.startsWith(`${user.id}/`)) {
      return json(403, { error: 'file_path must be inside your own storage folder' });
    }

    const segments = file_path.split('/');
    if (segments.some((s: string) => s === '' || s === '..')) {
      return json(400, { error: 'file_path contains invalid segments' });
    }

    const type = deriveItemType(mime_type);
    const fileName = fileNameFrom(file_path);
    const itemTitle = title || fileName;
    // Same placeholder the web writes for in-flight documents
    // (src/utils/contentProcessor.ts:484)
    const placeholderDescription =
      type === 'document' ? 'PDF file uploaded - text extraction in progress' : null;

    const { data: item, error } = await supabase
      .from('items')
      .insert({
        user_id: user.id,
        type,
        title: itemTitle,
        content: content || null,
        description: placeholderDescription,
        file_path,
        file_size: file_size ?? null,
        mime_type,
        is_public,
        visibility: is_public ? 'public' : 'private',
        attributes: safeAttributes,
      })
      .select()
      .single();

    if (error) return json(500, { error: 'Failed to create item', details: error.message });

    // --- enrichment: after-response, never blocks capture ---
    const publicUrl = `${Deno.env.get('SUPABASE_URL')}/storage/v1/object/public/stash-media/${file_path}`;

    const enrich = async () => {
      try {
        if (type === 'image') {
          // analyze-image writes description + page_body (OCR) and re-embeds the item
          const { error: imgErr } = await supabase.functions.invoke('analyze-image', {
            body: { itemId: item.id, imageUrl: publicUrl },
          });
          if (imgErr) console.error('add-file: analyze-image failed for', item.id, imgErr);
        } else if (type === 'audio' || type === 'video') {
          const { data: t, error: tErr } = await supabase.functions.invoke('transcribe-audio', {
            body: { audioUrl: publicUrl, fileName },
          });
          if (tErr) throw tErr;
          const transcript = typeof t.transcription === 'string' ? t.transcription.trim() : '';

          // Transcript is captured source → page_body (content model,
          // migration 20260810120000); description is the short AI summary
          const updates: Record<string, unknown> = {
            page_body: t.transcription || null,
            description: t.description || null,
          };

          // Re-read current state: the title guard must see the title as it
          // is NOW (the user may have renamed during enrichment), and
          // attributes is a whole-blob jsonb column — read-merge-write,
          // preserving every key we don't model. Fetch failure → be
          // conservative and skip both writes.
          const { data: current, error: curErr } = await supabase
            .from('items')
            .select('title, attributes')
            .eq('id', item.id)
            .single();
          if (curErr) {
            console.error('add-file: re-fetch before media enrichment failed (skipping title/attributes):', curErr);
          }

          let finalTitle = current?.title ?? itemTitle;
          if (current) {
            // attributes.media.kind — the media subtype clients render against:
            // voice_note (audio < 10 min or unknown duration), recording
            // (audio ≥ 10 min), video.
            const attrs = (current.attributes ?? {}) as Record<string, unknown>;
            const media = (attrs.media ?? {}) as Record<string, unknown>;
            const durationS = typeof media.duration_s === 'number' ? media.duration_s : null;
            const kind =
              type === 'video' ? 'video' : durationS !== null && durationS >= 600 ? 'recording' : 'voice_note';
            // The original filename is metadata worth keeping — but only a
            // real one, never our own storage timestamp/UUID object names.
            const meaningfulName =
              !isStorageTimestampName(fileName) && !isUuidObjectName(fileName) ? fileName : undefined;
            const fileNameForMedia =
              meaningfulName ?? (typeof media.file_name === 'string' ? media.file_name : undefined);
            updates.attributes = {
              ...attrs,
              media: { ...media, ...(fileNameForMedia ? { file_name: fileNameForMedia } : {}), kind },
            };

            // Title policy (_shared/titlePolicy.ts): replace a placeholder
            // (filename-shaped) title with one derived from the transcript;
            // a real user title is never touched.
            if (transcript && isPlaceholderTitle(current.title, file_path)) {
              const aiTitle = await titleFromTranscript(transcript);
              if (aiTitle) {
                updates.title = aiTitle;
                finalTitle = aiTitle;
              }
            }
          }

          await supabase.from('items').update(updates).eq('id', item.id);
          const text = [finalTitle, content, t.transcription, t.description].filter(Boolean).join(' ');
          if (text.trim()) {
            const { error: embErr } = await supabase.functions.invoke('generate-embeddings', {
              body: { itemId: item.id, textContent: text },
            });
            if (embErr) console.error('add-file: generate-embeddings failed for', item.id, embErr);
          }
        } else {
          // document: baseline embedding first so it's searchable even if
          // extraction never lands (mirrors contentProcessor.ts:580-594)
          const baseline = [itemTitle, fileName, content].filter(Boolean).join(' ');
          if (baseline.trim()) {
            const { error: embErr } = await supabase.functions.invoke('generate-embeddings', {
              body: { itemId: item.id, textContent: baseline },
            });
            if (embErr) console.error('add-file: generate-embeddings failed for', item.id, embErr);
          }
          if (mime_type === 'application/pdf') {
            const { error: qpsErr } = await supabase.functions.invoke('quick-pdf-summary', {
              body: { fileUrl: publicUrl, itemId: item.id, fileName },
            });
            if (qpsErr) console.error('add-file: quick-pdf-summary failed for', item.id, qpsErr);
            // writes page_body + summary + content embeddings itself
            const { error: extErr } = await supabase.functions.invoke('extract-pdf-text', {
              body: { fileUrl: publicUrl, itemId: item.id },
            });
            if (extErr) console.error('add-file: extract-pdf-text failed for', item.id, extErr);
          } else if (OFFICE_MIMES.has(mime_type)) {
            // OOXML documents → extract-office-text (committed+deployed c4cbdd0;
            // mirrors extract-pdf-text: writes page_body + summary + description,
            // re-embeds). Contract: {fileUrl, itemId, fileName, mimeType}
            // (extract-office-text/index.ts:127).
            const { error: offErr } = await supabase.functions.invoke('extract-office-text', {
              body: { fileUrl: publicUrl, itemId: item.id, fileName, mimeType: mime_type },
            });
            if (offErr) console.error('add-file: extract-office-text failed for', item.id, offErr);
          } else {
            // Other non-PDF documents (parity with 83e9809): no PDF pipeline.
            // Give the card a description and clear the "still extracting"
            // marker (summary IS NULL drives the shimmer).
            const { data: d, error: descErr } = await supabase.functions.invoke('generate-description', {
              body: { content: fileName, type: 'document' },
            });
            if (descErr) console.error('add-file: generate-description failed for', item.id, descErr);
            const description = d?.description ?? `Document: ${fileName}`;
            await supabase.from('items').update({ description, summary: description }).eq('id', item.id);
          }
        }
      } catch (e) {
        console.error('add-file enrichment failed (non-fatal):', e);
      }
    };

    const runtime = (globalThis as { EdgeRuntime?: { waitUntil: (p: Promise<unknown>) => void } }).EdgeRuntime;
    const p = enrich();
    runtime?.waitUntil?.(p);

    return json(200, { success: true, item });
  } catch (e) {
    return json(500, { error: 'Internal server error', details: e instanceof Error ? e.message : 'Unknown' });
  }
});
