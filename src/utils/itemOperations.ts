import { supabase } from '@/integrations/supabase/client';
import { generateEmbeddings } from './aiOperations';
import { extractPlainTextFromNovelContent } from './contentExtractor';

export const saveItem = async (
  id: string, 
  updates: any, 
  fetchItems: () => Promise<void>,
  showToast: (toast: { title: string; description: string; variant?: 'destructive' }) => void,
  options: { showSuccessToast?: boolean; refreshItems?: boolean } = {}
) => {
  const { showSuccessToast = true, refreshItems = true } = options;
  
  try {
    const { data: updatedItem, error } = await supabase
      .from('items')
      .update(updates)
      .eq('id', id)
      .select()
      .single();

    if (error) throw error;

    // Regenerate embeddings when a text field changed — but always from the full
    // merged row, so a partial patch (e.g. title-only blur save) can't wipe the
    // rest of the item's searchable content.
    const textFieldsChanged = ['title', 'description', 'content', 'supplemental_note']
      .some(field => field in updates);

    if (textFieldsChanged && updatedItem) {
      const textualContent = [];

      if (updatedItem.title) {
        textualContent.push(updatedItem.title);
      }

      if (updatedItem.description) {
        textualContent.push(updatedItem.description);
      }

      // Extract plain text from Novel editor content, stripping formatting
      if (updatedItem.content) {
        const plainTextContent = extractPlainTextFromNovelContent(updatedItem.content);
        if (plainTextContent.trim()) {
          textualContent.push(plainTextContent);
        }
      }

      if (updatedItem.supplemental_note) {
        textualContent.push(updatedItem.supplemental_note);
      }

      if (updatedItem.url) {
        textualContent.push(updatedItem.url);
      }

      // Captured source material and AI summary aren't user-editable here, but
      // embeddings are fully replaced on regeneration — losing them from the
      // text would silently drop them from search
      if (updatedItem.summary) {
        textualContent.push(updatedItem.summary);
      }

      if (updatedItem.page_body) {
        textualContent.push(updatedItem.page_body);
      }

      const textForEmbedding = textualContent.join(' ').trim();

      if (textForEmbedding) {
        console.log('Updating embeddings for item:', id);

        // Delete old embeddings
        await supabase.from('embeddings').delete().eq('item_id', id);

        // Generate new embeddings with plain text
        await generateEmbeddings(id, textForEmbedding);
      }
    }

    if (showSuccessToast) {
      showToast({
        title: "Success",
        description: "Item updated successfully!",
      });
    }

    if (refreshItems) {
      fetchItems();
    }
  } catch (error: any) {
    console.error('Error saving item:', error);
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
