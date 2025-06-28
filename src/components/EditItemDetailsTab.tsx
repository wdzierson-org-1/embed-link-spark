
import React, { useState } from 'react';
import { TabsContent } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { Maximize } from 'lucide-react';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemDescriptionSection from '@/components/EditItemDescriptionSection';
import EditItemImageSection from '@/components/EditItemImageSection';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import EditItemMediaSection from '@/components/EditItemMediaSection';
import EditItemTagsSection from '@/components/EditItemTagsSection';
import EditItemLinkSection from '@/components/EditItemLinkSection';
import EditItemDocumentSection from '@/components/EditItemDocumentSection';
import MaximizedEditor from '@/components/MaximizedEditor';

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
}: EditItemDetailsTabProps) => {
  const [isEditorMaximized, setIsEditorMaximized] = useState(false);

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
          ) : (
            <EditItemContentEditor
              content={content}
              onContentChange={onContentChange}
              itemId={item?.id}
              editorInstanceKey={editorKey}
              isMaximized={false}
            />
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

      {/* Media Section */}
      <EditItemMediaSection item={item} onMediaChange={onMediaChange} />

      {/* Tags Section */}
      <EditItemTagsSection item={item} onTagsChange={onTagsChange} />
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
