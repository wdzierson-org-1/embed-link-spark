
import React, { useState } from 'react';
import { Input } from '@/components/ui/input';

interface EditItemTitleSectionProps {
  title: string;
  onTitleChange: (title: string) => void;
  onSave: (title: string) => Promise<void>;
}

const EditItemTitleSection = ({ title, onTitleChange, onSave }: EditItemTitleSectionProps) => {
  const [isEditing, setIsEditing] = useState(false);
  const [isFlashing, setIsFlashing] = useState(false);

  const handleSave = async () => {
    try {
      await onSave(title.trim() || '');
      setIsEditing(false);
      
      // Trigger flash animation instead of toast
      setIsFlashing(true);
      setTimeout(() => setIsFlashing(false), 600); // Animation duration
    } catch (error) {
      console.error('Error saving title:', error);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleSave();
    }
  };

  if (isEditing) {
    return (
      <div className="relative" style={{ marginLeft: '-8px' }}>
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
    <>
      <style>
        {`
          @keyframes flash {
            0% { background-color: transparent; }
            16.66% { background-color: #fef3c7; }
            33.33% { background-color: #ddd6fe; }
            50% { background-color: #bfdbfe; }
            66.66% { background-color: #bbf7d0; }
            83.33% { background-color: #fed7d7; }
            100% { background-color: transparent; }
          }
        `}
      </style>
      <h1 
        className="text-2xl font-bold cursor-pointer hover:bg-yellow-50 p-2 rounded transition-colors"
        onClick={() => setIsEditing(true)}
        title="Click to edit title"
        style={{ 
          marginLeft: '-8px',
          ...(isFlashing && {
            animation: 'flash 0.6s ease-in-out'
          })
        }}
      >
        {title || 'Untitled Note'}
      </h1>
    </>
  );
};

export default EditItemTitleSection;
