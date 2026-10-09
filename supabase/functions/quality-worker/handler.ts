type Env = (name: string) => string | undefined;
type DB = { rpc: (name: string, args: Record<string, unknown>) => Promise<{ data: any; error: any }> };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const object = (x: any): x is Record<string, any> => !!x && typeof x === 'object' && !Array.isArray(x);
function keys(x: any, allowed: string[]) { if (!object(x) || Object.keys(x).some(k => !allowed.includes(k))) throw new Error('invalid_fields'); }
function text(x: any, max: number, optional = false) { if (optional && x === undefined) return; if (typeof x !== 'string' || !x.trim() || x.length > max) throw new Error('invalid_text'); }
function list(x: any, max: number) { if (!Array.isArray(x) || x.length > max) throw new Error('invalid_list'); }

export async function authorized(actual: string | null, expected?: string): Promise<boolean> {
  if (!expected || !actual || actual.length > 512) return false;
  const digest = async (value: string) => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
  const [a, b] = await Promise.all([digest(actual), digest(expected)]);
  let diff = 0; for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]; return diff === 0;
}
export async function readBody(req: Request, limit = 128_000): Promise<any> {
  const reader = req.body?.getReader(); if (!reader) throw new Error('invalid_json');
  const chunks: Uint8Array[] = []; let length = 0;
  try { while (true) { const { done, value } = await reader.read(); if (done) break; length += value.length;
    if (length > limit) { await reader.cancel(); throw new Error('body_too_large'); } chunks.push(value); }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length); let offset = 0; for (const c of chunks) { bytes.set(c, offset); offset += c.length; }
  try { return JSON.parse(new TextDecoder().decode(bytes)); } catch { throw new Error('invalid_json'); }
}
/** Syntax gate only; this API does not fetch citations. Browser egress is separately constrained. */
export function publicEvidenceUrl(value: unknown): value is string {
  if (typeof value !== 'string' || value.length > 2000) return false;
  try { const u = new URL(value); const h = u.hostname.toLowerCase();
    return u.protocol === 'https:' && !u.username && !u.password && (!u.port || u.port === '443') &&
      h.includes('.') && !h.includes(':') && !/^\d+(\.\d+)*$/.test(h) &&
      !/(^|\.)(localhost|local|internal|invalid)$/.test(h);
  } catch { return false; }
}
const normalize = (s: string) => s.replace(/\s+/g, ' ').trim();
export function validateResult(result: any, job: any) {
  keys(result, ['schema_version', 'summary', 'findings', 'proposals', 'uncertainties']);
  if (result.schema_version !== 1) throw new Error('invalid_schema_version');
  text(result.summary, 6000); list(result.findings, 20); list(result.proposals, 5); list(result.uncertainties, 20);
  const items = new Map<string, any>((job.input?.items || []).map((i: any) => [i.id, i]));
  for (const finding of result.findings) {
    keys(finding, ['item_id', 'category', 'severity', 'claim', 'evidence', 'recommendation']);
    if (finding.item_id !== undefined && !items.has(finding.item_id)) throw new Error('item_out_of_scope');
    if (job.kind === 'audit' && !finding.item_id && finding.category !== 'operations') throw new Error('item_required');
    if (!['identity', 'summary_grounding', 'image_association', 'source_completeness', 'freshness', 'retrieval', 'operations'].includes(finding.category)) throw new Error('invalid_category');
    if (!['info', 'warning', 'error'].includes(finding.severity)) throw new Error('invalid_severity');
    text(finding.claim, 1500); text(finding.recommendation, 1500); list(finding.evidence, 5);
    if (finding.category !== 'operations' && !finding.evidence.length) throw new Error('evidence_required');
    const item = items.get(finding.item_id);
    for (const evidence of finding.evidence) {
      keys(evidence, ['url', 'quote']); if (!publicEvidenceUrl(evidence.url)) throw new Error('invalid_evidence_url');
      text(evidence.quote, 1000, true);
      if (job.kind === 'audit') {
        if (!item || evidence.url !== item.url) throw new Error('evidence_out_of_scope');
        if (evidence.quote && !normalize(item.page_body || '').includes(normalize(evidence.quote))) throw new Error('quote_not_in_source');
      }
    }
  }
  for (const proposal of result.proposals) {
    keys(proposal, ['title', 'rationale', 'evidence_urls']); text(proposal.title, 200); text(proposal.rationale, 2000); list(proposal.evidence_urls, 5);
    if (!proposal.evidence_urls.length || proposal.evidence_urls.some((u: any) => !publicEvidenceUrl(u))) throw new Error('invalid_proposal_evidence');
    if (job.kind === 'audit' && proposal.evidence_urls.some((u: string) => ![...items.values()].some(i => i.url === u))) throw new Error('evidence_out_of_scope');
  }
  result.uncertainties.forEach((x: unknown) => text(x, 1000));
  return result;
}
function validateUsage(usage: any) {
  if (usage === undefined) return {};
  keys(usage, ['model', 'input_tokens', 'output_tokens', 'cost_usd']); text(usage.model, 100, true);
  for (const key of ['input_tokens', 'output_tokens', 'cost_usd']) if (usage[key] !== undefined && usage[key] !== null &&
    (typeof usage[key] !== 'number' || !Number.isFinite(usage[key]) || usage[key] < 0 || usage[key] > (key === 'cost_usd' ? 1000 : 10_000_000) || (key !== 'cost_usd' && !Number.isInteger(usage[key])))) throw new Error('invalid_usage');
  return usage;
}
export function createWorkerHandler({ db, env }: { db: DB; env: Env }) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return json(405, { error: 'post_only' });
    const workerToken = env('QUALITY_WORKER_TOKEN');
    if (!workerToken || workerToken.length < 32 || !await authorized(req.headers.get('authorization'), `Bearer ${workerToken}`)) return json(401, { error: 'unauthorized' });
    try {
      const body = await readBody(req);
      const call = async (name: string, args: Record<string, unknown>) => { const r = await db.rpc(name, args); if (r.error) throw new Error('database_error'); return r.data; };
      if (body?.action === 'claim') {
        keys(body, ['action']);
        if (env('QUALITY_ENABLED') !== 'true') return json(200, { job: null, disabled: true });
        return json(200, { job: await call('claim_hosted_quality_job', {}) });
      }
      if (!['heartbeat', 'complete', 'fail'].includes(body?.action)) throw new Error('invalid_action');
      keys(body, ['action', 'job_id', 'lease_token', 'fence', ...(body.action === 'complete' ? ['result', 'usage'] : body.action === 'fail' ? ['reason'] : [])]);
      if (!uuid.test(body.job_id) || !uuid.test(body.lease_token) || !Number.isSafeInteger(body.fence) || body.fence < 1) throw new Error('invalid_lease');
      const args = { target_id: body.job_id, token: body.lease_token, expected_fence: body.fence };
      let result;
      if (body.action === 'complete') {
        const usage = validateUsage(body.usage);
        const job = await call('hosted_quality_job_context', args);
        if (!job) return json(409, { error: 'lease_lost' });
        validateResult(body.result, job);
        result = await call('complete_hosted_quality_job', { ...args, result_payload: body.result, usage_payload: usage });
      } else if (body.action === 'fail') {
        text(body.reason, 500);
        // Persist error codes/short messages, never credentials or request payloads.
        result = await call('fail_hosted_quality_job', { ...args, failure_reason: body.reason.replace(/https?:\/\/\S+/g, '[url]').replace(/Bearer\s+\S+/gi, '[credential]') });
      } else result = await call('heartbeat_hosted_quality_job', args);
      return json(result?.ok ? 200 : 409, result || { error: 'lease_lost' });
    } catch (e) {
      const error = e instanceof Error ? e.message : 'invalid_request';
      if (error === 'database_error') return json(503, { error });
      return json(error === 'body_too_large' ? 413 : 400, { error });
    }
  };
}
