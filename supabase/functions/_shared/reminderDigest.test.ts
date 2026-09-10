import { describe, expect, it } from 'vitest';
import { digestItemTitle, renderReminderDigest } from './reminderDigest';

const base = { type: 'link', created_at: '2026-09-03T15:00:00Z', remind_at: '2026-09-06T15:00:00Z', content: null, url: null, title: null };
const now = new Date('2026-09-06T13:00:00Z');

describe('digestItemTitle', () => {
  it('prefers title, then content excerpt, then host, then type', () => {
    expect(digestItemTitle({ ...base, id: 'a', title: 'A page' })).toBe('A page');
    expect(digestItemTitle({ ...base, id: 'b', content: 'x'.repeat(100) })).toBe('x'.repeat(80) + '…');
    expect(digestItemTitle({ ...base, id: 'c', url: 'https://www.example.com/path' })).toBe('example.com');
    expect(digestItemTitle({ ...base, id: 'd', type: 'image' })).toBe('Saved image');
  });
});

describe('renderReminderDigest', () => {
  it('pluralises the subject', () => {
    expect(renderReminderDigest({ items: [{ ...base, id: 'a', title: 'A' }], unsubscribeUrl: 'https://u', now }).subject)
      .toBe('1 item you asked to see again');
    expect(renderReminderDigest({ items: [{ ...base, id: 'a', title: 'A' }, { ...base, id: 'b', title: 'B' }], unsubscribeUrl: 'https://u', now }).subject)
      .toBe('2 items you asked to see again');
  });
  it('links each item to the web deep link and escapes html', () => {
    const { html, text } = renderReminderDigest({ items: [{ ...base, id: '11111111-1111-4111-8111-111111111111', title: 'Tom & <Jerry>' }], unsubscribeUrl: 'https://u?token=t', now });
    expect(html).toContain('https://www.gostash.it/home#item=11111111-1111-4111-8111-111111111111');
    expect(html).toContain('Tom &amp; &lt;Jerry&gt;');
    expect(html).not.toContain('<Jerry>');
    expect(text).toContain('Tom & <Jerry>');
    expect(text).toContain('https://www.gostash.it/home#item=11111111-1111-4111-8111-111111111111');
  });
  it('says why the email exists and how to stop it', () => {
    const { html, text } = renderReminderDigest({ items: [{ ...base, id: 'a', title: 'A' }], unsubscribeUrl: 'https://u?token=t', now });
    expect(html).toContain('You asked Stash to remind you about these.');
    expect(html).toContain('href="https://u?token=t"');
    expect(text).toContain('Turn off reminder emails: https://u?token=t');
    expect(html).toContain('Saved Sep 3 · reminder for today');
  });
});
