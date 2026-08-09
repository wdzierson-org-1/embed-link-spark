// Routing contract for the chat mole's composer: it is both an ask box and a
// capture surface. Links and explicit remember/save/note prefixes become items;
// everything else is a question. Keep the rules few and predictable — the
// composer hint text teaches exactly these.

export type MoleMessage =
  | { kind: 'save-url'; url: string; note: string }
  | { kind: 'save-note'; note: string }
  | { kind: 'ask' };

const URL_PATTERN = /(https?:\/\/[^\s]+)/;
const NOTE_PREFIX = /^(remember|save|note):\s*/i;

export const classifyMoleMessage = (raw: string): MoleMessage => {
  const text = raw.trim();

  const prefixMatch = text.match(NOTE_PREFIX);
  if (prefixMatch) {
    return { kind: 'save-note', note: text.slice(prefixMatch[0].length).trim() };
  }

  const urlMatch = text.match(URL_PATTERN);
  if (urlMatch) {
    const url = urlMatch[1].replace(/[.,!?;)\]]+$/, '');
    const note = text.replace(urlMatch[1], '').replace(/\s+/g, ' ').trim();
    return { kind: 'save-url', url, note };
  }

  return { kind: 'ask' };
};
