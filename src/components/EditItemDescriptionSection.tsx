
import React, { useState } from 'react';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { RefreshCw, Trash2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { generateDescription } from '@/utils/aiOperations';

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
  onSave 
}: EditItemDescriptionSectionProps) => {
  const [isRefreshing, setIsRefreshing] = useState(false);
  const { toast } = useToast();

  const handleRefreshDescription = async () => {
    setIsRefreshing(true);
    try {
      const newDescription = await generateDescription('text', {
        content: content,
        title: title
      });
      
      if (newDescription) {
        onDescriptionChange(newDescription);
        await onSave(newDescription);
        toast({
          title: "Success",
          description: "Description refreshed",
        });
      }
    } catch (error) {
      console.error('Error refreshing description:', error);
      toast({
        title: "Error",
        description: "Failed to refresh description",
        variant: "destructive",
      });
    } finally {
      setIsRefreshing(false);
    }
  };

  const handleRemoveDescription = async () => {
    try {
      onDescriptionChange('');
      await onSave('');
      toast({
        title: "Success",
        description: "Description removed",
      });
    } catch (error) {
      console.error('Error removing description:', error);
      toast({
        title: "Error",
        description: "Failed to remove description",
        variant: "destructive",
      });
    }
  };

  if (!description) return null;

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <Label className="text-base font-medium">AI Summary</Label>
        <div className="flex space-x-2">
          <Button
            variant="outline"
            size="sm"
            onClick={handleRefreshDescription}
            disabled={isRefreshing}
          >
            <RefreshCw className={`h-4 w-4 mr-1 ${isRefreshing ? 'animate-spin' : ''}`} />
            Refresh
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={handleRemoveDescription}
          >
            <Trash2 className="h-4 w-4 mr-1" />
            Remove
          </Button>
        </div>
      </div>
      <Card>
        <CardContent className="p-4">
          <p className="text-sm text-muted-foreground">{description}</p>
        </CardContent>
      </Card>
    </div>
  );
};

export default EditItemDescriptionSection;
