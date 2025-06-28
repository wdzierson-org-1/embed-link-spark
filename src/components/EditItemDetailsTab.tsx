
import React from 'react';
import { TabsContent } from '@/components/ui/tabs';
import EditItemDescriptionSection from '@/components/EditItemDescriptionSection';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import EditItemTagsSection from '@/components/EditItemTagsSection';
import EditItemAttachments from '@/components/EditItemAttachments';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
  links?: any[];
  files?: any[];
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
  onTagsChange: (tags: string[]) => Promise<void>;
  onMediaChange: () => void;
  isInsideTabs: boolean;
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
  isInsideTabs,
}: EditItemDetailsTabProps) => {
  const TabContent = ({ children }: { children: React.ReactNode }) => {
    if (isInsideTabs) {
      return <TabsContent value="details" className="space-y-6 px-6 pb-6">{children}</TabsContent>;
    }
    return <div className="space-y-6 px-6 pb-6">{children}</div>;
  };

  return (
    <TabContent>
      {/* Note Content Editor */}
      {(item?.type === 'text' || item?.type === 'link' || item?.type === 'unified' || !item?.type) && (
        <div>
          <label className="text-sm font-medium text-muted-foreground mb-3 block">Note</label>
          <EditItemContentEditor
            content={content}
            onContentChange={onContentChange}
            itemId={item?.id}
            editorInstanceKey={editorKey}
          />
        </div>
      )}

      {/* AI Summary (Description) */}
      <EditItemDescriptionSection
        itemId={item?.id || ''}
        description={description}
        content={content}
        title={title}
        onDescriptionChange={onDescriptionChange}
        onSave={onDescriptionSave}
      />

      {/* Attachments - show if they exist */}
      {item && (item.links || item.files) && (
        <EditItemAttachments
          links={item.links}
          files={item.files}
          readonly={true}
        />
      )}

      {/* Tags */}
      <EditItemTagsSection
        item={item}
        onTagsChange={onTagsChange}
      />
    </TabContent>
  );
};

export default EditItemDetailsTab;
