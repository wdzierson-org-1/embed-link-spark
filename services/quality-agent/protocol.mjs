import { createHash, timingSafeEqual } from 'node:crypto';

export const HARD_MAX_TURNS = 6;
export const HARD_RUN_MS = 90_000;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const object = x => !!x && typeof x === 'object' && !Array.isArray(x);
function keys(x, allowed) { if (!object(x) || Object.keys(x).some(k => !allowed.includes(k))) throw new Error('invalid_fields'); }
function text(x, max, optional = false) { if (optional && x === undefined) return; if (typeof x !== 'string' || !x.trim() || x.length > max) throw new Error('invalid_text'); }
function list(x, max) { if (!Array.isArray(x) || x.length > max) throw new Error('invalid_list'); }
const normalize = value => value.replace(/\s+/g, ' ').trim();

export function authorized(actual, token) {
  if (typeof token !== 'string' || token.length < 32 || typeof actual !== 'string' || actual.length > 512) return false;
  const digest = value => createHash('sha256').update(value).digest();
  return timingSafeEqual(digest(actual), digest(`Bearer ${token}`));
}

// A syntax gate, not a DNS/egress guard. Retrieval is owned by the backend;
// Hermes has no browsing tools or retrieval-provider credential.
export function publicEvidenceUrl(value) {
  if (typeof value !== 'string' || value.length > 2000) return false;
  try {
    const u = new URL(value); const h = u.hostname.toLowerCase();
    return u.protocol === 'https:' && !u.username && !u.password && (!u.port || u.port === '443') &&
      h.includes('.') && !h.includes(':') && !/^\d+(\.\d+)*$/.test(h) &&
      !/(^|\.)(localhost|local|internal|invalid)$/.test(h);
  } catch { return false; }
}

export function validateJob(job, now = Date.now()) {
  if (!object(job) || !uuid.test(job.id) || !uuid.test(job.lease_token) || !Number.isSafeInteger(job.fence) || job.fence < 1 ||
    !Number.isFinite(Date.parse(job.lease_expires_at)) || Date.parse(job.lease_expires_at) <= now ||
    !Number.isFinite(Date.parse(job.deadline_at)) || Date.parse(job.deadline_at) <= now) throw new Error('invalid_lease');
  if (!['audit', 'research'].includes(job.kind)) throw new Error('unsupported_job_kind');
  if (!object(job.input) || job.input.schema_version !== 1 || !Array.isArray(job.input.items) || job.input.items.length > 50 ||
    job.input.items.some(i => !object(i) || !uuid.test(i.id)) || JSON.stringify(job.input).length > 256_000) throw new Error('invalid_input');
  if (!object(job.budget) || !Number.isSafeInteger(job.budget.max_turns) || job.budget.max_turns < 1 ||
    !Number.isSafeInteger(job.budget.run_seconds) || job.budget.run_seconds < 1) throw new Error('invalid_budget');
  return job;
}

export function jobBudget(job, now = Date.now()) {
  const runMs = Math.min(HARD_RUN_MS, job.budget.run_seconds * 1000, Date.parse(job.deadline_at) - now) - 10_000;
  if (runMs <= 0) throw new Error('insufficient_time');
  return { maxTurns: Math.min(HARD_MAX_TURNS, job.budget.max_turns), runMs };
}

export function validateObservation(observation, job) {
  if (!object(observation) || JSON.stringify(observation).length > 32_000 || observation.schema_version !== 1) throw new Error('invalid_observation');
  const item = job.input.items.find(i => i.id === observation.item_id);
  if (!item || observation.url !== item.url || !publicEvidenceUrl(observation.url)) throw new Error('evidence_out_of_scope');
  if (!Number.isFinite(Date.parse(observation.captured_at)) || !['retrieved', 'blocked', 'unavailable', 'mismatch'].includes(observation.outcome) ||
    typeof observation.title !== 'string' || observation.title.length > 400 || typeof observation.text !== 'string' || observation.text.length > 6000 ||
    typeof observation.source_truncated !== 'boolean') throw new Error('invalid_observation');
  list(observation.image_candidates, 5); list(observation.attempts, 3); list(observation.limitations, 10);
  for (const image of observation.image_candidates) if (!object(image) || !publicEvidenceUrl(image.url) || typeof image.associated !== 'boolean') throw new Error('invalid_observation');
  for (const attempt of observation.attempts) {
    if (!object(attempt)) throw new Error('invalid_observation');
    text(attempt.strategy, 100); text(attempt.outcome, 100); text(attempt.reason, 200);
    if (!Number.isFinite(attempt.duration_ms) || attempt.duration_ms < 0 || attempt.duration_ms > 30_000) throw new Error('invalid_observation');
  }
  observation.limitations.forEach(x => text(x, 1000));
  return observation;
}

// Keep bounds aligned with quality-worker. This checks shape and source scope,
// not whether a model's interpretation of the source is correct.
export function validateResult(result, job) {
  keys(result, ['schema_version', 'summary', 'findings', 'proposals', 'uncertainties']);
  if (result.schema_version !== 1) throw new Error('invalid_schema_version');
  text(result.summary, 6000); list(result.findings, 20); list(result.proposals, 5); list(result.uncertainties, 20);
  const items = new Map(job.input.items.map(i => [i.id, i]));
  for (const finding of result.findings) {
    keys(finding, ['item_id', 'category', 'severity', 'claim', 'evidence', 'recommendation']);
    if (finding.item_id !== undefined && !items.has(finding.item_id)) throw new Error('item_out_of_scope');
    if (!finding.item_id && finding.category !== 'operations') throw new Error('item_required');
    if (!['identity', 'summary_grounding', 'image_association', 'source_completeness', 'freshness', 'retrieval', 'operations'].includes(finding.category)) throw new Error('invalid_category');
    if (!['info', 'warning', 'error'].includes(finding.severity)) throw new Error('invalid_severity');
    text(finding.claim, 1500); text(finding.recommendation, 1500); list(finding.evidence, 5);
    if (finding.category !== 'operations' && !finding.evidence.length) throw new Error('evidence_required');
    const item = items.get(finding.item_id);
    for (const evidence of finding.evidence) {
      keys(evidence, ['url', 'quote', 'source']);
      if (!publicEvidenceUrl(evidence.url)) throw new Error('invalid_evidence_url');
      text(evidence.quote, 1000, true);
      if (!item || evidence.url !== item.url) throw new Error('evidence_out_of_scope');
      if (evidence.source !== undefined && !['snapshot', 'live'].includes(evidence.source)) throw new Error('invalid_evidence_source');
      const live = evidence.source === 'live';
      if (live && (job.kind !== 'research' || job.observation?.outcome !== 'retrieved' || job.observation?.item_id !== item.id || job.observation?.url !== item.url)) throw new Error('evidence_out_of_scope');
      const source = live ? job.observation.text : item.page_body;
      if (evidence.quote && !normalize(source || '').includes(normalize(evidence.quote))) throw new Error('quote_not_in_source');
    }
  }
  for (const proposal of result.proposals) {
    keys(proposal, ['title', 'rationale', 'evidence_urls']); text(proposal.title, 200); text(proposal.rationale, 2000); list(proposal.evidence_urls, 5);
    if (!proposal.evidence_urls.length || proposal.evidence_urls.some(u => !publicEvidenceUrl(u))) throw new Error('invalid_proposal_evidence');
    if (proposal.evidence_urls.some(u => ![...items.values()].some(i => i.url === u))) throw new Error('evidence_out_of_scope');
  }
  result.uncertainties.forEach(x => text(x, 1000));
  return result;
}

export function parseOutput(output, job) {
  if (Buffer.byteLength(output) > 2_000_000) throw new Error('output_limit');
  let terminal;
  for (const line of output.split('\n')) {
    if (!line.trim()) continue;
    if (Buffer.byteLength(line) > 128_000) throw new Error('output_limit');
    let event; try { event = JSON.parse(line); } catch { throw new Error('invalid_stream'); }
    if (!object(event) || typeof event.type !== 'string') throw new Error('invalid_stream');
    if (event.type !== 'result') continue;
    if (terminal) throw new Error('invalid_terminal_result');
    terminal = event;
  }
  if (!terminal) throw new Error('invalid_terminal_result');
  if (terminal.exit_code !== 0 || terminal.error) throw new Error('hermes_failed');
  if (typeof terminal.text !== 'string' || terminal.text.length > 64_000) throw new Error('invalid_result_json');
  let result; try { result = JSON.parse(terminal.text); } catch { throw new Error('invalid_result_json'); }
  const usage = { input_tokens: null, output_tokens: null };
  for (const [from, to] of [['input', 'input_tokens'], ['output', 'output_tokens']]) {
    const n = terminal.tokens?.[from];
    if (Number.isSafeInteger(n) && n >= 0 && n <= 10_000_000) usage[to] = n;
  }
  // Hermes can report an all-zero usage object when a streamed response omits
  // usage. A completed answer does not establish that the model call was free.
  if (!(usage.input_tokens > 0) && !(usage.output_tokens > 0)) {
    usage.input_tokens = null; usage.output_tokens = null;
  }
  return { result: validateResult(result, job), usage };
}
