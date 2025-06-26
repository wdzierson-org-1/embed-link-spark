
import React from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { FileText, Link as LinkIcon, Image, Mic, Video } from 'lucide-react';
import { format } from 'date-fns';
import ContentItemActions from '@/components/ContentItemActions';
import ContentItemContent from '@/components/ContentItemContent';
import ContentItemImage from '@/components/ContentItemImage';
import ItemTagsManager from '@/components/ItemTagsManager';
import LinkPreview from '@/components/LinkPreview';

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
      <Card className="group">
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
            <div className="flex items-center space-x-2 flex-shrink-0">
              <Badge className={getTypeColor(item.type)}>
                {getIcon(item.type)}
                <span className="ml-1 capitalize">{item.type === 'document' ? 'Document' : item.type}</span>
              </Badge>
              <ContentItemActions
                item={item}
                onDeleteItem={onDeleteItem}
                onEditItem={onEditItem}
                onChatWithItem={onChatWithItem}
              />
            </div>
          </div>
        </CardHeader>
        <CardContent>
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
            />
          </div>
          
          <p className="text-xs text-muted-foreground">
            {format(new Date(item.created_at), 'MMM d, yyyy')}
          </p>
        </CardContent>
      </Card>
    </TooltipProvider>
  );
};

export default ContentItem;
