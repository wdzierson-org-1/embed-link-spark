
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { Expand } from 'lucide-react';
import ContentItemImage from '@/components/ContentItemImage';
import { supabase } from '@/integrations/supabase/client';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';
  title?: string;
  file_path?: string;
  is_public?: boolean;
}

interface ContentItemHeaderProps {
  item: ContentItem;
  imageErrors: Set<string>;
  onImageError: (itemId: string) => void;
  onEditItem: (item: ContentItem) => void;
  onVideoExpand?: () => void;
  isPublicView?: boolean;
}

const ContentItemHeader = ({ 
  item, 
  imageErrors, 
  onImageError, 
  onEditItem,
  onVideoExpand,
  isPublicView = false
}: ContentItemHeaderProps) => {
  const getFileUrl = (item: ContentItem) => {
    if (item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  const handleTitleClick = () => {
    onEditItem(item);
  };

  const fileUrl = getFileUrl(item);

  return (
    <TooltipProvider>
      <div>
        {/* Image or Video at the top, clipped to card edges */}
        <div className="relative">
          {item.type === 'video' && fileUrl ? (
            <div className="relative w-full h-48 bg-black rounded-t-lg overflow-hidden">
              <video
                src={fileUrl}
                className="w-full h-full object-cover"
                controls
                preload="metadata"
              >
                Your browser does not support the video tag.
              </video>
              
              {/* Expand button overlay - shown on hover */}
              <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={onVideoExpand}
                  className="h-8 w-8 rounded-full bg-black/50 hover:bg-black/70 text-white p-0"
                >
                  <Expand className="h-4 w-4" />
                </Button>
              </div>
            </div>
          ) : (
        <ContentItemImage
          item={item}
          imageErrors={imageErrors}
          onImageError={onImageError}
          isPublicView={isPublicView}
        />
          )}

          {/* PUBLICLY SHARED badge for owner's main view */}
          {!isPublicView && item.is_public && (
            <div className="absolute top-2 right-2 z-10">
              <div className="bg-primary text-primary-foreground px-2 py-1 rounded text-xs font-medium">
                PUBLICLY SHARED
              </div>
            </div>
          )}
        </div>

        {/* Title section with clickable link */}
        {item.title && (
          <div className="mb-3 px-6 pt-6">
            {!isPublicView ? (
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={handleTitleClick}
                    className="text-left w-full group/title"
                  >
                    <h3 className="text-lg font-editorial leading-tight line-clamp-2 group-hover/title:underline transition-all duration-200 cursor-pointer">
                      {item.title}
                    </h3>
                  </button>
                </TooltipTrigger>
                <TooltipContent>
                  <p className="max-w-xs break-words">Click to edit: {item.title}</p>
                </TooltipContent>
              </Tooltip>
            ) : (
              <h3 className="text-lg font-editorial leading-tight line-clamp-2">
                {item.title}
              </h3>
            )}
          </div>
        )}
      </div>
    </TooltipProvider>
  );
};

export default ContentItemHeader;
