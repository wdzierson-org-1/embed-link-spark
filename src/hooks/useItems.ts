
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

export const useItems = () => {
  const { user } = useAuth();
  const [items, setItems] = useState([]);
  const { toast } = useToast();

  const fetchItems = async () => {
    if (!user) return;
    
    try {
      console.log('Fetching items for user:', user.id);
      const { data, error } = await supabase
        .from('items')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) {
        console.error('Error fetching items:', error);
        toast({
          title: "Error",
          description: "Failed to fetch items",
          variant: "destructive",
        });
      } else {
        console.log('Fetched items:', data);
        setItems(data || []);
      }
    } catch (error) {
      console.error('Exception while fetching items:', error);
      toast({
        title: "Error",
        description: "Failed to fetch items",
        variant: "destructive",
      });
    }
  };

  useEffect(() => {
    if (user) {
      fetchItems();
    }
  }, [user]);

  return {
    items,
    fetchItems,
    setItems
  };
};
