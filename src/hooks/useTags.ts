
import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

interface Tag {
  id: string;
  name: string;
  usage_count: number;
}

export const useTags = () => {
  const [tags, setTags] = useState<Tag[]>([]);
  const { user } = useAuth();

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
    if (!user) return;

    console.log('Adding tags to item in database:', { itemId, tagNames });

    for (const tagName of tagNames) {
      try {
        // Use the increment_tag_usage function to create or update tag
        const { data: tagId, error: tagError } = await supabase
          .rpc('increment_tag_usage', {
            tag_name: tagName.toLowerCase(),
            user_uuid: user.id
          });

        if (tagError) {
          console.error('Error creating/updating tag:', tagError);
          continue;
        }

        console.log('Tag created/updated:', { tagName, tagId });

        // Check if the relationship already exists
        const { data: existingRelation, error: checkError } = await supabase
          .from('item_tags')
          .select('id')
          .eq('item_id', itemId)
          .eq('tag_id', tagId)
          .single();

        if (checkError && checkError.code !== 'PGRST116') {
          console.error('Error checking existing relation:', checkError);
          continue;
        }

        // Only create the relationship if it doesn't exist
        if (!existingRelation) {
          const { error: relationError } = await supabase
            .from('item_tags')
            .insert({
              item_id: itemId,
              tag_id: tagId
            });

          if (relationError) {
            console.error('Error creating item-tag relation:', relationError);
            continue;
          }

          console.log('Item-tag relation created:', { itemId, tagId, tagName });
        } else {
          console.log('Item-tag relation already exists:', { itemId, tagId, tagName });
        }
      } catch (error) {
        console.error('Exception while adding tag:', tagName, error);
      }
    }

    // Refresh tags after adding
    await fetchTags();
  };

  const getSuggestedTags = (limit: number = 10) => {
    return tags
      .sort((a, b) => b.usage_count - a.usage_count)
      .slice(0, limit)
      .map(tag => tag.name);
  };

  const getAISuggestedTags = async (content: { title: string; content: string; description: string }) => {
    if (!user) return [];

    try {
      // Get all available tag names from user's existing tags
      const availableTags = tags.map(tag => tag.name);
      
      if (availableTags.length === 0) {
        return [];
      }

      // Call the get-relevant-tags function with the item content and available tags
      const { data: result, error } = await supabase.functions.invoke('get-relevant-tags', {
        body: {
          title: content.title || '',
          content: content.content || '',
          description: content.description || '',
          availableTags: availableTags
        }
      });

      if (error) {
        console.error('Error getting AI tag suggestions:', error);
        return [];
      }
      
      return result?.relevantTags || [];
    } catch (error) {
      console.error('Error fetching AI tag suggestions:', error);
      return [];
    }
  };

  useEffect(() => {
    if (user) {
      fetchTags();
    }
  }, [user]);

  return {
    tags,
    fetchTags,
    addTagsToItem,
    getSuggestedTags,
    getAISuggestedTags,
  };
};
