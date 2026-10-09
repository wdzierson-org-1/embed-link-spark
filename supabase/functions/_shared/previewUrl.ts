/** Syntax filter only: callers fetching these URLs must enforce DNS, redirects
 * and network egress separately. This helper performs no network requests. */
export function isPublicPreviewUrl(value: string): boolean {
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || (url.port && url.port !== '443')) return false;
    const host = url.hostname.toLowerCase().replace(/\.$/, '');
    // URL normalizes decimal/hex IPv4 spellings before this check. Reject all
    // IP literals; public-looking syntax cannot establish a safe destination.
    if (!host.includes('.') || /^[\d.]+$/.test(host) || host.includes(':') || host.length > 253) return false;
    if (/(?:^|\.)(?:localhost|local|internal|invalid|test|lan|home|onion)$/.test(host)) return false;
    return host.split('.').every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label));
  } catch { return false; }
}
