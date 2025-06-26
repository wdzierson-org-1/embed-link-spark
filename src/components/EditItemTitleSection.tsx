
import React, { useState } from 'react';
import { Input } from '@/components/ui/input';
import { Edit } from 'lucide-react';
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
      <div className="relative">
        <Input
          value={title}
          onChange={(e) => onTitleChange(e.target.value)}
          onKeyPress={handleKeyPress}
          onBlur={handleSave}
          className="text-2xl font-bold border-none p-0 shadow-none focus-visible:ring-0 h-auto resize-none"
          placeholder="Enter title..."
          autoFocus
          style={{ fontSize: '1.5rem', lineHeight: '2rem' }}
        />
      </div>
    );
  }

  return (
    <h1 
      className="text-2xl font-bold cursor-pointer hover:bg-yellow-50 p-2 rounded transition-colors flex items-center"
      onClick={() => setIsEditing(true)}
      title="Click to edit title"
    >
      <span className="flex-1">{title || 'Untitled Note'}</span>
      <Edit className="ml-2 h-4 w-4 opacity-50 flex-shrink-0" />
    </h1>
  );
};

export default EditItemTitleSection;
