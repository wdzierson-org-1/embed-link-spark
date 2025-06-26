
import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';

export const usePhoneNumber = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [isLoading, setIsLoading] = useState(false);
  const [phoneNumber, setPhoneNumber] = useState('');

  const registerPhoneNumber = async (phone: string) => {
    if (!user) {
      toast({
        title: "Error",
        description: "You must be logged in to register a phone number",
        variant: "destructive"
      });
      return false;
    }

    setIsLoading(true);
    try {
      // Clean phone number (remove spaces, dashes, etc.)
      const cleanPhone = phone.replace(/\D/g, '');
      
      const { error } = await supabase
        .from('user_phone_numbers')
        .upsert({
          user_id: user.id,
          phone_number: cleanPhone,
          verified: true // Auto-verify for now
        }, {
          onConflict: 'phone_number'
        });

      if (error) throw error;

      toast({
        title: "Success",
        description: "Phone number registered! You can now use SMS/WhatsApp features."
      });

      return true;
    } catch (error: any) {
      console.error('Error registering phone number:', error);
      toast({
        title: "Error",
        description: error.message || "Failed to register phone number",
        variant: "destructive"
      });
      return false;
    } finally {
      setIsLoading(false);
    }
  };

  const getRegisteredPhoneNumbers = async () => {
    if (!user) return [];

    try {
      const { data, error } = await supabase
        .from('user_phone_numbers')
        .select('*')
        .eq('user_id', user.id);

      if (error) throw error;
      return data || [];
    } catch (error) {
      console.error('Error fetching phone numbers:', error);
      return [];
    }
  };

  return {
    phoneNumber,
    setPhoneNumber,
    isLoading,
    registerPhoneNumber,
    getRegisteredPhoneNumbers
  };
};
