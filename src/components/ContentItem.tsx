
import React, { useState, useEffect, useRef } from 'react';
import { Card } from '@/components/ui/card';
import { TooltipProvider } from '@/components/ui/tooltip';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { Button } from '@/components/ui/button';
import { X } from 'lucide-react';
import ContentItemHeader from '@/components/ContentItemHeader';
import ContentItemContent from '@/components/ContentItemContent';
import ContentItemFooter from '@/components/ContentItemFooter';
import ItemTagsManager from '@/components/ItemTagsManager';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import ChatInterface from '@/components/ChatInterface';
import type { Attachment } from '@/components/CollectionAttachments';
import { supabase } from '@/integrations/supabase/client';
import { isDocumentProcessing } from '@/utils/documentProcessing';
import {
  ASSEMBLY_WINDOW_MS,
  itemAgeMs,
  missingPieces,
  REVEAL_TTL_MS,
  type AssemblyPiece,
} from '@/utils/itemAssembly';
import type { ItemAttributes } from '@/types/itemAttributes';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document' | 'collection';
  title?: string;
  content?: string;
  url?: string;
  file_path?: string;
  file_size?: number;
  description?: string;
  tags?: string[];
  created_at: string;
  mime_type?: string;
  is_public?: boolean;
  supplemental_note?: string;
  summary?: string;
  attributes?: ItemAttributes;
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
  collectionAttachments?: Attachment[];
  /** Enrichment pieces that just landed (piece → epoch ms), from ContentGrid */
  assemblyReveals?: Partial<Record<AssemblyPiece, number>>;
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
  onCommentClick,
  collectionAttachments,
  assemblyReveals
}: ContentItemProps) => {
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [isNoteExpanded, setIsNoteExpanded] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [isNoteDeleted, setIsNoteDeleted] = useState(false);

  // Updates arrive via the realtime items subscription in useItems (no polling)
  const isProcessing = isDocumentProcessing(item);

  // ---- Assembling state: fresh capture, enrichment still landing ----------
  const [nowMs, setNowMs] = useState(() => Date.now());
  const missing = isPublicView ? [] : missingPieces(item);
  const withinWindow = itemAgeMs(item, nowMs) < ASSEMBLY_WINDOW_MS;
  const isAssemblingNow = withinWindow && missing.length > 0;

  // While assembling, tick so the pulse honestly retires when the window
  // closes even if no further updates arrive (e.g. an enrichment step died)
  useEffect(() => {
    if (!isAssemblingNow) return;
    const timer = setInterval(() => setNowMs(Date.now()), 30_000);
    return () => clearInterval(timer);
  }, [isAssemblingNow]);

  // One completion beat when the last expected piece lands
  const wasAssemblingRef = useRef(isAssemblingNow);
  const [showAssembled, setShowAssembled] = useState(false);
  useEffect(() => {
    const was = wasAssemblingRef.current;
    wasAssemblingRef.current = isAssemblingNow;
    if (was && !isAssemblingNow && missing.length === 0) {
      setShowAssembled(true);
      const timer = setTimeout(() => setShowAssembled(false), 2200);
      return () => clearTimeout(timer);
    }
  }, [isAssemblingNow, missing.length]);

  // Cards born moments ago rise into the feed (realtime insert / first paint)
  const [enteredFresh] = useState(() => itemAgeMs(item, Date.now()) < 15_000);

  const revealIsFresh = (piece: AssemblyPiece) => {
    const at = assemblyReveals?.[piece];
    return typeof at === 'number' && Date.now() - at < REVEAL_TTL_MS;
  };
  const headerReveals = {
    title: revealIsFresh('title'),
    preview: revealIsFresh('preview'),
  };
  const contentReveal = revealIsFresh('description') || revealIsFresh('summary');

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

  const handleDeleteNote = async () => {
    try {
      // Optimistically hide the note immediately
      setIsNoteDeleted(true);
      setShowDeleteConfirm(false);
      
      await supabase
        .from('items')
        .update({ supplemental_note: null })
        .eq('id', item.id);
      
      // Refresh the items list to get updated data
      onTagsUpdated();
    } catch (error) {
      console.error('Error deleting note:', error);
      // Revert optimistic update on error
      setIsNoteDeleted(false);
    }
  };

  const renderNoteOverlay = () => {
    // Sticky notes are a shared-item feature; legacy notes on private items stay hidden
    if (!item.supplemental_note || isNoteDeleted || !item.is_public) return null;

    const plainText = getPlainTextFromContent(item.supplemental_note);
    if (!plainText.trim()) return null;

    const lines = plainText.split('\n').filter(line => line.trim() !== '');
    const shouldTruncate = lines.length > 2 || plainText.length > 100;
    const displayText = isNoteExpanded ? plainText : lines.slice(0, 2).join(' ');
    
    // Generate a consistent but random-seeming angle for each item
    const hash = item.id.split('').reduce((a, b) => {
      a = ((a << 5) - a) + b.charCodeAt(0);
      return a & a;
    }, 0);
    const randomAngle = (hash % 8) - 4; // Random angle between -4 and 3 degrees
    
    return (
      <div className="absolute top-2 -left-4 z-40">
        <div 
          className="bg-yellow-50/90 backdrop-blur-sm border border-amber-200/40 rounded-lg p-3 shadow-md hover:shadow-lg transition-all duration-200 max-w-60 cursor-pointer group/note relative"
          style={{ transform: `rotate(${randomAngle}deg) skew(0deg, 2deg)` }}
          onClick={() => shouldTruncate && setIsNoteExpanded(!isNoteExpanded)}
          onMouseEnter={(e) => e.currentTarget.style.transform = 'rotate(0deg) skew(0deg, 0deg)'}
          onMouseLeave={(e) => e.currentTarget.style.transform = `rotate(${randomAngle}deg) skew(0deg, 2deg)`}
        >
          {!isPublicView && (
            <Button
              variant="ghost"
              size="sm"
              className="absolute -top-2 -right-2 h-6 w-6 p-0 opacity-0 group-hover/note:opacity-100 transition-opacity bg-red-50 hover:bg-red-100 border border-red-200"
              onClick={(e) => {
                e.stopPropagation();
                setShowDeleteConfirm(true);
              }}
            >
              <X className="h-3 w-3 text-red-600" />
            </Button>
          )}
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
      {/* No overflow-hidden here — the sticky-note overlay hangs past the card
          edge; the image wrapper clips its own top corners instead */}
      <Card className={`group flex flex-col h-full bg-card border-0 shadow-[0_1px_2px_rgba(0,0,0,0.06),0_8px_24px_rgba(160,120,200,0.12)] hover:shadow-[0_2px_4px_rgba(0,0,0,0.08),0_14px_36px_rgba(160,120,200,0.18)] hover:-translate-y-0.5 transition-all duration-200 relative rounded-2xl ${
        enteredFresh ? 'animate-card-enter' : ''
      } ${isAssemblingNow ? 'animate-assembly-breathe' : ''}`}>
        {/* Note Overlay */}
        {renderNoteOverlay()}

        {/* Assembling thumper: enrichment is landing on this card right now */}
        {(isAssemblingNow || showAssembled) && (
          <div className="absolute top-2 left-2 z-30 animate-chip-pop">
            <span className="inline-flex items-center gap-1.5 rounded-full border border-black/[0.06] bg-white/85 px-2.5 py-1 text-[11px] font-medium text-foreground/70 shadow-sm backdrop-blur-sm">
              {isAssemblingNow ? (
                <>
                  <span className="h-1.5 w-1.5 rounded-full bg-violet-500 animate-assembly-dot" aria-hidden />
                  Filling in the blanks…
                </>
              ) : (
                <>
                  <span className="text-emerald-600" aria-hidden>✓</span>
                  Filled in
                </>
              )}
            </span>
          </div>
        )}

        <ContentItemHeader
          item={item}
          imageErrors={imageErrors}
          onImageError={onImageError}
          onEditItem={onEditItem}
          onVideoExpand={() => setIsVideoLightboxOpen(true)}
          isPublicView={isPublicView}
          reveals={headerReveals}
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
          
          {/* Content section with processing overlay */}
          <div className="flex-1 mb-4 relative">
            {isProcessing && (
              <div className="absolute inset-0 bg-background/60 backdrop-blur-[2px] rounded-lg flex items-center justify-center z-10">
                <div className="flex flex-col items-center gap-2">
                  <div className="animate-pulse flex gap-1">
                    <div className="h-2 w-2 bg-primary rounded-full animate-bounce [animation-delay:-0.3s]"></div>
                    <div className="h-2 w-2 bg-primary rounded-full animate-bounce [animation-delay:-0.15s]"></div>
                    <div className="h-2 w-2 bg-primary rounded-full animate-bounce"></div>
                  </div>
                  <p className="text-sm text-muted-foreground">Extracting content...</p>
                </div>
              </div>
            )}
            <ContentItemContent
              item={item}
              expandedContent={expandedContent}
              onToggleExpansion={onToggleExpansion}
              isPublicView={isPublicView}
              collectionAttachments={collectionAttachments}
              revealDescription={contentReveal}
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
            collectionCount={item.type === 'collection' ? collectionAttachments?.length : undefined}
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

        {/* Delete Note Confirmation */}
        <AlertDialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete Note</AlertDialogTitle>
              <AlertDialogDescription>
                Are you sure you want to delete this sticky note? This action cannot be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction onClick={handleDeleteNote} className="bg-red-600 hover:bg-red-700">
                Delete
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </Card>
    </TooltipProvider>
  );
};

export default ContentItem;
