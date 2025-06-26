
import React, { useState, useEffect, useCallback, useRef } from 'react';
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
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
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
  
  // Use refs to track the latest values without causing re-renders
  const titleRef = useRef(title);
  const descriptionRef = useRef(description);
  const contentRef = useRef(content);
  const saveTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const isLoadingRef = useRef(false);

  // Update refs when state changes
  useEffect(() => { titleRef.current = title; }, [title]);
  useEffect(() => { descriptionRef.current = description; }, [description]);
  useEffect(() => { contentRef.current = content; }, [content]);

  // Generate a unique editor key when item changes or sheet opens
  useEffect(() => {
    if (item && open) {
      setIsContentLoading(true);
      isLoadingRef.current = true;
      const newKey = `editor-${item.id}-${Date.now()}`;
      setEditorInstanceKey(newKey);
      
      setTitle(item.title || '');
      setDescription(item.description || '');
      
      // For links, use content as-is (should be user notes, not OG data)
      setContent(item.content || '');
      
      setTimeout(() => {
        setIsContentLoading(false);
        isLoadingRef.current = false;
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
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current);
        saveTimeoutRef.current = null;
      }
    }
  }, [open]);

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

  // Debounced auto-save function
  const debouncedAutoSave = useCallback(async () => {
    if (!item || isLoadingRef.current) return;
    
    setSaveStatus('saving');
    
    try {
      const updates: any = {
        title: titleRef.current.trim() || undefined,
        description: descriptionRef.current.trim() || undefined,
        content: contentRef.current.trim() || undefined,
      };

      // Use silent save (no toast, no refresh) for auto-saves
      await onSave(item.id, updates, { showSuccessToast: false, refreshItems: false });
      setSaveStatus('saved');
      
      setTimeout(() => {
        setSaveStatus('idle');
      }, 2000);
    } catch (error) {
      console.error('Auto-save failed:', error);
      setSaveStatus('idle');
    }
  }, [item?.id, onSave]);

  // Trigger auto-save with debouncing
  const triggerAutoSave = useCallback(() => {
    if (!item || isLoadingRef.current) return;
    
    if (saveTimeoutRef.current) {
      clearTimeout(saveTimeoutRef.current);
    }
    
    saveTimeoutRef.current = setTimeout(() => {
      debouncedAutoSave();
      saveTimeoutRef.current = null;
    }, 1000);
  }, [debouncedAutoSave, item]);

  // Individual change handlers that trigger auto-save
  const handleTitleChange = useCallback((newTitle: string) => {
    setTitle(newTitle);
    triggerAutoSave();
  }, [triggerAutoSave]);

  const handleDescriptionChange = useCallback((newDescription: string) => {
    setDescription(newDescription);
    triggerAutoSave();
  }, [triggerAutoSave]);

  const handleContentChange = useCallback((newContent: string) => {
    setContent(newContent);
    triggerAutoSave();
  }, [triggerAutoSave]);

  const handleTagsChange = () => {
    triggerAutoSave();
  };

  const handleMediaChange = () => {
    triggerAutoSave();
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
              onTitleChange={handleTitleChange}
              onDescriptionChange={handleDescriptionChange}
              onContentChange={handleContentChange}
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
