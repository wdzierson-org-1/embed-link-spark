
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { File, Image, Video, Mic, FileText, X } from 'lucide-react';

interface FilePreview {
  id: string;
  file: File;
  preview?: string;
}

interface FilePreviewCardProps {
  preview: FilePreview;
  onRemove: () => void;
}

const FilePreviewCard = ({ preview, onRemove }: FilePreviewCardProps) => {
  const getFileIcon = (file: File) => {
    if (file.type.startsWith('image/')) return <Image className="w-3 h-3" />;
    if (file.type.startsWith('video/')) return <Video className="w-3 h-3" />;
    if (file.type.startsWith('audio/')) return <Mic className="w-3 h-3" />;
    return <FileText className="w-3 h-3" />;
  };

  const formatFileSize = (bytes: number) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  return (
    <Card className="relative border border-gray-200 bg-white shadow-sm">
      <CardContent className="p-0">
        <div className="flex items-center h-16 p-2">
          {preview.preview ? (
            <div className="flex-shrink-0 w-12 h-12 mr-2">
              <img
                src={preview.preview}
                alt={preview.file.name}
                className="w-full h-full object-cover rounded"
              />
            </div>
          ) : (
            <div className="flex-shrink-0 w-12 h-12 mr-2 bg-gray-100 rounded flex items-center justify-center">
              {getFileIcon(preview.file)}
            </div>
          )}
          
          <div className="flex-grow min-w-0">
            <h3 className="font-medium text-xs text-gray-900 truncate mb-0.5">
              {preview.file.name}
            </h3>
            <div className="flex items-center space-x-1 text-xs text-gray-500">
              <span>{formatFileSize(preview.file.size)}</span>
              <span>•</span>
              <span>{preview.file.type.split('/')[1]?.toUpperCase() || 'FILE'}</span>
            </div>
          </div>

          <Button
            variant="ghost"
            size="sm"
            onClick={onRemove}
            className="absolute top-0.5 right-0.5 h-5 w-5 p-0 hover:bg-red-100 opacity-70 hover:opacity-100"
          >
            <X className="h-3 w-3" />
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};

export default FilePreviewCard;
