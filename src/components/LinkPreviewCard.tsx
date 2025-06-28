
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ExternalLink, X } from 'lucide-react';

interface LinkPreview {
  id: string;
  url: string;
  title?: string;
  description?: string;
  image?: string;
  siteName?: string;
}

interface LinkPreviewCardProps {
  preview: LinkPreview;
  onRemove: () => void;
}

const LinkPreviewCard = ({ preview, onRemove }: LinkPreviewCardProps) => {
  return (
    <Card className="relative border border-gray-200 bg-white shadow-sm">
      <CardContent className="p-0">
        <div className="flex h-16">
          {preview.image && (
            <div className="flex-shrink-0 w-16">
              <img
                src={preview.image}
                alt={preview.title || 'Link preview'}
                className="w-full h-full object-cover rounded-l"
              />
            </div>
          )}
          <div className="flex-grow min-w-0 p-2 flex flex-col justify-center">
            <div className="flex items-center space-x-1 mb-1">
              <ExternalLink className="h-3 w-3 text-gray-400 flex-shrink-0" />
              <span className="text-xs text-gray-500 truncate">
                {preview.siteName || new URL(preview.url).hostname}
              </span>
            </div>
            {preview.title && (
              <h3 className="font-medium text-xs text-gray-900 line-clamp-1 mb-0.5">
                {preview.title}
              </h3>
            )}
            {preview.description && (
              <p className="text-xs text-gray-600 line-clamp-1 leading-tight">
                {preview.description}
              </p>
            )}
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

export default LinkPreviewCard;
