import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import AdminEnrichment from './AdminEnrichment';
import type { EnrichmentDashboard } from '@/utils/adminEnrichmentApi';

const { fetchMock, reviewMock, navigateMock, authState, adminState } = vi.hoisted(() => ({
  fetchMock: vi.fn(), reviewMock: vi.fn(), navigateMock: vi.fn(),
  authState: { user: { id: 'admin' } as { id: string } | null, loading: false },
  adminState: { isAdmin: true, loading: false },
}));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => authState }));
vi.mock('@/hooks/useIsAdmin', () => ({ useIsAdmin: () => adminState }));
vi.mock('@/components/HeaderSection', () => ({ default: () => null }));
vi.mock('react-router-dom', async (original) => ({
  ...(await original<typeof import('react-router-dom')>()), useNavigate: () => navigateMock,
}));
vi.mock('@/utils/adminEnrichmentApi', async (original) => ({
  ...(await original<typeof import('@/utils/adminEnrichmentApi')>()),
  fetchEnrichmentDashboard: fetchMock, reviewEnrichmentProposal: reviewMock,
}));
const counts = { saved_items: 10, assessed: 4, ready: 2, partial: 1, blocked: 1, unsupported: 0, unassessed: 6 };
export const dashboard: EnrichmentDashboard = {
  window_start: '2026-10-09T14:00:00Z', window_end: '2026-10-10T14:00:00Z', lookback_hours: 24,
  pipeline: { ...counts, by_type: [], by_source: [], strategies: [
    { strategy: 'jina_reader', attempts: 4, failed: 1, improved: 2, avg_ms: 350, cost_known: 0, cost_usd: null },
  ] },
  daily: [{ ...counts, day: '2026-10-09' }],
  jobs: { total: 24, completed: 21, failed: 2, pending: 1, last_completed_at: '2026-10-10T13:10:00Z', error_counts: [{ reason: 'quote_not_in_source', count: 2 }] },
  delivery: { status: 'accepted', accepted_at: '2026-10-10T13:00:00Z', last_error: null, report_day: '2026-10-09' },
  proposal_counts: { new: 1, needs_evidence: 0, planned: 0, dismissed: 0, total: 1 },
  proposals: [{ id: 'p1', job_id: 'j1', kind: 'research', title: 'Verify selected product images',
    rationale: 'A campaign photo was unrelated to the saved product.', evidence_urls: ['https://example.org/jacket'],
    source_item_ids: ['i1'], status: 'new', revision: 1, created_at: '2026-10-10T12:00:00Z', reviewed_at: null, reviews: [] }],
  incomplete_items: [{ item_id: 'i1', user_id: 'u1', type: 'link', title: 'Navy jacket', source: 'example.org',
    url: 'https://example.org/jacket', status: 'partial', reasons: ['missing_image'], evaluated_at: null, created_at: '2026-10-10T10:00:00Z',
    attempts: [{ strategy: 'jina_reader', outcome: 'failed', reasons: ['access_wall'], elapsed_ms: 400, created_at: '2026-10-10T10:01:00Z' }] }],
};
const mount = () => render(<MemoryRouter><AdminEnrichment /></MemoryRouter>);
beforeEach(() => {
  vi.clearAllMocks(); authState.user = { id: 'admin' }; adminState.isAdmin = true;
  fetchMock.mockResolvedValue(structuredClone(dashboard)); reviewMock.mockResolvedValue(undefined);
});

it('redirects a non-admin without requesting private diagnostics', async () => {
  adminState.isAdmin = false; mount();
  await waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/home'));
  expect(fetchMock).not.toHaveBeenCalled();
});
it('uses assessed saves as the denominator and exposes recorded attempts', async () => {
  mount();
  expect(await screen.findByTestId('attention-rate')).toHaveTextContent('50.0%');
  expect(screen.getByText(/6 unassessed/)).toBeInTheDocument();
  expect(screen.getByRole('link', { name: 'View member library' })).toHaveAttribute('href', '/admin/users/u1');
  expect(screen.getByText(/access wall/)).toBeInTheDocument();
  expect(screen.getByText(/Accepted by email provider/)).toBeInTheDocument();
  expect(screen.getByText(/not a factual-accuracy rate/i)).toBeInTheDocument();
});
it('labels a zero denominator as unknown', async () => {
  const data = structuredClone(dashboard); Object.assign(data.pipeline, { assessed: 0, partial: 0, blocked: 0 });
  fetchMock.mockResolvedValue(data); mount();
  expect(await screen.findByTestId('attention-rate')).toHaveTextContent('Not assessed');
});
it('requires a review note and sends the displayed revision', async () => {
  mount(); await screen.findByText('Verify selected product images');
  fireEvent.click(screen.getByText('Review proposal'));
  const save = screen.getByRole('button', { name: 'Save review' });
  expect(save).toBeDisabled();
  fireEvent.change(screen.getByLabelText('Decision'), { target: { value: 'needs_evidence' } });
  fireEvent.change(screen.getByLabelText('Review note'), { target: { value: 'Compare the source image with the navy variant before changing the selector.' } });
  fireEvent.click(save);
  await waitFor(() => expect(reviewMock).toHaveBeenCalledWith(expect.objectContaining({
    proposal_id: 'p1', expected_revision: 1, new_status: 'needs_evidence',
    review_note: 'Compare the source image with the navy variant before changing the selector.', request_id: expect.any(String),
  })));
});
it('keeps the review draft after a conflict and offers refresh', async () => {
  reviewMock.mockRejectedValue(new Error('version_conflict'));
  mount(); await screen.findByText('Verify selected product images'); fireEvent.click(screen.getByText('Review proposal'));
  fireEvent.change(screen.getByLabelText('Review note'), { target: { value: 'Needs a labelled example.' } });
  fireEvent.click(screen.getByRole('button', { name: 'Save review' }));
  expect(await screen.findByText(/Another reviewer changed this proposal/)).toBeInTheDocument();
  expect(screen.getByLabelText('Review note')).toHaveValue('Needs a labelled example.');
  expect(screen.getByRole('button', { name: 'Refresh proposal' })).toBeInTheDocument();
  const updated = structuredClone(dashboard); updated.proposals[0].revision = 2; updated.proposals[0].status = 'planned';
  fetchMock.mockResolvedValue(updated);
  fireEvent.click(screen.getByRole('button', { name: 'Refresh proposal' }));
  await waitFor(() => expect(screen.queryByRole('button', { name: 'Refresh proposal' })).not.toBeInTheDocument());
  expect(screen.getByLabelText('Review note')).toHaveValue('Needs a labelled example.');
  reviewMock.mockResolvedValue(undefined);
  fireEvent.click(screen.getByRole('button', { name: 'Save review' }));
  await waitFor(() => expect(reviewMock).toHaveBeenLastCalledWith(expect.objectContaining({ expected_revision: 2 })));
});
it('reloads when changing the time window and can recover a load error', async () => {
  fetchMock.mockRejectedValueOnce(new Error('Service unavailable')); mount();
  expect(await screen.findByRole('alert')).toHaveTextContent('Service unavailable');
  fireEvent.click(screen.getByRole('button', { name: 'Refresh' }));
  await screen.findByTestId('attention-rate');
  fireEvent.change(screen.getByLabelText('Save window'), { target: { value: '168' } });
  await waitFor(() => expect(fetchMock).toHaveBeenLastCalledWith(168, undefined));
});
