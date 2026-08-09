
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import HeaderSection from '@/components/HeaderSection';
import SubscriptionBanner from '@/components/SubscriptionBanner';
import UnifiedInputPanel from '@/components/UnifiedInputPanel';
import LibraryToolbar, { type LibraryTypeFilter } from '@/components/LibraryToolbar';
import ContentGrid from '@/components/ContentGrid';
import EditItemSheet from '@/components/EditItemSheet';
import ChatMole from '@/components/ChatMole';
import { getSuggestedTags as getSuggestedTagsFromApi } from '@/utils/aiOperations';

const INPUT_UI_PREFERENCE_COOKIE = 'stash_input_ui_collapsed';
const MOLE_PINNED_KEY = 'stash_mole_pinned';

const readInputUiPreference = (): boolean | null => {
  if (typeof document === 'undefined') return null;

  const cookieValue = document.cookie
    .split('; ')
    .find((cookie) => cookie.startsWith(`${INPUT_UI_PREFERENCE_COOKIE}=`))
    ?.split('=')[1];

  if (cookieValue === 'true') return true;
  if (cookieValue === 'false') return false;
  return null;
};

const saveInputUiPreference = (isCollapsed: boolean) => {
  if (typeof document === 'undefined') return;
  const maxAgeSeconds = 60 * 60 * 24 * 365; // 1 year
  document.cookie = `${INPUT_UI_PREFERENCE_COOKIE}=${isCollapsed}; path=/; max-age=${maxAgeSeconds}; SameSite=Lax`;
};

const Index = () => {
  const { user, loading } = useAuth();
  const navigate = useNavigate();
  const {
    items,
    fetchItems,
    addOptimisticItem,
    removeOptimisticItem,
    clearSkeletonItems,
    isInitialLoadInProgress,
  } = useItems();
  const { handleAddContent, handleSaveItem, handleDeleteItem } = useItemOperations(
    fetchItems,
    addOptimisticItem,
    removeOptimisticItem,
    clearSkeletonItems
  );

  const [editingItem, setEditingItem] = useState(null);
  const [selectedTags, setSelectedTags] = useState([]);
  const [isInputUICollapsed, setIsInputUICollapsed] = useState(() => {
    const savedPreference = readInputUiPreference();
    if (savedPreference !== null) return savedPreference;

    // Minimize input panel by default for WebKit browsers (Safari) but not Chrome
    const isWebKit = /WebKit/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent);
    return isWebKit;
  });

  const [searchQuery, setSearchQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<LibraryTypeFilter>('all');
  const [molePinned, setMolePinned] = useState(() => {
    try {
      return localStorage.getItem(MOLE_PINNED_KEY) === 'true';
    } catch {
      return false;
    }
  });

  const getSuggestedTags = async (content) => {
    if (!user) return [];
    return await getSuggestedTagsFromApi(content);
  };

  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
  }, [loading, user, navigate]);

  const handleMolePinnedChange = (pinned: boolean) => {
    setMolePinned(pinned);
    try {
      localStorage.setItem(MOLE_PINNED_KEY, String(pinned));
    } catch {
      // localStorage unavailable — pin state just won't persist
    }
  };

  const handleEditItem = (item) => {
    setEditingItem(item);
  };

  const handleSourceClick = (sourceId: string) => {
    const item = items.find(item => item.id === sourceId);
    if (item) {
      setEditingItem(item);
    }
  };

  const toggleInputUI = () => {
    setIsInputUICollapsed(!isInputUICollapsed);
  };

  const handleUserToggleInputUI = () => {
    const nextState = !isInputUICollapsed;
    setIsInputUICollapsed(nextState);
    saveInputUiPreference(nextState);
  };

  if (loading || (user && isInitialLoadInProgress)) {
    const loadingLabel = loading ? 'Loading...' : 'Loading your items...';
    return (
      <div className="min-h-screen bg-gray-100 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-4 text-gray-600">{loadingLabel}</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return null; // Will redirect via useEffect
  }

  const realItemCount = items.filter(item => !item.isOptimistic).length;

  return (
    <div className="min-h-screen bg-white">
      <HeaderSection
        user={user}
      />

      {/* Content shifts right when the mole is pinned as a left dock */}
      <div className={molePinned ? 'transition-[padding] duration-200 sm:pl-[384px]' : 'transition-[padding] duration-200'}>
        <div className="container mx-auto px-4">
          <SubscriptionBanner />
        </div>

        <UnifiedInputPanel
          isInputUICollapsed={isInputUICollapsed}
          onToggleInputUI={toggleInputUI}
          onUserToggleInputUI={handleUserToggleInputUI}
          onAddContent={handleAddContent}
          getSuggestedTags={getSuggestedTags}
        />

        <div className="container mx-auto px-4 pt-1">
          <p className="text-xs text-gray-400">
            <b className="font-medium text-gray-500">Paste</b> a link anywhere on this page ·{' '}
            <b className="font-medium text-gray-500">drop</b> files onto the box ·{' '}
            start a chat message with <b className="font-medium text-gray-500">remember:</b> to save it as a note
          </p>
        </div>

        <LibraryToolbar
          searchQuery={searchQuery}
          onSearchChange={setSearchQuery}
          typeFilter={typeFilter}
          onTypeFilterChange={setTypeFilter}
          itemCount={realItemCount}
        />

        <main className="container mx-auto px-4 pb-28 bg-white">
          <ContentGrid
            items={items}
            onDeleteItem={handleDeleteItem}
            onEditItem={handleEditItem}
            onChatWithItem={() => {}}
            tagFilters={selectedTags}
            searchQuery={searchQuery}
            typeFilter={typeFilter}
            compact={molePinned}
          />
        </main>
      </div>

      <EditItemSheet
        open={!!editingItem}
        onOpenChange={(open) => !open && setEditingItem(null)}
        item={editingItem}
        onSave={handleSaveItem}
      />

      <ChatMole
        pinned={molePinned}
        onPinnedChange={handleMolePinnedChange}
        onSourceClick={handleSourceClick}
        itemCount={realItemCount}
      />
    </div>
  );
};

export default Index;
