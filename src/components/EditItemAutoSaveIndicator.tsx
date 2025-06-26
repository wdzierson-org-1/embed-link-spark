
import React from 'react';

interface EditItemAutoSaveIndicatorProps {
  saveStatus: 'idle' | 'saving' | 'saved';
}

const EditItemAutoSaveIndicator = ({ saveStatus }: EditItemAutoSaveIndicatorProps) => {
  const getSaveStatusText = () => {
    switch (saveStatus) {
      case 'saving':
        return 'Saving changes...';
      case 'saved':
        return 'All changes saved';
      default:
        return 'Changes are saved automatically to local storage';
    }
  };

  return (
    <div className="px-6 py-3 border-t bg-muted/30 flex-shrink-0">
      <p className={`text-xs ${saveStatus === 'saving' ? 'text-blue-600' : saveStatus === 'saved' ? 'text-green-600' : 'text-muted-foreground'}`}>
        {getSaveStatusText()}
      </p>
    </div>
  );
};

export default EditItemAutoSaveIndicator;
