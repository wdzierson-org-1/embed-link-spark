import test from 'node:test';
import assert from 'node:assert/strict';
import { parseLeasePath, prepareModelRequest } from './policy.mjs';

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
