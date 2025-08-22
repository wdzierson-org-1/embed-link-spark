
import { useCallback } from 'react';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';
import { validateUuid } from '@/utils/tempIdGenerator';
import { saveItem, deleteItem } from '@/utils/itemOperations';
import { createSkeletonItem } from '@/utils/optimisticItemHandler';
import { processAndInsertContent } from '@/utils/contentProcessor';

export const useItemOperations = (
  fetchItems: () => Promise<void>,
  addOptimisticItem?: (item: any) => void,
  removeOptimisticItem?: (tempId: string) => void,
  clearSkeletonItems?: () => void
) => {
  const { user, session } = useAuth();
  const { toast } = useToast();

  const showToast = useCallback((toastData: { title: string; description: string; variant?: 'destructive' }) => {
    toast(toastData);
  }, [toast]);

  const handleAddContent = useCallback(async (type: string, data: any) => {
    if (!user || !session) {
      console.error('No user or session found for content creation');
      toast({
        title: "Authentication Error",
        description: "Please log in to add content",
        variant: "destructive",
      });
      return;
    }

    // Handle skeleton/optimistic item creation
    if (data.isOptimistic && data.showSkeleton) {
      const skeletonItem = createSkeletonItem(type, data, user.id);
      
      if (addOptimisticItem) {
        addOptimisticItem(skeletonItem);
      }
      return; // Don't process further for skeleton items
    }

    try {
      // Create and add optimistic item for immediate feedback
      const skeletonData = {
        title: data.title || (type === 'collection' ? 'Collection' : 'New Item'),
        file: data.file
      };
      const skeletonItem = createSkeletonItem(type, skeletonData, user.id);
      
      if (addOptimisticItem) {
        addOptimisticItem(skeletonItem);
      }

      await processAndInsertContent(
        type, 
        data, 
        user.id, 
        !!session, 
        fetchItems, 
        showToast,
        clearSkeletonItems
      );

      toast({
        title: "Success",
        description: "Content added to your stash!",
      });

    } catch (error: any) {
      console.error('Error in handleAddContent:', error);
      
      // Clear skeleton items on error
      if (clearSkeletonItems) {
        clearSkeletonItems();
      }
      
      // Provide more specific error messages
      let errorMessage = "Failed to add content";
      if (error.message?.includes('Session expired')) {
        errorMessage = "Your session has expired. Please refresh and log in again.";
      } else if (error.message?.includes('RLS')) {
        errorMessage = "Permission denied. Please refresh and try again.";
      }
      
      toast({
        title: "Error",
        description: errorMessage,
        variant: "destructive",
      });
    }
  }, [user, session, fetchItems, showToast, addOptimisticItem, clearSkeletonItems, toast]);

  const handleSaveItem = useCallback(async (
    id: string, 
    updates: any, 
    options: { showSuccessToast?: boolean; refreshItems?: boolean } = {}
  ) => {
    // Validate the ID before proceeding
    if (!validateUuid(id)) {
      console.error('Invalid UUID provided for save operation:', id);
      toast({
        title: "Error",
        description: "Invalid item ID. Please refresh and try again.",
        variant: "destructive",
      });
      return;
    }
    
    await saveItem(id, updates, fetchItems, showToast, options);
  }, [fetchItems, showToast, toast]);

  const handleDeleteItem = useCallback(async (id: string) => {
    // Validate the ID before proceeding
    if (!validateUuid(id)) {
      console.error('Invalid UUID provided for delete operation:', id);
      toast({
        title: "Error",
        description: "Invalid item ID. Please refresh and try again.",
        variant: "destructive",
      });
      return;
    }
    
    await deleteItem(id, fetchItems, showToast);
  }, [fetchItems, showToast, toast]);

  return {
    handleAddContent,
    handleSaveItem,
    handleDeleteItem
  };
};
