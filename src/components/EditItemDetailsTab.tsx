
import React, { useState, useEffect, useMemo, useRef } from 'react';
import { TabsContent } from '@/components/ui/tabs';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import {
  Globe,
  Lock,
  Trash2,
  ImageUp,
  Copy,
  Check,
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
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemContentSection from '@/components/EditItemContentSection';
import EditItemLinkSection from '@/components/EditItemLinkSection';
import EditItemDocumentSection from '@/components/EditItemDocumentSection';
import MaximizedEditor from '@/components/MaximizedEditor';
import EditItemSupplementalNoteSection from '@/components/EditItemSupplementalNoteSection';
import ObjectFactsSection from '@/components/edit/ObjectFactsSection';
import EditItemDetailsDrawer from '@/components/edit/EditItemDetailsDrawer';
import EditItemMediaZone from '@/components/edit/EditItemMediaZone';
import EditItemImageStage from '@/components/edit/EditItemImageStage';
import { SectionHead } from '@/components/edit/EditPanelSection';
import { CropMarks, Spinner } from '@/components/machine/Machine';
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
  /** Saves a link's changed address */
  onUrlSave?: (url: string) => Promise<void>;
  /** Saves an edited summary */
  onSummarySave?: (summary: string) => Promise<void>;
}

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
  onUrlSave,
  onSummarySave,
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

  const contentComponent = (
    <div className="mt-0 px-4 pb-8 sm:px-10">
      {/* The source address strip leads (Will, 2026-10-09: "move the address above the title"):
          the whole address opens it; copy, edit, open */}
      {item?.type === 'link' && item?.url && (
        <div className="mb-7">
          <EditItemLinkSection url={item.url} onUrlSave={onUrlSave} />
        </div>
      )}

      {/* ── Header zone: title → description (the kind and source sit in the window bar) ── */}
      <div>
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
          className="-mx-2 mt-2.5 min-h-0 w-[calc(100%+16px)] resize-none overflow-hidden rounded-none border-0 bg-transparent px-2 py-0.5 text-[15px] leading-[1.5] text-muted-foreground shadow-none transition-colors hover:bg-fill focus-visible:bg-white focus-visible:text-ink focus-visible:shadow-[inset_0_0_0_1px_var(--ink),0_0_0_3px_rgb(var(--spot-rgb))] focus-visible:ring-0 focus-visible:ring-offset-0 md:text-[15px] v2:bg-transparent v2:hover:bg-fill v2:focus-visible:bg-white v2:focus-visible:ring-0"
        />
      </div>

      {/* ── Media zone: a recording's player strip, or the video itself ── */}
      {(item?.type === 'audio' || item?.type === 'video') && mediaUrl && (
        <EditItemMediaZone item={item} src={mediaUrl} title={title} />
      )}

      {/* Inline image for image items and links with images: a stage of fixed height, so the
          panel doesn't jump when the picture arrives */}
      {showInlineImage && imageUrl && (
        <EditItemImageStage
          src={imageUrl}
          alt={title || 'Content image'}
          onOpen={handleImageClick}
          controls={
            onImageChange && (
              <div className="absolute right-3 top-3 flex gap-1.5 opacity-0 transition-opacity group-hover/image:opacity-100">
                <button
                  onClick={() => imageFileInputRef.current?.click()}
                  disabled={isImageBusy}
                  title="Replace image"
                  aria-label="Replace image"
                  className="grid h-9 w-9 place-items-center border border-ink bg-white text-ink transition-colors hover:bg-ink hover:text-white"
                >
                  {isImageBusy ? <Spinner className="font-pixel text-pixel-md leading-none" /> : <ImageUp className="h-4 w-4" />}
                </button>
                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <button
                      disabled={isImageBusy}
                      title="Remove image"
                      aria-label="Remove image"
                      className="grid h-9 w-9 place-items-center border border-ink bg-white text-error transition-colors hover:bg-error hover:text-white"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </AlertDialogTrigger>
                  <AlertDialogContent>
                    <AlertDialogHeader>
                      <AlertDialogTitle>Remove this image?</AlertDialogTitle>
                      <AlertDialogDescription>
                        The image will be removed from this item. The item itself stays.
                      </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                      <AlertDialogCancel>Cancel</AlertDialogCancel>
                      <AlertDialogAction onClick={handleRemoveImage} className="bg-error hover:bg-error hover:opacity-90">
                        Remove
                      </AlertDialogAction>
                    </AlertDialogFooter>
                  </AlertDialogContent>
                </AlertDialog>
              </div>
            )
          }
        />
      )}
      {showInlineImage && imageUrl && (
        <input
          ref={imageFileInputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={handleReplaceImageFile}
        />
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
        onSummarySave={onSummarySave}
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

      {/* Publisher object facts are distinct from the user's capture location. */}
      {item?.type === 'link' && <ObjectFactsSection item={item} />}

      {/* ── Details drawer: format facts, filename, source, location ── */}
      {item && <EditItemDetailsDrawer item={item} onSaveAttributes={onAttributesSave} />}

      {/* ── Sharing ── */}
      <div className="mt-[30px]">
        <SectionHead label="Sharing" className="mb-3.5" />
        <div className="flex items-center gap-3 py-0.5">
          <div
            className={`grid h-9 w-9 flex-none place-items-center ${
              localIsPublic ? 'bg-ink text-white' : 'border border-line bg-fill text-ink'
            }`}
          >
            {localIsPublic ? <Globe className="h-4 w-4" /> : <Lock className="h-4 w-4" />}
          </div>
          <div className="min-w-0 flex-1">
            <div className="text-[14px] font-medium text-ink">
              {localIsPublic ? 'On your public feed' : 'Private'}
            </div>
            <div className="text-[13px] text-muted-foreground">
              {localIsPublic
                ? 'Anyone with your feed link can see this item'
                : 'Only you can see this item'}
            </div>
          </div>
          <Switch
            checked={localIsPublic}
            onCheckedChange={handlePublicToggle}
            aria-label="Share on your public feed"
          />
        </div>

        {localIsPublic && feedUrl && (
          <div className="v2-print-in mt-3 flex flex-wrap items-center gap-2.5 pl-12">
            <span className="inline-flex min-w-0 items-stretch border border-ink bg-white">
              <a
                href={feedUrl}
                target="_blank"
                rel="noreferrer"
                className="truncate px-2.5 py-1.5 font-pixel text-pixel text-ink hover:underline"
              >
                {feedUrl.replace('https://', '')}
              </a>
              <button
                onClick={handleCopyFeedUrl}
                title={copiedFeedUrl ? 'Copied' : 'Copy link'}
                aria-label="Copy public feed link"
                className="grid w-8 flex-none place-items-center border-l border-ink text-ink transition-colors hover:bg-ink hover:text-white"
              >
                {copiedFeedUrl ? <Check className="h-[13px] w-[13px]" /> : <Copy className="h-[13px] w-[13px]" />}
              </button>
            </span>
            <span className="text-[13px] text-muted-foreground">
              Turning this off removes it from your feed.
            </span>
          </div>
        )}

        {/* Sticky notes ride along with shared items */}
        {localIsPublic && (
          <div className="mt-4 pl-12">
            <EditItemSupplementalNoteSection
              supplementalNote={supplementalNote}
              onSupplementalNoteChange={onSupplementalNoteChange}
            />
          </div>
        )}
      </div>

      {/* Un-sharing deletes the item's sticky note — confirm before doing it */}
      <AlertDialog open={showUnshareConfirm} onOpenChange={setShowUnshareConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Make this item private?</AlertDialogTitle>
            <AlertDialogDescription>
              Its sticky note will be deleted — sticky notes only live on shared items.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep sharing</AlertDialogCancel>
            <AlertDialogAction onClick={confirmUnshare} className="bg-error hover:bg-error hover:opacity-90">
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
