-- Pins (2026-10-09): a person can pin a save. null = not pinned; the timestamp orders the
-- "pinned" tab, newest pin first. A user state like remind_at, so every client reads it off the
-- item row. The partial index serves the pinned tab's filter.
alter table public.items add column if not exists pinned_at timestamptz;

create index if not exists items_pinned_idx
  on public.items (user_id, pinned_at desc)
  where pinned_at is not null;
