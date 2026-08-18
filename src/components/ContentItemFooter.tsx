
import React from 'react';
import { Badge } from '@/components/ui/badge';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { FileText, Link as LinkIcon, Image, Mic, Video as VideoIcon, MoreVertical, MessageCircle, Download, ExternalLink, Edit, Trash2, Eye, EyeOff, MapPin, Layers } from 'lucide-react';
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
  /** Attachment count for multi-part items — shown instead of "collection" */
  collectionCount?: number;
}

const ContentItemFooter = ({
  item,
  onDeleteItem,
  onEditItem,
  onChatWithItem,
  isPublicView = false,
  currentUserId,
  onTogglePrivacy,
  onCommentClick,
  collectionCount
}: ContentItemFooterProps) => {
  const isProcessing = isDocumentProcessing(item);
  const getIcon = (type: string) => {
    switch (type) {
      case 'text': return <FileText className="h-4 w-4" />;
      case 'link': return <LinkIcon className="h-4 w-4" />;
      case 'image': return <Image className="h-4 w-4" />;
      case 'audio': return <Mic className="h-4 w-4" />;
      case 'video': return <VideoIcon className="h-4 w-4" />;
      case 'document': return <FileText className="h-4 w-4" />;
      case 'collection': return <Layers className="h-4 w-4" />;
      default: return <FileText className="h-4 w-4" />;
    }
  };

  const typeBadgeLabel =
    item.type === 'collection'
      ? collectionCount != null
        ? `${collectionCount} item${collectionCount === 1 ? '' : 's'}`
        : 'items'
      : item.type;

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
        {/* Asset Type Badge - Hidden until hover */}
        <Badge variant="secondary" className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
          {getIcon(item.type)}
          {typeBadgeLabel}
        </Badge>
        
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
