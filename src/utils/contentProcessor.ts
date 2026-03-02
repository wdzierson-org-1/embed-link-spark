
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

interface ExtractedLinkMetadata {
  title?: string;
  description?: string;
  image?: string;
  previewImagePath?: string;
  previewImagePublicUrl?: string;
  siteName?: string;
}

const collectionEmbeddingTimers = new Map<string, ReturnType<typeof setTimeout>>();

const hasValue = (value: unknown): value is string => typeof value === 'string' && value.trim().length > 0;

const getYouTubeVideoId = (url: string): string | null => {
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();

    if (!host.includes('youtube.com') && !host.includes('youtu.be')) {
      return null;
    }

    if (host.includes('youtu.be')) {
      return parsed.pathname.split('/').filter(Boolean)[0] || null;
    }

    const queryId = parsed.searchParams.get('v');
    if (queryId) return queryId;

    const segments = parsed.pathname.split('/').filter(Boolean);
    const markerIndex = segments.findIndex((segment) => ['embed', 'shorts', 'live'].includes(segment));
    if (markerIndex !== -1 && segments[markerIndex + 1]) {
      return segments[markerIndex + 1];
    }
  } catch {
    return null;
  }

  return null;
};

const buildYouTubeFallbackMetadata = (url: string): ExtractedLinkMetadata | null => {
  const videoId = getYouTubeVideoId(url);
  if (!videoId) return null;

  return {
    title: 'YouTube Video',
    description: 'Video link from YouTube',
    image: `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
    siteName: 'YouTube',
  };
};

const fetchYouTubeOEmbedMetadata = async (url: string): Promise<ExtractedLinkMetadata | null> => {
  const videoId = getYouTubeVideoId(url);
  if (!videoId) return null;

  try {
    const oembedUrl = `https://www.youtube.com/oembed?url=${encodeURIComponent(`https://www.youtube.com/watch?v=${videoId}`)}&format=json`;
    const response = await fetch(oembedUrl);
    if (!response.ok) return null;

    const data = await response.json();
    if (!data?.title) return null;

    return {
      title: data.title,
      description: data.author_name ? `Watch "${data.title}" by ${data.author_name} on YouTube` : 'YouTube video',
      image: data.thumbnail_url || `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
      siteName: 'YouTube',
    };
  } catch (error) {
    console.log('YouTube oEmbed fallback failed during enrichment:', error);
    return null;
  }
};

const extractLinkMetadata = async (url: string, userId: string): Promise<ExtractedLinkMetadata | null> => {
  if (!url) return null;

  try {
    const { data, error } = await supabase.functions.invoke('extract-link-metadata', {
      body: { url, userId, fastOnly: false }
    });

    if (error || !data) {
      const oembedFallback = await fetchYouTubeOEmbedMetadata(url);
      if (oembedFallback) return oembedFallback;
      return buildYouTubeFallbackMetadata(url);
    }

    return {
      title: data.title,
      description: data.description,
      image: data.image,
      previewImagePath: data.previewImagePath,
      previewImagePublicUrl: data.previewImagePublicUrl,
      siteName: data.siteName,
    };
  } catch (error) {
    console.error('Error extracting link metadata for enrichment:', error);
    const oembedFallback = await fetchYouTubeOEmbedMetadata(url);
    if (oembedFallback) return oembedFallback;
    return buildYouTubeFallbackMetadata(url);
  }
};

const getBestImagePath = (metadata: ExtractedLinkMetadata): string | undefined => {
  if (hasValue(metadata.previewImagePath) && !metadata.previewImagePath.startsWith('http')) {
    return metadata.previewImagePath;
  }

  if (hasValue(metadata.previewImagePublicUrl)) {
    return metadata.previewImagePublicUrl;
  }

  if (hasValue(metadata.image)) {
    return metadata.image;
  }

  return undefined;
};

const buildCollectionEmbeddingContent = (
  item: { title?: string | null; content?: string | null; description?: string | null },
  attachments: Array<{ title?: string | null; description?: string | null; url?: string | null; metadata?: any }>
) => {
  const attachmentText = attachments
    .map((attachment) => {
      const metadata = attachment.metadata || {};
      return [
        attachment.title,
        attachment.description,
        attachment.url,
        metadata.siteName,
        metadata.processedContent,
      ]
        .filter((value) => hasValue(value))
        .join(' ');
    })
    .filter((chunk) => chunk.trim().length > 0)
    .join(' ');

  return [
    item.title,
    item.content,
    item.description,
    attachmentText,
  ]
    .filter((value) => hasValue(value))
    .join(' ')
    .trim();
};

const refreshCollectionEmbeddings = async (collectionId: string) => {
  try {
    const { data: collectionItem, error: collectionError } = await supabase
      .from('items')
      .select('title,content,description')
      .eq('id', collectionId)
      .single();

    if (collectionError || !collectionItem) {
      console.error('Unable to refresh collection embeddings (item lookup failed):', collectionError);
      return;
    }

    const { data: attachments, error: attachmentsError } = await supabase
      .from('item_attachments')
      .select('title,description,url,metadata')
      .eq('item_id', collectionId);

    if (attachmentsError) {
      console.error('Unable to refresh collection embeddings (attachments lookup failed):', attachmentsError);
      return;
    }

    const embeddingContent = buildCollectionEmbeddingContent(collectionItem, attachments || []);
    if (!embeddingContent) return;

    await generateEmbeddings(collectionId, embeddingContent);
  } catch (error) {
    console.error('Error refreshing collection embeddings:', error);
  }
};

const scheduleCollectionEmbeddingRefresh = (collectionId: string, delayMs: number = 1500) => {
  const existingTimer = collectionEmbeddingTimers.get(collectionId);
  if (existingTimer) {
    clearTimeout(existingTimer);
  }

  const timer = setTimeout(() => {
    collectionEmbeddingTimers.delete(collectionId);
    void refreshCollectionEmbeddings(collectionId);
  }, delayMs);

  collectionEmbeddingTimers.set(collectionId, timer);
};

const enrichSavedLinkItem = async (
  itemId: string,
  url: string,
  userId: string,
  existing: { title?: string | null; description?: string | null; file_path?: string | null },
  fetchItems: () => Promise<void>
) => {
  const metadata = await extractLinkMetadata(url, userId);
  if (!metadata) return;

  const updates: Record<string, string> = {};
  const nextTitle = hasValue(metadata.title) ? metadata.title : undefined;
  const nextDescription = hasValue(metadata.description) ? metadata.description : undefined;
  const nextFilePath = getBestImagePath(metadata);

  if (nextTitle && nextTitle !== existing.title) {
    updates.title = nextTitle;
  }
  if (nextDescription && nextDescription !== existing.description) {
    updates.description = nextDescription;
  }
  if (nextFilePath && nextFilePath !== existing.file_path) {
    updates.file_path = nextFilePath;
  }

  if (Object.keys(updates).length === 0) {
    return;
  }

  const { error } = await supabase
    .from('items')
    .update(updates)
    .eq('id', itemId);

  if (error) {
    console.error('Error enriching saved link item:', error);
    return;
  }

  await fetchItems();
};

const enrichCollectionLinkAttachment = async (
  attachmentId: string,
  collectionId: string,
  linkUrl: string,
  userId: string,
  existing: { title?: string; description?: string; metadata?: Record<string, unknown> }
) => {
  const metadata = await extractLinkMetadata(linkUrl, userId);
  if (!metadata) return;

  const updates: Record<string, unknown> = {};
  const nextTitle = hasValue(metadata.title) ? metadata.title : undefined;
  const nextDescription = hasValue(metadata.description) ? metadata.description : undefined;
  const nextImage = getBestImagePath(metadata);
  const nextSiteName = hasValue(metadata.siteName) ? metadata.siteName : undefined;

  if (nextTitle && nextTitle !== existing.title) {
    updates.title = nextTitle;
  }
  if (nextDescription && nextDescription !== existing.description) {
    updates.description = nextDescription;
  }

  const existingMetadata = existing.metadata || {};
  const mergedMetadata = {
    ...existingMetadata,
    ...(nextImage ? { image: nextImage } : {}),
    ...(nextSiteName ? { siteName: nextSiteName } : {}),
  };

  if (JSON.stringify(mergedMetadata) !== JSON.stringify(existingMetadata)) {
    updates.metadata = mergedMetadata;
  }

  if (Object.keys(updates).length === 0) return;

  const { error } = await supabase
    .from('item_attachments')
    .update(updates)
    .eq('id', attachmentId);

  if (error) {
    console.error('Error enriching link attachment metadata:', error);
    return;
  }

  scheduleCollectionEmbeddingRefresh(collectionId);
};

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

  if (type === 'link' && data.url) {
    setTimeout(() => {
      void enrichSavedLinkItem(
        insertedItem.id,
        data.url!,
        userId,
        {
          title: insertedItem.title,
          description: insertedItem.description,
          file_path: insertedItem.file_path,
        },
        fetchItems
      );
    }, 0);
  }

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

  // Rebuild collection embeddings from stored item + attachments (and re-run after enrichment updates).
  scheduleCollectionEmbeddingRefresh(insertedItem.id, 500);

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
        attachmentData.title = attachment.title || attachment.name || attachment.url || 'Link';
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

        if (attachment.type === 'link' && attachment.url) {
          setTimeout(() => {
            void enrichCollectionLinkAttachment(
              insertedAttachment.id,
              itemId,
              attachment.url,
              userId,
              {
                title: insertedAttachment.title || attachmentData.title,
                description: insertedAttachment.description || attachmentData.description,
                metadata: (insertedAttachment.metadata as Record<string, unknown>) || attachmentData.metadata,
              }
            );
          }, 0);
        }
      }
    } catch (error) {
      console.error('Error processing attachment:', error);
    }
  }

  return processedAttachments;
};
