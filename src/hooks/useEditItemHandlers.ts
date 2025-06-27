
import { useCallback } from 'react';

export const useEditItemHandlers = () => {
  
  const handleTagsChange = useCallback(() => {
    // Tags changes are handled separately and don't need auto-save
  }, []);

  const handleMediaChange = useCallback(() => {
    // Media changes are handled separately and don't need auto-save
  }, []);

  return {
    handleTagsChange,
    handleMediaChange,
  };
};
