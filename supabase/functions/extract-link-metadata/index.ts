import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface MetadataResult {
  title?: string;
  description?: string;
  image?: string;
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

const extractMetaFromHtml = (html: string, originalUrl: string) => {
  const cleanHtml = html.replace(/\n/g, ' ').replace(/\s+/g, ' ');
  
  // Try JSON-LD first for rich structured data
  const jsonLdData = parseJsonLd(cleanHtml);
  
  // Extract title with multiple fallback strategies
  const titleMatch = cleanHtml.match(/<title[^>]*>([^<]+)<\/title>/i);
  const title = jsonLdData.title ||
               parseMetaContent(cleanHtml, 'og:title') || 
               parseMetaContent(cleanHtml, 'twitter:title') || 
               parseMetaContent(cleanHtml, 'title') ||
               (titleMatch ? titleMatch[1].trim() : null);

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
  const siteName = parseMetaContent(cleanHtml, 'og:site_name') || 
                  parseMetaContent(cleanHtml, 'twitter:domain') ||
                  parseMetaContent(cleanHtml, 'application-name');

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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { url } = await req.json();
    
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
      
      const metadata = extractMetaFromHtml(html, url);
      console.log(`Extracted metadata:`, {
        title: metadata.title ? 'Found' : 'Not found',
        description: metadata.description ? 'Found' : 'Not found',
        image: metadata.image ? metadata.image : 'Not found',
        siteName: metadata.siteName ? 'Found' : 'Not found',
        videoUrl: metadata.videoUrl ? 'Found' : 'Not found'
      });

      // More permissive image validation - don't remove image if validation fails
      let validImage = metadata.image;
      if (metadata.image) {
        const isValidImage = await validateImageUrl(metadata.image);
        if (!isValidImage) {
          console.log(`Image validation failed for: ${metadata.image}, but keeping it anyway`);
          // Keep the image URL even if validation fails - some valid images might fail validation
        }
      }

      // Create result with all available metadata
      const result: MetadataResult = {
        title: metadata.title || validUrl.hostname,
        description: metadata.description,
        image: validImage,
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
        error: error.message
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