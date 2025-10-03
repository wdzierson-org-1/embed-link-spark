
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

  // For links, use the preview image path if provided (only if it's a valid storage path)
  if (type === 'link' && data.previewImagePath && !data.previewImagePath.startsWith('http')) {
    filePath = data.previewImagePath;
    console.log('Using previewImagePath for link:', filePath);
  } else if (type === 'link' && !data.previewImagePath && data.ogData?.image && data.ogData.image.startsWith('http')) {
    // Fallback: if no storage path but we have an HTTP image URL, save it for display
    filePath = data.ogData.image;
    console.log('Using ogData.image fallback for link:', filePath);
  } else if (type === 'link') {
    console.log('No image path found for link:', { previewImagePath: data.previewImagePath, ogDataImage: data.ogData?.image });
  }

  // Generate title for text notes
  let title = data.title;
  if (type === 'text' && data.content && !title) {
    title = await generateTitle(data.content, type);
  }

  // Handle media processing and AI description generation
  let aiDescription = data.description;
  let transcription = '';
  
  if (!aiDescription && !data.isProcessing) {
    console.log('processAndInsertContent: Processing media and generating AI description');
    
    // Handle audio transcription
    if (type === 'audio' && (filePath || data.uploadedFilePath)) {
      try {
        const audioPath = filePath || data.uploadedFilePath;
        const { data: audioUrl } = supabase.storage.from('stash-media').getPublicUrl(audioPath);
        
        const { data: transcriptionResult, error: transcriptionError } = await supabase.functions.invoke('transcribe-audio', {
          body: {
            audioUrl: audioUrl.publicUrl,
            fileName: data.file?.name || 'audio.webm'
          }
        });

        if (transcriptionError) {
          console.error('Audio transcription failed:', transcriptionError);
          aiDescription = 'Audio file uploaded but transcription failed';
        } else {
          transcription = transcriptionResult.transcription || '';
          aiDescription = transcriptionResult.description || 'Audio transcription available';
          console.log('Audio transcribed successfully:', { transcription: transcription.substring(0, 100) + '...' });
        }
      } catch (error) {
        console.error('Audio processing error:', error);
        aiDescription = 'Audio file uploaded but processing failed';
      }
    }
    // Handle image description with proper URL
    else if (type === 'image' && (filePath || data.uploadedFilePath)) {
      try {
        const imagePath = filePath || data.uploadedFilePath;
        const { data: imageUrl } = supabase.storage.from('stash-media').getPublicUrl(imagePath);
        
        const imageData = { ...data, fileData: imageUrl.publicUrl };
        aiDescription = await generateDescription(type, imageData);
        console.log('Image described successfully:', aiDescription);
      } catch (error) {
        console.error('Image description error:', error);
        aiDescription = 'Image uploaded but description failed';
      }
    }
    // Handle other content types
    else {
      aiDescription = await generateDescription(type, data);
    }
    
    console.log('processAndInsertContent: Generated AI description:', aiDescription);
  } else if (data.isProcessing) {
    aiDescription = "PDF file uploaded - text extraction in progress";
  } else {
    console.log('processAndInsertContent: Using provided description:', aiDescription);
  }

  // Prepare the item data - for links, store clean structured data
  const itemContent = transcription || data.content; // Use transcription for audio files
  const itemData = {
    user_id: userId,
    type: type as ItemType,
    title: title || data.title,
    content: itemContent, // Use transcription for audio, original content for others
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

  // Add success toast when real item replaces skeleton
  showToast({
    title: "Success",
    description: "Content added to your stash!",
  });

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

  // Handle PDF processing with quick summary first, then full extraction
  if (type === 'document' && (filePath || data.uploadedFilePath)) {
    console.log('Starting PDF processing for item:', insertedItem.id);
    
    // Phase 1: Quick summary (immediate)
    setTimeout(async () => {
      try {
        const fileName = data.file?.name || 'document.pdf';
        const pdfPath = filePath || data.uploadedFilePath;
        const { data: urlData } = supabase.storage.from('stash-media').getPublicUrl(pdfPath);
        
        console.log('Calling quick-pdf-summary for:', insertedItem.id);
        await supabase.functions.invoke('quick-pdf-summary', {
          body: {
            fileUrl: urlData.publicUrl,
            itemId: insertedItem.id,
            fileName
          }
        });
        
        // Refresh UI with quick summary
        await fetchItems();
      } catch (error) {
        console.error('Quick PDF summary failed:', error);
      }
    }, 500);
    
    // Phase 2: Full extraction (after delay)
    setTimeout(async () => {
      try {
        await processPdfContent(insertedItem.id, filePath || data.uploadedFilePath, fetchItems, showToast);
      } catch (error) {
        console.error('Background PDF processing failed:', error);
      }
    }, 5000);
  } else {
    // Generate embeddings for textual content (including transcriptions and descriptions)
    const textForEmbedding = [
      title || data.title,
      transcription || data.content, // Use transcription for audio files
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

  // Add success toast when real item replaces skeleton
  showToast({
    title: "Success", 
    description: "Collection added to your stash!",
  });

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
  let processedAttachments = [];
  if (data.attachments && data.attachments.length > 0) {
    processedAttachments = await processAttachments(insertedItem.id, data.attachments, userId);
  }

  await fetchItems();

  // Generate embeddings for collection content including AI-processed attachments (run in background)
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

      // Include AI-processed content from attachments
      const aiProcessedContent = processedAttachments
        .map(att => att.metadata?.processedContent || '')
        .filter(content => content.trim())
        .join(' ');
      
      if (aiProcessedContent) {
        embeddingContent += ' ' + aiProcessedContent;
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
): Promise<any[]> => {
  console.log('Processing attachments for item:', itemId);
  const processedAttachments = [];

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

          // Process media with AI for better descriptions
          const { processMediaAttachment } = await import('./mediaProcessor');
          const mediaResult = await processMediaAttachment(
            uploadResult,
            attachment.type,
            attachment.name || attachment.title
          );

          // Update with AI-processed content
          if (mediaResult.title) attachmentData.title = mediaResult.title;
          if (mediaResult.description) attachmentData.description = mediaResult.description;
          
          attachmentData.metadata = {
            ...attachmentData.metadata,
            originalName: attachment.name || attachment.title,
            aiProcessed: true,
            processedContent: mediaResult.content
          };
        }
      }

      const { data: insertedAttachment, error } = await supabase
        .from('item_attachments')
        .insert(attachmentData)
        .select()
        .single();

      if (error) {
        console.error('Error inserting attachment:', error);
      } else {
        console.log('Attachment inserted successfully:', attachmentData.title);
        processedAttachments.push(insertedAttachment);
      }
    } catch (error) {
      console.error('Error processing attachment:', error);
    }
  }

  return processedAttachments;
};
