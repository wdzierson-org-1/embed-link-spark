
import { useState, useEffect } from 'react';
import { useToast } from '@/hooks/use-toast';
import { useTags } from '@/hooks/useTags';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

export const useEditItemTags = (item: ContentItem | null, onTagsChange?: () => void) => {
  const [itemTags, setItemTags] = useState<string[]>([]);
  const [newTags, setNewTags] = useState<string[]>([]);
  const [isEditingTags, setIsEditingTags] = useState(false);
  const [tagSuggestions, setTagSuggestions] = useState<string[]>([]);
  const { toast } = useToast();
  const { user } = useAuth();
  const { addTagsToItem, fetchTags, getSuggestedTags, getAISuggestedTags } = useTags();

  useEffect(() => {
    if (item) {
      fetchItemTags();
      loadTagSuggestions();
    }
  }, [item]);

  const loadTagSuggestions = async () => {
    if (!item) return;
    
    try {
      // Get AI-suggested tags based on content
      const aiSuggestions = await getAISuggestedTags({
        title: item.title || '',
        content: item.content || '',
        description: item.description || ''
      });
      
      // Get popular tags from user's existing tags
      const popularTags = getSuggestedTags(10);
      
      // Combine and deduplicate, prioritizing AI suggestions
      const allSuggestions = [...new Set([...aiSuggestions, ...popularTags])];
      
      // Filter out tags that are already applied to this item
      const filteredSuggestions = allSuggestions.filter(tag => 
        !itemTags.includes(tag.toLowerCase())
      );
      
      setTagSuggestions(filteredSuggestions.slice(0, 10)); // Limit to 10 suggestions
    } catch (error) {
      console.error('Error loading tag suggestions:', error);
      // Fallback to popular tags only
      const popularTags = getSuggestedTags(10);
      const filteredSuggestions = popularTags.filter(tag => 
        !itemTags.includes(tag.toLowerCase())
      );
      setTagSuggestions(filteredSuggestions);
    }
  };

  const fetchItemTags = async () => {
    if (!item || !user) return;
    
    try {
      console.log('Fetching tags for item:', item.id);
      const { data, error } = await supabase
        .from('item_tags')
        .select(`
          tags!inner(name)
        `)
        .eq('item_id', item.id);

      if (error) {
        console.error('Error fetching item tags:', error);
        setItemTags([]);
      } else {
        const tagNames = data?.map(row => row.tags.name) || [];
        console.log('Fetched tags for item:', item.id, tagNames);
        setItemTags(tagNames);
      }
    } catch (error) {
      console.error('Exception fetching item tags:', error);
      setItemTags([]);
    }
  };

  const handleAddTags = async () => {
    if (!item || newTags.length === 0) return;

    try {
      console.log('Adding tags to item:', item.id, newTags);
      await addTagsToItem(item.id, newTags);
      setNewTags([]);
      setIsEditingTags(false);
      await fetchItemTags();
      await fetchTags();
      // Reload suggestions after adding tags
      await loadTagSuggestions();
      
      // Notify parent component about tag changes for auto-save
      if (onTagsChange) {
        onTagsChange();
      }
      
      console.log('Successfully added tags to item:', item.id);
    } catch (error) {
      console.error('Error adding tags:', error);
      toast({
        title: "Error",
        description: "Failed to add tags",
        variant: "destructive",
      });
    }
  };

  const handleRemoveTag = async (tagName: string) => {
    if (!item) return;
    
    try {
      console.log('Removing tag from item:', item.id, tagName);
      
      const { data: tagData, error: tagError } = await supabase
        .from('tags')
        .select('id')
        .eq('name', tagName.toLowerCase())
        .eq('user_id', user?.id)
        .single();

      if (tagError) throw tagError;

      const { error: relationError } = await supabase
        .from('item_tags')
        .delete()
        .eq('item_id', item.id)
        .eq('tag_id', tagData.id);

      if (relationError) throw relationError;

      await fetchItemTags();
      await fetchTags();
      // Reload suggestions after removing tags
      await loadTagSuggestions();
      
      // Notify parent component about tag changes for auto-save
      if (onTagsChange) {
        onTagsChange();
      }
      
      console.log('Successfully removed tag from item:', item.id, tagName);
    } catch (error) {
      console.error('Error removing tag:', error);
      toast({
        title: "Error",
        description: "Failed to remove tag",
        variant: "destructive",
      });
    }
  };

  const handleCancelEditing = () => {
    setIsEditingTags(false);
    setNewTags([]);
  };

  return {
    itemTags,
    newTags,
    isEditingTags,
    tagSuggestions,
    setNewTags,
    setIsEditingTags,
    handleAddTags,
    handleRemoveTag,
    handleCancelEditing,
  };
};
