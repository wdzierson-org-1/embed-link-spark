
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
  onTagFilterChange
}: SearchSectionProps) => {
  return (
    <div className="container mx-auto px-4 pt-3 pb-2 bg-white">
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-4">
          {!isSearchActive ? (
            <Button
              variant="outline"
              size="sm"
              onClick={onSearchClick}
              className="flex items-center gap-2 bg-white border-gray-300 hover:bg-gray-50 transition-all duration-200"
            >
              <Search className="h-4 w-4" />
              Search notes
            </Button>
          ) : (
            <div className="flex items-center gap-2 animate-in slide-in-from-left-2 duration-200">
              <div className="relative flex items-center border border-gray-300 rounded-md bg-white px-3 py-2 w-64">
                <Search className="h-4 w-4 text-gray-400 mr-2" />
                <Input
                  value={searchQuery}
                  onChange={onSearchChange}
                  placeholder="Search notes..."
                  className="border-0 p-0 h-auto focus-visible:ring-0 focus-visible:ring-offset-0"
                  autoFocus
                />
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={onSearchClear}
                  className="h-6 w-6 p-0 ml-2 hover:bg-gray-100"
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
            className="flex items-center gap-2 bg-white border-gray-300 hover:bg-gray-50 transition-all duration-200"
          >
            <MessageSquare className="h-4 w-4" />
            Noodle assistant
          </Button>
        </div>
        <StashHeader 
          onShowGlobalChat={onShowGlobalChat}
          itemCount={itemCount}
          tags={tags}
          selectedTags={selectedTags}
          onTagFilterChange={onTagFilterChange}
        />
      </div>
    </div>
  );
};

export default SearchSection;
