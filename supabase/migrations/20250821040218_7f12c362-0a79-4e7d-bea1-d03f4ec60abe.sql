-- Update comments RLS policy to allow anonymous comments on public items
DROP POLICY IF EXISTS "Authenticated users can create comments on public items" ON public.comments;

-- Create new policy that allows both authenticated and anonymous users to comment on public items
CREATE POLICY "Anyone can create comments on public items" 
ON public.comments 
FOR INSERT 
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM items
    WHERE items.id = comments.item_id 
      AND items.is_public = true 
      AND items.comments_enabled = true
  )
);

-- Create an anonymous user profile entry for consistency
-- This allows the anonymous user ID to be used in foreign key relationships
INSERT INTO public.user_profiles (id, username, display_name, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  'anonymous',
  'Anonymous',
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;