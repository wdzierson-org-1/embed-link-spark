
import React, { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Plus, X } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useTags } from '@/hooks/useTags';
import TagInput from '@/components/TagInput';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { getSuggestedTags as getSuggestedTagsFromApi } from '@/utils/aiOperations';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface EditItemTagsSectionProps {
  item: ContentItem | null;
}

const EditItemTagsSection = ({ item }: EditItemTagsSectionProps) => {
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
      await addTagsToItem(item.id, newTags);
      setNewTags([]);
      setIsEditingTags(false);
      await fetchItemTags();
      await fetchTags();
      // Reload suggestions after adding tags
      await loadTagSuggestions();
      toast({
        title: "Success",
        description: `Added ${newTags.length} tag(s) to item`,
      });
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
      const { data: tagData, error: tagError } = await supabase
        .from('tags')
        .select('id')
        .eq('name', tagName.toLowerCase())
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
      toast({
        title: "Success",
        description: "Tag removed from item",
      });
    } catch (error) {
      console.error('Error removing tag:', error);
      toast({
        title: "Error",
        description: "Failed to remove tag",
        variant: "destructive",
      });
    }
  };

  if (!item) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-muted-foreground">Tags</label>
        {!isEditingTags && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setIsEditingTags(true)}
            className="h-auto p-1 text-xs"
          >
            <Plus className="h-3 w-3 mr-1" />
            Add tags
          </Button>
        )}
      </div>

      {/* Current Tags */}
      {itemTags.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {itemTags.map((tag, index) => (
            <Badge key={index} variant="secondary" className="text-xs">
              {tag}
              <Button
                variant="ghost"
                size="sm"
                className="h-auto p-0 ml-1 hover:bg-transparent"
                onClick={() => handleRemoveTag(tag)}
              >
                <X className="h-3 w-3" />
              </Button>
            </Badge>
          ))}
        </div>
      )}

      {/* Tag Input */}
      {isEditingTags && (
        <div className="space-y-3 p-4 bg-muted/30 rounded-lg">
          <TagInput
            tags={newTags}
            onTagsChange={setNewTags}
            suggestions={tagSuggestions}
            placeholder="Type to add tags..."
            maxTags={5}
          />
          
          <div className="flex gap-2">
            <Button size="sm" onClick={handleAddTags} disabled={newTags.length === 0}>
              Add Tags
            </Button>
            <Button 
              size="sm" 
              variant="outline" 
              onClick={() => {
                setIsEditingTags(false);
                setNewTags([]);
              }}
            >
              Cancel
            </Button>
          </div>
        </div>
      )}
    </div>
  );
};

export default EditItemTagsSection;
