import React, { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Link2, FileText, Image, Video, Music, Download, ExternalLink } from 'lucide-react';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';

interface Attachment {
  id: string;
  type: string;
  url?: string;
  file_path?: string;
  title?: string;
  description?: string;
  metadata?: any; // Use any to match the Json type from Supabase
  file_size?: number;
  mime_type?: string;
}

interface CollectionAttachmentsProps {
  itemId: string;
  maxDisplay?: number;
  showAll?: boolean;
}

const CollectionAttachments = ({ itemId, maxDisplay = 3, showAll = false }: CollectionAttachmentsProps) => {
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);
  const [selectedVideoUrl, setSelectedVideoUrl] = useState<string>('');
  const [selectedVideoTitle, setSelectedVideoTitle] = useState<string>('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchAttachments();
  }, [itemId]);

  const fetchAttachments = async () => {
    try {
      const { data, error } = await supabase
        .from('item_attachments')
        .select('*')
        .eq('item_id', itemId)
        .order('created_at', { ascending: true });

      if (error) {
        console.error('Error fetching attachments:', error);
        return;
      }

      setAttachments(data || []);
    } catch (error) {
      console.error('Error fetching attachments:', error);
    } finally {
      setLoading(false);
    }
  };

  const getFileUrl = (filePath: string): string => {
    const { data } = supabase.storage.from('stash-media').getPublicUrl(filePath);
    return data.publicUrl;
  };

  const getAttachmentIcon = (type: string) => {
    switch (type) {
      case 'link': return <Link2 className="h-4 w-4" />;
      case 'image': return <Image className="h-4 w-4" />;
      case 'video': return <Video className="h-4 w-4" />;
      case 'audio': return <Music className="h-4 w-4" />;
      default: return <FileText className="h-4 w-4" />;
    }
  };

  const handleVideoClick = (filePath: string, title: string) => {
    setSelectedVideoUrl(getFileUrl(filePath));
    setSelectedVideoTitle(title || 'Video');
    setIsVideoLightboxOpen(true);
  };

  const formatFileSize = (bytes?: number) => {
    if (!bytes) return '';
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${sizes[i]}`;
  };

  if (loading) {
    return <div className="text-sm text-muted-foreground">Loading attachments...</div>;
  }

  if (attachments.length === 0) {
    return null;
  }

  const displayedAttachments = showAll ? attachments : attachments.slice(0, maxDisplay);
  const remainingCount = attachments.length - maxDisplay;

  return (
    <div className="space-y-3">
      {displayedAttachments.map((attachment) => (
        <div key={attachment.id} className="flex items-center gap-3 p-3 bg-muted/30 rounded-lg">
          <div className="flex-shrink-0">
            <Badge variant="secondary" className="gap-1">
              {getAttachmentIcon(attachment.type)}
              {attachment.type}
            </Badge>
          </div>
          
          <div className="flex-1 min-w-0">
            <div className="font-medium text-sm truncate">
              {attachment.title || 'Untitled'}
            </div>
            {attachment.description && (
              <div className="text-xs text-muted-foreground line-clamp-1">
                {attachment.description}
              </div>
            )}
            {attachment.file_size && (
              <div className="text-xs text-muted-foreground">
                {formatFileSize(attachment.file_size)}
              </div>
            )}
          </div>

          <div className="flex-shrink-0">
            {attachment.type === 'link' && attachment.url && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => window.open(attachment.url, '_blank')}
                className="gap-1"
              >
                <ExternalLink className="h-3 w-3" />
                Visit
              </Button>
            )}
            
            {attachment.type === 'audio' && attachment.file_path && (
              <div className="w-48">
                <MediaPlayer
                  src={getFileUrl(attachment.file_path)}
                  fileName={attachment.title || 'Audio'}
                  showRemove={false}
                />
              </div>
            )}
            
            {attachment.type === 'video' && attachment.file_path && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => handleVideoClick(attachment.file_path!, attachment.title || 'Video')}
                className="gap-1"
              >
                <Video className="h-3 w-3" />
                Play
              </Button>
            )}
            
            {attachment.type === 'image' && attachment.file_path && (
              <div className="w-12 h-12 rounded overflow-hidden">
                <img
                  src={getFileUrl(attachment.file_path)}
                  alt={attachment.title || 'Image'}
                  className="w-full h-full object-cover"
                />
              </div>
            )}
            
            {attachment.file_path && attachment.type !== 'audio' && attachment.type !== 'image' && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => window.open(getFileUrl(attachment.file_path!), '_blank')}
                className="gap-1"
              >
                <Download className="h-3 w-3" />
                Download
              </Button>
            )}
          </div>
        </div>
      ))}

      {!showAll && remainingCount > 0 && (
        <div className="text-center">
          <Button variant="ghost" size="sm" className="text-muted-foreground">
            +{remainingCount} more attachment{remainingCount > 1 ? 's' : ''}
          </Button>
        </div>
      )}

      <VideoLightbox
        src={selectedVideoUrl}
        fileName={selectedVideoTitle}
        isOpen={isVideoLightboxOpen}
        onClose={() => setIsVideoLightboxOpen(false)}
      />
    </div>
  );
};

export default CollectionAttachments;