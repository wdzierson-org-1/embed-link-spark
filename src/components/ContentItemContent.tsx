
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
  isPublicView?: boolean;
}

const ContentItemContent = ({ item, expandedContent, onToggleExpansion, isPublicView }: ContentItemContentProps) => {
  const getPlainTextFromContent = (content: string) => {
    if (!content) return '';
    
    // Try to parse as JSON first (Tiptap format)
    try {
      const parsed = JSON.parse(content);
      if (parsed && parsed.type === 'doc' && Array.isArray(parsed.content)) {
        return extractTextFromTiptapJson(parsed);
      }
    } catch (e) {
      // Not JSON, treat as plain text or markdown
    }
    
    // Remove markdown formatting for preview
    return content
      .replace(/#{1,6}\s+/g, '') // Remove heading markers
      .replace(/\*\*(.*?)\*\*/g, '$1') // Remove bold markers
      .replace(/__(.*?)__/g, '$1') // Remove bold markers
      .replace(/\*(.*?)\*/g, '$1') // Remove italic markers
      .replace(/_(.*?)_/g, '$1') // Remove italic markers
      .replace(/`(.*?)`/g, '$1') // Remove code markers
      .replace(/^\s*[-*+]\s+/gm, '') // Remove bullet points
      .replace(/^\s*\d+\.\s+/gm, '') // Remove numbered list markers
      .replace(/^\s*[-*]\s+\[([ x])\]\s+/gm, '') // Remove task list markers
      .replace(/\n{2,}/g, '\n') // Replace multiple newlines with single
      .trim();
  };

  const extractTextFromTiptapJson = (jsonContent: any): string => {
    if (!jsonContent || !jsonContent.content) return '';
    
    const extractFromNode = (node: any): string => {
      if (node.type === 'text') {
        return node.text || '';
      }
      
      if (node.content && Array.isArray(node.content)) {
        return node.content.map(extractFromNode).join('');
      }
      
      return '';
    };
    
    return jsonContent.content.map(extractFromNode).join(' ').trim();
  };

  const renderContent = () => {
    if (!item.content) return null;

    const isExpanded = expandedContent.has(item.id);
    const plainText = getPlainTextFromContent(item.content);
    const lines = plainText.split('\n').filter(line => line.trim() !== '');
    const shouldShowMore = lines.length > 3;
    const displayLines = isExpanded ? lines.slice(0, 15) : lines.slice(0, 3);
    
    if (plainText.trim() === '') return null;
    
    return (
      <div className="mb-3">
        <div className="relative">
          <div className="bg-white/90 backdrop-blur-sm border border-gray-200/60 rounded-lg p-3 shadow-sm transform -rotate-1 hover:rotate-0 transition-transform duration-200 relative">
            <div className="text-xs text-gray-500 mb-1 font-medium">Note</div>
            <div className="text-sm text-gray-700">
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
        </div>
      </div>
    );
  };

  return (
    <>
      {item.description && (
        <div className="mb-2">
          <p className="text-sm text-muted-foreground line-clamp-3">
            {item.description}
          </p>
        </div>
      )}
      
      {renderContent()}
      
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
