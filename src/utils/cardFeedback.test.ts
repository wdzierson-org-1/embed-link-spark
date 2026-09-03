import { describe, expect, it } from 'vitest';
import { buildCardFeedbackSnapshot, CARD_FEEDBACK_ISSUES } from './cardFeedback';

describe('CARD_FEEDBACK_ISSUES', () => {
  it('has unique codes and human labels', () => {
    const codes = CARD_FEEDBACK_ISSUES.map((i) => i.code);
    expect(new Set(codes).size).toBe(codes.length);
    for (const issue of CARD_FEEDBACK_ISSUES) expect(issue.label.length).toBeGreaterThan(8);
  });
});

describe('buildCardFeedbackSnapshot', () => {
  it('keeps the fields a reviewer needs and truncates long text', () => {
    const snap = buildCardFeedbackSnapshot({
      type: 'link',
      title: 'T'.repeat(400),
      description: 'D'.repeat(600),
      url: 'https://example.com/x',
      file_path: 'uid/previews/p.jpg',
      summary: 'a summary',
      attributes: { link: { flavor: 'generic' } },
    });
    expect(snap.title).toHaveLength(300);
    expect(snap.description).toHaveLength(500);
    expect(snap).toMatchObject({ type: 'link', url: 'https://example.com/x', file_path: 'uid/previews/p.jpg', flavor: 'generic', has_summary: true });
  });

  it('tolerates sparse items', () => {
    expect(buildCardFeedbackSnapshot({})).toEqual({
      type: undefined, title: undefined, description: undefined, url: undefined, file_path: undefined, flavor: undefined, has_summary: false,
    });
  });
});
