
import React, { useState, useEffect, useMemo, useCallback } from 'react';
import ContentItem from './ContentItem';
import ContentItemSkeleton from './ContentItemSkeleton';
import WhatsAppInfo from './WhatsAppInfo';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import type { Attachment } from '@/components/CollectionAttachments';

interface ContentGridProps {
  items: any[];
  onDeleteItem: (id: string) => void;
  onEditItem: (item: any) => void;
  onChatWithItem: (item: any) => void;
  tagFilters: string[];
  searchQuery?: string;
  isPublicView?: boolean;
  currentUserId?: string;
  onTogglePrivacy?: (item: any) => void;
  onCommentClick?: (itemId: string) => void;
  showStickyNotes?: boolean;
}

const ContentGrid = ({ 
  items, 
  onDeleteItem, 
  onEditItem, 
  onChatWithItem, 
  tagFilters, 
  searchQuery = '',
  isPublicView = false,
  currentUserId,
  onTogglePrivacy,
  onCommentClick,
  showStickyNotes = true
}: ContentGridProps) => {
  const [itemTags, setItemTags] = useState<Record<string, string[]>>({});
  const [collectionAttachmentsByItem, setCollectionAttachmentsByItem] = useState<Record<string, Attachment[]>>({});
  const [imageErrors, setImageErrors] = useState<Set<string>>(new Set());
  const [expandedContent, setExpandedContent] = useState<Set<string>>(new Set());
  const { user } = useAuth();

  const realItems = useMemo(() => items.filter(item => !item.isOptimistic), [items]);
  const realItemIds = useMemo(() => realItems.map(item => item.id), [realItems]);
  const realItemIdsKey = useMemo(() => realItemIds.join(','), [realItemIds]);
  const collectionItemIds = useMemo(
    () => realItems.filter(item => item.type === 'collection').map(item => item.id),
    [realItems]
  );
  const collectionItemIdsKey = useMemo(() => collectionItemIds.join(','), [collectionItemIds]);

  // Fetch tags for all items
  const fetchItemTags = useCallback(async (itemIds: string[]) => {
    if (!user || itemIds.length === 0) {
      setItemTags({});
      return;
    }

    try {
      const { data, error } = await supabase
        .from('item_tags')
        .select(`
          item_id,
          tags!inner(name)
        `)
        .in('item_id', itemIds);

      if (error) {
        console.error('Error fetching item tags:', error);
        return;
      }

      // Group tags by item_id
      const tagsByItem: Record<string, string[]> = {};
      data?.forEach(row => {
        const itemId = row.item_id;
        const tagName = row.tags.name;
        if (!tagsByItem[itemId]) {
          tagsByItem[itemId] = [];
        }
        tagsByItem[itemId].push(tagName);
      });

      setItemTags(tagsByItem);
    } catch (error) {
      console.error('Exception fetching item tags:', error);
    }
  }, [user]);

  useEffect(() => {
    fetchItemTags(realItemIds);
  }, [fetchItemTags, realItemIds, realItemIdsKey]);

  const fetchCollectionAttachments = useCallback(async (collectionIds: string[]) => {
    if (!collectionIds.length) {
      setCollectionAttachmentsByItem({});
      return;
    }

    try {
      const { data, error } = await supabase
        .from('item_attachments')
        .select('*')
        .in('item_id', collectionIds)
        .order('created_at', { ascending: true });

      if (error) {
        console.error('Error fetching collection attachments:', error);
        return;
      }

      const grouped: Record<string, Attachment[]> = {};
      data?.forEach((attachment: Attachment & { item_id?: string }) => {
        const parentItemId = attachment.item_id;
        if (!parentItemId) return;

        if (!grouped[parentItemId]) {
          grouped[parentItemId] = [];
        }
        grouped[parentItemId].push(attachment);
      });

      setCollectionAttachmentsByItem(grouped);
    } catch (error) {
      console.error('Exception fetching collection attachments:', error);
    }
  }, []);

  useEffect(() => {
    fetchCollectionAttachments(collectionItemIds);
  }, [collectionItemIds, collectionItemIdsKey, fetchCollectionAttachments]);

  const handleImageError = (itemId: string) => {
    setImageErrors(prev => new Set([...prev, itemId]));
  };

  const handleToggleExpansion = (itemId: string) => {
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

  const handleTagsUpdated = () => {
    // Refetch tags when they're updated
    fetchItemTags(realItemIds);
  };

  // Filter items based on tag filters and search query
  const filteredItems = items.filter(item => {
    // Tag filter
    if (tagFilters && tagFilters.length > 0) {
      const currentItemTags = itemTags[item.id] || [];
      const matchesTag = tagFilters.some(filter => 
        currentItemTags.includes(filter)
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
  const visibleRealItems = filteredItems.filter(item => !item.isOptimistic);

  // Show WhatsApp info if no real items exist and no search is active
  if (visibleRealItems.length === 0 && optimisticItems.length === 0 && !searchQuery.trim()) {
    return (
      <div className="space-y-8 relative z-10">
        <div className="text-center py-12 relative z-10">
          <h2 className="text-2xl font-editorial text-gray-900 mb-2">Start building your knowledge base</h2>
          <p className="text-gray-600 mb-8">Capture ideas, notes, and insights to make them searchable and discoverable.</p>
        </div>
        <WhatsAppInfo />
      </div>
    );
  }

  // Show no results message for search
  if (visibleRealItems.length === 0 && optimisticItems.length === 0 && searchQuery.trim()) {
    return (
      <div className="text-center py-12">
        <h2 className="text-xl font-editorial text-gray-900 mb-2">No results found</h2>
        <p className="text-gray-600">Try adjusting your search terms or filters.</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {/* Show optimistic items first */}
        {optimisticItems.map((item) => (
          <ContentItemSkeleton 
            key={item.id} 
            showProgress={item.showProgress}
            title={item.skeletonProps?.title}
            description={item.skeletonProps?.description}
            type={item.skeletonProps?.type}
            fileSize={item.skeletonProps?.fileSize}
          />
        ))}
      
      {/* Show real items */}
      {visibleRealItems.map((item) => (
        <ContentItem
          key={item.id}
          item={{
            ...item,
            supplemental_note: showStickyNotes ? item.supplemental_note : null
          }}
          tags={itemTags[item.id] || []}
          imageErrors={imageErrors}
          expandedContent={expandedContent}
          onImageError={handleImageError}
          onToggleExpansion={handleToggleExpansion}
          onDeleteItem={onDeleteItem}
          onEditItem={onEditItem}
          onChatWithItem={onChatWithItem}
          onTagsUpdated={handleTagsUpdated}
          isPublicView={isPublicView}
          currentUserId={currentUserId}
          onTogglePrivacy={onTogglePrivacy}
          onCommentClick={onCommentClick}
          collectionAttachments={collectionAttachmentsByItem[item.id]}
        />
      ))}
    </div>
  );
};

export default ContentGrid;
