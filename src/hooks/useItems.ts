
import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

const ITEM_LIST_COLUMNS = [
  'id',
  'type',
  'title',
  'content',
  'url',
  'file_path',
  'description',
  'created_at',
  'mime_type',
  'is_public',
  'supplemental_note',
].join(',');

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
