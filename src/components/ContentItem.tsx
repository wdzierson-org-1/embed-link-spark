
import React from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { FileText, Link as LinkIcon, Image, Mic, Video, MoreVertical, MessageCircle, Download, ExternalLink, Edit, Trash2 } from 'lucide-react';
import { format } from 'date-fns';
import ContentItemContent from '@/components/ContentItemContent';
import ContentItemImage from '@/components/ContentItemImage';
import ItemTagsManager from '@/components/ItemTagsManager';
import LinkPreview from '@/components/LinkPreview';
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
  const getIcon = (type: string) => {
    switch (type) {
      case 'text': return <FileText className="h-4 w-4" />;
      case 'link': return <LinkIcon className="h-4 w-4" />;
      case 'image': return <Image className="h-4 w-4" />;
      case 'audio': return <Mic className="h-4 w-4" />;
      case 'video': return <Video className="h-4 w-4" />;
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

  // Parse OG data from content if it's a link
  let ogData = null;
  if (item.type === 'link' && item.content) {
    try {
      const contentData = JSON.parse(item.content);
      if (contentData.ogData) {
        ogData = contentData.ogData;
      }
    } catch (e) {
      // If content is not JSON, ignore
    }
  }

  return (
    <TooltipProvider>
      <Card className="group flex flex-col h-full">
        <CardHeader className="pb-3">
          <div className="flex items-start justify-between">
            <div className="flex-1 min-w-0 pr-2">
              {item.title && (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <CardTitle className="text-lg truncate cursor-help">
                      {item.title}
                    </CardTitle>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p className="max-w-xs break-words">{item.title}</p>
                  </TooltipContent>
                </Tooltip>
              )}
            </div>
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
        </CardHeader>
        <CardContent className="flex flex-col flex-1">
          <div className="flex-1">
            <ContentItemImage
              item={item}
              imageErrors={imageErrors}
              onImageError={onImageError}
            />
            
            {ogData && item.type === 'link' && (
              <div className="mb-3">
                <LinkPreview ogData={ogData} />
              </div>
            )}
            
            <ContentItemContent
              item={item}
              expandedContent={expandedContent}
              onToggleExpansion={onToggleExpansion}
            />
            
            <div className="mb-2">
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
          </div>
          
          <div className="flex items-center justify-between mt-auto pt-2">
            <Badge className={getTypeColor(item.type)}>
              {getIcon(item.type)}
              <span className="ml-1 capitalize">{item.type === 'document' ? 'Document' : item.type}</span>
            </Badge>
            <p className="text-xs text-muted-foreground">
              {format(new Date(item.created_at), 'MMM d, yyyy')}
            </p>
          </div>
        </CardContent>
      </Card>
    </TooltipProvider>
  );
};

export default ContentItem;
