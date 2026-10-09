-- Share links (DESIGN-v2 §12.8, §12.15; docs/ui-changes.md 2026-10-09): an unlisted, revocable,
-- read-only view of one save at /s/<token>. The owner mints a 10-character base62 token
-- client-side and writes it here through the normal owner update; clearing it kills the link.
alter table public.items
  add column if not exists share_token text,
  add column if not exists shared_at timestamptz;

create unique index if not exists items_share_token_key
  on public.items (share_token) where share_token is not null;

-- Anyone holding a token reads that one save, and who shared it. SECURITY DEFINER, so the
-- anonymous role needs no policy on items: the token is the whole credential, and nothing here
-- can list tokens. Pins, reminders, public-feed state and the sticky note are not returned.
create or replace function public.shared_item(p_token text)
returns table (
  id uuid,
  type text,
  title text,
  description text,
  url text,
  file_path text,
  mime_type text,
  file_size bigint,
  summary text,
  page_body text,
  content text,
  attributes jsonb,
  created_at timestamptz,
  shared_at timestamptz,
  username text,
  display_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select i.id, i.type::text, i.title, i.description, i.url, i.file_path, i.mime_type, i.file_size,
         i.summary, i.page_body, i.content, i.attributes, i.created_at, i.shared_at,
         p.username, p.display_name
  from public.items i
  left join public.user_profiles p on p.id = i.user_id
  where p_token is not null and i.share_token = p_token
  limit 1
$$;

revoke all on function public.shared_item(text) from public;
grant execute on function public.shared_item(text) to anon, authenticated;
