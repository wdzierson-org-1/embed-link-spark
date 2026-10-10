
import { useCallback } from 'react';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';
import { validateUuid } from '@/utils/tempIdGenerator';
import { saveItem, deleteItem } from '@/utils/itemOperations';
import { createSkeletonItem } from '@/utils/optimisticItemHandler';
import { captureContent, type CaptureInput, type CaptureKind } from '@/utils/captureClient';

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
      // A skeleton holds the card's place while the platform saves
      const skeletonItem = createSkeletonItem(type, { title: data.title, file: data.file }, user.id);
      if (addOptimisticItem) {
        addOptimisticItem(skeletonItem);
      }

      // The platform (add-note / add-url / add-file) saves and enriches — the same pipeline
      // every client gets. The card prints in from the row once the endpoint answers; realtime
      // then delivers each upgrade as enrichment lands.
      await captureContent(type as CaptureKind, data as CaptureInput, user.id);
      if (clearSkeletonItems) {
        clearSkeletonItems();
      }
      await fetchItems();

    } catch (error: any) {
      console.error('Error in handleAddContent:', error);

      // Clear skeleton items on error
      if (clearSkeletonItems) {
        clearSkeletonItems();
      }

      // Say what went wrong: a bare "failed" hid the cause from the person and from us
      let errorMessage = error?.message ? `Failed to add content: ${error.message}` : 'Failed to add content';
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
  }, [user, session, fetchItems, addOptimisticItem, clearSkeletonItems, toast]);

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
