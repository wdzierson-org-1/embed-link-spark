
import React, { useState, useEffect, useRef } from 'react';
import type { JSONContent } from 'novel';
import { Card } from '@/components/ui/card';
import { TooltipProvider } from '@/components/ui/tooltip';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { X } from 'lucide-react';
import ContentItemHeader from '@/components/ContentItemHeader';
import ContentItemContent from '@/components/ContentItemContent';
import ContentItemFooter from '@/components/ContentItemFooter';
import ChatInterface from '@/components/ChatInterface';
import { StatusLine } from '@/components/machine/Machine';
import type { Attachment } from '@/components/CollectionAttachments';
import { supabase } from '@/integrations/supabase/client';
import { isDocumentProcessing } from '@/utils/documentProcessing';
import {
  enrichmentState,
  isReadingDocument,
  missingPieces,
  itemAgeMs,
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
  remind_at?: string | null;
  reminder_cleared_at?: string | null;
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
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [isNoteExpanded, setIsNoteExpanded] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [isNoteDeleted, setIsNoteDeleted] = useState(false);

  // Updates arrive via the realtime items subscription in useItems (no polling)
  const isProcessing = isDocumentProcessing(item);

  // ---- Assembling state: fresh capture, enrichment still landing ----------
  const [nowMs, setNowMs] = useState(() => Date.now());
  const assemblyState = isPublicView ? 'complete' : enrichmentState(item, nowMs);
  const isAssemblingNow = assemblyState === 'pending';
  const isFullyEnriched = assemblyState === 'complete' && (item.attributes?.enrichment?.status === 'complete' || missingPieces(item).length === 0);

  // A PDF still extracting counts as being read only within its window (a failed extraction
  // writes nothing, so it would otherwise claim work forever)
  const isReadingPdf = !isPublicView && isReadingDocument(item, nowMs);
  const pdfGaveUp = !isPublicView && isProcessing && !isReadingPdf;

  // While assembling, tick so the reading state honestly retires when its window
  // closes even if no further updates arrive (e.g. an enrichment step died)
  useEffect(() => {
    if (!isAssemblingNow && !isReadingPdf) return;
    const timer = setInterval(() => setNowMs(Date.now()), 30_000);
    return () => clearInterval(timer);
  }, [isAssemblingNow, isReadingPdf]);

  // One completion beat when the last expected piece lands
  const wasAssemblingRef = useRef(isAssemblingNow);
  const [showAssembled, setShowAssembled] = useState(false);
  useEffect(() => {
    const was = wasAssemblingRef.current;
    wasAssemblingRef.current = isAssemblingNow;
    if (was && !isAssemblingNow && isFullyEnriched) {
      setShowAssembled(true);
      const timer = setTimeout(() => setShowAssembled(false), 2200);
      return () => clearTimeout(timer);
    }
  }, [isAssemblingNow, isFullyEnriched]);

  // Cards born moments ago print into the feed (realtime insert / first paint)
  const [enteredFresh] = useState(() => itemAgeMs(item, Date.now()) < 15_000);

  // The machine line under the title (DESIGN-v2 "while reading"): the `| / - \` cursor from the
  // share sheet, saying honestly what Stash is still waiting on for this kind of save
  const busyLabel = isReadingPdf
    ? 'reading the pdf'
    : item.type === 'audio' || item.type === 'video'
      ? 'transcribing'
      : item.type === 'image'
        ? 'reading the picture'
        : 'gathering more info';
  // Visitors to a public feed never see the machine at work, only the save
  const isReading = !isPublicView && (isAssemblingNow || isReadingPdf);
  const statusLine = isReading ? (
    <StatusLine tone="busy">{busyLabel}…</StatusLine>
  ) : showAssembled ? (
    <StatusLine tone="done">filled in</StatusLine>
  ) : assemblyState === 'partial' || pdfGaveUp ? (
    <StatusLine tone="idle">some info unavailable</StatusLine>
  ) : null;
  const awaitingDescription =
    isReading && (isReadingPdf || missingPieces(item).includes('description'));

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

  const extractTextFromTiptapJson = (jsonContent: JSONContent): string => {
    if (!jsonContent || !jsonContent.content) return '';
    
    const extractFromNode = (node: JSONContent): string => {
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
          className="group/note relative max-w-60 cursor-pointer border border-ink bg-white p-3 shadow-print-sm transition-transform duration-200"
          style={{ transform: `rotate(${randomAngle}deg) skew(0deg, 2deg)` }}
          onClick={() => shouldTruncate && setIsNoteExpanded(!isNoteExpanded)}
          onMouseEnter={(e) => e.currentTarget.style.transform = 'rotate(0deg) skew(0deg, 0deg)'}
          onMouseLeave={(e) => e.currentTarget.style.transform = `rotate(${randomAngle}deg) skew(0deg, 2deg)`}
        >
          {!isPublicView && (
            <button
              type="button"
              aria-label="Delete sticky note"
              className="absolute -right-2 -top-2 grid h-6 w-6 place-items-center bg-ink text-white opacity-0 transition-opacity hover:bg-error group-hover/note:opacity-100 focus-visible:opacity-100"
              onClick={(e) => {
                e.stopPropagation();
                setShowDeleteConfirm(true);
              }}
            >
              <X className="h-3 w-3" />
            </button>
          )}
          <div className="text-[13px] italic leading-snug text-ink/85">
            {shouldTruncate && !isNoteExpanded ? (
              <>
                {displayText}
                <span className="ml-1 not-italic text-muted-foreground">…</span>
              </>
            ) : (
              displayText
            )}
          </div>
        </div>
      </div>
    );
  };

  return (
    <TooltipProvider>
      {/* No overflow-hidden here — the sticky-note overlay hangs past the card
          edge; the image wrapper clips its own top corners instead */}
      <Card
        aria-busy={isReading}
        className={`group relative flex h-full flex-col rounded-object border border-line bg-white shadow-object transition-[transform,box-shadow,border-color] duration-150 ease-v2 hover:-translate-x-0.5 hover:-translate-y-0.5 hover:border-ink hover:shadow-print motion-reduce:transition-none motion-reduce:hover:translate-x-0 motion-reduce:hover:translate-y-0 ${
          enteredFresh ? 'v2-arrive' : ''
        }`}
      >
        {/* Note Overlay */}
        {renderNoteOverlay()}

        <div className="flex flex-1 flex-col">
        <ContentItemHeader
          item={item}
          imageErrors={imageErrors}
          onImageError={onImageError}
          onEditItem={onEditItem}
          isPublicView={isPublicView}
          reveals={headerReveals}
          reading={isReading}
          status={statusLine}
        />

        <div className="flex flex-1 flex-col px-5 pb-3.5 pt-2.5">
          <div className="mb-3.5 flex-1">
            <ContentItemContent
              item={item}
              expandedContent={expandedContent}
              onToggleExpansion={onToggleExpansion}
              isPublicView={isPublicView}
              collectionAttachments={collectionAttachments}
              revealDescription={contentReveal}
              awaitingDescription={awaitingDescription}
              onNoteSaved={onTagsUpdated}
            />
          </div>

          {/* Bottom section with date, location pin, and overflow menu */}
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

        </div>

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
              <AlertDialogTitle>Delete this sticky note?</AlertDialogTitle>
              <AlertDialogDescription>
                It comes off the shared item for good. This can't be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction onClick={handleDeleteNote} className="bg-error hover:bg-error hover:opacity-90">
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
