
import React, { useState } from 'react';
import { Input } from '@/components/ui/input';
import { useToast } from '@/hooks/use-toast';

interface EditItemTitleSectionProps {
  title: string;
  onTitleChange: (title: string) => void;
  onSave: (title: string) => Promise<void>;
}

const EditItemTitleSection = ({ title, onTitleChange, onSave }: EditItemTitleSectionProps) => {
  const [isEditing, setIsEditing] = useState(false);
  const { toast } = useToast();

  const handleSave = async () => {
    try {
      await onSave(title.trim() || '');
      setIsEditing(false);
      toast({
        title: "Success",
        description: "Title updated",
      });
    } catch (error) {
      console.error('Error saving title:', error);
      toast({
        title: "Error",
        description: "Failed to update title",
        variant: "destructive",
      });
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleSave();
    }
  };

  if (isEditing) {
    return (
      <div className="relative" style={{ marginLeft: '-10px' }}>
        <Input
          value={title}
          onChange={(e) => onTitleChange(e.target.value)}
          onKeyPress={handleKeyPress}
          onBlur={handleSave}
          className="text-2xl font-bold border-none p-0 shadow-none focus-visible:ring-0 h-auto resize-none ml-2"
          placeholder="Enter title..."
          autoFocus
          style={{ fontSize: '1.5rem', lineHeight: '2rem' }}
        />
      </div>
    );
  }

  return (
    <h1 
      className="text-2xl font-bold cursor-pointer hover:bg-yellow-50 p-2 rounded transition-colors"
      onClick={() => setIsEditing(true)}
      title="Click to edit title"
      style={{ marginLeft: '-10px' }}
    >
      {title || 'Untitled Note'}
    </h1>
  );
};

export default EditItemTitleSection;
