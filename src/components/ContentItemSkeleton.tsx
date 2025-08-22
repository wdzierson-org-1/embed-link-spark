
import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Progress } from '@/components/ui/progress';
import { FileText, Image, Video, Mic, Link, Package } from 'lucide-react';

interface ContentItemSkeletonProps {
  showProgress?: boolean;
  title?: string;
  description?: string;
  type?: string;
  fileSize?: number;
}

const ContentItemSkeleton = ({ 
  showProgress = false, 
  title = "Processing...", 
  description = "Processing...",
  type = "text",
  fileSize
}: ContentItemSkeletonProps) => {
  const [currentMessage, setCurrentMessage] = useState(0);
  const [flashEffect, setFlashEffect] = useState(true);

  const getTypeIcon = (type: string) => {
    switch (type) {
      case 'image': return <Image className="h-4 w-4" />;
      case 'video': return <Video className="h-4 w-4" />;
      case 'audio': return <Mic className="h-4 w-4" />;
      case 'link': return <Link className="h-4 w-4" />;
      case 'collection': return <Package className="h-4 w-4" />;
      default: return <FileText className="h-4 w-4" />;
    }
  };

  const getProcessingMessages = (type: string, fileSize?: number) => {
    const baseMessages = ["Processing...", "Almost done..."];
    
    switch (type) {
      case 'audio':
        return ["Uploading audio...", "Transcribing...", "Analyzing content...", "Almost done..."];
      case 'video':
        return ["Uploading video...", "Processing video...", "Extracting content...", "Almost done..."];
      case 'image':
        return ["Uploading image...", "Analyzing image...", "Generating description...", "Almost done..."];
      case 'document':
        return ["Uploading document...", "Extracting text...", "Processing content...", "Almost done..."];
      case 'collection':
        return ["Processing collection...", "Analyzing items...", "Organizing content...", "Almost done..."];
      case 'link':
        return ["Fetching page...", "Extracting metadata...", "Almost done..."];
      default:
        return baseMessages;
    }
  };

  const messages = getProcessingMessages(type, fileSize);

  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentMessage((prev) => (prev + 1) % messages.length);
    }, 2000);

    return () => clearInterval(interval);
  }, [messages.length]);

  useEffect(() => {
    // Flash effect when first appearing
    const timer = setTimeout(() => setFlashEffect(false), 500);
    return () => clearTimeout(timer);
  }, []);

  const formatFileSize = (bytes?: number) => {
    if (!bytes) return '';
    const mb = bytes / (1024 * 1024);
    return mb > 1 ? `${mb.toFixed(1)}MB` : `${(bytes / 1024).toFixed(0)}KB`;
  };

  return (
    <Card className={`group flex flex-col h-full bg-white border-2 transition-all duration-500 ${
      flashEffect ? 'border-primary/50 shadow-lg scale-[1.02]' : 'border-border/50'
    }`}>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between">
          <div className="flex-1 min-w-0 pr-2">
            <div className="flex items-center gap-2 mb-2">
              <div className="text-primary animate-pulse">
                {getTypeIcon(type)}
              </div>
              <div className="h-6 bg-white rounded animate-pulse px-2 py-1 text-sm font-medium text-foreground">
                {title}
              </div>
              {fileSize && (
                <span className="text-xs text-muted-foreground bg-muted/50 rounded px-2 py-1">
                  {formatFileSize(fileSize)}
                </span>
              )}
            </div>
          </div>
          <div className="h-8 w-8 bg-white rounded animate-pulse" />
        </div>
      </CardHeader>
      <CardContent className="flex flex-col flex-1">
        <div className="flex-1">
          <div className="w-full h-32 bg-white rounded-md mb-3 animate-pulse" />
          
          {/* Animated processing message */}
          <div className="mb-3">
            <div className="flex items-center gap-2 text-sm text-primary font-medium">
              <div className="h-2 w-2 bg-primary rounded-full animate-pulse" />
              <span className="animate-fade-in">
                {messages[currentMessage]}
              </span>
            </div>
            
            {/* Progress indicator for large files */}
            {showProgress && (
              <div className="mt-2">
                <Progress value={undefined} className="h-2 bg-muted/30" />
              </div>
            )}
          </div>
          
          <div className="space-y-2">
            <div className="h-4 bg-white rounded animate-pulse w-full" />
            <div className="h-4 bg-white rounded animate-pulse w-2/3" />
          </div>
          
          <div className="mt-3">
            <div className="flex flex-wrap gap-1">
              <div className="h-6 bg-white rounded-full animate-pulse w-16" />
              <div className="h-6 bg-white rounded-full animate-pulse w-20" />
            </div>
          </div>
        </div>
        
        <div className="flex items-center justify-between mt-auto pt-2">
          <div className="h-6 bg-white rounded-full animate-pulse w-20" />
          <div className="h-4 bg-white rounded animate-pulse w-20" />
        </div>
      </CardContent>
    </Card>
  );
};

export default ContentItemSkeleton;
