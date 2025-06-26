
-- Create table for storing chat feedback
CREATE TABLE public.chat_feedback (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  source_item_ids UUID[] DEFAULT ARRAY[]::UUID[],
  rating INTEGER CHECK (rating IN (-1, 1)), -- -1 for thumbs down, 1 for thumbs up
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.chat_feedback ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own feedback" 
  ON public.chat_feedback 
  FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own feedback" 
  ON public.chat_feedback 
  FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own feedback" 
  ON public.chat_feedback 
  FOR UPDATE 
  USING (auth.uid() = user_id);
