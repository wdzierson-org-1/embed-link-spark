import { supabase } from '@/integrations/supabase/client';
import { generateEmbeddings } from './aiOperations';
import { extractPlainTextFromNovelContent } from './contentExtractor';

// --- Search-index refresh, decoupled from the save path ---------------------
// Saves resolve as soon as the items PATCH lands; embedding regeneration (an
// OpenAI round trip, often 1s+) runs shortly after on an idle debounce,
// latest-write-wins per item. A failure here means search lags one edit — it
// never blocks or fails a save.
const EMBED_IDLE_MS = 4000;
const pendingEmbedRows = new Map<string, any>();
const pendingEmbedTimers = new Map<string, ReturnType<typeof setTimeout>>();
const inFlightEmbeds = new Map<string, Promise<void>>();

const buildEmbeddingText = (row: any): string => {
  const textualContent: string[] = [];

  if (row.title) textualContent.push(row.title);
  if (row.description) textualContent.push(row.description);

  // Extract plain text from Novel editor content, stripping formatting
  if (row.content) {
    const plainTextContent = extractPlainTextFromNovelContent(row.content);
    if (plainTextContent.trim()) textualContent.push(plainTextContent);
  }

  if (row.supplemental_note) textualContent.push(row.supplemental_note);
  if (row.url) textualContent.push(row.url);

  // Captured source material and AI summary aren't user-editable here, but
  // embeddings are fully replaced on regeneration — losing them from the
  // text would silently drop them from search
  if (row.summary) textualContent.push(row.summary);
  if (row.page_body) textualContent.push(row.page_body);

  return textualContent.join(' ').trim();
};

const runEmbeddingRefresh = async (itemId: string) => {
  const row = pendingEmbedRows.get(itemId);
  pendingEmbedRows.delete(itemId);
  if (!row) return;

  const textForEmbedding = buildEmbeddingText(row);
  if (!textForEmbedding) return;

  console.log('Updating embeddings for item:', itemId);
  await supabase.from('embeddings').delete().eq('item_id', itemId);
  await generateEmbeddings(itemId, textForEmbedding);
};

export const scheduleEmbeddingRefresh = (row: any) => {
  const itemId = row?.id;
  if (!itemId) return;

  // Keep only the newest merged row; restart the idle timer on every save
  pendingEmbedRows.set(itemId, row);
  const existingTimer = pendingEmbedTimers.get(itemId);
  if (existingTimer) clearTimeout(existingTimer);

  pendingEmbedTimers.set(itemId, setTimeout(() => {
    pendingEmbedTimers.delete(itemId);
    // Chain behind any in-flight run so an older regeneration can't finish
    // after (and clobber) a newer one
    const prev = inFlightEmbeds.get(itemId) ?? Promise.resolve();
    const next = prev
      .catch(() => {})
      .then(() => runEmbeddingRefresh(itemId))
      .catch(error => console.error('Embedding refresh failed:', error))
      .finally(() => {
        if (inFlightEmbeds.get(itemId) === next) inFlightEmbeds.delete(itemId);
      });
    inFlightEmbeds.set(itemId, next);
  }, EMBED_IDLE_MS));
};
// ---------------------------------------------------------------------------

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

    // Refresh embeddings when a text field changed — from the full merged row,
    // so a partial patch (e.g. title-only blur save) can't wipe the rest of the
    // item's searchable content. Deliberately not awaited: see scheduler above.
    const textFieldsChanged = ['title', 'description', 'content', 'supplemental_note']
      .some(field => field in updates);

    if (textFieldsChanged && updatedItem) {
      scheduleEmbeddingRefresh(updatedItem);
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
