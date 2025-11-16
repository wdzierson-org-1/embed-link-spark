import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Plus, ChevronUp, ChevronDown, Send } from 'lucide-react';
import InputChip from '@/components/InputChip';
import { useToast } from '@/hooks/use-toast';
import { useSubscription } from '@/hooks/useSubscription';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { MAX_FILE_SIZE_MB, MAX_VIDEO_SIZE_MB, MAX_AUDIO_SIZE_MB } from '@/services/imageUpload/MediaUploadTypes';

interface UnifiedInputPanelProps {
  isInputUICollapsed: boolean;
  onToggleInputUI: () => void;
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (content: any) => Promise<string[]>;
}

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  previewImagePath?: string; // Supabase storage path for database storage
  previewImageUrl?: string; // Public URL for display purposes
  url: string; // Required to match LinkPreview interface
  siteName?: string;
  videoUrl?: string;
}

interface InputItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
  content: any;
  ogData?: OpenGraphData;
}

const UnifiedInputPanel = ({ 
  isInputUICollapsed, 
  onToggleInputUI, 
  onAddContent, 
  getSuggestedTags 
}: UnifiedInputPanelProps) => {
  const [inputText, setInputText] = useState('');
  const [inputItems, setInputItems] = useState<InputItem[]>([]);
  const [isDragOver, setIsDragOver] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { toast } = useToast();
  const { user } = useAuth();
  const { canAddContent } = useSubscription();

  const generateId = () => Math.random().toString(36).substr(2, 9);

  const validateFileSize = (file: File): { valid: boolean; error?: string } => {
    const fileSizeMB = file.size / 1024 / 1024;
    
    if (file.type.startsWith('video/')) {
      if (fileSizeMB > MAX_VIDEO_SIZE_MB) {
        return {
          valid: false,
          error: `"${file.name}" is ${fileSizeMB.toFixed(1)}MB. Stash only accepts videos less than ${MAX_VIDEO_SIZE_MB}MB. Perhaps you can compress the video further?`
        };
      }
    } else if (file.type.startsWith('audio/')) {
      if (fileSizeMB > MAX_AUDIO_SIZE_MB) {
        return {
          valid: false,
          error: `"${file.name}" is ${fileSizeMB.toFixed(1)}MB. Maximum audio size is ${MAX_AUDIO_SIZE_MB}MB. Please choose a smaller file.`
        };
      }
    } else if (file.type.startsWith('image/') || file.type === 'application/pdf' || file.type.startsWith('text/') || file.type.startsWith('application/')) {
      if (fileSizeMB > MAX_FILE_SIZE_MB) {
        return {
          valid: false,
          error: `"${file.name}" is ${fileSizeMB.toFixed(1)}MB. Maximum file size is ${MAX_FILE_SIZE_MB}MB. Please choose a smaller file.`
        };
      }
    }
    
    return { valid: true };
  };

  const fetchOgData = async (url: string): Promise<OpenGraphData | null> => {
    try {
      console.log('fetchOgData called with URL:', url);
      console.log('User ID:', user?.id);
      console.log('Calling extract-link-metadata edge function...');
      
      const { data, error } = await supabase.functions.invoke('extract-link-metadata', {
        body: { url, userId: user?.id }
      });
      
      console.log('Edge function response:', { data, error });
      
      if (error) {
        console.error('Error fetching metadata:', error);
        return null;
      }
      
      if (data && data.success) {
        console.log('✓ Successfully fetched metadata:', {
          title: !!data.title,
          description: !!data.description, 
          image: data.image,
          previewImagePath: data.previewImagePath,
          previewImageUrl: data.previewImagePublicUrl
        });
        
        const ogDataResult: OpenGraphData = {
          title: data.title,
          description: data.description,
          image: data.image,
          previewImagePath: data.previewImagePath,
          previewImageUrl: data.previewImagePublicUrl,
          url: url,
          siteName: data.siteName,
          videoUrl: data.videoUrl
        };

        console.log('fetchOgData result:', ogDataResult);
        return ogDataResult;
      }
      
      console.log('Edge function returned unsuccessful result:', data);
      return data;
    } catch (error) {
      console.error('Error:', error);
      return null;
    }
  };

  const detectUrl = (text: string) => {
    const urlRegex = /(https?:\/\/[^\s]+)/g;
    return text.match(urlRegex);
  };

  const handleInputChange = async (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const value = e.target.value;
    setInputText(value);

    // Auto-detect URLs and add as link chips
    const urls = detectUrl(value);
    const currentUrls = inputItems.filter(item => item.type === 'link').map(item => item.content.url);
    
    if (urls) {
      for (const url of urls) {
        const existingLink = inputItems.find(item => 
          item.type === 'link' && item.content.url === url
        );
        if (!existingLink) {
          const newItem: InputItem = {
            id: generateId(),
            type: 'link',
            content: { url, title: url }
          };
          
          setInputItems(prev => [...prev, newItem]);
          
          // Fetch OG data in background
          fetchOgData(url).then(ogData => {
            if (ogData) {
              setInputItems(prev => prev.map(item => 
                item.id === newItem.id ? { ...item, ogData } : item
              ));
            }
          });
        }
      }
    }
    
    // Remove link items if URL was deleted/modified
    setInputItems(prev => prev.filter(item => 
      item.type !== 'link' || (urls && urls.includes(item.content.url))
    ));
  };

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);

    const files = Array.from(e.dataTransfer.files);
    files.forEach(file => {
      // Validate file size
      const validation = validateFileSize(file);
      if (!validation.valid) {
        toast({
          title: "File too large",
          description: validation.error,
          variant: "destructive",
        });
        return;
      }

      // Classify file type correctly
      let fileType: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
      if (file.type.startsWith('image/')) {
        fileType = 'image';
      } else if (file.type.startsWith('video/')) {
        fileType = 'video';
      } else if (file.type.startsWith('audio/')) {
        fileType = 'audio';
      } else {
        // PDFs, Word docs, text files, etc. are 'document'
        fileType = 'document';
      }
      
      setInputItems(prev => [...prev, {
        id: generateId(),
        type: fileType,
        content: {
          file,
          name: file.name,
          size: file.size,
          type: file.type
        }
      }]);
    });
  }, [toast]);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    files.forEach(file => {
      // Validate file size
      const validation = validateFileSize(file);
      if (!validation.valid) {
        toast({
          title: "File too large",
          description: validation.error,
          variant: "destructive",
        });
        return;
      }

      // Classify file type correctly
      let fileType: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
      if (file.type.startsWith('image/')) {
        fileType = 'image';
      } else if (file.type.startsWith('video/')) {
        fileType = 'video';
      } else if (file.type.startsWith('audio/')) {
        fileType = 'audio';
      } else {
        // PDFs, Word docs, text files, etc. are 'document'
        fileType = 'document';
      }
      
      setInputItems(prev => [...prev, {
        id: generateId(),
        type: fileType,
        content: {
          file,
          name: file.name,
          size: file.size,
          type: file.type
        }
      }]);
    });
  };

  const removeInputItem = (id: string) => {
    setInputItems(prev => prev.filter(item => item.id !== id));
  };

  const handleSubmit = async () => {
    if (!inputText.trim() && inputItems.length === 0) return;
    
    if (!canAddContent) {
      toast({
        title: "Feature Restricted",
        description: "Please subscribe to add new content.",
        variant: "destructive",
      });
      return;
    }
    
    setIsSubmitting(true);
    
    // Clear the form immediately for better UX
    const textToProcess = inputText;
    const itemsToProcess = [...inputItems];
    setInputText('');
    setInputItems([]);
    
    // Auto-collapse the input panel after submission to free up space
    if (!isInputUICollapsed) {
      onToggleInputUI();
    }

    try {
      const hasText = textToProcess.trim();
      const linkItems = itemsToProcess.filter(item => item.type === 'link');
      const mediaItems = itemsToProcess.filter(item => item.type !== 'link');

      // Case 1: Single link (with or without text) -> Individual link item
      if (linkItems.length === 1 && mediaItems.length === 0) {
        const linkItem = linkItems[0];
        console.log('Single link submission:', linkItem);
        await onAddContent('link', {
          url: linkItem.content.url,
          title: linkItem.ogData?.title || linkItem.content.title || linkItem.content.url,
          description: hasText || linkItem.ogData?.description,
          previewImagePath: linkItem.ogData?.previewImagePath,
          ogData: {
            ...linkItem.ogData,
            // Ensure we have image fallback for contentProcessor
            image: linkItem.ogData?.previewImageUrl || linkItem.ogData?.image
          },
          type: 'link'
        });
      }
      // Case 2: Only a single media file, no text, no other items -> Individual media item
      else if (mediaItems.length === 1 && !hasText && linkItems.length === 0) {
        const mediaItem = mediaItems[0];
        await onAddContent(mediaItem.type, {
          file: mediaItem.content.file,
          title: mediaItem.content.name,
          type: mediaItem.type
        });
      }
      // Case 3: Only text, no attachments -> Text note
      else if (hasText && linkItems.length === 0 && mediaItems.length === 0) {
        await onAddContent('text', {
          content: hasText,
          type: 'text'
        });
      }
      // Case 4: Multiple links or mixed items -> Collection
      else {
        const attachments = [];
        
        // Add link attachments
        for (const linkItem of linkItems) {
          attachments.push({
            type: 'link',
            url: linkItem.content.url,
            title: linkItem.ogData?.title || linkItem.content.url,
            description: linkItem.ogData?.description,
            image: linkItem.ogData?.previewImageUrl || linkItem.ogData?.image,
            siteName: linkItem.ogData?.siteName
          });
        }
        
        // Add media attachments
        for (const mediaItem of mediaItems) {
          attachments.push({
            type: mediaItem.type,
            file: mediaItem.content.file,
            name: mediaItem.content.name,
            size: mediaItem.content.size,
            fileType: mediaItem.content.type
          });
        }

        await onAddContent('collection', {
          content: hasText || '',
          type: 'collection',
          attachments: attachments
        });
      }

    } catch (error) {
      // Restore the form data on error
      setInputText(textToProcess);
      setInputItems(itemsToProcess);
      
      // Re-expand input panel on error
      if (isInputUICollapsed) {
        onToggleInputUI();
      }
      console.error('Error adding content:', error);
      toast({
        title: "Error",
        description: "Failed to add content. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="w-full relative">
      {/* Extended animated gradient background */}
      <div className="absolute inset-0 h-[200vh] animated-gradient opacity-30" />
      <div className="absolute inset-0 h-[200vh] bg-gradient-to-b from-transparent via-background/50 via-background/30 to-background" />
      
      <div className="relative pt-5 pb-8">
        <div className="container mx-auto px-4">
          <div className="bg-white/90 backdrop-blur-sm rounded-xl shadow-lg">
            {/* Input area with minimize button */}
            <div className={`overflow-hidden transition-all duration-300 ease-in-out ${
              isInputUICollapsed ? 'max-h-0 opacity-0' : 'max-h-96 opacity-100'
            }`}>
              <div 
                className={`p-4 space-y-4 relative ${
                  isDragOver ? 'bg-primary/5 border-2 border-dashed border-primary' : ''
                }`}
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
              >
                {/* Minimize button in top right */}
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={onToggleInputUI}
                  className="absolute top-2 right-2 h-6 w-6 p-0"
                >
                  <ChevronUp className="h-4 w-4" />
                </Button>

                <Textarea
                  value={inputText}
                  onChange={handleInputChange}
                  placeholder="What's on your mind? Drop files, paste links, or just start typing..."
                  className="min-h-[100px] resize-none border-0 bg-transparent focus:ring-0 focus:border-0 focus-visible:ring-0 focus-visible:ring-offset-0 text-base pr-10"
                />
                
                {/* Input chips */}
                {inputItems.length > 0 && (
                  <div className="flex flex-wrap gap-2 pt-2 border-t border-border">
                    {inputItems.map(item => (
                      <InputChip
                        key={item.id}
                        type={item.type}
                        content={item.content}
                        onRemove={() => removeInputItem(item.id)}
                        ogData={item.ogData}
                      />
                    ))}
                  </div>
                )}
                
                {/* Bottom actions */}
                <div className="flex items-center justify-between pt-2">
                  <div className="flex items-center gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => fileInputRef.current?.click()}
                      className="gap-2"
                    >
                      <Plus className="h-4 w-4" />
                      Attach
                    </Button>
                    <input
                      ref={fileInputRef}
                      type="file"
                      multiple
                      className="hidden"
                      onChange={handleFileSelect}
                    />
                  </div>
                  
                  <Button 
                    onClick={handleSubmit}
                    disabled={(!inputText.trim() && inputItems.length === 0) || isSubmitting}
                    className="gap-2"
                  >
                    {isSubmitting ? (
                      <>
                        <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
                        Adding...
                      </>
                    ) : (
                      <>
                        <Send className="h-4 w-4" />
                        Add to Stash
                      </>
                    )}
                  </Button>
                </div>
              </div>
            </div>

            {/* Collapsed state - show expand button */}
            {isInputUICollapsed && (
              <div className="p-4 flex justify-center">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={onToggleInputUI}
                    className="flex items-center gap-1"
                  >
                    <Plus className="h-4 w-4" />
                    Add something
                  </Button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default UnifiedInputPanel;