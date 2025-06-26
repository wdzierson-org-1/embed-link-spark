
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useTags } from '@/hooks/useTags';
import StashHeader from '@/components/StashHeader';
import ContentGrid from '@/components/ContentGrid';
import AddContentDialog from '@/components/AddContentDialog';
import EditItemDialog from '@/components/EditItemDialog';
import GlobalChatInterface from '@/components/GlobalChatInterface';
import { getSuggestedTags as getSuggestedTagsFromApi } from '@/utils/aiOperations';

const Index = () => {
  const { user } = useAuth();
  const { items, fetchItems, addOptimisticItem, removeOptimisticItem, clearSkeletonItems } = useItems();
  const { handleAddContent, handleSaveItem, handleDeleteItem } = useItemOperations(
    fetchItems, 
    addOptimisticItem, 
    removeOptimisticItem,
    clearSkeletonItems
  );
  const { tags } = useTags();
  
  const [isAddDialogOpen, setIsAddDialogOpen] = useState(false);
  const [editingItem, setEditingItem] = useState(null);
  const [selectedTags, setSelectedTags] = useState([]);
  const [showGlobalChat, setShowGlobalChat] = useState(false);

  const getSuggestedTags = async (content) => {
    if (!user) return [];
    return await getSuggestedTagsFromApi(content);
  };

  useEffect(() => {
    if (!user) return;
    fetchItems();
  }, [user, fetchItems]);

  const handleEditItem = (item) => {
    setEditingItem(item);
  };

  const handleChatWithItem = (item) => {
    // For now, just show the global chat when clicking chat with item
    setShowGlobalChat(true);
  };

  const handleTagFilterChange = (tags) => {
    setSelectedTags(tags);
  };

  if (!user) {
    return null;
  }

  return (
    <div className="min-h-screen bg-background">
      <StashHeader 
        itemCount={items.filter(item => !item.isOptimistic).length}
        onTagFiltersChange={handleTagFilterChange}
      />
      
      <main className="container mx-auto px-4 pt-24 pb-8">
        <ContentGrid 
          items={items} 
          onDeleteItem={handleDeleteItem}
          onEditItem={handleEditItem}
          onChatWithItem={handleChatWithItem}
          tagFilters={selectedTags}
        />
      </main>

      <AddContentDialog
        open={isAddDialogOpen}
        onOpenChange={setIsAddDialogOpen}
        onAddContent={handleAddContent}
      />

      <EditItemDialog
        open={!!editingItem}
        onOpenChange={(open) => !open && setEditingItem(null)}
        item={editingItem}
        onSave={handleSaveItem}
      />

      <GlobalChatInterface
        isOpen={showGlobalChat}
        onClose={() => setShowGlobalChat(false)}
      />
    </div>
  );
};

export default Index;
