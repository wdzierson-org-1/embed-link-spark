import React, { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Link2, FileText, Image, Video, Music, Download, ExternalLink, Eye } from 'lucide-react';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import ImageLightbox from '@/components/ImageLightbox';

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
  isCompactView?: boolean;
}

const CollectionAttachments = ({ itemId, maxDisplay = 3, showAll = false, isCompactView = false }: CollectionAttachmentsProps) => {
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);
  const [selectedVideoUrl, setSelectedVideoUrl] = useState<string>('');
  const [selectedVideoTitle, setSelectedVideoTitle] = useState<string>('');
  const [isImageLightboxOpen, setIsImageLightboxOpen] = useState(false);
  const [selectedImageUrl, setSelectedImageUrl] = useState<string>('');
  const [selectedImageTitle, setSelectedImageTitle] = useState<string>('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchAttachments();
  }, [itemId]);

  const fetchAttachments = async () => {
    try {
      console.log('Fetching attachments for itemId:', itemId);
      const { data, error } = await supabase
        .from('item_attachments')
        .select('*')
        .eq('item_id', itemId)
        .order('created_at', { ascending: true });

      if (error) {
        console.error('Error fetching attachments:', error);
        return;
      }

      console.log('Fetched attachments:', data);
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

  const handleImageClick = (filePath: string, title: string) => {
    setSelectedImageUrl(getFileUrl(filePath));
    setSelectedImageTitle(title || 'Image');
    setIsImageLightboxOpen(true);
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
    return (
      <div className="text-sm text-muted-foreground py-2">
        No items in this collection yet.
      </div>
    );
  }

  const displayedAttachments = showAll ? attachments : attachments.slice(0, maxDisplay);
  const remainingCount = attachments.length - maxDisplay;

  // Compact view for home screen
  if (isCompactView) {
    const hasMultipleTypes = new Set(attachments.map(a => a.type)).size > 1;
    const title = hasMultipleTypes ? "Mixed Collection" : "";
    
    return (
      <div className="space-y-2">
        {title && (
          <div className="text-sm font-medium text-foreground">
            {title}
          </div>
        )}
        <div className="text-sm text-muted-foreground">
          Collection of {attachments.length} item{attachments.length > 1 ? 's' : ''}:
        </div>
        <div className="space-y-1.5">
          {displayedAttachments.map((attachment) => (
            <div key={attachment.id} className="flex items-center gap-2 text-sm">
              <div className="flex-shrink-0 text-muted-foreground">
                {getAttachmentIcon(attachment.type)}
              </div>
              <span className="text-muted-foreground uppercase text-xs font-medium">
                {attachment.mime_type?.split('/')[1] || attachment.type}:
              </span>
              <span className="truncate font-medium">
                {attachment.title || 'Unnamed file'}
              </span>
              {attachment.metadata?.aiProcessed && (
                <span className="text-xs text-blue-600">transcribed</span>
              )}
            </div>
          ))}
          {!showAll && remainingCount > 0 && (
            <div className="text-sm text-muted-foreground">
              + {remainingCount} more attachment{remainingCount > 1 ? 's' : ''}
            </div>
          )}
        </div>
      </div>
    );
  }

  // Full view for edit panel
  return (
    <div className="space-y-4">
      <div className="border-l-2 border-primary/20 pl-3">
        <h4 className="text-sm font-semibold text-foreground mb-1">Collection Items</h4>
        <p className="text-xs text-muted-foreground">Original files and links added to this collection</p>
      </div>
      
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
              <div className="text-xs text-muted-foreground line-clamp-2 leading-relaxed max-w-64">
                {attachment.description}
              </div>
            )}
            {attachment.metadata?.aiProcessed && (
              <div className="text-xs text-blue-600 font-medium mt-1 flex items-center gap-1">
                <div className="w-1.5 h-1.5 bg-blue-500 rounded-full animate-pulse"></div>
                AI Enhanced
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
              <div className="flex items-center gap-2">
                <div 
                  className="w-12 h-12 rounded overflow-hidden cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all"
                  onClick={() => handleImageClick(attachment.file_path!, attachment.title || 'Image')}
                >
                  <img
                    src={getFileUrl(attachment.file_path)}
                    alt={attachment.title || 'Image'}
                    className="w-full h-full object-cover"
                  />
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => handleImageClick(attachment.file_path!, attachment.title || 'Image')}
                  className="gap-1"
                >
                  <Eye className="h-3 w-3" />
                  View
                </Button>
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
      </div>

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

      <ImageLightbox
        src={selectedImageUrl}
        fileName={selectedImageTitle}
        isOpen={isImageLightboxOpen}
        onClose={() => setIsImageLightboxOpen(false)}
      />
    </div>
  );
};

export default CollectionAttachments;