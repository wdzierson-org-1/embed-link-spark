
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { useNavigate } from 'react-router-dom';
import Navbar from '@/components/Navbar';
import AddContentDialog from '@/components/AddContentDialog';
import ContentGrid from '@/components/ContentGrid';
import { Button } from '@/components/ui/button';
import type { Database } from '@/integrations/supabase/types';

type ItemType = Database['public']['Enums']['item_type'];

const Index = () => {
  const { user, loading } = useAuth();
  const [items, setItems] = useState([]);
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const { toast } = useToast();
  const navigate = useNavigate();

  // Redirect to auth if not authenticated
  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
  }, [user, loading, navigate]);

  // Fetch user's items
  useEffect(() => {
    if (user) {
      fetchItems();
    }
  }, [user]);

  const fetchItems = async () => {
    const { data, error } = await supabase
      .from('items')
      .select('*')
      .order('created_at', { ascending: false });

    if (error) {
      toast({
        title: "Error",
        description: "Failed to fetch items",
        variant: "destructive",
      });
    } else {
      setItems(data || []);
    }
  };

  const handleAddContent = async (type: string, data: any) => {
    if (!user) return;

    try {
      let filePath = null;
      
      // Handle file upload if there's a file
      if (data.file) {
        const fileExt = data.file.name.split('.').pop();
        const fileName = `${Date.now()}.${fileExt}`;
        filePath = `${user.id}/${fileName}`;

        const { error: uploadError } = await supabase.storage
          .from('stash-media')
          .upload(filePath, data.file);

        if (uploadError) {
          throw uploadError;
        }
      }

      // Insert item into database
      const { error } = await supabase.from('items').insert({
        user_id: user.id,
        type: type as ItemType,
        title: data.title,
        content: data.content,
        url: data.url,
        file_path: filePath,
        file_size: data.file?.size,
        mime_type: data.file?.type,
      });

      if (error) {
        throw error;
      }

      toast({
        title: "Success",
        description: "Content added to your stash!",
      });

      fetchItems();
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to add content",
        variant: "destructive",
      });
    }
  };

  const handleDeleteItem = async (id: string) => {
    const { error } = await supabase
      .from('items')
      .delete()
      .eq('id', id);

    if (error) {
      toast({
        title: "Error",
        description: "Failed to delete item",
        variant: "destructive",
      });
    } else {
      toast({
        title: "Success",
        description: "Item deleted from your stash",
      });
      fetchItems();
    }
  };

  const handleOpenChat = () => {
    toast({
      title: "Coming soon",
      description: "Chat functionality will be available soon!",
    });
  };

  const handleOpenSearch = () => {
    toast({
      title: "Coming soon",
      description: "Search functionality will be available soon!",
    });
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p>Loading...</p>
      </div>
    );
  }

  if (!user) {
    return null; // Will redirect to auth
  }

  return (
    <div className="min-h-screen bg-background">
      <Navbar
        onAddContent={() => setAddDialogOpen(true)}
        onOpenChat={handleOpenChat}
        onOpenSearch={handleOpenSearch}
      />
      
      <main className="container mx-auto px-4 py-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-2xl font-bold">Your Stash</h2>
            <p className="text-muted-foreground">
              {items.length} {items.length === 1 ? 'item' : 'items'} in your collection
            </p>
          </div>
        </div>

        <ContentGrid
          items={items}
          onDeleteItem={handleDeleteItem}
        />
      </main>

      <AddContentDialog
        open={addDialogOpen}
        onOpenChange={setAddDialogOpen}
        onAddContent={handleAddContent}
      />
    </div>
  );
};

export default Index;
