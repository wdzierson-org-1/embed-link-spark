
import { supabase } from '@/integrations/supabase/client';
import { generateEmbeddings } from './aiOperations';

export const saveItem = async (
  id: string, 
  updates: any, 
  fetchItems: () => Promise<void>,
  showToast: (toast: { title: string; description: string; variant?: 'destructive' }) => void
) => {
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

    showToast({
      title: "Success",
      description: "Item updated successfully!",
    });

    fetchItems();
  } catch (error: any) {
    showToast({
      title: "Error",
      description: error.message || "Failed to update item",
      variant: "destructive",
    });
  }
};

export const deleteItem = async (
  id: string, 
  fetchItems: () => Promise<void>,
  showToast: (toast: { title: string; description: string; variant?: 'destructive' }) => void
) => {
  try {
    console.log('Deleting item:', id);
    
    // First delete any associated embeddings
    const { error: embeddingError } = await supabase
      .from('embeddings')
      .delete()
      .eq('item_id', id);

    if (embeddingError) {
      console.error('Error deleting embeddings:', embeddingError);
      // Don't fail the delete operation if embeddings deletion fails
    }

    // Then delete the item itself
    const { error } = await supabase
      .from('items')
      .delete()
      .eq('id', id);

    if (error) {
      console.error('Error deleting item:', error);
      throw error;
    }

    console.log('Item deleted successfully');
    
    showToast({
      title: "Success",
      description: "Item deleted from your stash",
    });
    
    // Refresh the items list
    await fetchItems();
  } catch (error: any) {
    console.error('Error in deleteItem:', error);
    showToast({
      title: "Error",
      description: error.message || "Failed to delete item",
      variant: "destructive",
    });
  }
};
