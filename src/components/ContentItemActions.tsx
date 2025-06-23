
import React from 'react';
import { Button } from '@/components/ui/button';
import { MessageCircle, Download, ExternalLink, Edit, Trash2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';
  url?: string;
  file_path?: string;
}

interface ContentItemActionsProps {
  item: ContentItem;
  onDeleteItem: (id: string) => void;
  onEditItem: (item: ContentItem) => void;
  onChatWithItem?: (item: ContentItem) => void;
}

const ContentItemActions = ({ item, onDeleteItem, onEditItem, onChatWithItem }: ContentItemActionsProps) => {
  const getFileUrl = (item: ContentItem) => {
    if (item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  const handleDownloadFile = (item: ContentItem) => {
    const fileUrl = getFileUrl(item);
    if (fileUrl) {
      window.open(fileUrl, '_blank');
    }
  };

  const fileUrl = getFileUrl(item);

  return (
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
      {fileUrl && (
        <Button
          variant="ghost"
          size="sm"
          onClick={() => handleDownloadFile(item)}
          className="opacity-0 group-hover:opacity-100 transition-opacity"
          title="Download original file"
        >
          <Download className="h-4 w-4" />
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
  );
};

export default ContentItemActions;
