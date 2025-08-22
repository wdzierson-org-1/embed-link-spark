
import React, { useState, useEffect } from 'react';
import { TabsContent } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Maximize, Globe, Lock } from 'lucide-react';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemDescriptionSection from '@/components/EditItemDescriptionSection';
import EditItemImageSection from '@/components/EditItemImageSection';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import EditItemMediaSection from '@/components/EditItemMediaSection';
import EditItemTagsSection from '@/components/EditItemTagsSection';
import EditItemLinkSection from '@/components/EditItemLinkSection';
import EditItemDocumentSection from '@/components/EditItemDocumentSection';
import MaximizedEditor from '@/components/MaximizedEditor';
import EditItemSupplementalNoteSection from '@/components/EditItemSupplementalNoteSection';

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
}: EditItemDetailsTabProps) => {
  const [isEditorMaximized, setIsEditorMaximized] = useState(false);
  const [mobileEditorReady, setMobileEditorReady] = useState(false);

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

  const contentComponent = (
    <div className="space-y-8 mt-0 px-6 pb-6" style={{ transform: 'translateY(-18px)' }}>
      {/* Title Section */}
      <EditItemTitleSection
        title={title}
        onTitleChange={onTitleChange}
        onSave={onTitleSave}
      />

      {/* Inline Image for image items and links with images */}
      {showInlineImage && imageUrl && (
        <div className="flex justify-center">
          <img
            src={imageUrl}
            alt={title || 'Content image'}
            className="max-w-full h-auto max-h-96 rounded-lg cursor-pointer hover:opacity-90 transition-opacity"
            onClick={handleImageClick}
            style={{ objectFit: 'contain' }}
          />
        </div>
      )}

      {/* Link Section - only for link items */}
      {item?.type === 'link' && item?.url && (
        <EditItemLinkSection url={item.url} />
      )}

      {/* Document Section - only for document items */}
      {(item?.type === 'document' || item?.type === 'pdf') && item?.file_path && (
        <EditItemDocumentSection 
          filePath={item.file_path} 
          fileName={item.title}
          mimeType={item.mime_type}
        />
      )}

      {/* Content Section */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <label className="text-sm font-medium text-muted-foreground">Content</label>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setIsEditorMaximized(true)}
            className="h-8 w-8 p-0"
          >
            <Maximize className="h-4 w-4" />
          </Button>
        </div>
        <div className="relative">
          {isContentLoading ? (
            <div className="border rounded-md p-4 min-h-[300px] flex items-center justify-center text-muted-foreground">
              Loading editor...
            </div>
          ) : !mobileEditorReady && isMobile ? (
            <div className="border rounded-md p-4 min-h-[300px] flex items-center justify-center text-muted-foreground">
              <div className="text-center">
                <div className="animate-pulse">Initializing editor...</div>
              </div>
            </div>
          ) : (
            <div className={`${isMobile ? 'min-h-[400px]' : ''}`}>
              <EditItemContentEditor
                content={content}
                onContentChange={onContentChange}
                itemId={item?.id}
                editorInstanceKey={editorKey}
                isMaximized={false}
              />
            </div>
          )}
          <div className="absolute bottom-3 right-3 text-xs text-muted-foreground bg-background/80 backdrop-blur-sm px-2 py-1 rounded">
            Press / for formatting options
          </div>
        </div>
      </div>

      {/* Summary Section */}
      <EditItemDescriptionSection
        itemId={item?.id || ''}
        description={description}
        content={content}
        title={title}
        onDescriptionChange={onDescriptionChange}
        onSave={onDescriptionSave}
      />

      {/* Supplemental Note Section */}
      <EditItemSupplementalNoteSection
        supplementalNote={supplementalNote}
        onSupplementalNoteChange={onSupplementalNoteChange}
      />

      {/* Public Feed Toggle */}
      <div className="space-y-2">
        <label className="text-sm font-medium text-muted-foreground">Visibility</label>
        <div className="flex items-center justify-between p-4 border rounded-lg bg-muted/50">
          <div className="flex items-center space-x-3">
            {item?.is_public ? (
              <Globe className="h-4 w-4 text-green-600" />
            ) : (
              <Lock className="h-4 w-4 text-muted-foreground" />
            )}
            <div>
              <div className="text-sm font-medium">
                {item?.is_public ? 'Public Feed' : 'Private'}
              </div>
              <div className="text-xs text-muted-foreground">
                {item?.is_public 
                  ? 'This item is visible in your public feed' 
                  : 'This item is only visible to you'}
              </div>
            </div>
          </div>
          <Switch
            checked={item?.is_public || false}
            onCheckedChange={onPublicToggle}
          />
        </div>
      </div>
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
