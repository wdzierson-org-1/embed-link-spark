
import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useTags } from '@/hooks/useTags';
import HeaderSection from '@/components/HeaderSection';
import InputSection from '@/components/InputSection';
import SearchSection from '@/components/SearchSection';
import ContentGrid from '@/components/ContentGrid';
import EditItemSheet from '@/components/EditItemSheet';
import GlobalChatInterface from '@/components/GlobalChatInterface';
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
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearchActive, setIsSearchActive] = useState(false);
  const [showStickyNotes, setShowStickyNotes] = useState(true);

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

  if (!user) {
    return null;
  }

  return (
    <div className="min-h-screen bg-gray-100">
      <HeaderSection 
        user={user}
        onShowSettings={() => setShowSettings(true)}
      />

      <InputSection
        activeTab={activeTab}
        isInputUICollapsed={isInputUICollapsed}
        onTabChange={handleTabChange}
        onToggleInputUI={toggleInputUI}
        onAddContent={handleAddContent}
        getSuggestedTags={getSuggestedTags}
      />

      <SearchSection
        isSearchActive={isSearchActive}
        searchQuery={searchQuery}
        onSearchClick={handleSearchClick}
        onSearchClear={handleSearchClear}
        onSearchChange={handleSearchChange}
        onShowGlobalChat={() => setShowGlobalChat(true)}
        itemCount={items.filter(item => !item.isOptimistic).length}
        tags={tags}
        selectedTags={selectedTags}
        onTagFilterChange={handleTagFilterChange}
        showStickyNotes={showStickyNotes}
        onStickyNotesToggle={setShowStickyNotes}
      />
      
      <main className="container mx-auto px-4 pb-8 bg-white">
        <ContentGrid 
          items={items} 
          onDeleteItem={handleDeleteItem}
          onEditItem={handleEditItem}
          onChatWithItem={handleChatWithItem}
          tagFilters={selectedTags}
          searchQuery={searchQuery}
          showStickyNotes={showStickyNotes}
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
