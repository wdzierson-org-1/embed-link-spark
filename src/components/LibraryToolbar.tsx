import React, { useEffect, useRef, useState } from 'react';
import { Search, X, Tag, Check, ChevronDown, Clock } from 'lucide-react';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';

const RECENT_SEARCHES_KEY = 'stash_recent_searches';
const MAX_RECENT = 5;

const loadRecentSearches = (): string[] => {
  try {
    const raw = localStorage.getItem(RECENT_SEARCHES_KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed.filter(s => typeof s === 'string') : [];
  } catch {
    return [];
  }
};

const persistRecentSearches = (searches: string[]) => {
  try {
    localStorage.setItem(RECENT_SEARCHES_KEY, JSON.stringify(searches));
  } catch {
    // Session-only is fine
  }
};

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
  const [isSearchFocused, setIsSearchFocused] = useState(false);
  const [recentSearches, setRecentSearches] = useState<string[]>(loadRecentSearches);
  const searchWrapRef = useRef<HTMLDivElement>(null);
  const searchInputRef = useRef<HTMLInputElement>(null);
  const commitTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const rememberSearch = (query: string) => {
    const trimmed = query.trim();
    if (trimmed.length < 2) return;
    setRecentSearches(prev => {
      const next = [trimmed, ...prev.filter(s => s.toLowerCase() !== trimmed.toLowerCase())].slice(0, MAX_RECENT);
      persistRecentSearches(next);
      return next;
    });
  };

  // A search "counts" as recent once the user pauses on it
  useEffect(() => {
    if (commitTimerRef.current) clearTimeout(commitTimerRef.current);
    if (!searchQuery.trim()) return;
    commitTimerRef.current = setTimeout(() => rememberSearch(searchQuery), 1600);
    return () => {
      if (commitTimerRef.current) clearTimeout(commitTimerRef.current);
    };
  }, [searchQuery]);

  useEffect(() => {
    const onMouseDown = (e: MouseEvent) => {
      if (!searchWrapRef.current?.contains(e.target as Node)) {
        setIsSearchFocused(false);
      }
    };
    window.addEventListener('mousedown', onMouseDown);
    return () => window.removeEventListener('mousedown', onMouseDown);
  }, []);

  const showRecents = isSearchFocused && !searchQuery && recentSearches.length > 0;

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

      <div ref={searchWrapRef} className="relative ml-auto min-w-0 basis-56 sm:max-w-[320px]">
        <div
          onClick={() => { setIsSearchFocused(true); searchInputRef.current?.focus(); }}
          className={`flex cursor-text items-center gap-2 rounded-full border px-4 py-2 transition-all duration-200 ${
            isSearchFocused
              ? 'border-violet-300 bg-white shadow-[0_2px_6px_rgba(0,0,0,0.06),0_10px_28px_rgba(139,92,246,0.16)] ring-2 ring-violet-200/60'
              : 'border-black/10 bg-white/80 shadow-[0_1px_2px_rgba(0,0,0,0.05)] hover:bg-white'
          }`}
        >
          <Search className={`h-4 w-4 flex-none transition-colors ${isSearchFocused ? 'text-violet-500' : 'text-gray-400'}`} />
          <input
            ref={searchInputRef}
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            onFocus={() => setIsSearchFocused(true)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') rememberSearch(searchQuery);
              if (e.key === 'Escape') { setIsSearchFocused(false); searchInputRef.current?.blur(); }
            }}
            placeholder="Search by keyword"
            className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-gray-400"
          />
          {searchQuery && (
            <button
              onClick={() => { onSearchChange(''); searchInputRef.current?.focus(); }}
              className="grid h-5 w-5 flex-none place-items-center rounded-full text-gray-400 hover:bg-gray-100"
              aria-label="Clear search"
            >
              <X className="h-3 w-3" />
            </button>
          )}
        </div>

        {showRecents && (
          <div className="absolute left-0 right-0 top-full z-30 mt-2 animate-in fade-in zoom-in-95 duration-150 rounded-2xl border border-black/5 bg-white p-1.5 shadow-[0_12px_36px_rgba(40,20,60,0.16),0_2px_8px_rgba(0,0,0,0.06)]">
            <div className="px-2.5 pb-1 pt-1.5 text-[11px] font-medium uppercase tracking-wide text-gray-400">
              Recent searches
            </div>
            {recentSearches.map(recent => (
              <button
                key={recent}
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => { onSearchChange(recent); rememberSearch(recent); searchInputRef.current?.focus(); }}
                className="flex w-full items-center gap-2.5 rounded-xl px-2.5 py-2 text-left text-sm text-gray-700 transition-colors hover:bg-violet-50"
              >
                <Clock className="h-3.5 w-3.5 flex-none text-gray-300" />
                <span className="min-w-0 flex-1 truncate">{recent}</span>
              </button>
            ))}
            <button
              onMouseDown={(e) => e.preventDefault()}
              onClick={() => { setRecentSearches([]); persistRecentSearches([]); }}
              className="mt-0.5 w-full rounded-xl px-2.5 py-1.5 text-left text-xs text-gray-400 transition-colors hover:bg-muted"
            >
              Clear recent searches
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default LibraryToolbar;
