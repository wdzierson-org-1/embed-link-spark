import { authorized, publicEvidenceUrl } from '../quality-worker/handler.ts';
type DB = { rpc: (name: string, args: Record<string, unknown>) => Promise<{ data: any; error: any }> };
type Env = (name: string) => string | undefined;
const json = (status:number,body:unknown) => new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function reportText(p:any):string {
  const lines=[`Stash quality report — ${p.report_day}`,`Jobs: ${p.job_count}; completed: ${p.completed}; failed: ${p.failed}; pending: ${p.pending}.`,
    'This is a bounded sample, not a population accuracy rate. Model findings are proposals; no saved items or playbooks were changed.',''];
  for(const r of p.results||[]) {
    lines.push(`[${r.kind}] ${r.summary}`);
    for(const f of r.findings||[]) {
      lines.push(`- ${f.severity}: ${f.claim}\n  Item: ${f.item_id||'operational finding'}\n  Recommendation: ${f.recommendation}`);
      for(const e of f.evidence||[]) lines.push(`  Source: ${e.url}${e.quote?`\n  Quote: ${e.quote}`:''}`);
    }
    for(const proposal of r.proposals||[]) lines.push(`Proposal: ${proposal.title}\n${proposal.rationale}\n${(proposal.evidence_urls||[]).join('\n')}`);
    for(const uncertainty of r.uncertainties||[]) lines.push(`Unknown: ${uncertainty}`);
    lines.push(`Recorded model cost: ${typeof r.usage?.cost_usd==='number'?`USD ${r.usage.cost_usd}`:'unknown'}`,'');
  }
  return lines.join('\n').slice(0,100000);
}
export function createDispatchHandler({db,env,fetcher=fetch}:{db:DB;env:Env;fetcher?:typeof fetch}) {
  return async(req:Request):Promise<Response>=>{
    if(req.method!=='POST')return json(405,{error:'post_only'});
    if(!await authorized(req.headers.get('x-cron-secret'),env('CRON_SECRET')))return json(401,{error:'unauthorized'});
    const call=async(name:string,args:Record<string,unknown>)=>{const r=await db.rpc(name,args);if(r.error)throw new Error('database_error');return r.data;};
    // Disabling paid work must not disable the retention policy for existing snapshots.
    try{await call('prune_hosted_quality_data',{});}catch{return json(503,{error:'quality_retention_failed'});}
    if(env('QUALITY_ENABLED')!=='true')return json(200,{status:'disabled'});
    const scope=[...new Set((env('QUALITY_SCOPE_USER_IDS')||'').split(',').map(s=>s.trim()).filter(Boolean))];
    const workerUrl=env('QUALITY_WORKER_URL')||'';const wakeToken=env('QUALITY_WAKE_TOKEN');
    if(!scope.length||scope.length>20||scope.some(s=>!uuid.test(s))||!publicEvidenceUrl(workerUrl)||!wakeToken||wakeToken.length<32)return json(503,{error:'quality_configuration_missing'});
    const endpoint=new URL(workerUrl);if(endpoint.search||endpoint.hash)return json(503,{error:'invalid_worker_url'});
    endpoint.pathname=`${endpoint.pathname.replace(/\/$/,'')}/run`;
    try{
      const queue=await call('enqueue_hosted_quality_jobs',{scope_user_ids:scope,include_research:env('QUALITY_RESEARCH_ENABLED')==='true'});
      let email='not_configured';const recipient=env('QUALITY_REPORT_RECIPIENT');
      if(recipient){
        await call('prepare_hosted_quality_report',{report_recipient:recipient});
        if(env('RESEND_API_KEY')){
          const message=await call('claim_hosted_quality_email',{});email=message?'pending':'idle';
          if(message){
            let accepted=false;let providerId:string|null=null;let failure:string|null=null;
            try{
              const response=await fetcher('https://api.resend.com/emails',{method:'POST',redirect:'error',headers:{Authorization:`Bearer ${env('RESEND_API_KEY')}`,'Content-Type':'application/json','Idempotency-Key':message.idempotency_key},
                body:JSON.stringify({from:env('QUALITY_REPORT_FROM')||'Stash <reminders@mail.gostash.it>',to:[message.recipient],subject:`Stash quality report — ${message.payload.report_day}`,text:reportText(message.payload)}),signal:AbortSignal.timeout(10000)});
              accepted=response.ok;
              if(accepted){const body=await response.json().catch(()=>({}));providerId=typeof body.id==='string'?body.id:null;}
              else failure=`resend_http_${response.status}`;
            }catch{failure='transport_uncertain';}
            const stamped=await call('finish_hosted_quality_email',{target_id:message.id,token:message.lease_token,accepted,provider_message_id:providerId,failure_reason:failure});
            if(!stamped)throw new Error('email_receipt_not_recorded');
            email=accepted?'accepted':'retry_queued';
          }
        }
      }
      // The container owns execution and heartbeats. Never schedule repair work here.
      let wake:Response;
      try{wake=await fetcher(endpoint.href,{method:'POST',redirect:'error',headers:{Authorization:`Bearer ${wakeToken}`,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(105000)});}
      catch{return json(503,{error:'worker_wake_failed',queue,email});}
      if(!wake.ok&&wake.status!==409)return json(503,{error:'worker_wake_failed',queue,email,http_status:wake.status});
      return json(200,{status:wake.status===409?'worker_busy':'dispatched',queue,email});
    }catch{return json(503,{error:'quality_dispatch_failed'});}
  };
}
