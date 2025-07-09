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
}

const parseMetaContent = (html: string, property: string): string | null => {
  const patterns = [
    new RegExp(`<meta\\s+property=["']${property}["']\\s+content=["']([^"']+)["']`, 'i'),
    new RegExp(`<meta\\s+content=["']([^"']+)["']\\s+property=["']${property}["']`, 'i'),
    new RegExp(`<meta\\s+name=["']${property}["']\\s+content=["']([^"']+)["']`, 'i'),
    new RegExp(`<meta\\s+content=["']([^"']+)["']\\s+name=["']${property}["']`, 'i'),
  ];

  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match && match[1]) {
      return match[1].replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
    }
  }
  return null;
};

const extractMetaFromHtml = (html: string, originalUrl: string) => {
  const cleanHtml = html.replace(/\n/g, ' ').replace(/\s+/g, ' ');
  
  // Extract title with multiple fallback strategies
  const titleMatch = cleanHtml.match(/<title[^>]*>([^<]+)<\/title>/i);
  const title = parseMetaContent(cleanHtml, 'og:title') || 
               parseMetaContent(cleanHtml, 'twitter:title') || 
               parseMetaContent(cleanHtml, 'title') ||
               (titleMatch ? titleMatch[1].trim() : null);

  // Extract description with multiple strategies
  const description = parseMetaContent(cleanHtml, 'og:description') || 
                     parseMetaContent(cleanHtml, 'twitter:description') || 
                     parseMetaContent(cleanHtml, 'description') ||
                     parseMetaContent(cleanHtml, 'twitter:summary');

  // Extract image with comprehensive strategies
  let image = parseMetaContent(cleanHtml, 'og:image') || 
             parseMetaContent(cleanHtml, 'twitter:image') ||
             parseMetaContent(cleanHtml, 'twitter:image:src');

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
    siteName: siteName?.trim()
  };
};

const validateImageUrl = async (imageUrl: string): Promise<boolean> => {
  try {
    const response = await fetch(imageUrl, { method: 'HEAD' });
    const contentType = response.headers.get('content-type');
    return response.ok && contentType?.startsWith('image/');
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

    // Fetch the webpage with proper headers
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Cache-Control': 'no-cache',
      },
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    const html = await response.text();
    const metadata = extractMetaFromHtml(html, url);

    // Validate image if present
    if (metadata.image) {
      const isValidImage = await validateImageUrl(metadata.image);
      if (!isValidImage) {
        console.log(`Invalid image URL: ${metadata.image}`);
        metadata.image = undefined;
      }
    }

    // Create fallback data if no metadata found
    const result: MetadataResult = {
      title: metadata.title || validUrl.hostname,
      description: metadata.description,
      image: metadata.image,
      siteName: metadata.siteName || validUrl.hostname,
      url: url,
      success: true
    };

    console.log(`Successfully extracted metadata:`, result);

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

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
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    } catch {
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to extract metadata' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
  }
});