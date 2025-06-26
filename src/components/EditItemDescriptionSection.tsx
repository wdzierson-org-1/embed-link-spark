
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Sparkles, Save } from 'lucide-react';
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
  const [isGenerating, setIsGenerating] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const { toast } = useToast();

  const handleGenerateDescription = async () => {
    if (!content?.trim() && !title?.trim()) {
      toast({
        title: "No content to summarize",
        description: "Add some content or title first to generate a summary.",
        variant: "destructive",
      });
      return;
    }

    setIsGenerating(true);
    try {
      const { data, error } = await supabase.functions.invoke('generate-description', {
        body: { 
          content: content || '', 
          title: title || '',
          itemId 
        }
      });

      if (error) throw error;

      if (data?.description) {
        onDescriptionChange(data.description);
        toast({
          title: "Summary generated",
          description: "AI summary has been generated successfully.",
        });
      }
    } catch (error) {
      console.error('Error generating description:', error);
      toast({
        title: "Error",
        description: "Failed to generate summary. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsGenerating(false);
    }
  };

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await onSave(description);
      toast({
        title: "Success",
        description: "Summary saved successfully.",
      });
    } catch (error) {
      console.error('Error saving description:', error);
      toast({
        title: "Error",
        description: "Failed to save summary. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-muted-foreground">AI Summary</label>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={handleGenerateDescription}
            disabled={isGenerating || (!content?.trim() && !title?.trim())}
            className="h-7 px-2 text-xs"
          >
            <Sparkles className="h-3 w-3 mr-1" />
            {isGenerating ? 'Generating...' : 'Generate'}
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={handleSave}
            disabled={isSaving || !description?.trim()}
            className="h-7 px-2 text-xs"
          >
            <Save className="h-3 w-3 mr-1" />
            {isSaving ? 'Saving...' : 'Save'}
          </Button>
        </div>
      </div>
      <Textarea
        value={description}
        onChange={(e) => onDescriptionChange(e.target.value)}
        placeholder="Enter a summary or description..."
        className="min-h-[100px] resize-none"
      />
    </div>
  );
};

export default EditItemDescriptionSection;
