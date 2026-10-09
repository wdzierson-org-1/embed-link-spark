
import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

// The columns a library card needs. The admin dashboard's member view loads
// the same list (supabase/functions/_shared/adminDashboard.ts, parity-tested)
// so its recreation of the grid never drifts from the real one.
export const ITEM_LIST_COLUMN_NAMES = [
  'id',
  'type',
  'title',
  'content',
  'url',
  'file_path',
  'description',
  'summary',
  'created_at',
  'mime_type',
  'file_size',
  'is_public',
  'supplemental_note',
  'attributes',
  'remind_at',
  'reminder_cleared_at',
  'pinned_at',
];
const ITEM_LIST_COLUMNS = ITEM_LIST_COLUMN_NAMES.join(',');

/** More changed rows than this in one burst, and the whole library is refetched instead */
const MAX_ROW_REFRESH = 150;

interface ListRow {
  id: string;
  created_at?: string;
}

/**
 * Fresh rows replace their old versions (or join the list), and the list keeps its order,
 * newest first. Pure, so the realtime merge can be tested without a socket.
 */
export const mergeItemRows = <T extends ListRow>(current: T[], fresh: T[]): T[] => {
  if (!fresh.length) return current;
  const byId = new Map(fresh.map((row) => [row.id, row]));
  const merged = current.map((row) => byId.get(row.id) ?? row);
  const seen = new Set(current.map((row) => row.id));
  for (const row of fresh) if (!seen.has(row.id)) merged.push(row);
  return merged.sort((a, b) => (b.created_at ?? '').localeCompare(a.created_at ?? ''));
};

export const useItems = () => {
  const { user } = useAuth();
  const [items, setItems] = useState([]);
  const [optimisticItems, setOptimisticItems] = useState([]);
  const [isInitialLoadInProgress, setIsInitialLoadInProgress] = useState(false);
  const initialLoadUserIdRef = useRef<string | null>(null);
  const { toast } = useToast();

  const fetchItems = useCallback(async () => {
    // Security check: Only proceed if we have a valid authenticated user
    if (!user?.id) {
      console.warn('fetchItems called without valid user ID');
      setItems([]); // Clear items if no user
      return;
    }
    
    try {
      console.log('Fetching items for user:', user.id);
      
      // CRITICAL FIX: Explicitly filter by user_id to prevent cross-user data access
      const { data, error } = await supabase
        .from('items')
        .select(ITEM_LIST_COLUMNS)
        .eq('user_id', user.id)  // This prevents users from seeing other users' items
        .order('created_at', { ascending: false });

      if (error) {
        console.error('Error fetching items:', error);
        toast({
          title: "Error",
          description: "Failed to fetch items",
          variant: "destructive",
        });
      } else {
        console.log(`Fetched ${data?.length || 0} items for user ${user.id}`);
        setItems(data || []);
      }
    } catch (error) {
      console.error('Exception while fetching items:', error);
      toast({
        title: "Error",
        description: "Failed to fetch items",
        variant: "destructive",
      });
    }
  }, [user, toast]);

  const addOptimisticItem = useCallback((tempItem: any) => {
    console.log('Adding optimistic item:', tempItem);
    setOptimisticItems(prev => [tempItem, ...prev]);
  }, []);

  const removeOptimisticItem = useCallback((tempId: string) => {
    console.log('Removing optimistic item:', tempId);
    setOptimisticItems(prev => prev.filter(item => item.id !== tempId));
  }, []);

  const clearSkeletonItems = useCallback(() => {
    console.log('Clearing all skeleton items');
    setOptimisticItems(prev => prev.filter(item => !item.showSkeleton));
  }, []);

  const allItems = useMemo(() => {
    return [...optimisticItems, ...items];
  }, [optimisticItems, items]);

  useEffect(() => {
    if (!user?.id) {
      initialLoadUserIdRef.current = null;
      setIsInitialLoadInProgress(false);
      return;
    }

    if (initialLoadUserIdRef.current === user.id) {
      return;
    }

    initialLoadUserIdRef.current = user.id;
    setIsInitialLoadInProgress(true);

    void fetchItems().finally(() => {
      setIsInitialLoadInProgress(false);
    });
  }, [user?.id, fetchItems]);

  // Realtime: when this user's items change server-side (async enrichment like
  // PDF extraction, image analysis, link scraping), re-read just the rows that
  // changed and merge them in. It used to refetch the whole library on every
  // event: at 841 saves that was ~535 KB per enrichment write, several times a
  // minute. A burst of events coalesces into one read; anything unexpected
  // falls back to the full refetch.
  const refetchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingRef = useRef<{ changed: Set<string>; removed: Set<string>; full: boolean }>({
    changed: new Set(),
    removed: new Set(),
    full: false,
  });
  useEffect(() => {
    if (!user?.id) return;
    const userId = user.id;

    const flush = async () => {
      const { changed, removed, full } = pendingRef.current;
      pendingRef.current = { changed: new Set(), removed: new Set(), full: false };
      if (full || changed.size > MAX_ROW_REFRESH) {
        void fetchItems();
        return;
      }
      if (removed.size) {
        setItems((prev) => prev.filter((item) => !removed.has(item.id)));
      }
      if (changed.size) {
        const { data, error } = await supabase
          .from('items')
          .select(ITEM_LIST_COLUMNS)
          .eq('user_id', userId)
          .in('id', [...changed]);
        if (error) {
          console.error('Error refreshing changed items:', error);
          void fetchItems();
          return;
        }
        setItems((prev) => mergeItemRows(prev, data ?? []));
      }
    };

    const channel = supabase
      .channel(`items-changes-${userId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'items',
          filter: `user_id=eq.${userId}`,
        },
        (payload: { eventType?: string; new?: { id?: string } | null; old?: { id?: string } | null }) => {
          const pending = pendingRef.current;
          if (payload.eventType === 'DELETE') {
            if (payload.old?.id) pending.removed.add(payload.old.id);
            else pending.full = true;
          } else if (payload.new?.id) {
            pending.changed.add(payload.new.id);
          } else {
            pending.full = true;
          }
          if (refetchTimerRef.current) clearTimeout(refetchTimerRef.current);
          refetchTimerRef.current = setTimeout(() => {
            void flush();
          }, 400);
        }
      )
      .subscribe();

    return () => {
      if (refetchTimerRef.current) clearTimeout(refetchTimerRef.current);
      supabase.removeChannel(channel);
    };
  }, [user?.id, fetchItems]);

  return {
    items: allItems,
    fetchItems,
    setItems,
    addOptimisticItem,
    removeOptimisticItem,
    clearSkeletonItems,
    isInitialLoadInProgress,
  };
};
