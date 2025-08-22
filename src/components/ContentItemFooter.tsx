
import React from 'react';
import { Badge } from '@/components/ui/badge';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { FileText, Link as LinkIcon, Image, Mic, Video as VideoIcon, MoreVertical, MessageCircle, Download, ExternalLink, Edit, Trash2, Eye, EyeOff } from 'lucide-react';
import { format } from 'date-fns';
import { supabase } from '@/integrations/supabase/client';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';
  title?: string;
  url?: string;
  file_path?: string;
  created_at: string;
  is_public?: boolean;
  user_id?: string;
  comment_count?: number;
}

interface ContentItemFooterProps {
  item: ContentItem;
  onDeleteItem: (id: string) => void;
  onEditItem: (item: ContentItem) => void;
  onChatWithItem?: (item: ContentItem) => void;
  isPublicView?: boolean;
  currentUserId?: string;
  onTogglePrivacy?: (item: ContentItem) => void;
  onCommentClick?: (itemId: string) => void;
}

const ContentItemFooter = ({ 
  item, 
  onDeleteItem, 
  onEditItem, 
  onChatWithItem,
  isPublicView = false,
  currentUserId,
  onTogglePrivacy,
  onCommentClick
}: ContentItemFooterProps) => {
  const getIcon = (type: string) => {
    switch (type) {
      case 'text': return <FileText className="h-4 w-4" />;
      case 'link': return <LinkIcon className="h-4 w-4" />;
      case 'image': return <Image className="h-4 w-4" />;
      case 'audio': return <Mic className="h-4 w-4" />;
      case 'video': return <VideoIcon className="h-4 w-4" />;
      case 'document': return <FileText className="h-4 w-4" />;
      default: return <FileText className="h-4 w-4" />;
    }
  };

  const getFileUrl = (item: ContentItem) => {
    if (item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  const handleDownloadFile = (item: ContentItem) => {
    const fileUrl = getFileUrl(item);
    if (fileUrl) {
      window.open(fileUrl, '_blank');
    }
  };

  const handleChatWithItem = () => {
    if (onChatWithItem) {
      onChatWithItem(item);
    }
  };

  const fileUrl = getFileUrl(item);
  const isOwner = currentUserId && item.user_id === currentUserId;
  const showOwnerControls = isPublicView && isOwner;

  return (
    <div className="flex items-center justify-between mt-auto">
      <div className="flex items-center gap-2">
        <p className="text-xs text-muted-foreground">
          {format(new Date(item.created_at), 'MMM d, yyyy')}
        </p>
      </div>
      
      <div className="flex items-center gap-2">
        {/* Comment count button for public view */}
        {isPublicView && onCommentClick && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => onCommentClick(item.id)}
            className="h-8 px-2 text-muted-foreground hover:text-foreground"
          >
            <MessageCircle className="h-4 w-4 mr-1" />
            <span className="text-sm">{item.comment_count || 0}</span>
          </Button>
        )}
        
        {/* Type badge - hidden by default, shown on hover with purple background */}
        <div className="opacity-0 group-hover:opacity-100 transition-opacity duration-200">
          <Badge variant="purple">
            {getIcon(item.type)}
            <span className="ml-1 capitalize">{item.type === 'document' ? 'Document' : item.type}</span>
          </Badge>
        </div>
        
        {/* Menu dropdown */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="sm" className="h-8 w-8 p-0 hover:bg-gray-200">
              <MoreVertical className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {!isPublicView && (
              <DropdownMenuItem onClick={handleChatWithItem}>
                <MessageCircle className="h-4 w-4 mr-2" />
                Chat with item
              </DropdownMenuItem>
            )}
            {isPublicView && onCommentClick && (
              <DropdownMenuItem onClick={() => onCommentClick(item.id)}>
                <MessageCircle className="h-4 w-4 mr-2" />
                Comments
              </DropdownMenuItem>
            )}
            {fileUrl && (
              <DropdownMenuItem onClick={() => handleDownloadFile(item)}>
                <Download className="h-4 w-4 mr-2" />
                Download
              </DropdownMenuItem>
            )}
            {item.url && (
              <DropdownMenuItem onClick={() => window.open(item.url, '_blank')}>
                <ExternalLink className="h-4 w-4 mr-2" />
                Open link
              </DropdownMenuItem>
            )}
            {showOwnerControls && (
              <>
                <DropdownMenuItem onClick={() => onEditItem(item)}>
                  <Edit className="h-4 w-4 mr-2" />
                  Edit
                </DropdownMenuItem>
                {onTogglePrivacy && (
                  <DropdownMenuItem onClick={() => onTogglePrivacy(item)}>
                    {item.is_public ? (
                      <>
                        <EyeOff className="h-4 w-4 mr-2" />
                        Set to Private
                      </>
                    ) : (
                      <>
                        <Eye className="h-4 w-4 mr-2" />
                        Set to Public
                      </>
                    )}
                  </DropdownMenuItem>
                )}
              </>
            )}
            {!isPublicView && (
              <>
                <DropdownMenuItem onClick={() => onEditItem(item)}>
                  <Edit className="h-4 w-4 mr-2" />
                  Edit
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => onDeleteItem(item.id)} className="text-red-600">
                  <Trash2 className="h-4 w-4 mr-2" />
                  Delete
                </DropdownMenuItem>
              </>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  );
};

export default ContentItemFooter;
