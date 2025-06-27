
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useTags } from '@/hooks/useTags';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { FileText, Link, Upload, MessageSquare, Settings, LogOut, ChevronUp, ChevronDown } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import StashHeader from '@/components/StashHeader';
import ContentGrid from '@/components/ContentGrid';
import EditItemSheet from '@/components/EditItemSheet';
import GlobalChatInterface from '@/components/GlobalChatInterface';
import TextNoteTab from '@/components/TextNoteTab';
import LinkTab from '@/components/LinkTab';
import MediaUploadTab from '@/components/MediaUploadTab';
import SettingsModal from '@/components/SettingsModal';
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
  const [showSettings, setShowSettings] = useState(false);
  const [isInputUICollapsed, setIsInputUICollapsed] = useState(false);
  const [activeTab, setActiveTab] = useState('text');

  const getSuggestedTags = async (content) => {
    if (!user) return [];
    return await getSuggestedTagsFromApi(content);
  };

  const getUserInitials = (email: string) => {
    return email?.charAt(0).toUpperCase() || 'U';
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
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

  const handleSourceClick = (sourceId: string) => {
    const item = items.find(item => item.id === sourceId);
    if (item) {
      setEditingItem(item);
    }
  };

  const handleViewAllSources = (sourceIds: string[]) => {
    // Create a filter that shows only the source items
    const sourceTagFilter = sourceIds;
    // For now, we'll implement this as showing all items
    // In the future, you could enhance this to filter by specific item IDs
    setSelectedTags([]);
  };

  // Get current date
  const currentDate = new Date().toLocaleDateString('en-US', { 
    month: 'long', 
    day: 'numeric', 
    year: 'numeric' 
  });

  if (!user) {
    return null;
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header with logo, date and user menu */}
      <div className="w-full bg-background">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center ml-2.5">
            <h1 className="text-2xl font-bold mt-2">
              <span className="font-bold">Noodle Notes</span>
              <span className="text-muted-foreground font-normal"> / {currentDate}</span>
            </h1>
          </div>
          <div className="flex items-center gap-4">
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" className="relative h-10 w-10 rounded-full p-0">
                  <Avatar className="h-10 w-10 bg-purple-400">
                    <AvatarFallback className="bg-purple-400 text-white font-medium">
                      {getUserInitials(user.email || '')}
                    </AvatarFallback>
                  </Avatar>
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent className="w-56" align="end" forceMount>
                <DropdownMenuLabel className="font-normal">
                  <div className="flex flex-col space-y-1">
                    <p className="text-sm font-medium leading-none">
                      {user.email}
                    </p>
                  </div>
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => setShowSettings(true)}>
                  <Settings className="mr-2 h-4 w-4" />
                  Settings
                </DropdownMenuItem>
                <DropdownMenuItem onClick={handleSignOut}>
                  <LogOut className="mr-2 h-4 w-4" />
                  Sign out
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </div>
      
      {/* Tab bar with integrated collapse button - contained style with rounded corners */}
      <div className="w-full bg-background">
        <div className="container mx-auto px-4">
          <div className="inline-flex items-center bg-muted rounded-lg p-1 w-full max-w-md">
            <Tabs value={activeTab} onValueChange={handleTabChange} className="flex-1">
              <TabsList className="grid w-full grid-cols-3 h-12 bg-transparent border-0">
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
              className="ml-2 flex items-center gap-1 bg-transparent hover:bg-muted-foreground/10"
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

      {/* Chat button and filter section - moved down by 18px */}
      <div className="container mx-auto px-4 pt-4 pb-4">
        <div className="flex items-center justify-between mb-4">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setShowGlobalChat(true)}
            className="flex items-center gap-2"
          >
            <MessageSquare className="h-4 w-4" />
            Noodle assistant
          </Button>
          <StashHeader 
            onShowGlobalChat={() => setShowGlobalChat(true)}
            itemCount={items.filter(item => !item.isOptimistic).length}
            tags={tags}
            selectedTags={selectedTags}
            onTagFilterChange={handleTagFilterChange}
          />
        </div>
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

      <EditItemSheet
        open={!!editingItem}
        onOpenChange={(open) => !open && setEditingItem(null)}
        item={editingItem}
        onSave={handleSaveItem}
      />

      <GlobalChatInterface
        isOpen={showGlobalChat}
        onClose={() => setShowGlobalChat(false)}
        onSourceClick={handleSourceClick}
        onViewAllSources={handleViewAllSources}
      />

      <SettingsModal 
        open={showSettings} 
        onOpenChange={setShowSettings}
      />
    </div>
  );
};

export default Index;
