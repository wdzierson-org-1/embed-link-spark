
import React from 'react';
import { ExternalLink, FileText } from 'lucide-react';
import { Button } from '@/components/ui/button';

interface EditItemDocumentSectionProps {
  filePath: string;
  fileName?: string;
  mimeType?: string;
}

const EditItemDocumentSection = ({ filePath, fileName, mimeType }: EditItemDocumentSectionProps) => {
  const handleOpenDocument = () => {
    // Get the public URL for the document
    const { data } = window.supabase?.storage?.from('stash-media')?.getPublicUrl(filePath) || { data: { publicUrl: filePath } };
    window.open(data.publicUrl, '_blank', 'noopener,noreferrer');
  };

  const getFileIcon = () => {
    if (mimeType?.includes('pdf')) return <FileText className="h-3 w-3 text-red-600" />;
    if (mimeType?.includes('word') || mimeType?.includes('document')) return <FileText className="h-3 w-3 text-blue-600" />;
    return <FileText className="h-3 w-3 text-gray-600" />;
  };

  const getFileTypeLabel = () => {
    if (mimeType?.includes('pdf')) return 'PDF Document';
    if (mimeType?.includes('word') || mimeType?.includes('document')) return 'Word Document';
    if (mimeType?.includes('text')) return 'Text Document';
    return 'Document';
  };

  return (
    <div className="space-y-2">
      <label className="text-sm font-medium text-muted-foreground">Original Document</label>
      <div className="flex items-center gap-2 p-3 border rounded-md bg-muted/50">
        <div className="flex items-center gap-2 flex-1">
          {getFileIcon()}
          <div className="flex-1 min-w-0">
            <div className="text-sm font-medium truncate">
              {fileName || 'Document'}
            </div>
            <div className="text-xs text-muted-foreground">
              {getFileTypeLabel()}
            </div>
          </div>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={handleOpenDocument}
          className="h-7 w-7 p-0"
        >
          <ExternalLink className="h-3 w-3" />
        </Button>
      </div>
    </div>
  );
};

export default EditItemDocumentSection;
