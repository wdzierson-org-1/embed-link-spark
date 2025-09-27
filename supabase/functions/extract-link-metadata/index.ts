import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface MetadataResult {
  title?: string;
  description?: string;
  image?: string;
  previewImagePath?: string;
  previewImagePublicUrl?: string;
  siteName?: string;
  url: string;
  success: boolean;
  error?: string;
  videoUrl?: string;
}

// Enhanced User-Agent rotation for different platforms
const getUserAgent = (url: string): string => {
  const domain = new URL(url).hostname.toLowerCase();
  
  if (domain.includes('linkedin.com')) {
    return 'LinkedInBot/1.0 (compatible; Mozilla/5.0; +https://www.linkedin.com/)'
  }
  if (domain.includes('twitter.com') || domain.includes('x.com')) {
    return 'Twitterbot/1.0'
  }
  if (domain.includes('facebook.com')) {
    return 'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)'
  }
  if (domain.includes('instagram.com')) {
    return 'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)'
  }
  if (domain.includes('pinterest.com')) {
    return 'Pinterest/0.2 (+https://www.pinterest.com/)'
  }
  if (domain.includes('reddit.com')) {
    return 'RedditBot/1.0'
  }
  if (domain.includes('github.com')) {
    return 'GitHubBot/1.0'
  }
  if (domain.includes('medium.com') || domain.includes('substack.com')) {
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  }
  
  // Default modern browser UA
  return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}

// Enhanced meta content parsing with better patterns
const parseMetaContent = (html: string, property: string): string | null => {
  const patterns = [
    new RegExp(`<meta[^>]*property=["']${property}["'][^>]*content=["']([^"']*?)["']`, 'i'),
    new RegExp(`<meta[^>]*content=["']([^"']*?)["'][^>]*property=["']${property}["']`, 'i'),
    new RegExp(`<meta[^>]*name=["']${property}["'][^>]*content=["']([^"']*?)["']`, 'i'),
    new RegExp(`<meta[^>]*content=["']([^"']*?)["'][^>]*name=["']${property}["']`, 'i'),
    // Handle unquoted attributes
    new RegExp(`<meta[^>]*property=${property}[^>]*content=["']([^"']*?)["']`, 'i'),
    new RegExp(`<meta[^>]*name=${property}[^>]*content=["']([^"']*?)["']`, 'i'),
  ];

  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match && match[1]) {
      return match[1].replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').trim();
    }
  }
  return null;
};

// Parse JSON-LD structured data
const parseJsonLd = (html: string): Partial<MetadataResult> => {
  const jsonLdPattern = /<script[^>]*type=["']application\/ld\+json["'][^>]*>(.*?)<\/script>/gi;
  let match;
  
  while ((match = jsonLdPattern.exec(html)) !== null) {
    try {
      const data = JSON.parse(match[1]);
      const result: Partial<MetadataResult> = {};
      
      if (data.name) result.title = data.name;
      if (data.headline) result.title = data.headline;
      if (data.description) result.description = data.description;
      if (data.image) {
        if (typeof data.image === 'string') {
          result.image = data.image;
        } else if (data.image.url) {
          result.image = data.image.url;
        } else if (Array.isArray(data.image) && data.image[0]) {
          result.image = typeof data.image[0] === 'string' ? data.image[0] : data.image[0].url;
        }
      }
      
      if (Object.keys(result).length > 0) return result;
    } catch (e) {
      console.log('Failed to parse JSON-LD:', e);
    }
  }
  
  return {};
};

// Extract fallback image from page content
const extractFallbackImage = (html: string, baseUrl: string): string | null => {
  const imgPatterns = [
    /<img[^>]*src=["']([^"']+)["'][^>]*>/gi,
    /<img[^>]*data-src=["']([^"']+)["'][^>]*>/gi,
  ];
  
  for (const pattern of imgPatterns) {
    let match;
    while ((match = pattern.exec(html)) !== null) {
      const src = match[1];
      if (src && !src.includes('data:') && !src.includes('placeholder') && !src.includes('blank')) {
        try {
          const imageUrl = new URL(src, baseUrl).toString();
          if (imageUrl.match(/\.(jpg|jpeg|png|webp|gif)(\?|$)/i)) {
            return imageUrl;
          }
        } catch (e) {
          continue;
        }
      }
    }
  }
  
  return null;
};

// Extract YouTube metadata using oEmbed API
const extractYouTubeMetadata = async (url: string): Promise<Partial<MetadataResult> | null> => {
  try {
    // Extract video ID from various YouTube URL formats
    const videoIdMatch = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/|m\.youtube\.com\/watch\?v=)([^&\n?#]+)/);
    if (!videoIdMatch) return null;
    
    const videoId = videoIdMatch[1];
    console.log(`Extracting YouTube metadata for video ID: ${videoId}`);
    
    // Use YouTube oEmbed API for reliable metadata
    const oembedUrl = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${videoId}&format=json`;
    
    const response = await fetch(oembedUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; LinkPreview/1.0)'
      },
      signal: AbortSignal.timeout(5000)
    });
    
    if (response.ok) {
      const data = await response.json();
      console.log('YouTube oEmbed data:', data);
      
      return {
        title: data.title,
        description: `Watch "${data.title}" by ${data.author_name} on YouTube`,
        image: data.thumbnail_url,
        siteName: 'YouTube',
        videoUrl: `https://www.youtube.com/watch?v=${videoId}`,
        url: url.replace('m.youtube.com', 'www.youtube.com')
      };
    }
  } catch (error) {
    console.error('YouTube oEmbed failed:', error);
  }
  return null;
};

// Extract metadata for other video platforms
const extractVideoMetadata = async (url: string): Promise<Partial<MetadataResult> | null> => {
  try {
    // Vimeo
    if (url.includes('vimeo.com')) {
      const videoIdMatch = url.match(/vimeo\.com\/(\d+)/);
      if (videoIdMatch) {
        const oembedUrl = `https://vimeo.com/api/oembed.json?url=${encodeURIComponent(url)}`;
        const response = await fetch(oembedUrl, { signal: AbortSignal.timeout(5000) });
        if (response.ok) {
          const data = await response.json();
          return {
            title: data.title,
            description: data.description,
            image: data.thumbnail_url,
            siteName: 'Vimeo',
            videoUrl: url
          };
        }
      }
    }
    
    // TikTok
    if (url.includes('tiktok.com')) {
      const oembedUrl = `https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`;
      try {
        const response = await fetch(oembedUrl, { signal: AbortSignal.timeout(5000) });
        if (response.ok) {
          const data = await response.json();
          return {
            title: data.title,
            description: data.author_name ? `Video by ${data.author_name} on TikTok` : 'TikTok Video',
            image: data.thumbnail_url,
            siteName: 'TikTok',
            videoUrl: url
          };
        }
      } catch (e) {
        console.log('TikTok oEmbed failed:', e);
      }
    }
  } catch (error) {
    console.error('Video metadata extraction failed:', error);
  }
  return null;
};

// Extract metadata for social media and other platforms
const extractSocialMetadata = async (url: string): Promise<Partial<MetadataResult> | null> => {
  try {
    // Twitter/X posts
    if ((url.includes('twitter.com') || url.includes('x.com')) && url.includes('/status/')) {
      // Twitter doesn't have public oEmbed anymore, but we can extract from URL structure
      const tweetMatch = url.match(/(?:twitter\.com|x\.com)\/(\w+)\/status\/(\d+)/);
      if (tweetMatch) {
        const username = tweetMatch[1];
        return {
          title: `Tweet by @${username}`,
          description: `View this tweet on ${url.includes('x.com') ? 'X' : 'Twitter'}`,
          siteName: url.includes('x.com') ? 'X' : 'Twitter',
          url
        };
      }
    }

    // LinkedIn posts/articles
    if (url.includes('linkedin.com')) {
      // Try LinkedIn oEmbed (may work for some content)
      try {
        const oembedUrl = `https://www.linkedin.com/embed/feed/update/urn:li:share:${url}`;
        // Note: LinkedIn oEmbed is limited, so we'll rely on HTML parsing mostly
      } catch (e) {
        console.log('LinkedIn specific extraction not available');
      }
    }

    // Reddit posts
    if (url.includes('reddit.com') && (url.includes('/r/') || url.includes('/comments/'))) {
      // Add .json to Reddit URLs for API access
      const jsonUrl = url.replace(/\/$/, '') + '.json';
      try {
        const response = await fetch(jsonUrl, { 
          signal: AbortSignal.timeout(5000),
          headers: { 'User-Agent': 'RedditBot/1.0' }
        });
        if (response.ok) {
          const data = await response.json();
          const post = data[0]?.data?.children?.[0]?.data;
          if (post) {
            return {
              title: post.title,
              description: `${post.ups} upvotes • r/${post.subreddit} • Reddit`,
              image: post.thumbnail && post.thumbnail !== 'self' ? post.thumbnail : null,
              siteName: 'Reddit',
              url
            };
          }
        }
      } catch (e) {
        console.log('Reddit API extraction failed:', e);
      }
    }

    // GitHub repositories/issues
    if (url.includes('github.com')) {
      const repoMatch = url.match(/github\.com\/([^\/]+)\/([^\/]+)/);
      if (repoMatch) {
        const [, owner, repo] = repoMatch;
        try {
          const apiUrl = `https://api.github.com/repos/${owner}/${repo}`;
          const response = await fetch(apiUrl, { 
            signal: AbortSignal.timeout(5000),
            headers: { 'User-Agent': 'GitHubBot/1.0' }
          });
          if (response.ok) {
            const data = await response.json();
            return {
              title: `${data.full_name}`,
              description: data.description || `GitHub repository by ${owner}`,
              image: data.owner.avatar_url,
              siteName: 'GitHub',
              url
            };
          }
        } catch (e) {
          console.log('GitHub API extraction failed:', e);
        }
      }
    }
    
  } catch (error) {
    console.error('Social metadata extraction failed:', error);
  }
  return null;
};

const extractMetaFromHtml = async (html: string, originalUrl: string) => {
  const cleanHtml = html.replace(/\n/g, ' ').replace(/\s+/g, ' ');
  
  // Try platform-specific extraction first for better results
  if (originalUrl.includes('youtube.com') || originalUrl.includes('youtu.be')) {
    const youtubeData = await extractYouTubeMetadata(originalUrl);
    if (youtubeData && youtubeData.title) {
      console.log('Using YouTube-specific metadata');
      return youtubeData;
    }
  }
  
  // Try other video platforms
  if (originalUrl.includes('vimeo.com') || originalUrl.includes('tiktok.com')) {
    const videoData = await extractVideoMetadata(originalUrl);
    if (videoData && videoData.title) {
      console.log('Using video platform-specific metadata');
      return videoData;
    }
  }
  
  // Try social media and other specialized platforms
  if (originalUrl.includes('twitter.com') || originalUrl.includes('x.com') || 
      originalUrl.includes('reddit.com') || originalUrl.includes('github.com') ||
      originalUrl.includes('linkedin.com')) {
    const socialData = await extractSocialMetadata(originalUrl);
    if (socialData && socialData.title) {
      console.log('Using platform-specific social metadata');
      return socialData;
    }
  }
  
  console.log('Falling back to HTML parsing');
  
  // Try JSON-LD first for rich structured data
  const jsonLdData = parseJsonLd(cleanHtml);
  
  // Extract title with multiple fallback strategies
  const titleMatch = cleanHtml.match(/<title[^>]*>([^<]+)<\/title>/i);
  let title = jsonLdData.title ||
              parseMetaContent(cleanHtml, 'og:title') || 
              parseMetaContent(cleanHtml, 'twitter:title') || 
              parseMetaContent(cleanHtml, 'title') ||
              (titleMatch ? titleMatch[1].trim() : null);
  
  // Clean up YouTube titles
  if (originalUrl.includes('youtube.com') && title) {
    title = title.replace(' - YouTube', '').trim();
  }

  // Extract description with multiple strategies
  const description = jsonLdData.description ||
                     parseMetaContent(cleanHtml, 'og:description') || 
                     parseMetaContent(cleanHtml, 'twitter:description') || 
                     parseMetaContent(cleanHtml, 'description') ||
                     parseMetaContent(cleanHtml, 'twitter:summary');

  // Extract image with comprehensive strategies including video thumbnails
  let image = jsonLdData.image ||
             parseMetaContent(cleanHtml, 'og:image') || 
             parseMetaContent(cleanHtml, 'twitter:image') ||
             parseMetaContent(cleanHtml, 'twitter:image:src') ||
             parseMetaContent(cleanHtml, 'og:video:thumbnail') ||
             parseMetaContent(cleanHtml, 'twitter:player:image');
  
  // YouTube-specific image extraction
  if ((originalUrl.includes('youtube.com') || originalUrl.includes('youtu.be')) && !image) {
    const videoIdMatch = originalUrl.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/|m\.youtube\.com\/watch\?v=)([^&\n?#]+)/);
    if (videoIdMatch) {
      const videoId = videoIdMatch[1];
      // Try different thumbnail qualities
      const thumbnailOptions = [
        `https://img.youtube.com/vi/${videoId}/maxresdefault.jpg`,
        `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
        `https://img.youtube.com/vi/${videoId}/mqdefault.jpg`,
        `https://img.youtube.com/vi/${videoId}/default.jpg`
      ];
      image = thumbnailOptions[0]; // Use highest quality by default
    }
  }
  
  // If no metadata image found, try to extract from page content
  if (!image) {
    image = extractFallbackImage(cleanHtml, originalUrl);
  }

  // Extract video URL for rich media content
  const videoUrl = parseMetaContent(cleanHtml, 'og:video:url') ||
                  parseMetaContent(cleanHtml, 'og:video') ||
                  parseMetaContent(cleanHtml, 'twitter:player:stream') ||
                  parseMetaContent(cleanHtml, 'twitter:player');

  // Resolve relative image URLs
  if (image && !image.startsWith('http')) {
    try {
      const baseUrl = new URL(originalUrl);
      if (image.startsWith('//')) {
        image = baseUrl.protocol + image;
      } else if (image.startsWith('/')) {
        image = baseUrl.origin + image;
      } else {
        image = new URL(image, originalUrl).toString();
      }
    } catch (e) {
      console.log('Failed to resolve image URL:', e);
      image = null;
    }
  }

  // Extract site name
  let siteName = parseMetaContent(cleanHtml, 'og:site_name') || 
                 parseMetaContent(cleanHtml, 'twitter:domain') ||
                 parseMetaContent(cleanHtml, 'application-name');
  
  // Set appropriate site name for known platforms
  if (!siteName) {
    if (originalUrl.includes('youtube.com') || originalUrl.includes('youtu.be')) {
      siteName = 'YouTube';
    } else if (originalUrl.includes('vimeo.com')) {
      siteName = 'Vimeo';
    } else if (originalUrl.includes('tiktok.com')) {
      siteName = 'TikTok';
    } else if (originalUrl.includes('twitter.com')) {
      siteName = 'Twitter';
    } else if (originalUrl.includes('x.com')) {
      siteName = 'X';
    } else if (originalUrl.includes('reddit.com')) {
      siteName = 'Reddit';
    } else if (originalUrl.includes('github.com')) {
      siteName = 'GitHub';
    } else if (originalUrl.includes('linkedin.com')) {
      siteName = 'LinkedIn';
    } else if (originalUrl.includes('medium.com')) {
      siteName = 'Medium';
    } else if (originalUrl.includes('substack.com')) {
      siteName = 'Substack';
    } else if (originalUrl.includes('pinterest.com')) {
      siteName = 'Pinterest';
    } else if (originalUrl.includes('amazon.com') || originalUrl.includes('amazon.')) {
      siteName = 'Amazon';
    } else if (originalUrl.includes('spotify.com')) {
      siteName = 'Spotify';
    } else if (originalUrl.includes('soundcloud.com')) {
      siteName = 'SoundCloud';
    }
  }

  return {
    title: title?.trim(),
    description: description?.trim(),
    image: image?.trim(),
    siteName: siteName?.trim(),
    videoUrl: videoUrl?.trim()
  };
};

// More permissive image validation
const validateImageUrl = async (imageUrl: string): Promise<boolean> => {
  try {
    const response = await fetch(imageUrl, { 
      method: 'HEAD',
      signal: AbortSignal.timeout(5000) // 5 second timeout
    });
    
    // Accept if request succeeds, don't be strict about content-type
    // Some servers don't return proper content-type headers
    return response.ok;
  } catch {
    return false;
  }
};

// Download and store image server-side
const downloadAndStoreImage = async (imageUrl: string, userId: string): Promise<{ path: string; publicUrl: string } | null> => {
  if (!userId || !imageUrl) return null;
  
  try {
    console.log(`Downloading image from: ${imageUrl}`);
    const response = await fetch(imageUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
      signal: AbortSignal.timeout(10000)
    });
    
    if (!response.ok) {
      console.log(`Failed to download image: ${response.status} ${response.statusText}`);
      return null;
    }
    
    const blob = await response.blob();
    if (blob.size === 0) {
      console.log('Downloaded image is empty');
      return null;
    }
    
    // Extract file extension from URL
    const urlParts = imageUrl.split('?')[0].split('/');
    const lastPart = urlParts[urlParts.length - 1];
    const fileExt = lastPart.includes('.') ? lastPart.split('.').pop() : 'jpg';
    const fileName = `preview_${Date.now()}.${fileExt}`;
    const filePath = `${userId}/previews/${fileName}`;

    // Initialize Supabase client with service role for server-side operations
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { error: uploadError } = await supabase.storage
      .from('stash-media')
      .upload(filePath, blob);

    if (uploadError) {
      console.error('Error uploading preview image:', uploadError);
      return null;
    }

    const { data: urlData } = supabase.storage
      .from('stash-media')
      .getPublicUrl(filePath);

    console.log(`Successfully stored image at: ${filePath}`);
    return { path: filePath, publicUrl: urlData.publicUrl };
  } catch (error) {
    console.error('Error downloading and storing image:', error);
    return null;
  }
};

// Check if result looks suspicious (redirect/placeholder page)
const isSuspiciousResult = (metadata: any): boolean => {
  const title = metadata.title?.toLowerCase() || '';
  const description = metadata.description?.toLowerCase() || '';
  const image = metadata.image || '';
  
  // Check for "Found" placeholder pages
  if (title === 'found' || description === 'found') {
    return true;
  }
  
  // Check for bare domain images (e.g., https://miro.medium.com/)
  if (image && image.match(/^https?:\/\/[^\/]+\/?$/)) {
    return true;
  }
  
  return false;
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { url, userId } = await req.json();
    
    if (!url) {
      return new Response(
        JSON.stringify({ success: false, error: 'URL is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate URL format
    let validUrl: URL;
    try {
      validUrl = new URL(url);
    } catch {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid URL format' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`Extracting metadata for: ${url}`);

    // Use platform-specific User-Agent
    const userAgent = getUserAgent(url);
    console.log(`Using User-Agent: ${userAgent}`);

    // Fetch the webpage with enhanced headers and timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000); // 15 second timeout

    try {
      const response = await fetch(url, {
        signal: controller.signal,
        headers: {
          'User-Agent': userAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/avif,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Accept-Encoding': 'gzip, deflate, br',
          'Cache-Control': 'no-cache',
          'Sec-Fetch-Dest': 'document',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'none',
          'Upgrade-Insecure-Requests': '1',
        },
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const html = await response.text();
      console.log(`Fetched HTML length: ${html.length} characters`);
      
      let metadata = await extractMetaFromHtml(html, url);
      console.log(`Extracted metadata:`, {
        title: metadata.title ? 'Found' : 'Not found',
        description: metadata.description ? 'Found' : 'Not found',
        image: metadata.image ? metadata.image : 'Not found',
        siteName: metadata.siteName ? 'Found' : 'Not found',
        videoUrl: metadata.videoUrl ? 'Found' : 'Not found'
      });

      // Check if result looks suspicious and retry with default UA if needed
      if (isSuspiciousResult(metadata) && userAgent !== 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36') {
        console.log('Suspicious result detected, retrying with default User-Agent');
        try {
          const retryResponse = await fetch(url, {
            signal: AbortSignal.timeout(10000),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/avif,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          });
          
          if (retryResponse.ok) {
            const retryHtml = await retryResponse.text();
            const retryMetadata = await extractMetaFromHtml(retryHtml, url);
            
            // Use retry result if it looks better
            if (!isSuspiciousResult(retryMetadata)) {
              console.log('Retry with default UA successful, using new metadata');
              metadata = retryMetadata;
            }
          }
        } catch (retryError) {
          console.log('Retry failed, using original metadata:', retryError);
        }
      }

      // More permissive image validation - don't remove image if validation fails
      let validImage = metadata.image;
      if (metadata.image) {
        const isValidImage = await validateImageUrl(metadata.image);
        if (!isValidImage) {
          console.log(`Image validation failed for: ${metadata.image}, but keeping it anyway`);
          // Keep the image URL even if validation fails - some valid images might fail validation
        }
      }

      // Download and store image server-side if userId provided
      let previewImagePath: string | undefined;
      let previewImagePublicUrl: string | undefined;
      
      if (validImage && userId) {
        const downloadResult = await downloadAndStoreImage(validImage, userId);
        if (downloadResult) {
          previewImagePath = downloadResult.path;
          previewImagePublicUrl = downloadResult.publicUrl;
          console.log(`Successfully downloaded and stored image: ${previewImagePath}`);
        } else {
          console.log('Failed to download image, will use original URL as fallback');
        }
      }

      // Create result with all available metadata
      const result: MetadataResult = {
        title: metadata.title || validUrl.hostname,
        description: metadata.description,
        image: validImage,
        previewImagePath,
        previewImagePublicUrl,
        siteName: metadata.siteName || validUrl.hostname,
        videoUrl: metadata.videoUrl,
        url: url,
        success: true
      };

      console.log(`Final result:`, result);

      return new Response(
        JSON.stringify(result),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );

    } catch (fetchError) {
      clearTimeout(timeoutId);
      throw fetchError;
    }

  } catch (error) {
    console.error('Error extracting metadata:', error);
    
    // Try to create fallback data even on error
    try {
      const { url: originalUrl } = await req.json();
      const fallbackUrl = new URL(originalUrl);
      const fallbackResult: MetadataResult = {
        title: fallbackUrl.hostname,
        siteName: fallbackUrl.hostname,
        url: originalUrl,
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
      
      return new Response(
        JSON.stringify(fallbackResult),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    } catch {
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to extract metadata' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
  }
});