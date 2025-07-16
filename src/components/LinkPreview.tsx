
import React, { useState, useEffect } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { ExternalLink } from 'lucide-react';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  previewImageUrl?: string; // For stored image URLs that can be displayed
  url: string;
  siteName?: string;
  videoUrl?: string;
}

interface LinkPreviewProps {
  ogData: OpenGraphData;
}

const LinkPreview = ({ ogData }: LinkPreviewProps) => {
  const [imageError, setImageError] = useState(false);
  const [imageLoading, setImageLoading] = useState(false);

  // Reset error state when image URL changes
  useEffect(() => {
    const imageUrl = ogData.previewImageUrl || ogData.image;
    if (imageUrl) {
      setImageError(false);
      setImageLoading(true);
    }
  }, [ogData.previewImageUrl, ogData.image]);

  const handleImageLoad = () => {
    setImageLoading(false);
  };

  const handleImageError = () => {
    const imageUrl = ogData.previewImageUrl || ogData.image;
    console.log('Image failed to load:', imageUrl);
    setImageError(true);
    setImageLoading(false);
  };

  // Use preview image URL if available, otherwise fallback to original
  const imageUrl = ogData.previewImageUrl || ogData.image;
  const shouldShowImage = imageUrl && !imageError;

  return (
    <Card className="mt-4 border border-gray-200 hover:border-gray-300 transition-colors">
      <CardContent className="p-0">
        <div className="flex min-h-24">
          {shouldShowImage && (
            <div className="flex-shrink-0 w-24 relative">
              {imageLoading && (
                <div className="absolute inset-0 bg-gray-100 animate-pulse rounded-l-lg" />
              )}
              <img
                src={imageUrl}
                alt={ogData.title || 'Link preview'}
                className="w-full h-full object-cover rounded-l-lg"
                onLoad={handleImageLoad}
                onError={handleImageError}
                style={{ display: imageLoading ? 'none' : 'block' }}
                loading="lazy"
              />
            </div>
          )}
          <div className="flex-grow min-w-0 p-4 flex flex-col justify-center">
            <div className="flex items-center space-x-2 mb-1">
              <ExternalLink className="h-3 w-3 text-gray-500 flex-shrink-0" />
              <span className="text-xs text-gray-500 truncate">
                {ogData.siteName || new URL(ogData.url).hostname}
              </span>
              {ogData.videoUrl && (
                <span className="text-xs bg-blue-100 text-blue-600 px-1 py-0.5 rounded text-[10px]">
                  VIDEO
                </span>
              )}
            </div>
            {ogData.title && (
              <h3 className="font-medium text-sm text-gray-900 mb-1 line-clamp-2 leading-tight">
                {ogData.title}
              </h3>
            )}
            {ogData.description && (
              <p className="text-xs text-gray-600 line-clamp-3 leading-relaxed">
                {ogData.description}
              </p>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default LinkPreview;
