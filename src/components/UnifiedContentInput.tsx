
import React, { useState, useCallback, useRef, useEffect } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Upload, X } from 'lucide-react';
import {
  EditorRoot,
  EditorContent,
  type JSONContent,
  type EditorInstance,
  handleCommandNavigation,
} from 'novel';
import { createEditorExtensions } from './editor/EditorExtensions';
import EditorCommandMenu from './editor/EditorCommandMenu';
import EditorBubbleMenu from './editor/EditorBubbleMenu';
import { useAuth } from '@/hooks/useAuth';
import { uploadImage } from '@/services/imageUploadService';
import { useToast } from '@/hooks/use-toast';
import LinkPreviewCard from './LinkPreviewCard';
import FilePreviewCard from './FilePreviewCard';

interface LinkPreview {
  id: string;
  url: string;
  title?: string;
  description?: string;
  image?: string;
  siteName?: string;
}

interface FilePreview {
  id: string;
  file: File;
  preview?: string;
}

interface UnifiedContentInputProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (content: { title?: string; content?: string; description?: string }) => Promise<string[]>;
}

const UnifiedContentInput = ({ onAddContent, getSuggestedTags }: UnifiedContentInputProps) => {
  const [content, setContent] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [editorInstance, setEditorInstance] = useState<EditorInstance | null>(null);
  const [linkPreviews, setLinkPreviews] = useState<LinkPreview[]>([]);
  const [filePreviews, setFilePreviews] = useState<FilePreview[]>([]);
  const [isProcessingLinks, setIsProcessingLinks] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { user, session } = useAuth();
  const { toast } = useToast();

  const isValidUrl = (string: string) => {
    try {
      new URL(string);
      return true;
    } catch (_) {
      return false;
    }
  };

  const fetchLinkPreview = async (url: string): Promise<LinkPreview | null> => {
    try {
      const response = await fetch(url, { 
        mode: 'cors',
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; LinkPreview/1.0)'
        }
      });
      
      if (response.ok) {
        const html = await response.text();
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        
        const ogTitle = doc.querySelector('meta[property="og:title"]')?.getAttribute('content') ||
                       doc.querySelector('title')?.textContent;
        const ogDescription = doc.querySelector('meta[property="og:description"]')?.getAttribute('content') ||
                             doc.querySelector('meta[name="description"]')?.getAttribute('content');
        const ogImage = doc.querySelector('meta[property="og:image"]')?.getAttribute('content');
        const ogSiteName = doc.querySelector('meta[property="og:site_name"]')?.getAttribute('content');
        
        return {
          id: Date.now().toString(),
          url,
          title: ogTitle,
          description: ogDescription,
          image: ogImage,
          siteName: ogSiteName
        };
      }
    } catch (error) {
      console.log('Could not fetch preview data:', error);
    }
    
    return {
      id: Date.now().toString(),
      url,
      title: url
    };
  };

  const detectAndProcessLinks = useCallback(async (text: string) => {
    const urlRegex = /https?:\/\/[^\s]+/g;
    const urls = text.match(urlRegex) || [];
    const newUrls = urls.filter(url => !linkPreviews.some(preview => preview.url === url));
    
    if (newUrls.length > 0) {
      setIsProcessingLinks(true);
      const newPreviews: LinkPreview[] = [];
      
      for (const url of newUrls) {
        if (isValidUrl(url)) {
          const preview = await fetchLinkPreview(url);
          if (preview) {
            newPreviews.push(preview);
          }
        }
      }
      
      setLinkPreviews(prev => [...prev, ...newPreviews]);
      setIsProcessingLinks(false);
    }
  }, [linkPreviews]);

  const handleImageUpload = async (file: File): Promise<string> => {
    if (!user || !session) {
      throw new Error('User not authenticated');
    }

    try {
      const result = await uploadImage({
        file,
        userId: user.id
      });
      
      return result.publicUrl;
    } catch (error) {
      console.error('UnifiedContentInput: Upload failed', error);
      throw error;
    }
  };

  const extensions = createEditorExtensions(handleImageUpload);

  const initialContent: JSONContent = {
    type: 'doc',
    content: [
      {
        type: 'paragraph',
        content: []
      }
    ]
  };

  const handleContentChange = useCallback((newContent: string) => {
    setContent(newContent);
    
    // Extract plain text for link detection
    if (editorInstance) {
      const plainText = editorInstance.getText();
      detectAndProcessLinks(plainText);
    }
  }, [editorInstance, detectAndProcessLinks]);

  const handleFileSelect = (selectedFiles: FileList | null) => {
    if (!selectedFiles) return;
    
    const newFiles = Array.from(selectedFiles);
    const validFiles = newFiles.filter(file => {
      const validTypes = [
        'image/', 'video/', 'audio/',
        'application/pdf', 'text/', 'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      ];
      return validTypes.some(type => file.type.startsWith(type));
    });

    if (validFiles.length !== newFiles.length) {
      toast({
        title: "Some files were skipped",
        description: "Only images, videos, audio files, and documents are supported.",
        variant: "destructive",
      });
    }

    const newFilePreviews = validFiles.map(file => ({
      id: Date.now().toString() + Math.random(),
      file,
      preview: file.type.startsWith('image/') ? URL.createObjectURL(file) : undefined
    }));

    setFilePreviews(prev => [...prev, ...newFilePreviews]);
  };

  const removeLinkPreview = (id: string) => {
    setLinkPreviews(prev => prev.filter(p => p.id !== id));
  };

  const removeFilePreview = (id: string) => {
    setFilePreviews(prev => {
      const toRemove = prev.find(p => p.id === id);
      if (toRemove?.preview) {
        URL.revokeObjectURL(toRemove.preview);
      }
      return prev.filter(p => p.id !== id);
    });
  };

  const clearAll = () => {
    if (editorInstance) {
      editorInstance.commands.setContent(initialContent);
    }
    setContent('');
    setLinkPreviews([]);
    filePreviews.forEach(fp => {
      if (fp.preview) URL.revokeObjectURL(fp.preview);
    });
    setFilePreviews([]);
  };

  const handleSubmit = async () => {
    const hasContent = content.trim().length > 0;
    const hasLinks = linkPreviews.length > 0;
    const hasFiles = filePreviews.length > 0;

    if (!hasContent && !hasLinks && !hasFiles) {
      toast({
        title: "No content",
        description: "Please add some content before saving.",
        variant: "destructive",
      });
      return;
    }

    setIsLoading(true);
    try {
      // Determine primary content type and handle accordingly
      if (hasFiles) {
        // If files are present, process each file
        for (const filePreview of filePreviews) {
          const fileType = filePreview.file.type.startsWith('image/') ? 'image' :
                          filePreview.file.type.startsWith('video/') ? 'video' :
                          filePreview.file.type.startsWith('audio/') ? 'audio' : 'document';

          await onAddContent(fileType, {
            file: filePreview.file,
            title: filePreview.file.name,
            content: hasContent ? content.trim() : '',
            description: '',
            tags: []
          });
        }
      } else if (hasLinks && !hasContent) {
        // If only links, save as link entries
        for (const linkPreview of linkPreviews) {
          await onAddContent('link', {
            url: linkPreview.url,
            title: linkPreview.title || linkPreview.url,
            description: linkPreview.description || '',
            content: '',
            tags: []
          });
        }
      } else {
        // Text content with possible links
        await onAddContent('text', {
          content: content.trim(),
          tags: []
        });
        
        // Also save any links separately if they exist
        for (const linkPreview of linkPreviews) {
          await onAddContent('link', {
            url: linkPreview.url,
            title: linkPreview.title || linkPreview.url,
            description: linkPreview.description || '',
            content: '',
            tags: []
          });
        }
      }

      clearAll();
      toast({
        title: "Success",
        description: "Content added successfully!",
      });
    } catch (error) {
      console.error('Error adding content:', error);
      toast({
        title: "Error",
        description: "Failed to add content. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const hasAnyContent = content.trim().length > 0 || linkPreviews.length > 0 || filePreviews.length > 0;

  return (
    <Card className="w-full">
      <CardContent className="p-6">
        <div className="space-y-4">
          {/* Main Editor Area */}
          <div className="border rounded-md">
            <EditorRoot>
              <EditorContent
                initialContent={initialContent}
                extensions={extensions}
                className="min-h-[200px] max-h-[60vh] overflow-y-auto w-full max-w-none"
                editorProps={{
                  handleDOMEvents: {
                    keydown: (_view, event) => handleCommandNavigation(event),
                    drop: (view, event) => {
                      event.preventDefault();
                      const files = event.dataTransfer?.files;
                      if (files) {
                        handleFileSelect(files);
                      }
                      return false;
                    },
                    dragover: (view, event) => {
                      event.preventDefault();
                      return false;
                    }
                  },
                  attributes: {
                    class: 'prose prose-sm dark:prose-invert prose-headings:font-bold font-default focus:outline-none max-w-full p-4 prose-h1:text-2xl prose-h1:font-bold prose-h2:text-xl prose-h2:font-bold prose-h3:text-lg prose-h3:font-bold prose-h4:text-base prose-h4:font-bold prose-h5:text-sm prose-h5:font-bold prose-h6:text-xs prose-h6:font-bold prose-p:leading-normal prose-p:mb-2 prose-ul:leading-normal prose-ol:leading-normal prose-li:leading-normal prose-li:mb-1',
                    'data-placeholder': 'Start typing, paste links, or drag files here...'
                  }
                }}
                onUpdate={({ editor }: { editor: EditorInstance }) => {
                  setEditorInstance(editor);
                  const json = editor.getJSON();
                  handleContentChange(JSON.stringify(json));
                }}
              >
                <EditorCommandMenu />
                <EditorBubbleMenu />
              </EditorContent>
            </EditorRoot>
          </div>

          {/* Link Previews */}
          {linkPreviews.length > 0 && (
            <div className="space-y-2">
              <div className="text-sm font-medium text-muted-foreground">
                Detected Links {isProcessingLinks && "(processing...)"}
              </div>
              <div className="grid gap-2">
                {linkPreviews.map((preview) => (
                  <LinkPreviewCard
                    key={preview.id}
                    preview={preview}
                    onRemove={() => removeLinkPreview(preview.id)}
                  />
                ))}
              </div>
            </div>
          )}

          {/* File Previews */}
          {filePreviews.length > 0 && (
            <div className="space-y-2">
              <div className="text-sm font-medium text-muted-foreground">Files to Upload</div>
              <div className="grid gap-2">
                {filePreviews.map((preview) => (
                  <FilePreviewCard
                    key={preview.id}
                    preview={preview}
                    onRemove={() => removeFilePreview(preview.id)}
                  />
                ))}
              </div>
            </div>
          )}

          {/* Upload Button */}
          <div className="flex items-center justify-between pt-2 border-t">
            <div className="flex items-center gap-2">
              <input
                ref={fileInputRef}
                type="file"
                multiple
                accept="image/*,video/*,audio/*,.pdf,.doc,.docx,.txt"
                onChange={(e) => handleFileSelect(e.target.files)}
                className="hidden"
              />
              <Button
                variant="outline"
                size="sm"
                onClick={() => fileInputRef.current?.click()}
                className="flex items-center gap-2"
              >
                <Upload className="h-4 w-4" />
                Upload Files
              </Button>
              
              {hasAnyContent && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={clearAll}
                  className="text-muted-foreground"
                >
                  Clear All
                </Button>
              )}
            </div>

            {hasAnyContent && (
              <Button 
                onClick={handleSubmit} 
                disabled={isLoading}
                className="min-w-24"
              >
                {isLoading ? 'Adding...' : 'Add Content'}
              </Button>
            )}
          </div>

          <div className="text-xs text-muted-foreground">
            Paste links to see previews • Drag files to upload • Use / for formatting
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default UnifiedContentInput;
