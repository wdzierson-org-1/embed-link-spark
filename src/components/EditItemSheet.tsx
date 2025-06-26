
import React, { useState, useEffect } from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { useToast } from '@/hooks/use-toast';
import { useTags } from '@/hooks/useTags';
import { Play, Plus, X } from 'lucide-react';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import TagInput from '@/components/TagInput';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface EditItemSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: ContentItem | null;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }) => Promise<void>;
}

const EditItemSheet = ({ open, onOpenChange, item, onSave }: EditItemSheetProps) => {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [content, setContent] = useState('');
  const [itemTags, setItemTags] = useState<string[]>([]);
  const [newTags, setNewTags] = useState<string[]>([]);
  const [isEditingTags, setIsEditingTags] = useState(false);
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);
  const { toast } = useToast();
  const { user } = useAuth();
  const { addTagsToItem, fetchTags } = useTags();

  useEffect(() => {
    if (item) {
      setTitle(item.title || '');
      setDescription(item.description || '');
      setContent(item.content || '');
      fetchItemTags();
    }
  }, [item]);

  const fetchItemTags = async () => {
    if (!item || !user) return;
    
    try {
      const { data, error } = await supabase
        .from('item_tags')
        .select(`
          tags!inner(name)
        `)
        .eq('item_id', item.id);

      if (error) {
        console.error('Error fetching item tags:', error);
        setItemTags([]);
      } else {
        const tagNames = data?.map(row => row.tags.name) || [];
        setItemTags(tagNames);
      }
    } catch (error) {
      console.error('Exception fetching item tags:', error);
      setItemTags([]);
    }
  };

  const getFileUrl = (item: ContentItem) => {
    if (item?.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  // Auto-save functionality with debouncing
  useEffect(() => {
    if (!item) return;
    
    const timeoutId = setTimeout(async () => {
      try {
        await onSave(item.id, {
          title: title.trim() || undefined,
          description: description.trim() || undefined,
          content: content.trim() || undefined,
        });
      } catch (error) {
        console.error('Auto-save failed:', error);
      }
    }, 1000); // 1 second debounce

    return () => clearTimeout(timeoutId);
  }, [title, description, content, item?.id, onSave]);

  const handleAddTags = async () => {
    if (!item || newTags.length === 0) return;

    try {
      await addTagsToItem(item.id, newTags);
      setNewTags([]);
      setIsEditingTags(false);
      await fetchItemTags();
      await fetchTags();
      toast({
        title: "Success",
        description: `Added ${newTags.length} tag(s) to item`,
      });
    } catch (error) {
      console.error('Error adding tags:', error);
      toast({
        title: "Error",
        description: "Failed to add tags",
        variant: "destructive",
      });
    }
  };

  const handleRemoveTag = async (tagName: string) => {
    if (!item) return;
    
    try {
      const { data: tagData, error: tagError } = await supabase
        .from('tags')
        .select('id')
        .eq('name', tagName.toLowerCase())
        .single();

      if (tagError) throw tagError;

      const { error: relationError } = await supabase
        .from('item_tags')
        .delete()
        .eq('item_id', item.id)
        .eq('tag_id', tagData.id);

      if (relationError) throw relationError;

      await fetchItemTags();
      await fetchTags();
      toast({
        title: "Success",
        description: "Tag removed from item",
      });
    } catch (error) {
      console.error('Error removing tag:', error);
      toast({
        title: "Error",
        description: "Failed to remove tag",
        variant: "destructive",
      });
    }
  };

  const fileUrl = getFileUrl(item);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-[800px] sm:max-w-[800px] p-0">
        <div className="h-full flex flex-col">
          <SheetHeader className="px-6 py-4 border-b">
            <SheetTitle>Edit Item</SheetTitle>
          </SheetHeader>

          <div className="flex-1 overflow-y-auto">
            <div className="p-6 space-y-8">
              {/* Title Section */}
              <div className="space-y-2">
                <label className="text-sm font-medium text-muted-foreground">Title</label>
                <Input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Enter title..."
                  className="border-0 border-b border-border rounded-none px-0 focus-visible:ring-0 focus-visible:border-primary"
                />
              </div>

              {/* Description Section */}
              <div className="space-y-2">
                <label className="text-sm font-medium text-muted-foreground">Description</label>
                <Textarea
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Enter description..."
                  className="border-0 border-b border-border rounded-none px-0 resize-none focus-visible:ring-0 focus-visible:border-primary"
                  rows={3}
                />
              </div>

              {/* Media Section */}
              {item?.file_path && (item.type === 'audio' || item.type === 'video') && (
                <div className="space-y-4">
                  <label className="text-sm font-medium text-muted-foreground">Media</label>
                  
                  {item.type === 'audio' && fileUrl && (
                    <MediaPlayer
                      src={fileUrl}
                      fileName={item.title || 'Audio file'}
                      showRemove={false}
                    />
                  )}

                  {item.type === 'video' && fileUrl && (
                    <div className="space-y-2">
                      <Button
                        variant="outline"
                        onClick={() => setIsVideoLightboxOpen(true)}
                        className="w-full justify-center gap-2"
                      >
                        <Play className="h-4 w-4" />
                        Preview Video
                      </Button>
                      <VideoLightbox
                        src={fileUrl}
                        fileName={item.title || 'Video file'}
                        isOpen={isVideoLightboxOpen}
                        onClose={() => setIsVideoLightboxOpen(false)}
                      />
                    </div>
                  )}
                </div>
              )}

              {/* Content Section */}
              {(item?.type === 'text' || item?.type === 'link') && (
                <div className="space-y-2">
                  <label className="text-sm font-medium text-muted-foreground">Content</label>
                  <Textarea
                    value={content}
                    onChange={(e) => setContent(e.target.value)}
                    placeholder="Enter content..."
                    className="border-0 border-b border-border rounded-none px-0 min-h-[200px] resize-none focus-visible:ring-0 focus-visible:border-primary"
                  />
                </div>
              )}

              {/* Tags Section */}
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <label className="text-sm font-medium text-muted-foreground">Tags</label>
                  {!isEditingTags && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setIsEditingTags(true)}
                      className="h-auto p-1 text-xs"
                    >
                      <Plus className="h-3 w-3 mr-1" />
                      Add tags
                    </Button>
                  )}
                </div>

                {/* Current Tags */}
                {itemTags.length > 0 && (
                  <div className="flex flex-wrap gap-2">
                    {itemTags.map((tag, index) => (
                      <Badge key={index} variant="secondary" className="text-xs">
                        {tag}
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-auto p-0 ml-1 hover:bg-transparent"
                          onClick={() => handleRemoveTag(tag)}
                        >
                          <X className="h-3 w-3" />
                        </Button>
                      </Badge>
                    ))}
                  </div>
                )}

                {/* Tag Input */}
                {isEditingTags && (
                  <div className="space-y-3 p-4 bg-muted/30 rounded-lg">
                    <TagInput
                      tags={newTags}
                      onTagsChange={setNewTags}
                      suggestions={[]}
                      placeholder="Type to add tags..."
                      maxTags={5}
                    />
                    
                    <div className="flex gap-2">
                      <Button size="sm" onClick={handleAddTags} disabled={newTags.length === 0}>
                        Add Tags
                      </Button>
                      <Button 
                        size="sm" 
                        variant="outline" 
                        onClick={() => {
                          setIsEditingTags(false);
                          setNewTags([]);
                        }}
                      >
                        Cancel
                      </Button>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Auto-save indicator */}
          <div className="px-6 py-3 border-t bg-muted/30">
            <p className="text-xs text-muted-foreground">Changes are saved automatically</p>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
};

export default EditItemSheet;
