/** Download evidence only: a valid raster structure is not a visual identity match
 * and does not prove that every pixel can be decoded. No item or storage writes. */
export type ImageCheck = {
  url: string;
  source_url: string;
  associated: boolean;
  strategy: 'public_raster_fetch';
  outcome: 'usable_asset' | 'invalid' | 'unavailable';
  reason: string;
  checked_at: string;
  duration_ms: number;
  mime_type?: string;
  byte_length?: number;
  width?: number;
  height?: number;
  sha256?: string;
};
const MAX_BYTES = 5 * 1024 * 1024;
const TIMEOUT_MS = 5_000;
// Exact provider-controlled hosts only. Arbitrary image hosts must wait for a
// DNS-pinned egress worker; the current general image proxy follows redirects.
const TRUSTED_HOSTS = new Set(['media.licdn.com', 'miro.medium.com', 'cdn-images-1.medium.com',
  'cdn-images-2.medium.com', 'i.ytimg.com', 'img.youtube.com', 'res.cloudinary.com']);
const SENSITIVE = /^(?:access[_-]?token|refresh[_-]?token|id[_-]?token|token|key|api[_-]?key|code|password|pass|secret|signature|sig|session(?:id|_id)?|auth(?:orization)?|jwt|x-amz-.*|x-goog-.*)$/i;
function targetGate(value: string): 'unsafe_image_url' | 'unsupported_image_host' | null {
  if (!value || value.length > 2000 || /[\s\\]/.test(value)) return 'unsafe_image_url';
  try {
    const parsed = new URL(value); const host = parsed.hostname;
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || (parsed.port && parsed.port !== '443') ||
      !host.includes('.') || host.includes(':') || /^\d+(\.\d+)*$/.test(host) || host.endsWith('.') ||
      /(^|\.)(localhost|local|internal|invalid|test|onion|arpa)$/.test(host) ||
      [...parsed.searchParams.keys()].some(key => SENSITIVE.test(key)) ||
      SENSITIVE.test(parsed.hash.slice(1).split('=')[0]) || /(?:^|[?&])(?:access_token|token|password|secret|signature)=/i.test(parsed.hash.slice(1))) return 'unsafe_image_url';
    return TRUSTED_HOSTS.has(host) ? null : 'unsupported_image_host';
  } catch { return 'unsafe_image_url'; }
}
class ImageError extends Error {
  constructor(readonly reason: string, readonly outcome: 'invalid' | 'unavailable' = 'invalid') { super(reason); }
}
const starts = (bytes: Uint8Array, signature: number[], at = 0) => signature.every((value, i) => bytes[at + i] === value);
const ascii = (bytes: Uint8Array, at: number, length: number) => String.fromCharCode(...bytes.subarray(at, at + length));
const be16 = (bytes: Uint8Array, at: number) => (bytes[at] << 8) | bytes[at + 1];
const be32 = (bytes: Uint8Array, at: number) => new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(at);
const le32 = (bytes: Uint8Array, at: number) => new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(at, true);
const le24 = (bytes: Uint8Array, at: number) => bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16);
function invalid(): never { throw new ImageError('invalid_raster_structure'); }
function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function pngDimensions(bytes: Uint8Array): [number, number] {
  let offset = 8; let dimensions: [number, number] | undefined; let dataLength = 0;
  while (offset + 12 <= bytes.length) {
    const length = be32(bytes, offset); const kind = ascii(bytes, offset + 4, 4);
    const end = offset + 12 + length;
    if (end > bytes.length || crc32(bytes.subarray(offset + 4, end - 4)) !== be32(bytes, end - 4)) invalid();
    if (!dimensions) {
      if (kind !== 'IHDR' || length !== 13) invalid();
      dimensions = [be32(bytes, offset + 8), be32(bytes, offset + 12)];
      const depth = bytes[offset + 16]; const color = bytes[offset + 17];
      const depths: Record<number, number[]> = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] };
      if (!depths[color]?.includes(depth) || bytes[offset + 18] !== 0 || bytes[offset + 19] !== 0 || bytes[offset + 20] > 1) invalid();
    } else if (kind === 'IHDR') invalid();
    if (kind === 'IDAT') dataLength += length;
    if (kind === 'IEND') {
      if (length !== 0 || end !== bytes.length || dataLength < 6) invalid();
      return dimensions;
    }
    offset = end;
  }
  return invalid();
}
function jpegDimensions(bytes: Uint8Array): [number, number] {
  let offset = 2; let dimensions: [number, number] | undefined; let scanned = false; let entropyBytes = 0;
  const frames = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
  while (offset < bytes.length) {
    if (bytes[offset++] !== 0xff) invalid();
    while (bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    if (marker === 0xd9) {
      if (!dimensions || !scanned || entropyBytes < 1 || offset !== bytes.length) invalid();
      return dimensions;
    }
    if (marker === 0x00 || marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7) || offset + 2 > bytes.length) invalid();
    const length = be16(bytes, offset);
    if (length < 2 || offset + length > bytes.length) invalid();
    if (frames.has(marker)) {
      if (length < 8 || dimensions) invalid();
      const components = bytes[offset + 7];
      if (!components || components > 4 || length !== 8 + components * 3) invalid();
      dimensions = [be16(bytes, offset + 5), be16(bytes, offset + 3)];
    }
    if (marker === 0xda) {
      if (!dimensions || length < 6 || length !== 6 + bytes[offset + 2] * 2) invalid();
      scanned = true; offset += length;
      while (offset < bytes.length) {
        if (bytes[offset] !== 0xff) { entropyBytes++; offset++; continue; }
        if (bytes[offset + 1] === 0x00) { entropyBytes++; offset += 2; continue; }
        if (bytes[offset + 1] >= 0xd0 && bytes[offset + 1] <= 0xd7) { offset += 2; continue; }
        break;
      }
    } else offset += length;
  }
  return invalid();
}
function webpDimensions(bytes: Uint8Array): [number, number] {
  if (bytes.length < 30 || le32(bytes, 4) + 8 !== bytes.length) invalid();
  let offset = 12; let dimensions: [number, number] | undefined; let imageData = false;
  while (offset + 8 <= bytes.length) {
    const kind = ascii(bytes, offset, 4); const length = le32(bytes, offset + 4); const data = offset + 8;
    const end = data + length + (length % 2);
    if (end > bytes.length) invalid();
    if (kind === 'VP8X') {
      if (length !== 10 || offset !== 12) invalid();
      dimensions = [le24(bytes, data + 4) + 1, le24(bytes, data + 7) + 1];
    } else if (kind === 'VP8 ') {
      if (length < 11 || !starts(bytes, [0x9d, 0x01, 0x2a], data + 3) || (bytes[data] & 1)) invalid();
      dimensions ||= [(bytes[data + 6] | (bytes[data + 7] << 8)) & 0x3fff, (bytes[data + 8] | (bytes[data + 9] << 8)) & 0x3fff];
      imageData = true;
    } else if (kind === 'VP8L') {
      if (length < 6 || bytes[data] !== 0x2f) invalid();
      const bits = le32(bytes, data + 1);
      if ((bits >>> 29) !== 0) invalid();
      dimensions ||= [(bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1]; imageData = true;
    }
    offset = end;
  }
  if (offset !== bytes.length || !dimensions || !imageData) invalid();
  return dimensions;
}
async function readImage(response: Response, signal: AbortSignal): Promise<Uint8Array> {
  if (Number(response.headers.get('content-length') || 0) > MAX_BYTES) {
    void response.body?.cancel().catch(() => {}); throw new ImageError('image_too_large');
  }
  const reader = response.body?.getReader(); if (!reader) throw new ImageError('empty_image');
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', cancel, { once: true });
  const chunks: Uint8Array[] = []; let length = 0;
  try {
    while (true) {
      if (signal.aborted) throw new ImageError('image_timeout', 'unavailable');
      const { done, value } = await reader.read(); if (done) break;
      length += value.byteLength;
      if (length > MAX_BYTES) { cancel(); throw new ImageError('image_too_large'); }
      chunks.push(value);
    }
    if (signal.aborted) throw new ImageError('image_timeout', 'unavailable');
  } finally { signal.removeEventListener('abort', cancel); reader.releaseLock(); }
  if (!length) throw new ImageError('empty_image');
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

/** Check one source-associated candidate, allowing at most five seconds and 5 MiB.
 * Fixed trusted CDN hosts prevent arbitrary DNS egress. Every redirect is refused;
 * no authorization, cookies, provider credentials or source headers are forwarded. */
export async function verifyImageAsset(candidate: { url: string; associated: boolean }, sourceUrl: string,
  { fetcher = fetch }: { fetcher?: typeof fetch } = {}): Promise<ImageCheck> {
  const started = Date.now();
  const check: ImageCheck = { url: candidate.url, source_url: sourceUrl, associated: candidate.associated,
    strategy: 'public_raster_fetch', outcome: 'unavailable', reason: 'image_request_failed', checked_at: new Date().toISOString(), duration_ms: 0 };
  const gate = !candidate.associated ? 'image_not_associated' : targetGate(candidate.url);
  if (gate) return { ...check, reason: gate };
  const controller = new AbortController(); let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const execute = async () => {
      const response = await fetcher(candidate.url, { method: 'GET', redirect: 'manual', credentials: 'omit', signal: controller.signal,
        headers: { Accept: 'image/jpeg,image/png,image/webp', 'User-Agent': 'StashImageEvidence/1.0' } });
      const refuse = (reason: string, outcome: 'invalid' | 'unavailable' = 'unavailable'): never => {
        void response.body?.cancel().catch(() => {}); throw new ImageError(reason, outcome);
      };
      if (response.redirected || (response.status >= 300 && response.status < 400)) refuse('image_redirect_rejected');
      if (!response.ok) refuse('image_http_error');
      const mime = (response.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
      if (!mime.startsWith('image/') || mime === 'image/svg+xml') refuse('non_raster_response', 'invalid');
      if (!['image/jpeg', 'image/png', 'image/webp'].includes(mime)) refuse('unsupported_raster_format');
      const bytes = await readImage(response, controller.signal);
      check.mime_type = mime; check.byte_length = bytes.byteLength;
      const detected = starts(bytes, [0xff, 0xd8, 0xff]) ? 'image/jpeg' : starts(bytes, [137, 80, 78, 71, 13, 10, 26, 10]) ? 'image/png' :
        starts(bytes, [82, 73, 70, 70]) && starts(bytes, [87, 69, 66, 80], 8) ? 'image/webp' : null;
      if (!detected) invalid();
      if (detected !== mime) throw new ImageError('image_mime_mismatch');
      const [width, height] = detected === 'image/png' ? pngDimensions(bytes) : detected === 'image/jpeg' ? jpegDimensions(bytes) : webpDimensions(bytes);
      check.width = width; check.height = height;
      if (width < 100 || height < 60) throw new ImageError('image_too_small');
      if (width > 12000 || height > 12000 || width * height > 20_000_000) throw new ImageError('image_dimensions_excessive');
      const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
      check.sha256 = [...digest].map(value => value.toString(16).padStart(2, '0')).join('');
    };
    const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => {
      controller.abort(); reject(new ImageError('image_timeout', 'unavailable'));
    }, TIMEOUT_MS); });
    await Promise.race([execute(), timeout]); check.outcome = 'usable_asset'; check.reason = 'raster_structure_valid';
  } catch (error) {
    check.outcome = error instanceof ImageError ? error.outcome : 'unavailable';
    check.reason = error instanceof ImageError ? error.reason : controller.signal.aborted ? 'image_timeout' : 'image_request_failed';
  } finally { clearTimeout(timer); controller.abort(); }
  // Return a snapshot: a timed-out transport that ignores AbortSignal must not
  // mutate the durable result after the request deadline has elapsed.
  return { ...check, duration_ms: Math.max(0, Date.now() - started) };
}
