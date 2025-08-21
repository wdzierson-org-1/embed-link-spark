import { useState, useEffect } from 'react';
import { X, Send, MessageCircle, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { ScrollArea } from '@/components/ui/scroll-area';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

interface Comment {
  id: string;
  content: string;
  created_at: string;
  updated_at: string;
  parent_comment_id: string | null;
  user_id: string;
  user_profiles: {
    username: string;
    display_name: string | null;
    avatar_url: string | null;
  };
}

interface CommentPanelProps {
  itemId: string;
  isOpen: boolean;
  onClose: () => void;
  isOwner?: boolean;
}

export const CommentPanel = ({ itemId, isOpen, onClose, isOwner }: CommentPanelProps) => {
  const [comments, setComments] = useState<Comment[]>([]);
  const [newComment, setNewComment] = useState('');
  const [loading, setLoading] = useState(false);
  const [commentsEnabled, setCommentsEnabled] = useState(true);
  const { user } = useAuth();
  const { toast } = useToast();

  useEffect(() => {
    if (isOpen && itemId) {
      fetchComments();
    }
  }, [isOpen, itemId]);

  const fetchComments = async () => {
    try {
      const response = await supabase.functions.invoke('get-comments', {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });

      if (response.error) {
        throw response.error;
      }

      const url = `https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/get-comments/${itemId}`;
      const directResponse = await fetch(url);
      const data = await directResponse.json();

      if (!directResponse.ok) {
        throw new Error(data.error || 'Failed to fetch comments');
      }

      setComments(data.comments || []);
      setCommentsEnabled(data.commentsEnabled !== false);
    } catch (error) {
      console.error('Error fetching comments:', error);
      toast({
        title: 'Error',
        description: 'Failed to load comments',
        variant: 'destructive',
      });
    }
  };

  const handleSubmitComment = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newComment.trim() || !user) return;

    setLoading(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        toast({
          title: 'Authentication required',
          description: 'Please sign in to post a comment',
          variant: 'destructive',
        });
        return;
      }

      const response = await fetch('https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/post-comment', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({
          itemId,
          content: newComment.trim(),
        }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || 'Failed to post comment');
      }

      setComments(prev => [...prev, data.comment]);
      setNewComment('');
      toast({
        title: 'Success',
        description: 'Comment posted successfully',
      });
    } catch (error) {
      console.error('Error posting comment:', error);
      toast({
        title: 'Error',
        description: error instanceof Error ? error.message : 'Failed to post comment',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  };

  const toggleCommentsEnabled = async () => {
    if (!isOwner) return;

    try {
      const { error } = await supabase
        .from('items')
        .update({ comments_enabled: !commentsEnabled })
        .eq('id', itemId);

      if (error) throw error;

      setCommentsEnabled(!commentsEnabled);
      toast({
        title: 'Success',
        description: `Comments ${!commentsEnabled ? 'enabled' : 'disabled'}`,
      });
    } catch (error) {
      console.error('Error toggling comments:', error);
      toast({
        title: 'Error',
        description: 'Failed to update comment settings',
        variant: 'destructive',
      });
    }
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-y-0 right-0 w-96 bg-card border-l shadow-lg z-50 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b">
        <div className="flex items-center gap-2">
          <MessageCircle className="h-5 w-5" />
          <h3 className="font-semibold">Comments</h3>
          <span className="text-sm text-muted-foreground">
            ({comments.length})
          </span>
        </div>
        <div className="flex items-center gap-2">
          {isOwner && (
            <Button
              variant="ghost"
              size="sm"
              onClick={toggleCommentsEnabled}
              className={commentsEnabled ? 'text-primary' : 'text-muted-foreground'}
            >
              {commentsEnabled ? 'Enabled' : 'Disabled'}
            </Button>
          )}
          <Button variant="ghost" size="sm" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Comments List */}
      <ScrollArea className="flex-1 p-4">
        {!commentsEnabled ? (
          <div className="text-center py-8 text-muted-foreground">
            <MessageCircle className="h-12 w-12 mx-auto mb-3 opacity-50" />
            <p>Comments are disabled for this item</p>
          </div>
        ) : comments.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">
            <MessageCircle className="h-12 w-12 mx-auto mb-3 opacity-50" />
            <p>No comments yet</p>
            <p className="text-sm">Be the first to comment!</p>
          </div>
        ) : (
          <div className="space-y-4">
            {comments.map((comment) => (
              <div key={comment.id} className="flex gap-3">
                <Avatar className="h-8 w-8">
                  <AvatarImage src={comment.user_profiles.avatar_url || undefined} />
                  <AvatarFallback>
                    {(comment.user_profiles.display_name || comment.user_profiles.username).charAt(0).toUpperCase()}
                  </AvatarFallback>
                </Avatar>
                <div className="flex-1 space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-sm">
                      {comment.user_profiles.display_name || comment.user_profiles.username}
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {formatDate(comment.created_at)}
                    </span>
                  </div>
                  <p className="text-sm leading-relaxed">{comment.content}</p>
                </div>
              </div>
            ))}
          </div>
        )}
      </ScrollArea>

      {/* Comment Form */}
      {commentsEnabled && (
        <div className="border-t p-4">
          {user ? (
            <form onSubmit={handleSubmitComment} className="space-y-3">
              <Textarea
                value={newComment}
                onChange={(e) => setNewComment(e.target.value)}
                placeholder="Write a comment..."
                className="min-h-[80px] resize-none"
                disabled={loading}
              />
              <div className="flex justify-end">
                <Button 
                  type="submit" 
                  size="sm"
                  disabled={!newComment.trim() || loading}
                >
                  <Send className="h-4 w-4 mr-1" />
                  {loading ? 'Posting...' : 'Post'}
                </Button>
              </div>
            </form>
          ) : (
            <div className="text-center py-4 text-muted-foreground">
              <p className="text-sm">Sign in to leave a comment</p>
            </div>
          )}
        </div>
      )}
    </div>
  );
};