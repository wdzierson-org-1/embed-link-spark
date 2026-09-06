// src/utils/agentActivity.ts
//
// Renders agent_access_log rows as the sentences Settings → Connected agents
// shows ("Claude searched your stash for restaurants, Tue 2:14pm" — the
// audit-log requirement in the 2026-08-28 context-layer spec, Workstream D).

export const MCP_SERVER_URL = 'https://www.gostash.it/mcp';

export interface AgentAccessRow {
  id: string;
  client_id: string;
  tool: string;
  query: string | null;
  filters: Record<string, unknown> | null;
  item_id: string | null;
  item_title: string | null;
  result_count: number | null;
  created_at: string;
}

const TYPE_LABELS: Record<string, string> = {
  text: 'notes', link: 'links', image: 'photos', audio: 'audio', video: 'videos', document: 'documents',
};

const joinNatural = (parts: string[]): string =>
  parts.length <= 1 ? parts.join('') : `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}`;

const countPhrase = (n: number | null): string => {
  if (n === null) return '';
  if (n === 0) return ' · no results';
  return ` · ${n} result${n === 1 ? '' : 's'}`;
};

export function describeAgentActivity(row: AgentAccessRow, clientName: string): string {
  const who = clientName || 'An agent';
  if (row.tool === 'search_stash') {
    if (row.query) return `${who} searched for “${row.query}”${countPhrase(row.result_count)}`;
    const types = Array.isArray(row.filters?.types) ? (row.filters!.types as string[]).map((t) => TYPE_LABELS[t] ?? t) : [];
    const what = types.length ? `recent ${joinNatural(types)}` : 'recent saves';
    return `${who} listed ${what}${countPhrase(row.result_count)}`;
  }
  if (row.tool === 'get_item') {
    if (row.item_title) return `${who} read “${row.item_title}”`;
    return row.result_count === 0 ? `${who} tried to read an item that wasn’t found` : `${who} read an item`;
  }
  return `${who} used ${row.tool}`;
}
