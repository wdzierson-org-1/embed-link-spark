
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

interface Tag {
  id: string;
  name: string;
  usage_count: number;
}

export const useTags = () => {
  const { user } = useAuth();
  const [tags, setTags] = useState<Tag[]>([]);
  const { toast } = useToast();

  const fetchTags = async () => {
    if (!user) return;
    
    try {
      const { data, error } = await supabase
        .from('tags')
        .select('id, name, usage_count')
        .eq('user_id', user.id)
        .order('usage_count', { ascending: false });

      if (error) {
        console.error('Error fetching tags:', error);
        setTags([]);
      } else {
        setTags(data || []);
      }
    } catch (error) {
      console.error('Exception while fetching tags:', error);
      setTags([]);
    }
  };

  const addTagsToItem = async (itemId: string, tagNames: string[]) => {
    if (!user || tagNames.length === 0) return;

    try {
      // Process each tag and get/create tag IDs
      const tagIds: string[] = [];
      
      for (const tagName of tagNames) {
        const trimmedName = tagName.trim().toLowerCase();
        if (!trimmedName) continue;

        const { data: tagId, error } = await supabase.rpc('increment_tag_usage', {
          tag_name: trimmedName,
          user_uuid: user.id
        });

        if (error) {
          console.error('Error processing tag:', error);
        } else if (tagId) {
          tagIds.push(tagId as string);
        }
      }

      // Create item-tag relationships
      const itemTagData = tagIds.map(tagId => ({
        item_id: itemId,
        tag_id: tagId
      }));

      if (itemTagData.length > 0) {
        const { error: relationError } = await supabase
          .from('item_tags')
          .insert(itemTagData);

        if (relationError) {
          console.error('Error creating item-tag relationships:', relationError);
          throw relationError;
        }
      }

      // Refresh tags list
      await fetchTags();
    } catch (error) {
      console.error('Exception while adding tags to item:', error);
      throw error;
    }
  };

  const getSuggestedTags = (limit: number = 10): string[] => {
    return tags
      .slice(0, limit)
      .map(tag => tag.name);
  };

  const getAISuggestedTags = async (content: { title?: string; content?: string; description?: string }): Promise<string[]> => {
    if (!user) return getSuggestedTags(5);
    
    try {
      const { data, error } = await supabase.functions.invoke('get-relevant-tags', {
        body: {
          title: content.title || '',
          content: content.content || '',
          description: content.description || ''
        }
      });

      if (error) {
        console.error('Error getting AI suggested tags:', error);
        // Fallback to popular tags
        return getSuggestedTags(5);
      }

      return data?.tags || getSuggestedTags(5);
    } catch (error) {
      console.error('Exception getting AI suggested tags:', error);
      // Fallback to popular tags
      return getSuggestedTags(5);
    }
  };

  useEffect(() => {
    if (user) {
      fetchTags();
    }
  }, [user]);

  return {
    tags,
    addTagsToItem,
    getSuggestedTags,
    getAISuggestedTags,
    fetchTags
  };
};
