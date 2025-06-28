
import React from 'react';
import ContentItem from './ContentItem';
import ContentItemSkeleton from './ContentItemSkeleton';
import WhatsAppInfo from './WhatsAppInfo';

interface ContentGridProps {
  items: any[];
  onDeleteItem: (id: string) => void;
  onEditItem: (item: any) => void;
  onChatWithItem: (item: any) => void;
  tagFilters: string[];
  searchQuery?: string;
}

const ContentGrid = ({ items, onDeleteItem, onEditItem, onChatWithItem, tagFilters, searchQuery = '' }: ContentGridProps) => {
  // Filter items based on tag filters and search query
  const filteredItems = items.filter(item => {
    // Tag filter
    if (tagFilters && tagFilters.length > 0) {
      const itemTags = item.tags || [];
      const matchesTag = tagFilters.some(filter => 
        itemTags.some((tag: any) => 
          typeof tag === 'string' ? tag === filter : tag.name === filter
        )
      );
      if (!matchesTag) return false;
    }
    
    // Search filter
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase();
      const title = (item.title || '').toLowerCase();
      const content = (item.content || '').toLowerCase();
      const description = (item.description || '').toLowerCase();
      const url = (item.url || '').toLowerCase();
      
      return title.includes(query) || 
             content.includes(query) || 
             description.includes(query) ||
             url.includes(query);
    }
    
    return true;
  });

  // Separate optimistic and real items
  const optimisticItems = filteredItems.filter(item => item.isOptimistic);
  const realItems = filteredItems.filter(item => !item.isOptimistic);

  // Show WhatsApp info if no real items exist and no search is active
  if (realItems.length === 0 && optimisticItems.length === 0 && !searchQuery.trim()) {
    return (
      <div className="space-y-8">
        <div className="text-center py-12">
          <h2 className="text-2xl font-semibold text-gray-900 mb-2">Start building your knowledge base</h2>
          <p className="text-gray-600 mb-8">Capture ideas, notes, and insights to make them searchable and discoverable.</p>
        </div>
        <WhatsAppInfo />
      </div>
    );
  }

  // Show no results message for search
  if (realItems.length === 0 && optimisticItems.length === 0 && searchQuery.trim()) {
    return (
      <div className="text-center py-12">
        <h2 className="text-xl font-semibold text-gray-900 mb-2">No results found</h2>
        <p className="text-gray-600">Try adjusting your search terms or filters.</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {/* Show optimistic items first */}
      {optimisticItems.map((item) => (
        <ContentItemSkeleton key={item.id} />
      ))}
      
      {/* Show real items */}
      {realItems.map((item) => (
        <ContentItem
          key={item.id}
          item={item}
          tags={[]}
          imageErrors={new Set()}
          expandedContent={new Set()}
          onImageError={() => {}}
          onToggleExpansion={() => {}}
          onDeleteItem={onDeleteItem}
          onEditItem={onEditItem}
          onChatWithItem={onChatWithItem}
          onTagsUpdated={() => {}}
        />
      ))}
    </div>
  );
};

export default ContentGrid;
