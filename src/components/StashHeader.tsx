
import React, { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { X, Filter } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

interface Tag {
  id: string;
  name: string;
  usage_count: number;
}

interface StashHeaderProps {
  itemCount: number;
  onTagFiltersChange?: (selectedTags: string[]) => void;
}

const StashHeader = ({ itemCount, onTagFiltersChange }: StashHeaderProps) => {
  const [showTagFilter, setShowTagFilter] = useState(false);
  const [availableTags, setAvailableTags] = useState<Tag[]>([]);
  const [selectedTags, setSelectedTags] = useState<string[]>([]);
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
        setAvailableTags([]);
      } else {
        setAvailableTags(data || []);
      }
    } catch (error) {
      console.error('Exception while fetching tags:', error);
      setAvailableTags([]);
    }
  };

  useEffect(() => {
    if (user && showTagFilter) {
      fetchTags();
    }
  }, [user, showTagFilter]);

  const handleTagToggle = (tagName: string) => {
    const newSelectedTags = selectedTags.includes(tagName)
      ? selectedTags.filter(tag => tag !== tagName)
      : [...selectedTags, tagName];
    
    setSelectedTags(newSelectedTags);
    onTagFiltersChange?.(newSelectedTags);
  };

  const handleClearFilters = () => {
    setSelectedTags([]);
    onTagFiltersChange?.([]);
  };

  const handleHideFilter = () => {
    setShowTagFilter(false);
    setSelectedTags([]);
    onTagFiltersChange?.([]);
  };

  return (
    <div className="mb-6">
      <div className="flex items-center justify-end mb-4">
        <div className="flex items-center gap-4">
          <p className="text-muted-foreground">
            {itemCount} {itemCount === 1 ? 'item' : 'items'}
          </p>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setShowTagFilter(!showTagFilter)}
            className="flex items-center gap-2"
          >
            <Filter className="h-4 w-4" />
            Filter by tag
          </Button>
        </div>
      </div>

      {showTagFilter && (
        <div className="bg-gray-50 border rounded-lg p-4 mb-4">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium">Filter by tags</h3>
            <Button
              variant="ghost"
              size="sm"
              onClick={handleHideFilter}
              className="h-6 w-6 p-0"
            >
              <X className="h-4 w-4" />
            </Button>
          </div>

          {selectedTags.length > 0 && (
            <div className="flex items-center gap-2 mb-3">
              <span className="text-xs text-muted-foreground">Selected:</span>
              {selectedTags.map((tag) => (
                <Badge key={tag} variant="secondary" className="text-xs">
                  {tag}
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 ml-1 hover:bg-transparent"
                    onClick={() => handleTagToggle(tag)}
                  >
                    <X className="h-3 w-3" />
                  </Button>
                </Badge>
              ))}
              <Button
                variant="outline"
                size="sm"
                onClick={handleClearFilters}
                className="h-6 text-xs"
              >
                Clear all
              </Button>
            </div>
          )}

          <div className="space-y-2">
            {availableTags.length === 0 ? (
              <p className="text-sm text-muted-foreground">No tags available</p>
            ) : (
              <div className="flex flex-wrap gap-2">
                {availableTags.map((tag) => (
                  <Button
                    key={tag.id}
                    variant={selectedTags.includes(tag.name) ? "default" : "outline"}
                    size="sm"
                    onClick={() => handleTagToggle(tag.name)}
                    className="h-7 text-xs"
                  >
                    {tag.name} ({tag.usage_count})
                  </Button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default StashHeader;
