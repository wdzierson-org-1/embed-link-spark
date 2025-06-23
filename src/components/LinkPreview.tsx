
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
      <CardContent className="p-4">
        <div className="flex space-x-4">
          {ogData.image && (
            <div className="flex-shrink-0">
              <img
                src={ogData.image}
                alt={ogData.title || 'Link preview'}
                className="w-16 h-16 object-cover rounded"
              />
            </div>
          )}
          <div className="flex-grow min-w-0">
            <div className="flex items-center space-x-2 mb-1">
              <ExternalLink className="h-4 w-4 text-gray-500" />
              <span className="text-sm text-gray-500 truncate">
                {ogData.siteName || new URL(ogData.url).hostname}
              </span>
            </div>
            {ogData.title && (
              <h3 className="font-medium text-gray-900 mb-1 line-clamp-2">
                {ogData.title}
              </h3>
            )}
            {ogData.description && (
              <p className="text-sm text-gray-600 line-clamp-2">
                {ogData.description}
              </p>
            )}
            <p className="text-xs text-blue-600 mt-1 truncate">
              {ogData.url}
            </p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default LinkPreview;
