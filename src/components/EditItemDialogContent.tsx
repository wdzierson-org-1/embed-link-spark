
import React from 'react';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemDescriptionSection from '@/components/EditItemDescriptionSection';
import EditItemImageSection from '@/components/EditItemImageSection';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import EditItemDialogMedia from '@/components/EditItemDialogMedia';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface EditItemDialogContentProps {
  item: ContentItem;
  title: string;
  description: string;
  content: string;
  editorInstanceKey: string;
  fileUrl: string | null;
  onTitleChange: (title: string) => void;
  onDescriptionChange: (description: string) => void;
  onContentChange: (content: string) => void;
  onTitleSave: (title: string) => Promise<void>;
  onDescriptionSave: (description: string) => Promise<void>;
  onImageUpdate: (hasImage: boolean, imageUrl: string) => Promise<void>;
  onRemoveMedia: () => Promise<void>;
}

const EditItemDialogContent = ({
  item,
  title,
  description,
  content,
  editorInstanceKey,
  fileUrl,
  onTitleChange,
  onDescriptionChange,
  onContentChange,
  onTitleSave,
  onDescriptionSave,
  onImageUpdate,
  onRemoveMedia,
}: EditItemDialogContentProps) => {
  return (
    <div className="space-y-6">
      <EditItemTitleSection
        title={title}
        onTitleChange={onTitleChange}
        onSave={onTitleSave}
      />

      <EditItemDescriptionSection
        itemId={item.id}
        description={description}
        content={content}
        title={title}
        onDescriptionChange={onDescriptionChange}
        onSave={onDescriptionSave}
      />

      {/* Media Section */}
      <EditItemDialogMedia
        item={item}
        fileUrl={fileUrl}
        onRemoveMedia={onRemoveMedia}
      />

      {item.type === 'image' && (
        <EditItemImageSection
          itemId={item.id}
          hasImage={!!item.file_path}
          imageUrl={fileUrl || ''}
          onImageStateChange={onImageUpdate}
        />
      )}

      {(item.type === 'text' || item.type === 'link') && (
        <EditItemContentEditor
          initialContent={content}
          onContentChange={onContentChange}
          itemId={item.id}
          editorInstanceKey={editorInstanceKey}
        />
      )}
    </div>
  );
};

export default EditItemDialogContent;
