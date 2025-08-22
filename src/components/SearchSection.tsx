import React from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Search, X, MessageSquare } from 'lucide-react';
import StashHeader from '@/components/StashHeader';

interface SearchSectionProps {
  isSearchActive: boolean;
  searchQuery: string;
  onSearchClick: () => void;
  onSearchClear: () => void;
  onSearchChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onShowGlobalChat: () => void;
  itemCount: number;
  tags: any[];
  selectedTags: string[];
  onTagFilterChange: (tags: string[]) => void;
  showStickyNotes?: boolean;
  onStickyNotesToggle?: (show: boolean) => void;
}

const SearchSection = ({
  isSearchActive,
  searchQuery,
  onSearchClick,
  onSearchClear,
  onSearchChange,
  onShowGlobalChat,
  itemCount,
  tags,
  selectedTags,
  onTagFilterChange,
  showStickyNotes = true,
  onStickyNotesToggle
}: SearchSectionProps) => {
  return (
    <div className="container mx-auto px-4 pt-3 pb-2 bg-white">
      {/* Mobile: Stack search/assistant on one line, filter on next line */}
      {/* Desktop: Keep all on one line initially, filter expands below */}
      <div className="flex flex-col gap-3 mb-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 flex-1 min-w-0">
            {!isSearchActive ? (
              <Button
                variant="outline"
                size="sm"
                onClick={onSearchClick}
                className="flex items-center gap-2 bg-white border-gray-300 hover:bg-gray-50 transition-all duration-200 shrink-0 relative z-50"
              >
                <Search className="h-4 w-4" />
                <span className="hidden sm:inline">Search notes</span>
                <span className="sm:hidden">Search</span>
              </Button>
            ) : (
              <div className="flex items-center gap-2 animate-in slide-in-from-left-2 duration-200 flex-1 min-w-0">
                <div className="relative flex items-center border border-gray-300 rounded-md bg-white px-3 py-2 flex-1 min-w-0 max-w-64">
                  <Search className="h-4 w-4 text-gray-400 mr-2 shrink-0" />
                  <Input
                    value={searchQuery}
                    onChange={onSearchChange}
                    placeholder="Search notes..."
                    className="border-0 p-0 h-auto focus-visible:ring-0 focus-visible:ring-offset-0 min-w-0"
                    autoFocus
                  />
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={onSearchClear}
                    className="h-6 w-6 p-0 ml-2 hover:bg-gray-100 shrink-0"
                  >
                    <X className="h-3 w-3" />
                  </Button>
                </div>
              </div>
            )}
            
            <Button
              variant="outline"
              size="sm"
              onClick={onShowGlobalChat}
              className="flex items-center gap-2 bg-white border-gray-300 hover:bg-gray-50 transition-all duration-200 shrink-0 relative z-50"
            >
              <MessageSquare className="h-4 w-4" />
              <span className="hidden sm:inline">Stash assistant</span>
              <span className="sm:hidden">Assistant</span>
            </Button>
          </div>

          {/* Desktop: Show filter button on the right */}
          <div className="hidden sm:block">
            <StashHeader 
              onShowGlobalChat={onShowGlobalChat}
              itemCount={itemCount}
              tags={tags}
              selectedTags={selectedTags}
              onTagFilterChange={onTagFilterChange}
              showStickyNotes={showStickyNotes}
              onStickyNotesToggle={onStickyNotesToggle}
            />
          </div>
        </div>

        {/* Mobile: Show filter button on separate line */}
        <div className="sm:hidden">
          <StashHeader 
            onShowGlobalChat={onShowGlobalChat}
            itemCount={itemCount}
            tags={tags}
            selectedTags={selectedTags}
            onTagFilterChange={onTagFilterChange}
            showStickyNotes={showStickyNotes}
            onStickyNotesToggle={onStickyNotesToggle}
          />
        </div>
      </div>
    </div>
  );
};

export default SearchSection;
