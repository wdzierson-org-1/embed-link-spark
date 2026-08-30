
import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import ContentItem from './ContentItem';
import ContentItemSkeleton from './ContentItemSkeleton';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { itemMatchesSearchQuery } from '@/utils/itemSearch';
import { landedPieces, REVEAL_TTL_MS, type AssemblyPiece } from '@/utils/itemAssembly';
import type { Attachment } from '@/components/CollectionAttachments';

type RevealMap = Record<string, Partial<Record<AssemblyPiece, number>>>;

export type ContentTypeFilter = 'all' | 'link' | 'note' | 'doc' | 'media';

const TYPE_FILTER_MAP: Record<Exclude<ContentTypeFilter, 'all'>, string[]> = {
  link: ['link'],
  note: ['text'],
  doc: ['document', 'collection'],
  media: ['image', 'video', 'audio'],
};

interface ContentGridProps {
  items: any[];
  onDeleteItem: (id: string) => void;
  onEditItem: (item: any) => void;
  onChatWithItem: (item: any) => void;
  tagFilters: string[];
  searchQuery?: string;
  // Relevance-ordered ids from the server hybrid search; null = unavailable
  // (pending/failed/short query), fall back to the client substring filter
  serverResultIds?: string[] | null;
  // Focused citation ids from a chat answer; overrides search filtering entirely
  focusItemIds?: string[] | null;
  isPublicView?: boolean;
  currentUserId?: string;
  onTogglePrivacy?: (item: any) => void;
  onCommentClick?: (itemId: string) => void;
  showStickyNotes?: boolean;
  typeFilter?: ContentTypeFilter;
  compact?: boolean;
}

const ContentGrid = ({
  items,
  onDeleteItem,
  onEditItem,
  onChatWithItem,
  tagFilters,
  searchQuery = '',
  serverResultIds = null,
  focusItemIds = null,
  isPublicView = false,
  currentUserId,
  onTogglePrivacy,
  onCommentClick,
  showStickyNotes = true,
  typeFilter = 'all',
  compact = false
}: ContentGridProps) => {
  const [itemTags, setItemTags] = useState<Record<string, string[]>>({});
  const [collectionAttachmentsByItem, setCollectionAttachmentsByItem] = useState<Record<string, Attachment[]>>({});
  const [imageErrors, setImageErrors] = useState<Set<string>>(new Set());
  const [expandedContent, setExpandedContent] = useState<Set<string>>(new Set());
  const { user } = useAuth();

  // Assembling cards: diff each realtime snapshot against the previous one so
  // enrichment pieces (title, description, summary, preview) can animate in
  // as they land. Lives here — the grid sees every refetched items array.
  const prevItemsRef = useRef<Map<string, any>>(new Map());
  const [assemblyReveals, setAssemblyReveals] = useState<RevealMap>({});

  useEffect(() => {
    const prev = prevItemsRef.current;
    const next = new Map<string, any>();
    const nowMs = Date.now();
    const fresh: RevealMap = {};

    for (const item of items) {
      if (item.isOptimistic || !item.id) continue;
      next.set(item.id, item);
      if (isPublicView) continue;
      const before = prev.get(item.id);
      if (!before) continue; // brand-new card — the entrance animation owns it
      const landed = landedPieces(before, item);
      if (landed.length > 0) {
        fresh[item.id] = Object.fromEntries(landed.map((piece) => [piece, nowMs]));
      }
    }

    prevItemsRef.current = next;
    if (Object.keys(fresh).length > 0) {
      setAssemblyReveals((current) => {
        const merged: RevealMap = {};
        // Keep only entries that are still animating or belong to this batch
        for (const [id, pieces] of Object.entries(current)) {
          const alive = Object.fromEntries(
            Object.entries(pieces).filter(([, at]) => nowMs - (at as number) < REVEAL_TTL_MS)
          );
          if (Object.keys(alive).length > 0) merged[id] = alive;
        }
        for (const [id, pieces] of Object.entries(fresh)) {
          merged[id] = { ...merged[id], ...pieces };
        }
        return merged;
      });
    }
  }, [items, isPublicView]);

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

  // Server search results (when available) beat the client substring filter:
  // they reach page_body/summary and match semantically, ranked by relevance.
  // A focus request (from a chat answer's citations) overrides both entirely.
  const rankIds = focusItemIds ?? serverResultIds;
  const searchRank = rankIds ? new Map(rankIds.map((id, index) => [id, index])) : null;
  const focusActive = Boolean(focusItemIds);

  // Filter items based on type, tag filters, and search query
  const filteredItems = items.filter(item => {
    // Type filter
    if (typeFilter !== 'all' && !TYPE_FILTER_MAP[typeFilter].includes(item.type)) {
      return false;
    }

    // Tag filter
    if (tagFilters && tagFilters.length > 0) {
      const currentItemTags = itemTags[item.id] || [];
      const matchesTag = tagFilters.some(filter =>
        currentItemTags.includes(filter)
      );
      if (!matchesTag) return false;
    }

    // Search filter — just-saved optimistic items aren't indexed server-side
    // yet, so they normally go through the client predicate; a focus request
    // overrides that exemption too, since it's not a search at all.
    if (searchRank && (focusActive || !item.isOptimistic)) {
      return searchRank.has(item.id);
    }
    return !focusActive && itemMatchesSearchQuery(item, searchQuery);
  });

  // Separate optimistic and real items
  const optimisticItems = filteredItems.filter(item => item.isOptimistic);
  const visibleRealItems = filteredItems.filter(item => !item.isOptimistic);
  if (searchRank) {
    // Relevance order while a server search is active (grid is otherwise chronological)
    visibleRealItems.sort((a, b) => searchRank.get(a.id)! - searchRank.get(b.id)!);
  }

  // Empty state: no real items and no search active
  if (visibleRealItems.length === 0 && optimisticItems.length === 0 && !searchQuery.trim() && !focusActive) {
    return (
      <div className="text-center py-12 relative z-10">
        <h2 className="text-2xl font-montreal font-semibold tracking-[-0.02em] text-gray-900 mb-2">Start building your knowledge base</h2>
        <p className="text-gray-600 mb-8">Capture ideas, notes, and insights to make them searchable and discoverable.</p>
      </div>
    );
  }

  // Show no results message for search (or a focus request whose cited items aren't loaded)
  if (visibleRealItems.length === 0 && optimisticItems.length === 0 && (searchQuery.trim() || focusActive)) {
    return (
      <div className="text-center py-12">
        <h2 className="text-xl font-montreal font-semibold tracking-[-0.02em] text-gray-900 mb-2">No results found</h2>
        <p className="text-gray-600">
          {focusActive ? "The cards cited by this answer aren't in your library anymore." : 'Try adjusting your search terms or filters.'}
        </p>
      </div>
    );
  }

  return (
    // Row-major grid: newest reads left-to-right across the columns (CSS
    // masonry columns flow top-to-bottom, which scrambles chronology). Each
    // row stretches to its tallest card; card bodies flex and footers pin to
    // the bottom, so mixed heights still align cleanly per row.
    <div className={`grid grid-cols-1 md:grid-cols-2 gap-4 ${compact ? '' : 'lg:grid-cols-3'}`}>
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
          assemblyReveals={assemblyReveals[item.id]}
        />
      ))}
    </div>
  );
};

export default ContentGrid;
