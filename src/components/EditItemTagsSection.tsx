
import React from 'react';
import { Button } from '@/components/ui/button';
import { Plus } from 'lucide-react';
import EditItemTagDisplay from '@/components/EditItemTagDisplay';
import EditItemTagInput from '@/components/EditItemTagInput';
import { useEditItemTags } from '@/hooks/useEditItemTags';

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
  onTagsChange?: () => void; // Optional callback for parent to know when tags change
}

const EditItemTagsSection = ({ item, onTagsChange }: EditItemTagsSectionProps) => {
  const {
    itemTags,
    newTags,
    isEditingTags,
    tagSuggestions,
    setNewTags,
    setIsEditingTags,
    handleAddTags,
    handleRemoveTag,
    handleCancelEditing,
  } = useEditItemTags(item, onTagsChange);

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
      <EditItemTagDisplay tags={itemTags} onRemoveTag={handleRemoveTag} />

      {/* Tag Input */}
      {isEditingTags && (
        <EditItemTagInput
          newTags={newTags}
          suggestions={tagSuggestions}
          onTagsChange={setNewTags}
          onAddTags={handleAddTags}
          onCancel={handleCancelEditing}
        />
      )}
    </div>
  );
};

export default EditItemTagsSection;
