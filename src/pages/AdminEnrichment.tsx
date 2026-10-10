import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import HeaderSection from '@/components/HeaderSection';
import { useAuth } from '@/hooks/useAuth';
import { useIsAdmin } from '@/hooks/useIsAdmin';
import {
  attentionRate, fetchEnrichmentDashboard, proposalLabels, reviewEnrichmentProposal,
  type EnrichmentDashboard, type IncompleteItem, type ProposalStatus, type QualityProposal,
} from '@/utils/adminEnrichmentApi';

const control = 'min-h-11 border border-ink bg-white px-3 text-label focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50';
const button = `${control} hover:bg-ink hover:text-white disabled:hover:bg-white disabled:hover:text-ink`;
const label = 'font-pixel text-pixel text-ink-muted';
const words = (value: string) => value.replace(/_/g, ' ');
const time = (value: string | null) => value ? new Date(value).toLocaleString('en-US', {
  timeZone: 'America/New_York', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
}) : 'Not recorded';
function Source({ url, children }: { url: string | null; children: ReactNode }) {
  let safe = false;
  try { const u = new URL(url ?? ''); safe = u.protocol === 'https:' && !u.username && !u.password; } catch { /* No link for a withheld URL. */ }
  return safe ? <a className="inline-flex min-h-11 items-center underline underline-offset-4 [overflow-wrap:anywhere]" href={url!} target="_blank" rel="noopener noreferrer">{children}</a> : <span>{children}</span>;
}
function Section({ title, note, children }: { title: string; note?: string; children: ReactNode }) {
  return <section className="mt-10 border-t border-ink pt-5">
    <h2 className="text-section-title font-medium">{title}</h2>
    {note && <p className="mt-2 max-w-3xl text-label leading-relaxed text-ink-muted">{note}</p>}
    <div className="mt-5">{children}</div>
  </section>;
}
function DataTable({ headers, children, label: tableLabel }: { headers: string[]; children: ReactNode; label: string }) {
  return <div className="overflow-x-auto border-y border-line" tabIndex={0} role="region" aria-label={tableLabel}>
    <table className="w-full min-w-[520px] text-left text-label tabular-nums [&_td:first-child]:min-w-[140px]">
      <thead><tr className="bg-fill">{headers.map(h => <th key={h} scope="col" className="whitespace-nowrap px-3 py-3 font-pixel text-pixel font-normal">{h}</th>)}</tr></thead>
      <tbody className="divide-y divide-line-soft [&_td]:px-3 [&_td]:py-3">{children}</tbody>
    </table>
  </div>;
}

function ItemDiagnostic({ item }: { item: IncompleteItem }) {
  return <details className="border-b border-line py-3">
    <summary className="min-h-11 cursor-pointer py-2 [overflow-wrap:anywhere]">
      <span className="mr-3 font-pixel text-pixel">{words(item.status)}</span>
      <span className="font-medium">{item.title || 'Untitled save'}</span>
      <span className="ml-3 text-label text-ink-muted">{item.source || item.type}</span>
    </summary>
    <div className="pb-3 pl-4 text-label leading-relaxed">
      <p className="text-ink-muted">Saved {time(item.created_at)} · Assessed {time(item.evaluated_at)} (New York)</p>
      <p className="mt-2">{item.reasons.length ? item.reasons.map(words).join(' · ') : 'No assessment reason recorded.'}</p>
      <div className="flex flex-wrap gap-x-5">
        {item.url && <Source url={item.url}>Open source</Source>}
        <Link className="inline-flex min-h-11 items-center underline underline-offset-4" to={`/admin/users/${item.user_id}`}>View member library</Link>
      </div>
      <p className="mb-2 font-code text-[11px] text-ink-muted [overflow-wrap:anywhere]">Item {item.item_id}</p>
      {item.attempts.length ? <ul className="space-y-2 border-l border-line pl-3">
        {item.attempts.map((a, i) => <li key={i} className="[overflow-wrap:anywhere]">
          <span className="font-medium">{words(a.strategy)}</span> · {words(a.outcome)} · {a.elapsed_ms === null ? 'Duration unknown' : `${a.elapsed_ms.toLocaleString()} ms`}
          <p className="text-ink-muted">{a.reasons.map(words).join(' · ') || 'No reason recorded'} · {time(a.created_at)}</p>
        </li>)}
      </ul> : <p>No strategy attempts recorded.</p>}
    </div>
  </details>;
}

function Proposal({ proposal, reload }: { proposal: QualityProposal; reload: () => Promise<void> }) {
  const [status, setStatus] = useState(proposal.status);
  const [note, setNote] = useState('');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [refreshedDraft, setRefreshedDraft] = useState(false);
  const attempt = useRef<{ signature: string; id: string } | null>(null);
  const seenRevision = useRef(proposal.revision);
  const conflict = error === 'version_conflict';
  useEffect(() => {
    if (seenRevision.current === proposal.revision) return;
    seenRevision.current = proposal.revision;
    // Keep the decision being written while loading another reviewer's change.
    // The next explicit submit uses the newly displayed revision and a new key.
    if (!note.trim()) setStatus(proposal.status);
    setRefreshedDraft(!!note.trim()); setError(null);
  }, [proposal.revision, proposal.status, note]);
  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!note.trim() || pending || conflict) return;
    const review = { proposal_id: proposal.id, expected_revision: proposal.revision, new_status: status, review_note: note.trim() };
    const signature = JSON.stringify(review);
    // A transport retry keeps its idempotency key; an edited decision gets a new one.
    if (attempt.current?.signature !== signature) attempt.current = { signature, id: crypto.randomUUID() };
    setPending(true); setError(null); setSaved(false); setRefreshedDraft(false);
    try {
      await reviewEnrichmentProposal({ ...review, request_id: attempt.current.id });
      setSaved(true); setNote(''); await reload();
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not save review.'); }
    finally { setPending(false); }
  };
  return <article className="border-b border-line py-5 [overflow-wrap:anywhere]">
    <div className="flex flex-wrap items-center gap-3">
      <span className="bg-ink px-2 py-1 font-pixel text-pixel text-white">{proposalLabels[proposal.status]}</span>
      <span className={label}>{proposal.kind} · {time(proposal.created_at)}</span>
    </div>
    <h3 className="mt-3 text-object-title font-medium">{proposal.title}</h3>
    <p className="mt-2 max-w-4xl whitespace-pre-wrap text-body text-ink-muted">{proposal.rationale}</p>
    <div className="mt-2 flex flex-col items-start text-label">
      {proposal.evidence_urls.map(url => <Source key={url} url={url}>{url}</Source>)}
    </div>
    <details className="mt-2">
      <summary className="min-h-11 cursor-pointer py-3 text-label underline underline-offset-4">Review proposal</summary>
      <div className="mt-2 max-w-2xl border-l border-ink pl-4">
        <p className="text-label leading-relaxed text-ink-muted">A review records a decision. It does not edit saved items or deploy a playbook.</p>
        <form onSubmit={submit} className="mt-4 space-y-4">
          <label className="block"><span className={`${label} block pb-2`}>Decision</span>
            <select className={`${control} w-full`} value={status} onChange={e => setStatus(e.target.value as ProposalStatus)} disabled={pending}>
              {Object.entries(proposalLabels).map(([key, text]) => <option key={key} value={key}>{text}</option>)}
            </select>
          </label>
          <label className="block"><span className={`${label} block pb-2`}>Review note</span>
            <textarea className={`${control} min-h-28 w-full py-3 leading-relaxed`} value={note} maxLength={2000} required disabled={pending}
              placeholder="Record the evidence needed, next step, or reason for dismissal." onChange={e => setNote(e.target.value)} />
          </label>
          {error && <div role="alert" className="text-label leading-relaxed">
            <p>{conflict ? 'Another reviewer changed this proposal. Refresh it before saving your decision.' : error}</p>
            {conflict && <button type="button" className={`${button} mt-3`} onClick={() => void reload()}>Refresh proposal</button>}
          </div>}
          {saved && <p role="status" className="text-label">Review saved.</p>}
          {refreshedDraft && <p role="status" className="text-label">Latest review loaded. Your draft is preserved; check the recent reviews before saving.</p>}
          <button type="submit" className={button} disabled={!note.trim() || pending || conflict}>{pending ? 'Saving…' : 'Save review'}</button>
        </form>
        <h4 className={`${label} mt-6 mb-2`}>Recent reviews</h4>
        {proposal.reviews.length ? <ol className="space-y-3 text-label leading-relaxed">
          {proposal.reviews.map(review => <li key={review.id}>
            <p className="font-medium">{proposalLabels[review.to_status]} · {time(review.created_at)}</p>
            <p className="whitespace-pre-wrap">{review.note}</p>
            <p className="mt-1 font-code text-[11px] text-ink-muted">Reviewer {review.actor_id}</p>
          </li>)}
        </ol> : <p className="text-label text-ink-muted">No human review recorded.</p>}
        <p className="mt-4 font-code text-[11px] text-ink-muted">Proposal {proposal.id} · Revision {proposal.revision}</p>
      </div>
    </details>
  </article>;
}

export default function AdminEnrichment() {
  const { user, loading: authLoading } = useAuth();
  const { isAdmin, loading: adminLoading } = useIsAdmin();
  const navigate = useNavigate();
  const [hours, setHours] = useState<24 | 168>(24);
  const [status, setStatus] = useState<ProposalStatus | ''>('');
  const [loaded, setLoaded] = useState<{ userId: string; data: EnrichmentDashboard } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const generation = useRef(0);
  const userId = user?.id;
  const allowed = !authLoading && !!userId && !adminLoading && isAdmin;
  const data = loaded?.userId === userId ? loaded.data : null;
  useEffect(() => {
    if (!authLoading && !user) navigate('/auth');
    else if (!authLoading && !adminLoading && !isAdmin) navigate('/home');
  }, [authLoading, user, adminLoading, isAdmin, navigate]);
  const reload = useCallback(async () => {
    if (!allowed || !userId) return;
    const request = ++generation.current;
    setLoading(true); setError(null);
    try {
      const next = await fetchEnrichmentDashboard(hours, status || undefined);
      if (request === generation.current) setLoaded({ userId, data: next });
    } catch (e) {
      if (request === generation.current) setError(e instanceof Error ? e.message : 'Could not load enrichment.');
    } finally { if (request === generation.current) setLoading(false); }
  }, [allowed, userId, hours, status]);
  useEffect(() => { void reload(); return () => { generation.current++; }; }, [reload]);
  if (!allowed) return null;
  return <div className="min-h-screen bg-paper text-ink">
    <HeaderSection user={user} />
    <main className="mx-auto max-w-6xl px-4 py-8 sm:px-8">
      <nav className="mb-6 flex gap-5 text-label" aria-label="Admin navigation">
        <Link className="inline-flex min-h-11 items-center underline underline-offset-4" to="/admin">Members</Link>
        <span aria-current="page" className="inline-flex min-h-11 items-center font-medium">Enrichment</span>
      </nav>
      <div className="flex flex-wrap items-end justify-between gap-5">
        <div><p className={`${label} mb-2`}>Stash operations / beta</p>
          <h1 className="text-[clamp(32px,5vw,48px)] font-medium leading-none tracking-[-0.04em]">Enrichment review</h1>
          <p className="mt-3 max-w-2xl text-body text-ink-muted">See what is incomplete, trace what was tried, and review the agent’s proposed improvements.</p>
        </div>
        <div className="flex flex-wrap items-end gap-2">
          <label><span className={`${label} mb-2 block`}>Save window</span>
            <select className={control} value={hours} onChange={e => setHours(Number(e.target.value) as 24 | 168)}>
              <option value={24}>Last 24 hours</option><option value={168}>Last 7 days</option>
            </select>
          </label>
          <button className={button} type="button" onClick={() => void reload()} disabled={loading}>Refresh</button>
        </div>
      </div>
      {loading && <p role="status" className={`${label} mt-5`}>Loading current records…</p>}
      {error && <div role="alert" className="mt-6 border border-ink bg-white p-5"><p className="font-medium">Couldn’t load enrichment</p><p className="mt-1 text-body">{error}</p></div>}
      {data && !error && <div aria-busy={loading}>
        <p className={`${label} mt-6`}>{time(data.window_start)} – {time(data.window_end)} · America/New_York · all users</p>
        <section className="mt-4 grid gap-0 border-y border-ink sm:grid-cols-[1fr_2fr]" aria-label="Pipeline health">
          <div className="bg-ink px-5 py-6 text-white">
            <p className="font-pixel text-pixel text-spot-on-ink">assessed saves needing attention</p>
            <p data-testid="attention-rate" className="mt-3 text-[40px] font-medium leading-none tracking-[-0.03em]">{attentionRate(data.pipeline)}</p>
            <p className="mt-3 text-label">{data.pipeline.partial + data.pipeline.blocked} of {data.pipeline.assessed} assessed saves</p>
          </div>
          <div className="px-5 py-6">
            <p className="text-object-title">{data.pipeline.saved_items} saves · {data.pipeline.unassessed} unassessed</p>
            <p className="mt-2 text-body text-ink-muted">{data.pipeline.ready} ready · {data.pipeline.partial} partial · {data.pipeline.blocked} blocked · {data.pipeline.unsupported} unsupported</p>
            <p className="mt-4 max-w-xl text-label leading-relaxed text-ink-muted">Current recorded completeness, not a factual-accuracy rate. Unassessed saves are unknown. Agent findings need review before they become fixes.</p>
          </div>
        </section>
        <Section title="Save cohorts" note="Current states grouped by the day each item was saved in New York. Edge days cover only the selected window; these are not historical snapshots.">
          <p className="mb-3 text-label text-ink-muted sm:hidden">Swipe across tables to see all columns.</p>
          <DataTable label="Save cohort counts" headers={['Saved on', 'Saves', 'Assessed', 'Partial', 'Blocked', 'Unassessed', 'Needs attention']}>
            {data.daily.map(day => <tr key={day.day}><td className="whitespace-nowrap">{day.day}</td><td>{day.saved_items}</td><td>{day.assessed}</td><td>{day.partial}</td><td>{day.blocked}</td><td>{day.unassessed}</td><td className="whitespace-nowrap">{attentionRate(day)}</td></tr>)}
          </DataTable>
        </Section>
        <Section title="Where enrichment is incomplete" note="Source and object-type counts cover saves in the selected window. Unknown means no assessment was recorded.">
          <div className="grid min-w-0 gap-6 lg:grid-cols-2">
            <DataTable label="Source completeness" headers={['Source', 'Saves', 'Partial', 'Blocked', 'Unknown']}>
              {data.pipeline.by_source.map(row => <tr key={row.source}><td className="break-all">{row.source}</td><td>{row.saved}</td><td>{row.partial}</td><td>{row.blocked}</td><td>{row.unassessed}</td></tr>)}
              {!data.pipeline.by_source.length && <tr><td colSpan={5}>No incomplete link sources recorded.</td></tr>}
            </DataTable>
            <DataTable label="Object type completeness" headers={['Object type', 'Saves', 'Partial', 'Blocked', 'Unknown']}>
              {data.pipeline.by_type.map(row => <tr key={row.type}><td>{words(row.type)}</td><td>{row.saved}</td><td>{row.partial}</td><td>{row.blocked}</td><td>{row.unassessed}</td></tr>)}
              {!data.pipeline.by_type.length && <tr><td colSpan={5}>No saves in this window.</td></tr>}
            </DataTable>
          </div>
        </Section>
        <Section title="Strategies attempted" note="Attempts made during this window, including retries of older saves. One save can have multiple attempts. Missing cost data stays unknown.">
          <DataTable label="Enrichment strategy attempts" headers={['Strategy', 'Attempts', 'Improved', 'Failed', 'Average time', 'Recorded cost (USD)']}>
            {data.pipeline.strategies.map(row => <tr key={row.strategy}><td>{words(row.strategy)}</td><td>{row.attempts}</td><td>{row.improved}</td><td>{row.failed}</td>
              <td className="whitespace-nowrap">{row.avg_ms === null ? 'Unknown' : `${row.avg_ms.toLocaleString()} ms`}</td>
              <td>{row.cost_known ? `$${Number(row.cost_usd).toFixed(4)} (${row.cost_known}/${row.attempts})` : 'Unknown'}</td>
            </tr>)}
            {!data.pipeline.strategies.length && <tr><td colSpan={6}>No attempts recorded in this window.</td></tr>}
          </DataTable>
        </Section>
        <Section title="Incomplete saves" note="Up to 30 recent partial, blocked, or unassessed saves from the selected window. Expand an item for its five latest recorded attempts.">
          {data.incomplete_items.map(item => <ItemDiagnostic key={item.item_id} item={item} />)}
          {!data.incomplete_items.length && <p className="text-body text-ink-muted">No incomplete saves in this window.</p>}
        </Section>
        <Section title="Hosted reviewer" note="One rotating account sample per hourly audit, plus one daily live investigation. This is a bounded sample of links.">
          <p className="text-body">{data.jobs.completed} completed · {data.jobs.failed} failed · {data.jobs.pending} pending · {data.jobs.total} jobs in this window</p>
          <p className="mt-2 text-label text-ink-muted">Last completion in window: {time(data.jobs.last_completed_at)} (New York).</p>
          {data.jobs.error_counts.length > 0 && <ul className="mt-3 space-y-1 text-label">{data.jobs.error_counts.map(row => <li key={row.reason}>{words(row.reason)}: {row.count} failed jobs</li>)}</ul>}
          <div className="mt-5 border-l border-ink pl-4 text-label leading-relaxed">
            <p>Daily email: after 09:00 America/New_York, checked every five minutes.</p>
            {data.delivery ? <p className="mt-1">Report for {data.delivery.report_day}: {data.delivery.status === 'accepted' ? `Accepted by email provider ${time(data.delivery.accepted_at)}. Inbox delivery is not confirmed here.` : words(data.delivery.status)}{data.delivery.last_error ? ` · ${words(data.delivery.last_error)}` : ''}</p> : <p className="mt-1">No report delivery recorded yet.</p>}
          </div>
        </Section>
        <Section title="Improvement proposals" note="Proposals are model suggestions, not verified defects. Review the evidence and record a next step. Records follow the 35-day audit retention and are removed when a source is deleted. No strategy is automatically published.">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="text-label text-ink-muted">{data.proposal_counts.new} new · {data.proposal_counts.needs_evidence} need evidence · {data.proposal_counts.planned} planned · {data.proposal_counts.dismissed} dismissed</p>
            <label><span className="sr-only">Proposal status</span><select className={control} value={status} onChange={e => setStatus(e.target.value as ProposalStatus | '')}>
              <option value="">All statuses</option>{Object.entries(proposalLabels).map(([key, text]) => <option key={key} value={key}>{text}</option>)}
            </select></label>
          </div>
          <p className={`${label} mt-3`}>Showing up to 50 retained proposals across all dates</p>
          {data.proposals.map(proposal => <Proposal key={proposal.id} proposal={proposal} reload={reload} />)}
          {!data.proposals.length && <p className="py-6 text-body text-ink-muted">No proposals match this status.</p>}
        </Section>
      </div>}
    </main>
  </div>;
}
