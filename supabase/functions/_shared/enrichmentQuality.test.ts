import { describe, expect, it } from 'vitest';
import { assessEnrichment, inspectSourceText, isPlaceholderMetadata, sourceIdentity, reviewCadence, nextReviewHours, enrichmentSearchText } from './enrichmentQuality';
const tik = 'https://www.tiktok.com/t/example/';
const ig = 'https://www.instagram.com/reel/example/';
const errorPage = "TikTok Log in Couldn't find this page Check out more trending videos on TikTok " + 'Company Careers About Privacy '.repeat(30);
describe('content quality regressions', () => {
  it('rejects a long TikTok error page rather than summarizing the footer', () => {
    expect(inspectSourceText(tik, errorPage)).toMatchObject({ usable: false, reason: 'unavailable_page' });
    expect(assessEnrichment({ type: 'link', url: tik, title: 'TikTok - Make Your Day', description: 'Video by Creator on TikTok', page_body: errorPage, summary: 'TikTok is a social network' }, true).status).toBe('blocked');
  });
  it('keeps a real Instagram caption despite surrounding login chrome and drops comment noise', () => {
    const result = inspectSourceText(ig, 'Instagram Log In Sign Up More options creator 1w Yann LeCun explains why world models matter. Load more comments Spam Like Reply');
    expect(result.usable).toBe(true); expect(result.text).toContain('world models'); expect(result.text).not.toContain('Spam');
  });
  it('does not reject an article quoting a site error in its body', () => {
    expect(inspectSourceText('https://example.com/article', 'A debugging guide for developers. '.repeat(30) + "Couldn't find this page").usable).toBe(true);
  });
  it('treats a short genuine transcript as evidence, and a missing-transcript message as failure', () => {
    expect(inspectSourceText(tik, 'Turn left at the red door.', 'transcript').usable).toBe(true);
    expect(inspectSourceText(tik, 'No transcript available', 'transcript').usable).toBe(false);
  });
  it('does not declare a caption-only Reel complete', () => {
    const item = { type: 'link', url: ig, title: 'Learning world models', description: 'An explanation of spatial reasoning.', page_body: 'The creator discusses learning world models and spatial reasoning.' };
    expect(assessEnrichment(item, true)).toMatchObject({ status: 'partial', reasons: ['missing_media_evidence'] });
    expect(assessEnrichment({ ...item, attributes: { enrichment: { evidence: { transcript: true } } } }, true).status).toBe('ready');
  });
  it('distinguishes profiles, videos, and impostor domains', () => {
    expect(sourceIdentity({ type: 'link', url: 'https://www.tiktok.com/@jeweler?_r=1' }).key).toBe('tiktok:profile');
    expect(sourceIdentity({ type: 'link', url: 'https://tiktok.com.attacker.test/video/1' }).source).not.toBe('tiktok');
  });
  it('recognizes platform placeholders but retains descriptive titles', () => {
    for (const s of ['Instagram', 'TikTok - Make Your Day', 'Video by JMM Collector on TikTok']) expect(isPlaceholderMetadata(s)).toBe(true);
    expect(isPlaceholderMetadata('How Instagram changed photography')).toBe(false);
  });
  it('generalizes evidence requirements without demanding OCR from a photo or a summary from a note', () => {
    expect(assessEnrichment({ type: 'image', title: 'A red bicycle', description: 'A red bicycle leaning against a brick wall.' }, true).status).toBe('ready');
    expect(assessEnrichment({ type: 'text', title: 'Buy milk', content: 'Buy milk' }, true).status).toBe('ready');
    expect(assessEnrichment({ type: 'audio', title: 'Meeting', description: 'Discussion' }, true).status).toBe('partial');
    expect(assessEnrichment({ type: 'document', mime_type: 'application/octet-stream' }, false).status).toBe('unsupported');
  });
  it('keeps user notes and drops contaminated generated text during indexing', () => {
    const text = enrichmentSearchText({ type: 'link', url: tik, title: 'TikTok - Make Your Day', page_body: errorPage, summary: 'TikTok company information', content: 'Glasses I liked' });
    expect(text).toContain('Glasses I liked'); expect(text).not.toContain('company information'); expect(text).not.toContain('Careers');
  });
});
describe('adaptive review policy', () => {
  const healthy = { assessed: 20, ready: 20, blocked: 0, failures: 0, attempts: 10 };
  it('escalates on poor outcomes and requires sustained recovery before slowing down', () => {
    expect(reviewCadence({ ...healthy, blocked: 1 }).cadence).toBe('hourly');
    expect(reviewCadence(healthy, 'hourly', 0).cadence).toBe('hourly');
    expect(reviewCadence(healthy, 'hourly', 2).cadence).toBe('daily');
  });
  it('backs off repeated failures and missing providers', () => {
    expect(nextReviewHours('partial', 'hourly', 1)).toBe(1);
    expect(nextReviewHours('partial', 'hourly', 2)).toBe(2);
    expect(nextReviewHours('partial', 'hourly', 3)).toBe(24);
    expect(nextReviewHours('partial', 'hourly', 5)).toBe(168);
    expect(nextReviewHours('partial', 'hourly', 1, true)).toBe(24);
  });
});
