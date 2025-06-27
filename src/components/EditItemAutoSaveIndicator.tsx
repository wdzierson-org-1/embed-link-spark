
import React from 'react';

interface EditItemAutoSaveIndicatorProps {
  saveStatus: 'idle' | 'saving' | 'saved';
  lastSaved?: Date | null;
}

const EditItemAutoSaveIndicator = ({ saveStatus, lastSaved }: EditItemAutoSaveIndicatorProps) => {
  const getSaveStatusText = () => {
    switch (saveStatus) {
      case 'saving':
        return 'Saving changes...';
      case 'saved':
        return lastSaved 
          ? `Last saved at ${lastSaved.toLocaleTimeString()}`
          : 'All changes saved';
      default:
        return 'Changes saved automatically';
    }
  };

  const getStatusColor = () => {
    switch (saveStatus) {
      case 'saving':
        return 'text-blue-600';
      case 'saved':
        return 'text-green-600';
      default:
        return 'text-muted-foreground';
    }
  };

  return (
    <div className="px-6 py-3 border-t bg-muted/30 flex-shrink-0">
      <div className="flex items-center gap-2">
        {saveStatus === 'saving' && (
          <div className="animate-spin rounded-full h-3 w-3 border-b-2 border-current"></div>
        )}
        {saveStatus === 'saved' && (
          <div className="rounded-full h-3 w-3 bg-green-500"></div>
        )}
        <p className={`text-xs ${getStatusColor()}`}>
          {getSaveStatusText()}
        </p>
      </div>
    </div>
  );
};

export default EditItemAutoSaveIndicator;
