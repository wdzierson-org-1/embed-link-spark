
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

  // ENHANCED: Better content loading and initialization
  useEffect(() => {
    if (item && open) {
      console.log('useEditItemState: Item opened/changed', { 
        itemId: item.id, 
        hasContent: !!item.content,
        contentLength: item.content?.length || 0,
        contentPreview: item.content ? item.content.slice(0, 100) + '...' : 'No content'
      });
      
      setIsContentLoading(true);
      initialLoadRef.current = true;
      
      // Create stable editor key that doesn't change during editing session
      const newKey = `editor-${item.id}-${Date.now()}`; // Add timestamp to force refresh
      setEditorInstanceKey(newKey);
      
      console.log('useEditItemState: Generated new editor key for fresh load', { 
        itemId: item.id, 
        editorKey: newKey 
      });
      
      // CRITICAL: Set initial values in both state and refs from DATABASE content
      const initialTitle = item.title || '';
      const initialDescription = item.description || '';
      const initialContent = item.content || '';
      
      console.log('useEditItemState: Setting initial content from database', {
        itemId: item.id,
        titleLength: initialTitle.length,
        descriptionLength: initialDescription.length,
        contentLength: initialContent.length,
        contentPreview: initialContent.slice(0, 100) + '...'
      });
      
      // Update state
      setTitle(initialTitle);
      setDescription(initialDescription);
      setContent(initialContent);
      
      // Update refs to match database content
      titleRef.current = initialTitle;
      descriptionRef.current = initialDescription;
      contentRef.current = initialContent;
      
      console.log('useEditItemState: State and refs updated with database content', {
        itemId: item.id,
        stateContentLength: initialContent.length,
        refContentLength: initialContent.length,
        contentMatch: contentRef.current === initialContent
      });
      
      // Shorter delay to reduce loading time while ensuring proper initialization
      setTimeout(() => {
        setIsContentLoading(false);
        initialLoadRef.current = false;
        console.log('useEditItemState: Content loading completed', {
          itemId: item.id,
          finalContentLength: contentRef.current.length
        });
      }, 50);
    }
  }, [item?.id, item?.content, open]); // Added item?.content to dependencies

  // Clear editor state when sheet closes
  useEffect(() => {
    if (!open) {
      console.log('useEditItemState: Clearing editor state on sheet close');
      
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
      
      console.log('useEditItemState: Editor state cleared completely');
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
