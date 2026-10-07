import React, { useEffect, useRef, useState } from 'react';
import { Search, X, Clock } from 'lucide-react';
import { StatusLine } from '@/components/machine/Machine';

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
  /** Saves Stash is still reading (enrichment pending), reported in the status line */
  readingCount?: number;
}

const LibraryToolbar = ({
  searchQuery,
  onSearchChange,
  itemCount,
  tags,
  selectedTags,
  onTagFilterChange,
  readingCount = 0,
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

  return (
    <div className="container mx-auto flex flex-wrap items-center gap-3 px-4 pb-5 pt-1">
      {/* Tag filtering hidden 2026-08-30 — tags are retired; themes will
          replace them as the grouping model. Props (tags, selectedTags,
          onTagFilterChange) kept so the contract with Index is unchanged. */}

      {/* The library's status line, in the machine voice: how much is here, and what Stash
          is still reading (the same cursor the cards turn) */}
      <p className="hidden items-center gap-2 font-pixel text-pixel text-muted-foreground sm:flex">
        <span className="text-ink">
          {itemCount} {itemCount === 1 ? 'save' : 'saves'}
        </span>
        {readingCount > 0 && (
          <>
            <span aria-hidden>·</span>
            <StatusLine tone="busy">reading {readingCount}…</StatusLine>
          </>
        )}
      </p>

      <div ref={searchWrapRef} className="relative ml-auto min-w-0 basis-56 sm:max-w-[340px]">
        <div
          onClick={() => { setIsSearchFocused(true); searchInputRef.current?.focus(); }}
          className={`flex h-10 cursor-text items-center gap-2 border bg-white px-3 transition-shadow duration-150 ${
            isSearchFocused
              ? 'border-ink shadow-[0_0_0_3px_rgb(var(--spot-rgb))]'
              : 'border-line hover:border-ink/40'
          }`}
        >
          <Search className={`h-4 w-4 flex-none ${isSearchFocused ? 'text-ink' : 'text-muted-foreground'}`} />
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
            className="min-w-0 flex-1 bg-transparent text-[15px] outline-none placeholder:text-muted-foreground"
          />
          {searchQuery && (
            <button
              onClick={() => { onSearchChange(''); searchInputRef.current?.focus(); }}
              className="grid h-6 w-6 flex-none place-items-center text-muted-foreground hover:bg-ink hover:text-white"
              aria-label="Clear search"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          )}
        </div>

        {showRecents && (
          // A small window: the machine remembering what you looked for
          <div className="v2-print-in absolute left-0 right-0 top-full z-30 mt-2 border border-ink bg-white shadow-print-sm">
            <div className="flex h-[22px] items-center justify-between bg-ink px-2 font-pixel text-pixel leading-none text-white">
              <span>recent searches</span>
              <button
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => { setRecentSearches([]); persistRecentSearches([]); }}
                className="px-1 text-white/70 hover:text-white hover:underline"
              >
                clear
              </button>
            </div>
            <div className="p-0.5">
              {recentSearches.map(recent => (
                <button
                  key={recent}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => { onSearchChange(recent); rememberSearch(recent); searchInputRef.current?.focus(); }}
                  className="flex w-full items-center gap-2.5 px-2.5 py-2 text-left text-sm text-ink hover:bg-ink hover:text-white"
                >
                  <Clock className="h-3.5 w-3.5 flex-none opacity-60" />
                  <span className="min-w-0 flex-1 truncate">{recent}</span>
                </button>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default LibraryToolbar;
