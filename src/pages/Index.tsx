
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useTags } from '@/hooks/useTags';
import HeaderSection from '@/components/HeaderSection';
import SubscriptionBanner from '@/components/SubscriptionBanner';
import UnifiedInputPanel from '@/components/UnifiedInputPanel';
import SearchSection from '@/components/SearchSection';
import ContentGrid from '@/components/ContentGrid';
import EditItemSheet from '@/components/EditItemSheet';
import GlobalChatInterface from '@/components/GlobalChatInterface';
import { getSuggestedTags as getSuggestedTagsFromApi } from '@/utils/aiOperations';

const Index = () => {
  const { user, loading } = useAuth();
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
  const [isInputUICollapsed, setIsInputUICollapsed] = useState(() => {
    // Minimize input panel by default for WebKit browsers (Safari) but not Chrome
    const isWebKit = /WebKit/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent);
    return isWebKit;
  });
  
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearchActive, setIsSearchActive] = useState(false);
  const [showStickyNotes, setShowStickyNotes] = useState(true);
  const [isFilterPanelOpen, setIsFilterPanelOpen] = useState(false);

  const getSuggestedTags = async (content) => {
    if (!user) return [];
    return await getSuggestedTagsFromApi(content);
  };

  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
  }, [loading, user, navigate]);

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

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-100 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-4 text-gray-600">Loading...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return null; // Will redirect via useEffect
  }

  return (
    <div className="min-h-screen bg-white">
      <HeaderSection 
        user={user}
      />

      <div className="container mx-auto px-4">
        <SubscriptionBanner />
      </div>

      <UnifiedInputPanel
        isInputUICollapsed={isInputUICollapsed}
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
        isFilterPanelOpen={isFilterPanelOpen}
        onFilterPanelToggle={setIsFilterPanelOpen}
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
    </div>
  );
};

export default Index;
