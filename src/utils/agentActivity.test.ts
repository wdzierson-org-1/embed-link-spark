import { describe, expect, it } from 'vitest';
import { describeAgentActivity, type AgentAccessRow } from './agentActivity';

const row = (over: Partial<AgentAccessRow>): AgentAccessRow => ({
  id: 'r1', client_id: 'c1', tool: 'search_stash', query: null, filters: null,
  item_id: null, item_title: null, result_count: null, created_at: '2026-09-05T14:14:00Z', ...over,
});

describe('describeAgentActivity', () => {
  it('describes searches with the query and result count', () => {
    expect(describeAgentActivity(row({ query: 'restaurants in Saratoga', result_count: 3 }), 'Claude'))
      .toBe('Claude searched for “restaurants in Saratoga” · 3 results');
    expect(describeAgentActivity(row({ query: 'x', result_count: 1 }), 'Claude')).toBe('Claude searched for “x” · 1 result');
    expect(describeAgentActivity(row({ query: 'x', result_count: 0 }), 'Claude')).toBe('Claude searched for “x” · no results');
  });

  it('describes listings, with the type filter when present', () => {
    expect(describeAgentActivity(row({ result_count: 20 }), 'Claude')).toBe('Claude listed recent saves · 20 results');
    expect(describeAgentActivity(row({ filters: { types: ['link'] }, result_count: 5 }), 'Cursor')).toBe('Cursor listed recent links · 5 results');
    expect(describeAgentActivity(row({ filters: { types: ['image', 'audio'] }, result_count: 2 }), 'Cursor')).toBe('Cursor listed recent photos and audio · 2 results');
  });

  it('describes reads by title and misses honestly', () => {
    expect(describeAgentActivity(row({ tool: 'get_item', item_title: 'Beyond the Basics', result_count: 1 }), 'Claude')).toBe('Claude read “Beyond the Basics”');
    expect(describeAgentActivity(row({ tool: 'get_item', item_title: null, result_count: 0 }), 'Claude')).toBe('Claude tried to read an item that wasn’t found');
  });

  it('falls back for unknown tools', () => {
    expect(describeAgentActivity(row({ tool: 'future_tool' }), 'Claude')).toBe('Claude used future_tool');
  });
});
