import React from 'react';
import { X, FileText, Link as LinkIcon, Image, Video, FileAudio, File } from 'lucide-react';
import { Button } from '@/components/ui/button';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  url?: string;
  siteName?: string;
  videoUrl?: string;
}

interface InputChipProps {
  type: 'text' | 'link' | 'image' | 'video' | 'audio' | 'file';
  content: any;
  onRemove: () => void;
  ogData?: OpenGraphData;
}

const InputChip = ({ type, content, onRemove, ogData }: InputChipProps) => {
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
        if (ogData && (ogData.image || ogData.title || ogData.description)) {
          return (
            <div className="flex items-center gap-3 max-w-[300px]">
              {ogData.image && (
                <img 
                  src={ogData.image} 
                  alt="" 
                  className="w-10 h-10 rounded object-cover flex-shrink-0" 
                />
              )}
              <div className="flex-1 min-w-0">
                <div className="text-sm font-medium truncate">
                  {ogData.title || content.url}
                </div>
                {ogData.description && (
                  <div className="text-xs text-muted-foreground truncate">
                    {ogData.description}
                  </div>
                )}
              </div>
            </div>
          );
        }
        return (
          <div className="flex items-center gap-2">
            <span className="truncate max-w-[200px]">{content.url || content.title}</span>
          </div>
        );
      case 'image':
        return (
          <div className="flex items-center gap-3">
            {content.file && (
              <img 
                src={URL.createObjectURL(content.file)} 
                alt="" 
                className="w-10 h-10 rounded object-cover" 
              />
            )}
            <div>
              <span className="text-sm font-medium truncate max-w-[150px] block">{content.name}</span>
              {content.size && (
                <span className="text-xs text-muted-foreground">
                  {(content.size / 1024 / 1024).toFixed(1)} MB
                </span>
              )}
            </div>
          </div>
        );
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
    <div className="flex items-center gap-2 bg-white border border-border rounded-lg px-3 py-2 shadow-sm max-w-fit">
      {!ogData?.image && getIcon()}
      {getDisplayContent()}
      <Button
        variant="ghost"
        size="sm"
        onClick={onRemove}
        className="h-6 w-6 p-0 hover:bg-destructive/10 flex-shrink-0"
      >
        <X className="h-3 w-3" />
      </Button>
    </div>
  );
};

export default InputChip;