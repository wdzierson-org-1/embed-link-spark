
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Plus, X } from 'lucide-react';
import { useTags } from '@/hooks/useTags';
import TagInput from '@/components/TagInput';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';

interface ItemTagsManagerProps {
  itemId: string;
  currentTags: string[];
  onTagsUpdated: () => void;
}

const ItemTagsManager = ({ itemId, currentTags, onTagsUpdated }: ItemTagsManagerProps) => {
  const [isEditing, setIsEditing] = useState(false);
  const [newTags, setNewTags] = useState<string[]>([]);
  const { getSuggestedTags, addTagsToItem } = useTags();
  const { toast } = useToast();

  const handleAddTags = async () => {
    if (newTags.length === 0) {
      setIsEditing(false);
      return;
    }

    try {
      await addTagsToItem(itemId, newTags);
      setNewTags([]);
      setIsEditing(false);
      onTagsUpdated();
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
    try {
      // Get the tag ID
      const { data: tagData, error: tagError } = await supabase
        .from('tags')
        .select('id')
        .eq('name', tagName.toLowerCase())
        .single();

      if (tagError) {
        console.error('Error finding tag:', tagError);
        return;
      }

      // Remove the item-tag relationship
      const { error: relationError } = await supabase
        .from('item_tags')
        .delete()
        .eq('item_id', itemId)
        .eq('tag_id', tagData.id);

      if (relationError) {
        console.error('Error removing tag relationship:', relationError);
        throw relationError;
      }

      onTagsUpdated();
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

  const handleSuggestionClick = (suggestion: string) => {
    if (!newTags.includes(suggestion)) {
      setNewTags([...newTags, suggestion]);
    }
  };

  const handleCancel = () => {
    setNewTags([]);
    setIsEditing(false);
  };

  const suggestions = getSuggestedTags(10).filter(tag => 
    !currentTags.includes(tag) && !newTags.includes(tag)
  );

  if (isEditing) {
    return (
      <div className="space-y-3 p-3 border rounded-md bg-gray-50">
        <div className="flex items-center justify-between">
          <h4 className="text-sm font-medium">Add Tags</h4>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleCancel}
            className="h-6 w-6 p-0"
          >
            <X className="h-3 w-3" />
          </Button>
        </div>
        
        {/* Current tags with remove option */}
        {currentTags.length > 0 && (
          <div className="space-y-2">
            <p className="text-xs font-medium text-muted-foreground">Current tags:</p>
            <div className="flex flex-wrap gap-1">
              {currentTags.map((tag, index) => (
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
          </div>
        )}
        
        <TagInput
          tags={newTags}
          onTagsChange={setNewTags}
          suggestions={[]}
          placeholder="Type to add tags..."
          maxTags={5}
        />
        
        {/* Suggested tags */}
        {suggestions.length > 0 && (
          <div className="space-y-2">
            <p className="text-xs font-medium text-muted-foreground">Suggested:</p>
            <div className="flex flex-wrap gap-1">
              {suggestions.map((suggestion, index) => (
                <Button
                  key={index}
                  variant="outline"
                  size="sm"
                  className="h-6 text-xs"
                  onClick={() => handleSuggestionClick(suggestion)}
                >
                  {suggestion}
                </Button>
              ))}
            </div>
          </div>
        )}
        
        <div className="flex gap-2">
          <Button size="sm" onClick={handleAddTags}>
            Add to Note
          </Button>
          <Button size="sm" variant="outline" onClick={handleCancel}>
            Cancel
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2 flex-wrap">
      {currentTags.map((tag, index) => (
        <Badge key={index} variant="outline" className="text-xs">
          {tag}
        </Badge>
      ))}
      <Button
        variant="outline"
        size="sm"
        onClick={() => setIsEditing(true)}
        className="h-6 text-xs"
      >
        <Plus className="h-3 w-3 mr-1" />
        Add tags
      </Button>
    </div>
  );
};

export default ItemTagsManager;
