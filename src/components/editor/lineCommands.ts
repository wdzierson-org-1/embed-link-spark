import type { ChainedCommands, Editor, Range } from '@tiptap/core';
import { TextSelection } from '@tiptap/pm/state';

/**
 * Block formatting works on blocks, but people think in lines: in the composer Enter submits
 * a simple note, so lines are made with Shift+Enter, which joins them into one paragraph with
 * hard breaks — and a heading chosen on one of them used to take every line in the block
 * (Will, 2026-10-10: "each item on the list is supposed to impact only the line it's
 * currently on"). `isolateLine` cuts the hard breaks around the selection and splits the
 * block there, so the line (or the lines a selection spans) is a block of its own and the
 * command that follows touches nothing else. Blocks without hard breaks, and code blocks
 * (newlines there are text), pass through untouched.
 *
 * It dispatches a transaction of its own: TipTap's `clearNodes` maps positions through the
 * whole transaction it runs in, so splitting in the same chain would double-shift them.
 * The history extension groups the dispatches into one undo step.
 *
 * @returns whether the block was split
 */
export const isolateLine = (editor: Editor): boolean => {
  const { state } = editor;
  const { $from, $to, from, to } = state.selection;
  if (!$from.sameParent($to)) return false;
  const block = $from.parent;
  if (!block.isTextblock || block.type.name === 'codeBlock') return false;

  const start = $from.start();
  const fromOffset = $from.parentOffset;
  const toOffset = $to.parentOffset;

  // The last hard break before the selection and the first one after it, as offsets in the block
  let breakBefore = -1;
  let breakAfter = -1;
  block.forEach((child, offset) => {
    if (child.type.name !== 'hardBreak') return;
    if (offset + child.nodeSize <= fromOffset) breakBefore = offset;
    else if (breakAfter === -1 && offset >= toOffset) breakAfter = offset;
  });
  if (breakBefore === -1 && breakAfter === -1) return false;

  const tr = state.tr;
  // Later positions first, so the earlier ones stay valid; each break goes and the block splits
  // where it was
  if (breakAfter !== -1) {
    const pos = start + breakAfter;
    tr.delete(pos, pos + 1);
    tr.split(pos);
  }
  if (breakBefore !== -1) {
    const pos = start + breakBefore;
    tr.delete(pos, pos + 1);
    tr.split(pos);
  }
  // Set the selection by hand: a caret at the split point would otherwise map into the next
  // block. Only the edit before the selection moves it: one token gone, two inserted.
  const shift = breakBefore !== -1 ? 1 : 0;
  tr.setSelection(TextSelection.create(tr.doc, from + shift, to + shift));
  editor.view.dispatch(tr);
  return true;
};

/**
 * Run a block command on the current line only: drop the slash text (`range`, when given),
 * isolate the line, then apply the command in a fresh chain.
 */
export const formatLine = (
  editor: Editor,
  range: Range | null,
  apply: (chain: ChainedCommands) => ChainedCommands,
): boolean => {
  const prepare = editor.chain().focus();
  if (range) prepare.deleteRange(range);
  prepare.run();
  isolateLine(editor);
  return apply(editor.chain()).run();
};
