
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import TagInput from '@/components/TagInput';
import { useToast } from '@/hooks/use-toast';

interface LinkTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (limit?: number) => string[];
}

const LinkTab = ({ onAddContent, getSuggestedTags }: LinkTabProps) => {
  const [url, setUrl] = useState('');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { toast } = useToast();

  const isValidUrl = (string: string) => {
    try {
      new URL(string);
      return true;
    } catch (_) {
      return false;
    }
  };

  const handleSubmit = async () => {
    const trimmedUrl = url.trim();
    
    if (!trimmedUrl) {
      toast({
        title: "URL required",
        description: "Please enter a URL to save.",
        variant: "destructive",
      });
      return;
    }

    if (!isValidUrl(trimmedUrl)) {
      toast({
        title: "Invalid URL",
        description: "Please enter a valid URL (including http:// or https://).",
        variant: "destructive",
      });
      return;
    }

    setIsSubmitting(true);
    try {
      await onAddContent('link', {
        url: trimmedUrl,
        title: title.trim() || trimmedUrl,
        description: description.trim(),
        tags
      });

      // Reset form
      setUrl('');
      setTitle('');
      setDescription('');
      setTags([]);

      toast({
        title: "Success",
        description: "Link added successfully!",
      });
    } catch (error) {
      console.error('Error adding link:', error);
      toast({
        title: "Error",
        description: "Failed to add link. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleUrlChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    let value = e.target.value;
    
    // Auto-add https:// if no protocol is present
    if (value && !value.startsWith('http://') && !value.startsWith('https://')) {
      if (value.includes('.') && !value.includes(' ')) {
        value = 'https://' + value;
      }
    }
    
    setUrl(value);
  };

  return (
    <Card>
      <CardContent className="pt-6">
        <div className="space-y-4">
          <Input
            placeholder="https://example.com"
            value={url}
            onChange={handleUrlChange}
            type="url"
          />

          <Input
            placeholder="Link title (optional)"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />

          <Textarea
            placeholder="Description (optional)"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={3}
          />

          <div>
            <p className="text-sm font-medium mb-2">Tags</p>
            <TagInput
              tags={tags}
              onTagsChange={setTags}
              suggestions={getSuggestedTags()}
            />
          </div>

          <Button 
            onClick={handleSubmit} 
            disabled={!url.trim() || isSubmitting}
            className="w-full"
          >
            {isSubmitting ? 'Adding Link...' : 'Add Link'}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};

export default LinkTab;
