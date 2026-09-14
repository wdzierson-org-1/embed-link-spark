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

// Notes are an independent section. These are the source tabs below it;
// notes-only types retain a sentinel default for existing callers.
export const getContentTabsConfig = (type?: string): ContentTabsConfig => {
  switch (type) {
    case 'link':
    case 'document':
    case 'pdf':
      return {
        title: 'Source',
        defaultTab: 'summary',
        tabs: [
          { key: 'summary', label: 'Summary' },
          { key: 'original', label: 'Original Content' },
        ],
      };
    case 'audio':
    case 'video':
      return {
        title: 'Transcript',
        defaultTab: 'transcript',
        tabs: [
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
