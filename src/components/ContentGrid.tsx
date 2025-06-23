
import { useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { FileText, Link as LinkIcon, Image, Mic, Video, Trash2, ExternalLink, Edit, MessageCircle } from 'lucide-react';
import { format } from 'date-fns';
import { supabase } from '@/integrations/supabase/client';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';
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
  onEditItem: (item: ContentItem) => void;
  onChatWithItem?: (item: ContentItem) => void;
}

const ContentGrid = ({ items, onDeleteItem, onEditItem, onChatWithItem }: ContentGridProps) => {
  const [imageErrors, setImageErrors] = useState<Set<string>>(new Set());

  const getIcon = (type: string) => {
    switch (type) {
      case 'text': return <FileText className="h-4 w-4" />;
      case 'link': return <LinkIcon className="h-4 w-4" />;
      case 'image': return <Image className="h-4 w-4" />;
      case 'audio': return <Mic className="h-4 w-4" />;
      case 'video': return <Video className="h-4 w-4" />;
      case 'document': return <FileText className="h-4 w-4" />;
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
      case 'document': return 'bg-yellow-100 text-yellow-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  const getImageUrl = (item: ContentItem) => {
    if (item.type === 'image' && item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  const handleImageError = (itemId: string) => {
    setImageErrors(prev => new Set([...prev, itemId]));
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
      {items.map((item) => {
        const imageUrl = getImageUrl(item);
        const showImage = imageUrl && !imageErrors.has(item.id);

        return (
          <Card key={item.id} className="group">
            <CardHeader className="pb-3">
              <div className="flex items-center justify-between">
                <Badge className={getTypeColor(item.type)}>
                  {getIcon(item.type)}
                  <span className="ml-1 capitalize">{item.type === 'document' ? 'Document' : item.type}</span>
                </Badge>
                <div className="flex items-center space-x-1">
                  {onChatWithItem && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => onChatWithItem(item)}
                      className="opacity-0 group-hover:opacity-100 transition-opacity"
                      title="Chat with this item"
                    >
                      <MessageCircle className="h-4 w-4" />
                    </Button>
                  )}
                  {item.url && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => window.open(item.url, '_blank')}
                      className="opacity-0 group-hover:opacity-100 transition-opacity"
                    >
                      <ExternalLink className="h-4 w-4" />
                    </Button>
                  )}
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => onEditItem(item)}
                    className="opacity-0 group-hover:opacity-100 transition-opacity"
                  >
                    <Edit className="h-4 w-4" />
                  </Button>
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
              {showImage && (
                <div className="mb-3">
                  <img
                    src={imageUrl}
                    alt={item.title || 'Content thumbnail'}
                    className="w-full h-32 object-cover rounded-md"
                    onError={() => handleImageError(item.id)}
                  />
                </div>
              )}
              
              {item.description && (
                <div className="mb-2">
                  <p className="text-sm font-medium text-blue-600 mb-1">AI Description:</p>
                  <p className="text-sm text-muted-foreground line-clamp-3">
                    {item.description}
                  </p>
                </div>
              )}
              {item.content && (
                <div className="mb-2">
                  <p className="text-sm font-medium mb-1">Content:</p>
                  <p className="text-sm text-muted-foreground line-clamp-3">
                    {item.content}
                  </p>
                </div>
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
        );
      })}
    </div>
  );
};

export default ContentGrid;
