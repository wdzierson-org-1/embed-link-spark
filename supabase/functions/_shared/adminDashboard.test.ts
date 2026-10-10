import { describe, expect, it } from 'vitest';
import { ADMIN_ITEM_COLUMNS, parseAdminRequest } from './adminDashboard';
import { ITEM_LIST_COLUMN_NAMES } from '@/hooks/useItems';

const UUID = '0a0afaa8-0e11-47e9-887f-223816a9bb53';

describe('parseAdminRequest', () => {
  it('accepts the users action', () => {
    expect(parseAdminRequest({ action: 'users' })).toEqual({ action: 'users' });
  });

  it('accepts items with a uuid user_id', () => {
    expect(parseAdminRequest({ action: 'items', user_id: UUID })).toEqual({ action: 'items', userId: UUID });
  });

  it('rejects items without a valid uuid', () => {
    expect(parseAdminRequest({ action: 'items' })).toEqual({ error: 'user_id must be a uuid' });
    expect(parseAdminRequest({ action: 'items', user_id: 'nope' })).toEqual({ error: 'user_id must be a uuid' });
    expect(parseAdminRequest({ action: 'items', user_id: 42 })).toEqual({ error: 'user_id must be a uuid' });
  });

  it('rejects unknown or missing actions and non-object bodies', () => {
    expect(parseAdminRequest({ action: 'delete' })).toEqual({ error: 'unknown action' });
    expect(parseAdminRequest({})).toEqual({ error: 'unknown action' });
    expect(parseAdminRequest(null)).toEqual({ error: 'unknown action' });
    expect(parseAdminRequest('users')).toEqual({ error: 'unknown action' });
  });

  it('accepts bounded enrichment windows and proposal filters', () => {
    expect(parseAdminRequest({ action: 'enrichment' })).toEqual({ action: 'enrichment', lookbackHours: 24, proposalStatus: null, proposalLimit: 50 });
    expect(parseAdminRequest({ action: 'enrichment', lookback_hours: 168, proposal_status: 'needs_evidence', proposal_limit: 10 }))
      .toEqual({ action: 'enrichment', lookbackHours: 168, proposalStatus: 'needs_evidence', proposalLimit: 10 });
  });

  it.each([
    { lookback_hours: 1 }, { lookback_hours: '24' }, { lookback_hours: null },
    { proposal_status: 'published' }, { proposal_limit: 51 }, { proposal_limit: 0 }, { proposal_limit: 1.5 },
    { actor_user_id: UUID }, { evidence_urls: ['https://example.com'] },
  ])('rejects an invalid enrichment request: %o', (patch) => {
    expect(parseAdminRequest({ action: 'enrichment', ...patch })).toHaveProperty('error');
  });

  it('accepts an evidence-preserving proposal triage request', () => {
    expect(parseAdminRequest({ action: 'review_proposal', proposal_id: UUID, expected_revision: 0,
      new_status: 'planned', review_note: '  Reproduce against a held-out fixture.  ', request_id: UUID }))
      .toEqual({ action: 'review_proposal', proposalId: UUID, expectedRevision: 0, newStatus: 'planned',
        reviewNote: 'Reproduce against a held-out fixture.', requestId: UUID });
  });

  it.each([
    { proposal_id: 'nope' }, { expected_revision: -1 }, { expected_revision: 1.5 },
    { expected_revision: Number.MAX_SAFE_INTEGER + 1 }, { new_status: 'published' },
    { review_note: '' }, { review_note: '  ' }, { review_note: 'x'.repeat(2001) },
    { review_note: null }, { request_id: 'nope' }, { actor_user_id: UUID },
    { evidence_urls: ['https://example.com'] }, { title: 'Changed evidence' },
  ])('rejects an invalid or evidence-changing review: %o', (patch) => {
    expect(parseAdminRequest({ action: 'review_proposal', proposal_id: UUID, expected_revision: 0,
      new_status: 'needs_evidence', review_note: 'Needs a source check.', request_id: UUID, ...patch })).toHaveProperty('error');
  });
});

describe('ADMIN_ITEM_COLUMNS', () => {
  // The member page recreates the library grid; it must load exactly what the
  // grid loads (plus the owner, for the read-only view) or the cards drift.
  it('matches the columns the library grid loads, plus user_id', () => {
    expect(ADMIN_ITEM_COLUMNS).toEqual([...ITEM_LIST_COLUMN_NAMES, 'user_id']);
  });
});
