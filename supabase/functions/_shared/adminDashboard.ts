// Request parsing + the item column list for the admin dashboard
// (spec: docs/superpowers/specs/2026-09-08-admin-dashboard-design.md).
// Plain TS with no Deno imports so vitest can check it against the web app's
// useItems column list.

// The member page recreates the library grid, so it loads exactly what the
// grid loads (src/hooks/useItems.ts ITEM_LIST_COLUMN_NAMES) plus the owner.
export const ADMIN_ITEM_COLUMNS = [
  'id',
  'type',
  'title',
  'content',
  'url',
  'file_path',
  'description',
  'summary',
  'created_at',
  'mime_type',
  'file_size',
  'is_public',
  'supplemental_note',
  'attributes',
  'remind_at',
  'reminder_cleared_at',
  'pinned_at',
  'share_token',
  'user_id',
];

export const PROPOSAL_REVIEW_STATUSES = ['new', 'needs_evidence', 'planned', 'dismissed'] as const;
export type ProposalReviewStatus = typeof PROPOSAL_REVIEW_STATUSES[number];

export type AdminRequest =
  | { action: 'users' }
  | { action: 'items'; userId: string }
  | { action: 'enrichment'; lookbackHours: 24 | 168; proposalStatus: ProposalReviewStatus | null; proposalLimit: number }
  | { action: 'review_proposal'; proposalId: string; expectedRevision: number; newStatus: ProposalReviewStatus; reviewNote: string; requestId: string }
  | { error: string };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parseAdminRequest(body: unknown): AdminRequest {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return { error: 'unknown action' };
  const fields = body as Record<string, unknown>;
  const { action, user_id: userId } = fields;
  if (action === 'users') return { action: 'users' };
  if (action === 'items') {
    if (typeof userId !== 'string' || !UUID_RE.test(userId)) return { error: 'user_id must be a uuid' };
    return { action: 'items', userId };
  }
  if (action === 'enrichment') {
    if (Object.keys(fields).some(key => !['action', 'lookback_hours', 'proposal_status', 'proposal_limit'].includes(key))) {
      return { error: 'unknown fields' };
    }
    const lookbackHours = fields.lookback_hours === undefined ? 24 : fields.lookback_hours;
    const proposalStatus = fields.proposal_status ?? null;
    const proposalLimit = fields.proposal_limit === undefined ? 50 : fields.proposal_limit;
    if (lookbackHours !== 24 && lookbackHours !== 168) return { error: 'lookback_hours must be 24 or 168' };
    if (proposalStatus !== null && !isProposalStatus(proposalStatus)) return { error: 'invalid proposal_status' };
    if (typeof proposalLimit !== 'number' || !Number.isInteger(proposalLimit) || proposalLimit < 1 || proposalLimit > 50) {
      return { error: 'proposal_limit must be an integer from 1 to 50' };
    }
    return { action, lookbackHours, proposalStatus, proposalLimit };
  }
  if (action === 'review_proposal') {
    // Review records may change triage state and add an admin note. Evidence,
    // actor identity and worker output are never supplied or rewritten here.
    if (Object.keys(fields).some(key => !['action', 'proposal_id', 'expected_revision', 'new_status', 'review_note', 'request_id'].includes(key))) {
      return { error: 'unknown fields' };
    }
    const { proposal_id: proposalId, expected_revision: expectedRevision, new_status: newStatus,
      review_note: note, request_id: requestId } = fields;
    if (typeof proposalId !== 'string' || !UUID_RE.test(proposalId)) return { error: 'proposal_id must be a uuid' };
    if (typeof requestId !== 'string' || !UUID_RE.test(requestId)) return { error: 'request_id must be a uuid' };
    if (typeof expectedRevision !== 'number' || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      return { error: 'expected_revision must be a nonnegative safe integer' };
    }
    if (!isProposalStatus(newStatus)) return { error: 'invalid new_status' };
    if (typeof note !== 'string' || !note.trim() || note.trim().length > 2000 || note.includes('\0')) {
      return { error: 'review_note must contain 1 to 2000 characters' };
    }
    return { action, proposalId, expectedRevision, newStatus, reviewNote: note.trim(), requestId };
  }
  return { error: 'unknown action' };
}

function isProposalStatus(value: unknown): value is ProposalReviewStatus {
  return typeof value === 'string' && (PROPOSAL_REVIEW_STATUSES as readonly string[]).includes(value);
}
