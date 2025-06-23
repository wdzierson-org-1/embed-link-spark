
import React, { useState, useRef } from 'react';
import { useToast } from '@/hooks/use-toast';
import { Upload, Image, Mic, Video, FileText } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import TagInput from './TagInput';

interface MediaUploadTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: () => string[];
}

const MediaUploadTab = ({ onAddContent, getSuggestedTags }: MediaUploadTabProps) => {
  const [isDragging, setIsDragging] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [tags, setTags] = useState<string[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { toast } = useToast();

  const detectContentType = (file: File): string => {
    if (file.type.startsWith('image/')) return 'image';
    if (file.type.startsWith('audio/')) return 'audio';
    if (file.type.startsWith('video/')) return 'video';
    if (file.type === 'application/pdf') return 'document';
    return 'text';
  };

  const handleDrop = async (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    
    const files = Array.from(e.dataTransfer.files);
    if (files.length > 0) {
      await processFile(files[0]);
    }
  };

  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (files && files.length > 0) {
      await processFile(files[0]);
    }
  };

  const processFile = async (file: File) => {
    // Check file size (20MB limit)
    const maxSize = 20 * 1024 * 1024; // 20MB in bytes
    if (file.size > maxSize) {
      toast({
        title: "File too large",
        description: "Maximum file size is 20MB",
        variant: "destructive",
      });
      return;
    }

    setIsProcessing(true);
    try {
      const type = detectContentType(file);
      let fileData = null;

      // For images, convert to base64 for AI processing
      if (type === 'image') {
        fileData = await new Promise<string>((resolve) => {
          const reader = new FileReader();
          reader.onload = (e) => resolve(e.target?.result as string);
          reader.readAsDataURL(file);
        });
      }

      // Special handling for PDFs with placeholder content
      if (type === 'document') {
        await onAddContent(type, {
          title: file.name,
          file,
          tags,
          content: `📄 PDF Processing...

We're working on extracting the text and generating a summary of this document.

File: ${file.name}
Size: ${(file.size / 1024 / 1024).toFixed(2)}MB

The content will be automatically updated once text extraction is complete and embeddings are generated for search functionality.`,
          isProcessing: true
        });
      } else {
        await onAddContent(type, {
          title: file.name,
          file,
          fileData,
          tags,
          content: type === 'text' ? await file.text() : undefined
        });
      }

      // Reset form
      setTags([]);

      toast({
        title: "Success",
        description: type === 'document' 
          ? `PDF uploaded! Text extraction is in progress...`
          : `${type.charAt(0).toUpperCase() + type.slice(1)} uploaded and processed!`,
      });
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to process file",
        variant: "destructive",
      });
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Add Media Files</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div
          className={`border-2 border-dashed rounded-lg p-8 text-center transition-colors ${
            isDragging ? 'border-primary bg-primary/5' : 'border-muted-foreground/25'
          } ${isProcessing ? 'opacity-50 pointer-events-none' : ''}`}
          onDragOver={(e) => {
            e.preventDefault();
            setIsDragging(true);
          }}
          onDragLeave={() => setIsDragging(false)}
          onDrop={handleDrop}
        >
          <div className="space-y-4">
            <div className="flex justify-center">
              <Upload className="h-12 w-12 text-muted-foreground" />
            </div>
            
            <div>
              <h3 className="text-lg font-semibold mb-2">Upload Media Files</h3>
              <p className="text-sm text-muted-foreground mb-4">
                Drag and drop files here, or click to browse. AI will automatically describe your content.
              </p>
              <p className="text-xs text-muted-foreground mb-4">
                Maximum file size: 20MB
              </p>
            </div>

            <div className="flex flex-wrap justify-center gap-2 mb-4">
              <div className="flex items-center space-x-1 text-xs text-muted-foreground bg-muted px-2 py-1 rounded">
                <Image className="h-3 w-3" />
                <span>Images</span>
              </div>
              <div className="flex items-center space-x-1 text-xs text-muted-foreground bg-muted px-2 py-1 rounded">
                <Mic className="h-3 w-3" />
                <span>Audio</span>
              </div>
              <div className="flex items-center space-x-1 text-xs text-muted-foreground bg-muted px-2 py-1 rounded">
                <Video className="h-3 w-3" />
                <span>Video</span>
              </div>
              <div className="flex items-center space-x-1 text-xs text-muted-foreground bg-muted px-2 py-1 rounded">
                <FileText className="h-3 w-3" />
                <span>Documents & PDFs</span>
              </div>
            </div>

            <Button
              variant="outline"
              onClick={() => fileInputRef.current?.click()}
              disabled={isProcessing}
              className="mx-auto"
            >
              <Upload className="h-4 w-4 mr-2" />
              Choose Files
            </Button>
            
            <input
              ref={fileInputRef}
              type="file"
              className="hidden"
              onChange={handleFileSelect}
              accept="image/*,audio/*,video/*,.txt,.md,.pdf"
            />

            {isProcessing && (
              <div className="text-sm text-muted-foreground">
                Processing content and generating AI description...
              </div>
            )}
          </div>
        </div>

        <div>
          <label className="text-sm font-medium mb-2 block">Tags (optional)</label>
          <TagInput
            tags={tags}
            onTagsChange={setTags}
            suggestions={getSuggestedTags()}
            placeholder="Add tags to organize your content..."
          />
        </div>
      </CardContent>
    </Card>
  );
};

export default MediaUploadTab;
