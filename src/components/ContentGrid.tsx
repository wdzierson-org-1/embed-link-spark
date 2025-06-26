import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import ContentItem from '@/components/ContentItem';
import ContentItemSkeleton from '@/components/ContentItemSkeleton';

interface ContentItemData {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';
  title?: string;
  content?: string;
  url?: string;
  file_path?: string;
  description?: string;
  tags?: string[];
  created_at: string;
  mime_type?: string;
  isOptimistic?: boolean;
}

interface ContentGridProps {
  items: ContentItemData[];
  onDeleteItem: (id: string) => void;
  onEditItem: (item: ContentItemData) => void;
  onChatWithItem?: (item: ContentItemData) => void;
  tagFilters?: string[];
}

const ContentGrid = ({ items, onDeleteItem, onEditItem, onChatWithItem, tagFilters = [] }: ContentGridProps) => {
  const [imageErrors, setImageErrors] = useState<Set<string>>(new Set());
  const [expandedContent, setExpandedContent] = useState<Set<string>>(new Set());
  const [itemTags, setItemTags] = useState<Record<string, string[]>>({});

  // Fetch tags for all items
  const fetchItemTags = async () => {
    if (items.length === 0) return;
    
    try {
      const { data, error } = await supabase
        .from('item_tags')
        .select(`
          item_id,
          tags (name)
        `)
        .in('item_id', items.map(item => item.id));

      if (error) {
        console.error('Error fetching item tags:', error);
        return;
      }

      const tagsMap: Record<string, string[]> = {};
      data?.forEach((itemTag) => {
        if (!tagsMap[itemTag.item_id]) {
          tagsMap[itemTag.item_id] = [];
        }
        if (itemTag.tags) {
          tagsMap[itemTag.item_id].push(itemTag.tags.name);
        }
      });

      setItemTags(tagsMap);
    } catch (error) {
      console.error('Exception while fetching item tags:', error);
    }
  };

  useEffect(() => {
    fetchItemTags();
  }, [items]);

  const handleImageError = (itemId: string) => {
    setImageErrors(prev => new Set([...prev, itemId]));
  };

  const toggleContentExpansion = (itemId: string) => {
    setExpandedContent(prev => {
      const newSet = new Set(prev);
      if (newSet.has(itemId)) {
        newSet.delete(itemId);
      } else {
        newSet.add(itemId);
      }
      return newSet;
    });
  };

  // Separate optimistic and real items
  const optimisticItems = items.filter(item => item.isOptimistic);
  const realItems = items.filter(item => !item.isOptimistic);

  // Filter real items based on selected tags
  const filteredItems = tagFilters.length === 0 
    ? realItems 
    : realItems.filter(item => {
        const itemTagsArray = itemTags[item.id] || [];
        // Check if the item has ALL selected tags (combinatorial AND logic)
        return tagFilters.every(filterTag => 
          itemTagsArray.some(itemTag => itemTag.toLowerCase() === filterTag.toLowerCase())
        );
      });

  // Combine optimistic items (always shown) with filtered real items
  const allItemsToShow = [...optimisticItems, ...filteredItems];

  if (allItemsToShow.length === 0 && tagFilters.length > 0) {
    return (
      <div className="text-center py-12">
        <p className="text-muted-foreground">No items found with the selected tag filters.</p>
      </div>
    );
  }

  if (allItemsToShow.length === 0) {
    return (
      <div className="text-center py-12">
        <p className="text-muted-foreground">No content yet. Start adding items to your stash!</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {allItemsToShow.map((item) => {
        // Render skeleton for optimistic items
        if (item.isOptimistic) {
          return <ContentItemSkeleton key={item.id} />;
        }

        const tags = itemTags[item.id] || [];

        return (
          <ContentItem
            key={item.id}
            item={item}
            tags={tags}
            imageErrors={imageErrors}
            expandedContent={expandedContent}
            onImageError={handleImageError}
            onToggleExpansion={toggleContentExpansion}
            onDeleteItem={onDeleteItem}
            onEditItem={onEditItem}
            onChatWithItem={onChatWithItem}
            onTagsUpdated={fetchItemTags}
          />
        );
      })}
    </div>
  );
};

export default ContentGrid;
