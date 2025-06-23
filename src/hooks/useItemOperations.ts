
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';
import type { Database } from '@/integrations/supabase/types';

type ItemType = Database['public']['Enums']['item_type'];

export const useItemOperations = (fetchItems: () => Promise<void>) => {
  const { user } = useAuth();
  const { toast } = useToast();

  const generateDescription = async (type: string, data: any) => {
    try {
      const { data: result, error } = await supabase.functions.invoke('generate-description', {
        body: {
          content: data.content,
          type,
          url: data.url,
          fileData: data.fileData,
          ogData: data.ogData
        }
      });

      if (error) throw error;
      return result.description;
    } catch (error) {
      console.error('Error generating description:', error);
      return null;
    }
  };

  const generateEmbeddings = async (itemId: string, textContent: string) => {
    try {
      const { error } = await supabase.functions.invoke('generate-embeddings', {
        body: {
          itemId,
          textContent
        }
      });

      if (error) throw error;
    } catch (error) {
      console.error('Error generating embeddings:', error);
    }
  };

  const handleAddContent = async (type: string, data: any) => {
    if (!user) return;

    try {
      console.log('Adding content:', { type, data, userId: user.id });
      
      let filePath = null;
      
      // Handle file upload if there's a file
      if (data.file) {
        const fileExt = data.file.name.split('.').pop();
        const fileName = `${Date.now()}.${fileExt}`;
        filePath = `${user.id}/${fileName}`;

        const { error: uploadError } = await supabase.storage
          .from('stash-media')
          .upload(filePath, data.file);

        if (uploadError) {
          throw uploadError;
        }
      }

      // Generate AI description
      const aiDescription = await generateDescription(type, data);

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

      // Generate embeddings for textual content
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

      toast({
        title: "Success",
        description: "Content added to your stash!",
      });

      fetchItems();
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
    try {
      const { error } = await supabase
        .from('items')
        .update(updates)
        .eq('id', id);

      if (error) throw error;

      // Regenerate embeddings if textual content changed
      const textForEmbedding = [
        updates.title,
        updates.content,
        updates.description
      ].filter(Boolean).join(' ');

      if (textForEmbedding.trim()) {
        // Delete old embeddings
        await supabase.from('embeddings').delete().eq('item_id', id);
        // Generate new embeddings
        await generateEmbeddings(id, textForEmbedding);
      }

      toast({
        title: "Success",
        description: "Item updated successfully!",
      });

      fetchItems();
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to update item",
        variant: "destructive",
      });
    }
  };

  const handleDeleteItem = async (id: string) => {
    const { error } = await supabase
      .from('items')
      .delete()
      .eq('id', id);

    if (error) {
      toast({
        title: "Error",
        description: "Failed to delete item",
        variant: "destructive",
      });
    } else {
      toast({
        title: "Success",
        description: "Item deleted from your stash",
      });
      fetchItems();
    }
  };

  return {
    handleAddContent,
    handleSaveItem,
    handleDeleteItem
  };
};
