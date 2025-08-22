
import { generateTempId } from '@/utils/tempIdGenerator';
import type { Database } from '@/integrations/supabase/types';

type ItemType = Database['public']['Enums']['item_type'];

export const createSkeletonItem = (
  type: string,
  data: any,
  userId: string
) => {
  const tempId = generateTempId();
  console.log('Generated temp ID for skeleton:', tempId);
  
  // Generate context-aware loading messages
  const getLoadingState = (type: string, data: any) => {
    switch (type) {
      case 'audio':
        return {
          title: data.title || 'Processing audio...',
          description: 'Transcribing audio...',
          showProgress: true
        };
      case 'image':
        return {
          title: data.title || 'Processing image...',
          description: 'Analyzing image...',
          showProgress: false
        };
      case 'video':
        return {
          title: data.title || 'Processing video...',
          description: 'Processing video...',
          showProgress: true
        };
      case 'text':
        return {
          title: 'Processing note...',
          description: 'Generating title...',
          showProgress: false
        };
      case 'collection':
        const attachmentCount = data.attachments?.length || 0;
        return {
          title: `Processing collection...`,
          description: `Processing ${attachmentCount} item${attachmentCount !== 1 ? 's' : ''}...`,
          showProgress: attachmentCount > 1
        };
      case 'document':
        return {
          title: data.title || 'Processing document...',
          description: 'Extracting text...',
          showProgress: true
        };
      case 'link':
        return {
          title: data.title || 'Processing link...',
          description: 'Extracting metadata...',
          showProgress: false
        };
      default:
        return {
          title: data.title || 'Processing...',
          description: 'Processing...',
          showProgress: false
        };
    }
  };

  const loadingState = getLoadingState(type, data);
  
  return {
    id: tempId,
    user_id: userId,
    type: type as ItemType,
    title: loadingState.title,
    content: null,
    description: loadingState.description,
    url: null,
    file_path: null,
    file_size: data.file?.size || null,
    mime_type: data.file?.type || null,
    created_at: new Date().toISOString(),
    isOptimistic: true,
    showSkeleton: true,
    showProgress: loadingState.showProgress
  };
};
