import { describe, expect, it } from 'vitest';
import { isPublicPreviewUrl } from './previewUrl';

describe('preview URL syntax', () => {
  it.each([
    'https://res.cloudinary.com/petermillar/image/upload/MF26XS49_NAV.jpg',
    'https://images.example.com:443/image.jpg?width=1200',
    'https://xn--bcher-kva.example/image.jpg',
  ])('accepts HTTPS publisher URLs: %s', value => {
    expect(isPublicPreviewUrl(value)).toBe(true);
  });
  it.each([
    'http://images.example.com/image.jpg', 'file:///tmp/image.jpg', 'data:image/png;base64,x',
    'https://user:secret@example.com/image.jpg', 'https://example.com:8443/image.jpg',
    'https://localhost/image.jpg', 'https://internal/image.jpg', 'https://host.local/image.jpg',
    'https://host.internal/image.jpg', 'https://host.localhost./image.jpg',
    'https://127.0.0.1/image.jpg', 'https://2130706433/image.jpg', 'https://0x7f000001/image.jpg',
    'https://8.8.8.8/image.jpg', 'https://[::1]/image.jpg', 'https://[2606:4700::1111]/image.jpg',
    'https://bad_label.example/image.jpg', 'not a URL',
  ])('rejects non-public or non-HTTPS syntax: %s', value => {
    expect(isPublicPreviewUrl(value)).toBe(false);
  });
});
