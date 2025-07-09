
import { useState, useEffect } from 'react';
import { isValidUrl } from '@/utils/urlMetadata';
import { supabase } from '@/integrations/supabase/client';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  url: string;
  siteName?: string;
  videoUrl?: string;
}

export const useLinkPreview = (url: string) => {
  const [ogData, setOgData] = useState<OpenGraphData | null>(null);
  const [isLoadingPreview, setIsLoadingPreview] = useState(false);

  const fetchOgData = async (urlToFetch: string) => {
    if (!isValidUrl(urlToFetch)) return;
    
    setIsLoadingPreview(true);
    try {
      const { data, error } = await supabase.functions.invoke('extract-link-metadata', {
        body: { url: urlToFetch }
      });

      if (error) {
        console.error('Edge function error:', error);
        throw new Error(error.message);
      }

      if (data && data.success) {
        setOgData({
          title: data.title,
          description: data.description,
          image: data.image,
          url: urlToFetch,
          siteName: data.siteName,
          videoUrl: data.videoUrl
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
      console.error('Failed to extract metadata:', error);
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

  return { ogData, isLoadingPreview };
};
