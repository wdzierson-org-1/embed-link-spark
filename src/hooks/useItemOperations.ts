
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';
import type { Database } from '@/integrations/supabase/types';
import { generateDescription, generateEmbeddings } from '@/utils/aiOperations';
import { processPdfContent } from '@/utils/pdfProcessor';
import { uploadFile } from '@/utils/fileUploader';
import { saveItem, deleteItem } from '@/utils/itemOperations';

type ItemType = Database['public']['Enums']['item_type'];

export const useItemOperations = (fetchItems: () => Promise<void>) => {
  const { user } = useAuth();
  const { toast } = useToast();

  const handleAddContent = async (type: string, data: any) => {
    if (!user) {
      console.error('No user found');
      return;
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
        title: data.title,
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

      // Immediately refresh items to show the new item
      await fetchItems();

      // Handle PDF processing separately
      if (type === 'document' && filePath) {
        console.log('Starting PDF processing for item:', insertedItem.id);
        // Process PDF in the background with a longer delay to ensure the item is visible first
        setTimeout(async () => {
          await processPdfContent(insertedItem.id, filePath, fetchItems);
        }, 2000);
      } else {
        // Generate embeddings for non-PDF textual content
        const textForEmbedding = [
          data.title,
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
      toast({
        title: "Error",
        description: error.message || "Failed to add content",
        variant: "destructive",
      });
    }
  };

  const handleSaveItem = async (id: string, updates: any) => {
    await saveItem(id, updates, fetchItems);
  };

  const handleDeleteItem = async (id: string) => {
    await deleteItem(id, fetchItems);
  };

  return {
    handleAddContent,
    handleSaveItem,
    handleDeleteItem
  };
};
