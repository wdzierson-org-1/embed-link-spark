import { attentionRate, fetchEnrichmentDashboard, reviewEnrichmentProposal } from './adminEnrichmentApi';
const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { functions: { invoke } } }));
beforeEach(() => vi.clearAllMocks());
it('requests a bounded window and optional status, without supplying an actor', async () => {
  invoke.mockResolvedValue({ data: { proposals: [] }, error: null });
  await expect(fetchEnrichmentDashboard(168, 'planned')).resolves.toEqual({ proposals: [] });
  expect(invoke).toHaveBeenCalledWith('admin-stats', { body: {
    action: 'enrichment', lookback_hours: 168, proposal_limit: 50, proposal_status: 'planned',
  } });
});
it('keeps review version and idempotency identity and surfaces a server conflict', async () => {
  invoke.mockResolvedValue({ error: { context: { json: async () => ({ error: 'version_conflict' }) } } });
  const review = { proposal_id: 'p1', expected_revision: 3, new_status: 'planned' as const, review_note: 'Add regression fixture first.', request_id: 'r1' };
  await expect(reviewEnrichmentProposal(review)).rejects.toThrow('version_conflict');
  expect(invoke).toHaveBeenCalledWith('admin-stats', { body: { action: 'review_proposal', ...review } });
});
it('does not count unassessed saves as successes', () => {
  expect(attentionRate({ saved_items: 100, assessed: 4, ready: 1, partial: 2, blocked: 1, unsupported: 0, unassessed: 96 })).toBe('75.0%');
  expect(attentionRate({ saved_items: 100, assessed: 0, ready: 0, partial: 0, blocked: 0, unsupported: 0, unassessed: 100 })).toBe('Not assessed');
});
