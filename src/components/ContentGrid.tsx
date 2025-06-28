
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
}

const ContentGrid = ({ items, onDeleteItem, onEditItem, onChatWithItem, tagFilters }: ContentGridProps) => {
  // Filter items based on tag filters
  const filteredItems = items.filter(item => {
    if (!tagFilters || tagFilters.length === 0) return true;
    
    const itemTags = item.tags || [];
    return tagFilters.some(filter => 
      itemTags.some((tag: any) => 
        typeof tag === 'string' ? tag === filter : tag.name === filter
      )
    );
  });

  // Separate optimistic and real items
  const optimisticItems = filteredItems.filter(item => item.isOptimistic);
  const realItems = filteredItems.filter(item => !item.isOptimistic);

  // Show WhatsApp info if no real items exist
  if (realItems.length === 0 && optimisticItems.length === 0) {
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

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      {/* Show optimistic items first */}
      {optimisticItems.map((item) => (
        <ContentItemSkeleton
          key={item.id}
          title={item.title}
          type={item.type}
        />
      ))}
      
      {/* Show real items */}
      {realItems.map((item) => (
        <ContentItem
          key={item.id}
          item={item}
          onDelete={onDeleteItem}
          onEdit={onEditItem}
          onChatWith={onChatWithItem}
        />
      ))}
    </div>
  );
};

export default ContentGrid;
