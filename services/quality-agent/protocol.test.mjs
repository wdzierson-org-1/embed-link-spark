import { test } from 'node:test';
import assert from 'node:assert/strict';
import { authorized, validateJob, validateResult, validateObservation, parseOutput, jobBudget } from './protocol.mjs';

export const itemId = '11111111-1111-4111-8111-111111111111';
export function job(now = Date.now()) {
  return { id: '22222222-2222-4222-8222-222222222222', kind: 'audit', input_hash: 'abc',
    input: { schema_version: 1, items: [{ id: itemId, url: 'https://example.com/article', page_body: 'The price starts at $100.' }] },
    lease_token: '33333333-3333-4333-8333-333333333333', fence: 1,
    lease_expires_at: new Date(now + 60_000).toISOString(), deadline_at: new Date(now + 90_000).toISOString(),
    budget: { max_turns: 6, run_seconds: 90 } };
}
export function result() { return { schema_version: 1, summary: 'One qualification was omitted.', findings: [{
  item_id: itemId, category: 'summary_grounding', severity: 'warning', claim: 'The starting price became a fixed price.',
  evidence: [{ url: 'https://example.com/article', quote: 'price starts at $100' }], recommendation: 'Retain the starting-price qualifier.'
}], proposals: [], uncertainties: [] }; }
export function stream(value = result(), overrides = {}) { return [JSON.stringify({ type: 'system', subtype: 'init' }), JSON.stringify({ type: 'result', exit_code: 0, text: JSON.stringify(value), tokens: { input: 15, output: 20 }, ...overrides })].join('\n') + '\n'; }

test('wake bearer authorization handles correct, wrong and different-length tokens', () => {
  const token = 'a'.repeat(40);
  assert.equal(authorized(`Bearer ${token}`, token), true);
  assert.equal(authorized(`Bearer ${'b'.repeat(40)}`, token), false);
  assert.equal(authorized('Bearer x', token), false);
  assert.equal(authorized(undefined, token), false);
  assert.equal(authorized('Bearer short', 'short'), false);
});
test('job validation rejects expired leases and unsupported job modes', () => {
  const now = Date.now();
  assert.equal(validateJob(job(now), now).kind, 'audit');
  assert.throws(() => validateJob({ ...job(now), kind: 'unbounded' }, now), /unsupported_job_kind/);
  assert.throws(() => validateJob({ ...job(now), lease_expires_at: new Date(now - 1).toISOString() }, now), /invalid_lease/);
});
test('hard pilot caps cannot be raised by a job and leave time for completion', () => {
  const now = Date.now(); const j = job(now); j.budget = { max_turns: 999, run_seconds: 999 };
  assert.deepEqual(jobBudget(j, now), { maxTurns: 6, runMs: 80_000 });
  j.deadline_at = new Date(now + 25_000).toISOString();
  assert.deepEqual(jobBudget(j, now), { maxTurns: 6, runMs: 15_000 });
});
test('schema gate accepts evidence in scope but rejects foreign IDs, URLs and invented quotes', () => {
  assert.deepEqual(validateResult(result(), job()), result());
  let value = result(); value.findings[0].item_id = 'other';
  assert.throws(() => validateResult(value, job()), /item_out_of_scope/);
  value = result(); value.findings[0].evidence[0].url = 'https://elsewhere.com';
  assert.throws(() => validateResult(value, job()), /evidence_out_of_scope/);
  value = result(); value.findings[0].evidence[0].quote = 'All services cost $100';
  assert.throws(() => validateResult(value, job()), /quote_not_in_source/);
  value = result(); value.extra = 'unrecognized';
  assert.throws(() => validateResult(value, job()), /invalid_fields/);
});
test('structured output requires one successful terminal result and ignores tool text', () => {
  assert.deepEqual(parseOutput(stream(), job()).result, result());
  assert.throws(() => parseOutput(stream() + stream(), job()), /invalid_terminal_result/);
  assert.throws(() => parseOutput(stream(undefined, { exit_code: 1 }), job()), /hermes_failed/);
  assert.throws(() => parseOutput('unstructured output\n', job()), /invalid_stream/);
  assert.throws(() => parseOutput(stream(undefined, { text: '```json\n{}\n```' }), job()), /invalid_result_json/);
  assert.throws(() => parseOutput(JSON.stringify({ type: 'text', text: JSON.stringify(result()) }), job()), /invalid_terminal_result/);
});
test('zero or missing terminal usage stays unknown rather than implying a free model call', () => {
  assert.deepEqual(parseOutput(stream(undefined, { tokens: { input: 0, output: 0 } }), job()).usage,
    { input_tokens: null, output_tokens: null });
  assert.deepEqual(parseOutput(stream(undefined, { tokens: undefined }), job()).usage,
    { input_tokens: null, output_tokens: null });
  assert.deepEqual(parseOutput(stream(undefined, { tokens: { input: 15, output: 0 } }), job()).usage,
    { input_tokens: 15, output_tokens: 0 });
});

const source = 'https://example.com/article';
const observation = { schema_version: 1, item_id: itemId, url: source, captured_at: '2026-10-10T12:00:00Z', outcome: 'retrieved', title: 'An article', text: 'The price starts at $100.', source_truncated: false, image_candidates: [], attempts: [{ strategy: 'firecrawl_rendered', outcome: 'retrieved', reason: 'rendered_source', duration_ms: 123 }], limitations: [] };

const assetUrl = 'https://media.licdn.com/dms/image/v2/person/photo.jpg';
const assetCheck = () => ({ url: assetUrl, source_url: source, associated: true,
  strategy: 'public_raster_fetch', outcome: 'usable_asset', reason: 'raster_structure_valid',
  checked_at: '2026-10-10T12:00:00Z', duration_ms: 125, mime_type: 'image/jpeg',
  byte_length: 1000, width: 400, height: 400, sha256: 'a'.repeat(64) });
const checkedObservation = () => ({ ...structuredClone(observation),
  image_candidates: [{ url: assetUrl, associated: true }], image_checks: [assetCheck()],
  limitations: ['image_pixels_not_verified', 'image_decode_not_verified'] });
const invalidAssetMutations = [
  ['second check', o => o.image_checks.push(assetCheck())],
  ['unrelated source', o => { o.image_checks[0].source_url = 'https://other.example/article'; }],
  ['unrelated image', o => { o.image_checks[0].url = 'https://media.licdn.com/other.jpg'; }],
  ['unassociated image', o => { o.image_candidates[0].associated = false; }],
  ['second associated candidate', o => { o.image_candidates.unshift({ url: 'https://media.licdn.com/first.jpg', associated: true }); }],
  ['claimed visual match', o => { o.image_checks[0].visual_match = true; }],
  ['unknown top level field', o => { o.visual_match = true; }],
  ['unknown strategy', o => { o.image_checks[0].strategy = 'browser_magic'; }],
  ['unknown outcome', o => { o.image_checks[0].outcome = 'matched'; }],
  ['unknown reason', o => { o.image_checks[0].reason = 'secret from exception'; }],
  ['wrong reason/outcome pair', o => { o.image_checks[0].reason = 'image_timeout'; }],
  ['missing hash', o => { delete o.image_checks[0].sha256; }],
  ['invalid hash', o => { o.image_checks[0].sha256 = 'xxx'; }],
  ['missing dimensions', o => { delete o.image_checks[0].width; }],
  ['tiny usable asset', o => { o.image_checks[0].width = 1; }],
  ['large usable asset', o => { o.image_checks[0].width = 12001; }],
  ['pixel budget overflow', o => { o.image_checks[0].width = 10000; o.image_checks[0].height = 10000; }],
  ['missing bytes', o => { delete o.image_checks[0].byte_length; }],
  ['excess bytes', o => { o.image_checks[0].byte_length = 5242881; }],
  ['fractional bytes', o => { o.image_checks[0].byte_length = 100.1; }],
  ['zero bytes', o => { o.image_checks[0].byte_length = 0; }],
  ['unsupported MIME', o => { o.image_checks[0].mime_type = 'image/svg+xml'; }],
  ['missing MIME', o => { delete o.image_checks[0].mime_type; }],
  ['invalid timestamp', o => { o.image_checks[0].checked_at = 'yesterday'; }],
  ['excess duration', o => { o.image_checks[0].duration_ms = 10001; }],
  ['negative duration', o => { o.image_checks[0].duration_ms = -1; }],
  ['fractional duration', o => { o.image_checks[0].duration_ms = 0.1; }],
  ['missing interpretation limit', o => { o.limitations = []; }],
  ['failed check with success hash', o => { o.image_checks[0].outcome = 'invalid'; o.image_checks[0].reason = 'image_too_small'; }],
  ['check containing credential URL', o => { const target = assetUrl + '?token=secret'; o.image_candidates[0].url = target; o.image_checks[0].url = target; }],
];

test('image evidence protocol accepts valid asset, no-check legacy and failed check observations', () => {
  assert.deepEqual(validateObservation(checkedObservation(), job()), checkedObservation());
  assert.deepEqual(validateObservation(observation, job()), observation);
  for (const [outcome, reason] of [['unavailable', 'unsupported_image_host'], ['unavailable', 'image_timeout'], ['invalid', 'non_raster_response']]) {
    const value = checkedObservation(); value.image_checks = [{ url: assetUrl, source_url: source, associated: true, strategy: 'public_raster_fetch', outcome, reason, checked_at: '2026-10-10T12:00:00Z', duration_ms: 20 }];
    assert.deepEqual(validateObservation(value, job()), value);
  }
});
for (const [name, mutate] of invalidAssetMutations) test(`image evidence protocol rejects ${name}`, () => {
  const value = checkedObservation(); mutate(value); assert.throws(() => validateObservation(value, job()));
});
test('image evidence protocol forbids check payload on an unsafe source refusal', () => {
  const j = job(); j.input.items[0].url = 'https://example.com/?access_token=secret';
  const value = { ...checkedObservation(), url: j.input.items[0].url, outcome: 'unavailable', title: '', text: '', image_candidates: [], attempts: [{ strategy: 'firecrawl_rendered', outcome: 'unavailable', reason: 'unsafe_url', duration_ms: 0 }] };
  assert.throws(() => validateObservation(value, j));
});
