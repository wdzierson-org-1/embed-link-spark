-- Create icons bucket for favicon and app icons
INSERT INTO storage.buckets (id, name, public) VALUES ('icons', 'icons', true);

-- Create RLS policies for icons bucket - make it publicly readable
CREATE POLICY "Icons are publicly accessible" 
ON storage.objects 
FOR SELECT 
USING (bucket_id = 'icons');

-- Allow authenticated users to upload icons (for admin purposes)
CREATE POLICY "Authenticated users can upload icons" 
ON storage.objects 
FOR INSERT 
WITH CHECK (bucket_id = 'icons' AND auth.role() = 'authenticated');