
import { useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { FileText, Link as LinkIcon, Image, Mic, Video, Trash2, ExternalLink } from 'lucide-react';
import { format } from 'date-fns';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video';
  title?: string;
  content?: string;
  url?: string;
  file_path?: string;
  description?: string;
  tags?: string[];
  created_at: string;
}

interface ContentGridProps {
  items: ContentItem[];
  onDeleteItem: (id: string) => void;
}

const ContentGrid = ({ items, onDeleteItem }: ContentGridProps) => {
  const getIcon = (type: string) => {
    switch (type) {
      case 'text': return <FileText className="h-4 w-4" />;
      case 'link': return <LinkIcon className="h-4 w-4" />;
      case 'image': return <Image className="h-4 w-4" />;
      case 'audio': return <Mic className="h-4 w-4" />;
      case 'video': return <Video className="h-4 w-4" />;
      default: return <FileText className="h-4 w-4" />;
    }
  };

  const getTypeColor = (type: string) => {
    switch (type) {
      case 'text': return 'bg-blue-100 text-blue-800';
      case 'link': return 'bg-green-100 text-green-800';
      case 'image': return 'bg-purple-100 text-purple-800';
      case 'audio': return 'bg-orange-100 text-orange-800';
      case 'video': return 'bg-red-100 text-red-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  if (items.length === 0) {
    return (
      <div className="text-center py-12">
        <p className="text-muted-foreground">No content yet. Start adding items to your stash!</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {items.map((item) => (
        <Card key={item.id} className="group">
          <CardHeader className="pb-3">
            <div className="flex items-center justify-between">
              <Badge className={getTypeColor(item.type)}>
                {getIcon(item.type)}
                <span className="ml-1 capitalize">{item.type}</span>
              </Badge>
              <div className="flex items-center space-x-1">
                {item.url && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => window.open(item.url, '_blank')}
                  >
                    <ExternalLink className="h-4 w-4" />
                  </Button>
                )}
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => onDeleteItem(item.id)}
                  className="opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>
            </div>
            {item.title && (
              <CardTitle className="text-lg">{item.title}</CardTitle>
            )}
          </CardHeader>
          <CardContent>
            {item.content && (
              <p className="text-sm text-muted-foreground mb-2 line-clamp-3">
                {item.content}
              </p>
            )}
            {item.description && (
              <p className="text-sm text-muted-foreground mb-2 line-clamp-2">
                {item.description}
              </p>
            )}
            {item.url && item.type === 'link' && (
              <p className="text-sm text-blue-600 mb-2 truncate">
                {item.url}
              </p>
            )}
            {item.tags && item.tags.length > 0 && (
              <div className="flex flex-wrap gap-1 mb-2">
                {item.tags.slice(0, 3).map((tag, index) => (
                  <Badge key={index} variant="outline" className="text-xs">
                    {tag}
                  </Badge>
                ))}
                {item.tags.length > 3 && (
                  <Badge variant="outline" className="text-xs">
                    +{item.tags.length - 3}
                  </Badge>
                )}
              </div>
            )}
            <p className="text-xs text-muted-foreground">
              {format(new Date(item.created_at), 'MMM d, yyyy')}
            </p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
};

export default ContentGrid;
