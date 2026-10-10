import { Editor } from '@tiptap/core';
import { StarterKit } from 'novel';
import { TimestampLinks } from './TimestampLinks';
import { SEEK_EVENT } from '@/components/edit/MediaClock';

const editorWith = (html: string) =>
  new Editor({ element: document.createElement('div'), extensions: [StarterKit, TimestampLinks], content: html });

describe('timestamp markers in a note', () => {
  it('are rendered as seek points without touching the text', () => {
    const editor = editorWith('<p>At [1:42] it starts, and [1:02:03] it ends.</p>');
    const marks = editor.view.dom.querySelectorAll('.stash-timestamp');
    expect(Array.from(marks).map((m) => m.getAttribute('data-seconds'))).toEqual(['102', '3723']);
    expect(editor.getText()).toBe('At [1:42] it starts, and [1:02:03] it ends.');
    editor.destroy();
  });

  it('follow edits', () => {
    const editor = editorWith('<p>Nothing yet</p>');
    expect(editor.view.dom.querySelector('.stash-timestamp')).toBeNull();
    editor.commands.insertContent(' [0:30]');
    expect(editor.view.dom.querySelector('.stash-timestamp')).not.toBeNull();
    editor.destroy();
  });

  it('a click on a marker asks the panel’s player to seek there', () => {
    const editor = editorWith('<p>Go to [0:45] now</p>');
    const heard = vi.fn();
    window.addEventListener(SEEK_EVENT, heard);
    const marker = editor.view.dom.querySelector('.stash-timestamp') as HTMLElement;
    const handled = editor.view.someProp('handleClick', (handler) => handler(editor.view, 0, { target: marker } as unknown as MouseEvent));
    expect(handled).toBe(true);
    expect((heard.mock.calls[0][0] as CustomEvent).detail).toEqual({ seconds: 45 });
    window.removeEventListener(SEEK_EVENT, heard);
    editor.destroy();
  });
});
