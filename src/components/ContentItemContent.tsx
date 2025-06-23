
import React from 'react';
import { supabase } from '@/integrations/supabase/client';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';
  content?: string;
  description?: string;
  url?: string;
  file_path?: string;
}

interface ContentItemContentProps {
  item: ContentItem;
  expandedContent: Set<string>;
  onToggleExpansion: (itemId: string) => void;
}

const ContentItemContent = ({ item, expandedContent, onToggleExpansion }: ContentItemContentProps) => {
  const renderContent = () => {
    if (!item.content) return null;

    const isExpanded = expandedContent.has(item.id);
    const lines = item.content.split('\n');
    const shouldShowMore = lines.length > 3;
    const displayLines = isExpanded ? lines.slice(0, 15) : lines.slice(0, 3);
    
    return (
      <div className="mb-2">
        <p className="text-sm font-medium mb-1">Content:</p>
        <div className="text-sm text-muted-foreground">
          {displayLines.map((line, index) => (
            <div key={index} className="line-clamp-1">{line}</div>
          ))}
          {shouldShowMore && (
            <button
              onClick={() => onToggleExpansion(item.id)}
              className="text-blue-600 hover:text-blue-800 text-sm mt-1 font-medium"
            >
              {isExpanded ? 'show less...' : 'more...'}
            </button>
          )}
        </div>
      </div>
    );
  };

  return (
    <>
      {item.description && (
        <div className="mb-2">
          <p className="text-sm font-medium text-blue-600 mb-1">AI Description:</p>
          <p className="text-sm text-muted-foreground line-clamp-3">
            {item.description}
          </p>
        </div>
      )}
      
      {renderContent()}
      
      {item.url && item.type === 'link' && (
        <p className="text-sm text-blue-600 mb-2 truncate">
          {item.url}
        </p>
      )}
    </>
  );
};

export default ContentItemContent;
