import { render, screen } from '@testing-library/react';
import ObjectFactsSection from './ObjectFactsSection';
import type { ObjectFacts } from '../../../supabase/functions/_shared/objectFacts';

const url = 'https://shop.example/alpine';
const product: ObjectFacts = { version: 1, beta: true, kind: 'product', name: 'Alpine Jacket', product: { brand: 'Mountain Goods', sku: 'ALPINE', material: 'Wool', offer: { price: '748.00', currency: 'USD', availability: 'InStock' } }, evidence: { source_url: url, observed_at: '2026-10-10T14:00:00.000Z', method: 'json-ld', extraction_version: 'object-facts-v1', schema_type: 'Product' } };
const item = { url, attributes: { object_facts: product } };

it('shows beta publisher facts with an observed price and source', () => {
  render(<ObjectFactsSection item={item} />);
  expect(screen.getByText('beta')).toBeVisible();
  expect(screen.getByText('Mountain Goods')).toBeVisible();
  expect(screen.getByText(/748\.00 USD/)).toBeVisible();
  expect(screen.getByText(/Observed Oct 10, 2026/)).toBeVisible();
  expect(screen.getByRole('link', { name: 'shop.example' })).toHaveAttribute('href', url);
  expect(screen.getByRole('link', { name: /Compare retailers/ })).toHaveAttribute('href', expect.stringContaining('https://search.brave.com/search?q='));
  expect(screen.getByText(/Opens a web search/)).toBeVisible();
});

it('does not promise a current price or show a price row when no variant offer is verified', () => {
  render(<ObjectFactsSection item={{ ...item, attributes: { object_facts: { ...product, product: { sku: 'ALPINE', material: 'Wool' } } } }} />);
  expect(screen.queryByText('Price at capture')).not.toBeInTheDocument();
  expect(screen.queryByText(/748/)).not.toBeInTheDocument();
  expect(screen.getByText('ALPINE')).toBeVisible();
});

it('uses the place location for a map and keeps it distinct from capture location', () => {
  const place: ObjectFacts = { ...product, kind: 'place', name: 'Village Cafe', product: undefined, place: { address: { street_address: '1 Main Street', locality: 'New York' }, geo: { latitude: 40.735, longitude: -74.005 }, cuisine: ['Italian'], price_range: '$$' }, evidence: { ...product.evidence, schema_type: 'Restaurant' } };
  render(<ObjectFactsSection item={{ url, attributes: { object_facts: place, location: { label: 'San Francisco' } } }} />);
  expect(screen.getByText(/1 Main Street, New York/)).toBeVisible();
  expect(screen.getByText('Italian')).toBeVisible();
  expect(screen.getByRole('link', { name: /Open map/ })).toHaveAttribute('href', 'https://www.google.com/maps/search/?api=1&query=40.735%2C-74.005');
  expect(screen.queryByText('San Francisco')).not.toBeInTheDocument();
  expect(screen.queryByRole('link', { name: /Compare retailers/ })).not.toBeInTheDocument();
});

it.each([undefined, { ...product, version: 2 }, { ...product, evidence: { ...product.evidence, source_url: 'https://unrelated.example/' } }])('hides absent, unsupported, or source-mismatched facts', facts => {
  const { container } = render(<ObjectFactsSection item={{ url, attributes: { object_facts: facts } }} />);
  expect(container).toBeEmptyDOMElement();
});

it('keeps verified selected color and size in retailer searches', () => {
  const selectedUrl = `${url}?variant=navy-xl`;
  render(<ObjectFactsSection item={{ url: selectedUrl, attributes: { object_facts: { ...product, product: { ...product.product, color: 'Navy', size: 'XL' }, evidence: { ...product.evidence, source_url: selectedUrl } } } }} />);
  const target = new URL(screen.getByRole('link', { name: /Compare retailers/ }).getAttribute('href')!);
  expect(target.searchParams.get('q')).toContain('Navy XL');
});
