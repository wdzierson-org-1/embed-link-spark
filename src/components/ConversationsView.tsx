import { useEffect, useState } from 'react';
import { format } from 'date-fns';
import { supabase } from '@/integrations/supabase/client';
import { bucketConversations, type ConversationListRow } from '@/utils/chatSessions';

interface ConversationsViewProps {
  onOpenConversation: (c: { id: string; title: string | null }) => void;
  onBack: () => void;
}

// Main-pane replacement for the card grid while "Earlier conversations" is
// open. Read-only list; clicking a row loads that session into the mole.
const ConversationsView = ({ onOpenConversation, onBack }: ConversationsViewProps) => {
  const [rows, setRows] = useState<ConversationListRow[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    void supabase.rpc('list_conversations').then(({ data, error }) => {
      if (cancelled) return;
      if (error) {
        console.error('list_conversations failed:', error);
        setRows([]);
        return;
      }
      setRows((data ?? []) as ConversationListRow[]);
    });
    return () => { cancelled = true; };
  }, []);

  const buckets = rows ? bucketConversations(rows, new Date()) : [];

  return (
    <div className="mx-auto max-w-3xl">
      <button
        onClick={onBack}
        className="mb-4 text-sm text-muted-foreground hover:text-foreground"
      >
        ← Back to your stash
      </button>
      <h1 className="text-lg font-semibold">Conversations</h1>
      <p className="mb-4 text-sm text-muted-foreground">
        Chats start fresh after a few hours away — nothing to name or file.
      </p>

      {rows && rows.length === 0 && (
        <p className="py-10 text-center text-sm text-muted-foreground">
          No conversations yet — ask your stash something.
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
              className="mb-2 flex w-full items-center gap-3 rounded-xl border border-border bg-white px-4 py-3 text-left transition hover:shadow-md"
            >
              <span className="h-2 w-2 flex-none rounded-full bg-violet-300" />
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
    </div>
  );
};

export default ConversationsView;
