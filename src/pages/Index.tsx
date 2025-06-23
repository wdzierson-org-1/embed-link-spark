import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { useNavigate } from 'react-router-dom';
import Navbar from '@/components/Navbar';
import AddContentDialog from '@/components/AddContentDialog';
import ContentGrid from '@/components/ContentGrid';
import UnifiedUploadBox from '@/components/UnifiedUploadBox';
import EditItemDialog from '@/components/EditItemDialog';
import TextLinkInput from '@/components/TextLinkInput';
import type { Database } from '@/integrations/supabase/types';

type ItemType = Database['public']['Enums']['item_type'];

const Index = () => {
  const { user, loading } = useAuth();
  const [items, setItems] = useState([]);
  const [editingItem, setEditingItem] = useState(null);
  const [editDialogOpen, setEditDialogOpen] = useState(false);
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

  const generateDescription = async (type: string, data: any) => {
    try {
      const { data: result, error } = await supabase.functions.invoke('generate-description', {
        body: {
          content: data.content,
          type,
          url: data.url,
          fileData: data.fileData,
          ogData: data.ogData
        }
      });

      if (error) throw error;
      return result.description;
    } catch (error) {
      console.error('Error generating description:', error);
      return null;
    }
  };

  const generateEmbeddings = async (itemId: string, textContent: string) => {
    try {
      const { error } = await supabase.functions.invoke('generate-embeddings', {
        body: {
          itemId,
          textContent
        }
      });

      if (error) throw error;
    } catch (error) {
      console.error('Error generating embeddings:', error);
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

      // Generate AI description
      const aiDescription = await generateDescription(type, data);

      // Prepare metadata for links with OG data
      let metadata = null;
      if (data.ogData) {
        metadata = {
          ogTitle: data.ogData.title,
          ogDescription: data.ogData.description,
          ogImage: data.ogData.image,
          ogSiteName: data.ogData.siteName
        };
      }

      // Insert item into database
      const { data: insertedItem, error } = await supabase.from('items').insert({
        user_id: user.id,
        type: type as ItemType,
        title: data.title,
        content: data.content,
        description: aiDescription,
        url: data.url,
        file_path: filePath,
        file_size: data.file?.size,
        mime_type: data.file?.type,
        metadata
      }).select().single();

      if (error) {
        throw error;
      }

      // Generate embeddings for textual content
      const textForEmbedding = [
        data.title,
        data.content,
        aiDescription,
        data.url,
        data.ogData?.title,
        data.ogData?.description
      ].filter(Boolean).join(' ');

      if (textForEmbedding.trim()) {
        await generateEmbeddings(insertedItem.id, textForEmbedding);
      }

      toast({
        title: "Success",
        description: "Content added to your stash with AI description!",
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

  const handleEditItem = (item: any) => {
    setEditingItem(item);
    setEditDialogOpen(true);
  };

  const handleSaveItem = async (id: string, updates: any) => {
    try {
      const { error } = await supabase
        .from('items')
        .update(updates)
        .eq('id', id);

      if (error) throw error;

      // Regenerate embeddings if textual content changed
      const textForEmbedding = [
        updates.title,
        updates.content,
        updates.description
      ].filter(Boolean).join(' ');

      if (textForEmbedding.trim()) {
        // Delete old embeddings
        await supabase.from('embeddings').delete().eq('item_id', id);
        // Generate new embeddings
        await generateEmbeddings(id, textForEmbedding);
      }

      toast({
        title: "Success",
        description: "Item updated successfully!",
      });

      fetchItems();
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to update item",
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
        onAddContent={() => {}} // No longer needed
        onOpenChat={handleOpenChat}
        onOpenSearch={handleOpenSearch}
      />
      
      <main className="container mx-auto px-4 py-6">
        <UnifiedUploadBox onAddContent={handleAddContent} />
        <TextLinkInput onAddContent={handleAddContent} />
        
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
          onEditItem={handleEditItem}
        />
      </main>

      <EditItemDialog
        open={editDialogOpen}
        onOpenChange={setEditDialogOpen}
        item={editingItem}
        onSave={handleSaveItem}
      />
    </div>
  );
};

export default Index;
