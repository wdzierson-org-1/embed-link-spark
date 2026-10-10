import { Extension } from '@tiptap/core';
import { Plugin, PluginKey } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';
import type { Node as ProseMirrorNode } from '@tiptap/pm/model';
import { TIMESTAMP_PATTERN, parseTimestamp } from '@/utils/timestamps';
import { dispatchSeek } from '@/components/edit/MediaClock';

const key = new PluginKey('stash-timestamps');

/** `[1:42]` and `[1:02:03]` in the text become seek points; the text itself is untouched */
const decorate = (doc: ProseMirrorNode): DecorationSet => {
  const decorations: Decoration[] = [];
  doc.descendants((node, pos) => {
    if (!node.isText || !node.text) return;
    for (const match of node.text.matchAll(TIMESTAMP_PATTERN)) {
      const seconds = parseTimestamp(match[0].slice(1, -1));
      if (seconds === null || match.index === undefined) continue;
      decorations.push(
        Decoration.inline(pos + match.index, pos + match.index + match[0].length, {
          class: 'stash-timestamp',
          'data-seconds': String(seconds),
          title: 'go to this moment',
        }),
      );
    }
  });
  return DecorationSet.create(doc, decorations);
};

/**
 * Timestamped notes (docs/ui-changes.md 2026-10-10): a `[m:ss]` marker in a note is a link into
 * the save's media. Clicking one asks whichever player is on the panel to seek there
 * (MediaClock). Plain text underneath, so every client reads the note the same way.
 */
export const TimestampLinks = Extension.create({
  name: 'stashTimestamps',
  addProseMirrorPlugins() {
    return [
      new Plugin({
        key,
        state: {
          init: (_config, state) => decorate(state.doc),
          apply: (transaction, old) => (transaction.docChanged ? decorate(transaction.doc) : old),
        },
        props: {
          decorations(state) {
            return key.getState(state) as DecorationSet | undefined;
          },
          handleClick(_view, _pos, event) {
            const target = (event.target as HTMLElement | null)?.closest?.('.stash-timestamp');
            if (!target) return false;
            const seconds = Number(target.getAttribute('data-seconds'));
            if (Number.isFinite(seconds)) dispatchSeek(seconds);
            return true;
          },
        },
      }),
    ];
  },
});
