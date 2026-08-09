import React from 'react';
import { Search, X, Tag, Check, ChevronDown } from 'lucide-react';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';

interface TagOption {
  name: string;
  usage_count: number;
}

interface LibraryToolbarProps {
  searchQuery: string;
  onSearchChange: (value: string) => void;
  itemCount: number;
  tags: TagOption[];
  selectedTags: string[];
  onTagFilterChange: (tags: string[]) => void;
}

const LibraryToolbar = ({
  searchQuery,
  onSearchChange,
  itemCount,
  tags,
  selectedTags,
  onTagFilterChange,
}: LibraryToolbarProps) => {
  const toggleTag = (name: string) => {
    onTagFilterChange(
      selectedTags.includes(name)
        ? selectedTags.filter(tag => tag !== name)
        : [...selectedTags, name]
    );
  };

  return (
    <div className="container mx-auto flex flex-wrap items-center gap-3 px-4 pb-4 pt-4">
      {tags.length > 0 && (
        <Popover>
          <PopoverTrigger asChild>
            <button
              className={`flex items-center gap-1.5 rounded-full border px-3.5 py-2 text-[13px] shadow-[0_1px_2px_rgba(0,0,0,0.05)] transition-colors ${
                selectedTags.length > 0
                  ? 'border-violet-300 bg-violet-50 text-violet-700'
                  : 'border-black/10 bg-white/80 text-gray-600 hover:bg-white'
              }`}
            >
              <Tag className="h-3.5 w-3.5" />
              {selectedTags.length > 0 ? `Tags · ${selectedTags.length}` : 'Filter by tag'}
              <ChevronDown className="h-3 w-3 opacity-60" />
            </button>
          </PopoverTrigger>
          <PopoverContent align="start" className="w-60 rounded-xl p-2 shadow-xl">
            <div className="max-h-64 overflow-y-auto">
              {tags.map(tag => {
                const active = selectedTags.includes(tag.name);
                return (
                  <button
                    key={tag.name}
                    onClick={() => toggleTag(tag.name)}
                    className={`flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-left text-sm transition-colors ${
                      active ? 'bg-violet-50 text-violet-700' : 'hover:bg-muted'
                    }`}
                  >
                    <span className={`grid h-4 w-4 place-items-center rounded border ${active ? 'border-violet-400 bg-violet-500 text-white' : 'border-black/15'}`}>
                      {active && <Check className="h-3 w-3" />}
                    </span>
                    <span className="min-w-0 flex-1 truncate">{tag.name}</span>
                    <span className="text-xs text-muted-foreground">{tag.usage_count}</span>
                  </button>
                );
              })}
            </div>
            {selectedTags.length > 0 && (
              <button
                onClick={() => onTagFilterChange([])}
                className="mt-1 w-full rounded-lg px-2.5 py-1.5 text-left text-xs text-muted-foreground hover:bg-muted"
              >
                Clear filters
              </button>
            )}
          </PopoverContent>
        </Popover>
      )}

      {selectedTags.map(tag => (
        <button
          key={tag}
          onClick={() => toggleTag(tag)}
          className="flex items-center gap-1 rounded-full bg-gray-900 px-3 py-1.5 text-xs text-white shadow-sm"
        >
          {tag}
          <X className="h-3 w-3 opacity-70" />
        </button>
      ))}

      <span className="hidden text-[13px] text-gray-400 sm:block">
        {itemCount} {itemCount === 1 ? 'item' : 'items'}
      </span>

      <div className="ml-auto flex min-w-0 basis-56 items-center gap-2 rounded-full border border-black/10 bg-white/80 px-4 py-2 shadow-[0_1px_2px_rgba(0,0,0,0.05)] sm:max-w-[300px]">
        <Search className="h-4 w-4 flex-none text-gray-400" />
        <input
          value={searchQuery}
          onChange={(e) => onSearchChange(e.target.value)}
          placeholder="Search by keyword"
          className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-gray-400"
        />
        {searchQuery && (
          <button
            onClick={() => onSearchChange('')}
            className="grid h-5 w-5 flex-none place-items-center rounded-full text-gray-400 hover:bg-gray-100"
            aria-label="Clear search"
          >
            <X className="h-3 w-3" />
          </button>
        )}
      </div>
    </div>
  );
};

export default LibraryToolbar;
