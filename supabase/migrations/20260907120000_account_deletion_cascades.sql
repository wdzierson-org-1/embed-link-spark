-- Account deletion (punch list B1).
--
-- Deleting an auth user 500'd in GoTrue as soon as they owned an item, because
-- items.user_id and conversations.user_id referenced auth.users with NO ACTION.
-- Everything else already cascaded (tags, user_phone_numbers, user_preferences,
-- user_profiles, agent_grants, sms_conversations, and the auth.* tables), and
-- items → embeddings / item_tags / comments and conversations → messages
-- cascade in turn. Four user-scoped tables had no foreign key at all and would
-- have been left as orphans; they get a cascading one here.
--
-- Storage objects are not covered by any constraint — the delete-account edge
-- function removes `<user_id>/**` in stash-media through the storage API
-- before it deletes the auth user.

BEGIN;

ALTER TABLE public.items
  DROP CONSTRAINT items_user_id_fkey,
  ADD CONSTRAINT items_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.conversations
  DROP CONSTRAINT conversations_user_id_fkey,
  ADD CONSTRAINT conversations_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Rows orphaned by earlier manual user deletions would block the new keys.
DELETE FROM public.chat_feedback   WHERE user_id IS NOT NULL AND user_id NOT IN (SELECT id FROM auth.users);
DELETE FROM public.card_feedback   WHERE user_id IS NOT NULL AND user_id NOT IN (SELECT id FROM auth.users);
DELETE FROM public.pending_intents WHERE user_id IS NOT NULL AND user_id NOT IN (SELECT id FROM auth.users);
DELETE FROM public.retrieval_log   WHERE user_id IS NOT NULL AND user_id NOT IN (SELECT id FROM auth.users);

ALTER TABLE public.chat_feedback
  ADD CONSTRAINT chat_feedback_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.card_feedback
  ADD CONSTRAINT card_feedback_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.pending_intents
  ADD CONSTRAINT pending_intents_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.retrieval_log
  ADD CONSTRAINT retrieval_log_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

COMMIT;
