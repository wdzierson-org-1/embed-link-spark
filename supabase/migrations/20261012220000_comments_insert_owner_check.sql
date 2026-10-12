-- Comments: close the impersonation hole (2026-10-12, found by the AS-UGC audit).
--
-- "Anyone can create comments on public items" (20250821040218 / 20250821040241) let the `public`
-- role — the anon key included — insert a comment with ANY user_profiles.id as the author, skipping
-- post-comment's length cap and spam list. No client writes this table directly: the web posts
-- through post-comment, which uses the service role (RLS-exempt), and iOS does not comment. So the
-- only thing this changes is that a direct insert must come from a signed-in session writing as
-- itself, on a public item with comments enabled.
drop policy if exists "Anyone can create comments on public items" on public.comments;
create policy "Users can create their own comments on public items" on public.comments
  for insert to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.items
      where items.id = comments.item_id and items.is_public = true and items.comments_enabled = true
    )
  );
