
export const useEditItemHandlers = () => {
  const handleTagsChange = async (tags: string[]) => {
    // Tags are handled by the EditItemTagsSection component
    // This is just a placeholder for the parent component interface
    console.log('Tags changed:', tags);
  };

  const handleMediaChange = () => {
    // Media changes are handled by individual media components
    console.log('Media changed');
  };

  return {
    handleTagsChange,
    handleMediaChange,
  };
};
