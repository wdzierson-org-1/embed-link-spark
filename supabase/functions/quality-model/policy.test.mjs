import test from 'node:test';
import assert from 'node:assert/strict';
import { parseLeasePath, prepareModelRequest } from './policy.mjs';
import { validateResult } from '../../../services/quality-agent/protocol.mjs';

test('proxy accepts only the leased job chat completion path', () => {
  const id = '10000000-0000-4000-8000-000000000001';
  assert.deepEqual(parseLeasePath(`/quality-model/${id}/3/v1/chat/completions`), { id, fence: 3 });
  for (const path of [`/quality-model/${id}/0/v1/chat/completions`, `/quality-model/${id}/3/v1/files`, '/quality-model/anything/3/v1/chat/completions']) {
    assert.equal(parseLeasePath(path), null);
  }
});

test('server fixes model, completion limit and allowed transport fields', () => {
  const out = prepareModelRequest({ model: 'unapproved', messages: [{ role: 'user', content: 'check this fact' }], stream: true, max_tokens: 100000, store: true, user: 'leak', metadata: { private: 'data' } }, 'gpt-4.1');
  assert.equal(out.model, 'gpt-4.1');
  assert.equal(out.max_tokens, 4096);
  assert.equal(out.store, false);
  assert.equal(out.stream, true);
  assert.deepEqual(out.stream_options, { include_usage: true });
  assert.equal(out.user, undefined);
  assert.equal(out.metadata, undefined);
});

test('requires bounded text conversations and prohibits remote image fetching', () => {
  for (const messages of [[], [{role:'user', content:[{type:'image_url',image_url:{url:'http://127.0.0.1/'}}]}], [{role:'user',content:'x'.repeat(64001)}], [{role:'unknown',content:'text'}]]) {
    assert.throws(() => prepareModelRequest({messages}, 'gpt-4.1'));
  }
});

test('allows tool messages for compatible clients without expanding tool permissions', () => {
  const out = prepareModelRequest({messages:[{role:'assistant',content:null,tool_calls:[{id:'call_1',type:'function',function:{name:'fetch',arguments:'{}'}}]},{role:'tool',tool_call_id:'call_1',content:'observed source'}], tools:[{type:'function',function:{name:'fetch',parameters:{type:'object'}}}]}, 'gpt-4.1');
  assert.equal(out.messages[1].tool_call_id, 'call_1');
  assert.equal(out.tools, undefined);
});

test('server enforces a strict result schema without changing streaming or allowing caller overrides', () => {
  for (const stream of [false, true]) {
    const out = prepareModelRequest({ messages: [{ role: 'user', content: 'Audit the supplied source.' }], stream,
      response_format: { type: 'text' }, tools: [{ type: 'function' }] }, 'gpt-4.1');
    assert.equal(out.response_format?.type, 'json_schema');
    assert.equal(out.response_format.json_schema.name, 'stash_quality_result_v1');
    assert.equal(out.response_format.json_schema.strict, true);
    assert.equal(out.stream, stream); assert.equal(out.max_tokens, 4096); assert.equal(out.store, false);
    assert.equal(out.tools, undefined); assert.equal(out.model, 'gpt-4.1');
    assert.deepEqual(out.stream_options, stream ? { include_usage: true } : undefined);
  }
});

test('every schema object is closed and requires its listed fields; the root stays an object', () => {
  const schema = prepareModelRequest({ messages: [{ role: 'user', content: 'Audit.' }] }, 'gpt-4.1').response_format?.json_schema.schema;
  assert.equal(schema?.type, 'object'); assert.equal(schema.anyOf, undefined);
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'object') {
      assert.equal(node.additionalProperties, false);
      assert.deepEqual([...node.required].sort(), Object.keys(node.properties).sort());
    }
    for (const value of Object.values(node)) if (value && typeof value === 'object') {
      if (Array.isArray(value)) value.forEach(walk); else walk(value);
    }
  };
  walk(schema);
});

test('strict output exposes only existing finding fields and explicit source citations', () => {
  const schema = prepareModelRequest({ messages: [{ role: 'user', content: 'Audit.' }] }, 'gpt-4.1').response_format?.json_schema.schema;
  assert.ok(schema); assert.deepEqual(schema.properties.schema_version.enum, [1]);
  assert.equal(schema.properties.findings.maxItems, 20); assert.equal(schema.properties.findings.minItems, 0);
  assert.equal(schema.properties.proposals.maxItems, 5); assert.equal(schema.properties.uncertainties.maxItems, 20);
  const [item, operations] = schema.properties.findings.items.anyOf;
  assert.deepEqual(Object.keys(item.properties).sort(), ['item_id', 'category', 'severity', 'claim', 'evidence', 'recommendation'].sort());
  assert.deepEqual(item.properties.category.enum, ['identity', 'summary_grounding', 'image_association', 'source_completeness', 'freshness', 'retrieval', 'operations']);
  assert.deepEqual(item.properties.severity.enum, ['info', 'warning', 'error']);
  assert.equal(item.properties.evidence.minItems, 1);
  assert.deepEqual(item.properties.evidence.items.required, ['url', 'quote', 'source']);
  assert.deepEqual(item.properties.evidence.items.properties.source.enum, ['snapshot', 'live']);
  assert.equal(item.properties.evidence.items.properties.quote.type, 'string');
  assert.deepEqual(operations.properties.category.enum, ['operations']);
  assert.equal(operations.properties.item_id, undefined); assert.equal(operations.properties.evidence.maxItems, 0);
});


test('schema-compatible results still require exact quotes and in-scope sources', () => {
  const id = '10000000-0000-4000-8000-000000000001'; const url = 'https://example.com/article';
  const job = { kind: 'audit', input: { items: [{ id, url, page_body: 'The starting price is $100.' }] } };
  const result = { schema_version: 1, summary: 'One qualification omitted.', findings: [{ item_id: id,
    category: 'summary_grounding', severity: 'warning', claim: 'Starting price became a fixed price.',
    evidence: [{ url, quote: 'The starting price is $100.', source: 'snapshot' }], recommendation: 'Keep the starting-price qualification.' }], proposals: [], uncertainties: [] };
  assert.equal(validateResult(result, job), result);
  const wrongQuote = structuredClone(result); wrongQuote.findings[0].evidence[0].quote = 'All items cost $100.';
  assert.throws(() => validateResult(wrongQuote, job), /quote_not_in_source/);
  const foreign = structuredClone(result); foreign.findings[0].evidence[0].url = 'https://other.example/article';
  assert.throws(() => validateResult(foreign, job), /evidence_out_of_scope/);
  const operations = { ...result, findings: [{ category: 'operations', severity: 'info', claim: 'Source is unavailable.', evidence: [], recommendation: 'Retain the uncertainty.' }] };
  assert.equal(validateResult(operations, job), operations);
});
