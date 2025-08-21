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