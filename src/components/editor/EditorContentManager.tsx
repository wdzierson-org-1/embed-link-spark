
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

  // Track content prop changes
  useEffect(() => {
    console.log('EditorContainer: Content prop changed:', {
      editorKey,
      newContentLength: content?.length || 0,
      lastContentLength: lastContentRef.current?.length || 0,
      contentChanged: content !== lastContentRef.current,
      contentPreview: content ? content.slice(0, 100) + '...' : 'No content'
    });
    
    // Update the ref when content prop changes (from database load)
    if (content !== lastContentRef.current) {
      console.log('EditorContainer: Updating lastContentRef due to prop change');
      lastContentRef.current = content || '';
    }
  }, [content, editorKey]);

  const getInitialContent = (): JSONContent | null => {
    const contentToUse = content || '';
    console.log('EditorContainer: Converting initial content:', { 
      contentLength: contentToUse.length,
      editorKey,
      contentPreview: contentToUse.slice(0, 100) + '...'
    });
    
    const jsonContent = convertToJsonContent(contentToUse);
    
    // CRITICAL: Ensure lastContentRef matches the initial content
    lastContentRef.current = contentToUse;
    initializationRef.current = true;
    
    console.log('EditorContainer: Initial content conversion complete:', {
      editorKey,
      hasJsonContent: !!jsonContent,
      lastContentRefLength: lastContentRef.current.length
    });
    
    return jsonContent;
  };

  return {
    lastContentRef,
    initializationRef,
    getInitialContent
  };
};
