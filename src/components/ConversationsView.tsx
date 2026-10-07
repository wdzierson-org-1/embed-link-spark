import { useEffect, useState } from 'react';
import { format } from 'date-fns';
import { Search } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { bucketConversations, type ConversationListRow } from '@/utils/chatSessions';

interface ConversationsViewProps {
  onOpenConversation: (c: { id: string; title: string | null }) => void;
  onBack: () => void;
}

const PAGE_SIZES = [25, 50, 100] as const;
const SEARCH_DEBOUNCE_MS = 300;

// Main-pane replacement for the card grid while "Earlier conversations" is
// open. Server-paged + searchable (titles and message contents); clicking a
// row loads that session into the mole.
const ConversationsView = ({ onOpenConversation, onBack }: ConversationsViewProps) => {
  const [rows, setRows] = useState<ConversationListRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [pageSize, setPageSize] = useState<number>(PAGE_SIZES[0]);
  const [page, setPage] = useState(0);

  // Debounce typed search into the fetch-triggering value (resets to page 0)
  useEffect(() => {
    const timer = setTimeout(() => {
      setSearch(searchInput.trim());
      setPage(0);
    }, SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [searchInput]);

  useEffect(() => {
    let cancelled = false;
    void supabase
      .rpc('list_conversations', {
        search_text: search || null,
        page_limit: pageSize,
        page_offset: page * pageSize,
      })
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error) {
          console.error('list_conversations failed:', error);
          setRows([]);
          setTotalCount(0);
          return;
        }
        const result = (data ?? []) as Array<ConversationListRow & { total_count: number }>;
        setRows(result);
        setTotalCount(result[0]?.total_count ?? 0);
      });
    return () => {
      cancelled = true;
    };
  }, [search, pageSize, page]);

  const buckets = rows ? bucketConversations(rows, new Date()) : [];
  const firstShown = totalCount === 0 ? 0 : page * pageSize + 1;
  const lastShown = page * pageSize + (rows?.length ?? 0);
  const hasPrev = page > 0;
  const hasNext = lastShown < totalCount;

  return (
    // pt clears the header's drop shadow; back link sits at the container's
    // left edge, aligned with the Stash wordmark above
    <div className="pt-4">
      <button
        onClick={onBack}
        className="mb-8 inline-flex h-8 items-center bg-white px-2.5 text-[14px] font-medium text-ink shadow-[0_0_0_1px_rgba(0,0,0,0.06)] hover:bg-ink hover:text-white"
      >
        ← Back to your stash
      </button>

      <div className="mx-auto max-w-3xl">
      <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
        <h1 className="text-screen-title font-medium text-ink">Conversations</h1>
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Search conversations…"
            className="h-10 w-72 border border-line bg-white pl-9 pr-3 text-[15px] outline-none transition-shadow placeholder:text-muted-foreground focus:border-ink focus:shadow-[0_0_0_3px_rgb(var(--spot-rgb))]"
          />
        </div>
      </div>

      {rows && rows.length === 0 && (
        <p className="v2-dots border border-line py-10 text-center text-[15px] text-muted-foreground">
          {search
            ? `No conversations match “${search}”.`
            : 'No conversations yet — ask your stash something.'}
        </p>
      )}

      {buckets.map(bucket => (
        <section key={bucket.label}>
          <h2 className="mb-2.5 mt-6 border-b border-ink pb-1.5 font-pixel text-pixel lowercase text-ink">
            {bucket.label}
          </h2>
          {bucket.rows.map(row => (
            <button
              key={row.id}
              onClick={() => onOpenConversation({ id: row.id, title: row.title })}
              className="relative mb-2 flex w-full items-center gap-3 rounded-object border border-line bg-white px-4 py-3 text-left transition-[transform,box-shadow,border-color] duration-150 hover:-translate-x-0.5 hover:-translate-y-0.5 hover:border-ink hover:shadow-print-sm"
            >
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[15px] font-medium text-ink">
                  {row.title ?? 'New chat'}
                </span>
                {row.preview && (
                  <span className="mt-0.5 block truncate text-[14px] text-muted-foreground">
                    {row.preview}
                  </span>
                )}
              </span>
              <span className="flex-none text-right font-pixel text-pixel leading-[1.6] text-muted-foreground">
                {format(new Date(row.last_message_at), 'MMM d').toLowerCase()}
                <br />
                {row.message_count} message{row.message_count === 1 ? '' : 's'}
              </span>
            </button>
          ))}
        </section>
      ))}

      {totalCount > 0 && (
        <div className="relative mt-5 flex flex-wrap items-center justify-between gap-3 font-pixel text-pixel text-muted-foreground">
          <span>
            Showing {firstShown}–{lastShown} of {totalCount}
          </span>
          <div className="flex items-center gap-1.5">
            <label className="mr-1 flex items-center gap-1.5">
              Show
              <select
                value={pageSize}
                onChange={(e) => {
                  setPageSize(Number(e.target.value));
                  setPage(0);
                }}
                className="h-7 border border-line bg-white px-1.5 font-pixel text-pixel text-ink outline-none focus:border-ink"
              >
                {PAGE_SIZES.map(size => (
                  <option key={size} value={size}>{size}</option>
                ))}
              </select>
            </label>
            <button
              onClick={() => setPage(p => Math.max(0, p - 1))}
              disabled={!hasPrev}
              className="h-7 border border-ink bg-white px-2.5 text-ink hover:bg-ink hover:text-white disabled:border-line disabled:text-muted-foreground disabled:hover:bg-white"
            >
              ← Prev
            </button>
            <button
              onClick={() => setPage(p => p + 1)}
              disabled={!hasNext}
              className="h-7 border border-ink bg-white px-2.5 text-ink hover:bg-ink hover:text-white disabled:border-line disabled:text-muted-foreground disabled:hover:bg-white"
            >
              Next →
            </button>
          </div>
        </div>
      )}
      </div>
    </div>
  );
};

export default ConversationsView;
