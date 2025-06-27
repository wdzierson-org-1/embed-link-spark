
import { useRef, useEffect } from 'react';
import { convertToJsonContent } from './EditorUtils';
import type { JSONContent } from 'novel';

interface EditorContentManagerProps {
  content: string;
  editorKey: string;
}

export const useEditorContentManager = ({ content, editorKey }: EditorContentManagerProps) => {
  const lastContentRef = useRef<string>('');
  const initializationRef = useRef<boolean>(false);

  // CRITICAL: Initialize lastContentRef properly when content prop changes
  useEffect(() => {
    console.log('EditorContentManager: Content prop changed:', {
      editorKey,
      newContentLength: content?.length || 0,
      lastContentLength: lastContentRef.current?.length || 0,
      contentChanged: content !== lastContentRef.current,
      contentPreview: content ? content.slice(0, 100) + '...' : 'No content'
    });
    
    // ALWAYS update the ref when content prop changes (from database load)
    // This ensures we start with the correct baseline for comparison
    console.log('EditorContentManager: Updating lastContentRef to match database content');
    lastContentRef.current = content || '';
  }, [content, editorKey]);

  const getInitialContent = (): JSONContent | null => {
    const contentToUse = content || '';
    console.log('EditorContentManager: Converting initial content:', { 
      contentLength: contentToUse.length,
      editorKey,
      contentPreview: contentToUse.slice(0, 100) + '...'
    });
    
    const jsonContent = convertToJsonContent(contentToUse);
    
    // CRITICAL: Ensure lastContentRef matches the initial content exactly
    lastContentRef.current = contentToUse;
    initializationRef.current = true;
    
    console.log('EditorContentManager: Initial content setup complete:', {
      editorKey,
      hasJsonContent: !!jsonContent,
      lastContentRefSet: lastContentRef.current.length,
      initializationFlagSet: initializationRef.current
    });
    
    return jsonContent;
  };

  return {
    lastContentRef,
    initializationRef,
    getInitialContent
  };
};
