// supabase/functions/_shared/askGuidance.test.ts
// @vitest-environment node
//
// Regression for the 2026-10-12 App Store review finding: a real Ask answer cited the right
// note, then offered to set a reminder or open directions — neither exists in Ask's toolset
// (search_stash, browse_catalog, get_item). The prompt must rule such offers out by name and
// point the person at the saved item instead.
import { describe, expect, it } from 'vitest';
import { APP_GUIDE, ASK_TOOL_NAMES, buildAskSystemPrompt } from './askGuidance';

describe('askGuidance — what Ask may offer', () => {
  const prompt = buildAskSystemPrompt('2026-10-12');

  it('names exactly the three retrieval tools as the whole toolset', () => {
    expect(ASK_TOOL_NAMES).toEqual(['search_stash', 'browse_catalog', 'get_item']);
    for (const name of ASK_TOOL_NAMES) expect(prompt).toContain(name);
  });

  it('forbids offering actions the toolset cannot perform, by name', () => {
    const lower = prompt.toLowerCase();
    for (const action of ['reminder', 'directions', 'maps', 'send', 'edit', 'delete', 'share', 'open links']) {
      expect(lower, `rule must name "${action}"`).toContain(action);
    }
    expect(prompt).toMatch(/you cannot[\s\S]*must not offer to/i);
    expect(prompt).toMatch(/never end an answer with an offer/i);
  });

  it('points the person at the saved item instead', () => {
    expect(prompt).toContain('Tap the title to open your saved item.');
  });

  it('no longer advertises phone or WhatsApp setup (withdrawn 2026-10-12)', () => {
    expect(APP_GUIDE).not.toMatch(/whatsapp|sms|phone number|text links/i);
    expect(prompt).not.toMatch(/whatsapp|sms|phone number/i);
  });

  it('tells people where reminders actually live (the item, not Ask)', () => {
    expect(APP_GUIDE).toMatch(/Resurface in/);
  });

  it('carries the date it was built with and the whole app guide', () => {
    expect(prompt).toContain('Today is 2026-10-12.');
    expect(prompt).toContain(APP_GUIDE);
  });
});
