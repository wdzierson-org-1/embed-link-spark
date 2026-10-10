// Render the immutable report snapshot; never fetch new facts while sending it.
export function reportText(p: any): string {
  const lines = [`Stash enrichment report — ${p.report_day} (America/New_York)`,
    `Jobs: ${p.job_count}; completed: ${p.completed}; failed: ${p.failed}; pending: ${p.pending}.`];
  const m = p.pipeline;
  if (m) {
    const attention = m.partial + m.blocked;
    lines.push('', 'PIPELINE HEALTH — ALL USERS',
      `${m.saved_items} saves in the report window: ${m.assessed} assessed; ${m.unassessed} unassessed.`,
      `${attention} of ${m.assessed} assessed saves need attention (${m.assessed ? (100 * attention / m.assessed).toFixed(1) + '%' : 'no assessed saves'}).`,
      `Ready: ${m.ready}; partial: ${m.partial}; blocked: ${m.blocked}; unsupported: ${m.unsupported}.`,
      'These are current recorded enrichment states for saves made that day, not a measured factual-accuracy rate. Unassessed saves are not counted as successes.',
      'By object type:');
    for (const row of m.by_type || []) lines.push(`  ${row.type}: ${row.saved} saves; ${row.partial} partial; ${row.blocked} blocked; ${row.unassessed} unassessed.`);
    lines.push('Sources with incomplete enrichment (up to 10):');
    for (const row of m.by_source || []) lines.push(`  ${row.source}: ${row.saved} saves; ${row.partial} partial; ${row.blocked} blocked; ${row.unassessed} unassessed.`);
    lines.push('Recorded strategy attempts during the day (includes retries of older saves):');
    for (const row of m.strategies || []) lines.push(`  ${row.strategy}: ${row.attempts} attempts; ${row.failed} failed; ${row.improved} improved; average ${row.avg_ms} ms; recorded cost USD ${row.cost_usd ?? 'unknown'} (${row.cost_known}/${row.attempts} attempts have cost data).`);
  }
  const results = p.results || [];
  const items = new Set(results.flatMap((r: any) => r.item_ids || []));
  lines.push('', `HERMES REVIEW — ${items.size} distinct sampled items`,
    'This is a bounded sample, not a population accuracy rate. Model findings are proposals; no saved items or playbooks were changed.');
  const findings = new Map<string, { finding: any; count: number }>();
  const proposals = new Map<string, any>();
  const uncertainties = new Set<string>();
  const summaries = new Set<string>();
  const privateCategories = new Map<string, number>();
  let privateProposals = 0;
  let input = 0, output = 0, knownUsage = 0;
  for (const r of results) {
    if (r.redacted) {
      privateProposals += r.proposal_count || 0;
      for (const f of r.finding_counts || []) {
        const key = `${f.category} / ${f.severity}`;
        privateCategories.set(key, (privateCategories.get(key) || 0) + f.count);
      }
    }
    if (r.summary) summaries.add(`[${r.kind}] ${r.summary}`);
    for (const f of r.findings || []) {
      const key = JSON.stringify([f.item_id, f.category, f.severity, f.claim?.replace(/\s+/g, ' ').trim(), f.recommendation, f.evidence]);
      const entry = findings.get(key);
      if (entry) entry.count++;
      else findings.set(key, { finding: f, count: 1 });
    }
    for (const proposal of r.proposals || []) proposals.set(JSON.stringify(proposal), proposal);
    for (const uncertainty of r.uncertainties || []) uncertainties.add(uncertainty);
    if (typeof r.usage?.input_tokens === 'number' && typeof r.usage?.output_tokens === 'number') {
      input += r.usage.input_tokens; output += r.usage.output_tokens; knownUsage++;
    }
  }
  lines.push(`${findings.size} distinct detailed findings; ${proposals.size} detailed improvement proposals.`,
    `Recorded model tokens: ${input} input / ${output} output across ${knownUsage}/${results.length} results; model cost is unknown.`, '');
  if (privateCategories.size || privateProposals) {
    lines.push('Other-account reviews (counts can include repeat observations; private details omitted):');
    for (const [category, count] of privateCategories) lines.push(`  ${category}: ${count} observations`);
    lines.push(`  ${privateProposals} additional proposal observations; details retained in Stash infrastructure.`);
  }
  for (const summary of summaries) lines.push(summary);
  for (const { finding: f, count } of findings.values()) {
    lines.push(`- ${f.severity}: ${f.claim}${count > 1 ? ` (observed in ${count} reviews)` : ''}`,
      `  Item: ${f.item_id || 'operational finding'}`, `  Recommendation: ${f.recommendation}`);
    for (const e of f.evidence || []) lines.push(`  Source${e.source === 'live' ? ' (live)' : ''}: ${e.url}${e.quote ? `\n  Quote: ${e.quote}` : ''}`);
  }
  lines.push('', 'INVESTIGATIONS AND STRATEGIES TRIED');
  for (const r of results) {
    const o = r.retrieval;
    if (!o) continue;
    lines.push(`Live retrieval: ${o.outcome}; item ${o.item_id}; captured ${o.captured_at}.`, `  Source: ${o.url}`);
    for (const a of o.attempts || []) lines.push(`  ${a.strategy}: ${a.outcome} (${a.reason}; ${a.duration_ms} ms)`);
    if (o.source_truncated) lines.push('  The source excerpt was truncated.');
    for (const candidate of o.image_candidates || []) lines.push(`  Image candidate: ${candidate.url} (${candidate.associated ? 'page association found' : 'association not established'}; image pixels are unverified)`);
    for (const check of o.image_checks || []) lines.push(`  Image asset check: ${check.outcome} (${check.reason}; ${check.duration_ms} ms)${check.width && check.height ? `; ${check.width} × ${check.height}; ${check.byte_length} bytes` : ''}. File structure only; visual match and full decoding are unverified.`);
    for (const limitation of o.limitations || []) lines.push(`  Retrieval limit: ${limitation}`);
  }
  lines.push('', 'PROPOSED PLAYBOOK IMPROVEMENTS');
  for (const proposal of proposals.values()) lines.push(`Proposal: ${proposal.title}`, proposal.rationale, (proposal.evidence_urls || []).join('\n'));
  if (!proposals.size && !privateProposals) lines.push('No evidence-backed playbook proposal in this report.');
  for (const uncertainty of uncertainties) lines.push(`Unknown: ${uncertainty}`);
  lines.push('', 'Daily reports are prepared after 09:00 America/New_York; the dispatcher checks every five minutes.');
  const body = lines.join('\n');
  return body.length > 99_800 ? body.slice(0, 99_800) + '\n[Email truncated; full results remain in Stash infrastructure.]' : body;
}
