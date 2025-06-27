
import { useState, useRef, useEffect } from 'react';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface UseEditItemStateProps {
  open: boolean;
  item: ContentItem | null;
}

export const useEditItemState = ({ open, item }: UseEditItemStateProps) => {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [content, setContent] = useState('');
  const [isContentLoading, setIsContentLoading] = useState(false);
  const [editorKey, setEditorKey] = useState<string>('');
  const [editorInstanceKey, setEditorInstanceKey] = useState<string>('');
  const [activeTab, setActiveTab] = useState('details');
  
  // Refs to hold current values without triggering re-renders
  const titleRef = useRef('');
  const descriptionRef = useRef('');
  const contentRef = useRef('');
  const itemRef = useRef(item);
  const initialLoadRef = useRef(false);

  // Update refs when item changes
  useEffect(() => { 
    itemRef.current = item; 
  }, [item]);

  // Generate a stable editor key when item changes or sheet opens
  useEffect(() => {
    if (item && open) {
      setIsContentLoading(true);
      initialLoadRef.current = true;
      
      // Create stable editor key that doesn't change during editing session
      const newKey = `editor-${item.id}-stable`;
      setEditorInstanceKey(newKey);
      
      console.log('useEditItemState: Generated stable editor key for item', { 
        itemId: item.id, 
        editorKey: newKey 
      });
      
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
    }
  }, [item?.id, open]);

  // Clear editor state when sheet closes
  useEffect(() => {
    if (!open) {
      setTitle('');
      setDescription('');
      setContent('');
      setIsContentLoading(false);
      setEditorKey('');
      setEditorInstanceKey('');
      setActiveTab('details');
      
      // Clear refs
      titleRef.current = '';
      descriptionRef.current = '';
      contentRef.current = '';
      
      console.log('useEditItemState: Cleared editor state on sheet close');
    }
  }, [open]);

  return {
    // State
    title,
    description,
    content,
    isContentLoading,
    editorKey: editorInstanceKey, // Use editorInstanceKey as the main editor key
    activeTab,
    setActiveTab,
    
    // Refs
    titleRef,
    descriptionRef,
    contentRef,
    itemRef,
    initialLoadRef,
    
    // State setters
    setTitle,
    setDescription,
    setContent,
  };
};
