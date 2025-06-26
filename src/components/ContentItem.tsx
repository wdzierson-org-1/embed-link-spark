
import React, { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { FileText, Link as LinkIcon, Image, Mic, Video as VideoIcon, MoreVertical, MessageCircle, Download, ExternalLink, Edit, Trash2, Play } from 'lucide-react';
import { format } from 'date-fns';
import ContentItemContent from '@/components/ContentItemContent';
import ContentItemImage from '@/components/ContentItemImage';
import ItemTagsManager from '@/components/ItemTagsManager';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import { supabase } from '@/integrations/supabase/client';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';
  title?: string;
  content?: string;
  url?: string;
  file_path?: string;
  description?: string;
  tags?: string[];
  created_at: string;
  mime_type?: string;
}

interface ContentItemProps {
  item: ContentItem;
  tags: string[];
  imageErrors: Set<string>;
  expandedContent: Set<string>;
  onImageError: (itemId: string) => void;
  onToggleExpansion: (itemId: string) => void;
  onDeleteItem: (id: string) => void;
  onEditItem: (item: ContentItem) => void;
  onChatWithItem?: (item: ContentItem) => void;
  onTagsUpdated: () => void;
}

const ContentItem = ({
  item,
  tags,
  imageErrors,
  expandedContent,
  onImageError,
  onToggleExpansion,
  onDeleteItem,
  onEditItem,
  onChatWithItem,
  onTagsUpdated
}: ContentItemProps) => {
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);

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

  const getTypeColor = (type: string) => {
    switch (type) {
      case 'text': return 'bg-blue-100 text-blue-800';
      case 'link': return 'bg-green-100 text-green-800';
      case 'image': return 'bg-purple-100 text-purple-800';
      case 'audio': return 'bg-orange-100 text-orange-800';
      case 'video': return 'bg-red-100 text-red-800';
      case 'document': return 'bg-yellow-100 text-yellow-800';
      default: return 'bg-gray-100 text-gray-800';
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

  const fileUrl = getFileUrl(item);

  return (
    <TooltipProvider>
      <Card className="group flex flex-col h-full hover:border-gray-400 transition-colors duration-200 overflow-hidden">
        {/* Image at the top, clipped to card edges */}
        <div className="relative">
          <ContentItemImage
            item={item}
            imageErrors={imageErrors}
            onImageError={onImageError}
          />
          
          {/* Video play button overlay */}
          {item.type === 'video' && fileUrl && (
            <div className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity duration-200 bg-black/20">
              <Button
                variant="ghost"
                size="lg"
                onClick={() => setIsVideoLightboxOpen(true)}
                className="h-16 w-16 rounded-full bg-white/90 hover:bg-white text-black"
              >
                <Play className="h-8 w-8 ml-1" />
              </Button>
            </div>
          )}
        </div>

        <div className="flex flex-col flex-1 p-4">
          {/* Title section */}
          {item.title && (
            <div className="mb-3">
              <Tooltip>
                <TooltipTrigger asChild>
                  <h3 className="text-lg font-semibold leading-tight line-clamp-2 cursor-help">
                    {item.title}
                  </h3>
                </TooltipTrigger>
                <TooltipContent>
                  <p className="max-w-xs break-words">{item.title}</p>
                </TooltipContent>
              </Tooltip>
            </div>
          )}
          
          {/* Audio player - shown on hover */}
          {item.type === 'audio' && fileUrl && (
            <div className="opacity-0 group-hover:opacity-100 transition-opacity duration-200 mb-4">
              <MediaPlayer
                src={fileUrl}
                fileName={item.title || 'Audio file'}
              />
            </div>
          )}
          
          {/* Content section */}
          <div className="flex-1 mb-4">
            <ContentItemContent
              item={item}
              expandedContent={expandedContent}
              onToggleExpansion={onToggleExpansion}
            />
          </div>
          
          {/* Tags - hidden by default, shown on hover */}
          <div className="opacity-0 group-hover:opacity-100 transition-opacity duration-200 mb-4">
            <ItemTagsManager
              itemId={item.id}
              currentTags={tags}
              onTagsUpdated={onTagsUpdated}
              itemContent={{
                title: item.title,
                content: item.content,
                description: item.description
              }}
            />
          </div>
          
          {/* Bottom section with date, type badge, and menu */}
          <div className="flex items-center justify-between mt-auto">
            <div className="flex items-center gap-2">
              <p className="text-xs text-muted-foreground">
                {format(new Date(item.created_at), 'MMM d, yyyy')}
              </p>
              {/* Type badge - hidden by default, shown on hover */}
              <Badge className={`opacity-0 group-hover:opacity-100 transition-opacity duration-200 ${getTypeColor(item.type)}`}>
                {getIcon(item.type)}
                <span className="ml-1 capitalize">{item.type === 'document' ? 'Document' : item.type}</span>
              </Badge>
            </div>
            
            {/* Menu dropdown */}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="sm" className="h-8 w-8 p-0">
                  <MoreVertical className="h-4 w-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                {onChatWithItem && (
                  <DropdownMenuItem onClick={() => onChatWithItem(item)}>
                    <MessageCircle className="h-4 w-4 mr-2" />
                    Chat with item
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
                <DropdownMenuItem onClick={() => onEditItem(item)}>
                  <Edit className="h-4 w-4 mr-2" />
                  Edit
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => onDeleteItem(item.id)} className="text-red-600">
                  <Trash2 className="h-4 w-4 mr-2" />
                  Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>

        {/* Video Lightbox */}
        {item.type === 'video' && fileUrl && (
          <VideoLightbox
            src={fileUrl}
            fileName={item.title || 'Video file'}
            isOpen={isVideoLightboxOpen}
            onClose={() => setIsVideoLightboxOpen(false)}
          />
        )}
      </Card>
    </TooltipProvider>
  );
};

export default ContentItem;
