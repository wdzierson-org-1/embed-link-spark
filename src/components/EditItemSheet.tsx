import React, { useState, useEffect } from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Tabs } from '@/components/ui/tabs';
import { TooltipProvider } from '@/components/ui/tooltip';
import EditItemTabNavigation from '@/components/EditItemTabNavigation';
import EditItemDetailsTab from '@/components/EditItemDetailsTab';
import EditItemImageTab from '@/components/EditItemImageTab';
import EditItemAutoSaveIndicator from '@/components/EditItemAutoSaveIndicator';
import { supabase } from '@/integrations/supabase/client';
import { generateTitle } from '@/utils/titleGenerator';

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
  const [hasImage, setHasImage] = useState(false);
  const [imageUrl, setImageUrl] = useState('');
  const [isContentLoading, setIsContentLoading] = useState(false);
  const [editorKey, setEditorKey] = useState<string>('');
  const [editorInstanceKey, setEditorInstanceKey] = useState<string>('');
  const [activeTab, setActiveTab] = useState('details');
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved'>('idle');
  const [saveTimeoutId, setSaveTimeoutId] = useState<NodeJS.Timeout | null>(null);

  // Generate a unique editor key when item changes or sheet opens
  useEffect(() => {
    if (item && open) {
      setIsContentLoading(true);
      const newKey = `editor-${item.id}-${Date.now()}`;
      setEditorInstanceKey(newKey);
      
      setTitle(item.title || '');
      setDescription(item.description || '');
      
      // For links, use content as-is (should be user notes, not OG data)
      setContent(item.content || '');
      
      setTimeout(() => {
        setIsContentLoading(false);
      }, 100);
      
      checkForImage();
    }
  }, [item?.id, open]);

  // Clear editor state when sheet closes
  useEffect(() => {
    if (!open) {
      setTitle('');
      setDescription('');
      setContent('');
      setHasImage(false);
      setImageUrl('');
      setIsContentLoading(false);
      setEditorKey('');
      setEditorInstanceKey('');
      setActiveTab('details');
      setSaveStatus('idle');
      if (saveTimeoutId) {
        clearTimeout(saveTimeoutId);
        setSaveTimeoutId(null);
      }
    }
  }, [open, saveTimeoutId]);

  const checkForImage = () => {
    if (!item) return;
    
    if (item.type === 'image' && item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      setHasImage(true);
      setImageUrl(data.publicUrl);
    } else if (item.type === 'link' && item.file_path) {
      // For links, check if there's a preview image stored in file_path
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      setHasImage(true);
      setImageUrl(data.publicUrl);
    } else {
      setHasImage(false);
      setImageUrl('');
    }
  };

  // Unified auto-save function that handles all types of changes
  const triggerAutoSave = async (changeType: 'content' | 'tags' | 'media' = 'content') => {
    if (!item || isContentLoading) return;
    
    if (saveTimeoutId) {
      clearTimeout(saveTimeoutId);
    }
    
    setSaveStatus('saving');
    
    const timeoutId = setTimeout(async () => {
      try {
        // For links, preserve the file_path (preview image) during auto-save
        const updates: any = {
          title: title.trim() || undefined,
          description: description.trim() || undefined,
          content: content.trim() || undefined,
        };

        await onSave(item.id, updates);
        setSaveStatus('saved');
        
        setTimeout(() => {
          setSaveStatus('idle');
        }, 2000);
      } catch (error) {
        console.error('Auto-save failed:', error);
        setSaveStatus('idle');
      }
      setSaveTimeoutId(null);
    }, 1000);
    
    setSaveTimeoutId(timeoutId);
  };

  // Auto-save functionality with debouncing for content changes
  useEffect(() => {
    triggerAutoSave('content');
  }, [title, description, content, item?.id]);

  const handleTagsChange = () => {
    triggerAutoSave('tags');
  };

  const handleMediaChange = () => {
    triggerAutoSave('media');
  };

  const handleTitleSave = async (newTitle: string) => {
    if (!item) return;
    
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

  const handleImageStateChange = (newHasImage: boolean, newImageUrl: string) => {
    setHasImage(newHasImage);
    setImageUrl(newImageUrl);
    if (item) {
      setTimeout(() => checkForImage(), 500);
    }
    handleMediaChange();
  };

  return (
    <TooltipProvider>
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent className="w-[800px] sm:max-w-[800px] p-0 flex flex-col">
          <SheetHeader className="px-6 py-4 border-b flex-shrink-0">
            <SheetTitle>Edit Item</SheetTitle>
          </SheetHeader>

          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1 flex flex-col min-h-0">
            <EditItemTabNavigation hasImage={hasImage} />

            <EditItemDetailsTab
              item={item}
              title={title}
              description={description}
              content={content}
              isContentLoading={isContentLoading}
              editorKey={editorKey}
              onTitleChange={setTitle}
              onDescriptionChange={setDescription}
              onContentChange={setContent}
              onTitleSave={handleTitleSave}
              onDescriptionSave={handleDescriptionSave}
              onTagsChange={handleTagsChange}
              onMediaChange={handleMediaChange}
            />

            <EditItemImageTab
              item={item}
              hasImage={hasImage}
              imageUrl={imageUrl}
              onImageStateChange={handleImageStateChange}
            />
          </Tabs>

          <EditItemAutoSaveIndicator saveStatus={saveStatus} />
        </SheetContent>
      </Sheet>
    </TooltipProvider>
  );
};

export default EditItemSheet;
