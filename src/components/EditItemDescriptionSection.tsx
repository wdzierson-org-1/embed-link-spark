
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { RefreshCcw } from 'lucide-react';
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
        // Auto-save the generated description
        await onSave(data.description);
        toast({
          title: "Summary generated",
          description: "AI summary has been generated and saved automatically.",
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

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild>
              <label className="text-sm font-medium text-muted-foreground cursor-help">
                AI Summary
              </label>
            </TooltipTrigger>
            <TooltipContent>
              <p>This content is used to help train the AI assistant on your content</p>
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>
        <Button
          variant="outline"
          size="sm"
          onClick={handleGenerateDescription}
          disabled={isGenerating || (!content?.trim() && !title?.trim())}
          className="h-7 w-7 p-0"
        >
          <RefreshCcw className={`h-3 w-3 ${isGenerating ? 'animate-spin' : ''}`} />
        </Button>
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
