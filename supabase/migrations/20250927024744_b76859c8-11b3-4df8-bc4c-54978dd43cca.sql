-- Create RLS policy to allow public access to files in stash-media bucket
CREATE POLICY "Public access to stash-media files" ON storage.objects
FOR SELECT USING (bucket_id = 'stash-media');