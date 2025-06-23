
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

export const useUserPreferences = () => {
  const { user } = useAuth();
  const [hideAddSection, setHideAddSection] = useState(false);
  const [loading, setLoading] = useState(true);
  const { toast } = useToast();

  const fetchPreferences = async () => {
    if (!user) return;
    
    try {
      const { data, error } = await supabase
        .from('user_preferences' as any)
        .select('hide_add_section')
        .eq('user_id', user.id)
        .single();

      if (error && error.code !== 'PGRST116') { // PGRST116 = no rows found
        console.error('Error fetching preferences:', error);
      } else if (data) {
        setHideAddSection(data.hide_add_section);
      }
    } catch (error) {
      console.error('Exception while fetching preferences:', error);
    } finally {
      setLoading(false);
    }
  };

  const updatePreference = async (hideAdd: boolean) => {
    if (!user) return;

    try {
      const { error } = await supabase
        .from('user_preferences' as any)
        .upsert({
          user_id: user.id,
          hide_add_section: hideAdd,
          updated_at: new Date().toISOString()
        });

      if (error) {
        console.error('Error updating preferences:', error);
        toast({
          title: "Error",
          description: "Failed to save preference",
          variant: "destructive",
        });
      } else {
        setHideAddSection(hideAdd);
      }
    } catch (error) {
      console.error('Exception while updating preferences:', error);
    }
  };

  useEffect(() => {
    if (user) {
      fetchPreferences();
    }
  }, [user]);

  return {
    hideAddSection,
    updatePreference,
    loading
  };
};
