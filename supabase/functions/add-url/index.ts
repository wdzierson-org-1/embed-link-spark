import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Utility functions for metadata extraction
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
      return match[1];
    }
  }
  return null;
};

const extractMetaFromHtml = (html: string) => {
  const cleanHtml = html.replace(/\n/g, ' ').replace(/\s+/g, ' ');
  
  const titleMatch = cleanHtml.match(/<title[^>]*>([^<]+)<\/title>/i);
  const title = parseMetaContent(cleanHtml, 'og:title') || 
               parseMetaContent(cleanHtml, 'twitter:title') || 
               (titleMatch ? titleMatch[1] : null);

  const description = parseMetaContent(cleanHtml, 'og:description') || 
                     parseMetaContent(cleanHtml, 'twitter:description') || 
                     parseMetaContent(cleanHtml, 'description');

  const image = parseMetaContent(cleanHtml, 'og:image') || 
               parseMetaContent(cleanHtml, 'twitter:image');

  const siteName = parseMetaContent(cleanHtml, 'og:site_name') || 
                  parseMetaContent(cleanHtml, 'twitter:domain');

  return {
    title: title?.trim(),
    description: description?.trim(),
    image: image?.trim(),
    siteName: siteName?.trim()
  };
};

const downloadAndStoreImage = async (imageUrl: string, userId: string, supabase: any): Promise<string | null> => {
  if (!userId || !imageUrl) return null;
  
  try {
    console.log('Downloading image from:', imageUrl);
    const response = await fetch(imageUrl, { 
      mode: 'cors',
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; Notes2MeBot/1.0)'
      }
    });
    
    if (!response.ok) {
      console.log('Failed to download image, status:', response.status);
      return null;
    }
    
    const blob = await response.blob();
    const urlParts = imageUrl.split('?')[0].split('/');
    const lastPart = urlParts[urlParts.length - 1];
    const fileExt = lastPart.includes('.') ? lastPart.split('.').pop() : 'jpg';
    const fileName = `preview_${Date.now()}.${fileExt}`;
    const filePath = `${userId}/previews/${fileName}`;

    const { error: uploadError } = await supabase.storage
      .from('stash-media')
      .upload(filePath, blob);

    if (uploadError) {
      console.error('Error uploading preview image:', uploadError);
      return null;
    }

    console.log('Preview image stored successfully at:', filePath);
    return filePath;
  } catch (error) {
    console.error('Error downloading and storing image:', error);
    return null;
  }
};

Deno.serve(async (req) => {
  console.log('Add URL function called');

  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'Method not allowed' }),
        { 
          status: 405, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    const body = await req.json();
    console.log('Request body:', body);

    const { url, userId, title: customTitle, content: userNotes, message, supplemental_note, is_public = true } = body;

    // Validate URL
    if (!url) {
      return new Response(
        JSON.stringify({ error: 'URL is required' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    try {
      new URL(url);
    } catch {
      return new Response(
        JSON.stringify({ error: 'Invalid URL format' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    // Default to demo user if no userId provided
    const targetUserId = userId || '0a0afaa8-0e11-47e9-887f-223816a9bb53';

    console.log('Fetching metadata for URL:', url);

    // Fetch the webpage content
    let metadata = { title: null, description: null, image: null, siteName: null };
    let previewImagePath = null;

    try {
      const response = await fetch(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; Notes2MeBot/1.0)'
        }
      });

      if (response.ok) {
        const html = await response.text();
        metadata = extractMetaFromHtml(html);
        console.log('Extracted metadata:', metadata);

        // Download and store preview image if available
        if (metadata.image) {
          previewImagePath = await downloadAndStoreImage(metadata.image, targetUserId, supabase);
        }
      }
    } catch (fetchError) {
      console.log('Direct fetch failed, trying with proxy:', fetchError);
      
      // Try with a proxy service as fallback
      try {
        const proxyUrl = `https://api.allorigins.win/get?url=${encodeURIComponent(url)}`;
        const proxyResponse = await fetch(proxyUrl);
        
        if (proxyResponse.ok) {
          const proxyData = await proxyResponse.json();
          const html = proxyData.contents;
          metadata = extractMetaFromHtml(html);
          console.log('Extracted metadata via proxy:', metadata);

          if (metadata.image) {
            previewImagePath = await downloadAndStoreImage(metadata.image, targetUserId, supabase);
          }
        }
      } catch (proxyError) {
        console.error('Proxy fetch also failed:', proxyError);
      }
    }

    // Use custom title or fallback to extracted title or URL
    const finalTitle = customTitle || metadata.title || url;
    const finalDescription = metadata.description || `Link from ${metadata.siteName || new URL(url).hostname}`;

    // Insert the link into the items table
    const { data: item, error } = await supabase
      .from('items')
      .insert({
        user_id: targetUserId,
        type: 'link',
        url: url,
        title: finalTitle,
        content: message || userNotes || null, // User's message or notes about the link
        supplemental_note: supplemental_note || null, // Separate sticky note content
        description: finalDescription,
        file_path: previewImagePath,
        is_public: is_public,
        visibility: is_public ? 'public' : 'private'
      })
      .select()
      .single();

    if (error) {
      console.error('Error creating link item:', error);
      return new Response(
        JSON.stringify({ error: 'Failed to save link', details: error.message }),
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    console.log('Link item created successfully:', item.id);

    // Generate embeddings in the background to avoid timeout
    const contentForEmbedding = [
      finalTitle,
      finalDescription,
      message || userNotes
    ].filter(Boolean).join(' ');

    if (contentForEmbedding.trim()) {
      // Run embeddings generation in the background
      EdgeRuntime.waitUntil(
        supabase.functions.invoke('generate-embeddings', {
          body: {
            itemId: item.id,
            textContent: contentForEmbedding
          }
        }).then(() => {
          console.log('Embeddings generated for link:', item.id);
        }).catch((embeddingError) => {
          console.error('Error generating embeddings:', embeddingError);
        })
      );
    }

    // Return immediate success response
    const statusCode = 200; // Always return 200 for success
    const statusMessage = is_public 
      ? 'URL added successfully to your public feed' 
      : 'URL saved privately to your stash';

    return new Response(
      JSON.stringify({ 
        success: true, 
        item: {
          ...item,
          metadata,
          previewImagePath
        },
        message: statusMessage,
        visibility: is_public ? 'public' : 'private'
      }),
      { 
        status: statusCode, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: error.message }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
  }
});