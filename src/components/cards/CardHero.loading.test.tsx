import { fireEvent, render, screen } from '@testing-library/react';
import { AspectAwareImage, LinkCover } from './CardHero';
import * as heroFocal from '@/utils/heroFocal';

vi.mock('@/integrations/supabase/client', () => ({ SUPABASE_URL: 'https://storage.example' }));
vi.mock('@/components/machine/PixelMosaic', () => ({
  PixelMosaic: () => <div data-testid="pixel-mosaic" />,
}));

afterEach(() => vi.restoreAllMocks());

describe('card preview loading', () => {
  it('keeps ordinary network loading quiet for saved image and link previews', () => {
    render(<>
      <AspectAwareImage src="/saved-photo.jpg" alt="Saved photo" />
      <LinkCover imageSource="/saved-preview.jpg" alt="Saved link" onFailed={vi.fn()} />
    </>);
    expect(screen.queryAllByTestId('pixel-mosaic')).toHaveLength(0);
    expect(screen.getByAltText('Saved photo')).toHaveAttribute('loading', 'lazy');
    expect(screen.getByAltText('Saved link')).toHaveAttribute('loading', 'lazy');
  });

  it('keeps the enrichment mosaic when a new preview arrives or Stash is reading', () => {
    render(<>
      <AspectAwareImage src="/new-photo.jpg" alt="New photo" arriving />
      <LinkCover imageSource="/reading-preview.jpg" alt="Reading link" reading onFailed={vi.fn()} />
    </>);
    expect(screen.getAllByTestId('pixel-mosaic')).toHaveLength(2);
  });

  it('does not start a decorative portrait download ahead of its lazy foreground', () => {
    const { container } = render(<LinkCover imageSource="/book.jpg" alt="Book" tall onFailed={vi.fn()} />);
    expect(container.querySelectorAll('img')).toHaveLength(1);
  });

  it('keeps the loaded foreground and request mode when a photo turns out to be portrait', () => {
    const { container } = render(<AspectAwareImage src="/portrait.jpg" alt="Portrait" />);
    const foreground = screen.getByAltText('Portrait');
    Object.defineProperties(foreground, { naturalWidth: { value: 600 }, naturalHeight: { value: 900 } });
    fireEvent.load(foreground);
    expect(screen.getByAltText('Portrait')).toBe(foreground);
    const images = [...container.querySelectorAll('img')];
    expect(images).toHaveLength(2);
    for (const img of images) {
      expect(img).toHaveAttribute('crossorigin', 'anonymous');
      expect(img).toHaveAttribute('loading', 'lazy');
    }
  });

  it('recognizes cached portrait dimensions without waiting for a second load event', () => {
    vi.spyOn(HTMLImageElement.prototype, 'complete', 'get').mockReturnValue(true);
    vi.spyOn(HTMLImageElement.prototype, 'naturalWidth', 'get').mockReturnValue(600);
    vi.spyOn(HTMLImageElement.prototype, 'naturalHeight', 'get').mockReturnValue(900);
    const { container } = render(<AspectAwareImage src="/cached-portrait.jpg" alt="Cached portrait" />);
    expect(screen.getByAltText('Cached portrait')).toHaveClass('object-contain');
    expect(container.querySelectorAll('img')).toHaveLength(2);
  });

  it.each(['photo', 'link'])('applies the subject crop to a cached %s before a load event', (kind) => {
    vi.spyOn(HTMLImageElement.prototype, 'complete', 'get').mockReturnValue(true);
    vi.spyOn(HTMLImageElement.prototype, 'naturalWidth', 'get').mockReturnValue(1000);
    vi.spyOn(HTMLImageElement.prototype, 'naturalHeight', 'get').mockReturnValue(400);
    vi.spyOn(Element.prototype, 'clientWidth', 'get').mockReturnValue(320);
    vi.spyOn(Element.prototype, 'clientHeight', 'get').mockReturnValue(160);
    vi.spyOn(heroFocal, 'analyzeImageElement').mockReturnValue({
      background: [255, 255, 255], flatBackground: true,
      bounds: { x0: 0.8, y0: 0.3, x1: 1, y1: 0.7 }, focal: { x: 0.9, y: 0.5 },
    });
    render(kind === 'photo'
      ? <AspectAwareImage src="/cached-wide.jpg" alt="Cached wide" />
      : <LinkCover imageSource="/cached-wide.jpg" alt="Cached wide" onFailed={vi.fn()} />);
    expect(screen.getByAltText('Cached wide')).toHaveStyle({ objectPosition: '100.0% 50.0%' });
  });

  it('resets portrait and loading state for a different image source', () => {
    const { rerender, container } = render(<AspectAwareImage src="/first.jpg" alt="Changing image" />);
    const first = screen.getByAltText('Changing image');
    Object.defineProperties(first, { naturalWidth: { value: 600 }, naturalHeight: { value: 900 } });
    fireEvent.load(first);
    rerender(<AspectAwareImage src="/second.jpg" alt="Changing image" />);
    expect(screen.getByAltText('Changing image')).toHaveClass('object-cover');
    expect(screen.getByAltText('Changing image')).not.toBe(first);
    expect(container.querySelectorAll('img')).toHaveLength(1);
  });

  it('resets the link fallback chain when a new preview source replaces the old one', () => {
    const onFailed = vi.fn();
    const { rerender } = render(<LinkCover imageSource="https://example.com/first.jpg" alt="Changing link" onFailed={onFailed} />);
    fireEvent.error(screen.getByAltText('Changing link'));
    expect(screen.getByAltText('Changing link')).toHaveAttribute('src', expect.stringContaining('/image-proxy?url='));
    fireEvent.error(screen.getByAltText('Changing link'));
    expect(onFailed).toHaveBeenCalledTimes(1);

    rerender(<LinkCover imageSource="https://example.com/second.jpg" alt="Changing link" onFailed={onFailed} />);
    expect(screen.getByAltText('Changing link')).toHaveAttribute('src', 'https://example.com/second.jpg');
    fireEvent.error(screen.getByAltText('Changing link'));
    expect(onFailed).toHaveBeenCalledTimes(1);
    expect(screen.getByAltText('Changing link')).toHaveAttribute('src', expect.stringContaining('second.jpg'));
  });
});
