import { test } from 'node:test';
import assert from 'node:assert/strict';
import { authorized, validateJob, validateResult, parseOutput, jobBudget } from './protocol.mjs';

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
