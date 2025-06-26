
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useTags } from '@/hooks/useTags';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { FileText, Link, Upload, MessageSquare, LogOut, ChevronUp, ChevronDown } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
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
  const [isInputUICollapsed, setIsInputUICollapsed] = useState(false);
  const [activeTab, setActiveTab] = useState('text');

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

  const handleTabChange = (value) => {
    setActiveTab(value);
    // If UI is collapsed and user clicks a tab, expand it
    if (isInputUICollapsed) {
      setIsInputUICollapsed(false);
    }
  };

  const toggleInputUI = () => {
    setIsInputUICollapsed(!isInputUICollapsed);
  };

  if (!user) {
    return null;
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header with logo and chat/logout buttons - removed border-b */}
      <div className="w-full bg-background">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center">
            <h1 className="text-2xl font-bold ml-4 mt-2">Stash</h1>
          </div>
          <div className="flex items-center gap-4">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setShowGlobalChat(true)}
              className="flex items-center gap-2"
            >
              <MessageSquare className="h-4 w-4" />
              Chat
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => supabase.auth.signOut()}
              className="flex items-center gap-2"
            >
              <LogOut className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
      
      {/* Full-width tab bar with collapse button */}
      <div className="w-full bg-background">
        <div className="container mx-auto px-4">
          <div className="flex items-center justify-between">
            <Tabs value={activeTab} onValueChange={handleTabChange} className="flex-1">
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
            </Tabs>
            
            <Button
              variant="ghost"
              size="sm"
              onClick={toggleInputUI}
              className="ml-4 flex items-center gap-1"
            >
              {isInputUICollapsed ? (
                <ChevronDown className="h-4 w-4" />
              ) : (
                <ChevronUp className="h-4 w-4" />
              )}
            </Button>
          </div>
          
          {/* Input UI Area with animation */}
          <div className={`overflow-hidden transition-all duration-300 ease-in-out ${
            isInputUICollapsed ? 'max-h-0 opacity-0' : 'max-h-96 opacity-100'
          }`}>
            <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
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
      </div>

      {/* Item count and filter section */}
      <div className="container mx-auto px-4 pt-6 pb-4">
        <StashHeader 
          onShowGlobalChat={() => setShowGlobalChat(true)}
          itemCount={items.filter(item => !item.isOptimistic).length}
          tags={tags}
          selectedTags={selectedTags}
          onTagFilterChange={handleTagFilterChange}
        />
      </div>
      
      <main className="container mx-auto px-4 pb-8">
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
