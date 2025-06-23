
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { generateEmbeddings } from './aiOperations';

export const saveItem = async (id: string, updates: any, fetchItems: () => Promise<void>) => {
  const { toast } = useToast();
  
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

export const deleteItem = async (id: string, fetchItems: () => Promise<void>) => {
  const { toast } = useToast();
  
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
