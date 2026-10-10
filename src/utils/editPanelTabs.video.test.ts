import { getContentTabsConfig, isVideoLink } from './editPanelTabs';

describe('a video link’s tabs (spec 2026-09-05; Will, 2026-10-10)', () => {
  const youtube = { type: 'link', attributes: { link: { flavor: 'video' as const } } };

  it('adds Transcript beside Summary and Original Content until a transcript is captured', () => {
    const config = getContentTabsConfig(youtube);
    expect(config.tabs.map((t) => t.key)).toEqual(['summary', 'original', 'transcript']);
    expect(config.defaultTab).toBe('summary');
    expect(isVideoLink(youtube)).toBe(true);
  });

  it('once the transcript is the content, Original Content goes', () => {
    const transcribed = { type: 'link', attributes: { link: { flavor: 'video' as const, transcript: { source: 'youtube-captions' } } } };
    expect(getContentTabsConfig(transcribed).tabs.map((t) => t.key)).toEqual(['summary', 'transcript']);
  });

  it('leaves other links, and a bare type string, as they were', () => {
    expect(getContentTabsConfig({ type: 'link', attributes: { link: { flavor: 'article' as const } } }).tabs.map((t) => t.key)).toEqual(['summary', 'original']);
    expect(getContentTabsConfig('link').tabs.map((t) => t.key)).toEqual(['summary', 'original']);
    expect(getContentTabsConfig({ type: 'audio' }).tabs.map((t) => t.key)).toEqual(['transcript']);
    expect(isVideoLink({ type: 'video' })).toBe(false);
  });
});
