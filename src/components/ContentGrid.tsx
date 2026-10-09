
import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import ContentItem from './ContentItem';
import LibraryLayout from '@/components/LibraryLayout';
import ContentItemSkeleton from './ContentItemSkeleton';
import { CropMarks } from '@/components/machine/Machine';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { itemMatchesSearchQuery } from '@/utils/itemSearch';
import { landedPieces, REVEAL_TTL_MS, type AssemblyPiece } from '@/utils/itemAssembly';
import type { Attachment } from '@/components/CollectionAttachments';
import { orderDueFirst } from '@/utils/reminders';
import { useNow } from '@/hooks/useNow';

type RevealMap = Record<string, Partial<Record<AssemblyPiece, number>>>;

export type ContentTypeFilter = 'all' | 'link' | 'note' | 'doc' | 'media';

/** PostgREST's page: the tag query reads in pages of this many rows */
const TAG_PAGE = 1000;

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
  onTogglePin?: (item: any) => void;
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
  onTogglePin,
  onCommentClick,
  showStickyNotes = true,
  typeFilter = 'all',
  compact = false
}: ContentGridProps) => {
  const now = useNow();
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

  // Fetch the tags on every one of the person's items. Not filtered by the ids on screen: the
  // ids went in the URL, and at a few hundred saves the URL passed the gateway's limit and
  // every fetch came back 400. Row-level security already keeps this to their own items, so
  // the query needs no filter; it's read in pages, since PostgREST answers 1,000 rows at most.
  const fetchItemTags = useCallback(async (itemIds: string[]) => {
    if (!user || itemIds.length === 0) {
      setItemTags({});
      return;
    }

    try {
      const tagsByItem: Record<string, string[]> = {};
      for (let from = 0; ; from += TAG_PAGE) {
        const { data, error } = await supabase
          .from('item_tags')
          .select('item_id, tags!inner(name)')
          .range(from, from + TAG_PAGE - 1);

        if (error) {
          console.error('Error fetching item tags:', error);
          return;
        }
        for (const row of data ?? []) {
          (tagsByItem[row.item_id] ??= []).push(row.tags.name);
        }
        if (!data || data.length < TAG_PAGE) break;
      }

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
  let visibleRealItems = filteredItems.filter(item => !item.isOptimistic);
  if (searchRank) {
    // Relevance order while a server search is active (grid is otherwise chronological)
    visibleRealItems.sort((a, b) => searchRank.get(a.id)! - searchRank.get(b.id)!);
  } else if (!isPublicView) {
    // Due reminders surface above the chronological list
    visibleRealItems = orderDueFirst(visibleRealItems, now);
  }

  // Empty state: no real items and no search active
  // Empty states are small stages (DESIGN-v2): the dot grid in crop marks, and an invitation
  if (visibleRealItems.length === 0 && optimisticItems.length === 0 && !searchQuery.trim() && !focusActive) {
    return (
      <div className="v2-dots relative z-10 mx-2.5 my-6 px-6 py-16 text-center">
        <CropMarks />
        <h2 className="mx-auto max-w-[16em] text-[clamp(28px,3vw,40px)] font-medium leading-[1.02] tracking-[-0.04em] text-ink">
          Save your first thing.
        </h2>
        <p className="mx-auto mt-4 max-w-[30em] bg-paper/80 text-[17px] leading-[1.45] text-muted-foreground">
          Paste a link, drop in a screenshot or a PDF, or type a note up there. Stash reads it and gathers
          the background, so you can find it again by what it's about.
        </p>
      </div>
    );
  }

  // Show no results message for search (or a focus request whose cited items aren't loaded)
  if (visibleRealItems.length === 0 && optimisticItems.length === 0 && (searchQuery.trim() || focusActive)) {
    return (
      <div className="v2-dots relative mx-2.5 my-6 px-6 py-14 text-center">
        <CropMarks />
        <p className="font-pixel text-pixel text-muted-foreground">
          {focusActive ? '0 cards to show' : `0 saves match “${searchQuery.trim()}”`}
        </p>
        <h2 className="mt-3 text-section-title font-medium text-ink">
          {focusActive ? "Those cards aren't in your stash anymore." : 'Nothing matches that.'}
        </h2>
        <p className="mt-2 text-[15px] text-muted-foreground">
          {focusActive ? 'Clear the focus to see everything again.' : 'Try different words: search reads what your saves are about, not just their titles.'}
        </p>
      </div>
    );
  }

  return (
    <LibraryLayout compact={compact}>
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
          onTogglePin={onTogglePin}
          onCommentClick={onCommentClick}
          collectionAttachments={collectionAttachmentsByItem[item.id]}
          assemblyReveals={assemblyReveals[item.id]}
        />
      ))}
    </LibraryLayout>
  );
};

export default ContentGrid;
