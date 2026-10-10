// analyze-note-images: describe the pictures inside a note so they are stored and embedded
// like its words (Will, 2026-10-10). Contract: POST { itemId }. The caller is the capture
// pipeline (add-note, after the insert) or a client that just saved a note (the web panel,
// with the person's own token): both only ask; the work is done here. Each picture is
// described once (`analyze-image` in its no-write mode — a description, the text it carries)
// and kept in `attributes.note_images` (see _shared/noteImages.ts); pictures that left the
// note are dropped; nothing is sent to the model for a note whose pictures are all known.
// The leaf is written through a compare-and-swap (set_item_note_images), then the save is
// re-indexed, so the descriptions join the embeddings the way place facts do.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { requireItemAccess } from '../_shared/enrichmentAuth.ts';
import {
  type NoteImage,
  type NoteImages,
  noteImageSources,
  readNoteImages,
  reconcileNoteImages,
} from '../_shared/noteImages.ts';

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

/** At most this many new pictures described per call: the rest wait for the next save. */
const MAX_NEW_PER_CALL = 8;

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });

interface VisionReply {
  success?: boolean;
  description?: string;
  detected_text?: string;
}

/** One picture through the vision pass; null when it could not be described (not fatal). */
const describe = async (db: any, src: string): Promise<NoteImage | null> => {
  const { data, error } = await db.functions.invoke('analyze-image', { body: { imageUrl: src } });
  const reply = data as VisionReply | null;
  if (error || !reply || reply.success === false || typeof reply.description !== 'string' || !reply.description.trim()) {
    console.error('analyze-note-images: picture not described', src, error ?? reply);
    return null;
  }
  const text = typeof reply.detected_text === 'string' ? reply.detected_text.trim() : '';
  return {
    src,
    description: reply.description.trim(),
    ...(text && text.toLowerCase() !== 'none' ? { text } : {}),
    analyzed_at: new Date().toISOString(),
  };
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return json(405, { error: 'POST only' });

  try {
    const { itemId } = await req.json();
    if (typeof itemId !== 'string' || !itemId) return json(400, { error: 'itemId required' });

    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let item: { id: string; content: string | null; attributes: Record<string, unknown> | null };
    try {
      item = await requireItemAccess(req, db, itemId, 'id,content,attributes');
    } catch {
      return json(403, { error: 'Item not found or access denied' });
    }

    const sources = noteImageSources(item.content);
    const current = readNoteImages(item.attributes);
    const { kept, missing } = reconcileNoteImages(current, sources);

    const described: NoteImage[] = [];
    for (const src of missing.slice(0, MAX_NEW_PER_CALL)) {
      const image = await describe(db, src);
      if (image) described.push(image);
    }

    // The note's order, with the new descriptions in place
    const bySrc = new Map([...kept, ...described].map((image) => [image.src, image]));
    const images = sources.map((src) => bySrc.get(src)).filter((image): image is NoteImage => !!image);

    const unchanged =
      (current?.images.length ?? 0) === images.length &&
      images.every((image, index) => current?.images[index]?.src === image.src);
    if (unchanged) {
      return json(200, { success: true, changed: false, described: 0, pending: Math.max(0, missing.length - described.length) });
    }

    // Nothing left to say and nothing said before: leave the leaf out entirely
    const next: NoteImages | null = images.length ? { version: 1, images } : null;
    const { data: written, error: rpcError } = await db.rpc('set_item_note_images', {
      target_id: itemId,
      expected: current,
      next,
    });
    if (rpcError) throw rpcError;
    if (written !== true) {
      // Another writer changed the leaf meanwhile; that writer re-indexes
      return json(200, { success: false, reason: 'item_changed' });
    }

    const { error: indexError } = await db.functions.invoke('generate-embeddings', { body: { itemId } });
    if (indexError) console.error('analyze-note-images: re-index failed', itemId, indexError);

    return json(200, {
      success: true,
      changed: true,
      described: described.length,
      pending: Math.max(0, missing.length - described.length),
    });
  } catch (error) {
    console.error('analyze-note-images failed', error);
    return json(500, { error: 'Note image analysis failed' });
  }
});
