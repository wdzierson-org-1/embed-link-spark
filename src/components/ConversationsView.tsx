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
    <div className="mx-auto max-w-3xl pt-6">
      <button
        onClick={onBack}
        className="mb-4 text-sm text-muted-foreground hover:text-foreground"
      >
        ← Back to your stash
      </button>

      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-lg font-semibold">Conversations</h1>
          <p className="text-sm text-muted-foreground">
            Chats start fresh after a few hours away — nothing to name or file.
          </p>
        </div>
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
          <input
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Search conversations…"
            className="w-64 rounded-full border border-input bg-white py-1.5 pl-9 pr-3 text-sm outline-none focus:border-violet-300 focus:ring-2 focus:ring-violet-100"
          />
        </div>
      </div>

      {rows && rows.length === 0 && (
        <p className="py-10 text-center text-sm text-muted-foreground">
          {search
            ? `No conversations match “${search}”.`
            : 'No conversations yet — ask your stash something.'}
        </p>
      )}

      {buckets.map(bucket => (
        <section key={bucket.label}>
          <h2 className="pb-2 pt-5 text-[10.5px] font-semibold uppercase tracking-wider text-muted-foreground">
            {bucket.label}
          </h2>
          {bucket.rows.map(row => (
            <button
              key={row.id}
              onClick={() => onOpenConversation({ id: row.id, title: row.title })}
              className="relative mb-2 flex w-full items-center gap-3 rounded-xl border border-border bg-white px-4 py-3 text-left transition hover:shadow-md"
            >
              <span className="h-2 w-2 flex-none rounded-full bg-violet-300" aria-hidden />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium">
                  {row.title ?? 'New chat'}
                </span>
                {row.preview && (
                  <span className="block truncate text-xs text-muted-foreground">
                    {row.preview}
                  </span>
                )}
              </span>
              <span className="flex-none text-right text-xs leading-relaxed text-muted-foreground">
                {format(new Date(row.last_message_at), 'MMM d')}
                <br />
                {row.message_count} message{row.message_count === 1 ? '' : 's'}
              </span>
            </button>
          ))}
        </section>
      ))}

      {totalCount > 0 && (
        <div className="relative mt-4 flex flex-wrap items-center justify-between gap-3 text-xs text-muted-foreground">
          <span>
            Showing {firstShown}–{lastShown} of {totalCount}
          </span>
          <div className="flex items-center gap-2">
            <label className="flex items-center gap-1.5">
              Show
              <select
                value={pageSize}
                onChange={(e) => {
                  setPageSize(Number(e.target.value));
                  setPage(0);
                }}
                className="rounded-md border border-input bg-white px-1.5 py-1 text-xs outline-none"
              >
                {PAGE_SIZES.map(size => (
                  <option key={size} value={size}>{size}</option>
                ))}
              </select>
            </label>
            <button
              onClick={() => setPage(p => Math.max(0, p - 1))}
              disabled={!hasPrev}
              className="rounded-md border border-input bg-white px-2.5 py-1 disabled:opacity-40"
            >
              ← Prev
            </button>
            <button
              onClick={() => setPage(p => p + 1)}
              disabled={!hasNext}
              className="rounded-md border border-input bg-white px-2.5 py-1 disabled:opacity-40"
            >
              Next →
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default ConversationsView;
