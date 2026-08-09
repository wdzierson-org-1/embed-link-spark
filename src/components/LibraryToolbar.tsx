import React from 'react';
import { Search, X } from 'lucide-react';

export type LibraryTypeFilter = 'all' | 'link' | 'note' | 'doc' | 'media';

const FILTERS: Array<{ key: LibraryTypeFilter; label: string }> = [
  { key: 'all', label: 'All' },
  { key: 'link', label: 'Links' },
  { key: 'note', label: 'Notes' },
  { key: 'doc', label: 'Docs' },
  { key: 'media', label: 'Media' },
];

interface LibraryToolbarProps {
  searchQuery: string;
  onSearchChange: (value: string) => void;
  typeFilter: LibraryTypeFilter;
  onTypeFilterChange: (filter: LibraryTypeFilter) => void;
  itemCount: number;
}

const LibraryToolbar = ({
  searchQuery,
  onSearchChange,
  typeFilter,
  onTypeFilterChange,
  itemCount,
}: LibraryToolbarProps) => (
  <div className="container mx-auto flex flex-wrap items-center gap-3 px-4 pb-4 pt-5">
    <div className="flex min-w-0 flex-1 basis-64 items-center gap-2 rounded-full border border-black/10 bg-white/75 px-4 py-2 sm:max-w-[340px]">
      <Search className="h-4 w-4 flex-none text-gray-400" />
      <input
        value={searchQuery}
        onChange={(e) => onSearchChange(e.target.value)}
        placeholder="Search your stash..."
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

    <div className="flex items-center gap-2">
      {FILTERS.map(({ key, label }) => (
        <button
          key={key}
          onClick={() => onTypeFilterChange(key)}
          className={`rounded-full border px-3 py-1.5 text-xs transition-colors ${
            typeFilter === key
              ? 'border-gray-900 bg-gray-900 text-white'
              : 'border-black/10 bg-white/65 text-gray-600 hover:bg-white'
          }`}
        >
          {label}
        </button>
      ))}
    </div>

    <span className="ml-auto hidden text-[13px] text-gray-400 sm:block">
      {itemCount} {itemCount === 1 ? 'item' : 'items'}
    </span>
  </div>
);

export default LibraryToolbar;
