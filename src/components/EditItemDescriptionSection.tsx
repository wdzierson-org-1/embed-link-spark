
import React, { useState, useRef, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Wand2, Edit2, Check, X } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';

interface EditItemDescriptionSectionProps {
  itemId: string;
  description: string;
  content: string;
  title: string;
  onDescriptionChange: (description: string) => void;
  onSave: (description: string) => Promise<void>;
}

const EditItemDescriptionSection = ({
  itemId,
  description,
  content,
  title,
  onDescriptionChange,
  onSave,
}: EditItemDescriptionSectionProps) => {
  const [isEditing, setIsEditing] = useState(false);
  const [tempDescription, setTempDescription] = useState(description);
  const [isGenerating, setIsGenerating] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const { toast } = useToast();

  useEffect(() => {
    setTempDescription(description);
  }, [description]);

  useEffect(() => {
    if (isEditing && textareaRef.current) {
      textareaRef.current.focus();
      textareaRef.current.select();
    }
  }, [isEditing]);

  const handleEdit = () => {
    setTempDescription(description);
    setIsEditing(true);
  };

  const handleSave = async () => {
    try {
      await onSave(tempDescription);
      setIsEditing(false);
    } catch (error) {
      console.error('Error saving description:', error);
      toast({
        title: "Error",
        description: "Failed to save description",
        variant: "destructive",
      });
    }
  };

  const handleCancel = () => {
    setTempDescription(description);
    setIsEditing(false);
  };

  const generateDescription = async () => {
    if (!itemId || isGenerating) return;

    setIsGenerating(true);
    try {
      const { data, error } = await supabase.functions.invoke('generate-description', {
        body: { 
          content: content || title,
          itemId 
        }
      });

      if (error) throw error;
      
      if (data?.description) {
        onDescriptionChange(data.description);
        await onSave(data.description);
        toast({
          title: "Success",
          description: "AI summary generated successfully",
        });
      }
    } catch (error) {
      console.error('Error generating description:', error);
      toast({
        title: "Error",
        description: "Failed to generate AI summary",
        variant: "destructive",
      });
    } finally {
      setIsGenerating(false);
    }
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-muted-foreground">AI Summary</label>
        <div className="flex items-center gap-2">
          {!isEditing && (
            <>
              <Button
                variant="ghost"
                size="sm"
                onClick={generateDescription}
                disabled={isGenerating}
                className="h-auto p-1 text-xs"
              >
                <Wand2 className="h-3 w-3 mr-1" />
                {isGenerating ? 'Generating...' : 'Generate'}
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={handleEdit}
                className="h-auto p-1 text-xs"
              >
                <Edit2 className="h-3 w-3 mr-1" />
                Edit
              </Button>
            </>
          )}
          {isEditing && (
            <>
              <Button
                variant="ghost"
                size="sm"
                onClick={handleSave}
                className="h-auto p-1 text-xs text-green-600 hover:text-green-700"
              >
                <Check className="h-3 w-3" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={handleCancel}
                className="h-auto p-1 text-xs text-red-600 hover:text-red-700"
              >
                <X className="h-3 w-3" />
              </Button>
            </>
          )}
        </div>
      </div>

      {isEditing ? (
        <Textarea
          ref={textareaRef}
          value={tempDescription}
          onChange={(e) => setTempDescription(e.target.value)}
          className="min-h-[80px] resize-none"
          placeholder="Enter AI summary..."
        />
      ) : (
        <div className="text-sm text-muted-foreground bg-muted/30 rounded-md p-3 min-h-[80px] border border-dashed">
          {description || (
            <span className="italic">
              No AI summary yet. Click "Generate" to create one automatically.
            </span>
          )}
        </div>
      )}
    </div>
  );
};

export default EditItemDescriptionSection;
