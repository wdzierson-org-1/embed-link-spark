
import { useState, useEffect } from 'react';
import { isValidUrl } from '@/utils/urlMetadata';
import { supabase } from '@/integrations/supabase/client';
import { downloadAndStoreImage } from '@/utils/linkImageStorage';
import { useAuth } from '@/hooks/useAuth';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  previewImageUrl?: string; // For stored image URLs that can be displayed
  url: string;
  siteName?: string;
  videoUrl?: string;
}

export const useLinkPreview = (url: string) => {
  const [ogData, setOgData] = useState<OpenGraphData | null>(null);
  const [isLoadingPreview, setIsLoadingPreview] = useState(false);
  const { user } = useAuth();

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
        const ogDataResult: OpenGraphData = {
          title: data.title,
          description: data.description,
          image: data.image,
          url: urlToFetch,
          siteName: data.siteName,
          videoUrl: data.videoUrl
        };

        console.log('🔄 Setting initial OG data:', ogDataResult);
        // Set initial data first
        setOgData(ogDataResult);

        // Try to download and store the image for preview if available
        if (data.image && user) {
          console.log('📸 Attempting to download image:', data.image);
          try {
            // Add timeout for image download
            const downloadPromise = downloadAndStoreImage(data.image, user.id);
            const timeoutPromise = new Promise<string | null>((_, reject) => 
              setTimeout(() => reject(new Error('Download timeout')), 10000)
            );
            
            const previewImagePath = await Promise.race([downloadPromise, timeoutPromise]);
            
            if (previewImagePath) {
              console.log('✅ Image downloaded successfully, path:', previewImagePath);
              const { data: urlData } = supabase.storage.from('stash-media').getPublicUrl(previewImagePath);
              console.log('🔗 Generated public URL:', urlData.publicUrl);
              
              // Update the data with the preview image URL
              setOgData(prev => {
                if (prev) {
                  const updated = { ...prev, previewImageUrl: urlData.publicUrl };
                  console.log('🔄 Updating OG data with preview image:', updated);
                  return updated;
                }
                return null;
              });
            } else {
              console.warn('⚠️ Image download returned null path');
              // Fallback: keep original image URL for direct display attempt
            }
          } catch (error) {
            console.error('❌ Failed to download preview image:', error);
            console.log('🔄 Falling back to original image URL for direct display');
            // Keep the original image URL as fallback - don't change ogData
          }
        } else if (data.image && !user) {
          console.log('👤 No user logged in, keeping original image URL');
        }
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
