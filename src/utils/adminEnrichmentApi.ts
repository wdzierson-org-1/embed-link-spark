import { supabase } from '@/integrations/supabase/client';
import { describeInvokeError } from './adminApi';

export type ProposalStatus = 'new' | 'needs_evidence' | 'planned' | 'dismissed';
export const proposalLabels: Record<ProposalStatus, string> = {
  new: 'New', needs_evidence: 'Needs evidence', planned: 'Planned', dismissed: 'Dismissed',
};
export interface QualityCounts {
  saved_items: number; assessed: number; ready: number; partial: number;
  blocked: number; unsupported: number; unassessed: number;
}
export interface StrategyCount {
  strategy: string; attempts: number; failed: number; improved: number;
  avg_ms: number | null; cost_known: number; cost_usd: number | null;
}
export interface QualityProposal {
  id: string; job_id: string; kind: string; title: string; rationale: string;
  evidence_urls: string[]; source_item_ids: string[]; status: ProposalStatus;
  revision: number; created_at: string; reviewed_at: string | null;
  reviews: { id: string; actor_id: string; from_status: ProposalStatus; to_status: ProposalStatus;
    note: string; revision: number; created_at: string }[];
}
export interface IncompleteItem {
  item_id: string; user_id: string; type: string; title: string | null; source: string | null;
  url: string | null; status: string; reasons: string[]; evaluated_at: string | null; created_at: string;
  attempts: { strategy: string; outcome: string; reasons: string[]; created_at: string; elapsed_ms: number | null }[];
}
export interface EnrichmentDashboard {
  window_start: string; window_end: string; lookback_hours: number;
  pipeline: QualityCounts & {
    by_type: { type: string; saved: number; partial: number; blocked: number; unassessed: number }[];
    by_source: { source: string; saved: number; partial: number; blocked: number; unassessed: number }[];
    strategies: StrategyCount[];
  };
  daily: (QualityCounts & { day: string })[];
  jobs: { total: number; completed: number; failed: number; pending: number;
    last_completed_at: string | null; error_counts: { reason: string; count: number }[] };
  delivery: { status: string; accepted_at: string | null; last_error: string | null; report_day: string } | null;
  proposal_counts: Record<ProposalStatus | 'total', number>;
  proposals: QualityProposal[]; incomplete_items: IncompleteItem[];
}
export interface ProposalReview {
  proposal_id: string; expected_revision: number; new_status: ProposalStatus;
  review_note: string; request_id: string;
}

export async function fetchEnrichmentDashboard(hours: 24 | 168, status?: ProposalStatus): Promise<EnrichmentDashboard> {
  const { data, error } = await supabase.functions.invoke('admin-stats', { body: {
    action: 'enrichment', lookback_hours: hours, proposal_limit: 50, ...(status ? { proposal_status: status } : {}),
  } });
  if (error) throw new Error(await describeInvokeError(error));
  return data as EnrichmentDashboard;
}

export async function reviewEnrichmentProposal(review: ProposalReview): Promise<void> {
  const { error } = await supabase.functions.invoke('admin-stats', { body: { action: 'review_proposal', ...review } });
  if (error) throw new Error(await describeInvokeError(error));
}

/** An unassessed save is unknown, never implicitly successful. */
export function attentionRate(counts: QualityCounts): string {
  return counts.assessed ? `${(100 * (counts.partial + counts.blocked) / counts.assessed).toFixed(1)}%` : 'Not assessed';
}
