
import React, { useState, useEffect } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { X, Plus, Check } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { getSuggestedTags } from '@/utils/aiOperations';

interface ItemTagsManagerProps {
  itemId: string;
  currentTags: string[];
  onTagsUpdated: () => void;
  itemContent: {
    title?: string;
    content?: string;
    description?: string;
  };
}

const ItemTagsManager = ({ itemId, currentTags, onTagsUpdated, itemContent }: ItemTagsManagerProps) => {
  const { user } = useAuth();
  const [isEditing, setIsEditing] = useState(false);
  const [newTags, setNewTags] = useState<string[]>([]);
  const [inputValue, setInputValue] = useState('');
  const [tagSuggestions, setTagSuggestions] = useState<string[]>([]);
  const [itemTags, setItemTags] = useState<string[]>(currentTags);

  useEffect(() => {
    setItemTags(currentTags);
  }, [currentTags]);

  useEffect(() => {
    if (isEditing) {
      fetchTagSuggestions();
    }
  }, [isEditing]);

  const fetchTagSuggestions = async () => {
    if (!user) return;
    
    const content = [itemContent.title, itemContent.content, itemContent.description]
      .filter(Boolean)
      .join(' ');
    
    if (content.trim()) {
      try {
        const suggestions = await getSuggestedTags(content);
        // Filter out tags that are already applied
        const filteredSuggestions = suggestions.filter(
          suggestion => !itemTags.includes(suggestion)
        );
        setTagSuggestions(filteredSuggestions);
      } catch (error) {
        console.error('Error fetching tag suggestions:', error);
        setTagSuggestions([]);
      }
    }
  };

  const handleAddTag = (tagName: string) => {
    if (tagName.trim() && !newTags.includes(tagName.trim()) && !itemTags.includes(tagName.trim())) {
      setNewTags([...newTags, tagName.trim()]);
      setInputValue('');
    }
  };

  const handleRemoveNewTag = (tagToRemove: string) => {
    setNewTags(newTags.filter(tag => tag !== tagToRemove));
  };

  const handleSaveTags = async () => {
    if (!user || newTags.length === 0) {
      setIsEditing(false);
      setNewTags([]);
      return;
    }

    try {
      // Add new tags to the item
      for (const tagName of newTags) {
        // First, create or get the tag
        const { data: existingTag, error: tagError } = await supabase
          .from('tags')
          .select('id, usage_count')
          .eq('name', tagName)
          .eq('user_id', user.id)
          .single();

        let tagId;
        if (tagError && tagError.code === 'PGRST116') {
          // Tag doesn't exist, create it
          const { data: newTag, error: createError } = await supabase
            .from('tags')
            .insert({
              name: tagName,
              user_id: user.id,
              usage_count: 1
            })
            .select('id')
            .single();

          if (createError) {
            console.error('Error creating tag:', createError);
            continue;
          }
          tagId = newTag.id;
        } else if (existingTag) {
          tagId = existingTag.id;
          // Increment usage count
          await supabase
            .from('tags')
            .update({ usage_count: existingTag.usage_count + 1 })
            .eq('id', tagId);
        } else {
          console.error('Error fetching tag:', tagError);
          continue;
        }

        // Add the tag to the item
        await supabase
          .from('item_tags')
          .insert({
            item_id: itemId,
            tag_id: tagId
          });
      }

      // Update local state
      setItemTags([...itemTags, ...newTags]);
      setNewTags([]);
      setIsEditing(false);
      onTagsUpdated();
    } catch (error) {
      console.error('Error saving tags:', error);
    }
  };

  const handleRemoveTag = async (tagName: string) => {
    if (!user) return;

    try {
      // Get the tag
      const { data: tag, error: tagError } = await supabase
        .from('tags')
        .select('id, usage_count')
        .eq('name', tagName)
        .eq('user_id', user.id)
        .single();

      if (tagError || !tag) {
        console.error('Error finding tag:', tagError);
        return;
      }

      // Remove the tag from the item
      await supabase
        .from('item_tags')
        .delete()
        .eq('item_id', itemId)
        .eq('tag_id', tag.id);

      // Decrement usage count
      await supabase
        .from('tags')
        .update({ usage_count: Math.max(0, tag.usage_count - 1) })
        .eq('id', tag.id);

      // Update local state
      setItemTags(itemTags.filter(t => t !== tagName));
      onTagsUpdated();
    } catch (error) {
      console.error('Error removing tag:', error);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && inputValue.trim()) {
      handleAddTag(inputValue);
    }
  };

  const handleSuggestionClick = (suggestion: string) => {
    handleAddTag(suggestion);
  };

  return (
    <div className="space-y-2">
      {/* Current tags */}
      <div className="flex flex-wrap gap-1">
        {itemTags.map((tag) => (
          <Badge key={tag} variant="secondary" className="text-xs">
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
        
        {/* Add tags button */}
        {!isEditing && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => setIsEditing(true)}
            className="h-5 px-2 text-xs lowercase opacity-70 hover:opacity-100"
          >
            <Plus className="h-3 w-3 mr-1" />
            add tags
          </Button>
        )}
      </div>

      {/* New tags being added */}
      {newTags.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {newTags.map((tag) => (
            <Badge key={tag} variant="default" className="text-xs">
              {tag}
              <Button
                variant="ghost"
                size="sm"
                className="h-auto p-0 ml-1 hover:bg-transparent"
                onClick={() => handleRemoveNewTag(tag)}
              >
                <X className="h-3 w-3" />
              </Button>
            </Badge>
          ))}
        </div>
      )}

      {/* Tag input */}
      {isEditing && (
        <div className="space-y-2">
          <div className="flex gap-2">
            <Input
              type="text"
              placeholder="Add tags..."
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              onKeyPress={handleKeyPress}
              className="h-8 text-xs"
              autoFocus
            />
            <Button
              size="sm"
              onClick={handleSaveTags}
              className="h-8 px-2"
            >
              <Check className="h-3 w-3" />
            </Button>
          </div>
          
          {/* Tag suggestions */}
          {tagSuggestions.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {tagSuggestions.slice(0, 5).map((suggestion) => (
                <Button
                  key={suggestion}
                  variant="outline"
                  size="sm"
                  onClick={() => handleSuggestionClick(suggestion)}
                  className="h-6 px-2 text-xs"
                >
                  {suggestion}
                </Button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default ItemTagsManager;
