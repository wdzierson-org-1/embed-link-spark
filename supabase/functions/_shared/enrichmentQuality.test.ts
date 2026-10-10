import { describe, expect, it } from 'vitest';
import { assessEnrichment, inspectSourceText, isPlaceholderMetadata, sourceIdentity, reviewCadence, nextReviewHours, enrichmentSearchText } from './enrichmentQuality';
const tik = 'https://www.tiktok.com/t/example/';
const ig = 'https://www.instagram.com/reel/example/';
const errorPage = "TikTok Log in Couldn't find this page Check out more trending videos on TikTok " + 'Company Careers About Privacy '.repeat(30);
const youtube = 'https://www.youtube.com/watch?v=YGgNBcIgI4s';
const youtubeFooter = '- YouTube About Press Copyright Contact us Creators Advertise Developers Terms Privacy Policy & Safety How YouTube works Test new features NFL Sunday Ticket &copy; 2026 Google LLC';
describe('content quality regressions', () => {
  it('rejects LinkedIn signup bodies but preserves profiles with login chrome', () => {
    const url = 'https://www.linkedin.com/in/example/';
    const signup = 'Sign Up | LinkedIn 750 million+ members | Manage your professional identity. Build and engage with your professional network. Access knowledge, insights and opportunities. ' + 'User Agreement Privacy Policy '.repeat(20);
    expect(inspectSourceText(url, signup)).toMatchObject({ usable: false, reason: 'login_page' });
    expect(isPlaceholderMetadata('Sign Up | LinkedIn', url)).toBe(true);
    const real = 'Scott Jenson | LinkedIn Product strategist and designer, previously at Google. Experience: product design, user research, interaction design. Sign up to view full profile.';
    expect(inspectSourceText(url, real).usable).toBe(true);
    expect(inspectSourceText('https://example.org/review', signup).usable).toBe(true);
  });
  it('rejects the YouTube footer-only page returned for a saved video', () => {
    expect(inspectSourceText(youtube, youtubeFooter)).toMatchObject({ usable: false, reason: 'navigation_only', text: '' });
    expect(assessEnrichment({ type: 'link', url: youtube, title: 'Useful video', page_body: youtubeFooter }, true).content_usable).toBe(false);
  });
  it('keeps genuine short YouTube captions and transcripts, including captions with footer chrome', () => {
    const caption = 'Pick ripe tomatoes, salt them, and finish with olive oil.';
    expect(inspectSourceText(youtube, caption, 'caption')).toMatchObject({ usable: true, text: caption });
    expect(inspectSourceText(youtube, `${caption}\n${youtubeFooter}`)).toMatchObject({ usable: true });
    expect(inspectSourceText(youtube, 'Turn left at the red door.', 'transcript')).toMatchObject({ usable: true });
    expect(inspectSourceText('https://example.com/article', youtubeFooter)).toMatchObject({ usable: true });
  });
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
    for (const s of ['Instagram', 'TikTok - Make Your Day', 'Video by JMM Collector on TikTok', 'TikTok by Katina Bajaj (@katina.bajaj)']) expect(isPlaceholderMetadata(s)).toBe(true);
    expect(isPlaceholderMetadata('How Instagram changed photography')).toBe(false);
  });
  it('generalizes evidence requirements without demanding OCR from a photo or a summary from a note', () => {
    expect(assessEnrichment({ type: 'image', title: 'A red bicycle', description: 'A red bicycle leaning against a brick wall.' }, true).status).toBe('ready');
    expect(assessEnrichment({ type: 'text', title: 'Buy milk', content: 'Buy milk' }, true).status).toBe('ready');
    expect(assessEnrichment({ type: 'audio', title: 'Meeting', description: 'Discussion' }, true).status).toBe('partial');
    expect(assessEnrichment({ type: 'document', mime_type: 'application/octet-stream' }, false).status).toBe('unsupported');
  });
  it('indexes source-bound product facts and omits stale facts after a URL edit', () => {
    const url='https://example.org/jacket';
    const facts={version:1,beta:true,kind:'product',product:{brand:'Acme',sku:'NAV-123',material:'Merino wool'},evidence:{source_url:url,observed_at:'2026-10-10T00:00:00Z',method:'json-ld',extraction_version:'object-facts-v1',schema_type:'Product'}};
    const item={type:'link',url,attributes:{object_facts:facts}};
    expect(enrichmentSearchText(item)).toContain('NAV-123');
    expect(enrichmentSearchText({...item,url:'https://example.org/other'})).not.toContain('NAV-123');
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
