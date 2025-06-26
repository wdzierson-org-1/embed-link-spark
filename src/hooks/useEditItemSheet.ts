
import { useState, useEffect, useCallback, useRef } from 'react';
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

interface UseEditItemSheetProps {
  open: boolean;
  item: ContentItem | null;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
}

export const useEditItemSheet = ({ open, item, onSave }: UseEditItemSheetProps) => {
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
  
  // Use refs to track the latest values and auto-save state
  const titleRef = useRef(title);
  const descriptionRef = useRef(description);
  const contentRef = useRef(content);
  const saveTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const isLoadingRef = useRef(false);
  const itemRef = useRef(item);

  // Update refs when state changes
  useEffect(() => { titleRef.current = title; }, [title]);
  useEffect(() => { descriptionRef.current = description; }, [description]);
  useEffect(() => { contentRef.current = content; }, [content]);
  useEffect(() => { itemRef.current = item; }, [item]);

  // Stable auto-save function using refs
  const performAutoSave = useCallback(async () => {
    const currentItem = itemRef.current;
    if (!currentItem || isLoadingRef.current) return;
    
    setSaveStatus('saving');
    
    try {
      const updates: any = {
        title: titleRef.current.trim() || undefined,
        description: descriptionRef.current.trim() || undefined,
        content: contentRef.current.trim() || undefined,
      };

      // Use silent save (no toast, no refresh) for auto-saves
      await onSave(currentItem.id, updates, { showSuccessToast: false, refreshItems: false });
      setSaveStatus('saved');
      
      setTimeout(() => {
        setSaveStatus('idle');
      }, 2000);
    } catch (error) {
      console.error('Auto-save failed:', error);
      setSaveStatus('idle');
    }
  }, [onSave]);

  // Stable debounced auto-save trigger
  const triggerAutoSave = useCallback(() => {
    if (!itemRef.current || isLoadingRef.current) return;
    
    if (saveTimeoutRef.current) {
      clearTimeout(saveTimeoutRef.current);
    }
    
    saveTimeoutRef.current = setTimeout(() => {
      performAutoSave();
      saveTimeoutRef.current = null;
    }, 1000);
  }, [performAutoSave]);

  // Stable change handlers
  const handleTitleChange = useCallback((newTitle: string) => {
    setTitle(newTitle);
    triggerAutoSave();
  }, [triggerAutoSave]);

  const handleDescriptionChange = useCallback((newDescription: string) => {
    setDescription(newDescription);
    triggerAutoSave();
  }, [triggerAutoSave]);

  // CRITICAL: Make this callback completely stable
  const handleContentChange = useCallback((newContent: string) => {
    setContent(newContent);
    // Use the ref-based auto-save trigger to avoid recreating this callback
    if (saveTimeoutRef.current) {
      clearTimeout(saveTimeoutRef.current);
    }
    
    saveTimeoutRef.current = setTimeout(() => {
      if (itemRef.current && !isLoadingRef.current) {
        performAutoSave();
      }
      saveTimeoutRef.current = null;
    }, 1000);
  }, [performAutoSave]);

  const checkForImage = useCallback(() => {
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
  }, [item]);

  // Generate a unique editor key when item changes or sheet opens
  useEffect(() => {
    if (item && open) {
      setIsContentLoading(true);
      isLoadingRef.current = true;
      const newKey = `editor-${item.id}-${Date.now()}`;
      setEditorInstanceKey(newKey);
      
      setTitle(item.title || '');
      setDescription(item.description || '');
      setContent(item.content || '');
      
      setTimeout(() => {
        setIsContentLoading(false);
        isLoadingRef.current = false;
      }, 100);
      
      checkForImage();
    }
  }, [item?.id, open, checkForImage]);

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

  return {
    // State
    title,
    description,
    content,
    hasImage,
    imageUrl,
    isContentLoading,
    editorKey,
    activeTab,
    saveStatus,
    setActiveTab,
    
    // Handlers
    handleTitleChange,
    handleDescriptionChange,
    handleContentChange,
    handleTitleSave,
    handleDescriptionSave,
    handleTagsChange,
    handleMediaChange,
    handleImageStateChange,
  };
};
