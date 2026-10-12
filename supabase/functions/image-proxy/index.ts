import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

/** Monitor requests are fully buffered within one deadline so an upstream body
 * cannot keep downloading after the collector has timed out. Browser requests
 * retain the existing streaming behavior. */
async function fetchMonitorImage(url: string, init: RequestInit): Promise<Response> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const collect = async (): Promise<Response> => {
    const response = await fetch(url, { ...init, redirect: 'error', signal: controller.signal });
    if (!response.ok || response.redirected) {
      void response.body?.cancel().catch(() => {});
      return response;
    }
    const limit = 5 * 1024 * 1024;
    if (Number(response.headers.get('content-length') || 0) > limit) {
      void response.body?.cancel().catch(() => {});
      throw new Error('monitor_image_too_large');
    }
    const reader = response.body?.getReader();
    if (!reader) throw new Error('monitor_empty_image');
    const cancel = () => { void reader.cancel().catch(() => {}); };
    controller.signal.addEventListener('abort', cancel, { once: true });
    const chunks: Uint8Array[] = []; let size = 0;
    try {
      while (true) {
        if (controller.signal.aborted) throw new Error('monitor_timeout');
        const { value, done } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > limit) { cancel(); throw new Error('monitor_image_too_large'); }
        chunks.push(value);
      }
      if (controller.signal.aborted) throw new Error('monitor_timeout');
    } finally {
      controller.signal.removeEventListener('abort', cancel);
      reader.releaseLock();
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return new Response(bytes, { status: response.status, headers: response.headers });
  };
  try {
    return await Promise.race([collect(), new Promise<never>((_, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new Error('monitor_timeout')); }, 5_000);
    })]);
  } finally { clearTimeout(timer); controller.abort(); }
}

serve(async (req) => {
  // Hosted visual audits inspect the same route, but must never inherit this
  // legacy proxy's redirect-following behavior. Default browser requests retain
  // their current behavior. The response marker lets audits fail closed against
  // an older deployment or an ordinary cached response.
  const visualMonitor = req.headers.get('X-Stash-Visual-Monitor') === '1';
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const imageUrl = url.searchParams.get('url');

    if (!imageUrl) {
      return new Response(
        JSON.stringify({ error: 'Missing url parameter' }),
        { 
          status: 400,
          headers: { 
            ...corsHeaders, 
            'Content-Type': 'application/json'
          }
        }
      );
    }

    // Validate that it's a proper URL
    try {
      const targetUrl = new URL(imageUrl);
      if (!['http:', 'https:'].includes(targetUrl.protocol)) {
        throw new Error('Invalid protocol');
      }
    } catch {
      return new Response(
        JSON.stringify({ error: 'Invalid URL' }),
        { 
          status: 400,
          headers: { 
            ...corsHeaders, 
            'Content-Type': 'application/json'
          }
        }
      );
    }

    if (!visualMonitor) console.log(`Proxying image from: ${imageUrl}`);

    // Fetch the image with browser-like headers
    const upstreamOptions: RequestInit = {
      method: 'GET',
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'image/webp,image/avif,image/apng,image/*,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Referer': new URL(imageUrl).origin,
        'Sec-Fetch-Dest': 'image',
        'Sec-Fetch-Mode': 'no-cors',
        'Sec-Fetch-Site': 'cross-site',
      },
    };
    const response = visualMonitor
      ? await fetchMonitorImage(imageUrl, upstreamOptions)
      : await fetch(imageUrl, upstreamOptions);

    if (!response.ok || (visualMonitor && response.redirected)) {
      if (!visualMonitor) console.log(`Failed to fetch image: ${response.status} ${response.statusText}`);
      void response.body?.cancel().catch(() => {});
      return new Response(
        JSON.stringify({ error: 'Failed to fetch image' }),
        { 
          status: 502,
          headers: { 
            ...corsHeaders, 
            'Content-Type': 'application/json'
          }
        }
      );
    }

    const contentType = response.headers.get('content-type');
    if (!contentType || !contentType.startsWith('image/')) {
      console.log(`Not an image content-type: ${contentType}`);
      return new Response(
        JSON.stringify({ error: 'Response is not an image' }),
        { 
          status: 400,
          headers: { 
            ...corsHeaders, 
            'Content-Type': 'application/json'
          }
        }
      );
    }

    // Stream the image back with proper headers
    const responseHeaders = new Headers({
      ...corsHeaders,
      'Content-Type': contentType,
      'Cache-Control': visualMonitor ? 'no-store' : 'public, max-age=86400',
      'Vary': 'X-Stash-Visual-Monitor',
      ...(visualMonitor ? { 'X-Stash-Visual-Mode': 'no-redirect' } : {}),
    });

    // Add content-length if available
    const contentLength = response.headers.get('content-length');
    if (contentLength) {
      responseHeaders.set('Content-Length', contentLength);
    }

    console.log(`Successfully proxying image of type: ${contentType}`);

    return new Response(response.body, {
      status: 200,
      headers: responseHeaders,
    });

  } catch (error) {
    console.error('Error in image proxy:', visualMonitor ? 'monitor_upstream_unavailable' : error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { 
        status: 500,
        headers: { 
          ...corsHeaders, 
          'Content-Type': 'application/json'
        }
      }
    );
  }
});