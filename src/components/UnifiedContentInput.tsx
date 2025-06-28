
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

  const extractImagesFromContent = () => {
    if (!editorInstance) return [];
    
    const json = editorInstance.getJSON();
    const images: string[] = [];
    
    const extractImages = (node: any) => {
      if (node.type === 'image' && node.attrs?.src) {
        images.push(node.attrs.src);
      }
      if (node.content) {
        node.content.forEach(extractImages);
      }
    };
    
    if (json.content) {
      json.content.forEach(extractImages);
    }
    
    return images;
  };

  const handleSubmit = async () => {
    const hasContent = content.trim().length > 0;
    const hasLinks = linkPreviews.length > 0;
    const hasFiles = filePreviews.length > 0;
    const editorImages = extractImagesFromContent();
    const hasEditorImages = editorImages.length > 0;

    if (!hasContent && !hasLinks && !hasFiles && !hasEditorImages) {
      toast({
        title: "No content",
        description: "Please add some content before saving.",
        variant: "destructive",
      });
      return;
    }

    setIsLoading(true);
    try {
      // Get plain text content from editor
      const plainTextContent = editorInstance?.getText() || '';
      
      // Combine all content for AI analysis
      const combinedContent = {
        content: plainTextContent,
        links: linkPreviews.map(link => ({ url: link.url, title: link.title, description: link.description })),
        fileNames: filePreviews.map(file => file.file.name),
        images: editorImages
      };

      // Determine primary image: first from editor, then from file uploads, then from link previews
      let primaryImage = editorImages[0] || 
                        (filePreviews.find(f => f.preview)?.preview) || 
                        linkPreviews.find(l => l.image)?.image;

      // Create a single unified note with all content
      await onAddContent('text', {
        content: content.trim(),
        title: plainTextContent.slice(0, 100) + (plainTextContent.length > 100 ? '...' : ''),
        description: '',
        tags: [],
        primaryImage,
        links: linkPreviews,
        files: filePreviews,
        combinedContent
      });

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

  const hasAnyContent = content.trim().length > 0 || linkPreviews.length > 0 || filePreviews.length > 0 || extractImagesFromContent().length > 0;

  return (
    <div className="w-full">
      <div className="bg-gray-50 rounded-lg p-4 border-0">
        <div className="space-y-3">
          {/* Main Editor Area with gray background */}
          <div className="bg-gray-100 rounded-md border-0">
            <EditorRoot>
              <EditorContent
                initialContent={initialContent}
                extensions={extensions}
                className="min-h-[150px] max-h-[60vh] overflow-y-auto w-full max-w-none"
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

          {/* Inline Link Previews - smaller and side by side */}
          {linkPreviews.length > 0 && (
            <div className="px-2">
              <div className="flex flex-wrap gap-2">
                {linkPreviews.map((preview) => (
                  <div key={preview.id} className="flex-none w-80">
                    <LinkPreviewCard
                      preview={preview}
                      onRemove={() => removeLinkPreview(preview.id)}
                    />
                  </div>
                ))}
              </div>
              {isProcessingLinks && (
                <div className="text-xs text-muted-foreground mt-1 px-2">
                  Processing links...
                </div>
              )}
            </div>
          )}

          {/* File Previews - also smaller and inline */}
          {filePreviews.length > 0 && (
            <div className="px-2">
              <div className="flex flex-wrap gap-2">
                {filePreviews.map((preview) => (
                  <div key={preview.id} className="flex-none w-80">
                    <FilePreviewCard
                      preview={preview}
                      onRemove={() => removeFilePreview(preview.id)}
                    />
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Bottom Controls */}
          <div className="flex items-center justify-between pt-2">
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
                variant="ghost"
                size="sm"
                onClick={() => fileInputRef.current?.click()}
                className="flex items-center gap-2 text-muted-foreground hover:text-foreground"
              >
                <Upload className="h-4 w-4" />
                Upload
              </Button>
              
              {hasAnyContent && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={clearAll}
                  className="text-muted-foreground hover:text-foreground"
                >
                  Clear
                </Button>
              )}
            </div>

            {hasAnyContent && (
              <Button 
                onClick={handleSubmit} 
                disabled={isLoading}
                className="min-w-24"
              >
                {isLoading ? 'Adding...' : 'Add Note'}
              </Button>
            )}
          </div>
        </div>
      </div>
      
      <div className="text-xs text-muted-foreground mt-2 text-center">
        Paste links for previews • Drag files to upload • Use / for formatting
      </div>
    </div>
  );
};

export default UnifiedContentInput;
