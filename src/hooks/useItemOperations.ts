import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';
import type { Database } from '@/integrations/supabase/types';
import { generateDescription, generateEmbeddings } from '@/utils/aiOperations';
import { processPdfContent } from '@/utils/pdfProcessor';
import { uploadFile } from '@/utils/fileUploader';
import { saveItem, deleteItem } from '@/utils/itemOperations';
import { generateTempId, validateUuid } from '@/utils/tempIdGenerator';

type ItemType = Database['public']['Enums']['item_type'];

const generateTitle = async (content: string, type: string): Promise<string> => {
  try {
    const { data: result, error } = await supabase.functions.invoke('generate-title', {
      body: { content }
    });

    if (error) throw error;
    return result.title || 'Untitled Note';
  } catch (error) {
    console.error('Error generating title:', error);
    // Fallback to a simple title based on content
    if (type === 'text' && content) {
      const plainText = content.length > 50 ? content.substring(0, 47) + '...' : content;
      return plainText || 'Untitled Note';
    }
    return 'Untitled Note';
  }
};

export const useItemOperations = (
  fetchItems: () => Promise<void>,
  addOptimisticItem?: (item: any) => void,
  removeOptimisticItem?: (tempId: string) => void
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
      const tempId = generateTempId();
      console.log('Generated temp ID for skeleton:', tempId);
      
      const skeletonItem = {
        id: tempId,
        user_id: user.id,
        type: type as ItemType,
        title: data.title || 'Processing...',
        content: null,
        description: 'Processing...',
        url: null,
        file_path: null,
        file_size: data.file?.size || null,
        mime_type: data.file?.type || null,
        created_at: new Date().toISOString(),
        isOptimistic: true,
        showSkeleton: true
      };

      if (addOptimisticItem) {
        addOptimisticItem(skeletonItem);
      }
      return; // Don't process further for skeleton items
    }

    // Generate proper temporary ID for real content
    const tempId = generateTempId();
    console.log('Generated temp ID:', tempId);
    
    // Generate title for text notes
    let title = data.title;
    if (type === 'text' && data.content && !title) {
      title = await generateTitle(data.content, type);
    }

    try {
      console.log('Adding content:', { type, data, userId: user.id, sessionValid: !!session });
      
      let filePath = null;
      
      // Handle file upload if there's a file and no uploaded path provided
      if (data.file && !data.uploadedFilePath) {
        console.log('Starting file upload for user:', user.id);
        
        // Verify session is still valid before upload
        const { data: { session: currentSession }, error: sessionError } = await supabase.auth.getSession();
        if (sessionError || !currentSession) {
          console.error('Session validation failed before file upload:', sessionError);
          throw new Error('Session expired. Please log in again.');
        }
        
        filePath = await uploadFile(data.file, user.id);
        console.log('File uploaded successfully:', filePath);
      }

      // Use provided description or generate AI description
      let aiDescription = data.description; // This comes from MediaUploadTab for images
      
      if (!aiDescription && !data.isProcessing) {
        console.log('useItemOperations: No description provided, generating AI description');
        aiDescription = await generateDescription(type, data);
        console.log('useItemOperations: Generated AI description:', aiDescription);
      } else if (data.isProcessing) {
        aiDescription = "PDF file uploaded - text extraction in progress";
      } else {
        console.log('useItemOperations: Using provided description:', aiDescription);
      }

      // Prepare the item data
      const itemData = {
        user_id: user.id,
        type: type as ItemType,
        title: title || data.title,
        content: data.content,
        description: aiDescription || null, // Ensure we use the AI description
        url: data.url,
        file_path: filePath || data.uploadedFilePath, // Use uploaded file path if provided
        file_size: data.file?.size,
        mime_type: data.file?.type,
      };

      console.log('useItemOperations: Inserting item data:', itemData);

      // Insert item into database
      const { data: insertedItem, error } = await supabase
        .from('items')
        .insert(itemData)
        .select()
        .single();

      if (error) {
        console.error('Error inserting item:', error);
        throw error;
      }

      console.log('useItemOperations: Item inserted successfully:', insertedItem);

      // If this is replacing an optimistic item, remove all skeleton items and refresh
      if (data.replaceOptimistic && removeOptimisticItem) {
        // Remove all optimistic items of the same type (since we can't track specific temp IDs across the async boundary)
        // This will be cleaned up by fetchItems anyway
      }
      
      await fetchItems();

      // Handle PDF processing separately with longer delay
      if (type === 'document' && (filePath || data.uploadedFilePath)) {
        console.log('Starting PDF processing for item:', insertedItem.id);
        // Process PDF in the background with a longer delay
        setTimeout(async () => {
          try {
            await processPdfContent(insertedItem.id, filePath || data.uploadedFilePath, fetchItems, showToast);
          } catch (error) {
            console.error('Background PDF processing failed:', error);
          }
        }, 3000);
      } else {
        // Generate embeddings for non-PDF textual content
        const textForEmbedding = [
          title || data.title,
          data.content,
          aiDescription,
          data.url,
          data.ogData?.title,
          data.ogData?.description
        ].filter(Boolean).join(' ');

        if (textForEmbedding.trim()) {
          await generateEmbeddings(insertedItem.id, textForEmbedding);
        }
      }

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

  const handleSaveItem = async (id: string, updates: any) => {
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
    
    await saveItem(id, updates, fetchItems, showToast);
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
