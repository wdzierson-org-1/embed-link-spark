
export const isValidUrl = (string: string) => {
  try {
    new URL(string);
    return true;
  } catch (_) {
    return false;
  }
};

export const parseMetaContent = (html: string, property: string): string | null => {
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

export const extractMetaFromHtml = (html: string) => {
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

export const fetchWithProxy = async (urlToFetch: string) => {
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
