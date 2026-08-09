interface SearchableItem {
  title?: string | null;
  content?: string | null;
  description?: string | null;
  url?: string | null;
  supplemental_note?: string | null;
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
  ].some(field => (field || '').toLowerCase().includes(query));
};
