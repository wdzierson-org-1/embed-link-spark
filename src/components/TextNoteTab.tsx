
import React, { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { FileText } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';

interface TextNoteTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
}

const TextNoteTab = ({ onAddContent }: TextNoteTabProps) => {
  const [textInput, setTextInput] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const { toast } = useToast();

  const handleSubmit = async () => {
    if (!textInput.trim()) return;
    
    setIsProcessing(true);
    try {
      await onAddContent('text', {
        content: textInput,
        title: textInput.slice(0, 50) + (textInput.length > 50 ? '...' : '')
      });
      
      setTextInput('');
      
      toast({
        title: "Success",
        description: "Text note added to your stash!",
      });
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to add text note",
        variant: "destructive",
      });
    } finally {
      setIsProcessing(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      handleSubmit();
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <FileText className="h-5 w-5" />
          <span>Add Text Note</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <Textarea
            placeholder="Type your text note here..."
            value={textInput}
            onChange={(e) => setTextInput(e.target.value)}
            onKeyDown={handleKeyPress}
            disabled={isProcessing}
            className="min-h-[120px] resize-none"
          />
          <p className="text-xs text-muted-foreground mt-2">
            Tip: Press Cmd/Ctrl + Enter to save quickly
          </p>
        </div>

        <Button
          onClick={handleSubmit}
          disabled={isProcessing || !textInput.trim()}
          className="w-full"
        >
          {isProcessing ? (
            'Processing...'
          ) : (
            <>
              <FileText className="h-4 w-4 mr-2" />
              Save Text Note
            </>
          )}
        </Button>
      </CardContent>
    </Card>
  );
};

export default TextNoteTab;
