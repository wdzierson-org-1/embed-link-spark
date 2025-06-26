
import React from 'react';
import { Button } from '@/components/ui/button';
import { X, File, Music, Video as VideoIcon } from 'lucide-react';

interface MediaRemovalItemProps {
  fileName: string;
  fileType: 'audio' | 'video' | 'document';
  onRemove: () => void;
}

const MediaRemovalItem = ({ fileName, fileType, onRemove }: MediaRemovalItemProps) => {
  const getIcon = () => {
    switch (fileType) {
      case 'audio': return <Music className="h-4 w-4" />;
      case 'video': return <VideoIcon className="h-4 w-4" />;
      default: return <File className="h-4 w-4" />;
    }
  };

  return (
    <div className="flex items-center justify-between p-2 bg-gray-50 rounded border">
      <div className="flex items-center gap-2">
        {getIcon()}
        <span className="text-sm text-gray-700 truncate">{fileName}</span>
      </div>
      <Button
        variant="ghost"
        size="sm"
        onClick={onRemove}
        className="h-6 w-6 p-0 text-gray-500 hover:text-red-500"
      >
        <X className="h-4 w-4" />
      </Button>
    </div>
  );
};

export default MediaRemovalItem;
