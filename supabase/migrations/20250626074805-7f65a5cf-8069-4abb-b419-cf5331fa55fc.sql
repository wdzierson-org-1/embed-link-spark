
-- Drop existing storage policies that might be causing issues
DROP POLICY IF EXISTS "Users can upload their own media" ON storage.objects;
DROP POLICY IF EXISTS "Users can view their own media" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own media" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own media" ON storage.objects;

-- Create corrected storage policies using split_part for proper user ID extraction
CREATE POLICY "Users can upload their own media" 
  ON storage.objects 
  FOR INSERT 
  WITH CHECK (
    bucket_id = 'stash-media' 
    AND auth.uid()::text = split_part(name, '/', 1)
  );

CREATE POLICY "Users can view their own media" 
  ON storage.objects 
  FOR SELECT 
  USING (
    bucket_id = 'stash-media' 
    AND auth.uid()::text = split_part(name, '/', 1)
  );

CREATE POLICY "Users can update their own media" 
  ON storage.objects 
  FOR UPDATE 
  USING (
    bucket_id = 'stash-media' 
    AND auth.uid()::text = split_part(name, '/', 1)
  );

CREATE POLICY "Users can delete their own media" 
  ON storage.objects 
  FOR DELETE 
  USING (
    bucket_id = 'stash-media' 
    AND auth.uid()::text = split_part(name, '/', 1)
  );
