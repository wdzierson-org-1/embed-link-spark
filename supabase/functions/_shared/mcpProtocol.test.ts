import { describe, expect, it, vi } from 'vitest';
import {
  LATEST_PROTOCOL_VERSION, errorResult, handleMcpMessage, negotiateProtocolVersion,
  parseJsonRpcBody, textResult, type McpServerSpec,
} from './mcpProtocol';

const spec = (): McpServerSpec => ({
  name: 'stash',
  version: '1.0.0',
  instructions: 'Search first.',
  tools: [{ name: 'search_stash', description: 'Search', inputSchema: { type: 'object', properties: {} } }],
  callTool: vi.fn(async (name, args) => textResult(`${name}:${JSON.stringify(args)}`, { ok: true })),
});

describe('negotiateProtocolVersion', () => {
  it('echoes a supported version and falls back to the latest otherwise', () => {
    expect(negotiateProtocolVersion('2025-06-18')).toBe('2025-06-18');
    expect(negotiateProtocolVersion('2024-11-05')).toBe('2024-11-05');
    expect(negotiateProtocolVersion('1999-01-01')).toBe(LATEST_PROTOCOL_VERSION);
    expect(negotiateProtocolVersion(undefined)).toBe(LATEST_PROTOCOL_VERSION);
  });
});

describe('handleMcpMessage', () => {
  it('answers initialize with capabilities, server info and instructions', async () => {
    const res = await handleMcpMessage(
      { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {} } },
      spec(),
    );
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      jsonrpc: '2.0', id: 1,
      result: { protocolVersion: '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'stash', version: '1.0.0' }, instructions: 'Search first.' },
    });
  });

  it('accepts notifications with 202 and no body', async () => {
    const res = await handleMcpMessage({ jsonrpc: '2.0', method: 'notifications/initialized' }, spec());
    expect(res).toEqual({ status: 202, body: null });
  });

  it('answers ping and tools/list', async () => {
    expect(await handleMcpMessage({ jsonrpc: '2.0', id: 'a', method: 'ping' }, spec())).toEqual({
      status: 200, body: { jsonrpc: '2.0', id: 'a', result: {} },
    });
    const list = await handleMcpMessage({ jsonrpc: '2.0', id: 2, method: 'tools/list' }, spec());
    expect(list.body).toMatchObject({ result: { tools: [{ name: 'search_stash' }] } });
  });

  it('runs tools/call and passes arguments through', async () => {
    const s = spec();
    const res = await handleMcpMessage(
      { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'search_stash', arguments: { query: 'x' } } }, s,
    );
    expect(s.callTool).toHaveBeenCalledWith('search_stash', { query: 'x' });
    expect(res.body).toMatchObject({ id: 3, result: { content: [{ type: 'text', text: 'search_stash:{"query":"x"}' }], structuredContent: { ok: true } } });
  });

  it('rejects unknown tools and non-object arguments with -32602', async () => {
    const bad = await handleMcpMessage({ jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'nope' } }, spec());
    expect(bad.body).toMatchObject({ id: 4, error: { code: -32602 } });
    const badArgs = await handleMcpMessage(
      { jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'search_stash', arguments: [1] } }, spec(),
    );
    expect(badArgs.body).toMatchObject({ id: 5, error: { code: -32602 } });
  });

  it('turns a throwing tool into an isError result, not a protocol error', async () => {
    const s = spec();
    (s.callTool as ReturnType<typeof vi.fn>).mockRejectedValueOnce(new Error('boom'));
    const res = await handleMcpMessage({ jsonrpc: '2.0', id: 6, method: 'tools/call', params: { name: 'search_stash', arguments: {} } }, s);
    expect(res.body).toMatchObject({ id: 6, result: { isError: true, content: [{ type: 'text', text: expect.stringContaining('boom') }] } });
  });

  it('returns -32601 for unknown methods and -32600 for malformed messages', async () => {
    expect((await handleMcpMessage({ jsonrpc: '2.0', id: 7, method: 'resources/list' }, spec())).body)
      .toMatchObject({ id: 7, error: { code: -32601 } });
    expect((await handleMcpMessage({ id: 8, method: 'ping' }, spec())).body).toMatchObject({ id: 8, error: { code: -32600 } });
    expect((await handleMcpMessage('nonsense', spec())).body).toMatchObject({ id: null, error: { code: -32600 } });
  });

  it('handles batches: responses only for requests; all-notifications → 202', async () => {
    const mixed = await handleMcpMessage(
      [{ jsonrpc: '2.0', method: 'notifications/initialized' }, { jsonrpc: '2.0', id: 9, method: 'ping' }], spec(),
    );
    expect(mixed).toEqual({ status: 200, body: [{ jsonrpc: '2.0', id: 9, result: {} }] });
    expect(await handleMcpMessage([{ jsonrpc: '2.0', method: 'notifications/cancelled' }], spec())).toEqual({ status: 202, body: null });
    expect((await handleMcpMessage([], spec())).status).toBe(400);
  });

  it('ignores client responses (messages with result/error and no method)', async () => {
    expect(await handleMcpMessage({ jsonrpc: '2.0', id: 1, result: {} }, spec())).toEqual({ status: 202, body: null });
  });
});

describe('parseJsonRpcBody', () => {
  it('parses JSON and maps parse failures to a -32700 400', () => {
    expect(parseJsonRpcBody('{"a":1}')).toEqual({ ok: true, value: { a: 1 } });
    const bad = parseJsonRpcBody('{nope');
    expect(bad.ok).toBe(false);
    if (!bad.ok) expect(bad.response).toMatchObject({ status: 400, body: { error: { code: -32700 } } });
  });
});

describe('result helpers', () => {
  it('build text and error results', () => {
    expect(textResult('hi')).toEqual({ content: [{ type: 'text', text: 'hi' }] });
    expect(textResult('hi', { n: 1 })).toEqual({ content: [{ type: 'text', text: 'hi' }], structuredContent: { n: 1 } });
    expect(errorResult('no')).toEqual({ content: [{ type: 'text', text: 'no' }], isError: true });
  });
});
