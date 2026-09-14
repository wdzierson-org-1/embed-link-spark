import { describe, it, expect } from 'vitest';
import { getContentTabsConfig, needsSourceContent } from './editPanelTabs';

describe('getContentTabsConfig', () => {
  it('gives links Summary | Original Content with Summary first', () => {
    const config = getContentTabsConfig('link');
    expect(config.title).toBe('Source');
    expect(config.tabs.map((t) => t.key)).toEqual(['summary', 'original']);
    expect(config.defaultTab).toBe('summary');
  });

  it('treats documents (and legacy pdf type) like links', () => {
    for (const type of ['document', 'pdf']) {
      const config = getContentTabsConfig(type);
      expect(config.tabs.map((t) => t.key)).toEqual(['summary', 'original']);
    }
  });

  it('gives audio and video Transcript below the independent Notes section', () => {
    for (const type of ['audio', 'video']) {
      const config = getContentTabsConfig(type);
      expect(config.title).toBe('Transcript');
      expect(config.tabs.map((t) => t.key)).toEqual(['transcript']);
      expect(config.defaultTab).toBe('transcript');
    }
  });

  it('gives images, text, collections, and unknown types Notes only', () => {
    for (const type of ['image', 'text', 'collection', undefined, 'anything-else']) {
      const config = getContentTabsConfig(type);
      expect(config.title).toBe('Notes');
      expect(config.tabs.map((t) => t.key)).toEqual(['notes']);
      expect(config.defaultTab).toBe('notes');
    }
  });
});

describe('needsSourceContent', () => {
  it('is true only for types with non-notes tabs', () => {
    expect(needsSourceContent('link')).toBe(true);
    expect(needsSourceContent('document')).toBe(true);
    expect(needsSourceContent('audio')).toBe(true);
    expect(needsSourceContent('video')).toBe(true);
    expect(needsSourceContent('image')).toBe(false);
    expect(needsSourceContent('text')).toBe(false);
    expect(needsSourceContent(undefined)).toBe(false);
  });
});
