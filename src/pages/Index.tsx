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
import { supabase } from '@/integrations/supabase/client';

const Index = () => {
  const { user, loading } = useAuth();
  const [editingItem, setEditingItem] = useState(null);
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [chatItem, setChatItem] = useState(null);
  const [chatOpen, setChatOpen] = useState(false);
  const [globalChatOpen, setGlobalChatOpen] = useState(false);
  const [currentTab, setCurrentTab] = useState('media');
  const [tagFilters, setTagFilters] = useState<string[]>([]);
  const { toast } = useToast();
  const navigate = useNavigate();
  
  const { items, fetchItems, addOptimisticItem, removeOptimisticItem } = useItems();
  const { handleAddContent, handleSaveItem, handleDeleteItem } = useItemOperations(
    fetchItems, 
    addOptimisticItem, 
    removeOptimisticItem
  );
  const { hideAddSection, updatePreference, loading: preferencesLoading } = useUserPreferences();
  const { getSuggestedTags: getPopularTags, getAISuggestedTags } = useTags();

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

  const toggleAddSection = () => {
    updatePreference(!hideAddSection);
  };

  const handleTabChange = (value: string) => {
    // If the add section is hidden and user clicks on any tab (including current), expand it
    if (hideAddSection) {
      updatePreference(false);
    }
    setCurrentTab(value);
  };

  const handleTabClick = (value: string) => {
    // If clicking on the currently active tab and section is hidden, expand it
    if (value === currentTab && hideAddSection) {
      updatePreference(false);
    }
    setCurrentTab(value);
  };

  const handleTagFiltersChange = (selectedTags: string[]) => {
    setTagFilters(selectedTags);
  };

  // AI-based suggested tags function that analyzes content
  const getAISuggestedTags = async (content: { title?: string; content?: string; description?: string }): Promise<string[]> => {
    if (!user) return [];
    
    try {
      const { data, error } = await supabase.functions.invoke('get-relevant-tags', {
        body: {
          title: content.title || '',
          content: content.content || '',
          description: content.description || ''
        }
      });

      if (error) {
        console.error('Error getting AI suggested tags:', error);
        // Fallback to popular tags
        return getPopularTags(5);
      }

      return data?.tags || getPopularTags(5);
    } catch (error) {
      console.error('Exception getting AI suggested tags:', error);
      // Fallback to popular tags
      return getPopularTags(5);
    }
  };

  // Create a wrapper function that matches LinkTab's expected signature
  const getPopularTagsForLink = (limit: number = 5): string[] => {
    return getPopularTags(limit);
  };

  // Filter items based on selected tags
  const filteredItems = tagFilters.length === 0 
    ? items 
    : items.filter(item => {
        // Get item tags from the database
        // This will be handled by the ContentGrid component
        return true; // For now, we'll let ContentGrid handle the filtering
      });

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
            <Tabs defaultValue="media" className="w-full" value={currentTab} onValueChange={handleTabChange}>
              <div className="flex items-center justify-between">
                <TabsList className="grid grid-cols-3 w-full">
                  <TabsTrigger value="media" onClick={() => handleTabClick('media')}>Add media</TabsTrigger>
                  <TabsTrigger value="note" onClick={() => handleTabClick('note')}>New note</TabsTrigger>
                  <TabsTrigger value="link" onClick={() => handleTabClick('link')}>Paste link</TabsTrigger>
                </TabsList>
                
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={toggleAddSection}
                  className="flex items-center ml-4"
                >
                  {hideAddSection ? (
                    <ChevronDown className="h-4 w-4" />
                  ) : (
                    <ChevronUp className="h-4 w-4" />
                  )}
                </Button>
              </div>

              {!hideAddSection && (
                <>
                  <TabsContent value="media" className="mt-6">
                    <MediaUploadTab 
                      onAddContent={handleAddContent}
                      getSuggestedTags={getAISuggestedTags}
                    />
                  </TabsContent>
                  
                  <TabsContent value="note" className="mt-6">
                    <TextNoteTab 
                      onAddContent={handleAddContent}
                      getSuggestedTags={getAISuggestedTags}
                    />
                  </TabsContent>
                  
                  <TabsContent value="link" className="mt-6">
                    <LinkTab 
                      onAddContent={handleAddContent}
                      getSuggestedTags={getPopularTagsForLink}
                    />
                  </TabsContent>
                </>
              )}
            </Tabs>
          </div>
        </div>
        
        <StashHeader 
          itemCount={filteredItems.length} 
          onTagFiltersChange={handleTagFiltersChange}
        />

        <ContentGrid
          items={filteredItems}
          onDeleteItem={handleDeleteItem}
          onEditItem={handleEditItem}
          onChatWithItem={handleChatWithItem}
          tagFilters={tagFilters}
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
