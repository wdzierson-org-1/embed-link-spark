
import React from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Plus } from 'lucide-react';

interface EditItemTagSuggestionsProps {
  suggestions: string[];
  onAddTag: (tag: string) => void;
  existingTags: string[];
}

const EditItemTagSuggestions = ({ 
  suggestions, 
  onAddTag, 
  existingTags 
}: EditItemTagSuggestionsProps) => {
  const filteredSuggestions = suggestions.filter(
    suggestion => !existingTags.includes(suggestion.toLowerCase())
  );

  if (filteredSuggestions.length === 0) {
    return null;
  }

  return (
    <div className="space-y-2">
      <label className="text-xs font-medium text-muted-foreground">
        Suggested Tags
      </label>
      <div className="flex flex-wrap gap-1">
        {filteredSuggestions.slice(0, 6).map((suggestion) => (
          <Button
            key={suggestion}
            variant="outline"
            size="sm"
            onClick={() => onAddTag(suggestion)}
            className="h-6 px-2 text-xs flex items-center gap-1"
          >
            <Plus className="h-3 w-3" />
            {suggestion}
          </Button>
        ))}
      </div>
    </div>
  );
};

export default EditItemTagSuggestions;
