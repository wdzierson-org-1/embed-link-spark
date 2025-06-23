
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Plus, X } from 'lucide-react';
import { useTags } from '@/hooks/useTags';
import TagInput from '@/components/TagInput';
import { useToast } from '@/hooks/use-toast';

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

  const handleCancel = () => {
    setNewTags([]);
    setIsEditing(false);
  };

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
        
        <TagInput
          tags={newTags}
          onTagsChange={setNewTags}
          suggestions={getSuggestedTags(10)}
          placeholder="Type to add tags..."
          maxTags={5}
        />
        
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
