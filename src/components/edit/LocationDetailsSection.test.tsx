import { fireEvent, render, screen } from '@testing-library/react';
import LocationDetailsSection from './LocationDetailsSection';
import type { PlaceAttributes } from '../../../supabase/functions/_shared/place';

const place: PlaceAttributes = {
  version: 1,
  name: 'Solevo Kitchen + Social',
  address: { lines: ['55 Phila St', 'Saratoga Springs, NY 12866', 'United States'] },
  geo: { latitude: 43.080499, longitude: -73.783109 },
  timezone: 'America/New_York',
  phone: '+15184507094',
  website: 'http://www.solevokitchenandsocial.com/',
  menu_url: 'https://www.yelp.com/biz/solevo?utm_source=apple#menu_photos',
  hours: [
    { days: [0], ranges: [{ open: '13:00', close: '20:00' }] },
    { days: [1, 2, 3, 4], ranges: [{ open: '16:00', close: '21:00' }] },
    { days: [5], ranges: [{ open: '16:00', close: '22:00' }] },
    { days: [6], ranges: [{ open: '13:00', close: '22:00' }] },
  ],
  rating: { score: 4.1, max: 5, count: 295, source: 'yelp' },
  price_range: { level: 3, max: 4 },
  category: 'Italian Cuisine',
  provider: { kind: 'apple-maps', place_id: 'I6DF1454FE08462BE', url: 'https://maps.apple.com/place?name=Solevo' },
  map: { file_path: 'u/previews/map_1.png', provider: 'mapbox', style: 'mapbox/light-v11', zoom: 15, rendered_at: '2026-10-10T12:00:00.000Z' },
  evidence: { source_url: 'https://maps.apple/p/7mJUJoBjKam4Ns', observed_at: '2026-10-10T12:00:00.000Z', method: 'map-page', extraction_version: 'place-v1' },
};

describe('LocationDetailsSection', () => {
  beforeEach(() => {
    // Friday 2026-10-16, 2:30 PM in Saratoga Springs
    vi.useFakeTimers({ now: new Date('2026-10-16T18:30:00Z'), toFake: ['Date', 'setInterval', 'clearInterval'] });
  });
  afterEach(() => vi.useRealTimers());

  it('lists the place’s facts as a tree, says when it opens, and offers the cells', () => {
    render(<LocationDetailsSection place={place} />);
    expect(screen.getByRole('region', { name: 'Location details' })).toBeInTheDocument();
    expect(screen.getByText('location')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '55 Phila St, Saratoga Springs, NY 12866, United States' })).toHaveAttribute('href', 'https://maps.apple.com/place?name=Solevo');
    expect(screen.getByRole('button', { name: /closed · opens 4:00 PM/ })).toHaveAttribute('aria-expanded', 'false');
    expect(screen.getByRole('link', { name: '(518) 450-7094' })).toHaveAttribute('href', 'tel:+15184507094');
    expect(screen.getByRole('link', { name: 'solevokitchenandsocial.com' })).toHaveAttribute('href', 'http://www.solevokitchenandsocial.com/');
    expect(screen.getByRole('link', { name: 'menu on yelp' })).toBeInTheDocument();
    expect(screen.getByText('4.1 / 5 · 295 reviews · yelp')).toBeInTheDocument();
    expect(screen.getByText('$$$')).toBeInTheDocument();
    expect(screen.getByText('Italian Cuisine')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Directions/ })).toHaveAttribute('href', 'https://maps.apple.com/?daddr=43.080499%2C-73.783109&q=Solevo%20Kitchen%20%2B%20Social');
    expect(screen.getByRole('link', { name: /^Call/ })).toHaveAttribute('href', 'tel:+15184507094');
    expect(screen.getByRole('link', { name: /^Menu/ })).toHaveAttribute('href', place.menu_url);
    expect(screen.getByRole('link', { name: /^Website/ })).toHaveAttribute('href', place.website);
    expect(screen.getByRole('link', { name: 'open in apple maps' })).toHaveAttribute('href', place.provider.url);
    expect(screen.getByText(/From Apple Maps, observed Oct 10, 2026/)).toBeInTheDocument();
  });

  it('opens the week on the hours row', () => {
    render(<LocationDetailsSection place={place} />);
    fireEvent.click(screen.getByRole('button', { name: /closed · opens/ }));
    expect(screen.getByRole('button', { name: /closed · opens/ })).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByText('Mon–Thu')).toBeInTheDocument();
    expect(screen.getByText('4:00–9:00 PM')).toBeInTheDocument();
    expect(screen.getByText('Sun')).toBeInTheDocument();
  });

  it('shows today’s hours without claiming open or closed when the zone is unknown', () => {
    render(<LocationDetailsSection place={{ ...place, timezone: undefined }} />);
    const button = screen.getByRole('button', { name: /Fri 4:00–10:00 PM/ });
    expect(button.textContent).not.toMatch(/open ·|closed ·/);
  });

  it('renders nothing for a place with no facts and no coordinates', () => {
    const { container } = render(<LocationDetailsSection place={{ version: 1, provider: { kind: 'page', url: 'https://example.com' }, evidence: place.evidence }} />);
    expect(container).toBeEmptyDOMElement();
  });
});
