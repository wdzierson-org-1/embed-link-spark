
-- Create table to map phone numbers to users
CREATE TABLE public.user_phone_numbers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  phone_number TEXT NOT NULL UNIQUE,
  verified BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.user_phone_numbers ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own phone numbers" 
  ON public.user_phone_numbers 
  FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own phone numbers" 
  ON public.user_phone_numbers 
  FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own phone numbers" 
  ON public.user_phone_numbers 
  FOR UPDATE 
  USING (auth.uid() = user_id);

-- Create table for SMS/WhatsApp conversation history
CREATE TABLE public.sms_conversations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  phone_number TEXT NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('sms', 'whatsapp')),
  message_type TEXT NOT NULL CHECK (message_type IN ('user', 'assistant')),
  content TEXT NOT NULL,
  intent TEXT CHECK (intent IN ('note', 'question', 'command')),
  media_url TEXT,
  media_type TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.sms_conversations ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own SMS conversations" 
  ON public.sms_conversations 
  FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own SMS conversations" 
  ON public.sms_conversations 
  FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

-- Create indexes for better performance
CREATE INDEX idx_user_phone_numbers_phone ON public.user_phone_numbers(phone_number);
CREATE INDEX idx_user_phone_numbers_user_id ON public.user_phone_numbers(user_id);
CREATE INDEX idx_sms_conversations_user_id ON public.sms_conversations(user_id);
CREATE INDEX idx_sms_conversations_phone ON public.sms_conversations(phone_number);
CREATE INDEX idx_sms_conversations_created_at ON public.sms_conversations(created_at DESC);
