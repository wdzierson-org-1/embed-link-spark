
import { useState, useEffect, useMemo, useRef } from 'react';
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
import ContentGrid from '@/components/ContentGrid';
import { NowProvider } from '@/hooks/useNow';
import EditItemSheet from '@/components/EditItemSheet';
import ChatMole from '@/components/ChatMole';
import ConversationsView from '@/components/ConversationsView';
import LoadingInterstitial from '@/components/LoadingInterstitial';
import { PaperBackdrop } from '@/components/machine/PaperBackdrop';
import { getSuggestedTags as getSuggestedTagsFromApi } from '@/utils/aiOperations';
import { sweepStagingOrphans } from '@/utils/stagedUploader';
import { enrichmentState, isReadingDocument } from '@/utils/itemAssembly';

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

  // The opened card, as it was when tapped. The panel shows the live row (below): a save opened
  // while Stash was still reading it fills in as enrichment lands, instead of staying "Untitled"
  const [openedItem, setEditingItem] = useState(null);
  const editingItem = useMemo(
    () => (openedItem ? (items.find((item) => item.id === openedItem.id) ?? openedItem) : null),
    [openedItem, items],
  );
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

  // How many saves Stash is still reading, for the toolbar's status line. The assembling
  // window closes on time alone (no realtime event), so a slow clock ticks while any are open.
  const [clockMs, setClockMs] = useState(() => Date.now());
  const readingCount = items.filter(
    (item) => !item.isOptimistic && (isReadingDocument(item, clockMs) || enrichmentState(item, clockMs) === 'pending')
  ).length;
  useEffect(() => {
    if (!readingCount) return;
    const timer = setInterval(() => setClockMs(Date.now()), 30_000);
    return () => clearInterval(timer);
  }, [readingCount]);

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

  // Deep link from agents/citations: /home#item=<uuid> opens that card once
  // the library has loaded, then clears the hash so reloads don't reopen it.
  useEffect(() => {
    const match = /^#item=([0-9a-f-]{36})$/i.exec(window.location.hash);
    if (!match || !items.length) return;
    const item = items.find((it) => it.id === match[1]);
    if (item) setEditingItem(item);
    history.replaceState(null, '', window.location.pathname + window.location.search);
  }, [items]);

  if (loading || (user && isInitialLoadInProgress)) {
    return <LoadingInterstitial />;
  }

  if (!user) {
    return null; // Will redirect via useEffect
  }

  const realItemCount = items.filter(item => !item.isOptimistic).length;

  return (
    <div className="relative isolate min-h-screen bg-paper">
      {/* DESIGN-v2 paper with tooth: the cutting-mat dots, stippled spheres and grain, fixed so
          the cards scroll over a still surface */}
      <PaperBackdrop />
      {/* Header lives INSIDE the dock-padded wrapper so its container centers
          on the same axis as the content below — logo/avatar edges align with
          the capture panel, toolbar, and cards whether or not the mole is pinned */}
      <div className={`relative ${molePinned ? 'transition-[padding] duration-200 sm:pl-[384px]' : 'transition-[padding] duration-200'}`}>
        <HeaderSection
          user={user}
        />
        {/* Collapse this spacing when there is no subscription notice. */}
        <div className="container mx-auto px-4 empty:hidden [&>*]:mt-4 [&>*:last-child]:mb-4">
          <SubscriptionBanner />
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
            readingCount={readingCount}
          />
          </div>
        )}

        <main className="container mx-auto px-4 pb-28">
          {mainView === 'chats' ? (
            <ConversationsView
              onOpenConversation={handleOpenConversation}
              onBack={() => setMainView('cards')}
            />
          ) : (
            <>
              {focusItemIds && (
                // The machine saying what it's showing: a black tag with its own way out
                <div className="mb-4 inline-flex items-center bg-ink font-pixel text-pixel leading-none text-white">
                  <span className="px-2 pb-[5px] pt-1.5">
                    showing {focusItemIds.length} {focusItemIds.length === 1 ? 'card' : 'cards'} from this answer
                  </span>
                  <button
                    onClick={() => setFocusItemIds(null)}
                    className="self-stretch border-l border-white/25 px-2 pb-[5px] pt-1.5 hover:bg-spot hover:text-spot-on"
                  >
                    clear
                  </button>
                </div>
              )}
              <NowProvider>
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
              </NowProvider>
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
