import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import ContentGrid from '@/components/ContentGrid';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { useAuth } from '@/hooks/useAuth';
import { useItemOperations } from '@/hooks/useItemOperations';
import { useToast } from '@/hooks/use-toast';

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
}

interface PublicFeedData {
  profile: PublicProfile;
  items: PublicItem[];
}

export const PublicFeed = () => {
  const { username } = useParams<{ username: string }>();
  const [data, setData] = useState<PublicFeedData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { user } = useAuth();
  const { toast } = useToast();
  
  // Mock fetchItems function for useItemOperations
  const fetchItems = async () => {
    // Refresh the public feed data
    if (username) {
      const response = await fetch(`https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/get-public-feed/${username}`);
      if (response.ok) {
        const feedData = await response.json();
        setData(feedData);
      }
    }
  };
  
  const { handleSaveItem } = useItemOperations(fetchItems);

  useEffect(() => {
    if (!username) return;

    const fetchPublicFeed = async () => {
      try {
        setLoading(true);
        const response = await fetch(`https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/get-public-feed/${username}`);
        
        if (!response.ok) {
          const errorData = await response.json();
          throw new Error(errorData.error || 'Failed to fetch public feed');
        }

        const feedData = await response.json();
        setData(feedData);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'An error occurred');
      } finally {
        setLoading(false);
      }
    };

    fetchPublicFeed();
  }, [username]);

  const handleTogglePrivacy = async (item: PublicItem) => {
    try {
      await handleSaveItem(item.id, { 
        is_public: !item.is_public 
      });
      
      toast({
        title: "Success",
        description: `Item set to ${item.is_public ? 'private' : 'public'}`,
      });
      
      // Refresh the feed
      fetchItems();
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to update item privacy",
        variant: "destructive",
      });
    }
  };

  if (loading) {
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

  const { profile, items } = data;

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <div className="border-b bg-card">
        <div className="max-w-4xl mx-auto px-4 py-8">
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
                {items.length} public {items.length === 1 ? 'item' : 'items'}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-4xl mx-auto px-4 py-8">
        {items.length === 0 ? (
          <Card>
            <CardContent className="text-center p-8">
              <p className="text-muted-foreground">No public items yet.</p>
            </CardContent>
          </Card>
        ) : (
          <ContentGrid 
            items={items} 
            onDeleteItem={() => {}} // Disabled for public view
            onEditItem={() => {}} // Disabled for public view
            onChatWithItem={() => {}} // Disabled for public view
            tagFilters={[]}
            searchQuery=""
            isPublicView={true}
            currentUserId={user?.id}
            onTogglePrivacy={handleTogglePrivacy}
          />
        )}
      </div>
    </div>
  );
};