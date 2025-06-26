import React, { useState, useEffect } from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { X, Upload, RefreshCw, Trash2, Edit } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import ItemTagsManager from '@/components/ItemTagsManager';
import { generateDescription } from '@/utils/aiOperations';
import {
  EditorRoot,
  EditorContent,
  EditorCommand,
  EditorCommandItem,
  EditorBubble,
  EditorBubbleItem,
  type JSONContent,
  type EditorInstance,
} from 'novel';

interface EditItemDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: {
    id: string;
    title?: string;
    description?: string;
    content?: string;
    file_path?: string;
    type?: string;
    tags?: string[];
  } | null;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }) => Promise<void>;
}

const EditItemDialog = ({ open, onOpenChange, item, onSave }: EditItemDialogProps) => {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [content, setContent] = useState('');
  const [editorContent, setEditorContent] = useState<JSONContent | null>(null);
  const [isEditingTitle, setIsEditingTitle] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [isRefreshingDescription, setIsRefreshingDescription] = useState(false);
  const [hasImage, setHasImage] = useState(false);
  const [imageUrl, setImageUrl] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const { toast } = useToast();

  // Convert HTML string to JSONContent for the editor
  const convertHtmlToJson = (htmlString: string): JSONContent => {
    if (!htmlString || htmlString.trim() === '') {
      return {
        type: 'doc',
        content: [
          {
            type: 'paragraph',
            content: []
          }
        ]
      };
    }
    
    // For now, we'll create a simple paragraph with the text content
    // In a more sophisticated implementation, you'd parse the HTML properly
    return {
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [
            {
              type: 'text',
              text: htmlString.replace(/<[^>]*>/g, '') // Strip HTML tags for now
            }
          ]
        }
      ]
    };
  };

  useEffect(() => {
    if (item) {
      setTitle(item.title || '');
      setDescription(item.description || '');
      setContent(item.content || '');
      setTags(item.tags || []);
      
      // Convert content to JSONContent for the editor
      setEditorContent(convertHtmlToJson(item.content || ''));
      
      // Check if item has an image
      if (item.file_path && item.type === 'image') {
        setHasImage(true);
        const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
        setImageUrl(data.publicUrl);
      } else {
        setHasImage(false);
        setImageUrl('');
      }
    }
  }, [item]);

  const handleSave = async () => {
    if (!item) return;
    
    setIsLoading(true);
    try {
      await onSave(item.id, {
        title: title.trim() || undefined,
        description: description.trim() || undefined,
        content: content.trim() || undefined,
      });
      onOpenChange(false);
    } catch (error) {
      console.error('Error saving item:', error);
      toast({
        title: "Error",
        description: "Failed to save changes",
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const handleTitleSave = async () => {
    if (!item) return;
    
    try {
      await onSave(item.id, {
        title: title.trim() || undefined,
      });
      setIsEditingTitle(false);
      toast({
        title: "Success",
        description: "Title updated",
      });
    } catch (error) {
      console.error('Error saving title:', error);
      toast({
        title: "Error",
        description: "Failed to update title",
        variant: "destructive",
      });
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleTitleSave();
    }
  };

  const handleRemoveImage = async () => {
    if (!item || !item.file_path) return;
    
    try {
      // Delete from storage
      const { error: storageError } = await supabase.storage
        .from('stash-media')
        .remove([item.file_path]);
      
      if (storageError) throw storageError;

      // Update item to remove file_path and change type
      const { error: updateError } = await supabase
        .from('items')
        .update({ 
          file_path: null,
          type: 'text'
        })
        .eq('id', item.id);
      
      if (updateError) throw updateError;

      setHasImage(false);
      setImageUrl('');
      
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
    if (!item) return;

    try {
      const fileExt = file.name.split('.').pop();
      const fileName = `${item.id}.${fileExt}`;
      
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
        .eq('id', item.id);
      
      if (updateError) throw updateError;

      // Update local state
      const { data } = supabase.storage.from('stash-media').getPublicUrl(fileName);
      setImageUrl(data.publicUrl);
      setHasImage(true);
      
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

  const handleRefreshDescription = async () => {
    if (!item) return;

    setIsRefreshingDescription(true);
    try {
      const newDescription = await generateDescription('text', {
        content: content,
        title: title
      });
      
      if (newDescription) {
        setDescription(newDescription);
        await onSave(item.id, { description: newDescription });
        toast({
          title: "Success",
          description: "Description refreshed",
        });
      }
    } catch (error) {
      console.error('Error refreshing description:', error);
      toast({
        title: "Error",
        description: "Failed to refresh description",
        variant: "destructive",
      });
    } finally {
      setIsRefreshingDescription(false);
    }
  };

  const handleRemoveDescription = async () => {
    if (!item) return;

    try {
      setDescription('');
      await onSave(item.id, { description: '' });
      toast({
        title: "Success",
        description: "Description removed",
      });
    } catch (error) {
      console.error('Error removing description:', error);
      toast({
        title: "Error",
        description: "Failed to remove description",
        variant: "destructive",
      });
    }
  };

  const handleTagsUpdated = () => {
    // This will be called when tags are updated
    // The ItemTagsManager handles the actual updates
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent 
        side="right" 
        className="w-full sm:max-w-2xl p-0 flex flex-col"
      >
        <SheetHeader className="flex-shrink-0 border-b p-6 pb-4">
          <SheetTitle>Edit Note</SheetTitle>
        </SheetHeader>
        
        <ScrollArea className="flex-1">
          <div className="p-6 space-y-6">
            {/* Title Section */}
            <div>
              {isEditingTitle ? (
                <Input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  onKeyPress={handleKeyPress}
                  onBlur={handleTitleSave}
                  className="text-2xl font-bold border-none p-0 shadow-none focus-visible:ring-0"
                  placeholder="Enter title..."
                  autoFocus
                />
              ) : (
                <h1 
                  className="text-2xl font-bold cursor-pointer hover:bg-yellow-50 p-2 rounded transition-colors"
                  onClick={() => setIsEditingTitle(true)}
                  title="Click to edit title"
                >
                  {title || 'Untitled Note'}
                  <Edit className="inline-block ml-2 h-4 w-4 opacity-50" />
                </h1>
              )}
            </div>

            {/* Image Section */}
            {hasImage ? (
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
            ) : (
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
            )}

            {/* Content Section */}
            <div>
              <Label className="text-base font-medium mb-3 block">Content</Label>
              <div className="border rounded-md">
                {editorContent && (
                  <EditorRoot>
                    <EditorContent
                      initialContent={editorContent}
                      onUpdate={({ editor }: { editor: EditorInstance }) => {
                        const html = editor.getHTML();
                        setContent(html);
                      }}
                      className="min-h-[300px] p-4"
                    >
                      <EditorCommand className="z-50 h-auto max-h-[330px] overflow-y-auto rounded-md border border-muted bg-background px-1 py-2 shadow-md transition-all">
                        <EditorCommandItem
                          value="paragraph"
                          onCommand={(val) => console.log(val)}
                        />
                      </EditorCommand>
                      <EditorBubble className="flex w-fit max-w-[90vw] overflow-hidden rounded-md border border-muted bg-background shadow-xl">
                        <EditorBubbleItem>Bold</EditorBubbleItem>
                        <EditorBubbleItem>Italic</EditorBubbleItem>
                      </EditorBubble>
                    </EditorContent>
                  </EditorRoot>
                )}
              </div>
            </div>

            {/* AI Description Section */}
            {description && (
              <div>
                <div className="flex items-center justify-between mb-3">
                  <Label className="text-base font-medium">AI Summary</Label>
                  <div className="flex space-x-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={handleRefreshDescription}
                      disabled={isRefreshingDescription}
                    >
                      <RefreshCw className={`h-4 w-4 mr-1 ${isRefreshingDescription ? 'animate-spin' : ''}`} />
                      Refresh
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={handleRemoveDescription}
                    >
                      <Trash2 className="h-4 w-4 mr-1" />
                      Remove
                    </Button>
                  </div>
                </div>
                <Card>
                  <CardContent className="p-4">
                    <p className="text-sm text-muted-foreground">{description}</p>
                  </CardContent>
                </Card>
              </div>
            )}

            {/* Tags Section */}
            <div>
              <Label className="text-base font-medium mb-3 block">Tags</Label>
              <ItemTagsManager
                itemId={item?.id || ''}
                currentTags={tags}
                onTagsUpdated={handleTagsUpdated}
                itemContent={{
                  title: title,
                  content: content,
                  description: description
                }}
              />
            </div>
          </div>
        </ScrollArea>

        {/* Save Button */}
        <div className="flex-shrink-0 p-6 pt-4 border-t bg-background">
          <Button onClick={handleSave} disabled={isLoading} className="w-full">
            {isLoading ? 'Saving...' : 'Save Changes'}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
};

export default EditItemDialog;
