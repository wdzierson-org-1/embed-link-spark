import React, { useEffect, useRef } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Search, X, MessageSquare } from 'lucide-react';
import { useSubscription } from '@/hooks/useSubscription';
import { useToast } from '@/hooks/use-toast';

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
  isFilterPanelOpen?: boolean;
  onFilterPanelToggle?: (isOpen: boolean) => void;
}

const SearchSection = ({
  isSearchActive,
  searchQuery,
  onSearchClick,
  onSearchClear,
  onSearchChange,
  onShowGlobalChat,
  itemCount,
  isFilterPanelOpen = false,
}: SearchSectionProps) => {
  const { canSearch } = useSubscription();
  const { toast } = useToast();
  const searchInputRef = useRef<HTMLInputElement>(null);

  const handleSearchClick = () => {
    if (!canSearch) {
      toast({
        title: "Feature Restricted",
        description: "Search is only available with an active subscription.",
        variant: "destructive"
      });
      return;
    }
    onSearchClick();
  };

  useEffect(() => {
    if (!isSearchActive) return;

    const focusTimer = window.setTimeout(() => {
      searchInputRef.current?.focus();
    }, 180);

    return () => {
      window.clearTimeout(focusTimer);
    };
  }, [isSearchActive]);

  return (
    <div className="container mx-auto px-4 pt-3 pb-2 bg-white">
      <div className="flex flex-col gap-3 mb-2">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2 min-w-0">
            {itemCount > 0 && !isFilterPanelOpen && (
              <Button
                variant="ghost"
                size="sm"
                onClick={onShowGlobalChat}
                className="flex items-center gap-2 hover:bg-black/10 transition-all duration-200 shrink-0 relative z-30 border-0 shadow-none"
              >
                <MessageSquare className="h-4 w-4" />
                <span className="hidden sm:inline">Ask Stash</span>
                <span className="sm:hidden">Ask</span>
              </Button>
            )}
          </div>

          <div className="flex items-center justify-end gap-2 flex-1 min-w-0">
            {itemCount > 0 && !isFilterPanelOpen && (
              <AnimatePresence initial={false} mode="wait">
                {!isSearchActive ? (
                  <motion.div
                    key="keyword-search-button"
                    initial={{ opacity: 0, x: 6 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: -6 }}
                    transition={{
                      x: { duration: 0.16, ease: [0.22, 1, 0.36, 1] },
                      opacity: { duration: 0.16, ease: [0.22, 1, 0.36, 1] },
                    }}
                  >
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={handleSearchClick}
                      className="flex items-center gap-2 hover:bg-black/10 transition-all duration-200 shrink-0 relative z-30 border-0 shadow-none"
                    >
                      <motion.span
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                        transition={{ duration: 0.16, ease: [0.22, 1, 0.36, 1] }}
                        className="inline-flex"
                      >
                        <Search className="h-4 w-4" />
                      </motion.span>
                      <span className="hidden sm:inline">Keyword search</span>
                      <span className="sm:hidden">Keyword</span>
                    </Button>
                  </motion.div>
                ) : (
                  <motion.div
                    key="keyword-search-input"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.12, ease: [0.22, 1, 0.36, 1] }}
                    className="flex items-center gap-2 min-w-0"
                  >
                    <motion.div
                      initial={{ width: 0, opacity: 0 }}
                      animate={{ width: 280, opacity: 1 }}
                      exit={{ width: 0, opacity: 0 }}
                      transition={{ duration: 0.24, ease: [0.22, 1, 0.36, 1] }}
                      className="relative rounded-md bg-white px-3 py-2 min-w-0 w-[220px] sm:w-[280px] shadow-[0_2px_2px_rgba(0,0,0,0.2)] overflow-hidden"
                    >
                      <span className="absolute left-3 top-[calc(50%-1px)] -translate-y-1/2 inline-flex text-gray-400">
                        <motion.span
                          initial={{ opacity: 0 }}
                          animate={{ opacity: 1 }}
                          exit={{ opacity: 0 }}
                          transition={{ duration: 0.65, delay: 0.24, ease: [0.22, 1, 0.36, 1] }}
                          className="inline-flex"
                        >
                          <Search className="h-4 w-4 shrink-0" />
                        </motion.span>
                      </span>

                      <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                        transition={{ duration: 0.2, delay: 0.12, ease: [0.22, 1, 0.36, 1] }}
                        className="flex items-center"
                      >
                        <Input
                          ref={searchInputRef}
                          value={searchQuery}
                          onChange={onSearchChange}
                          placeholder="Search notes..."
                          className="border-0 p-0 pl-6 h-auto focus-visible:ring-0 focus-visible:ring-offset-0 min-w-0"
                        />
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={onSearchClear}
                          className="h-6 w-6 p-0 ml-2 hover:bg-gray-100 shrink-0"
                        >
                          <X className="h-3 w-3" />
                        </Button>
                      </motion.div>
                    </motion.div>
                  </motion.div>
                )}
              </AnimatePresence>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default SearchSection;
