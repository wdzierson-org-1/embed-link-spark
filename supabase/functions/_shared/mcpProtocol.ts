// supabase/functions/_shared/mcpProtocol.ts
//
// Pure MCP core for a stateless, tools-only server over Streamable HTTP
// (spec: https://modelcontextprotocol.io/specification — basic/transports).
// Deliberately dependency-free: it runs under Deno in the `mcp` edge function
// and under vitest on the web toolchain. The HTTP shell owns auth, headers and
// status codes; this module owns JSON-RPC semantics.

// Every version current clients send; echoed back when requested so nothing
// downgrades unexpectedly. Unknown versions get the newest we know.
export const SUPPORTED_PROTOCOL_VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05'] as const;
export const LATEST_PROTOCOL_VERSION: string = SUPPORTED_PROTOCOL_VERSIONS[0];

export interface McpToolAnnotations {
  readOnlyHint?: boolean;
  destructiveHint?: boolean;
  idempotentHint?: boolean;
  openWorldHint?: boolean;
}

export interface McpToolDefinition {
  name: string;
  title?: string;
  description: string;
  inputSchema: Record<string, unknown>;
  annotations?: McpToolAnnotations;
}

export interface McpToolResult {
  content: Array<{ type: 'text'; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}

export interface McpServerSpec {
  name: string;
  version: string;
  instructions?: string;
  tools: McpToolDefinition[];
  callTool: (name: string, args: Record<string, unknown>) => Promise<McpToolResult>;
}

export interface McpHttpResult {
  status: 200 | 202 | 400;
  body: unknown | null;
}

type JsonRpcId = string | number | null;

export const textResult = (text: string, structured?: Record<string, unknown>): McpToolResult =>
  structured ? { content: [{ type: 'text', text }], structuredContent: structured } : { content: [{ type: 'text', text }] };

export const errorResult = (text: string): McpToolResult => ({ content: [{ type: 'text', text }], isError: true });

const rpcResult = (id: JsonRpcId, result: unknown) => ({ jsonrpc: '2.0', id, result });
const rpcError = (id: JsonRpcId, code: number, message: string) => ({ jsonrpc: '2.0', id, error: { code, message } });

export const negotiateProtocolVersion = (requested: unknown): string =>
  typeof requested === 'string' && (SUPPORTED_PROTOCOL_VERSIONS as readonly string[]).includes(requested)
    ? requested
    : LATEST_PROTOCOL_VERSION;

const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

// One JSON-RPC message → one response object, or null when nothing should be
// sent back (notifications, and responses the client sends us).
async function handleOne(message: unknown, spec: McpServerSpec): Promise<Record<string, unknown> | null> {
  if (!isPlainObject(message)) return rpcError(null, -32600, 'Invalid Request');
  const id = (message.id === undefined ? undefined : message.id) as JsonRpcId | undefined;
  if (message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
    if (message.method === undefined && ('result' in message || 'error' in message)) return null;
    return rpcError(id ?? null, -32600, 'Invalid Request');
  }
  if (id === undefined) return null; // notification
  const params = isPlainObject(message.params) ? message.params : {};

  switch (message.method) {
    case 'initialize':
      return rpcResult(id, {
        protocolVersion: negotiateProtocolVersion(params.protocolVersion),
        capabilities: { tools: {} },
        serverInfo: { name: spec.name, version: spec.version },
        ...(spec.instructions ? { instructions: spec.instructions } : {}),
      });
    case 'ping':
      return rpcResult(id, {});
    case 'tools/list':
      return rpcResult(id, { tools: spec.tools });
    case 'tools/call': {
      const name = params.name;
      if (typeof name !== 'string' || !spec.tools.some((t) => t.name === name)) {
        return rpcError(id, -32602, `Unknown tool: ${String(name)}`);
      }
      const args = params.arguments === undefined ? {} : params.arguments;
      if (!isPlainObject(args)) return rpcError(id, -32602, 'arguments must be an object');
      try {
        return rpcResult(id, await spec.callTool(name, args));
      } catch (e) {
        const detail = e instanceof Error ? e.message : 'unknown error';
        return rpcResult(id, errorResult(`Tool failed: ${detail}`));
      }
    }
    default:
      return rpcError(id, -32601, `Method not found: ${message.method}`);
  }
}

export async function handleMcpMessage(payload: unknown, spec: McpServerSpec): Promise<McpHttpResult> {
  if (Array.isArray(payload)) {
    if (payload.length === 0) return { status: 400, body: rpcError(null, -32600, 'Invalid Request: empty batch') };
    const responses = (await Promise.all(payload.map((m) => handleOne(m, spec)))).filter((r) => r !== null);
    return responses.length ? { status: 200, body: responses } : { status: 202, body: null };
  }
  const response = await handleOne(payload, spec);
  return response ? { status: 200, body: response } : { status: 202, body: null };
}

export function parseJsonRpcBody(raw: string): { ok: true; value: unknown } | { ok: false; response: McpHttpResult } {
  try {
    return { ok: true, value: JSON.parse(raw) };
  } catch {
    return { ok: false, response: { status: 400, body: rpcError(null, -32700, 'Parse error') } };
  }
}
