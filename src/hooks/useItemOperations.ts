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

  const showToast = (toastData: { title: string; description: string; variant?: 'destructive' }) => {
    toast(toastData);
  };

  const handleAddContent = async (type: string, data: any) => {
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
  };

  const handleSaveItem = async (
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
  };

  const handleDeleteItem = async (id: string) => {
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
  };

  return {
    handleAddContent,
    handleSaveItem,
    handleDeleteItem
  };
};
