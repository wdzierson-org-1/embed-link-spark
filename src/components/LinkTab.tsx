
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
      const response = await fetch(imageUrl, { mode: 'cors' });
      if (!response.ok) return null;
      
      const blob = await response.blob();
      const fileExt = imageUrl.split('.').pop()?.split('?')[0] || 'jpg';
      const fileName = `preview_${Date.now()}.${fileExt}`;
      const filePath = `${user.id}/previews/${fileName}`;

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

  const parseMetaContent = (html: string, property: string): string | null => {
    // Try multiple variations of meta tag formats
    const patterns = [
      new RegExp(`<meta\\s+property=["']${property}["']\\s+content=["']([^"']+)["']`, 'i'),
      new RegExp(`<meta\\s+content=["']([^"']+)["']\\s+property=["']${property}["']`, 'i'),
      new RegExp(`<meta\\s+name=["']${property}["']\\s+content=["']([^"']+)["']`, 'i'),
      new RegExp(`<meta\\s+content=["']([^"']+)["']\\s+name=["']${property}["']`, 'i'),
    ];

    for (const pattern of patterns) {
      const match = html.match(pattern);
      if (match && match[1]) {
        return match[1];
      }
    }
    return null;
  };

  const extractMetaFromHtml = (html: string) => {
    // Clean up HTML to make parsing more reliable
    const cleanHtml = html.replace(/\n/g, ' ').replace(/\s+/g, ' ');
    
    // Extract title
    const titleMatch = cleanHtml.match(/<title[^>]*>([^<]+)<\/title>/i);
    const title = parseMetaContent(cleanHtml, 'og:title') || 
                 parseMetaContent(cleanHtml, 'twitter:title') || 
                 (titleMatch ? titleMatch[1] : null);

    // Extract description
    const description = parseMetaContent(cleanHtml, 'og:description') || 
                       parseMetaContent(cleanHtml, 'twitter:description') || 
                       parseMetaContent(cleanHtml, 'description');

    // Extract image
    const image = parseMetaContent(cleanHtml, 'og:image') || 
                 parseMetaContent(cleanHtml, 'twitter:image');

    // Extract site name
    const siteName = parseMetaContent(cleanHtml, 'og:site_name') || 
                    parseMetaContent(cleanHtml, 'twitter:domain');

    return {
      title: title?.trim(),
      description: description?.trim(),
      image: image?.trim(),
      siteName: siteName?.trim()
    };
  };

  const fetchWithProxy = async (urlToFetch: string) => {
    // Try multiple proxy services for better reliability
    const proxyServices = [
      `https://api.allorigins.win/get?url=${encodeURIComponent(urlToFetch)}`,
      `https://cors-anywhere.herokuapp.com/${urlToFetch}`,
      `https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(urlToFetch)}`
    ];

    for (const proxyUrl of proxyServices) {
      try {
        const response = await fetch(proxyUrl, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; StashBot/1.0)',
          }
        });
        
        if (response.ok) {
          const data = await response.json();
          // Handle different proxy response formats
          const html = data.contents || data.content || data;
          return typeof html === 'string' ? html : null;
        }
      } catch (error) {
        console.log(`Proxy ${proxyUrl} failed:`, error);
        continue;
      }
    }
    return null;
  };

  const fetchOgData = async (urlToFetch: string) => {
    if (!isValidUrl(urlToFetch)) return;
    
    setIsLoadingPreview(true);
    try {
      let html = null;
      
      // Try direct fetch first (works for CORS-enabled sites)
      try {
        const response = await fetch(urlToFetch, { 
          mode: 'cors',
          headers: {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
          }
        });
        
        if (response.ok) {
          html = await response.text();
        }
      } catch (directFetchError) {
        console.log('Direct fetch failed, trying proxy services...');
      }

      // If direct fetch fails, try proxy services
      if (!html) {
        html = await fetchWithProxy(urlToFetch);
      }

      if (html) {
        const metaData = extractMetaFromHtml(html);
        
        // Resolve relative URLs for images
        let imageUrl = metaData.image;
        if (imageUrl && !imageUrl.startsWith('http')) {
          const baseUrl = new URL(urlToFetch);
          if (imageUrl.startsWith('//')) {
            imageUrl = baseUrl.protocol + imageUrl;
          } else if (imageUrl.startsWith('/')) {
            imageUrl = baseUrl.origin + imageUrl;
          } else {
            imageUrl = new URL(imageUrl, urlToFetch).toString();
          }
        }
        
        setOgData({
          title: metaData.title,
          description: metaData.description,
          image: imageUrl,
          url: urlToFetch,
          siteName: metaData.siteName
        });
      } else {
        // Fallback: create basic data from URL
        const domain = new URL(urlToFetch).hostname;
        setOgData({
          url: urlToFetch,
          title: domain,
          siteName: domain
        });
      }
    } catch (error) {
      console.log('All metadata extraction methods failed:', error);
      // Create minimal fallback data
      try {
        const domain = new URL(urlToFetch).hostname;
        setOgData({
          url: urlToFetch,
          title: domain,
          siteName: domain
        });
      } catch (urlError) {
        setOgData({
          url: urlToFetch,
          title: urlToFetch
        });
      }
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
    }, 1000);

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
        try {
          previewImagePath = await downloadAndStoreImage(ogData.image);
        } catch (imageError) {
          console.log('Failed to download preview image:', imageError);
          // Continue without image - don't fail the entire operation
        }
      }

      // Store link data in proper structure
      await onAddContent('link', {
        url: trimmedUrl,
        title: ogData?.title || trimmedUrl,
        description: ogData?.description || '',
        content: '',
        tags: [],
        // Store preview image path for retrieval
        previewImagePath: previewImagePath
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
