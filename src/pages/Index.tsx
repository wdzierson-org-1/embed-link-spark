
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';
import { useNavigate } from 'react-router-dom';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import Navbar from '@/components/Navbar';
import ContentGrid from '@/components/ContentGrid';
import UnifiedUploadBox from '@/components/UnifiedUploadBox';
import EditItemDialog from '@/components/EditItemDialog';
import TextLinkInput from '@/components/TextLinkInput';
import StashHeader from '@/components/StashHeader';

const Index = () => {
  const { user, loading } = useAuth();
  const [editingItem, setEditingItem] = useState(null);
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const { toast } = useToast();
  const navigate = useNavigate();
  
  const { items, fetchItems } = useItems();
  const { handleAddContent, handleSaveItem, handleDeleteItem } = useItemOperations(fetchItems);

  // Redirect to auth if not authenticated
  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
  }, [user, loading, navigate]);

  const handleEditItem = (item: any) => {
    setEditingItem(item);
    setEditDialogOpen(true);
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
        
        <StashHeader itemCount={items.length} />

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
