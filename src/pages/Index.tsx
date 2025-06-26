
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useTags } from '@/hooks/useTags';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { FileText, Link, Upload } from 'lucide-react';
import StashHeader from '@/components/StashHeader';
import ContentGrid from '@/components/ContentGrid';
import EditItemDialog from '@/components/EditItemDialog';
import GlobalChatInterface from '@/components/GlobalChatInterface';
import TextNoteTab from '@/components/TextNoteTab';
import LinkTab from '@/components/LinkTab';
import MediaUploadTab from '@/components/MediaUploadTab';
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
        onShowGlobalChat={() => setShowGlobalChat(true)}
        itemCount={items.filter(item => !item.isOptimistic).length}
        tags={tags}
        selectedTags={selectedTags}
        onTagFilterChange={handleTagFilterChange}
      />
      
      {/* Full-width tab bar */}
      <div className="w-full border-b bg-background">
        <div className="container mx-auto px-4">
          <Tabs defaultValue="text" className="w-full">
            <TabsList className="grid w-full grid-cols-3 h-12">
              <TabsTrigger value="text" className="flex items-center gap-2">
                <FileText className="h-4 w-4" />
                Text Note
              </TabsTrigger>
              <TabsTrigger value="link" className="flex items-center gap-2">
                <Link className="h-4 w-4" />
                Link
              </TabsTrigger>
              <TabsTrigger value="media" className="flex items-center gap-2">
                <Upload className="h-4 w-4" />
                Upload
              </TabsTrigger>
            </TabsList>
            
            <TabsContent value="text" className="mt-6 pb-6">
              <TextNoteTab
                onAddContent={handleAddContent}
                getSuggestedTags={getSuggestedTags}
              />
            </TabsContent>
            
            <TabsContent value="link" className="mt-6 pb-6">
              <LinkTab
                onAddContent={handleAddContent}
                getSuggestedTags={() => []}
              />
            </TabsContent>
            
            <TabsContent value="media" className="mt-6 pb-6">
              <MediaUploadTab
                onAddContent={handleAddContent}
                getSuggestedTags={getSuggestedTags}
              />
            </TabsContent>
          </Tabs>
        </div>
      </div>
      
      <main className="container mx-auto px-4 pt-8 pb-8">
        <ContentGrid 
          items={items} 
          onDeleteItem={handleDeleteItem}
          onEditItem={handleEditItem}
          onChatWithItem={handleChatWithItem}
          tagFilters={selectedTags}
        />
      </main>

      <EditItemDialog
        open={!!editingItem}
        onOpenChange={(open) => !open && setEditingItem(null)}
        item={editingItem}
        onSave={handleSaveItem}
      />

      <GlobalChatInterface
        open={showGlobalChat}
        onOpenChange={setShowGlobalChat}
      />
    </div>
  );
};

export default Index;
