
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';
import { useNavigate } from 'react-router-dom';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useUserPreferences } from '@/hooks/useUserPreferences';
import { useTags } from '@/hooks/useTags';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { ChevronDown, ChevronUp } from 'lucide-react';
import Navbar from '@/components/Navbar';
import ContentGrid from '@/components/ContentGrid';
import EditItemDialog from '@/components/EditItemDialog';
import StashHeader from '@/components/StashHeader';
import MediaUploadTab from '@/components/MediaUploadTab';
import TextNoteTab from '@/components/TextNoteTab';
import LinkTab from '@/components/LinkTab';
import ChatInterface from '@/components/ChatInterface';
import GlobalChatInterface from '@/components/GlobalChatInterface';

const Index = () => {
  const { user, loading } = useAuth();
  const [editingItem, setEditingItem] = useState(null);
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [chatItem, setChatItem] = useState(null);
  const [chatOpen, setChatOpen] = useState(false);
  const [globalChatOpen, setGlobalChatOpen] = useState(false);
  const { toast } = useToast();
  const navigate = useNavigate();
  
  const { items, fetchItems } = useItems();
  const { handleAddContent, handleSaveItem, handleDeleteItem } = useItemOperations(fetchItems);
  const { hideAddSection, updatePreference, loading: preferencesLoading } = useUserPreferences();
  const { getSuggestedTags, addTagsToItem } = useTags();

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

  const handleChatWithItem = (item: any) => {
    setChatItem(item);
    setChatOpen(true);
  };

  const handleOpenChat = () => {
    setGlobalChatOpen(true);
  };

  const handleOpenSearch = () => {
    toast({
      title: "Coming soon",
      description: "Search functionality will be available soon!",
    });
  };

  const handleAddContentWithTags = async (type: string, data: any) => {
    try {
      // First add the content
      await handleAddContent(type, data);
      
      // If tags were provided, add them to the item
      if (data.tags && data.tags.length > 0) {
        // We need to get the item ID from the most recent item
        // This is a bit of a workaround - in a production app you'd want to return the ID from handleAddContent
        setTimeout(async () => {
          await fetchItems(); // Refresh items to get the new one
          // The new item should be at the top of the list
          const latestItem = items[0];
          if (latestItem) {
            await addTagsToItem(latestItem.id, data.tags);
            await fetchItems(); // Refresh again to show the tags
          }
        }, 1000);
      }
    } catch (error) {
      console.error('Error adding content with tags:', error);
    }
  };

  const toggleAddSection = () => {
    updatePreference(!hideAddSection);
  };

  if (loading || preferencesLoading) {
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
        <div className="mb-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-semibold">Quick Add</h2>
            <Button
              variant="ghost"
              size="sm"
              onClick={toggleAddSection}
              className="flex items-center space-x-1"
            >
              {hideAddSection ? (
                <>
                  <ChevronDown className="h-4 w-4" />
                  <span>Show</span>
                </>
              ) : (
                <>
                  <ChevronUp className="h-4 w-4" />
                  <span>Hide</span>
                </>
              )}
            </Button>
          </div>

          {!hideAddSection && (
            <Tabs defaultValue="media" className="mb-6">
              <TabsList className="grid w-full grid-cols-3">
                <TabsTrigger value="media">Add media</TabsTrigger>
                <TabsTrigger value="note">New note</TabsTrigger>
                <TabsTrigger value="link">Paste link</TabsTrigger>
              </TabsList>
              
              <TabsContent value="media" className="mt-6">
                <MediaUploadTab 
                  onAddContent={handleAddContentWithTags}
                  getSuggestedTags={getSuggestedTags}
                />
              </TabsContent>
              
              <TabsContent value="note" className="mt-6">
                <TextNoteTab 
                  onAddContent={handleAddContentWithTags}
                  getSuggestedTags={getSuggestedTags}
                />
              </TabsContent>
              
              <TabsContent value="link" className="mt-6">
                <LinkTab 
                  onAddContent={handleAddContentWithTags}
                  getSuggestedTags={getSuggestedTags}
                />
              </TabsContent>
            </Tabs>
          )}
        </div>
        
        <StashHeader itemCount={items.length} />

        <ContentGrid
          items={items}
          onDeleteItem={handleDeleteItem}
          onEditItem={handleEditItem}
          onChatWithItem={handleChatWithItem}
        />
      </main>

      <EditItemDialog
        open={editDialogOpen}
        onOpenChange={setEditDialogOpen}
        item={editingItem}
        onSave={handleSaveItem}
      />

      <ChatInterface
        isOpen={chatOpen}
        onClose={() => setChatOpen(false)}
        item={chatItem}
      />

      <GlobalChatInterface
        isOpen={globalChatOpen}
        onClose={() => setGlobalChatOpen(false)}
      />
    </div>
  );
};

export default Index;
