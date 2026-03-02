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
  strategyUsed?: string;
  traceId?: string;
}

const normalizeWhitespace = (value?: string) => value?.replace(/\s+/g, ' ').trim();

const titleFromSlug = (slug?: string) => {
  if (!slug) return undefined;
  const cleaned = slug.replace(/[-_]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (!cleaned) return undefined;
  return cleaned
    .split(' ')
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
};

const getYouTubeVideoId = (url: string): string | null => {
  try {
    const parsedUrl = new URL(url);
    const hostname = parsedUrl.hostname.toLowerCase();

    if (!hostname.includes('youtube.com') && !hostname.includes('youtu.be')) {
      return null;
    }

    if (hostname.includes('youtu.be')) {
      const shortId = parsedUrl.pathname.split('/').filter(Boolean)[0];
      return shortId || null;
    }

    const queryVideoId = parsedUrl.searchParams.get('v');
    if (queryVideoId) return queryVideoId;

    const pathSegments = parsedUrl.pathname.split('/').filter(Boolean);
    const markerIndex = pathSegments.findIndex(segment => ['embed', 'shorts', 'live'].includes(segment));
    if (markerIndex !== -1 && pathSegments[markerIndex + 1]) {
      return pathSegments[markerIndex + 1];
    }

    return null;
  } catch {
    return null;
  }
};

const buildYouTubeFallbackMetadata = (url: string): Partial<MetadataResult> | null => {
  const videoId = getYouTubeVideoId(url);
  if (!videoId) return null;

  return {
    title: 'YouTube Video',
    description: 'Video link from YouTube',
    image: `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
    siteName: 'YouTube',
    videoUrl: `https://www.youtube.com/watch?v=${videoId}`,
  };
};

const buildYouTubeMetadataResult = (
  url: string,
  videoId: string,
  title: string,
  authorName?: string,
  thumbnailUrl?: string,
  strategyUsed: string = 'youtube-oembed'
): Partial<MetadataResult> => ({
  title,
  description: authorName
    ? `Watch "${title}" by ${authorName} on YouTube`
    : 'YouTube video',
  image: thumbnailUrl || `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
  siteName: 'YouTube',
  videoUrl: `https://www.youtube.com/watch?v=${videoId}`,
  url: url.replace('m.youtube.com', 'www.youtube.com'),
  strategyUsed,
});

const buildBotUnfriendlyFallbackMetadata = (rawUrl: string): Partial<MetadataResult> | null => {
  try {
    const url = new URL(rawUrl);
    const hostname = url.hostname.toLowerCase();

    if (hostname.includes('youtube.com') || hostname.includes('youtu.be')) {
      return {
        ...(buildYouTubeFallbackMetadata(rawUrl) || {}),
        strategyUsed: 'youtube-thumbnail-fallback',
      };
    }

    if (hostname.includes('linkedin.com')) {
      const isJobsLink = url.pathname.includes('/jobs/');
      return {
        title: isJobsLink ? 'LinkedIn Job Listing' : 'LinkedIn Page',
        description: 'LinkedIn may require login to access full preview metadata.',
        siteName: 'LinkedIn',
        image: 'https://static.licdn.com/scds/common/u/images/logos/favicons/v1/favicon.ico',
        strategyUsed: 'linkedin-authwall-fallback',
      };
    }

    if (hostname.includes('twitter.com') || hostname.includes('x.com')) {
      const match = url.pathname.match(/^\/([^\/]+)\/status\/(\d+)/);
      const handle = match?.[1];
      const statusId = match?.[2];
      return {
        title: handle ? `Post by @${handle} on ${hostname.includes('x.com') ? 'X' : 'Twitter'}` : 'Social Post',
        description: statusId ? `Open to view post ${statusId}` : `Open to view this post on ${hostname.includes('x.com') ? 'X' : 'Twitter'}`,
        siteName: hostname.includes('x.com') ? 'X' : 'Twitter',
        strategyUsed: 'x-url-structure-fallback',
      };
    }

    if (hostname.includes('reddit.com')) {
      const match = url.pathname.match(/\/r\/([^\/]+)\/comments\/([^\/]+)\/?([^\/]*)/);
      const subreddit = match?.[1];
      const slug = match?.[3];
      const inferredTitle = titleFromSlug(slug);
      return {
        title: inferredTitle || (subreddit ? `Post on r/${subreddit}` : 'Reddit Post'),
        description: subreddit ? `Open this Reddit post in r/${subreddit}` : 'Open this Reddit post',
        siteName: 'Reddit',
        image: 'https://www.redditstatic.com/desktop2x/img/favicon/apple-icon-180x180.png',
        strategyUsed: 'reddit-url-structure-fallback',
      };
    }
  } catch (error) {
    console.log('Failed to build bot-unfriendly fallback metadata:', error);
  }

  return null;
};

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
    const videoId = getYouTubeVideoId(url);
    if (!videoId) return null;
    console.log(`Extracting YouTube metadata for video ID: ${videoId}`);

    // Try YouTube oEmbed first.
    const oembedUrl = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${videoId}&format=json`;
    const oembedResponse = await fetch(oembedUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; LinkPreview/1.0)'
      },
      signal: AbortSignal.timeout(5000)
    });

    if (oembedResponse.ok) {
      const oembedData = await oembedResponse.json();
      console.log('YouTube oEmbed data:', oembedData);

      if (oembedData?.title) {
        return buildYouTubeMetadataResult(
          url,
          videoId,
          oembedData.title,
          oembedData.author_name,
          oembedData.thumbnail_url,
          'youtube-oembed'
        );
      }
    }

    // If oEmbed fails or returns no title, fall back to noembed.
    const noembedUrl = `https://noembed.com/embed?url=${encodeURIComponent(`https://www.youtube.com/watch?v=${videoId}`)}`;
    const noembedResponse = await fetch(noembedUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; LinkPreview/1.0)'
      },
      signal: AbortSignal.timeout(5000)
    });

    if (noembedResponse.ok) {
      const noembedData = await noembedResponse.json();
      console.log('YouTube noembed data:', noembedData);

      if (noembedData?.title) {
        return buildYouTubeMetadataResult(
          url,
          videoId,
          noembedData.title,
          noembedData.author_name,
          noembedData.thumbnail_url,
          'youtube-noembed'
        );
      }
    }
  } catch (error) {
    console.error('YouTube oEmbed failed:', error);
  }
  const fallback = buildYouTubeFallbackMetadata(url);
  if (!fallback) return null;
  return {
    ...fallback,
    strategyUsed: 'youtube-thumbnail-fallback'
  };
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
          url,
          strategyUsed: 'x-url-structure-fallback'
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
              url,
              strategyUsed: 'reddit-json-api'
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
              url,
              strategyUsed: 'github-repo-api'
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

const isLikelyAuthWall = (metadata: Partial<MetadataResult>, originalUrl: string, finalUrl: string): boolean => {
  const combinedText = `${metadata.title || ''} ${metadata.description || ''} ${finalUrl || ''}`.toLowerCase();

  if (combinedText.includes('login') || combinedText.includes('sign in') || combinedText.includes('checkpoint')) {
    return true;
  }

  try {
    const originalHost = new URL(originalUrl).hostname.toLowerCase();
    const finalHost = new URL(finalUrl).hostname.toLowerCase();

    if (originalHost.includes('linkedin.com') && finalHost.includes('linkedin.com') && finalUrl.includes('/login')) {
      return true;
    }
  } catch {
    return false;
  }

  return false;
};

const extractMetaFromHtml = async (html: string, originalUrl: string, finalUrl: string) => {
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
      return {
        ...videoData,
        strategyUsed: 'video-platform-oembed'
      };
    }
  }
  
  // Try social media and other specialized platforms
  if (originalUrl.includes('twitter.com') || originalUrl.includes('x.com') || 
      originalUrl.includes('reddit.com') || originalUrl.includes('github.com') ||
      originalUrl.includes('linkedin.com')) {
    const socialData = await extractSocialMetadata(originalUrl);
    if (socialData && socialData.title) {
      console.log('Using platform-specific social metadata');
      return {
        ...socialData,
        strategyUsed: 'social-platform-fallback'
      };
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
    title: normalizeWhitespace(title),
    description: normalizeWhitespace(description),
    image: image?.trim(),
    siteName: siteName?.trim(),
    videoUrl: videoUrl?.trim(),
    strategyUsed: 'html-meta-parse'
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
  if (!userId || !imageUrl) {
    console.log('downloadAndStoreImage: Missing required params:', { userId: !!userId, imageUrl: !!imageUrl });
    return null;
  }
  
  try {
    console.log(`=== DOWNLOADING IMAGE ===`);
    console.log(`Image URL: ${imageUrl}`);
    console.log(`User ID: ${userId}`);
    
    // First, try to validate the image URL with a HEAD request
    const headResponse = await fetch(imageUrl, {
      method: 'HEAD',
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Sec-Fetch-Dest': 'image',
        'Sec-Fetch-Mode': 'no-cors',
        'Sec-Fetch-Site': 'cross-site'
      },
      signal: AbortSignal.timeout(5000)
    });
    
    console.log(`HEAD request status: ${headResponse.status}`);
    console.log(`Content-Type: ${headResponse.headers.get('content-type')}`);
    console.log(`Content-Length: ${headResponse.headers.get('content-length')}`);
    
    // Check if it's actually an image
    const contentType = headResponse.headers.get('content-type');
    if (!contentType || !contentType.startsWith('image/')) {
      console.log(`⚠️ HEAD not image content-type: ${contentType} — will attempt GET anyway`);
      // Do not return; some servers block HEAD or mask content type
    }
    
    // Check content length - if it's very small, it's likely a placeholder
    const contentLength = headResponse.headers.get('content-length');
    if (contentLength && parseInt(contentLength) < 100) {
      console.log(`⚠️ HEAD shows very small size (${contentLength} bytes) — will still attempt GET`);
      // Do not return; we'll verify after GET
    }
    
    // Now download the actual image
    const response = await fetch(imageUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Sec-Fetch-Dest': 'image',
        'Sec-Fetch-Mode': 'no-cors',
        'Sec-Fetch-Site': 'cross-site',
        'Referer': new URL(imageUrl).origin
      },
      signal: AbortSignal.timeout(15000)
    });
    
    if (!response.ok) {
      console.log(`❌ Failed to download image: ${response.status} ${response.statusText}`);
      return null;
    }
    
    const blob = await response.blob();
    console.log(`📦 Downloaded blob size: ${blob.size} bytes`);
    
    if (blob.size === 0 || blob.size < 100) {
      console.log(`❌ Downloaded image is too small: ${blob.size} bytes`);
      return null;
    }
    
    // Verify it's actually image data by checking the blob type
    if (!blob.type || !blob.type.startsWith('image/')) {
      console.log(`❌ Invalid blob type: ${blob.type}`);
      return null;
    }
    
    // Extract file extension from content type or URL
    let fileExt = 'jpg';
    if (blob.type.includes('png')) fileExt = 'png';
    else if (blob.type.includes('gif')) fileExt = 'gif';
    else if (blob.type.includes('webp')) fileExt = 'webp';
    else if (blob.type.includes('svg')) fileExt = 'svg';
    else {
      // Fallback to URL extension
      const urlParts = imageUrl.split('?')[0].split('/');
      const lastPart = urlParts[urlParts.length - 1];
      if (lastPart.includes('.')) {
        const ext = lastPart.split('.').pop()?.toLowerCase();
        if (ext && ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].includes(ext)) {
          fileExt = ext;
        }
      }
    }
    
    const fileName = `preview_${Date.now()}.${fileExt}`;
    const filePath = `${userId}/previews/${fileName}`;

    // Initialize Supabase client with service role for server-side operations
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    
    console.log(`📁 File path: ${filePath}`);
    console.log(`📤 Uploading ${blob.size} bytes to storage...`);
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { error: uploadError } = await supabase.storage
      .from('stash-media')
      .upload(filePath, blob, {
        contentType: blob.type,
        cacheControl: '3600'
      });

    if (uploadError) {
      console.error('❌ Error uploading preview image:', uploadError);
      return null;
    }
    
    console.log('✅ Successfully uploaded to storage');

    const { data: urlData } = supabase.storage
      .from('stash-media')
      .getPublicUrl(filePath);

    console.log(`✅ Successfully downloaded and stored image: ${filePath}`);
    console.log(`🔗 Public URL: ${urlData.publicUrl}`);
    
    return { path: filePath, publicUrl: urlData.publicUrl };
  } catch (error) {
    console.error('❌ Error downloading and storing image:', error);
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
  const traceId = `trace_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  let requestPayload: { url?: string; userId?: string; fastOnly?: boolean } = {};

  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    requestPayload = await req.json();
    const { url, userId, fastOnly = false } = requestPayload;
    
    // CRITICAL DEBUG LOGGING
    console.log('=== EXTRACT-LINK-METADATA DEBUG ===');
    console.log('Trace ID:', traceId);
    console.log('Received userId:', userId);
    console.log('fastOnly mode:', fastOnly);
    console.log('SUPABASE_SERVICE_ROLE_KEY exists:', !!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'));
    console.log('SUPABASE_URL exists:', !!Deno.env.get('SUPABASE_URL'));
    
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
    const timeoutId = setTimeout(() => controller.abort(), fastOnly ? 6000 : 15000); // Keep fast path responsive

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
      
      const finalResolvedUrl = response.url || url;
      let metadata = await extractMetaFromHtml(html, url, finalResolvedUrl);
      console.log(`Extracted metadata:`, {
        title: metadata.title ? 'Found' : 'Not found',
        description: metadata.description ? 'Found' : 'Not found',
        image: metadata.image ? metadata.image : 'Not found',
        siteName: metadata.siteName ? 'Found' : 'Not found',
        videoUrl: metadata.videoUrl ? 'Found' : 'Not found'
      });

      // Check if result looks suspicious and retry with default UA if needed
      if (!fastOnly && isSuspiciousResult(metadata) && userAgent !== 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36') {
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
            const retryMetadata = await extractMetaFromHtml(retryHtml, url, retryResponse.url || url);
            
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

      if (isLikelyAuthWall(metadata, url, finalResolvedUrl)) {
        const botFriendlyFallback = buildBotUnfriendlyFallbackMetadata(url);
        if (botFriendlyFallback) {
          metadata = {
            ...metadata,
            ...botFriendlyFallback,
            strategyUsed: `${botFriendlyFallback.strategyUsed || 'authwall'}-detected`,
          };
          console.log('Auth wall detected, using fallback metadata strategy:', metadata.strategyUsed);
        }
      }

      if (!metadata.title || (!metadata.description && !metadata.image)) {
        const botFriendlyFallback = buildBotUnfriendlyFallbackMetadata(url);
        if (botFriendlyFallback) {
          metadata = {
            ...metadata,
            ...botFriendlyFallback,
            strategyUsed: botFriendlyFallback.strategyUsed || metadata.strategyUsed || 'bot-unfriendly-fallback',
          };
          console.log('Weak metadata detected, applying bot-unfriendly fallback:', metadata.strategyUsed);
        }
      }

      // More permissive image validation - don't remove image if validation fails
      let validImage = metadata.image;
      if (!fastOnly && metadata.image) {
        const isValidImage = await validateImageUrl(metadata.image);
        if (!isValidImage) {
          console.log(`Image validation failed for: ${metadata.image}, but keeping it anyway`);
          // Keep the image URL even if validation fails - some valid images might fail validation
        }
      }

      // Download and store image server-side if userId provided
      let previewImagePath: string | undefined;
      let previewImagePublicUrl: string | undefined;
      
      console.log('Image download check:', { validImage: !!validImage, userId: !!userId, imageUrl: validImage });
      
      if (!fastOnly && validImage && userId) {
        console.log('Attempting to download and store image...');
        const downloadResult = await downloadAndStoreImage(validImage, userId);
        if (downloadResult) {
          previewImagePath = downloadResult.path;
          previewImagePublicUrl = downloadResult.publicUrl;
          console.log(`✓ Successfully downloaded and stored image: ${previewImagePath}`);
          console.log(`✓ Public URL: ${previewImagePublicUrl}`);
        } else {
          console.log('✗ Failed to download image, will use original URL as fallback');
        }
      } else {
        console.log('Skipping image download:', { validImage: !!validImage, userId: !!userId });
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
        strategyUsed: metadata.strategyUsed || 'html-meta-parse',
        traceId,
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
      const originalUrl = requestPayload.url;
      if (!originalUrl) throw new Error('Missing original URL in request payload');
      const fallbackUrl = new URL(originalUrl);
      const youtubeFallback = buildYouTubeFallbackMetadata(originalUrl);
      const botFallback = buildBotUnfriendlyFallbackMetadata(originalUrl);
      const finalFallback = botFallback || youtubeFallback;
      const fallbackResult: MetadataResult = {
        title: finalFallback?.title || fallbackUrl.hostname,
        description: finalFallback?.description,
        image: finalFallback?.image,
        siteName: finalFallback?.siteName || fallbackUrl.hostname,
        videoUrl: finalFallback?.videoUrl,
        strategyUsed: finalFallback?.strategyUsed || 'hostname-fallback',
        traceId,
        url: originalUrl,
        success: !!finalFallback,
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