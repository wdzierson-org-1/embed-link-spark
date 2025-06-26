
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { X, Upload } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';

interface EditItemImageSectionProps {
  itemId: string;
  hasImage: boolean;
  imageUrl: string;
  onImageStateChange: (hasImage: boolean, imageUrl: string) => void;
}

const EditItemImageSection = ({ itemId, hasImage, imageUrl, onImageStateChange }: EditItemImageSectionProps) => {
  const { toast } = useToast();

  const handleRemoveImage = async () => {
    try {
      // Get current item to find file_path
      const { data: itemData, error: itemError } = await supabase
        .from('items')
        .select('file_path')
        .eq('id', itemId)
        .single();

      if (itemError || !itemData?.file_path) throw itemError;

      // Delete from storage
      const { error: storageError } = await supabase.storage
        .from('stash-media')
        .remove([itemData.file_path]);
      
      if (storageError) throw storageError;

      // Update item to remove file_path and change type
      const { error: updateError } = await supabase
        .from('items')
        .update({ 
          file_path: null,
          type: 'text'
        })
        .eq('id', itemId);
      
      if (updateError) throw updateError;

      onImageStateChange(false, '');
      
      toast({
        title: "Success",
        description: "Image removed",
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

  const handleImageUpload = async (file: File) => {
    try {
      const fileExt = file.name.split('.').pop();
      const fileName = `${itemId}.${fileExt}`;
      
      const { error: uploadError } = await supabase.storage
        .from('stash-media')
        .upload(fileName, file, { upsert: true });
      
      if (uploadError) throw uploadError;

      // Update item with new file path and type
      const { error: updateError } = await supabase
        .from('items')
        .update({ 
          file_path: fileName,
          type: 'image'
        })
        .eq('id', itemId);
      
      if (updateError) throw updateError;

      // Update local state
      const { data } = supabase.storage.from('stash-media').getPublicUrl(fileName);
      onImageStateChange(true, data.publicUrl);
      
      toast({
        title: "Success",
        description: "Image uploaded",
      });
    } catch (error) {
      console.error('Error uploading image:', error);
      toast({
        title: "Error",
        description: "Failed to upload image",
        variant: "destructive",
      });
    }
  };

  if (hasImage) {
    return (
      <Card>
        <CardContent className="p-4">
          <div className="relative">
            <img
              src={imageUrl}
              alt="Note image"
              className="w-full h-48 object-cover rounded"
            />
            <Button
              variant="destructive"
              size="sm"
              className="absolute top-2 right-2"
              onClick={handleRemoveImage}
            >
              <X className="h-4 w-4" />
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-dashed">
      <CardContent className="p-4">
        <div className="text-center">
          <input
            type="file"
            accept="image/*"
            className="hidden"
            id="image-upload"
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) handleImageUpload(file);
            }}
          />
          <label
            htmlFor="image-upload"
            className="cursor-pointer flex flex-col items-center space-y-2 text-muted-foreground hover:text-foreground transition-colors"
          >
            <Upload className="h-8 w-8" />
            <span>Click to add an image</span>
          </label>
        </div>
      </CardContent>
    </Card>
  );
};

export default EditItemImageSection;
