import React, { useState, useEffect } from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { useToast } from '@/hooks/use-toast';
import { useTags } from '@/hooks/useTags';
import { Play, Plus, X } from 'lucide-react';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import TagInput from '@/components/TagInput';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemDescriptionSection from '@/components/EditItemDescriptionSection';
import EditItemImageSection from '@/components/EditItemImageSection';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { generateTitle } from '@/utils/titleGenerator';
import { getSuggestedTags as getSuggestedTagsFromApi } from '@/utils/aiOperations';

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
  const [tagSuggestions, setTagSuggestions] = useState<string[]>([]);
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);
  const [hasImage, setHasImage] = useState(false);
  const [imageUrl, setImageUrl] = useState('');
  const [isContentLoading, setIsContentLoading] = useState(false);
  const [editorKey, setEditorKey] = useState<string>('');
  const { toast } = useToast();
  const { user } = useAuth();
  const { addTagsToItem, fetchTags, getSuggestedTags } = useTags();

  // Generate a unique editor key when item changes or sheet opens
  useEffect(() => {
    if (item && open) {
      setIsContentLoading(true);
      // Create a unique key combining item ID and timestamp to force editor recreation
      const newKey = `editor-${item.id}-${Date.now()}`;
      setEditorKey(newKey);
      
      // Set content state
      setTitle(item.title || '');
      setDescription(item.description || '');
      setContent(item.content || '');
      
      // Small delay to ensure state is updated before showing editor
      setTimeout(() => {
        setIsContentLoading(false);
      }, 100);
      
      fetchItemTags();
      checkForImage();
      loadTagSuggestions();
    }
  }, [item?.id, open]); // Only depend on item ID and open state

  // Clear editor state when sheet closes
  useEffect(() => {
    if (!open) {
      // Reset all state when sheet closes to ensure clean state
      setTitle('');
      setDescription('');
      setContent('');
      setItemTags([]);
      setNewTags([]);
      setIsEditingTags(false);
      setTagSuggestions([]);
      setIsVideoLightboxOpen(false);
      setHasImage(false);
      setImageUrl('');
      setIsContentLoading(false);
      setEditorKey('');
    }
  }, [open]);

  useEffect(() => {
    if (item) {
      setTitle(item.title || '');
      setDescription(item.description || '');
      setContent(item.content || '');
      fetchItemTags();
      checkForImage();
      loadTagSuggestions();
    }
  }, [item]);

  const loadTagSuggestions = async () => {
    if (!item) return;
    
    try {
      // Get AI-suggested tags
      const aiSuggestions = await getSuggestedTagsFromApi({
        title: item.title || '',
        content: item.content || '',
        description: item.description || ''
      });
      
      // Get popular tags from user's existing tags
      const popularTags = getSuggestedTags(10);
      
      // Combine and deduplicate
      const allSuggestions = [...new Set([...aiSuggestions, ...popularTags])];
      setTagSuggestions(allSuggestions);
    } catch (error) {
      console.error('Error loading tag suggestions:', error);
      // Fallback to popular tags only
      setTagSuggestions(getSuggestedTags(10));
    }
  };

  const checkForImage = () => {
    if (!item) return;
    
    // Check for regular image files
    if (item.type === 'image' && item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      setHasImage(true);
      setImageUrl(data.publicUrl);
    }
    // Check for link preview images
    else if (item.type === 'link' && item.content) {
      try {
        const contentData = JSON.parse(item.content);
        const storedImagePath = contentData.ogData?.storedImagePath;
        
        if (storedImagePath) {
          const { data } = supabase.storage.from('stash-media').getPublicUrl(storedImagePath);
          setHasImage(true);
          setImageUrl(data.publicUrl);
        }
      } catch (e) {
        // If content is not JSON, ignore
      }
    } else {
      setHasImage(false);
      setImageUrl('');
    }
  };

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
    if (!item || isContentLoading) return;
    
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
  }, [title, description, content, item?.id, onSave, isContentLoading]);

  const handleTitleSave = async (newTitle: string) => {
    if (!item) return;
    
    // If title is empty, generate one from content
    let finalTitle = newTitle;
    if (!finalTitle && content) {
      try {
        finalTitle = await generateTitle(content, item.type || 'text');
      } catch (error) {
        console.error('Error generating title:', error);
        finalTitle = 'Untitled Note';
      }
    }
    
    setTitle(finalTitle);
    await onSave(item.id, { title: finalTitle });
  };

  const handleDescriptionSave = async (newDescription: string) => {
    if (!item) return;
    await onSave(item.id, { description: newDescription });
  };

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

  const handleImageStateChange = (newHasImage: boolean, newImageUrl: string) => {
    setHasImage(newHasImage);
    setImageUrl(newImageUrl);
    // Refetch the item to update the UI properly
    if (item) {
      setTimeout(() => checkForImage(), 500);
    }
  };

  const fileUrl = getFileUrl(item);

  return (
    <TooltipProvider>
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent className="w-[800px] sm:max-w-[800px] p-0">
          <div className="h-full flex flex-col">
            <SheetHeader className="px-6 py-4 border-b">
              <SheetTitle>Edit Item</SheetTitle>
            </SheetHeader>

            <div className="flex-1 overflow-y-auto">
              <div className="p-6 space-y-8">
                
                {/* Image Section */}
                {hasImage && (
                  <div className="relative inline-block">
                    <img
                      src={imageUrl}
                      alt="Item image"
                      className="w-full max-w-md rounded-lg border"
                    />
                    <EditItemImageSection
                      itemId={item?.id || ''}
                      hasImage={hasImage}
                      imageUrl={imageUrl}
                      onImageStateChange={handleImageStateChange}
                      asLink={true}
                    />
                  </div>
                )}

                {/* Title Section */}
                <EditItemTitleSection
                  title={title}
                  onTitleChange={setTitle}
                  onSave={handleTitleSave}
                />

                {/* Content Section - Always shown */}
                <div className="space-y-2">
                  <label className="text-sm font-medium text-muted-foreground">Content</label>
                  <div className="relative">
                    {isContentLoading ? (
                      <div className="border rounded-md p-4 min-h-[300px] flex items-center justify-center text-muted-foreground">
                        Loading editor...
                      </div>
                    ) : (
                      <EditItemContentEditor
                        content={content}
                        onContentChange={setContent}
                        itemId={item?.id}
                        editorInstanceKey={editorKey}
                      />
                    )}
                    <div className="absolute bottom-3 right-3 text-xs text-muted-foreground bg-background/80 backdrop-blur-sm px-2 py-1 rounded">
                      Press / for formatting options
                    </div>
                  </div>
                </div>

                {/* Summary Section */}
                <EditItemDescriptionSection
                  itemId={item?.id || ''}
                  description={description}
                  content={content}
                  title={title}
                  onDescriptionChange={setDescription}
                  onSave={handleDescriptionSave}
                />

                {/* Media Section */}
                {item?.file_path && (item.type === 'audio' || item.type === 'video') && (
                  <div className="space-y-4">
                    
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
                        suggestions={tagSuggestions}
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
    </TooltipProvider>
  );
};

export default EditItemSheet;
