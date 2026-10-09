import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateJob, validateResult, validateObservation } from './protocol.mjs';
import { createSupervisor } from './supervisor.mjs';
import { auditPrompt } from './runner.mjs';

const itemId = '11111111-1111-4111-8111-111111111111';
const now = Date.now();
const item = { id:itemId, url:'https://example.com/product?color=NAV', page_body:'A winter jacket.' };
const job = () => ({ id:'22222222-2222-4222-8222-222222222222', kind:'research', input:{schema_version:1,items:[item]},
 lease_token:'33333333-3333-4333-8333-333333333333',fence:1,lease_expires_at:new Date(now+60000).toISOString(),
 deadline_at:new Date(now+90000).toISOString(),budget:{max_turns:6,run_seconds:90} });
const observation = () => ({schema_version:1,item_id:itemId,url:item.url,captured_at:new Date(now).toISOString(),
 outcome:'retrieved',title:'Navy jacket',text:'The navy jacket costs $125.',source_truncated:false,
 image_candidates:[{url:'https://images.example.com/jacket_NAV.jpg',associated:true}],
 attempts:[{strategy:'firecrawl_rendered',outcome:'retrieved',reason:'source_captured',duration_ms:1000}],
 limitations:['Image pixels are unverified.']});
const result = () => ({schema_version:1,summary:'A fresh source was checked.',findings:[{item_id:itemId,category:'freshness',severity:'info',
 claim:'A price is available in the current source.',evidence:[{url:item.url,source:'live',quote:'The navy jacket costs $125.'}],
 recommendation:'Review this price with its capture time.'}],proposals:[],uncertainties:[]});
const config={ready:true,model:'test'};

test('research jobs are accepted while unknown job kinds remain rejected',()=>{
 assert.equal(validateJob(job(),now).kind,'research');
 assert.throws(()=>validateJob({...job(),kind:'arbitrary'},now),/unsupported_job_kind/);
});
test('research quotes must cite the recorded live source and never fabricated or foreign evidence',()=>{
 const j={...job(),observation:observation()};
 assert.deepEqual(validateResult(result(),j),result());
 assert.throws(()=>validateResult(result(),job()),/evidence_out_of_scope/);
 assert.throws(()=>validateResult(result(),{...j,observation:{...observation(),outcome:'blocked'}}),/evidence_out_of_scope/);
 const stale=result();delete stale.findings[0].evidence[0].source;
 assert.throws(()=>validateResult(stale,j),/quote_not_in_source/);
 const fake=result();fake.findings[0].evidence[0].quote='The jacket costs $10.';
 assert.throws(()=>validateResult(fake,j),/quote_not_in_source/);
 const foreign=result();foreign.findings[0].evidence[0].url='https://elsewhere.com/';
 assert.throws(()=>validateResult(foreign,j),/evidence_out_of_scope/);
 const wrongItem={...j,observation:{...observation(),item_id:'44444444-4444-4444-8444-444444444444'}};
 assert.throws(()=>validateResult(result(),wrongItem),/evidence_out_of_scope/);
});
test('live retrieval is persisted first and time spent retrieving reduces the Hermes allowance',async()=>{
 let clock=now;const actions=[];
 const s=createSupervisor(config,{now:()=>clock,call:async body=>{
  actions.push(body.action);
  if(body.action==='claim')return {job:job()};
  if(body.action==='investigate'){clock+=25000;return {ok:true,observation:observation()};}
  if(body.action==='complete')return {ok:true,status:'completed'};
  throw new Error('unexpected_action');
 },run:async(_config,j,budget)=>{
  assert.equal(budget.runMs,55000);assert.deepEqual(j.observation,observation());
  return {result:result(),usage:{input_tokens:10}};
 }});
 assert.equal((await s.runOnce()).status,'completed');
 assert.deepEqual(actions,['claim','investigate','complete']);
});
test('foreign or oversized retrieval evidence cannot reach the model',async()=>{
 for(const invalid of [{...observation(),url:'https://other.example.com'}, {...observation(),text:'x'.repeat(6001)}]){
  let modelCalls=0;
  const s=createSupervisor(config,{call:async body=>body.action==='claim'?{job:job()}:body.action==='investigate'?{ok:true,observation:invalid}:{ok:true},
   run:async()=>{modelCalls++;return {result:result(),usage:{}};}});
  assert.equal((await s.runOnce()).status,'failed');assert.equal(modelCalls,0);
 }
});
test('research prompt distinguishes source times, page association, and unverified image pixels',()=>{
 const prompt=auditPrompt({...job(),observation:observation()});
 assert.match(prompt,/BEGIN UNTRUSTED LIVE EVIDENCE JSON/);
 assert.match(prompt,/source.*live/);
 assert.match(prompt,/cannot verify.*pixels/i);
 assert.ok(prompt.includes(JSON.stringify(observation())));
 assert.match(prompt,/propos/i);
});
test('a rejected sensitive URL is not forwarded to the model in either snapshot or observation',()=>{
 const secretUrl='https://example.com/product?api_key=PRIVATE_CANARY';
 const j={...job(),input:{schema_version:1,items:[{...item,url:secretUrl}]},observation:{...observation(),url:secretUrl,outcome:'unavailable',text:'',title:'',image_candidates:[],attempts:[{strategy:'firecrawl_rendered',outcome:'unavailable',reason:'unsafe_url',duration_ms:0}]}};
 assert.ok(!auditPrompt(j).includes('PRIVATE_CANARY'));
});

test('observation accepts three known strategies and rejects malformed telemetry',()=>{
 const attempt=observation().attempts[0];
 const attempts=[attempt,{...attempt,strategy:'jina_reader'},{...attempt,strategy:'medium_public_feed'}];
 assert.deepEqual(validateObservation({...observation(),attempts},job()).attempts,attempts);
 for(const bad of [[],[...attempts,attempt],[{...attempt,strategy:'arbitrary_browser'}],[{...attempt,outcome:'fixed'}],[{...attempt,duration_ms:0.5}]]){
  assert.throws(()=>validateObservation({...observation(),attempts:bad},job()));
 }
});
test('research prompt explains strategy escalation and feed-only evidence limits',()=>{
 const prompt=auditPrompt({...job(),observation:observation()});
 assert.match(prompt,/up to three bounded retrieval strategies/i);
 assert.match(prompt,/public_feed_artwork_only/);
 assert.doesNotMatch(prompt,/recorded ONE browser-rendering attempt/);
});

test('refused private URLs reach Hermes only as empty, redacted refusal evidence',async()=>{
 const privateUrl='https://127.0.0.1/?token=PRIVATE_CANARY';
 const refusal={...observation(),url:privateUrl,outcome:'unavailable',text:'',title:'',image_candidates:[],
  attempts:[{strategy:'firecrawl_rendered',outcome:'unavailable',reason:'unsafe_url',duration_ms:0}]};
 const j={...job(),input:{schema_version:1,items:[{...item,url:privateUrl}]}};
 assert.deepEqual(validateObservation(refusal,j),refusal);
 assert.ok(!auditPrompt({...j,observation:refusal}).includes('PRIVATE_CANARY'));
 for(const patch of [{title:'secret source'},{text:'secret source'},{image_candidates:observation().image_candidates},{outcome:'retrieved'},{source_truncated:true},{attempts:[...refusal.attempts,...refusal.attempts]}]){
  assert.throws(()=>validateObservation({...refusal,...patch},j));
 }
});
test('prompt requests exact quotes and testable proposals without relaxing source evidence',()=>{
 const prompt=auditPrompt({...job(),observation:observation()});
 assert.match(prompt,/copy quotes verbatim/i);
 assert.match(prompt,/concrete regression case/i);
 assert.match(prompt,/expected effect/i);
});
