
import { supabase } from '@/integrations/supabase/client';

export const processPdfContent = async (
  itemId: string, 
  filePath: string, 
  fetchItems: () => Promise<void>,
  showToast: (toast: { title: string; description: string; variant?: 'destructive' }) => void
) => {
  try {
    // Get the public URL for the file
    const { data: urlData } = supabase.storage
      .from('stash-media')
      .getPublicUrl(filePath);

    if (!urlData?.publicUrl) {
      throw new Error('Failed to get file URL');
    }

    console.log('Processing PDF with URL:', urlData.publicUrl, 'for item:', itemId);

    // Call the PDF extraction function
    const { data: result, error } = await supabase.functions.invoke('extract-pdf-text', {
      body: {
        fileUrl: urlData.publicUrl,
        itemId
      }
    });

    if (error) {
      console.error('PDF extraction error:', error);
      throw error;
    }

    console.log('PDF extraction result:', result);

    // Force refresh items multiple times to ensure UI updates
    console.log('PDF processing completed, refreshing items...');
    await fetchItems();
    
    // Add a small delay and fetch again to ensure the update is reflected
    setTimeout(async () => {
      await fetchItems();
    }, 1000);
    
    showToast({
      title: "PDF Processed",
      description: "PDF text has been extracted and is now searchable!",
    });
  } catch (error) {
    console.error('Error processing PDF:', error);
    showToast({
      title: "PDF Processing Failed",
      description: error.message || "Failed to extract text from PDF",
      variant: "destructive",
    });
  }
};

export const getPdfFileUrl = (filePath: string): string => {
  const { data } = supabase.storage
    .from('stash-media')
    .getPublicUrl(filePath);
  return data.publicUrl;
};
