import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { isAgentToken } from '../_shared/agentToken.ts';
import { afterDraining } from '../_shared/capture.ts';
import { requireEntitlement } from '../_shared/entitlementGate.ts';
import { NO_PREAMBLE_RULES, stripPreamble } from '../_shared/summarize.ts';
import {
  KEEP_FILENAME_TOKEN,
  capTitle,
  isPlaceholderTitle,
  isStorageTimestampName,
  isUuidObjectName,
  transcriptTitleSystemPrompt,
} from '../_shared/titlePolicy.ts';
import { parseRemindAt } from '../_shared/reminders.ts';
import { runImagePlaceStep } from '../_shared/placeEnrichment.ts';
import { runDocumentPreviewStep } from '../_shared/documentPreview.ts';

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
// (attributes.media.file_name). Since 2026-09-09 the transcribe-audio job
// derives the title itself once the transcript exists.

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return await afterDraining(req, json(405, { error: 'Method not allowed' }));

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Owner always derived from the verified JWT, never the body
    const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim();
    if (!token) return await afterDraining(req, json(401, { error: 'Missing authorization token' }));
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) return await afterDraining(req, json(401, { error: 'Invalid or expired token' }));
    if (isAgentToken(token)) return await afterDraining(req, json(403, { error: 'Agent tokens are only accepted by the MCP endpoint' }));
    if (authError || !user) return await afterDraining(req, json(401, { error: 'Invalid or expired token' }));
    if (isAgentToken(token)) return await afterDraining(req, json(403, { error: 'Agent tokens are only accepted by the MCP endpoint' }));
    const denied = await requireEntitlement(supabase, user, corsHeaders);
    // The paywall answers before the body is read; without draining first the
    // gateway turns this 403 into a hang for anything over ~0.5 MB.
    if (denied) return await afterDraining(req, denied);

    const { file_path, mime_type, file_size, content, title, is_public = false, attributes, remind_at } = await req.json();
    const safeAttributes =
      attributes && typeof attributes === 'object' && !Array.isArray(attributes) ? attributes : {};
    const remindAt = parseRemindAt(remind_at);
    if (remind_at !== undefined && remindAt === null) {
      console.warn('add-file: ignoring invalid remind_at', { remind_at });
    }
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
        attributes: { ...safeAttributes, enrichment: { status: 'pending', updated_at: new Date().toISOString() } },
        remind_at: remindAt,
      })
      .select()
      .single();

    if (error) return json(500, { error: 'Failed to create item', details: error.message });

    // --- enrichment: after-response, never blocks capture ---
    const publicUrl = `${Deno.env.get('SUPABASE_URL')}/storage/v1/object/public/stash-media/${file_path}`;

    const enrich = async () => {
      let status = 'complete';
      try {
        if (type === 'image') {
          // analyze-image writes description + page_body (OCR) and re-embeds the item
          const { data: imageResult, error: imgErr } = await supabase.functions.invoke('analyze-image', {
            body: { itemId: item.id, imageUrl: publicUrl },
          });
          if (imgErr || imageResult?.success === false) status = 'partial';
          if (imgErr) console.error('add-file: analyze-image failed for', item.id, imgErr);
          // A picture whose text names a street address is a place too: once the address
          // is confirmed on the map, the lane and the map join the save (the photo stays
          // its picture). Never fatal to the save.
          if (!imgErr) {
            try {
              const outcome = await runImagePlaceStep(supabase, item.id, { mapboxToken: Deno.env.get('MAPBOX_ACCESS_TOKEN') });
              console.log('add-file: place step', item.id, JSON.stringify('skipped' in outcome ? outcome : { kept: true, map: outcome.map ?? null }));
            } catch (placeError) {
              console.error('add-file: place step failed', item.id, placeError);
            }
          }
        } else if (type === 'audio' || type === 'video') {
          // What we know now lands now: attributes.media.kind (the subtype
          // clients render against — voice_note < 10 min or unknown duration,
          // recording ≥ 10 min, video), the original filename, and a pending
          // transcript status. The transcribe-audio job then owns the rest:
          // page_body (chunk by chunk), description, summary, AI title, and
          // the content embeddings — see the 2026-09-09 spec. attributes is a
          // whole-blob jsonb column: read-merge-write, preserving every key
          // we don't model.
          const { data: current, error: curErr } = await supabase
            .from('items')
            .select('attributes')
            .eq('id', item.id)
            .single();
          if (curErr) console.error('add-file: re-fetch before media enrichment failed:', curErr);
          const attrs = ((current?.attributes ?? safeAttributes) ?? {}) as Record<string, unknown>;
          const media = (attrs.media ?? {}) as Record<string, unknown>;
          const durationS = typeof media.duration_s === 'number' ? media.duration_s : null;
          const kind =
            type === 'video' ? 'video' : durationS !== null && durationS >= 600 ? 'recording' : 'voice_note';
          // The original filename is metadata worth keeping: the caller's
          // attributes.media.file_name is that name (the web and iOS send it);
          // the storage object's name only counts when it is a real one, never
          // our own timestamp/UUID/staging object names.
          const callerName = typeof media.file_name === 'string' && media.file_name.trim() ? media.file_name.trim() : undefined;
          const meaningfulName =
            !isStorageTimestampName(fileName) && !isUuidObjectName(fileName) ? fileName : undefined;
          const fileNameForMedia = callerName ?? meaningfulName;
          await supabase
            .from('items')
            .update({
              attributes: {
                ...attrs,
                media: {
                  ...media,
                  ...(fileNameForMedia ? { file_name: fileNameForMedia } : {}),
                  kind,
                  transcript: { status: 'pending', updated_at: new Date().toISOString() },
                },
              },
            })
            .eq('id', item.id);

          // Baseline embedding so the item is findable by title/filename/note
          // while the (possibly minutes-long) transcription runs; the job
          // replaces it with content embeddings when the transcript lands.
          const baseline = [itemTitle, fileNameForMedia, content].filter(Boolean).join(' ');
          if (baseline.trim()) {
            const { error: embErr } = await supabase.functions.invoke('generate-embeddings', {
              body: { itemId: item.id, textContent: baseline },
            });
            if (embErr) console.error('add-file: baseline generate-embeddings failed for', item.id, embErr);
          }

          const { error: tErr } = await supabase.functions.invoke('transcribe-audio', {
            body: { itemId: item.id },
          });
          if (tErr) console.error('add-file: transcribe-audio job start failed for', item.id, tErr);
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
          // The first page is the card's picture (a PDF drawn by the renderer, an Office
          // file's own saved preview): before extraction, so it lands while the text is
          // still being read. Never fatal to the save.
          try {
            const outcome = await runDocumentPreviewStep(supabase, { id: item.id, user_id: user.id, mime_type }, {
              publicUrl,
              rendererUrl: Deno.env.get('DOCUMENT_PREVIEW_URL') ?? 'https://www.gostash.it/api/document-preview',
              rendererSecret: Deno.env.get('DOCUMENT_PREVIEW_SECRET'),
            });
            console.log('add-file: preview step', item.id, JSON.stringify(outcome));
          } catch (previewError) {
            console.error('add-file: preview step failed', item.id, previewError);
          }
          if (mime_type === 'application/pdf') {
            const { error: qpsErr } = await supabase.functions.invoke('quick-pdf-summary', {
              body: { fileUrl: publicUrl, itemId: item.id, fileName },
            });
            if (qpsErr) console.error('add-file: quick-pdf-summary failed for', item.id, qpsErr);
            // writes page_body + summary + content embeddings itself
            const { data: pdfResult, error: extErr } = await supabase.functions.invoke('extract-pdf-text', {
              body: { fileUrl: publicUrl, itemId: item.id },
            });
            if (extErr || pdfResult?.success === false) status = 'partial';
            if (extErr) console.error('add-file: extract-pdf-text failed for', item.id, extErr);
          } else if (OFFICE_MIMES.has(mime_type)) {
            // OOXML documents → extract-office-text (committed+deployed c4cbdd0;
            // mirrors extract-pdf-text: writes page_body + summary + description,
            // re-embeds). Contract: {fileUrl, itemId, fileName, mimeType}
            // (extract-office-text/index.ts:127).
            const { data: officeResult, error: offErr } = await supabase.functions.invoke('extract-office-text', {
              body: { fileUrl: publicUrl, itemId: item.id, fileName, mimeType: mime_type },
            });
            if (offErr || officeResult?.success === false) status = 'partial';
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
        status = 'partial';
        console.error('add-file enrichment failed (non-fatal):', e);
      } finally {
        // Audio and video are still being transcribed when this returns: the
        // transcribe-audio job settles their status when it finishes (complete)
        // or gives up (partial). Everything else is done here.
        if (type !== 'audio' && type !== 'video') {
          const { error: statusError } = await supabase.rpc('set_item_enrichment', { target_id: item.id, next_status: status });
          if (statusError) console.error('Failed to settle enrichment:', statusError);
        }
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
