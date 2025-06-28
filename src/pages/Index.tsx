
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useTags } from '@/hooks/useTags';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { FileText, Link, Upload, Search, Settings, LogOut, ChevronUp, ChevronDown, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNavigate } from 'react-router-dom';
import StashHeader from '@/components/StashHeader';
import ContentGrid from '@/components/ContentGrid';
import EditItemSheet from '@/components/EditItemSheet';
import GlobalChatInterface from '@/components/GlobalChatInterface';
import TextNoteTab from '@/components/TextNoteTab';
import LinkTab from '@/components/LinkTab';
import MediaUploadTab from '@/components/MediaUploadTab';
import SettingsModal from '@/components/SettingsModal';
import PinnedChatWidget from '@/components/PinnedChatWidget';
import { getSuggestedTags as getSuggestedTagsFromApi } from '@/utils/aiOperations';

const Index = () => {
  const { user } = useAuth();
  const navigate = useNavigate();
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
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearchActive, setIsSearchActive] = useState(false);

  const getSuggestedTags = async (content) => {
    if (!user) return [];
    return await getSuggestedTagsFromApi(content);
  };

  const getUserInitials = (email: string) => {
    return email?.charAt(0).toUpperCase() || 'U';
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    navigate('/');
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

  const handleTabChange = (value) => {
    setActiveTab(value);
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
    setSelectedTags([]);
  };

  const handleSearchClick = () => {
    setIsSearchActive(true);
  };

  const handleSearchClear = () => {
    setSearchQuery('');
    setIsSearchActive(false);
  };

  const handleSearchChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchQuery(e.target.value);
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
    <div className="min-h-screen bg-white">
      {/* Header with logo, date and user menu - now white background with increased height */}
      <div className="w-full bg-white border-b border-gray-200">
        <div className="container mx-auto px-4 h-20 flex items-center justify-between">
          <div className="flex items-center space-x-4">
            {/* Logo */}
            <div className="flex items-center space-x-2">
              <div className="w-8 h-8 bg-gray-600 rounded-lg flex items-center justify-center">
                <span className="text-white font-bold text-sm">N</span>
              </div>
              <span className="text-xl font-bold text-gray-900">Noodle</span>
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

      {/* Grey background section with increased spacing */}
      <div className="w-full bg-gray-100">
        <div className="pt-8 pb-8">
          <div className="container mx-auto px-4">
            <div className="flex items-center bg-gray-200 rounded-lg p-1 w-full">
              <Tabs value={activeTab} onValueChange={handleTabChange} className="flex-1">
                <TabsList className="grid w-full grid-cols-3 h-12 bg-transparent border-0">
                  <TabsTrigger 
                    value="text" 
                    className="flex items-center gap-2 data-[state=active]:bg-white data-[state=active]:shadow-sm hover:bg-gray-300 transition-colors"
                  >
                    <FileText className="h-4 w-4" />
                    Text Note
                  </TabsTrigger>
                  <TabsTrigger 
                    value="link" 
                    className="flex items-center gap-2 data-[state=active]:bg-white data-[state=active]:shadow-sm hover:bg-gray-300 transition-colors"
                  >
                    <Link className="h-4 w-4" />
                    Link
                  </TabsTrigger>
                  <TabsTrigger 
                    value="media" 
                    className="flex items-center gap-2 data-[state=active]:bg-white data-[state=active]:shadow-sm hover:bg-gray-300 transition-colors"
                  >
                    <Upload className="h-4 w-4" />
                    Upload
                  </TabsTrigger>
                </TabsList>
              </Tabs>
              
              <Button
                variant="ghost"
                size="sm"
                onClick={toggleInputUI}
                className="ml-2 flex items-center gap-1 bg-transparent hover:bg-gray-300/50"
              >
                {isInputUICollapsed ? (
                  <ChevronDown className="h-4 w-4" />
                ) : (
                  <ChevronUp className="h-4 w-4" />
                )}
              </Button>
            </div>
            
            {/* Input UI Area with reduced spacing */}
            <div className={`overflow-hidden transition-all duration-300 ease-in-out ${
              isInputUICollapsed ? 'max-h-0 opacity-0' : 'max-h-96 opacity-100'
            }`}>
              <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
                <TabsContent value="text" className="mt-2 pb-0">
                  <TextNoteTab
                    onAddContent={handleAddContent}
                    getSuggestedTags={getSuggestedTags}
                  />
                </TabsContent>
                
                <TabsContent value="link" className="mt-2 pb-0">
                  <LinkTab
                    onAddContent={handleAddContent}
                    getSuggestedTags={() => []}
                  />
                </TabsContent>
                
                <TabsContent value="media" className="mt-2 pb-0">
                  <MediaUploadTab
                    onAddContent={handleAddContent}
                    getSuggestedTags={getSuggestedTags}
                  />
                </TabsContent>
              </Tabs>
            </div>
          </div>
        </div>
      </div>

      {/* Search and filter section - white background */}
      <div className="container mx-auto px-4 pt-6 pb-4 bg-white">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center">
            {!isSearchActive ? (
              <Button
                variant="outline"
                size="sm"
                onClick={handleSearchClick}
                className="flex items-center gap-2 bg-white border-gray-300 hover:bg-gray-50 transition-all duration-200"
              >
                <Search className="h-4 w-4" />
                Search notes
              </Button>
            ) : (
              <div className="flex items-center gap-2 animate-in slide-in-from-left-2 duration-200">
                <div className="relative flex items-center border border-gray-300 rounded-md bg-white px-3 py-2 w-64">
                  <Search className="h-4 w-4 text-gray-400 mr-2" />
                  <Input
                    value={searchQuery}
                    onChange={handleSearchChange}
                    placeholder="Search notes..."
                    className="border-0 p-0 h-auto focus-visible:ring-0 focus-visible:ring-offset-0"
                    autoFocus
                  />
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={handleSearchClear}
                    className="h-6 w-6 p-0 ml-2 hover:bg-gray-100"
                  >
                    <X className="h-3 w-3" />
                  </Button>
                </div>
              </div>
            )}
          </div>
          <StashHeader 
            onShowGlobalChat={() => setShowGlobalChat(true)}
            itemCount={items.filter(item => !item.isOptimistic).length}
            tags={tags}
            selectedTags={selectedTags}
            onTagFilterChange={handleTagFilterChange}
          />
        </div>
      </div>
      
      <main className="container mx-auto px-4 pb-8 bg-white">
        <ContentGrid 
          items={items} 
          onDeleteItem={handleDeleteItem}
          onEditItem={handleEditItem}
          onChatWithItem={handleChatWithItem}
          tagFilters={selectedTags}
          searchQuery={searchQuery}
        />
      </main>

      {/* Enhanced Pinned Chat Widget */}
      <PinnedChatWidget onExpandToModal={() => setShowGlobalChat(true)} />

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
