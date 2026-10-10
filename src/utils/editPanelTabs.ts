import type { ItemAttributes } from '@/types/itemAttributes';

export type ContentTabKey = 'summary' | 'original' | 'notes' | 'transcript';

export interface ContentTab {
  key: ContentTabKey;
  label: string;
}

export interface ContentTabsConfig {
  title: string;
  defaultTab: ContentTabKey;
  tabs: ContentTab[];
}

/** What the tabs are decided from: the kind, and for a link its flavor and transcript state */
export interface TabsSubject {
  type?: string | null;
  attributes?: ItemAttributes | null;
}

const SUMMARY: ContentTab = { key: 'summary', label: 'Summary' };
const ORIGINAL: ContentTab = { key: 'original', label: 'Original Content' };
const TRANSCRIPT: ContentTab = { key: 'transcript', label: 'Transcript' };

/** A link to a video (YouTube, TikTok, a reel…): its content is its transcript (spec 2026-09-05) */
export const isVideoLink = (subject?: TabsSubject | null): boolean =>
  subject?.type === 'link' && subject.attributes?.link?.flavor === 'video';

/** `page_body` holds a captured transcript: the server's `enrichment.evidence.transcript` flag */
export const hasCapturedTranscript = (attributes?: ItemAttributes | null): boolean =>
  attributes?.enrichment?.evidence?.transcript === true;

// Notes are an independent section. These are the source tabs below it;
// notes-only types retain a sentinel default for existing callers.
export const getContentTabsConfig = (subject?: string | TabsSubject | null): ContentTabsConfig => {
  const type = typeof subject === 'string' ? subject : subject?.type ?? undefined;
  const attributes = subject && typeof subject === 'object' ? subject.attributes : undefined;
  switch (type) {
    case 'link': {
      if (attributes?.link?.flavor === 'video') {
        // Until a transcript is captured the page text stays readable under Original Content;
        // once there is one it IS the original content, so the tab goes (Will, 2026-10-10)
        const transcribed = hasCapturedTranscript(attributes);
        return {
          title: 'Source',
          defaultTab: 'summary',
          tabs: transcribed ? [SUMMARY, TRANSCRIPT] : [SUMMARY, ORIGINAL, TRANSCRIPT],
        };
      }
      return { title: 'Source', defaultTab: 'summary', tabs: [SUMMARY, ORIGINAL] };
    }
    case 'document':
    case 'pdf':
      return { title: 'Source', defaultTab: 'summary', tabs: [SUMMARY, ORIGINAL] };
    case 'audio':
    case 'video':
      return { title: 'Transcript', defaultTab: 'transcript', tabs: [TRANSCRIPT] };
    default:
      return { title: 'Notes', defaultTab: 'notes', tabs: [{ key: 'notes', label: 'Notes' }] };
  }
};

export const needsSourceContent = (type?: string): boolean =>
  getContentTabsConfig(type).tabs.some((tab) => tab.key !== 'notes');
