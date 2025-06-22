
-- Enable the vector extension first
CREATE EXTENSION IF NOT EXISTS vector;

-- Create enum for item types
CREATE TYPE item_type AS ENUM ('text', 'link', 'image', 'audio', 'video');

-- Create items table to store all user content
CREATE TABLE public.items (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  type item_type NOT NULL,
  title TEXT,
  content TEXT,
  url TEXT,
  file_path TEXT,
  file_size BIGINT,
  mime_type TEXT,
  description TEXT, -- AI-generated description for media
  tags TEXT[],
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create embeddings table for RAG functionality
CREATE TABLE public.embeddings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  item_id UUID REFERENCES public.items ON DELETE CASCADE NOT NULL,
  embedding vector(1536), -- OpenAI embeddings dimension
  content_chunk TEXT NOT NULL,
  chunk_index INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create chat conversations table
CREATE TABLE public.conversations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  title TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create chat messages table
CREATE TABLE public.messages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations ON DELETE CASCADE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  source_items UUID[], -- Array of item IDs that were referenced
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create storage bucket for media files
INSERT INTO storage.buckets (id, name, public)
VALUES ('stash-media', 'stash-media', true);

-- Enable RLS on all tables
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.embeddings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- RLS policies for items
CREATE POLICY "Users can view their own items" 
  ON public.items 
  FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own items" 
  ON public.items 
  FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own items" 
  ON public.items 
  FOR UPDATE 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own items" 
  ON public.items 
  FOR DELETE 
  USING (auth.uid() = user_id);

-- RLS policies for embeddings
CREATE POLICY "Users can view embeddings for their items" 
  ON public.embeddings 
  FOR SELECT 
  USING (EXISTS (
    SELECT 1 FROM public.items 
    WHERE items.id = embeddings.item_id 
    AND items.user_id = auth.uid()
  ));

CREATE POLICY "Users can create embeddings for their items" 
  ON public.embeddings 
  FOR INSERT 
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.items 
    WHERE items.id = embeddings.item_id 
    AND items.user_id = auth.uid()
  ));

CREATE POLICY "Users can update embeddings for their items" 
  ON public.embeddings 
  FOR UPDATE 
  USING (EXISTS (
    SELECT 1 FROM public.items 
    WHERE items.id = embeddings.item_id 
    AND items.user_id = auth.uid()
  ));

CREATE POLICY "Users can delete embeddings for their items" 
  ON public.embeddings 
  FOR DELETE 
  USING (EXISTS (
    SELECT 1 FROM public.items 
    WHERE items.id = embeddings.item_id 
    AND items.user_id = auth.uid()
  ));

-- RLS policies for conversations
CREATE POLICY "Users can view their own conversations" 
  ON public.conversations 
  FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own conversations" 
  ON public.conversations 
  FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own conversations" 
  ON public.conversations 
  FOR UPDATE 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own conversations" 
  ON public.conversations 
  FOR DELETE 
  USING (auth.uid() = user_id);

-- RLS policies for messages
CREATE POLICY "Users can view messages in their conversations" 
  ON public.messages 
  FOR SELECT 
  USING (EXISTS (
    SELECT 1 FROM public.conversations 
    WHERE conversations.id = messages.conversation_id 
    AND conversations.user_id = auth.uid()
  ));

CREATE POLICY "Users can create messages in their conversations" 
  ON public.messages 
  FOR INSERT 
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.conversations 
    WHERE conversations.id = messages.conversation_id 
    AND conversations.user_id = auth.uid()
  ));

CREATE POLICY "Users can update messages in their conversations" 
  ON public.messages 
  FOR UPDATE 
  USING (EXISTS (
    SELECT 1 FROM public.conversations 
    WHERE conversations.id = messages.conversation_id 
    AND conversations.user_id = auth.uid()
  ));

CREATE POLICY "Users can delete messages in their conversations" 
  ON public.messages 
  FOR DELETE 
  USING (EXISTS (
    SELECT 1 FROM public.conversations 
    WHERE conversations.id = messages.conversation_id 
    AND conversations.user_id = auth.uid()
  ));

-- Storage policies for media bucket
CREATE POLICY "Users can upload their own media" 
  ON storage.objects 
  FOR INSERT 
  WITH CHECK (bucket_id = 'stash-media' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can view their own media" 
  ON storage.objects 
  FOR SELECT 
  USING (bucket_id = 'stash-media' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can update their own media" 
  ON storage.objects 
  FOR UPDATE 
  USING (bucket_id = 'stash-media' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can delete their own media" 
  ON storage.objects 
  FOR DELETE 
  USING (bucket_id = 'stash-media' AND auth.uid()::text = (storage.foldername(name))[1]);

-- Create index for faster similarity search
CREATE INDEX embeddings_vector_idx ON public.embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Create function to search similar content
CREATE OR REPLACE FUNCTION search_similar_content(
  query_embedding vector(1536),
  match_threshold float DEFAULT 0.7,
  match_count int DEFAULT 10,
  target_user_id uuid DEFAULT auth.uid()
)
RETURNS TABLE (
  item_id uuid,
  content_chunk text,
  similarity float,
  item_title text,
  item_type item_type,
  item_url text
)
LANGUAGE sql
STABLE
AS $$
  SELECT 
    e.item_id,
    e.content_chunk,
    1 - (e.embedding <=> query_embedding) as similarity,
    i.title as item_title,
    i.type as item_type,
    i.url as item_url
  FROM embeddings e
  JOIN items i ON e.item_id = i.id
  WHERE i.user_id = target_user_id
    AND 1 - (e.embedding <=> query_embedding) > match_threshold
  ORDER BY e.embedding <=> query_embedding
  LIMIT match_count;
$$;
