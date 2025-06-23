
-- Create tags table
CREATE TABLE public.tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  usage_count INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(user_id, name)
);

-- Create item_tags junction table for many-to-many relationship
CREATE TABLE public.item_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id UUID NOT NULL REFERENCES public.items(id) ON DELETE CASCADE,
  tag_id UUID NOT NULL REFERENCES public.tags(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(item_id, tag_id)
);

-- Create user_preferences table
CREATE TABLE public.user_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  hide_add_section BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

-- RLS policies for tags table
CREATE POLICY "Users can view their own tags" ON public.tags
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own tags" ON public.tags
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own tags" ON public.tags
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own tags" ON public.tags
  FOR DELETE USING (auth.uid() = user_id);

-- RLS policies for item_tags table (users can only access tags for their own items)
CREATE POLICY "Users can view item_tags for their own items" ON public.item_tags
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.items 
      WHERE items.id = item_tags.item_id 
      AND items.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create item_tags for their own items" ON public.item_tags
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.items 
      WHERE items.id = item_tags.item_id 
      AND items.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can delete item_tags for their own items" ON public.item_tags
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.items 
      WHERE items.id = item_tags.item_id 
      AND items.user_id = auth.uid()
    )
  );

-- RLS policies for user_preferences table
CREATE POLICY "Users can view their own preferences" ON public.user_preferences
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own preferences" ON public.user_preferences
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own preferences" ON public.user_preferences
  FOR UPDATE USING (auth.uid() = user_id);

-- Create function to increment tag usage and return tag ID
CREATE OR REPLACE FUNCTION public.increment_tag_usage(
  tag_name TEXT,
  user_uuid UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  tag_id UUID;
BEGIN
  -- Try to find existing tag
  SELECT id INTO tag_id
  FROM public.tags
  WHERE name = LOWER(tag_name) AND user_id = user_uuid;
  
  -- If tag exists, increment usage count
  IF tag_id IS NOT NULL THEN
    UPDATE public.tags
    SET usage_count = usage_count + 1,
        updated_at = now()
    WHERE id = tag_id;
  ELSE
    -- Create new tag
    INSERT INTO public.tags (name, user_id, usage_count)
    VALUES (LOWER(tag_name), user_uuid, 1)
    RETURNING id INTO tag_id;
  END IF;
  
  RETURN tag_id;
END;
$$;
