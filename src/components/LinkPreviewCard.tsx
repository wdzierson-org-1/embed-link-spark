
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
    <Card className="relative border border-gray-200 bg-gray-50">
      <CardContent className="p-0">
        <div className="flex min-h-20">
          {preview.image && (
            <div className="flex-shrink-0 w-20">
              <img
                src={preview.image}
                alt={preview.title || 'Link preview'}
                className="w-full h-full object-cover rounded-l"
              />
            </div>
          )}
          <div className="flex-grow min-w-0 p-3 flex flex-col justify-center">
            <div className="flex items-center space-x-2 mb-1">
              <ExternalLink className="h-3 w-3 text-gray-500 flex-shrink-0" />
              <span className="text-xs text-gray-500 truncate">
                {preview.siteName || new URL(preview.url).hostname}
              </span>
            </div>
            {preview.title && (
              <h3 className="font-medium text-sm text-gray-900 mb-1 line-clamp-1">
                {preview.title}
              </h3>
            )}
            {preview.description && (
              <p className="text-xs text-gray-600 line-clamp-2 leading-relaxed">
                {preview.description}
              </p>
            )}
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={onRemove}
            className="absolute top-1 right-1 h-6 w-6 p-0 hover:bg-red-100"
          >
            <X className="h-3 w-3" />
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};

export default LinkPreviewCard;
