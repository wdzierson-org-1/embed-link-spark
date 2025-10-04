
import React from 'react';
import CollectionAttachments from '@/components/CollectionAttachments';
import ReadOnlyNovelRenderer from '@/components/ReadOnlyNovelRenderer';

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
  return (
    <>
      <div className="space-y-2">
        {item.description && (
          <div className="mb-2">
            <ReadOnlyNovelRenderer 
              content={item.description}
              maxLines={item.type === 'image' ? 6 : 3}
            />
          </div>
        )}
        
        {item.content && item.type !== 'audio' && item.type !== 'video' && (
          <ReadOnlyNovelRenderer 
            content={item.content}
            maxLines={3}
          />
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
