
import React, { useState } from 'react';
import { Card } from '@/components/ui/card';
import { TooltipProvider } from '@/components/ui/tooltip';
import ContentItemHeader from '@/components/ContentItemHeader';
import ContentItemContent from '@/components/ContentItemContent';
import ContentItemFooter from '@/components/ContentItemFooter';
import ItemTagsManager from '@/components/ItemTagsManager';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import ChatInterface from '@/components/ChatInterface';
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
  is_public?: boolean;
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
  isPublicView?: boolean;
  currentUserId?: string;
  onTogglePrivacy?: (item: ContentItem) => void;
  onCommentClick?: (itemId: string) => void;
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
  onTagsUpdated,
  isPublicView = false,
  currentUserId,
  onTogglePrivacy,
  onCommentClick
}: ContentItemProps) => {
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [isNoteExpanded, setIsNoteExpanded] = useState(false);

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

  const getFileUrl = (item: ContentItem) => {
    if (item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  const handleChatWithItem = () => {
    setIsChatOpen(true);
  };

  const renderNoteOverlay = () => {
    if (!item.content) return null;

    const plainText = getPlainTextFromContent(item.content);
    if (!plainText.trim()) return null;

    const lines = plainText.split('\n').filter(line => line.trim() !== '');
    const shouldTruncate = lines.length > 2 || plainText.length > 100;
    const displayText = isNoteExpanded ? plainText : lines.slice(0, 2).join(' ');
    
    return (
      <div className="absolute top-4 right-4 z-10">
        <div 
          className="bg-yellow-100/95 backdrop-blur-sm border border-yellow-200/60 rounded-lg p-3 shadow-lg transform rotate-2 hover:rotate-0 transition-all duration-200 max-w-60 cursor-pointer"
          onClick={() => shouldTruncate && setIsNoteExpanded(!isNoteExpanded)}
        >
          <div className="text-sm text-yellow-800">
            {shouldTruncate && !isNoteExpanded ? (
              <>
                {displayText}
                <span className="text-yellow-600 font-medium ml-1">...</span>
              </>
            ) : (
              displayText
            )}
          </div>
        </div>
      </div>
    );
  };

  const fileUrl = getFileUrl(item);

  return (
    <TooltipProvider>
      <Card className="group flex flex-col h-full bg-gray-50 border border-gray-200 hover:shadow-md transition-all duration-200 overflow-hidden relative">
        {/* Note Overlay */}
        {renderNoteOverlay()}
        
        <ContentItemHeader
          item={item}
          imageErrors={imageErrors}
          onImageError={onImageError}
          onEditItem={onEditItem}
          onVideoExpand={() => setIsVideoLightboxOpen(true)}
          isPublicView={isPublicView}
        />

        <div className="flex flex-col flex-1 p-6 pt-0">
          {/* Audio player - always visible */}
          {item.type === 'audio' && fileUrl && (
            <div className="mb-4">
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
              isPublicView={isPublicView}
            />
          </div>
          
          {/* Tags - hidden by default, shown on hover - only for non-public views */}
          {!isPublicView && (
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
          )}
          
          {/* Bottom section with date, type badge, and menu */}
          <ContentItemFooter
            item={item}
            onDeleteItem={onDeleteItem}
            onEditItem={onEditItem}
            onChatWithItem={handleChatWithItem}
            isPublicView={isPublicView}
            currentUserId={currentUserId}
            onTogglePrivacy={onTogglePrivacy}
            onCommentClick={onCommentClick}
          />
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

        {/* Individual Item Chat Interface */}
        <ChatInterface
          isOpen={isChatOpen}
          onClose={() => setIsChatOpen(false)}
          item={item}
        />
      </Card>
    </TooltipProvider>
  );
};

export default ContentItem;
