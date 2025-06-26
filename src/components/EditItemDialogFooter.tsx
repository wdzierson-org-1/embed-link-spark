
import React from 'react';
import { Button } from '@/components/ui/button';

interface EditItemDialogFooterProps {
  onCancel: () => void;
  onSave: () => void;
  isSaving: boolean;
}

const EditItemDialogFooter = ({ onCancel, onSave, isSaving }: EditItemDialogFooterProps) => {
  return (
    <div className="flex justify-end gap-2 pt-4 border-t">
      <Button variant="outline" onClick={onCancel}>
        Cancel
      </Button>
      <Button onClick={onSave} disabled={isSaving}>
        {isSaving ? 'Saving...' : 'Save Changes'}
      </Button>
    </div>
  );
};

export default EditItemDialogFooter;
