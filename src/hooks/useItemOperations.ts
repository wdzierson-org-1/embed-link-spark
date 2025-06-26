
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';
import type { Database } from '@/integrations/supabase/types';
import { generateDescription, generateEmbeddings } from '@/utils/aiOperations';
import { processPdfContent } from '@/utils/pdfProcessor';
import { uploadFile } from '@/utils/fileUploader';
import { saveItem, deleteItem } from '@/utils/itemOperations';

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
  const { user } = useAuth();
  const { toast } = useToast();

  const showToast = (toastData: { title: string; description: string; variant?: 'destructive' }) => {
    toast(toastData);
  };

  const handleAddContent = async (type: string, data: any) => {
    if (!user) {
      console.error('No user found');
      return;
    }

    // Generate temporary ID for optimistic update
    const tempId = `temp-${Date.now()}-${Math.random()}`;
    
    // Generate title for text notes
    let title = data.title;
    if (type === 'text' && data.content && !title) {
      title = await generateTitle(data.content, type);
    }
    
    // Create optimistic item
    const optimisticItem = {
      id: tempId,
      user_id: user.id,
      type: type as ItemType,
      title: title || data.title || 'Processing...',
      content: data.content || null,
      description: 'Generating description...',
      url: data.url || null,
      file_path: null,
      file_size: data.file?.size || null,
      mime_type: data.file?.type || null,
      created_at: new Date().toISOString(),
      isOptimistic: true
    };

    // Add optimistic item immediately
    if (addOptimisticItem) {
      addOptimisticItem(optimisticItem);
    }

    try {
      console.log('Adding content:', { type, data, userId: user.id });
      
      let filePath = null;
      
      // Handle file upload if there's a file
      if (data.file) {
        filePath = await uploadFile(data.file, user.id);
      }

      // Generate AI description (skip for PDFs with placeholder content)
      const aiDescription = data.isProcessing ? 
        "PDF file uploaded - text extraction in progress" : 
        await generateDescription(type, data);

      console.log('Generated description:', aiDescription);

      // Prepare the item data
      const itemData = {
        user_id: user.id,
        type: type as ItemType,
        title: title || data.title,
        content: data.content,
        description: aiDescription,
        url: data.url,
        file_path: filePath,
        file_size: data.file?.size,
        mime_type: data.file?.type,
      };

      console.log('Inserting item data:', itemData);

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

      console.log('Item inserted successfully:', insertedItem);

      // Remove optimistic item and refresh real items
      if (removeOptimisticItem) {
        removeOptimisticItem(tempId);
      }
      await fetchItems();

      // Handle PDF processing separately with longer delay
      if (type === 'document' && filePath) {
        console.log('Starting PDF processing for item:', insertedItem.id);
        // Process PDF in the background with a longer delay
        setTimeout(async () => {
          try {
            await processPdfContent(insertedItem.id, filePath, fetchItems, showToast);
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
      
      // Remove optimistic item on error
      if (removeOptimisticItem) {
        removeOptimisticItem(tempId);
      }
      
      toast({
        title: "Error",
        description: error.message || "Failed to add content",
        variant: "destructive",
      });
    }
  };

  const handleSaveItem = async (id: string, updates: any) => {
    await saveItem(id, updates, fetchItems, showToast);
  };

  const handleDeleteItem = async (id: string) => {
    await deleteItem(id, fetchItems, showToast);
  };

  return {
    handleAddContent,
    handleSaveItem,
    handleDeleteItem
  };
};
