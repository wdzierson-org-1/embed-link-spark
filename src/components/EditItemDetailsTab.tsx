
import React, { useState, useEffect, useRef } from 'react';
import { TabsContent } from '@/components/ui/tabs';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import { Globe, Lock, AlignLeft, Trash2, ImageUp, Loader2, Copy, Check } from 'lucide-react';
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
import { useAuth } from '@/hooks/useAuth';
import { useProfile } from '@/hooks/useProfile';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemImageSection from '@/components/EditItemImageSection';
import EditItemContentSection from '@/components/EditItemContentSection';
import EditItemLinkSection from '@/components/EditItemLinkSection';
import EditItemDocumentSection from '@/components/EditItemDocumentSection';
import MaximizedEditor from '@/components/MaximizedEditor';
import EditItemSupplementalNoteSection from '@/components/EditItemSupplementalNoteSection';
import CollectionAttachments from '@/components/CollectionAttachments';

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
  supplemental_note?: string;
  is_public?: boolean;
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

  const sectionCard =
    'rounded-2xl border border-black/5 bg-white p-4 shadow-[0_1px_2px_rgba(0,0,0,0.05),0_6px_18px_rgba(160,120,200,0.08)]';
  const sectionLabel = 'flex items-center gap-1.5 text-[13px] font-medium text-muted-foreground';

  const contentComponent = (
    <div className="space-y-5 mt-0 px-6 pb-6">
      {/* Title + Description in one elevated card */}
      <div className={`${sectionCard} space-y-4`}>
        <EditItemTitleSection
          title={title}
          onTitleChange={onTitleChange}
          onSave={onTitleSave}
        />

        <div className="space-y-1.5">
          <label htmlFor="edit-item-description" className={sectionLabel}>
            <AlignLeft className="h-3.5 w-3.5" />
            Description
          </label>
          <Textarea
            id="edit-item-description"
            ref={descriptionRef}
            value={description}
            onChange={(e) => { onDescriptionChange(e.target.value); resizeDescription(); }}
            onBlur={() => void onDescriptionSave(description)}
            placeholder="Add a description..."
            className="min-h-[72px] resize-none overflow-hidden rounded-xl border-black/10 bg-gray-50/60 focus-visible:ring-violet-300"
          />
        </div>
      </div>

      {/* Inline Image for image items and links with images */}
      {showInlineImage && imageUrl && (
        <div className="flex justify-center">
          <div className="group/image relative inline-block">
            <img
              src={imageUrl}
              alt={title || 'Content image'}
              className="max-w-full h-auto max-h-96 rounded-2xl shadow-[0_2px_8px_rgba(0,0,0,0.08),0_12px_32px_rgba(160,120,200,0.14)] cursor-pointer hover:opacity-95 transition-opacity"
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
                  {isImageBusy ? <Loader2 className="h-4 w-4 animate-spin" /> : <ImageUp className="h-4 w-4" />}
                </button>
                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <button
                      disabled={isImageBusy}
                      title="Remove image"
                      className="grid h-9 w-9 place-items-center rounded-xl bg-white/95 text-red-500 shadow-[0_2px_8px_rgba(0,0,0,0.18)] backdrop-blur transition-all hover:bg-white hover:shadow-lg"
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

      {/* Link Section - only for link items */}
      {item?.type === 'link' && item?.url && (
        <div className={sectionCard}>
          <EditItemLinkSection url={item.url} />
        </div>
      )}

      {/* Document Section - only for document items */}
      {(item?.type === 'document' || item?.type === 'pdf') && item?.file_path && (
        <EditItemDocumentSection 
          filePath={item.file_path} 
          fileName={item.title}
          mimeType={item.mime_type}
        />
      )}

      {/* Collection Items Section - only for collection items */}
      {item?.type === 'collection' && (
        <div className="space-y-2">
          <label className="text-sm font-medium text-muted-foreground">Collection Items</label>
          <div className="border rounded-lg p-4 bg-muted/50">
            <CollectionAttachments
              itemId={item.id}
              showAll={true}
              isCompactView={false}
            />
          </div>
        </div>
      )}

      {/* Notes & Summary Section */}
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

      {/* Public Feed Toggle */}
      <div className={sectionCard}>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3.5">
            <div className={`grid h-10 w-10 flex-none place-items-center rounded-xl shadow-inner ${localIsPublic ? 'bg-gradient-to-b from-emerald-400 to-green-500' : 'bg-gradient-to-b from-gray-200 to-gray-300'}`}>
              {localIsPublic ? (
                <Globe className="h-5 w-5 text-white" />
              ) : (
                <Lock className="h-5 w-5 text-gray-500" />
              )}
            </div>
            <div>
              <div className="text-sm font-medium">
                {localIsPublic ? 'Public Feed' : 'Private'}
              </div>
              <div className="text-xs text-muted-foreground">
                {localIsPublic
                  ? 'This item is visible in your public feed'
                  : 'This item is only visible to you'}
              </div>
            </div>
          </div>
          <Switch
            checked={localIsPublic}
            onCheckedChange={handlePublicToggle}
          />
        </div>

        {localIsPublic && feedUrl && (
          <div className="mt-3.5 flex items-center gap-2 rounded-xl border border-emerald-200/60 bg-emerald-50/50 px-3 py-2">
            <span className="flex-none text-xs text-muted-foreground">This item is visible publicly:</span>
            <a
              href={feedUrl}
              target="_blank"
              rel="noreferrer"
              className="min-w-0 flex-1 truncate text-xs font-medium text-emerald-700 hover:underline"
            >
              {feedUrl.replace('https://', '')}
            </a>
            <button
              onClick={handleCopyFeedUrl}
              title="Copy link"
              aria-label="Copy public feed link"
              className="grid h-6 w-6 flex-none place-items-center rounded-md text-emerald-600 transition-colors hover:bg-emerald-100"
            >
              {copiedFeedUrl ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
            </button>
          </div>
        )}
      </div>

      {/* Supplemental Note Section — sticky notes ride along with shared items */}
      {localIsPublic && (
        <div className={sectionCard}>
          <EditItemSupplementalNoteSection
            supplementalNote={supplementalNote}
            onSupplementalNoteChange={onSupplementalNoteChange}
          />
        </div>
      )}

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
    <TabsContent value="details" className="space-y-8 mt-0">
      {contentComponent}
    </TabsContent>
  ) : (
    contentComponent
  );
};

export default EditItemDetailsTab;
