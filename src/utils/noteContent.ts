import { docIsEmpty } from '@/utils/captureDoc';

/**
 * True when a stored note holds nothing a person wrote: null, whitespace, an empty editor
 * document (`{"type":"doc","content":[{"type":"paragraph"}]}`), or an empty HTML paragraph.
 * The notes field reads this to stay a single line, and the editor to avoid writing one back.
 */
export const noteIsEmpty = (content: string | null | undefined): boolean => {
  const text = content?.trim() ?? '';
  if (!text) return true;
  if (text.startsWith('{')) {
    try {
      return docIsEmpty(JSON.parse(text));
    } catch {
      return false;
    }
  }
  return /^(\s|<p>|<\/p>|<br\s*\/?>|&nbsp;)*$/i.test(text);
};
