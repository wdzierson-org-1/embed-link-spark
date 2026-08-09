import { useEffect, useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Search, Loader2 } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { SUPABASE_URL } from '@/integrations/supabase/client';
import HeaderSection from '@/components/HeaderSection';
import ContentGrid from '@/components/ContentGrid';

interface DiscoverItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  url?: string;
  file_path?: string;
  type: string;
  created_at: string;
  user_id?: string;
  tags?: string[];
  is_public?: boolean;
  comment_count?: number;
  profile?: {
    username: string;
    display_name?: string;
    avatar_url?: string;
  };
}

type Pagination = {
  offset: number;
  limit: number;
  total: number;
  hasMore: boolean;
};

export function Discover() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [items, setItems] = useState<DiscoverItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [offset, setOffset] = useState(0);
  const [hasMore, setHasMore] = useState(true);

  const fetchDiscoverFeed = useCallback(async (currentOffset = 0, isLoadMore = false) => {
    try {
      if (!isLoadMore) setLoading(true);
      else setLoadingMore(true);

      const params = new URLSearchParams({
        offset: currentOffset.toString(),
        limit: '20',
        ...(searchQuery && { search: searchQuery }),
      });

      const response = await fetch(
        `${SUPABASE_URL}/functions/v1/get-discover-feed?${params}`
      );

      if (!response.ok) {
        throw new Error('Failed to fetch discover feed');
      }

      const data = await response.json();

      if (isLoadMore) {
        setItems(prev => [...prev, ...data.items]);
      } else {
        setItems(data.items);
      }

      setHasMore(data.pagination?.hasMore || false);
      setOffset(currentOffset + data.items.length);
    } catch (error) {
      console.error('Discover feed error:', error);
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [searchQuery]);

  useEffect(() => {
    fetchDiscoverFeed();
  }, [fetchDiscoverFeed]);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasMore && !loadingMore && !loading) {
          fetchDiscoverFeed(offset, true);
        }
      },
      { threshold: 0.1 }
    );

    const sentinel = document.getElementById('discover-scroll-sentinel');
    if (sentinel) {
      observer.observe(sentinel);
    }

    return () => observer.disconnect();
  }, [hasMore, loadingMore, loading, offset, fetchDiscoverFeed]);

  const handleSearch = (query: string) => {
    setSearchQuery(query);
    setOffset(0);
    setHasMore(true);
  };

  if (loading && !items.length) {
    return (
      <>
        <HeaderSection user={user} />
        <div className="min-h-screen bg-background flex items-center justify-center">
          <div className="text-center">
            <Loader2 className="h-8 w-8 animate-spin mx-auto mb-4 text-primary" />
            <p className="text-muted-foreground">Loading discover feed...</p>
          </div>
        </div>
      </>
    );
  }

  return (
    <>
      <HeaderSection user={user} />
      <div className="min-h-screen bg-background">
        {/* Page header */}
        <div className="border-b bg-card">
          <div className="max-w-4xl mx-auto px-4 py-8">
            <h1 className="text-3xl font-bold mb-2">Discover</h1>
            <p className="text-muted-foreground">
              Explore public items from the Stash community
            </p>
          </div>
        </div>

        {/* Search */}
        <div className="max-w-4xl mx-auto px-4 py-6">
          <div className="relative max-w-md">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              type="text"
              placeholder="Search items..."
              value={searchQuery}
              onChange={(e) => handleSearch(e.target.value)}
              className="pl-10"
            />
          </div>
        </div>

        {/* Content */}
        <div className="max-w-4xl mx-auto px-4 pb-8">
          {items.length === 0 && !loading ? (
            <Card>
              <CardContent className="text-center p-8">
                <p className="text-muted-foreground">
                  {searchQuery ? 'No items found matching your search.' : 'No items in the discover feed yet.'}
                </p>
              </CardContent>
            </Card>
          ) : (
            <>
              <ContentGrid
                items={items}
                onDeleteItem={() => {}}
                onEditItem={() => {}}
                onChatWithItem={() => {}}
                tagFilters={[]}
                searchQuery=""
                isPublicView={true}
                currentUserId={user?.id}
                onCommentClick={(itemId) => navigate(`/feed/${items.find(i => i.id === itemId)?.profile?.username}?openComment=${itemId}`)}
              />

              {/* Infinite scroll sentinel */}
              {hasMore && (
                <div id="discover-scroll-sentinel" className="flex justify-center py-8">
                  {loadingMore && <Loader2 className="h-6 w-6 animate-spin text-primary" />}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </>
  );
}
