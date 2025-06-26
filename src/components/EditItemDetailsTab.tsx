
import React from 'react';
import { TabsContent } from '@/components/ui/tabs';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemDescriptionSection from '@/components/EditItemDescriptionSection';
import EditItemImageSection from '@/components/EditItemImageSection';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import EditItemMediaSection from '@/components/EditItemMediaSection';
import EditItemTagsSection from '@/components/EditItemTagsSection';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface EditItemDetailsTabProps {
  item: ContentItem | null;
  title: string;
  description: string;
  content: string;
  isContentLoading: boolean;
  editorKey: string;
  onTitleChange: (title: string) => void;
  onDescriptionChange: (description: string) => void;
  onContentChange: (content: string) => void;
  onTitleSave: (title: string) => Promise<void>;
  onDescriptionSave: (description: string) => Promise<void>;
  onTagsChange: () => void;
  onMediaChange: () => void;
}

const EditItemDetailsTab = ({
  item,
  title,
  description,
  content,
  isContentLoading,
  editorKey,
  onTitleChange,
  onDescriptionChange,
  onContentChange,
  onTitleSave,
  onDescriptionSave,
  onTagsChange,
  onMediaChange,
}: EditItemDetailsTabProps) => {
  return (
    <TabsContent value="details" className="px-6 pb-6 mt-0">
      <div className="space-y-8 pt-6">
        {/* Title Section */}
        <EditItemTitleSection
          title={title}
          onTitleChange={onTitleChange}
          onSave={onTitleSave}
        />

        {/* Content Section */}
        <div className="space-y-2">
          <label className="text-sm font-medium text-muted-foreground">Content</label>
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
    </TabsContent>
  );
};

export default EditItemDetailsTab;
