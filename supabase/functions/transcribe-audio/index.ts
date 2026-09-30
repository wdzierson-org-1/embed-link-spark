// transcribe-audio — transcription for audio/video items of any size.
//
// Two modes (spec: docs/superpowers/specs/2026-09-09-long-audio-transcription-design.md):
//
//   Preview  { audioUrl, fileName }  → { transcription, description } (sync)
//            Used by the web chip before save. Files over INLINE_MAX_BYTES
//            answer { deferred: true } instead of failing — the save-time
//            job below handles them.
//
//   Job      { itemId }              → 202 { accepted: true }
//            Owns every write for the item: chunked transcript → page_body
//            (progressively), description, summary, AI title, media kind,
//            embeddings, and attributes.media.transcript status. Long files
//            are split without decoding (_shared/mp4Audio.ts) so OpenAI's
//            25 MiB cap never applies. Work past the time budget continues
//            in a fresh invocation; a pg_cron sweep ({ sweep: true }) resumes
//            anything that stalled.
//
// Auth (gateway verify_jwt is off): x-cron-secret, the service role key, or
// the item owner's JWT. Preview only accepts URLs inside our own bucket.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { isAgentToken } from '../_shared/agentToken.ts';
import { NO_PREAMBLE_RULES, generateSummary, stripPreamble } from '../_shared/summarize.ts';
import {
  KEEP_FILENAME_TOKEN,
  capTitle,
  isPlaceholderTitle,
  isStorageTimestampName,
  isUuidObjectName,
  transcriptTitleSystemPrompt,
} from '../_shared/titlePolicy.ts';
import {
  Mp4Error,
  buildChunkFile,
  parseAudioTrack,
  planChunks,
  type AudioTrack,
  type ByteReader,
  type ChunkPlan,
} from '../_shared/mp4Audio.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// OpenAI rejects uploads at 26,214,400 bytes. Whole files up to 24 MiB go as
// they are; anything bigger is demuxed into ≤ 24 MiB / ≤ 20 min chunks (the
// remuxed moov adds well under 1 MiB even for an hour of audio).
const INLINE_MAX_BYTES = 24 * 1024 * 1024;
const CHUNK_MAX_BYTES = 24 * 1024 * 1024;
const CHUNK_MAX_SECONDS = 20 * 60;
const PAGE_BODY_CAP = 200_000;
const PROMPT_TAIL_CHARS = 600;
// Pro plan wall clock is 400 s; one chunk can take up to OPENAI_TIMEOUT_MS,
// so stop starting new chunks after this and hand off to a fresh invocation.
const TIME_BUDGET_MS = 150_000;
const OPENAI_TIMEOUT_MS = 180_000;
const DEFAULT_MODEL = Deno.env.get('TRANSCRIBE_MODEL') || 'gpt-4o-transcribe';
const FALLBACK_MODEL = 'whisper-1';

// Sweep policy
const SWEEP_BATCH = 3;
const SWEEP_WINDOW_DAYS = 14;
const MAX_ATTEMPTS = 3;
const PENDING_GRACE_MS = 2 * 60_000; // let the capture path's own invoke win
const STALE_PROCESSING_MS = 15 * 60_000; // no chunk landed in this long → resume
const FAILED_RETRY_MS = 10 * 60_000;

type TranscriptStatus = 'pending' | 'processing' | 'done' | 'failed';
type TranscriptError =
  | 'download_failed'
  | 'no_audio_track'
  | 'unsupported_container'
  | 'transcription_failed'
  | 'no_speech';

interface TranscriptState {
  status?: TranscriptStatus;
  source?: string;
  chunks_total?: number;
  chunks_done?: number;
  attempts?: number;
  updated_at?: string;
  error?: TranscriptError;
}

type Db = ReturnType<typeof createClient>;

const env = (key: string) => Deno.env.get(key) ?? '';
const storagePrefix = () => `${env('SUPABASE_URL')}/storage/v1/object/public/stash-media/`;
const publicUrl = (filePath: string) => `${storagePrefix()}${filePath}`;
const basename = (path: string) => path.split('/').pop() ?? 'audio';
const nowIso = () => new Date().toISOString();

// ---- OpenAI ------------------------------------------------------------------

class OpenAIError extends Error {
  status: number;
  constructor(status: number, detail: string) {
    super(`OpenAI ${status}: ${detail.slice(0, 300)}`);
    this.status = status;
  }
}

const transcribeBytes = async (
  bytes: Uint8Array,
  fileName: string,
  model: string,
  prompt?: string,
): Promise<string> => {
  const form = new FormData();
  form.append('file', new Blob([bytes]), fileName);
  form.append('model', model);
  form.append('response_format', 'text');
  if (prompt) form.append('prompt', prompt);
  const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env('OPENAI_API_KEY')}` },
    body: form,
    signal: AbortSignal.timeout(OPENAI_TIMEOUT_MS),
  });
  if (!res.ok) throw new OpenAIError(res.status, await res.text());
  return (await res.text()).trim();
};

// Preferred model first; on a model-side failure (not auth, size, or rate
// limit) retry the same bytes once with whisper-1.
const transcribeWithFallback = async (
  bytes: Uint8Array,
  fileName: string,
  prompt?: string,
): Promise<{ text: string; model: string }> => {
  try {
    return { text: await transcribeBytes(bytes, fileName, DEFAULT_MODEL, prompt), model: DEFAULT_MODEL };
  } catch (e) {
    const status = e instanceof OpenAIError ? e.status : 0;
    if (DEFAULT_MODEL === FALLBACK_MODEL || status === 401 || status === 413 || status === 429) throw e;
    console.warn(`transcribe-audio: ${DEFAULT_MODEL} failed (${e instanceof Error ? e.message : e}); retrying with ${FALLBACK_MODEL}`);
    return { text: await transcribeBytes(bytes, fileName, FALLBACK_MODEL, prompt), model: FALLBACK_MODEL };
  }
};

const chat = async (system: string, user: string, maxTokens: number): Promise<string | null> => {
  try {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${env('OPENAI_API_KEY')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
        max_tokens: maxTokens,
        temperature: 0.2,
      }),
      signal: AbortSignal.timeout(30_000),
    });
    if (!res.ok) {
      console.error('transcribe-audio: chat completion failed', res.status, await res.text());
      return null;
    }
    const data = await res.json();
    const text = data.choices?.[0]?.message?.content?.trim();
    return text ? stripPreamble(text) : null;
  } catch (e) {
    console.error('transcribe-audio: chat completion error (non-fatal):', e);
    return null;
  }
};

// Card blurb: the short `description` lane
const describeTranscript = (transcript: string) =>
  chat(
    'You write the card blurb for a transcribed recording (conversation, meeting, lecture, or voice memo) ' +
      'in a personal library: 1-3 sentences, at most 60 words, stating what it is about and the most ' +
      'important point. State the content directly — never "this recording" or "the transcript". ' +
      NO_PREAMBLE_RULES,
    `Transcript:\n\n${transcript.slice(0, 24_000)}`,
    140,
  );

// Title policy (_shared/titlePolicy.ts): null → leave the filename title alone
const titleFromTranscript = async (transcript: string): Promise<string | null> => {
  const raw = await chat(transcriptTitleSystemPrompt(NO_PREAMBLE_RULES), `Transcript:\n\n${transcript.slice(0, 6000)}`, 40);
  if (!raw || raw.includes(KEEP_FILENAME_TOKEN)) return null;
  return capTitle(raw);
};

// ---- storage -----------------------------------------------------------------

const rangeReader = (url: string): ByteReader => async (start, end) => {
  const res = await fetch(url, { headers: { Range: `bytes=${start}-${end}` } });
  if (res.status !== 206 && res.status !== 200) throw new Error(`download_failed: range ${start}-${end} → ${res.status}`);
  const buf = new Uint8Array(await res.arrayBuffer());
  // A server that ignores Range sends the whole object
  return res.status === 200 ? buf.subarray(start, end + 1) : buf;
};

const remoteSize = async (url: string): Promise<number> => {
  const res = await fetch(url, { headers: { Range: 'bytes=0-0' } });
  if (!res.ok) throw new Error(`download_failed: ${res.status}`);
  const total = res.headers.get('content-range')?.split('/')[1];
  const len = res.headers.get('content-length');
  const size = total ? Number(total) : res.status === 200 && len ? Number(len) : NaN;
  if (!Number.isFinite(size)) throw new Error('download_failed: no size');
  return size;
};

const downloadWhole = async (url: string): Promise<Uint8Array> => {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`download_failed: ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
};

// ---- item state ----------------------------------------------------------------

const mediaOf = (attributes: unknown) => {
  const attrs = (attributes && typeof attributes === 'object' && !Array.isArray(attributes) ? attributes : {}) as Record<string, unknown>;
  const media = (attrs.media && typeof attrs.media === 'object' ? attrs.media : {}) as Record<string, unknown>;
  const transcript = (media.transcript && typeof media.transcript === 'object' ? media.transcript : {}) as TranscriptState;
  return { attrs, media, transcript };
};

// attributes is a whole-blob jsonb column: re-read, merge, write — so a
// concurrent user edit (rename, location) is never clobbered.
const patchItem = async (
  db: Db,
  itemId: string,
  transcriptPatch: TranscriptState,
  columns: Record<string, unknown> = {},
  mediaPatch: Record<string, unknown> = {},
) => {
  const { data } = await db.from('items').select('attributes').eq('id', itemId).single();
  const { attrs, media, transcript } = mediaOf(data?.attributes);
  const next = {
    ...attrs,
    media: { ...media, ...mediaPatch, transcript: { ...transcript, ...transcriptPatch, updated_at: nowIso() } },
  };
  const { error } = await db.from('items').update({ ...columns, attributes: next }).eq('id', itemId);
  if (error) console.error('transcribe-audio: item update failed', itemId, error);
};

const joinTranscript = (soFar: string, next: string) =>
  soFar.trim() ? `${soFar.trimEnd()}\n${next.trim()}` : next.trim();

const classify = (e: unknown): TranscriptError => {
  if (e instanceof Mp4Error) return e.code === 'no_audio_track' ? 'no_audio_track' : 'unsupported_container';
  if (e instanceof OpenAIError) return 'transcription_failed';
  const msg = e instanceof Error ? e.message : String(e);
  if (msg.startsWith('download_failed')) return 'download_failed';
  return 'transcription_failed';
};

// ---- the job ------------------------------------------------------------------

interface ItemRow {
  id: string;
  user_id: string;
  type: string;
  title: string | null;
  content: string | null;
  file_path: string | null;
  file_size: number | null;
  mime_type: string | null;
  page_body: string | null;
  attributes: unknown;
}

const selfContinue = async (itemId: string) => {
  try {
    const res = await fetch(`${env('SUPABASE_URL')}/functions/v1/transcribe-audio`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env('SUPABASE_SERVICE_ROLE_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ itemId, continue: true }),
    });
    console.log('transcribe-audio: continuation requested for', itemId, res.status);
  } catch (e) {
    console.error('transcribe-audio: continuation request failed (sweep will resume):', e);
  }
};

const runJob = async (db: Db, itemId: string, trigger: 'start' | 'continue' | 'sweep') => {
  const started = Date.now();
  const { data: item, error } = await db
    .from('items')
    .select('id, user_id, type, title, content, file_path, file_size, mime_type, page_body, attributes')
    .eq('id', itemId)
    .single();
  if (error || !item) {
    console.error('transcribe-audio: item not found', itemId, error);
    return;
  }
  const row = item as unknown as ItemRow;
  if ((row.type !== 'audio' && row.type !== 'video') || !row.file_path) return;

  const { media, transcript: prev } = mediaOf(row.attributes);
  if (prev.status === 'done') return;

  const attempts = (prev.attempts ?? 0) + (trigger === 'continue' ? 0 : 1);
  const url = publicUrl(row.file_path);
  const fileName =
    typeof media.file_name === 'string' && /\.[a-z0-9]{2,5}$/i.test(media.file_name)
      ? media.file_name
      : basename(row.file_path);

  console.log(`transcribe-audio: job ${trigger} for ${itemId} (${row.type}, ${row.file_size ?? '?'} bytes, attempt ${attempts})`);
  await patchItem(db, itemId, { status: 'processing', attempts, error: undefined });

  try {
    const size = row.file_size ?? (await remoteSize(url));
    const read = rangeReader(url);

    let track: AudioTrack | null = null;
    let plan: ChunkPlan[] | null = null;
    if (size > INLINE_MAX_BYTES) {
      track = await parseAudioTrack(read, size);
      plan = planChunks(track, { maxBytes: CHUNK_MAX_BYTES, maxSeconds: CHUNK_MAX_SECONDS });
      console.log(`transcribe-audio: ${itemId} planned ${plan.length} chunks over ${track.durationS.toFixed(0)} s`);
    }
    const chunksTotal = plan ? plan.length : 1;

    // Resume only when the previous run left a compatible plan behind
    const resumable = prev.status === 'processing' || prev.status === 'failed';
    let done = resumable && prev.chunks_total === chunksTotal ? Math.min(prev.chunks_done ?? 0, chunksTotal) : 0;
    let text = done > 0 ? row.page_body ?? '' : '';
    if (done > 0 && !text.trim()) done = 0;
    let model = DEFAULT_MODEL;

    for (let idx = done; idx < chunksTotal; idx++) {
      if (idx > done && Date.now() - started > TIME_BUDGET_MS) {
        await patchItem(db, itemId, { status: 'processing', chunks_total: chunksTotal, chunks_done: idx });
        await selfContinue(itemId);
        return;
      }
      const bytes = plan && track ? await buildChunkFile(read, track, plan[idx]) : await downloadWhole(url);
      const name = plan ? `chunk-${idx}.m4a` : fileName;
      const result = await transcribeWithFallback(bytes, name, text.slice(-PROMPT_TAIL_CHARS) || undefined);
      model = result.model;
      text = joinTranscript(text, result.text);
      await patchItem(
        db,
        itemId,
        { status: 'processing', chunks_total: chunksTotal, chunks_done: idx + 1, source: `openai:${model}` },
        { page_body: text.slice(0, PAGE_BODY_CAP) || null },
      );
      console.log(`transcribe-audio: ${itemId} chunk ${idx + 1}/${chunksTotal} → ${result.text.length} chars via ${model}`);
    }

    if (!text.trim()) {
      await patchItem(db, itemId, { status: 'failed', chunks_total: chunksTotal, chunks_done: chunksTotal, error: 'no_speech' });
      return;
    }

    // ---- finalize: description, summary, title, kind, embeddings ----
    const { data: fresh } = await db.from('items').select('title, content, file_path, attributes').eq('id', itemId).single();
    const currentTitle = (fresh?.title as string | null) ?? row.title;
    const placeholder = isPlaceholderTitle(currentTitle, row.file_path);
    const [description, summary, aiTitle] = await Promise.all([
      describeTranscript(text),
      generateSummary(env('OPENAI_API_KEY'), { sourceText: text, kind: 'recording', title: placeholder ? null : currentTitle }),
      placeholder ? titleFromTranscript(text) : Promise.resolve(null),
    ]);

    const freshMedia = mediaOf(fresh?.attributes).media;
    const durationS = typeof freshMedia.duration_s === 'number' ? freshMedia.duration_s : track?.durationS ?? null;
    const kind = row.type === 'video' ? 'video' : durationS !== null && durationS >= 600 ? 'recording' : 'voice_note';
    const meaningfulName = !isStorageTimestampName(fileName) && !isUuidObjectName(fileName) ? fileName : undefined;
    const mediaPatch: Record<string, unknown> = { kind };
    if (meaningfulName && typeof freshMedia.file_name !== 'string') mediaPatch.file_name = meaningfulName;
    if (durationS !== null && typeof freshMedia.duration_s !== 'number') mediaPatch.duration_s = Math.round(durationS);

    const columns: Record<string, unknown> = {
      page_body: text.slice(0, PAGE_BODY_CAP),
      description: description ?? null,
      summary: summary ?? null,
    };
    if (aiTitle) columns.title = aiTitle;
    await patchItem(
      db,
      itemId,
      { status: 'done', chunks_total: chunksTotal, chunks_done: chunksTotal, source: `openai:${model}`, error: undefined },
      columns,
      mediaPatch,
    );

    const embedText = [aiTitle ?? currentTitle, fresh?.content ?? row.content, text, summary ?? description]
      .filter(Boolean)
      .join(' ');
    const { error: embErr } = await db.functions.invoke('generate-embeddings', {
      body: { itemId, textContent: embedText },
    });
    if (embErr) console.error('transcribe-audio: generate-embeddings failed for', itemId, embErr);
    console.log(`transcribe-audio: ${itemId} done — ${text.length} chars, ${chunksTotal} chunk(s), ${Math.round((Date.now() - started) / 1000)} s`);
  } catch (e) {
    const code = classify(e);
    console.error(`transcribe-audio: ${itemId} failed (${code}):`, e);
    await patchItem(db, itemId, { status: 'failed', error: code });
  }
};

// ---- sweep --------------------------------------------------------------------

const runSweep = async (db: Db) => {
  const windowStart = new Date(Date.now() - SWEEP_WINDOW_DAYS * 86_400_000).toISOString();
  const { data, error } = await db
    .from('items')
    .select('id, attributes')
    .in('type', ['audio', 'video'])
    .not('file_path', 'is', null)
    .gt('created_at', windowStart)
    .or('page_body.is.null,page_body.eq.,attributes->media->transcript->>status.in.(pending,processing,failed)')
    .order('created_at', { ascending: false })
    .limit(60);
  if (error) throw error;

  const now = Date.now();
  const age = (t: TranscriptState) => (t.updated_at ? now - Date.parse(t.updated_at) : Number.POSITIVE_INFINITY);
  const due = (data ?? []).filter((r) => {
    const t = mediaOf((r as { attributes: unknown }).attributes).transcript;
    switch (t.status) {
      case 'done':
        return false;
      case 'pending':
        return age(t) > PENDING_GRACE_MS;
      case 'processing':
        return age(t) > STALE_PROCESSING_MS;
      case 'failed':
        return (t.attempts ?? 0) < MAX_ATTEMPTS && age(t) > FAILED_RETRY_MS;
      default:
        return true; // never attempted (legacy rows)
    }
  });

  const picked = due.slice(0, SWEEP_BATCH).map((r) => (r as { id: string }).id);
  console.log(`transcribe-audio: sweep found ${due.length} due, starting ${picked.length}`);
  for (const id of picked) {
    const t = mediaOf((data ?? []).find((r) => (r as { id: string }).id === id)?.attributes).transcript;
    await runJob(db, id, t.status === 'processing' ? 'continue' : 'sweep');
  }
  return { due: due.length, started: picked };
};

// ---- preview (chip) -------------------------------------------------------------

const preview = async (audioUrl: string, fileName: string | undefined) => {
  if (!audioUrl.startsWith(storagePrefix())) return json(400, { error: 'audioUrl must point at stash-media' });
  const size = await remoteSize(audioUrl);
  if (size > INLINE_MAX_BYTES) {
    return json(200, { transcription: '', description: '', deferred: true });
  }
  const bytes = await downloadWhole(audioUrl);
  const { text } = await transcribeWithFallback(bytes, fileName || basename(audioUrl));
  if (!text) {
    return json(200, { transcription: '', description: 'Audio was processed but no speech was detected.' });
  }
  const description = (await describeTranscript(text)) ?? 'Transcription available';
  return json(200, { transcription: text, description });
};

// ---- auth + routing -------------------------------------------------------------

type Caller = { trusted: true } | { trusted: false; userId: string };

const authenticate = async (req: Request, db: Db): Promise<Caller | null> => {
  const cronSecret = env('CRON_SECRET');
  const presented = req.headers.get('x-cron-secret');
  if (cronSecret && presented && presented === cronSecret) return { trusted: true };
  const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim();
  if (!token) return null;
  if (token === env('SUPABASE_SERVICE_ROLE_KEY')) return { trusted: true };
  if (isAgentToken(token)) return null;
  const { data: { user }, error } = await db.auth.getUser(token);
  if (error || !user) return null;
  return { trusted: false, userId: user.id };
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return json(405, { error: 'Method not allowed' });

  try {
    if (!env('OPENAI_API_KEY')) throw new Error('OpenAI API key not configured');
    const db = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'));
    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;

    const caller = await authenticate(req, db);
    if (!caller) return json(401, { error: 'Unauthorized' });

    if (body.sweep === true) {
      if (!caller.trusted) return json(403, { error: 'Forbidden' });
      return json(200, await runSweep(db));
    }

    if (typeof body.itemId === 'string' && body.itemId) {
      const itemId = body.itemId;
      if (!caller.trusted) {
        const { data } = await db.from('items').select('user_id').eq('id', itemId).single();
        if (!data || data.user_id !== caller.userId) return json(404, { error: 'Item not found' });
      }
      const trigger = body.continue === true ? 'continue' : 'start';
      const work = runJob(db, itemId, trigger);
      const runtime = (globalThis as { EdgeRuntime?: { waitUntil: (p: Promise<unknown>) => void } }).EdgeRuntime;
      if (runtime?.waitUntil) runtime.waitUntil(work);
      else await work;
      return json(202, { accepted: true, itemId });
    }

    if (typeof body.audioUrl === 'string' && body.audioUrl) {
      return await preview(body.audioUrl, typeof body.fileName === 'string' ? body.fileName : undefined);
    }

    return json(400, { error: 'Provide itemId, audioUrl, or sweep' });
  } catch (error) {
    console.error('Error transcribing audio:', error);
    return json(500, {
      error: error instanceof Error ? error.message : 'Unknown error',
      transcription: '',
      description: '',
    });
  }
});
