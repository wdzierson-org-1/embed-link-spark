import React from 'react';
import { X, FileText, Link as LinkIcon, Image, Video, FileAudio, File } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { SUPABASE_URL } from '@/integrations/supabase/client';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  previewImageUrl?: string; // Supabase public URL for downloaded images
  url?: string;
  siteName?: string;
  videoUrl?: string;
}

interface InputChipProps {
  type: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
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
        if (ogData && (ogData.previewImageUrl || ogData.image || ogData.title || ogData.description)) {
          const imageUrl = ogData.previewImageUrl || ogData.image;
          return (
            <div className="flex items-center gap-3 max-w-[300px]">
              {imageUrl && (
                <img 
                  src={imageUrl} 
                  alt="" 
                  className="w-10 h-10 rounded object-cover flex-shrink-0" 
                  referrerPolicy="no-referrer"
                  loading="lazy"
                  decoding="async"
                  onError={(e) => {
                    console.log('InputChip image failed to load:', imageUrl);
                    // Try proxy URL if current URL isn't already proxied
                    if (!e.currentTarget.src.includes('/functions/v1/image-proxy')) {
                      const proxiedUrl = `${SUPABASE_URL}/functions/v1/image-proxy?url=${encodeURIComponent(imageUrl)}`;
                      console.log('Trying proxy URL:', proxiedUrl);
                      e.currentTarget.src = proxiedUrl;
                    } else {
                      // Proxy also failed, hide image
                      e.currentTarget.style.display = 'none';
                    }
                  }}
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
            {content.file ? (
              <img 
                src={URL.createObjectURL(content.file)} 
                alt="" 
                className="w-10 h-10 rounded object-cover" 
              />
            ) : (
              <div className="w-10 h-10 rounded bg-muted flex items-center justify-center">
                <Image className="h-5 w-5 text-muted-foreground" />
              </div>
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
      case 'document':
        return (
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded bg-muted flex items-center justify-center">
              {type === 'video' && <Video className="h-5 w-5 text-muted-foreground" />}
              {type === 'audio' && <FileAudio className="h-5 w-5 text-muted-foreground" />}
              {type === 'document' && <File className="h-5 w-5 text-muted-foreground" />}
            </div>
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
      default:
        return <span className="truncate max-w-[200px]">{content.title || content.text}</span>;
    }
  };

  return (
    <div className="flex items-center gap-2 bg-white border border-border rounded-lg px-3 py-2 shadow-sm max-w-fit">
      {!ogData?.previewImageUrl && !ogData?.image && !content.file && getIcon()}
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