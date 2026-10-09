// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { createDispatchHandler } from './handler';
const values: Record<string,string> = { CRON_SECRET:'cron-secret', QUALITY_ENABLED:'true', QUALITY_SCOPE_USER_IDS:'11111111-1111-4111-8111-111111111111', QUALITY_WORKER_URL:'https://worker.example.org', QUALITY_WAKE_TOKEN:'w'.repeat(40), QUALITY_REPORT_RECIPIENT:'will@example.org', RESEND_API_KEY:'resend-test' };
const request = () => new Request('https://backend.example/quality-dispatch', {method:'POST',headers:{'x-cron-secret':values.CRON_SECRET},body:'{}'});
const outbox={id:'email-id',lease_token:'email-lease',idempotency_key:'hosted-quality/report-id',recipient:'will@example.org',payload:{report_day:'2026-10-08',job_count:2,completed:1,failed:0,pending:1,results:[{kind:'audit',summary:'A source-grounding issue.',findings:[{item_id:'item-123',severity:'warning',claim:'Wrong units.',recommendation:'Keep points.',evidence:[{url:'https://example.org/article',quote:'nine points'}]}],proposals:[],uncertainties:['Cost unavailable.'],usage:{}}]}};
function setup(overrides: Record<string,string|undefined>={}) {
  const db={rpc:vi.fn(async(name:string)=>({data:name==='claim_hosted_quality_email'?outbox:name==='finish_hosted_quality_email'?true:{enqueued:1},error:null}))};
  const fetcher=vi.fn(async(url:string)=>new Response(JSON.stringify(url.includes('resend')?{id:'provider-id'}:{ok:true}),{status:200}));
  const handle=createDispatchHandler({db,env:k=>({...values,...overrides})[k],fetcher:fetcher as typeof fetch});
  return {db,fetcher,handle};
}
describe('hosted quality dispatch',()=>{
  it('checks cron auth before database or network and defaults disabled',async()=>{
    const {handle,db,fetcher}=setup({QUALITY_ENABLED:undefined});
    expect((await handle(new Request('https://backend.example',{method:'POST'}))).status).toBe(401);
    expect(db.rpc).not.toHaveBeenCalled();
    expect(await (await handle(request())).json()).toEqual({status:'disabled'});
    expect(db.rpc).toHaveBeenCalledExactlyOnceWith('prune_hosted_quality_data',{});expect(fetcher).not.toHaveBeenCalled();
  });
  it('requires an explicit UUID scope and public HTTPS configured worker',async()=>{
    for(const overrides of [{QUALITY_SCOPE_USER_IDS:''},{QUALITY_SCOPE_USER_IDS:'not-a-uuid'},{QUALITY_WORKER_URL:'http://worker.example.org'},{QUALITY_WORKER_URL:'https://127.0.0.1'}]) {
      const {handle,db}=setup(overrides); expect((await handle(request())).status).toBe(503); expect(db.rpc).toHaveBeenCalledExactlyOnceWith('prune_hosted_quality_data',{});
    }
  });
  it('enqueues durably, sends the immutable outbox with a stable provider key, then wakes the worker',async()=>{
    const {handle,db,fetcher}=setup(); expect((await handle(request())).status).toBe(200);
    expect(db.rpc).toHaveBeenCalledWith('enqueue_hosted_quality_jobs',{scope_user_ids:[values.QUALITY_SCOPE_USER_IDS],include_research:false});
    expect(fetcher).toHaveBeenCalledWith('https://api.resend.com/emails',expect.objectContaining({redirect:'error',headers:expect.objectContaining({'Idempotency-Key':outbox.idempotency_key})}));
    const email=JSON.parse(fetcher.mock.calls.find(c=>c[0].includes('resend'))![1]!.body as string);
    expect(email.text).toContain('item-123');expect(email.text).toContain('https://example.org/article');expect(email.text).toContain('nine points');
    expect(db.rpc).toHaveBeenCalledWith('prune_hosted_quality_data',{});
    expect(db.rpc).toHaveBeenCalledWith('finish_hosted_quality_email',expect.objectContaining({accepted:true,provider_message_id:'provider-id'}));
    expect(fetcher).toHaveBeenCalledWith('https://worker.example.org/run',expect.objectContaining({redirect:'error',headers:expect.objectContaining({Authorization:`Bearer ${values.QUALITY_WAKE_TOKEN}`})}));
  });
  it('leaves delivery retry durable after a transport error and does not regenerate the report in the sender',async()=>{
    const {handle,db,fetcher}=setup();fetcher.mockImplementation(async(url:string)=>{if(url.includes('resend'))throw new Error('timeout');return new Response('{}');});
    expect((await handle(request())).status).toBe(200);
    expect(db.rpc).toHaveBeenCalledWith('finish_hosted_quality_email',expect.objectContaining({accepted:false,failure_reason:'transport_uncertain'}));
    expect(db.rpc.mock.calls.filter(c=>c[0]==='prepare_hosted_quality_report')).toHaveLength(1);
  });
  it('reports wake failure while retaining the queued job',async()=>{
    const {handle,db,fetcher}=setup({QUALITY_REPORT_RECIPIENT:undefined});fetcher.mockResolvedValue(new Response('{}',{status:502}));
    const res=await handle(request());expect(res.status).toBe(503);expect((await res.json()).error).toBe('worker_wake_failed');
    expect(db.rpc).toHaveBeenCalledWith('enqueue_hosted_quality_jobs',expect.anything());
  });
  it('only requests research after its separate capability switch is enabled',async()=>{
    const {handle,db}=setup({QUALITY_RESEARCH_ENABLED:'true'}); await handle(request());
    expect(db.rpc).toHaveBeenCalledWith('enqueue_hosted_quality_jobs',{scope_user_ids:[values.QUALITY_SCOPE_USER_IDS],include_research:true});
  });
  it('includes live strategy outcomes and candidate URLs without claiming pixel verification',async()=>{
    const {handle,db,fetcher}=setup();
    const message=structuredClone(outbox) as any;
    message.payload.results[0].retrieval={item_id:'item-123',url:'https://example.org/article',outcome:'retrieved',captured_at:'2026-10-09T12:00:00Z',source_truncated:true,attempts:[{strategy:'firecrawl_rendered',outcome:'retrieved',reason:'rendered_source',duration_ms:654}],image_candidates:[{url:'https://example.org/product.jpg',associated:true}],limitations:['image_pixels_not_verified']};
    db.rpc.mockImplementation(async(name:string)=>({data:name==='claim_hosted_quality_email'?message:name==='finish_hosted_quality_email'?true:{enqueued:1},error:null}));
    await handle(request());
    const email=JSON.parse(fetcher.mock.calls.find(c=>c[0].includes('resend'))![1]!.body as string);
    expect(email.text).toContain('Live retrieval: retrieved');
    expect(email.text).toContain('firecrawl_rendered: retrieved (rendered_source; 654 ms)');
    expect(email.text).toContain('https://example.org/product.jpg');
    expect(email.text).toContain('image pixels are unverified');
    expect(email.text).toContain('source excerpt was truncated');
  });
});
