import { setTimeout as delay } from 'node:timers/promises';
import { validateJob, jobBudget, HARD_RUN_MS } from './protocol.mjs';
import { runHermes } from './runner.mjs';

export class ApiError extends Error {
  constructor(code, status, retryable = false) { super(code); this.status = status; this.retryable = retryable; }
}
export async function apiCall(config, body, signal) {
  const timeout = AbortSignal.timeout(body.action === 'claim' ? 5000 : 2500);
  let response;
  try {
    response = await fetch(config.apiUrl, { method: 'POST', redirect: 'error',
      headers: { Authorization: `Bearer ${config.workerToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body), signal: signal ? AbortSignal.any([signal, timeout]) : timeout });
  } catch { throw new ApiError('backend_unavailable', undefined, true); }
  if (!response.ok) { await response.body?.cancel(); throw new ApiError(response.status === 409 ? 'lease_lost' : 'backend_rejected', response.status, response.status >= 500); }
  const reader = response.body?.getReader(); const chunks = []; let length = 0;
  if (!reader) throw new ApiError('invalid_backend_response');
  try {
    while (true) { const { done, value } = await reader.read(); if (done) break; length += value.length;
      if (length > 300_000) { await reader.cancel(); throw new ApiError('invalid_backend_response'); } chunks.push(value); }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch { throw new ApiError('invalid_backend_response', undefined, true); }
  finally { reader.releaseLock(); }
}

const safeReasons = new Set(['run_timeout', 'hermes_failed', 'spawn_failed', 'invalid_stream', 'invalid_terminal_result', 'invalid_result_json', 'output_limit',
  'invalid_fields', 'invalid_schema_version', 'invalid_text', 'invalid_list', 'item_out_of_scope', 'item_required', 'invalid_category', 'invalid_severity',
  'evidence_required', 'invalid_evidence_url', 'evidence_out_of_scope', 'quote_not_in_source', 'invalid_proposal_evidence', 'shutdown', 'client_disconnected']);

export function createSupervisor(config, { call = (body, signal) => apiCall(config, body, signal), run = runHermes, heartbeatMs = 20_000, retryDelayMs = 200 } = {}) {
  let busy = false; let controller;
  return {
    get busy() { return busy; },
    cancel(reason = 'shutdown') { controller?.abort(new Error(reason)); },
    async runOnce() {
      if (busy) return { status: 'busy' };
      if (!config.ready) return { status: 'unconfigured' };
      busy = true; controller = new AbortController();
      let job; let leaseValid = true; let heartbeatTimer; let heartbeatPending; let stopHeartbeat = false; let completionStarted = false;
      // Includes claim overhead; the claimed job itself has a stricter90s deadline.
      const totalTimer = setTimeout(() => controller.abort(new Error('run_timeout')), HARD_RUN_MS + 5000);
      let jobTimer;
      const lease = () => ({ job_id: job.id, lease_token: job.lease_token, fence: job.fence });
      const heartbeat = async () => {
        if (stopHeartbeat || controller.signal.aborted) return;
        try {
          const response = await call({ action: 'heartbeat', ...lease() }, controller.signal);
          if (!response?.ok || !Number.isFinite(Date.parse(response.lease_expires_at)) || Date.parse(response.lease_expires_at) <= Date.now()) throw new ApiError('lease_lost', 409);
        } catch {
          leaseValid = false;
          controller.abort(new Error('lease_lost'));
        }
        if (!stopHeartbeat && !controller.signal.aborted) heartbeatTimer = setTimeout(() => { heartbeatPending = heartbeat(); }, heartbeatMs);
      };
      try {
        const claimed = await call({ action: 'claim' }, controller.signal);
        if (controller.signal.aborted) throw controller.signal.reason;
        if (claimed?.job === null) return { status: 'idle' };
        job = validateJob(claimed?.job);
        const budget = jobBudget(job);
        jobTimer = setTimeout(() => controller.abort(new Error('run_timeout')), Math.min(HARD_RUN_MS, Date.parse(job.deadline_at) - Date.now()));
        heartbeatTimer = setTimeout(() => { heartbeatPending = heartbeat(); }, heartbeatMs);
        const output = await run(config, job, { ...budget, signal: controller.signal });
        if (controller.signal.aborted) throw controller.signal.reason;
        // Resolve an in-flight heartbeat before submitting, and avoid racing a
        // successful completion with a heartbeat that now observes completed state.
        stopHeartbeat = true; clearTimeout(heartbeatTimer); await heartbeatPending;
        if (!leaseValid || controller.signal.aborted) throw controller.signal.reason || new Error('lease_lost');
        const completion = { action: 'complete', ...lease(), result: output.result, usage: { ...output.usage, model: config.model } };
        completionStarted = true;
        for (let attempt = 0; attempt < 2; attempt++) {
          try {
            const response = await call(completion, controller.signal);
            if (!response?.ok || response.status !== 'completed') throw new ApiError('invalid_backend_response');
            return { status: 'completed', job_id: job.id };
          } catch (error) {
            if (error.status === 409) { leaseValid = false; return { status: 'lease_lost', job_id: job.id }; }
            if (!error.retryable || attempt === 1 || controller.signal.aborted) return { status: 'completion_unconfirmed', job_id: job.id };
            await delay(retryDelayMs, undefined, { signal: controller.signal });
          }
        }
      } catch (error) {
        if (job && !leaseValid) return { status: 'lease_lost', job_id: job.id };
        if (completionStarted) return { status: 'completion_unconfirmed', job_id: job?.id };
        if (job) {
          const reason = safeReasons.has(error?.message) ? error.message : 'runner_failed';
          // A fresh bounded API call can record cancellation; the lease fence is
          // authoritative. Do not send raw exception/model text to the backend.
          try { await call({ action: 'fail', ...lease(), reason }); } catch { /* lease expiry recovers the job */ }
        }
        return { status: 'failed', ...(job ? { job_id: job.id } : {}) };
      } finally {
        stopHeartbeat = true; clearTimeout(heartbeatTimer); clearTimeout(totalTimer); clearTimeout(jobTimer);
        await heartbeatPending; busy = false; controller = undefined;
      }
    },
  };
}
