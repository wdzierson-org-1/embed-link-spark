
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
  attachments?: Array<{
    type: string;
    url?: string;
    file?: File;
    title?: string;
    description?: string;
    name?: string;
    size?: number;
    fileType?: string;
    image?: string;
    siteName?: string;
  }>;
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
  
  // Handle collection type with attachments
  if (type === 'collection' && data.attachments && data.attachments.length > 0) {
    return await processCollection(data, userId, sessionValid, fetchItems, showToast, clearSkeletonItems);
  }
  
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

// New function to process collections with attachments
const processCollection = async (
  data: ContentData,
  userId: string,
  sessionValid: boolean,
  fetchItems: () => Promise<void>,
  showToast: (toast: { title: string; description: string; variant?: 'destructive' }) => void,
  clearSkeletonItems?: () => void
): Promise<any> => {
  console.log('Processing collection with', data.attachments?.length, 'attachments');

  let title = data.title;
  let description = data.description;

  // If no title/description provided, use AI to analyze the collection
  if (!title || !description) {
    try {
      const { data: analysisResult, error: analysisError } = await supabase.functions.invoke('analyze-collection', {
        body: { 
          attachments: data.attachments,
          userText: data.content || ''
        }
      });

      if (analysisError) throw analysisError;

      if (!title) title = analysisResult.title;
      if (!description) description = analysisResult.description;
    } catch (error) {
      console.error('Error analyzing collection:', error);
      title = title || 'Collection';
      description = description || `Collection with ${data.attachments?.length || 0} items`;
    }
  }

  // Create the collection item
  const itemData: any = {
    type: 'collection' as ItemType,
    user_id: userId,
    title,
    description,
    content: data.content || null,
  };

  console.log('Inserting collection with data:', itemData);

  if (clearSkeletonItems) {
    clearSkeletonItems();
  }

  const { data: insertedItem, error } = await supabase
    .from('items')
    .insert(itemData)
    .select()
    .single();

  if (error) {
    console.error('Error inserting collection:', error);
    throw error;
  }

  console.log('Collection inserted successfully:', insertedItem);

  // Process and insert attachments
  if (data.attachments && data.attachments.length > 0) {
    await processAttachments(insertedItem.id, data.attachments, userId);
  }

  await fetchItems();

  // Generate embeddings for collection content (run in background)
  setTimeout(async () => {
    try {
      let embeddingContent = data.content || '';
      
      // Add attachment titles and descriptions to embedding content
      if (data.attachments) {
        const attachmentTexts = data.attachments
          .map(att => `${att.title || att.name || att.url || ''} ${att.description || ''}`)
          .filter(text => text.trim())
          .join(' ');
        embeddingContent += ' ' + attachmentTexts;
      }

      if (embeddingContent.trim()) {
        await generateEmbeddings(insertedItem.id, embeddingContent);
      }
    } catch (error) {
      console.error('Error generating embeddings for collection:', error);
    }
  }, 2000);

  return insertedItem;
};

// Process individual attachments
const processAttachments = async (
  itemId: string,
  attachments: any[],
  userId: string
): Promise<void> => {
  console.log('Processing attachments for item:', itemId);

  for (const attachment of attachments) {
    try {
      let attachmentData: any = {
        item_id: itemId,
        type: attachment.type as ItemType,
        title: attachment.title || attachment.name,
        description: attachment.description,
      };

      if (attachment.type === 'link') {
        attachmentData.url = attachment.url;
        attachmentData.metadata = {
          siteName: attachment.siteName,
          image: attachment.image,
        };
      } else {
        // Handle file upload for media attachments
        if (attachment.file) {
          const uploadResult = await uploadFile(attachment.file, userId);
          attachmentData.file_path = uploadResult;
          attachmentData.file_size = attachment.size;
          attachmentData.mime_type = attachment.fileType;
        }
      }

      const { error } = await supabase
        .from('item_attachments')
        .insert(attachmentData);

      if (error) {
        console.error('Error inserting attachment:', error);
      } else {
        console.log('Attachment inserted successfully:', attachmentData.title);
      }
    } catch (error) {
      console.error('Error processing attachment:', error);
    }
  }
};
