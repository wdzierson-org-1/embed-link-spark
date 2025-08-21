-- Add missing relationship between comments and user_profiles
ALTER TABLE public.comments 
ADD CONSTRAINT comments_user_id_fkey 
FOREIGN KEY (user_id) 
REFERENCES public.user_profiles(id) 
ON DELETE CASCADE;