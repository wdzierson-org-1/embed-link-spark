
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
      <div className="mb-2">
        <p className="text-sm font-medium mb-1">Note content</p>
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
          <p className="text-sm text-muted-foreground line-clamp-3">
            {item.description}
          </p>
        </div>
      )}
      
      {renderContent()}
      
      {item.url && item.type === 'link' && (
        <button 
          onClick={() => window.open(item.url, '_blank')}
          className="text-sm text-blue-600 mb-2 truncate hover:underline cursor-pointer text-left"
        >
          {item.url}
        </button>
      )}
    </>
  );
};

export default ContentItemContent;
