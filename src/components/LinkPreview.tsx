
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { ExternalLink } from 'lucide-react';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  url: string;
  siteName?: string;
}

interface LinkPreviewProps {
  ogData: OpenGraphData;
}

const LinkPreview = ({ ogData }: LinkPreviewProps) => {
  return (
    <Card className="mt-4 border border-gray-200">
      <CardContent className="p-0">
        <div className="flex min-h-24">
          {ogData.image && (
            <div className="flex-shrink-0 w-24">
              <img
                src={ogData.image}
                alt={ogData.title || 'Link preview'}
                className="w-full h-full object-cover rounded-l"
              />
            </div>
          )}
          <div className="flex-grow min-w-0 p-4 flex flex-col justify-center">
            <div className="flex items-center space-x-2 mb-1">
              <ExternalLink className="h-3 w-3 text-gray-500 flex-shrink-0" />
              <span className="text-xs text-gray-500 truncate">
                {ogData.siteName || new URL(ogData.url).hostname}
              </span>
            </div>
            {ogData.title && (
              <h3 className="font-medium text-sm text-gray-900 mb-1 line-clamp-1">
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
