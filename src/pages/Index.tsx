
import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { useItems } from '@/hooks/useItems';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useTags } from '@/hooks/useTags';
import { useServerSearch } from '@/hooks/useServerSearch';
import HeaderSection from '@/components/HeaderSection';
import SubscriptionBanner from '@/components/SubscriptionBanner';
import UnifiedInputPanel from '@/components/UnifiedInputPanel';
import LibraryToolbar from '@/components/LibraryToolbar';
import DismissibleHint from '@/components/DismissibleHint';
import ContentGrid from '@/components/ContentGrid';
import EditItemSheet from '@/components/EditItemSheet';
import ChatMole from '@/components/ChatMole';
import ConversationsView from '@/components/ConversationsView';
import { getSuggestedTags as getSuggestedTagsFromApi } from '@/utils/aiOperations';
import { sweepStagingOrphans } from '@/utils/stagedUploader';

const MOLE_PINNED_KEY = 'stash_mole_pinned';

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

  // Once per session: clear abandoned chip-time uploads (>24h, unreferenced)
  const stagingSweepRanRef = useRef(false);
  useEffect(() => {
    if (!user?.id || stagingSweepRanRef.current) return;
    stagingSweepRanRef.current = true;
    void sweepStagingOrphans(user.id);
  }, [user?.id]);

  const [editingItem, setEditingItem] = useState(null);
  const [selectedTags, setSelectedTags] = useState([]);

  const { tags } = useTags();
  const [searchQuery, setSearchQuery] = useState('');
  const { serverResultIds } = useServerSearch(searchQuery);
  const [molePinned, setMolePinned] = useState(() => {
    try {
      return localStorage.getItem(MOLE_PINNED_KEY) === 'true';
    } catch {
      return false;
    }
  });
  const [mainView, setMainView] = useState<'cards' | 'chats'>('cards');
  const [focusItemIds, setFocusItemIds] = useState<string[] | null>(null);
  const [openConvoReq, setOpenConvoReq] = useState<{ id: string; title: string | null; token: number } | null>(null);

  const getSuggestedTags = async (content) => {
    if (!user) return [];
    return await getSuggestedTagsFromApi(content);
  };

  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
    // Try-stash visitors (anonymous sessions) belong on the landing page —
    // the dashboard would self-heal a trial subscription for them otherwise
    if (!loading && user && (user as { is_anonymous?: boolean }).is_anonymous) {
      navigate('/');
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

  // Starting a new search clears any chat-answer focus — the search intent wins
  const handleSearchChange = (q: string) => {
    setSearchQuery(q);
    if (q.trim()) setFocusItemIds(null);
  };

  const handleFocusSources = (ids: string[] | null) => {
    setFocusItemIds(ids);
    if (ids) {
      setMainView('cards'); // focusing is a request to SEE items — the list yields
      // A floating mole overlays the content column (and the pill's Clear
      // button) — dock it so chat and focused cards sit side by side
      if (!molePinned) handleMolePinnedChange(true);
    }
  };

  const handleOpenConversation = (c: { id: string; title: string | null }) => {
    setOpenConvoReq({ ...c, token: Date.now() });
    handleMolePinnedChange(true); // surface the mole if minimized
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
      <div className={`relative ${molePinned ? 'transition-[padding] duration-200 sm:pl-[384px]' : 'transition-[padding] duration-200'}`}>
        {/* Extended animated gradient backdrop — page-level so it survives the
            capture panel being hidden in conversations/focus states */}
        <div className="pointer-events-none absolute inset-0 h-[200vh] animated-gradient opacity-30" />
        <div className="pointer-events-none absolute inset-0 h-[200vh] bg-gradient-to-b from-transparent via-background/50 via-background/30 to-background" />
        {/* Banner + hint share one spacing stack: every combination of them
            (minimized banner, dismissed hint, neither) keeps even 16px gaps,
            and the stack vanishes entirely when both are gone */}
        <div className="container mx-auto px-4 empty:hidden [&>*]:mt-4 [&>*:last-child]:mb-4">
          <SubscriptionBanner />
          <DismissibleHint id="capture-shortcuts">
            <b className="font-medium">Paste</b> a link anywhere on this page to capture it — or,{' '}
            <b className="font-medium">drop</b> files onto the box below
          </DismissibleHint>
        </div>

        {/* Capture is out of place while browsing conversations or focused on
            an answer's cards — hide the panel (and its gradient backdrop) there */}
        {mainView === 'cards' && !focusItemIds && (
          <UnifiedInputPanel
            onAddContent={handleAddContent}
            getSuggestedTags={getSuggestedTags}
          />
        )}

        {/* Search / count / tag filter only make sense once something is stashed.
            With the capture panel hidden (focus mode), give the toolbar breathing
            room below the header instead of hugging its drop shadow */}
        {realItemCount > 0 && mainView === 'cards' && (
          <div className={focusItemIds ? 'pt-[26px]' : ''}>
          <LibraryToolbar
            searchQuery={searchQuery}
            onSearchChange={handleSearchChange}
            itemCount={realItemCount}
            tags={tags}
            selectedTags={selectedTags}
            onTagFilterChange={setSelectedTags}
          />
          </div>
        )}

        <main className="container mx-auto px-4 pb-28 bg-white">
          {mainView === 'chats' ? (
            <ConversationsView
              onOpenConversation={handleOpenConversation}
              onBack={() => setMainView('cards')}
            />
          ) : (
            <>
              {focusItemIds && (
                <div className="mb-3 inline-flex items-center gap-2 rounded-full bg-violet-100 py-1 pl-3 pr-1.5 text-xs text-violet-700">
                  <span>Showing <b>{focusItemIds.length}</b> cards from this answer</span>
                  <button
                    onClick={() => setFocusItemIds(null)}
                    className="rounded-full bg-white px-2.5 py-0.5 text-[11.5px]"
                  >
                    Clear
                  </button>
                </div>
              )}
              <ContentGrid
                items={items}
                onDeleteItem={handleDeleteItem}
                onEditItem={handleEditItem}
                onChatWithItem={() => {}}
                tagFilters={selectedTags}
                searchQuery={searchQuery}
                serverResultIds={serverResultIds}
                focusItemIds={focusItemIds}
                compact={molePinned}
              />
            </>
          )}
        </main>
      </div>

      <EditItemSheet
        open={!!editingItem}
        onOpenChange={(open) => !open && setEditingItem(null)}
        item={editingItem}
        onSave={handleSaveItem}
        onDelete={handleDeleteItem}
      />

      <ChatMole
        pinned={molePinned}
        onPinnedChange={handleMolePinnedChange}
        onSourceClick={handleSourceClick}
        itemCount={realItemCount}
        conversationsOpen={mainView === 'chats'}
        onToggleConversations={() => setMainView(v => (v === 'chats' ? 'cards' : 'chats'))}
        focusedSourceIds={focusItemIds}
        onFocusSources={handleFocusSources}
        openConversationRequest={openConvoReq}
      />
    </div>
  );
};

export default Index;
