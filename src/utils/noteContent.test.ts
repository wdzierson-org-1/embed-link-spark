import { noteIsEmpty } from './noteContent';

describe('noteIsEmpty', () => {
  it('treats nothing, whitespace and the editor’s empty document as empty', () => {
    expect(noteIsEmpty(null)).toBe(true);
    expect(noteIsEmpty(undefined)).toBe(true);
    expect(noteIsEmpty('   \n')).toBe(true);
    expect(noteIsEmpty('{"type":"doc","content":[{"type":"paragraph"}]}')).toBe(true);
    expect(noteIsEmpty('{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"  "}]}]}')).toBe(true);
    expect(noteIsEmpty('<p></p>')).toBe(true);
    expect(noteIsEmpty('<p><br></p>')).toBe(true);
  });

  it('keeps anything a person wrote, including an image on its own', () => {
    expect(noteIsEmpty('hello')).toBe(false);
    expect(noteIsEmpty('{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"a"}]}]}')).toBe(false);
    expect(noteIsEmpty('{"type":"doc","content":[{"type":"image","attrs":{"src":"https://x/y.png"}}]}')).toBe(false);
    expect(noteIsEmpty('<p>hi</p>')).toBe(false);
  });

  it('does not mistake broken JSON for an empty note', () => {
    expect(noteIsEmpty('{not json')).toBe(false);
  });
});
