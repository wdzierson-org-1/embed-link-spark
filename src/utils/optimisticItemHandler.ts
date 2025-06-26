
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
  
  return {
    id: tempId,
    user_id: userId,
    type: type as ItemType,
    title: data.title || 'Processing...',
    content: null,
    description: 'Processing...',
    url: null,
    file_path: null,
    file_size: data.file?.size || null,
    mime_type: data.file?.type || null,
    created_at: new Date().toISOString(),
    isOptimistic: true,
    showSkeleton: true
  };
};
