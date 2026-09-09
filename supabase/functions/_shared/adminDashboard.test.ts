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
});

describe('ADMIN_ITEM_COLUMNS', () => {
  // The member page recreates the library grid; it must load exactly what the
  // grid loads (plus the owner, for the read-only view) or the cards drift.
  it('matches the columns the library grid loads, plus user_id', () => {
    expect(ADMIN_ITEM_COLUMNS).toEqual([...ITEM_LIST_COLUMN_NAMES, 'user_id']);
  });
});
