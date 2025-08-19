-- Phase 1: Database Schema Updates

-- Add privacy controls to items table
ALTER TABLE public.items 
ADD COLUMN is_public boolean NOT NULL DEFAULT false,
ADD COLUMN visibility text NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'public', 'unlisted'));

-- Create user_profiles table
CREATE TABLE public.user_profiles (
  id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  username text UNIQUE NOT NULL,
  display_name text,
  bio text,
  avatar_url text,
  public_feed_enabled boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS on user_profiles
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_profiles
CREATE POLICY "Users can view all public profiles" 
ON public.user_profiles 
FOR SELECT 
USING (true);

CREATE POLICY "Users can create their own profile" 
ON public.user_profiles 
FOR INSERT 
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile" 
ON public.user_profiles 
FOR UPDATE 
USING (auth.uid() = id);

-- Add new RLS policies for items to allow public access
CREATE POLICY "Anyone can view public items" 
ON public.items 
FOR SELECT 
USING (is_public = true);

-- Create indexes for performance
CREATE INDEX idx_items_public ON public.items(is_public) WHERE is_public = true;
CREATE INDEX idx_items_user_public ON public.items(user_id, is_public);
CREATE INDEX idx_user_profiles_username ON public.user_profiles(username);

-- Create trigger for updating user_profiles updated_at
CREATE OR REPLACE FUNCTION public.update_user_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_profiles_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_user_profiles_updated_at();