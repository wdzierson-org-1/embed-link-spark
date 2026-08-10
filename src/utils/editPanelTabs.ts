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

// Which tabs the edit panel's content section shows, by item type:
// - link/document: AI summary + captured source + the user's notes
// - audio/video: notes + transcript (the AI summary lives in the description)
// - image/text/everything else: just the user's notes (for images, the
//   description carries the AI summary)
export const getContentTabsConfig = (type?: string): ContentTabsConfig => {
  switch (type) {
    case 'link':
    case 'document':
    case 'pdf':
      return {
        title: 'Notes & Summary',
        defaultTab: 'summary',
        tabs: [
          { key: 'summary', label: 'Summary' },
          { key: 'original', label: 'Original Content' },
          { key: 'notes', label: 'Notes' },
        ],
      };
    case 'audio':
    case 'video':
      return {
        title: 'Notes & Transcript',
        defaultTab: 'notes',
        tabs: [
          { key: 'notes', label: 'Notes' },
          { key: 'transcript', label: 'Transcript' },
        ],
      };
    default:
      return {
        title: 'Notes',
        defaultTab: 'notes',
        tabs: [{ key: 'notes', label: 'Notes' }],
      };
  }
};

// True when the section needs summary/page_body loaded from the DB (the item
// list intentionally omits page_body — it can be tens of KB per item)
export const needsSourceContent = (type?: string): boolean =>
  getContentTabsConfig(type).tabs.some((tab) => tab.key !== 'notes');
