
import React from 'react';
import { Badge } from '@/components/ui/badge';
import { FileIcon, ImageIcon, VideoIcon, MusicIcon, LinkIcon, FileTextIcon, FolderIcon } from 'lucide-react';
import CollectionAttachments from '@/components/CollectionAttachments';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document' | 'collection';
  content?: string;
  description?: string;
  url?: string;
  file_path?: string;
}

interface ContentItemContentProps {
  item: ContentItem;
  expandedContent: Set<string>;
  onToggleExpansion: (itemId: string) => void;
  isPublicView?: boolean;
}

const ContentItemContent = ({ item, expandedContent, onToggleExpansion, isPublicView }: ContentItemContentProps) => {
  const getTypeIcon = () => {
    switch (item.type) {
      case 'text':
        return <FileTextIcon className="h-4 w-4" />;
      case 'link':
        return <LinkIcon className="h-4 w-4" />;
      case 'image':
        return <ImageIcon className="h-4 w-4" />;
      case 'video':
        return <VideoIcon className="h-4 w-4" />;
      case 'audio':
        return <MusicIcon className="h-4 w-4" />;
      case 'collection':
        return <FolderIcon className="h-4 w-4" />;
      default:
        return <FileIcon className="h-4 w-4" />;
    }
  };

  return (
    <>
      <div className="space-y-2">
        <Badge variant="secondary" className="gap-1.5">
          {getTypeIcon()}
          {item.type}
        </Badge>
        
        {item.description && (
          <div className="mb-2">
            <p className={`text-sm text-muted-foreground ${item.type === 'image' ? 'line-clamp-6' : 'line-clamp-3'}`}>
              {item.description}
            </p>
          </div>
        )}
        
        {item.content && item.type !== 'audio' && item.type !== 'video' && (
          <p className="text-muted-foreground text-sm line-clamp-3">
            {item.content}
          </p>
        )}
        
        {/* Show attachments for collections */}
        {item.type === 'collection' && (
          <CollectionAttachments itemId={item.id} maxDisplay={3} isCompactView={true} />
        )}
      </div>
      
      {item.url && item.type === 'link' && (
        <div className="mb-2 relative">
          <button 
            onClick={() => window.open(item.url, '_blank')}
            className="text-sm text-blue-600 hover:underline cursor-pointer text-left block w-full truncate relative group/url"
            title=""
          >
            {item.url}
            <div className="absolute left-0 top-full mt-1 bg-gray-900 text-white text-xs rounded px-2 py-1 opacity-0 group-hover/url:opacity-100 transition-opacity duration-200 z-10 max-w-xs break-all pointer-events-none">
              {item.url}
            </div>
          </button>
        </div>
      )}
    </>
  );
};

export default ContentItemContent;
