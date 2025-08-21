import { useEffect, useState, useCallback } from 'react';
import { useParams, useSearchParams } from 'react-router-dom';
import ContentGrid from '@/components/ContentGrid';
import { Card, CardContent } from '@/components/ui/card';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Search } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useToast } from '@/hooks/use-toast';
import { CommentPanel } from '@/components/CommentPanel';
import { OwnerMenu } from '@/components/OwnerMenu';

interface PublicProfile {
  username: string;
  display_name?: string;
  bio?: string;
  avatar_url?: string;
}

interface PublicItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  url?: string;
  file_path?: string;
  type: string;
  created_at: string;
  tags?: string[];
  is_public?: boolean;
  user_id?: string;
  comments_enabled?: boolean;
}

interface PublicFeedData {
  profile: PublicProfile;
  items: PublicItem[];
  pagination?: {
    offset: number;
    limit: number;
    total: number;
    hasMore: boolean;
  };
}

export const PublicFeed = () => {
  const { username } = useParams<{ username: string }>();
  const [searchParams, setSearchParams] = useSearchParams();
  const [data, setData] = useState<PublicFeedData | null>(null);
  const [allItems, setAllItems] = useState<PublicItem[]>([]);
  const [displayedItems, setDisplayedItems] = useState<PublicItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCommentItem, setSelectedCommentItem] = useState<string | null>(null);
  const [offset, setOffset] = useState(0);
  const [hasMore, setHasMore] = useState(true);
  const { user } = useAuth();
  const { toast } = useToast();
  
  const isOwner = user?.id === data?.items[0]?.user_id;
  
  const fetchFeedData = useCallback(async (searchTerm = '', currentOffset = 0, isLoadMore = false) => {
    if (!username) return;

    try {
      if (!isLoadMore) setLoading(true);
      else setLoadingMore(true);

      const params = new URLSearchParams({
        offset: currentOffset.toString(),
        limit: '20',
        ...(searchTerm && { search: searchTerm })
      });

      const response = await fetch(
        `https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/get-public-feed/${username}?${params}`
      );
      
      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Failed to fetch public feed');
      }

      const feedData = await response.json();
      
      if (isLoadMore) {
        setAllItems(prev => [...prev, ...feedData.items]);
        setDisplayedItems(prev => [...prev, ...feedData.items]);
      } else {
        setAllItems(feedData.items);
        setDisplayedItems(feedData.items);
        setData(feedData);
      }
      
      setHasMore(feedData.pagination?.hasMore || false);
      setOffset(currentOffset + feedData.items.length);
      
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred');
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [username]);

  // Mock fetchItems function for useItemOperations
  const fetchItems = async () => {
    fetchFeedData(searchQuery, 0, false);
  };
  
  const { handleSaveItem } = useItemOperations(fetchItems);

  useEffect(() => {
    fetchFeedData();
    
    // Check for openComment parameter after auth redirect
    const openCommentId = searchParams.get('openComment');
    if (openCommentId) {
      setSelectedCommentItem(openCommentId);
      // Clean up the URL parameter
      setSearchParams(prev => {
        const newParams = new URLSearchParams(prev);
        newParams.delete('openComment');
        return newParams;
      });
    }
  }, [fetchFeedData, searchParams, setSearchParams]);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasMore && !loadingMore && !loading) {
          fetchFeedData(searchQuery, offset, true);
        }
      },
      { threshold: 0.1 }
    );

    const sentinel = document.getElementById('scroll-sentinel');
    if (sentinel) {
      observer.observe(sentinel);
    }

    return () => observer.disconnect();
  }, [hasMore, loadingMore, loading, offset, searchQuery, fetchFeedData]);

  const handleSearch = (query: string) => {
    setSearchQuery(query);
    setOffset(0);
    setHasMore(true);
    fetchFeedData(query, 0, false);
  };

  const handleTogglePrivacy = async (item: PublicItem) => {
    if (!isOwner) return;
    
    try {
      await handleSaveItem(item.id, { 
        is_public: !item.is_public 
      });
      
      toast({
        title: "Success",
        description: `Item set to ${item.is_public ? 'private' : 'public'}`,
      });
      
      fetchItems();
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to update item privacy",
        variant: "destructive",
      });
    }
  };

  const handleCommentClick = (itemId: string) => {
    setSelectedCommentItem(itemId);
  };

  if (loading && !data) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary mx-auto mb-4"></div>
          <p className="text-muted-foreground">Loading public feed...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <Card className="max-w-md mx-4">
          <CardContent className="text-center p-6">
            <h1 className="text-2xl font-bold mb-2">Feed Not Found</h1>
            <p className="text-muted-foreground mb-4">{error}</p>
            <Badge variant="outline">@{username}</Badge>
          </CardContent>
        </Card>
      </div>
    );
  }

  if (!data) return null;

  const { profile } = data;

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <div className="border-b bg-card">
        <div className="max-w-4xl mx-auto px-4 py-8">
          <div className="flex items-start justify-between">
            <div className="flex items-start gap-6">
              <Avatar className="h-20 w-20">
                <AvatarImage src={profile.avatar_url} />
                <AvatarFallback className="text-xl">
                  {(profile.display_name || profile.username).charAt(0).toUpperCase()}
                </AvatarFallback>
              </Avatar>
              
              <div className="flex-1">
                <h1 className="text-3xl font-bold mb-2">
                  {profile.display_name || profile.username}
                </h1>
                <Badge variant="outline" className="mb-3">@{profile.username}</Badge>
                {profile.bio && (
                  <p className="text-muted-foreground text-lg">{profile.bio}</p>
                )}
                <div className="mt-4 text-sm text-muted-foreground">
                  {allItems.length} public {allItems.length === 1 ? 'item' : 'items'}
                </div>
              </div>
            </div>

            {/* Owner Menu */}
            {isOwner && (
              <OwnerMenu profile={profile} />
            )}
          </div>
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
        {displayedItems.length === 0 && !loading ? (
          <Card>
            <CardContent className="text-center p-8">
              <p className="text-muted-foreground">
                {searchQuery ? 'No items found matching your search.' : 'No public items yet.'}
              </p>
            </CardContent>
          </Card>
        ) : (
          <>
            <ContentGrid 
              items={displayedItems} 
              onDeleteItem={() => {}} // Disabled for public view
              onEditItem={() => {}} // Disabled for public view
              onChatWithItem={() => {}} // Disabled for public view
              tagFilters={[]}
              searchQuery=""
              isPublicView={true}
              currentUserId={user?.id}
              onTogglePrivacy={isOwner ? handleTogglePrivacy : undefined}
              onCommentClick={handleCommentClick}
            />
            
            {/* Infinite scroll sentinel */}
            {hasMore && (
              <div 
                id="scroll-sentinel" 
                className="flex justify-center py-8"
              >
                {loadingMore && (
                  <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary"></div>
                )}
              </div>
            )}
          </>
        )}
      </div>

      {/* Comment Panel */}
      <CommentPanel
        itemId={selectedCommentItem || ''}
        isOpen={!!selectedCommentItem}
        onClose={() => setSelectedCommentItem(null)}
        isOwner={isOwner}
      />
    </div>
  );
};