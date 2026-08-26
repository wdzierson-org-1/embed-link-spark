import type { ItemAttributes } from '@/types/itemAttributes';

interface SearchableItem {
  title?: string | null;
  content?: string | null;
  description?: string | null;
  url?: string | null;
  supplemental_note?: string | null;
  attributes?: ItemAttributes | null;
}

export const itemMatchesSearchQuery = (
  item: SearchableItem,
  searchQuery: string
): boolean => {
  const query = searchQuery.trim().toLowerCase();
  if (!query) return true;

  return [
    item.title,
    item.content,
    item.description,
    item.url,
    item.supplemental_note,
    // Original filename (image/audio/video) — titles are AI-derived, but
    // "IMG_2041" or "budget-v3.png" must still find the item
    item.attributes?.media?.file_name,
  ].some(field => (field || '').toLowerCase().includes(query));
};
