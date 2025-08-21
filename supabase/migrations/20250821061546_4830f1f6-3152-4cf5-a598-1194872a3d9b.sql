-- Add supplemental_note column to items table
ALTER TABLE public.items 
ADD COLUMN supplemental_note TEXT;