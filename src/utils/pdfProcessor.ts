
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

export const processPdfContent = async (
  itemId: string, 
  filePath: string, 
  fetchItems: () => Promise<void>
) => {
  const { toast } = useToast();
  
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
    const { error } = await supabase.functions.invoke('extract-pdf-text', {
      body: {
        fileUrl: urlData.publicUrl,
        itemId
      }
    });

    if (error) throw error;

    // Force refresh items to show updated content
    console.log('PDF processing completed, refreshing items...');
    await fetchItems();
    
    toast({
      title: "PDF Processed",
      description: "PDF text has been extracted and is now searchable!",
    });
  } catch (error) {
    console.error('Error processing PDF:', error);
    toast({
      title: "PDF Processing Failed",
      description: "Failed to extract text from PDF",
      variant: "destructive",
    });
  }
};
