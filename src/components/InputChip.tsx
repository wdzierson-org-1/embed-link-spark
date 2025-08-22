import React from 'react';
import { X, FileText, Link as LinkIcon, Image, Video, FileAudio, File } from 'lucide-react';
import { Button } from '@/components/ui/button';

interface InputChipProps {
  type: 'text' | 'link' | 'image' | 'video' | 'audio' | 'file';
  content: any;
  onRemove: () => void;
}

const InputChip = ({ type, content, onRemove }: InputChipProps) => {
  const getIcon = () => {
    switch (type) {
      case 'text':
        return <FileText className="h-4 w-4" />;
      case 'link':
        return <LinkIcon className="h-4 w-4" />;
      case 'image':
        return <Image className="h-4 w-4" />;
      case 'video':
        return <Video className="h-4 w-4" />;
      case 'audio':
        return <FileAudio className="h-4 w-4" />;
      default:
        return <File className="h-4 w-4" />;
    }
  };

  const getDisplayContent = () => {
    switch (type) {
      case 'link':
        return (
          <div className="flex items-center gap-2">
            {content.favicon && (
              <img src={content.favicon} alt="" className="w-4 h-4" />
            )}
            <span className="truncate max-w-[200px]">{content.url || content.title}</span>
          </div>
        );
      case 'image':
      case 'video':
      case 'audio':
      case 'file':
        return (
          <div className="flex items-center gap-2">
            <span className="truncate max-w-[150px]">{content.name}</span>
            {content.size && (
              <span className="text-xs text-muted-foreground">
                {(content.size / 1024 / 1024).toFixed(1)} MB
              </span>
            )}
          </div>
        );
      default:
        return <span className="truncate max-w-[200px]">{content.title || content.text}</span>;
    }
  };

  return (
    <div className="flex items-center gap-2 bg-white border border-border rounded-lg px-3 py-2 shadow-sm">
      {getIcon()}
      {getDisplayContent()}
      <Button
        variant="ghost"
        size="sm"
        onClick={onRemove}
        className="h-6 w-6 p-0 hover:bg-destructive/10"
      >
        <X className="h-3 w-3" />
      </Button>
    </div>
  );
};

export default InputChip;