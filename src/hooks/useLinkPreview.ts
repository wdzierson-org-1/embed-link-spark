
import { useState, useEffect } from 'react';
import { isValidUrl, extractMetaFromHtml, fetchWithProxy } from '@/utils/urlMetadata';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  url: string;
  siteName?: string;
}

export const useLinkPreview = (url: string) => {
  const [ogData, setOgData] = useState<OpenGraphData | null>(null);
  const [isLoadingPreview, setIsLoadingPreview] = useState(false);

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

  return { ogData, isLoadingPreview };
};
