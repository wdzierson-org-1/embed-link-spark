
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

interface UserPreference {
  hide_add_section: boolean;
  reminder_emails: boolean;
}

export const useUserPreferences = () => {
  const { user } = useAuth();
  const [hideAddSection, setHideAddSection] = useState(false);
  const [reminderEmails, setReminderEmails] = useState(true);
  const [loading, setLoading] = useState(true);
  const { toast } = useToast();

  const fetchPreferences = async () => {
    if (!user) return;

    try {
      const { data, error } = await supabase
        .from('user_preferences')
        .select('hide_add_section, reminder_emails')
        .eq('user_id', user.id)
        .single();

      if (error && error.code !== 'PGRST116') { // PGRST116 = no rows found
        console.error('Error fetching preferences:', error);
      } else if (data) {
        setHideAddSection(data.hide_add_section);
        setReminderEmails(data.reminder_emails ?? true);
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
        .from('user_preferences')
        .upsert({
          user_id: user.id,
          hide_add_section: hideAdd,
          updated_at: new Date().toISOString()
        }, {
          onConflict: 'user_id'
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

  const updateReminderEmails = async (enabled: boolean) => {
    if (!user) return;
    const { error } = await supabase
      .from('user_preferences')
      .upsert({ user_id: user.id, reminder_emails: enabled, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
    if (error) {
      console.error('Error updating reminder_emails:', error);
      toast({ title: 'Error', description: 'Failed to save preference', variant: 'destructive' });
      return;
    }
    setReminderEmails(enabled);
  };

  useEffect(() => {
    if (user) {
      fetchPreferences();
    }
  }, [user]);

  return {
    hideAddSection,
    updatePreference,
    reminderEmails,
    updateReminderEmails,
    loading
  };
};
