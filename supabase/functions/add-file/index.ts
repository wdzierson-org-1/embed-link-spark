import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';

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

const fileNameFrom = (path: string) => path.split('/').pop() ?? 'file';

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

    const { file_path, mime_type, file_size, content, title, is_public = false } = await req.json();
    if (!file_path || typeof file_path !== 'string') return json(400, { error: 'file_path is required' });
    if (!mime_type || typeof mime_type !== 'string') return json(400, { error: 'mime_type is required' });
    if (!file_path.startsWith(`${user.id}/`)) {
      return json(403, { error: 'file_path must be inside your own storage folder' });
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
          await supabase.functions.invoke('analyze-image', {
            body: { itemId: item.id, imageUrl: publicUrl },
          });
        } else if (type === 'audio' || type === 'video') {
          const { data: t, error: tErr } = await supabase.functions.invoke('transcribe-audio', {
            body: { audioUrl: publicUrl, fileName },
          });
          if (tErr) throw tErr;
          // Transcript is captured source → page_body (content model,
          // migration 20260810120000); description is the short AI summary
          await supabase.from('items').update({
            page_body: t.transcription || null,
            description: t.description || null,
          }).eq('id', item.id);
          const text = [itemTitle, content, t.transcription, t.description].filter(Boolean).join(' ');
          if (text.trim()) {
            await supabase.functions.invoke('generate-embeddings', {
              body: { itemId: item.id, textContent: text },
            });
          }
        } else {
          // document: baseline embedding first so it's searchable even if
          // extraction never lands (mirrors contentProcessor.ts:580-594)
          const baseline = [itemTitle, fileName, content].filter(Boolean).join(' ');
          if (baseline.trim()) {
            await supabase.functions.invoke('generate-embeddings', {
              body: { itemId: item.id, textContent: baseline },
            });
          }
          await supabase.functions.invoke('quick-pdf-summary', {
            body: { fileUrl: publicUrl, itemId: item.id, fileName },
          });
          // writes page_body + summary + content embeddings itself
          await supabase.functions.invoke('extract-pdf-text', {
            body: { fileUrl: publicUrl, itemId: item.id },
          });
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
