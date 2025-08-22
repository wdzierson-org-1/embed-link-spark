-- Add "collection" to the item_type enum
ALTER TYPE item_type ADD VALUE 'collection';

-- Create item_attachments table to store multiple attachments per item
CREATE TABLE public.item_attachments (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  item_id UUID NOT NULL,
  type item_type NOT NULL,
  url TEXT,
  file_path TEXT,
  file_size BIGINT,
  mime_type TEXT,
  title TEXT,
  description TEXT,
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.item_attachments ENABLE ROW LEVEL SECURITY;

-- Create policies for item_attachments
CREATE POLICY "Users can view attachments for their items" 
ON public.item_attachments 
FOR SELECT 
USING (EXISTS (
  SELECT 1 FROM public.items 
  WHERE items.id = item_attachments.item_id 
  AND items.user_id = auth.uid()
));

CREATE POLICY "Users can create attachments for their items" 
ON public.item_attachments 
FOR INSERT 
WITH CHECK (EXISTS (
  SELECT 1 FROM public.items 
  WHERE items.id = item_attachments.item_id 
  AND items.user_id = auth.uid()
));

CREATE POLICY "Users can update attachments for their items" 
ON public.item_attachments 
FOR UPDATE 
USING (EXISTS (
  SELECT 1 FROM public.items 
  WHERE items.id = item_attachments.item_id 
  AND items.user_id = auth.uid()
));

CREATE POLICY "Users can delete attachments for their items" 
ON public.item_attachments 
FOR DELETE 
USING (EXISTS (
  SELECT 1 FROM public.items 
  WHERE items.id = item_attachments.item_id 
  AND items.user_id = auth.uid()
));

-- Create function to update timestamps
CREATE TRIGGER update_item_attachments_updated_at
BEFORE UPDATE ON public.item_attachments
FOR EACH ROW
EXECUTE FUNCTION public.update_comments_updated_at();