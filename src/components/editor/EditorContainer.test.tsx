import { fireEvent, render, screen } from '@testing-library/react';
import EditorContainer from './EditorContainer';

/**
 * Novel's editor is a contenteditable jsdom can't drive: a stub lets a test fire the container's
 * update and blur handlers with a fake editor reporting whatever document the test sets.
 */
const fake = vi.hoisted(() => ({ doc: {} as Record<string, unknown> }));
vi.mock('./EditorContentRenderer', () => ({
  default: (props: { onUpdate: (editor: unknown) => void; onBlur?: (editor: unknown) => void }) => {
    const editor = { getJSON: () => fake.doc };
    return (
      <div>
        <button onClick={() => props.onUpdate(editor)}>update</button>
        <button onClick={() => props.onBlur?.(editor)}>blur</button>
      </div>
    );
  },
}));

const EMPTY_DOC = { type: 'doc', content: [{ type: 'paragraph' }] };
const text = (value: string) => ({ type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: value }] }] });

const renderEditor = (content: string) => {
  const onContentChange = vi.fn();
  render(<EditorContainer content={content} onContentChange={onContentChange} handleImageUpload={vi.fn()} editorKey="k" />);
  return onContentChange;
};

beforeEach(() => {
  vi.spyOn(console, 'log').mockImplementation(() => {});
});

describe('what the editor writes back', () => {
  it('writes nothing when an untouched empty editor blurs over an empty note', () => {
    fake.doc = EMPTY_DOC;
    const onContentChange = renderEditor('');
    fireEvent.click(screen.getByText('blur'));
    expect(onContentChange).not.toHaveBeenCalled();
  });

  it('also treats a stored empty document as empty, so reopening it writes nothing', () => {
    fake.doc = EMPTY_DOC;
    const onContentChange = renderEditor(JSON.stringify(EMPTY_DOC));
    fireEvent.click(screen.getByText('update')); // the initialisation update is skipped
    fireEvent.click(screen.getByText('update'));
    fireEvent.click(screen.getByText('blur'));
    expect(onContentChange).not.toHaveBeenCalled();
  });

  it('saves typed text on blur', () => {
    fake.doc = text('a thought');
    const onContentChange = renderEditor('');
    fireEvent.click(screen.getByText('blur'));
    expect(onContentChange).toHaveBeenCalledWith(JSON.stringify(text('a thought')));
  });

  it('still saves when a note that had text is emptied — clearing is an edit', () => {
    fake.doc = EMPTY_DOC;
    const onContentChange = renderEditor(JSON.stringify(text('old words')));
    fireEvent.click(screen.getByText('blur'));
    expect(onContentChange).toHaveBeenCalledWith(JSON.stringify(EMPTY_DOC));
  });
});
