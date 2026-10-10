import { Editor } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import { describe, expect, it } from 'vitest';
import { formatLine, isolateLine } from './lineCommands';

const makeEditor = (content: string) =>
  new Editor({ element: document.createElement('div'), extensions: [StarterKit], content });

/** Absolute positions of a text run: where it starts and where it ends */
const runAt = (editor: Editor, text: string): { from: number; to: number } => {
  let found: { from: number; to: number } | null = null;
  editor.state.doc.descendants((node, pos) => {
    if (!found && node.isText && node.text === text) found = { from: pos, to: pos + text.length };
    return !found;
  });
  if (!found) throw new Error(`no text run "${text}"`);
  return found;
};

/** Caret right after the given text run */
const caretAfter = (editor: Editor, text: string) => editor.commands.setTextSelection(runAt(editor, text).to);

const heading = (editor: Editor) => formatLine(editor, null, (chain) => chain.setNode('heading', { level: 1 }));

describe('isolateLine / formatLine', () => {
  it('formats only the line the caret is on when the lines are joined by hard breaks', () => {
    const editor = makeEditor('<p>alpha<br>beta<br>gamma</p>');
    caretAfter(editor, 'beta');
    heading(editor);
    expect(editor.getHTML()).toBe('<p>alpha</p><h1>beta</h1><p>gamma</p>');
  });

  it('keeps the first and last lines in their own blocks', () => {
    const first = makeEditor('<p>alpha<br>beta</p>');
    caretAfter(first, 'alpha');
    heading(first);
    expect(first.getHTML()).toBe('<h1>alpha</h1><p>beta</p>');

    const last = makeEditor('<p>alpha<br>beta</p>');
    caretAfter(last, 'beta');
    heading(last);
    expect(last.getHTML()).toBe('<p>alpha</p><h1>beta</h1>');
  });

  it('works from the start of a line, right after the break', () => {
    const editor = makeEditor('<p>alpha<br>beta</p>');
    editor.commands.setTextSelection(runAt(editor, 'beta').from);
    heading(editor);
    expect(editor.getHTML()).toBe('<p>alpha</p><h1>beta</h1>');
  });

  it('leaves a block without hard breaks alone and formats just that block', () => {
    const editor = makeEditor('<p>alpha</p><p>beta</p>');
    caretAfter(editor, 'beta');
    expect(isolateLine(editor)).toBe(false);
    heading(editor);
    expect(editor.getHTML()).toBe('<p>alpha</p><h1>beta</h1>');
  });

  it('turns one line of a hard-broken heading back into text, keeping the others', () => {
    const editor = makeEditor('<h1>alpha<br>beta<br>gamma</h1>');
    caretAfter(editor, 'beta');
    formatLine(editor, null, (chain) => chain.clearNodes());
    expect(editor.getHTML()).toBe('<h1>alpha</h1><p>beta</p><h1>gamma</h1>');
  });

  it('splits inside a list item so only that line takes the format', () => {
    const editor = makeEditor('<ul><li><p>alpha<br>beta</p></li></ul>');
    caretAfter(editor, 'beta');
    heading(editor);
    expect(editor.getHTML()).toBe('<ul><li><p>alpha</p><h1>beta</h1></li></ul>');
  });

  it('isolates every line a selection spans', () => {
    const editor = makeEditor('<p>alpha<br>beta<br>gamma<br>delta</p>');
    editor.commands.setTextSelection({ from: runAt(editor, 'beta').from, to: runAt(editor, 'gamma').to });
    heading(editor);
    expect(editor.getHTML()).toBe('<p>alpha</p><h1>beta<br>gamma</h1><p>delta</p>');
  });

  it('drops the slash text before formatting, like the menu does', () => {
    const editor = makeEditor('<p>alpha<br>beta/</p>');
    const slash = runAt(editor, 'beta/');
    const range = { from: slash.to - 1, to: slash.to };
    editor.commands.setTextSelection(slash.to);
    formatLine(editor, range, (chain) => chain.setNode('heading', { level: 2 }));
    expect(editor.getHTML()).toBe('<p>alpha</p><h2>beta</h2>');
  });

  it('is one undo step', () => {
    const editor = makeEditor('<p>alpha<br>beta</p>');
    caretAfter(editor, 'beta');
    heading(editor);
    editor.commands.undo();
    expect(editor.getHTML()).toBe('<p>alpha<br>beta</p>');
  });
});
