
import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { generateTitle } from '@/utils/titleGenerator';
import { debounce } from 'lodash';

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
  const [content, setContent] = useState(''); // Only for initial load and draft restore
  const [hasImage, setHasImage] = useState(false);
  const [imageUrl, setImageUrl] = useState('');
  const [isContentLoading, setIsContentLoading] = useState(false);
  const [editorKey, setEditorKey] = useState<string>('');
  const [editorInstanceKey, setEditorInstanceKey] = useState<string>('');
  const [activeTab, setActiveTab] = useState('details');
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved'>('idle');
  const [showDraftRestore, setShowDraftRestore] = useState(false);
  const [lastSaved, setLastSaved] = useState<Date | null>(null);
  
  // Refs to hold current values without triggering re-renders
  const titleRef = useRef('');
  const descriptionRef = useRef('');
  const contentRef = useRef('');
  const itemRef = useRef(item);
  const initialLoadRef = useRef(false);

  // Update refs when item changes
  useEffect(() => { itemRef.current = item; }, [item]);

  // Local storage draft management
  const getDraftKey = useCallback((id: string) => `editDraft-${id}`, []);

  const saveToLocalStorage = useCallback((itemId: string, data: { title: string; description: string; content: string }) => {
    const draftKey = getDraftKey(itemId);
    const draftData = {
      ...data,
      timestamp: Date.now()
    };
    localStorage.setItem(draftKey, JSON.stringify(draftData));
  }, [getDraftKey]);

  const clearDraft = useCallback((itemId: string) => {
    const draftKey = getDraftKey(itemId);
    localStorage.removeItem(draftKey);
  }, [getDraftKey]);

  // Debounced save function - saves to both localStorage and server
  const debouncedSave = useCallback(
    debounce(async (itemId: string, updates: { title?: string; description?: string; content?: string }) => {
      if (!itemId) return;
      
      setSaveStatus('saving');
      
      try {
        // Save to localStorage first (immediate)
        saveToLocalStorage(itemId, {
          title: titleRef.current,
          description: descriptionRef.current,
          content: contentRef.current
        });

        // Then save to server
        await onSave(itemId, updates, { showSuccessToast: false, refreshItems: false });
        
        setSaveStatus('saved');
        setLastSaved(new Date());
      } catch (error) {
        console.error('Debounced save failed:', error);
        setSaveStatus('idle');
      }
    }, 2000), // 2 second delay
    [onSave, saveToLocalStorage]
  );

  // Update content ref and trigger debounced save
  const handleTitleChange = useCallback((newTitle: string) => {
    titleRef.current = newTitle;
    setTitle(newTitle); // Update state for UI binding
    
    if (item?.id) {
      debouncedSave(item.id, { 
        title: newTitle.trim() || undefined,
        description: descriptionRef.current.trim() || undefined,
        content: contentRef.current.trim() || undefined
      });
    }
  }, [item?.id, debouncedSave]);

  const handleDescriptionChange = useCallback((newDescription: string) => {
    descriptionRef.current = newDescription;
    setDescription(newDescription); // Update state for UI binding
    
    if (item?.id) {
      debouncedSave(item.id, { 
        title: titleRef.current.trim() || undefined,
        description: newDescription.trim() || undefined,
        content: contentRef.current.trim() || undefined
      });
    }
  }, [item?.id, debouncedSave]);

  const handleContentChange = useCallback((newContent: string) => {
    contentRef.current = newContent;
    // Don't update content state to avoid re-renders that cause focus loss
    
    if (item?.id) {
      debouncedSave(item.id, { 
        title: titleRef.current.trim() || undefined,
        description: descriptionRef.current.trim() || undefined,
        content: newContent.trim() || undefined
      });
    }
  }, [item?.id, debouncedSave]);

  const checkForImage = useCallback(() => {
    if (!item) return;
    
    if (item.type === 'image' && item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      setHasImage(true);
      setImageUrl(data.publicUrl);
    } else if (item.type === 'link' && item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      setHasImage(true);
      setImageUrl(data.publicUrl);
    } else {
      setHasImage(false);
      setImageUrl('');
    }
  }, [item]);

  // Check for existing draft when sheet opens
  useEffect(() => {
    if (item?.id && open) {
      const draftKey = getDraftKey(item.id);
      const savedDraft = localStorage.getItem(draftKey);
      
      if (savedDraft) {
        try {
          const draft = JSON.parse(savedDraft);
          // Check if draft is less than 24 hours old
          const isRecentDraft = Date.now() - draft.timestamp < 24 * 60 * 60 * 1000;
          
          if (isRecentDraft) {
            setShowDraftRestore(true);
          } else {
            localStorage.removeItem(draftKey);
          }
        } catch (error) {
          console.error('Error parsing draft:', error);
          localStorage.removeItem(draftKey);
        }
      }
    }
  }, [item?.id, open, getDraftKey]);

  // Handle draft restoration
  const handleRestoreDraft = useCallback(() => {
    if (!item?.id) return;
    
    const draftKey = getDraftKey(item.id);
    const savedDraft = localStorage.getItem(draftKey);
    
    if (savedDraft) {
      try {
        const draft = JSON.parse(savedDraft);
        
        // Update both state and refs
        setTitle(draft.title);
        setDescription(draft.description);
        setContent(draft.content);
        
        titleRef.current = draft.title;
        descriptionRef.current = draft.description;
        contentRef.current = draft.content;
      } catch (error) {
        console.error('Error restoring draft:', error);
      }
    }
    setShowDraftRestore(false);
  }, [item?.id, getDraftKey]);

  const handleDiscardDraft = useCallback(() => {
    if (item?.id) {
      clearDraft(item.id);
    }
    setShowDraftRestore(false);
  }, [item?.id, clearDraft]);

  // Generate a unique editor key when item changes or sheet opens
  useEffect(() => {
    if (item && open) {
      setIsContentLoading(true);
      initialLoadRef.current = true;
      const newKey = `editor-${item.id}-${Date.now()}`;
      setEditorInstanceKey(newKey);
      
      // Set initial values in both state and refs
      const initialTitle = item.title || '';
      const initialDescription = item.description || '';
      const initialContent = item.content || '';
      
      setTitle(initialTitle);
      setDescription(initialDescription);
      setContent(initialContent);
      
      titleRef.current = initialTitle;
      descriptionRef.current = initialDescription;
      contentRef.current = initialContent;
      
      setTimeout(() => {
        setIsContentLoading(false);
        initialLoadRef.current = false;
      }, 100);
      
      checkForImage();
    }
  }, [item?.id, open, checkForImage]);

  // Save to server when sheet closes (final save)
  useEffect(() => {
    if (!open && itemRef.current && !initialLoadRef.current) {
      const performFinalSave = async () => {
        setSaveStatus('saving');
        
        try {
          const updates: any = {
            title: titleRef.current.trim() || undefined,
            description: descriptionRef.current.trim() || undefined,
            content: contentRef.current.trim() || undefined,
          };

          await onSave(itemRef.current!.id, updates, { showSuccessToast: false, refreshItems: true });
          
          // Clear localStorage after successful save
          if (itemRef.current?.id) {
            clearDraft(itemRef.current.id);
          }
          
          setSaveStatus('saved');
        } catch (error) {
          console.error('Final save failed:', error);
          setSaveStatus('idle');
        }
      };

      // Only save if there are actual changes
      if (titleRef.current || descriptionRef.current || contentRef.current) {
        performFinalSave();
      } else if (itemRef.current?.id) {
        clearDraft(itemRef.current.id);
      }
    }

    // Clear editor state when sheet closes
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
      setShowDraftRestore(false);
      setLastSaved(null);
      
      // Clear refs
      titleRef.current = '';
      descriptionRef.current = '';
      contentRef.current = '';
    }
  }, [open, onSave, clearDraft]);

  const handleTagsChange = () => {
    // Tags changes are handled separately and don't need auto-save
  };

  const handleMediaChange = () => {
    // Media changes are handled separately and don't need auto-save
  };

  const handleTitleSave = async (newTitle: string) => {
    if (!item) return;
    
    let finalTitle = newTitle;
    if (!finalTitle && contentRef.current) {
      try {
        finalTitle = await generateTitle(contentRef.current, item.type || 'text');
      } catch (error) {
        console.error('Error generating title:', error);
        finalTitle = 'Untitled Note';
      }
    }
    
    setTitle(finalTitle);
    titleRef.current = finalTitle;
    await onSave(item.id, { title: finalTitle });
  };

  const handleDescriptionSave = async (newDescription: string) => {
    if (!item) return;
    descriptionRef.current = newDescription;
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
    content, // Only used for initial load and editor mounting
    hasImage,
    imageUrl,
    isContentLoading,
    editorKey,
    activeTab,
    saveStatus,
    showDraftRestore,
    lastSaved,
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
    handleRestoreDraft,
    handleDiscardDraft,
  };
};
