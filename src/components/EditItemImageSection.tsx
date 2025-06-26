import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Upload, Trash2, Image as ImageIcon } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';

interface EditItemImageSectionProps {
  itemId: string;
  hasImage: boolean;
  imageUrl: string;
  onImageStateChange: (hasImage: boolean, imageUrl: string) => void;
  asLink?: boolean;
}

const EditItemImageSection = ({ 
  itemId, 
  hasImage, 
  imageUrl, 
  onImageStateChange, 
  asLink = false 
}: EditItemImageSectionProps) => {
  const [isUploading, setIsUploading] = useState(false);
  const { toast } = useToast();

  const handleImageUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith('image/')) {
      toast({
        title: "Error",
        description: "Please select an image file",
        variant: "destructive",
      });
      return;
    }

    setIsUploading(true);
    try {
      // Upload to Supabase storage
      const fileExt = file.name.split('.').pop();
      const fileName = `${itemId}-${Date.now()}.${fileExt}`;
      
      const { error: uploadError } = await supabase.storage
        .from('stash-media')
        .upload(fileName, file);

      if (uploadError) {
        throw uploadError;
      }

      // Update item with image path
      const { error: updateError } = await supabase
        .from('items')
        .update({ 
          file_path: fileName,
          type: 'image',
          mime_type: file.type
        })
        .eq('id', itemId);

      if (updateError) {
        throw updateError;
      }

      // Get public URL
      const { data } = supabase.storage.from('stash-media').getPublicUrl(fileName);
      
      onImageStateChange(true, data.publicUrl);
      toast({
        title: "Success",
        description: "Image uploaded successfully",
      });
    } catch (error) {
      console.error('Error uploading image:', error);
      toast({
        title: "Error",
        description: "Failed to upload image",
        variant: "destructive",
      });
    } finally {
      setIsUploading(false);
    }
  };

  const handleImageRemove = async () => {
    try {
      // Update item to remove image
      const { error } = await supabase
        .from('items')
        .update({ 
          file_path: null,
          type: 'text',
          mime_type: null
        })
        .eq('id', itemId);

      if (error) {
        throw error;
      }

      onImageStateChange(false, '');
      toast({
        title: "Success",
        description: "Image removed successfully",
      });
    } catch (error) {
      console.error('Error removing image:', error);
      toast({
        title: "Error",
        description: "Failed to remove image",
        variant: "destructive",
      });
    }
  };

  if (asLink) {
    return (
      <div className="flex items-center gap-2 text-sm">
        {hasImage ? (
          <>
            <Button
              variant="ghost"
              size="sm"
              onClick={handleImageRemove}
              className="text-red-600 hover:text-red-800 p-0 h-auto"
            >
              Remove image
            </Button>
          </>
        ) : (
          <>
            <input
              type="file"
              accept="image/*"
              onChange={handleImageUpload}
              disabled={isUploading}
              className="hidden"
              id={`image-upload-${itemId}`}
            />
            <label htmlFor={`image-upload-${itemId}`}>
              <Button
                variant="ghost"
                size="sm"
                asChild
                disabled={isUploading}
                className="text-blue-600 hover:text-blue-800 p-0 h-auto cursor-pointer"
              >
                <span className="flex items-center gap-1">
                  <ImageIcon className="h-3 w-3" />
                  {isUploading ? 'Uploading...' : 'Add image'}
                </span>
              </Button>
            </label>
          </>
        )}
      </div>
    );
  }

  return (
    <div>
      <Label className="text-base font-medium mb-3 block">Image</Label>
      {hasImage ? (
        <div className="space-y-3">
          <div className="relative">
            <img
              src={imageUrl}
              alt="Item image"
              className="w-full max-w-md rounded-lg border"
            />
          </div>
          <Button
            variant="outline"
            onClick={handleImageRemove}
            className="text-red-600 hover:text-red-700"
          >
            <Trash2 className="h-4 w-4 mr-2" />
            Remove Image
          </Button>
        </div>
      ) : (
        <div className="border-2 border-dashed border-muted-foreground/25 rounded-lg p-6">
          <div className="text-center">
            <Upload className="mx-auto h-8 w-8 text-muted-foreground mb-2" />
            <p className="text-sm text-muted-foreground mb-3">
              Click to upload an image
            </p>
            <input
              type="file"
              accept="image/*"
              onChange={handleImageUpload}
              disabled={isUploading}
              className="hidden"
              id={`image-upload-${itemId}`}
            />
            <label htmlFor={`image-upload-${itemId}`}>
              <Button variant="outline" asChild disabled={isUploading}>
                <span className="cursor-pointer">
                  {isUploading ? 'Uploading...' : 'Choose File'}
                </span>
              </Button>
            </label>
          </div>
        </div>
      )}
    </div>
  );
};

export default EditItemImageSection;
