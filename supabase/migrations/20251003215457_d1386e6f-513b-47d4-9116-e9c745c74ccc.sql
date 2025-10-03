-- Add first_name and last_name to user_profiles table
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS first_name TEXT,
ADD COLUMN IF NOT EXISTS last_name TEXT;

-- Update RLS policy to allow users to delete their own phone numbers
DROP POLICY IF EXISTS "Users can delete their own phone numbers" ON user_phone_numbers;
CREATE POLICY "Users can delete their own phone numbers"
ON user_phone_numbers FOR DELETE
USING (auth.uid() = user_id);

-- Update RLS policy to allow users to delete their own tags
-- This will also delete associated item_tags due to foreign key
DROP POLICY IF EXISTS "Users can delete their own tags" ON tags;
CREATE POLICY "Users can delete their own tags"
ON tags FOR DELETE
USING (auth.uid() = user_id);

-- Ensure item_tags has proper delete policy
DROP POLICY IF EXISTS "Users can delete item_tags for their own items" ON item_tags;
CREATE POLICY "Users can delete item_tags for their own items"
ON item_tags FOR DELETE
USING (EXISTS (
  SELECT 1 FROM items
  WHERE items.id = item_tags.item_id
  AND items.user_id = auth.uid()
));