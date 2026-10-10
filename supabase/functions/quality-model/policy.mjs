import { qualityResultFormat } from './resultSchema.mjs';

const uuid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const pathPattern = new RegExp(`/quality-model/(${uuid})/([1-9][0-9]*)/v1/chat/completions$`, 'i');

export function parseLeasePath(path) {
  const match = path.match(pathPattern);
  if (!match || !Number.isSafeInteger(Number(match[2]))) return null;
  return { id: match[1], fence: Number(match[2]) };
}

export function prepareModelRequest(body, model) {
  if (!body || !Array.isArray(body.messages) || body.messages.length < 1 || body.messages.length > 80) throw new Error('invalid_messages');
  if (JSON.stringify(body.messages).length > 64000) throw new Error('input_too_large');
  const roles = new Set(['system', 'developer', 'user', 'assistant', 'tool']);
  const messages = body.messages.map(message => {
    if (!message || !roles.has(message.role)) throw new Error('invalid_role');
    let content = message.content;
    if (Array.isArray(content)) {
      if (!content.every(part => part && part.type === 'text' && typeof part.text === 'string')) throw new Error('text_only');
      content = content.map(part => ({ type: 'text', text: part.text }));
    } else if (typeof content !== 'string' && !(content === null && message.role === 'assistant')) throw new Error('invalid_content');
    const clean = { role: message.role, content };
    if (message.role === 'tool' && typeof message.tool_call_id === 'string') clean.tool_call_id = message.tool_call_id;
    if (message.role === 'assistant' && Array.isArray(message.tool_calls)) clean.tool_calls = message.tool_calls;
    return clean;
  });
  // Initial snapshot-audit pilot has no tools. A client cannot opt into
  // external retrieval, extra completions, storage, or a more expensive model.
  return { model, messages, response_format: qualityResultFormat(), max_tokens: 4096, stream: body.stream === true,
    ...(body.stream === true ? { stream_options: { include_usage: true } } : {}), store: false };
}
