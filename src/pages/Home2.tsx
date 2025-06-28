
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useTags } from '@/hooks/useTags';
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
import { MessageSquare, Settings, LogOut } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import StashHeader from '@/components/StashHeader';
import ContentGrid from '@/components/ContentGrid';
import EditItemSheet from '@/components/EditItemSheet';
import GlobalChatInterface from '@/components/GlobalChatInterface';
import SettingsModal from '@/components/SettingsModal';
import UnifiedContentInput from '@/components/UnifiedContentInput';
import { getSuggestedTags as getSuggestedTagsFromApi } from '@/utils/aiOperations';

const Home2 = () => {
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
    setShowGlobalChat(true);
  };

  const handleTagFilterChange = (tags) => {
    setSelectedTags(tags);
  };

  const handleSourceClick = (sourceId: string) => {
    const item = items.find(item => item.id === sourceId);
    if (item) {
      setEditingItem(item);
    }
  };

  const handleViewAllSources = (sourceIds: string[]) => {
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
          <div className="flex items-center space-x-4">
            {/* Logo */}
            <div className="flex items-center space-x-2">
              <div className="w-8 h-8 bg-gray-600 rounded-lg flex items-center justify-center">
                <span className="text-white font-bold text-sm">N</span>
              </div>
              <span className="text-xl font-bold text-gray-900">Noodle</span>
              <span className="text-sm text-muted-foreground bg-blue-100 px-2 py-1 rounded">v2</span>
            </div>
            
            {/* Date */}
            <div className="text-muted-foreground">
              <span className="font-normal">/ {currentDate}</span>
            </div>
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
      
      {/* Unified Content Input - replaces the tab system */}
      <div className="container mx-auto px-4 pt-6">
        <UnifiedContentInput
          onAddContent={handleAddContent}
          getSuggestedTags={getSuggestedTags}
        />
      </div>

      {/* Chat button and filter section */}
      <div className="container mx-auto px-4 pt-6 pb-4">
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

export default Home2;
