
import React from 'react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { MoreHorizontal, MessageCircle, Download, ExternalLink, Edit, Trash2, Eye, EyeOff, MapPin } from 'lucide-react';
import { format } from 'date-fns';
import { supabase } from '@/integrations/supabase/client';
import { AnimatedCommentCount } from '@/components/AnimatedCommentCount';
import { isDocumentProcessing } from '@/utils/documentProcessing';
import type { ItemAttributes } from '@/types/itemAttributes';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document' | 'collection';
  title?: string;
  content?: string;
  url?: string;
  file_path?: string;
  mime_type?: string;
  created_at: string;
  is_public?: boolean;
  user_id?: string;
  comment_count?: number;
  summary?: string;
  attributes?: ItemAttributes;
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
  const isProcessing = isDocumentProcessing(item);

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

  const fileUrl = getFileUrl(item);
  const isOwner = currentUserId && item.user_id === currentUserId;
  const showOwnerControls = isPublicView && isOwner;

  return (
    <div className="flex items-center justify-between mt-auto">
      <div className="flex items-center gap-2 min-w-0">
        <p className="text-xs text-muted-foreground whitespace-nowrap">
          {format(new Date(item.created_at), 'MMM d, yyyy')}
        </p>
        {item.attributes?.location?.label && (
          <p
            className="flex items-center gap-0.5 text-xs text-muted-foreground min-w-0"
            title={`posted from ${item.attributes.location.label}`}
          >
            <MapPin className="h-3 w-3 flex-none" />
            <span className="truncate max-w-[140px]">{item.attributes.location.label}</span>
          </p>
        )}
      </div>
      
      <div className="flex items-center gap-2">
        {/* Comment count with animation */}
        {isPublicView && onCommentClick && (
          <AnimatedCommentCount 
            count={item.comment_count || 0}
            onCommentClick={() => onCommentClick(item.id)}
          />
        )}
        
        {/* Menu dropdown */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              size="sm"
              className="h-6 w-6 rounded-full p-0 text-muted-foreground hover:bg-black/5 hover:text-foreground"
            >
              <MoreHorizontal className="h-[15px] w-[15px]" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
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
                <DropdownMenuItem 
                  onClick={() => onEditItem(item)}
                  disabled={isProcessing}
                  className={isProcessing ? 'opacity-50 cursor-not-allowed' : ''}
                >
                  <Edit className="h-4 w-4 mr-2" />
                  {isProcessing ? 'Processing...' : 'Edit'}
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
                <DropdownMenuItem 
                  onClick={() => onEditItem(item)}
                  disabled={isProcessing}
                  className={isProcessing ? 'opacity-50 cursor-not-allowed' : ''}
                >
                  <Edit className="h-4 w-4 mr-2" />
                  {isProcessing ? 'Processing...' : 'Edit'}
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
