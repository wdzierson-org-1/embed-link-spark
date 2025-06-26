
import React, { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import LinkPreview from '@/components/LinkPreview';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

interface LinkTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (limit?: number) => string[];
}

const LinkTab = ({ onAddContent, getSuggestedTags }: LinkTabProps) => {
  const [url, setUrl] = useState('');
  const [ogData, setOgData] = useState(null);
  const [isLoadingPreview, setIsLoadingPreview] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { toast } = useToast();
  const { user } = useAuth();

  const isValidUrl = (string: string) => {
    try {
      new URL(string);
      return true;
    } catch (_) {
      return false;
    }
  };

  const downloadAndStoreImage = async (imageUrl: string): Promise<string | null> => {
    if (!user) return null;
    
    try {
      // Fetch the image
      const response = await fetch(imageUrl, { mode: 'cors' });
      if (!response.ok) return null;
      
      const blob = await response.blob();
      const fileExt = imageUrl.split('.').pop()?.split('?')[0] || 'jpg';
      const fileName = `preview_${Date.now()}.${fileExt}`;
      const filePath = `${user.id}/previews/${fileName}`;

      // Upload to Supabase storage
      const { error: uploadError } = await supabase.storage
        .from('stash-media')
        .upload(filePath, blob);

      if (uploadError) {
        console.error('Error uploading preview image:', uploadError);
        return null;
      }

      return filePath;
    } catch (error) {
      console.error('Error downloading and storing image:', error);
      return null;
    }
  };

  const fetchOgData = async (urlToFetch: string) => {
    if (!isValidUrl(urlToFetch)) return;
    
    setIsLoadingPreview(true);
    try {
      // Simple fetch to get basic info - in a real app you'd use a service
      const response = await fetch(urlToFetch, { 
        mode: 'cors',
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; LinkPreview/1.0)'
        }
      });
      
      if (response.ok) {
        const html = await response.text();
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        
        const ogTitle = doc.querySelector('meta[property="og:title"]')?.getAttribute('content') ||
                       doc.querySelector('title')?.textContent;
        const ogDescription = doc.querySelector('meta[property="og:description"]')?.getAttribute('content') ||
                             doc.querySelector('meta[name="description"]')?.getAttribute('content');
        const ogImage = doc.querySelector('meta[property="og:image"]')?.getAttribute('content');
        const ogSiteName = doc.querySelector('meta[property="og:site_name"]')?.getAttribute('content');
        
        setOgData({
          title: ogTitle,
          description: ogDescription,
          image: ogImage,
          url: urlToFetch,
          siteName: ogSiteName
        });
      }
    } catch (error) {
      console.log('Could not fetch preview data:', error);
      // Fallback to basic URL info
      setOgData({
        url: urlToFetch,
        title: urlToFetch
      });
    } finally {
      setIsLoadingPreview(false);
    }
  };

  useEffect(() => {
    const timeoutId = setTimeout(() => {
      if (url && isValidUrl(url)) {
        fetchOgData(url);
      } else {
        setOgData(null);
      }
    }, 1000); // Debounce by 1 second

    return () => clearTimeout(timeoutId);
  }, [url]);

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
      let previewImagePath = null;
      
      // Download and store preview image if available
      if (ogData?.image) {
        previewImagePath = await downloadAndStoreImage(ogData.image);
      }

      await onAddContent('link', {
        url: trimmedUrl,
        title: ogData?.title || trimmedUrl,
        description: ogData?.description || '',
        tags: [],
        ogData: {
          ...ogData,
          storedImagePath: previewImagePath
        }
      });

      // Reset form
      setUrl('');
      setOgData(null);

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
          
          {isLoadingPreview && (
            <div className="text-sm text-gray-500">Loading preview...</div>
          )}
          
          {ogData && <LinkPreview ogData={ogData} />}

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
