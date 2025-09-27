
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import LinkPreview from '@/components/LinkPreview';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';
import { useLinkPreview } from '@/hooks/useLinkPreview';
import { isValidUrl } from '@/utils/urlMetadata';

interface LinkTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (limit?: number) => string[];
}

const LinkTab = ({ onAddContent, getSuggestedTags }: LinkTabProps) => {
  const [url, setUrl] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { toast } = useToast();
  const { user } = useAuth();
  const { ogData, isLoadingPreview } = useLinkPreview(url);

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
      // Store link data in proper structure
      await onAddContent('link', {
        url: trimmedUrl,
        title: ogData?.title || trimmedUrl,
        description: ogData?.description || '',
        content: '',
        tags: [],
        // We no longer download client-side; rely on server-side caching when available
        previewImagePath: undefined
      });

      // Reset form
      setUrl('');

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
    
    if (value && !value.startsWith('http://') && !value.startsWith('https://')) {
      if (value.includes('.') && !value.includes(' ')) {
        value = 'https://' + value;
      }
    }
    
    setUrl(value);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      e.preventDefault();
      handleSubmit();
    }
  };

  const hasContent = url.trim().length > 0;

  return (
    <Card className="bg-gray-50 border-0">
      <CardContent className="pt-6">
        <div className="space-y-4">
          <Input
            placeholder="https://example.com"
            value={url}
            onChange={handleUrlChange}
            onKeyDown={handleKeyDown}
            type="url"
            className="bg-white border-0"
          />
          
          {isLoadingPreview && (
            <div className="text-sm text-gray-500">Loading preview...</div>
          )}
          
          {ogData && <LinkPreview ogData={ogData} />}

          <div className="text-xs text-gray-500">
            Press cmd + enter to save quickly
          </div>

          {hasContent && (
            <Button 
              onClick={handleSubmit} 
              disabled={isSubmitting}
              className="w-full"
            >
              {isSubmitting ? 'Adding Link...' : 'Add Link'}
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
};

export default LinkTab;
