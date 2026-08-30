
import React, { useState, useEffect, useMemo, useRef } from 'react';
import { TabsContent } from '@/components/ui/tabs';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import {
  Globe,
  Lock,
  Trash2,
  ImageUp,
  Loader2,
  Copy,
  Check,
  Mic,
  AudioLines,
  ScanLine,
  Video,
  Image as ImageIcon,
  FileText,
  Link2,
  PenLine,
  Layers,
  type LucideIcon,
} from 'lucide-react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { uploadFile } from '@/utils/fileUploader';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { useProfile } from '@/hooks/useProfile';
import { domainOfUrl } from '@/utils/linkFlavor';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemContentSection from '@/components/EditItemContentSection';
import EditItemLinkSection from '@/components/EditItemLinkSection';
import EditItemDocumentSection from '@/components/EditItemDocumentSection';
import MaximizedEditor from '@/components/MaximizedEditor';
import EditItemSupplementalNoteSection from '@/components/EditItemSupplementalNoteSection';
import EditItemDetailsDrawer from '@/components/edit/EditItemDetailsDrawer';
import EditItemPlayerStrip from '@/components/edit/EditItemPlayerStrip';
import { SectionHead } from '@/components/edit/EditPanelSection';
import { audioSubtype, isScreenshotItem } from '@/components/cards/CardBits';
import CollectionAttachments from '@/components/CollectionAttachments';
import type { ItemAttributes } from '@/types/itemAttributes';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
  url?: string;
  mime_type?: string;
  file_size?: number;
  created_at?: string;
  supplemental_note?: string;
  is_public?: boolean;
  attributes?: ItemAttributes;
}

interface EditItemDetailsTabProps {
  item: ContentItem | null;
  title: string;
  description: string;
  content: string;
  isContentLoading: boolean;
  editorKey: string;
  saveStatus?: 'idle' | 'saving' | 'saved';
  lastSaved?: Date | null;
  onTitleChange: (title: string) => void;
  onDescriptionChange: (description: string) => void;
  onContentChange: (content: string) => void;
  onTitleSave: (title: string) => Promise<void>;
  onDescriptionSave: (description: string) => Promise<void>;
  onTagsChange: () => void;
  onMediaChange: () => void;
  isInsideTabs?: boolean;
  showInlineImage?: boolean;
  imageUrl?: string;
  isMobile?: boolean;
  supplementalNote?: string;
  onSupplementalNoteChange?: (note: string) => void;
  onPublicToggle?: (isPublic: boolean) => void;
  onImageChange?: (filePath: string | null) => Promise<void>;
  onAttributesSave?: (attributes: ItemAttributes) => Promise<void>;
}

const FILE_BACKED_TYPES = new Set(['audio', 'video', 'image', 'document', 'pdf']);
const NEUTRAL_CHIP = 'bg-[rgba(20,22,30,0.05)] text-[#646b76]';

/** Tinted type chip per the DESIGN.md spectrum table; neutral for the rest */
const getTypeChip = (
  item: ContentItem | null,
): { Icon: LucideIcon; label: string; className: string } => {
  switch (item?.type) {
    case 'audio':
      return audioSubtype(item.attributes) === 'recording'
        ? {
            Icon: AudioLines,
            label: 'recording',
            className: 'bg-[rgba(139,74,158,0.12)] text-[#7d3d84]',
          }
        : { Icon: Mic, label: 'voice note', className: 'bg-[rgba(84,88,178,0.12)] text-[#45408c]' };
    case 'video':
      return { Icon: Video, label: 'video', className: NEUTRAL_CHIP };
    case 'image':
      return isScreenshotItem(item)
        ? {
            Icon: ScanLine,
            label: 'screenshot',
            className: 'bg-[rgba(52,132,201,0.12)] text-[#22689c]',
          }
        : { Icon: ImageIcon, label: 'image', className: NEUTRAL_CHIP };
    case 'document':
    case 'pdf': {
      const isPdf = item.type === 'pdf' || Boolean(item.mime_type?.includes('pdf'));
      return {
        Icon: FileText,
        label: isPdf ? 'pdf' : 'document',
        className: 'bg-[rgba(205,90,105,0.12)] text-[#a33d52]',
      };
    }
    case 'link': {
      const flavor = item.attributes?.link?.flavor;
      return {
        Icon: Link2,
        label: flavor && flavor !== 'generic' ? flavor : 'link',
        className: NEUTRAL_CHIP,
      };
    }
    case 'text':
      return { Icon: PenLine, label: 'note', className: NEUTRAL_CHIP };
    case 'collection':
      return { Icon: Layers, label: 'multi-part', className: NEUTRAL_CHIP };
    default:
      return { Icon: PenLine, label: item?.type || 'item', className: NEUTRAL_CHIP };
  }
};

const EditItemDetailsTab = ({
  item,
  title,
  description,
  content,
  isContentLoading,
  editorKey,
  saveStatus = 'idle',
  lastSaved,
  onTitleChange,
  onDescriptionChange,
  onContentChange,
  onTitleSave,
  onDescriptionSave,
  onTagsChange,
  onMediaChange,
  isInsideTabs = true,
  showInlineImage = false,
  imageUrl = '',
  isMobile = false,
  supplementalNote = '',
  onSupplementalNoteChange = () => {},
  onPublicToggle = () => {},
  onImageChange,
  onAttributesSave,
}: EditItemDetailsTabProps) => {
  const [isEditorMaximized, setIsEditorMaximized] = useState(false);
  const [mobileEditorReady, setMobileEditorReady] = useState(false);
  const [isImageBusy, setIsImageBusy] = useState(false);
  const { user } = useAuth();
  const imageFileInputRef = useRef<HTMLInputElement>(null);
  const descriptionRef = useRef<HTMLTextAreaElement>(null);

  // Description grows with its content
  const resizeDescription = () => {
    const el = descriptionRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${el.scrollHeight + 2}px`;
  };
  useEffect(() => {
    resizeDescription();
  }, [description]);

  const handleReplaceImageFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !user || !onImageChange) return;
    setIsImageBusy(true);
    try {
      const path = await uploadFile(file, user.id);
      await onImageChange(path);
    } catch (error) {
      console.error('Image replace failed:', error);
    } finally {
      setIsImageBusy(false);
    }
  };

  const handleRemoveImage = async () => {
    if (!onImageChange) return;
    setIsImageBusy(true);
    try {
      await onImageChange(null);
    } catch (error) {
      console.error('Image remove failed:', error);
    } finally {
      setIsImageBusy(false);
    }
  };

  // Local state for immediate UI feedback
  const [localIsPublic, setLocalIsPublic] = React.useState(item?.is_public || false);
  const [showUnshareConfirm, setShowUnshareConfirm] = useState(false);
  const [copiedFeedUrl, setCopiedFeedUrl] = useState(false);

  // Username for the public feed URL shown when the item is shared
  const { profile } = useProfile();
  const feedUrl = profile?.username ? `https://gostash.it/feed/${profile.username}` : '';

  // Update local state when item changes
  React.useEffect(() => {
    setLocalIsPublic(item?.is_public || false);
  }, [item?.is_public]);

  // Public toggle handler. Un-sharing an item deletes its sticky note (notes
  // are a public-feed feature), so that path confirms with the user first.
  const handlePublicToggle = (isPublic: boolean) => {
    if (!isPublic && supplementalNote.trim()) {
      setShowUnshareConfirm(true);
      return;
    }
    // Update local state immediately for UI feedback
    setLocalIsPublic(isPublic);
    // Save to backend
    onPublicToggle(isPublic);
  };

  const confirmUnshare = () => {
    setShowUnshareConfirm(false);
    setLocalIsPublic(false);
    // useEditItemSheet clears the note alongside the is_public save
    onPublicToggle(false);
  };

  const handleCopyFeedUrl = async () => {
    if (!feedUrl) return;
    try {
      await navigator.clipboard.writeText(feedUrl);
      setCopiedFeedUrl(true);
      setTimeout(() => setCopiedFeedUrl(false), 1600);
    } catch (error) {
      console.error('Copy failed:', error);
    }
  };

  // Enhanced mobile editor initialization fix
  useEffect(() => {
    if (isMobile && !isContentLoading) {
      console.log('EditItemDetailsTab: Mobile editor initialization sequence starting', {
        itemId: item?.id,
        contentLength: content?.length || 0,
        hasContent: !!content,
        editorKey,
        isContentLoading
      });

      // Small delay to ensure the sheet animation completes and layout is stable
      const initTimer = setTimeout(() => {
        console.log('EditItemDetailsTab: Setting mobile editor as ready after layout stabilization');
        setMobileEditorReady(true);
      }, 100);

      return () => clearTimeout(initTimer);
    } else if (!isMobile) {
      // Desktop doesn't need this delay
      setMobileEditorReady(true);
    }
  }, [isMobile, isContentLoading, item?.id, editorKey]);

  // Reset mobile editor ready state when item changes
  useEffect(() => {
    if (isMobile) {
      setMobileEditorReady(false);
      console.log('EditItemDetailsTab: Reset mobile editor ready state for new item');
    }
  }, [item?.id, isMobile]);

  const handleImageClick = () => {
    if (imageUrl) {
      window.open(imageUrl, '_blank');
    }
  };

  // Enhanced debugging for mobile editor issues
  React.useEffect(() => {
    if (isMobile && content) {
      console.log('EditItemDetailsTab: Mobile content editor state check', {
        itemId: item?.id,
        contentLength: content?.length || 0,
        isContentLoading,
        editorKey,
        isMaximized: isEditorMaximized,
        showInlineImage,
        mobileEditorReady,
        editorShouldRender: !isContentLoading && mobileEditorReady
      });
    }
  }, [isMobile, content, isContentLoading, editorKey, isEditorMaximized, item?.id, showInlineImage, mobileEditorReady]);

  // Playable source for audio/video items (external URLs pass through as-is)
  const mediaUrl = useMemo(() => {
    if (!item?.file_path || !(item.type === 'audio' || item.type === 'video')) return '';
    if (item.file_path.startsWith('http')) return item.file_path;
    return supabase.storage.from('stash-media').getPublicUrl(item.file_path).data.publicUrl;
  }, [item?.file_path, item?.type]);

  if (isEditorMaximized) {
    return (
      <MaximizedEditor
        content={content}
        onContentChange={onContentChange}
        itemId={item?.id}
        editorKey={editorKey}
        saveStatus={saveStatus}
        lastSaved={lastSaved}
        onMinimize={() => setIsEditorMaximized(false)}
      />
    );
  }

  const { Icon: ChipIcon, label: chipLabel, className: chipClassName } = getTypeChip(item);

  const shortDate = (() => {
    if (!item?.created_at) return '';
    const date = new Date(item.created_at);
    if (Number.isNaN(date.getTime())) return '';
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  })();
  const sourceHint =
    item?.type === 'link'
      ? domainOfUrl(item.url)
      : shortDate
        ? `${FILE_BACKED_TYPES.has(item?.type ?? '') ? 'uploaded' : 'saved'} · ${shortDate}`
        : '';

  const contentComponent = (
    <div className="mt-0 px-6 pb-7 sm:px-10">
      {/* ── Header zone: type eyebrow → title → description ── */}
      <div>
        <div className="mb-3 flex items-center gap-2.5">
          <span
            className={`inline-flex items-center gap-1.5 rounded-full px-[11px] py-1 text-[11px] font-semibold uppercase tracking-[0.09em] ${chipClassName}`}
          >
            <ChipIcon className="h-3 w-3" />
            {chipLabel}
          </span>
          {sourceHint && <span className="text-xs text-[#959ba6]">{sourceHint}</span>}
        </div>

        <EditItemTitleSection
          title={title}
          onTitleChange={onTitleChange}
          onSave={onTitleSave}
        />

        <Textarea
          id="edit-item-description"
          aria-label="Description"
          ref={descriptionRef}
          value={description}
          onChange={(e) => { onDescriptionChange(e.target.value); resizeDescription(); }}
          onBlur={() => void onDescriptionSave(description)}
          placeholder="Add a description..."
          className="-mx-2 mt-2 min-h-0 w-[calc(100%+16px)] max-w-[64ch] resize-none overflow-hidden rounded-lg border-0 bg-transparent px-2 py-0.5 text-[14.5px] leading-relaxed text-[#646b76] shadow-none transition-colors hover:bg-[rgba(109,91,208,0.05)] focus-visible:bg-[rgba(109,91,208,0.06)] focus-visible:ring-2 focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0 md:text-[14.5px]"
        />
      </div>

      {/* ── Media zone ── */}
      {(item?.type === 'audio' || item?.type === 'video') && mediaUrl && (
        <EditItemPlayerStrip
          src={mediaUrl}
          itemId={item.id}
          variant={
            item.type === 'audio' && audioSubtype(item.attributes) === 'voice_note'
              ? 'voice'
              : 'warm'
          }
          durationHint={item.attributes?.media?.duration_s}
          downloadUrl={mediaUrl}
        />
      )}

      {/* Inline image for image items and links with images */}
      {showInlineImage && imageUrl && (
        <div className="mt-6 flex justify-center">
          <div className="group/image relative inline-block">
            <img
              src={imageUrl}
              alt={title || 'Content image'}
              className="h-auto max-h-96 max-w-full cursor-pointer rounded-[14px] shadow-[0_1px_2px_rgba(20,22,30,0.05),0_8px_24px_rgba(30,33,44,0.08)] transition-opacity hover:opacity-95"
              onClick={handleImageClick}
              style={{ objectFit: 'contain' }}
            />
            {onImageChange && (
              <div className="absolute right-3 top-3 flex gap-1.5 opacity-0 transition-opacity group-hover/image:opacity-100">
                <button
                  onClick={() => imageFileInputRef.current?.click()}
                  disabled={isImageBusy}
                  title="Replace image"
                  className="grid h-9 w-9 place-items-center rounded-xl bg-white/95 text-gray-700 shadow-[0_2px_8px_rgba(0,0,0,0.18)] backdrop-blur transition-all hover:bg-white hover:shadow-lg"
                >
                  {isImageBusy ? <Loader2 className="h-4 w-4 animate-spin motion-reduce:animate-none" /> : <ImageUp className="h-4 w-4" />}
                </button>
                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <button
                      disabled={isImageBusy}
                      title="Remove image"
                      className="grid h-9 w-9 place-items-center rounded-xl bg-white/95 text-[#c93a3a] shadow-[0_2px_8px_rgba(0,0,0,0.18)] backdrop-blur transition-all hover:bg-white hover:shadow-lg"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </AlertDialogTrigger>
                  <AlertDialogContent className="rounded-2xl">
                    <AlertDialogHeader>
                      <AlertDialogTitle>Remove this image?</AlertDialogTitle>
                      <AlertDialogDescription>
                        The image will be removed from this item. The item itself stays.
                      </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                      <AlertDialogCancel>Cancel</AlertDialogCancel>
                      <AlertDialogAction onClick={handleRemoveImage} className="bg-red-600 hover:bg-red-700">
                        Remove
                      </AlertDialogAction>
                    </AlertDialogFooter>
                  </AlertDialogContent>
                </AlertDialog>
              </div>
            )}
            <input
              ref={imageFileInputRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={handleReplaceImageFile}
            />
          </div>
        </div>
      )}

      {/* Link row — hairline row with favicon, only for link items */}
      {item?.type === 'link' && item?.url && (
        <div className="mt-2.5">
          <EditItemLinkSection url={item.url} />
        </div>
      )}

      {/* Document preview — only for document items */}
      {(item?.type === 'document' || item?.type === 'pdf') && item?.file_path && (
        <div className="mt-6">
          <EditItemDocumentSection
            filePath={item.file_path}
            fileName={item.title}
            mimeType={item.mime_type}
          />
        </div>
      )}

      {/* ── Content tabs (Notes/Transcript/Summary/Original per type) ── */}
      <EditItemContentSection
        item={item}
        content={content}
        isContentLoading={isContentLoading}
        editorKey={editorKey}
        onContentChange={onContentChange}
        onMaximize={() => setIsEditorMaximized(true)}
        isMobile={isMobile}
        mobileEditorReady={mobileEditorReady}
      />

      {/* Attachments — only for multi-part (collection) items */}
      {item?.type === 'collection' && (
        <div className="mt-[30px]">
          <SectionHead label="Attachments" />
          <div className="mt-3.5">
            <CollectionAttachments
              itemId={item.id}
              showAll={true}
              isCompactView={false}
            />
          </div>
        </div>
      )}

      {/* ── Details drawer: format facts, filename, source, location ── */}
      {item && <EditItemDetailsDrawer item={item} onSaveAttributes={onAttributesSave} />}

      {/* ── Sharing ── */}
      <div className="mt-[30px]">
        <SectionHead label="Sharing" className="mb-3.5" />
        <div className="flex items-center gap-3 py-0.5">
          <div
            className={`grid h-[34px] w-[34px] flex-none place-items-center rounded-[10px] ${
              localIsPublic
                ? 'bg-[rgba(109,91,208,0.12)] text-[#6d5bd0]'
                : 'bg-[rgba(20,22,30,0.05)] text-[#646b76]'
            }`}
          >
            {localIsPublic ? <Globe className="h-4 w-4" /> : <Lock className="h-4 w-4" />}
          </div>
          <div className="min-w-0 flex-1">
            <div className="text-[13.5px] font-semibold text-[#22262f]">
              {localIsPublic ? 'On your public feed' : 'Private'}
            </div>
            <div className="text-xs text-[#959ba6]">
              {localIsPublic
                ? 'Anyone with your feed link can see this item'
                : 'Only you can see this item'}
            </div>
          </div>
          <Switch
            checked={localIsPublic}
            onCheckedChange={handlePublicToggle}
            className="data-[state=checked]:bg-[#6d5bd0] data-[state=unchecked]:bg-[rgba(20,22,30,0.15)] focus-visible:ring-[#b6a8ef]"
          />
        </div>

        {localIsPublic && feedUrl && (
          <div className="mt-3 flex flex-wrap items-center gap-2.5 pl-[46px] duration-200 animate-in fade-in-0 slide-in-from-top-1 motion-reduce:animate-none">
            <span className="inline-flex min-w-0 items-center gap-2 rounded-full border border-black/[0.07] bg-white/85 px-3.5 py-[5px] font-mono text-xs text-[#646b76]">
              <a
                href={feedUrl}
                target="_blank"
                rel="noreferrer"
                className="truncate hover:text-[#6d5bd0]"
              >
                {feedUrl.replace('https://', '')}
              </a>
              <button
                onClick={handleCopyFeedUrl}
                title={copiedFeedUrl ? 'Copied' : 'Copy link'}
                aria-label="Copy public feed link"
                className="grid flex-none place-items-center text-[#6d5bd0] transition-opacity hover:opacity-75"
              >
                {copiedFeedUrl ? <Check className="h-[13px] w-[13px]" /> : <Copy className="h-[13px] w-[13px]" />}
              </button>
            </span>
            <span className="text-[11.5px] text-[#959ba6]">
              Turning this off removes it from your feed.
            </span>
          </div>
        )}

        {/* Sticky notes ride along with shared items */}
        {localIsPublic && (
          <div className="mt-4 pl-[46px]">
            <EditItemSupplementalNoteSection
              supplementalNote={supplementalNote}
              onSupplementalNoteChange={onSupplementalNoteChange}
            />
          </div>
        )}
      </div>

      {/* Un-sharing deletes the item's sticky note — confirm before doing it */}
      <AlertDialog open={showUnshareConfirm} onOpenChange={setShowUnshareConfirm}>
        <AlertDialogContent className="rounded-2xl">
          <AlertDialogHeader>
            <AlertDialogTitle>Make this item private?</AlertDialogTitle>
            <AlertDialogDescription>
              Its sticky note will be deleted — sticky notes only live on shared items.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep sharing</AlertDialogCancel>
            <AlertDialogAction onClick={confirmUnshare} className="bg-red-600 hover:bg-red-700">
              Make private
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );

  // Conditionally wrap with TabsContent only if inside Tabs
  return isInsideTabs ? (
    <TabsContent value="details" className="mt-0">
      {contentComponent}
    </TabsContent>
  ) : (
    contentComponent
  );
};

export default EditItemDetailsTab;
