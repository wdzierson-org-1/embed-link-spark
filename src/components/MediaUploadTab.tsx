
import React, { useState, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Upload, File, X, Image, Video, Mic, FileText } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';
import { uploadImage } from '@/services/imageUploadService';
import { generateDescription } from '@/utils/aiOperations';
import { MAX_FILE_SIZE_MB, MAX_VIDEO_SIZE_MB, MAX_AUDIO_SIZE_MB } from '@/services/imageUpload/MediaUploadTypes';

interface MediaUploadTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (content: { title?: string; content?: string; description?: string }) => Promise<string[]>;
}

const MediaUploadTab = ({ onAddContent, getSuggestedTags }: MediaUploadTabProps) => {
  const [files, setFiles] = useState<File[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [isDragOver, setIsDragOver] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { toast } = useToast();
  const { user } = useAuth();

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

  const handleFileSelect = (selectedFiles: FileList | null) => {
    if (!selectedFiles) return;
    
    const newFiles = Array.from(selectedFiles);
    const validFiles: File[] = [];
    const errors: string[] = [];
    
    newFiles.forEach(file => {
      // Check file type
      const validTypes = [
        'image/', 'video/', 'audio/',
        'application/pdf', 'text/', 'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      ];
      const isValidType = validTypes.some(type => file.type.startsWith(type));
      
      if (!isValidType) {
        errors.push(`"${file.name}" is not a supported file type.`);
        return;
      }
      
      // Check file size
      const sizeValidation = validateFileSize(file);
      if (!sizeValidation.valid) {
        errors.push(sizeValidation.error!);
        return;
      }
      
      validFiles.push(file);
    });

    if (errors.length > 0) {
      toast({
        title: "Some files were skipped",
        description: errors[0], // Show first error
        variant: "destructive",
      });
    }

    setFiles(prev => [...prev, ...validFiles]);
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(true);
  };

  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
    
    const droppedFiles = e.dataTransfer.files;
    handleFileSelect(droppedFiles);
  };

  const removeFile = (index: number) => {
    setFiles(prev => prev.filter((_, i) => i !== index));
  };

  const getFileIcon = (file: File) => {
    if (file.type.startsWith('image/')) return <Image className="w-4 h-4" />;
    if (file.type.startsWith('video/')) return <Video className="w-4 h-4" />;
    if (file.type.startsWith('audio/')) return <Mic className="w-4 h-4" />;
    return <FileText className="w-4 h-4" />;
  };

  const handleUpload = async () => {
    if (files.length === 0) {
      toast({
        title: "No files selected",
        description: "Please select at least one file to upload.",
        variant: "destructive",
      });
      return;
    }

    if (!user) {
      toast({
        title: "Authentication required",
        description: "Please log in to upload files.",
        variant: "destructive",
      });
      return;
    }

    setIsUploading(true);
    try {
      // Process files and show skeletons immediately
      for (const file of files) {
        // Classify file type correctly to match database enum
        const fileType = file.type.startsWith('image/') ? 'image' :
                        file.type.startsWith('video/') ? 'video' :
                        file.type.startsWith('audio/') ? 'audio' : 'document';

        console.log('MediaUploadTab: Starting upload for file:', file.name);

        // First, add skeleton item
        await onAddContent(fileType, {
          file,
          title: file.name,
          description: 'Processing...',
          tags: [],
          isOptimistic: true,
          showSkeleton: true
        });

        // Then process the actual file in the background
        setTimeout(async () => {
          try {
            if (fileType === 'image') {
              // For images, use the centralized upload service and generate AI description
              const result = await uploadImage({
                file,
                userId: user.id
              });
              
              console.log('MediaUploadTab: Image uploaded successfully, generating AI description');
              
              // Wait a moment to ensure the file is accessible
              await new Promise(resolve => setTimeout(resolve, 1000));
              
              // Generate AI description for the uploaded image
              const aiDescription = await generateDescription('image', {
                fileData: result.publicUrl,
                content: file.name
              });
              
              console.log('MediaUploadTab: AI description generated:', aiDescription);
              
              // Now add the actual content
              await onAddContent(fileType, {
                file,
                title: file.name,
                description: aiDescription || '',
                tags: [],
                uploadedFilePath: result.filePath,
                uploadedUrl: result.publicUrl,
                isOptimistic: false
              });
            } else {
              // For non-image files, process normally
              await onAddContent(fileType, {
                file,
                title: file.name,
                description: '',
                tags: [],
                isOptimistic: false
              });
            }
          } catch (error) {
            console.error('MediaUploadTab: Error processing file:', error);
            toast({
              title: "Upload failed",
              description: `Failed to process ${file.name}. Please try again.`,
              variant: "destructive",
            });
          }
        }, 100); // Small delay to ensure skeleton is shown first
      }

      // Reset form
      setFiles([]);
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }

      toast({
        title: "Upload started",
        description: `Processing ${files.length} file(s)...`,
      });
    } catch (error) {
      console.error('MediaUploadTab: Error starting upload:', error);
      toast({
        title: "Upload failed",
        description: "There was an error starting the upload. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsUploading(false);
    }
  };

  const hasFiles = files.length > 0;

  return (
    <Card className="bg-gray-50 border-0">
      <CardContent className="pt-6">
        <div className="space-y-4">
          <div>
            <input
              ref={fileInputRef}
              type="file"
              multiple
              accept="image/*,video/*,audio/*,.pdf,.doc,.docx,.txt"
              onChange={(e) => handleFileSelect(e.target.files)}
              className="hidden"
              id="file-upload"
            />
            <label
              htmlFor="file-upload"
              className={`flex flex-col items-center justify-center w-full h-40 border-0 rounded-lg cursor-pointer transition-colors bg-white ${
                isDragOver 
                  ? 'bg-blue-50' 
                  : 'hover:bg-gray-50'
              }`}
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
              onDrop={handleDrop}
            >
              <div className="flex flex-col items-center justify-center pt-5 pb-6">
                <Upload className="w-8 h-8 mb-4 text-gray-500" />
                <p className="mb-2 text-sm text-gray-500">
                  <span className="font-semibold">Click to upload</span> or drag and drop
                </p>
                <div className="flex items-center justify-center flex-wrap gap-x-4 gap-y-2 text-xs text-gray-500 px-4">
                  <div className="flex items-center space-x-1">
                    <Image className="w-3 h-3" />
                    <span>Images</span>
                  </div>
                  <div className="flex items-center space-x-1">
                    <Video className="w-3 h-3" />
                    <span>Videos</span>
                  </div>
                  <div className="flex items-center space-x-1">
                    <Mic className="w-3 h-3" />
                    <span>Audio</span>
                  </div>
                  <div className="flex items-center space-x-1">
                    <FileText className="w-3 h-3" />
                    <span>Documents</span>
                  </div>
                </div>
              </div>
            </label>
          </div>

          {files.length > 0 && (
            <div className="space-y-2">
              <p className="text-sm font-medium">Selected files:</p>
              {files.map((file, index) => {
                const fileSizeMB = (file.size / 1024 / 1024).toFixed(1);
                return (
                  <div key={index} className="flex items-center justify-between p-2 bg-white rounded border-0">
                    <div className="flex items-center space-x-2 flex-1 min-w-0">
                      {getFileIcon(file)}
                      <div className="flex flex-col min-w-0 flex-1">
                        <span className="text-sm truncate">{file.name}</span>
                        <span className="text-xs text-gray-500">{fileSizeMB}MB</span>
                      </div>
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => removeFile(index)}
                      className="h-8 w-8 p-0 shrink-0"
                    >
                      <X className="w-4 h-4" />
                    </Button>
                  </div>
                );
              })}
            </div>
          )}

          {hasFiles && (
            <Button 
              onClick={handleUpload} 
              disabled={isUploading}
              className="w-full"
            >
              {isUploading ? 'Starting Upload...' : 'Upload Files'}
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
};

export default MediaUploadTab;
