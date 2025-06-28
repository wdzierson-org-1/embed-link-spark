
import React from 'react';
import LinkPreviewCard from './LinkPreviewCard';
import FilePreviewCard from './FilePreviewCard';

interface LinkPreview {
  id: string;
  url: string;
  title?: string;
  description?: string;
  image?: string;
  siteName?: string;
}

interface FilePreview {
  id: string;
  file: File;
  preview?: string;
}

interface EditItemAttachmentsProps {
  links?: LinkPreview[];
  files?: FilePreview[];
  onRemoveLink?: (id: string) => void;
  onRemoveFile?: (id: string) => void;
  readonly?: boolean;
}

const EditItemAttachments = ({ 
  links = [], 
  files = [], 
  onRemoveLink, 
  onRemoveFile, 
  readonly = false 
}: EditItemAttachmentsProps) => {
  const hasAttachments = links.length > 0 || files.length > 0;

  if (!hasAttachments) {
    return null;
  }

  return (
    <div className="space-y-4">
      <h3 className="text-sm font-medium text-gray-700">Attachments</h3>
      <div className="flex flex-wrap gap-2">
        {links.map((link) => (
          <div key={link.id} className="flex-none w-80">
            <LinkPreviewCard
              preview={link}
              onRemove={readonly ? () => {} : () => onRemoveLink?.(link.id)}
            />
          </div>
        ))}
        {files.map((file) => (
          <div key={file.id} className="flex-none w-80">
            <FilePreviewCard
              preview={file}
              onRemove={readonly ? () => {} : () => onRemoveFile?.(file.id)}
            />
          </div>
        ))}
      </div>
    </div>
  );
};

export default EditItemAttachments;
