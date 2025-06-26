
import React from 'react';
import { Button } from '@/components/ui/button';
import TagInput from '@/components/TagInput';

interface EditItemTagInputProps {
  newTags: string[];
  suggestions: string[];
  onTagsChange: (tags: string[]) => void;
  onAddTags: () => void;
  onCancel: () => void;
}

const EditItemTagInput = ({ 
  newTags, 
  suggestions, 
  onTagsChange, 
  onAddTags, 
  onCancel 
}: EditItemTagInputProps) => {
  return (
    <div className="space-y-3 p-4 bg-muted/30 rounded-lg">
      <TagInput
        tags={newTags}
        onTagsChange={onTagsChange}
        suggestions={suggestions}
        placeholder="Type to add tags..."
        maxTags={5}
      />
      
      <div className="flex gap-2">
        <Button size="sm" onClick={onAddTags} disabled={newTags.length === 0}>
          Add Tags
        </Button>
        <Button size="sm" variant="outline" onClick={onCancel}>
          Cancel
        </Button>
      </div>
    </div>
  );
};

export default EditItemTagInput;
