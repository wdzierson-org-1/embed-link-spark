
import { supabase } from '@/integrations/supabase/client';
import { generateDescription, generateEmbeddings } from '@/utils/aiOperations';
import { processPdfContent } from '@/utils/pdfProcessor';
import { uploadFile } from '@/utils/fileUploader';
import { generateTitle } from '@/utils/titleGenerator';
import type { Database } from '@/integrations/supabase/types';

type ItemType = Database['public']['Enums']['item_type'];

interface ContentData {
  file?: File;
  uploadedFilePath?: string;
  content?: string;
  description?: string;
  url?: string;
  title?: string;
  isProcessing?: boolean;
  ogData?: any;
  previewImagePath?: string; // New field for link preview images
}

export const processAndInsertContent = async (
  type: string,
  data: ContentData,
  userId: string,
  sessionValid: boolean,
  fetchItems: () => Promise<void>,
  showToast: (toast: { title: string; description: string; variant?: 'destructive' }) => void,
  clearSkeletonItems?: () => void
) => {
  console.log('Processing content:', { type, data, userId, sessionValid });
  
  let filePath = null;
  
  // Handle file upload if there's a file and no uploaded path provided
  if (data.file && !data.uploadedFilePath) {
    console.log('Starting file upload for user:', userId);
    
    const { data: { session: currentSession }, error: sessionError } = await supabase.auth.getSession();
    if (sessionError || !currentSession) {
      console.error('Session validation failed before file upload:', sessionError);
      throw new Error('Session expired. Please log in again.');
    }
    
    filePath = await uploadFile(data.file, userId);
    console.log('File uploaded successfully:', filePath);
  }

  // For links, use the preview image path if provided
  if (type === 'link' && data.previewImagePath) {
    filePath = data.previewImagePath;
  }

  // Generate title for text notes
  let title = data.title;
  if (type === 'text' && data.content && !title) {
    title = await generateTitle(data.content, type);
  }

  // Use provided description or generate AI description
  let aiDescription = data.description;
  
  if (!aiDescription && !data.isProcessing) {
    console.log('processAndInsertContent: No description provided, generating AI description');
    aiDescription = await generateDescription(type, data);
    console.log('processAndInsertContent: Generated AI description:', aiDescription);
  } else if (data.isProcessing) {
    aiDescription = "PDF file uploaded - text extraction in progress";
  } else {
    console.log('processAndInsertContent: Using provided description:', aiDescription);
  }

  // Prepare the item data - for links, store clean structured data
  const itemData = {
    user_id: userId,
    type: type as ItemType,
    title: title || data.title,
    content: data.content, // For links, this should be empty initially (user notes)
    description: aiDescription || null,
    url: data.url,
    file_path: filePath || data.uploadedFilePath,
    file_size: data.file?.size,
    mime_type: data.file?.type,
  };

  console.log('processAndInsertContent: Inserting item data:', itemData);

  if (clearSkeletonItems) {
    clearSkeletonItems();
  }

  const { data: insertedItem, error } = await supabase
    .from('items')
    .insert(itemData)
    .select()
    .single();

  if (error) {
    console.error('Error inserting item:', error);
    throw error;
  }

  console.log('processAndInsertContent: Item inserted successfully:', insertedItem);
  
  await fetchItems();

  // Handle PDF processing separately with longer delay
  if (type === 'document' && (filePath || data.uploadedFilePath)) {
    console.log('Starting PDF processing for item:', insertedItem.id);
    setTimeout(async () => {
      try {
        await processPdfContent(insertedItem.id, filePath || data.uploadedFilePath, fetchItems, showToast);
      } catch (error) {
        console.error('Background PDF processing failed:', error);
      }
    }, 3000);
  } else {
    // Generate embeddings for textual content
    const textForEmbedding = [
      title || data.title,
      data.content,
      aiDescription,
      data.url
    ].filter(Boolean).join(' ');

    if (textForEmbedding.trim()) {
      await generateEmbeddings(insertedItem.id, textForEmbedding);
    }
  }

  return insertedItem;
};
