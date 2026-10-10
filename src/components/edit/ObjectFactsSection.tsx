import { ArrowUpRight } from 'lucide-react';
import { readObjectFacts } from '../../../supabase/functions/_shared/objectFacts';
import { readPlace } from '../../../supabase/functions/_shared/place';
import { SectionHead } from './EditPanelSection';

interface Props {
  item: { url?: string; attributes?: { object_facts?: unknown; [key: string]: unknown } };
}

const availabilityLabel: Record<string, string> = {
  InStock: 'In stock', OutOfStock: 'Out of stock', SoldOut: 'Sold out', BackOrder: 'Back order',
  PreOrder: 'Preorder', PreSale: 'Presale', LimitedAvailability: 'Limited availability',
  Discontinued: 'Discontinued', InStoreOnly: 'In store only', OnlineOnly: 'Online only',
  MadeToOrder: 'Made to order', Reserved: 'Reserved',
};

const Action = ({ href, children }: { href: string; children: React.ReactNode }) => (
  <a href={href} target="_blank" rel="noopener noreferrer" className="inline-flex min-h-11 items-center gap-2 border border-ink px-3 text-[13px] text-ink transition-colors hover:bg-ink hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink">
    {children}<ArrowUpRight aria-hidden="true" className="h-3.5 w-3.5" />
  </a>
);

/** Read-only, source-bound beta facts. Actions open searches; no prices are compared silently. */
export default function ObjectFactsSection({ item }: Props) {
  const facts = item.url ? readObjectFacts(item.attributes?.object_facts, item.url) : undefined;
  if (!facts) return null;
  // The location section (attributes.place) carries a place's facts in full; no second listing
  if (facts.kind === 'place' && readPlace(item.attributes?.place)) return null;
  const product = facts.product, place = facts.place;
  const rows: Array<[string, string | undefined]> = product ? [
    ['Brand', product.brand], ['Style / SKU', product.sku ?? product.mpn],
    ['Color', product.color], ['Size', product.size], ['Material', product.material],
    ['Price at capture', product.offer ? `${product.offer.price} ${product.offer.currency}` : undefined],
    ['Availability', product.offer?.availability ? availabilityLabel[product.offer.availability] : undefined],
  ] : [
    ['Address', place?.address ? Object.values(place.address).filter(Boolean).join(', ') : undefined],
    ['Cuisine', place?.cuisine?.join(', ')], ['Price range', place?.price_range],
  ];
  const visibleRows = rows.filter((row): row is [string, string] => !!row[1]);
  const observed = new Date(facts.evidence.observed_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  const source = new URL(facts.evidence.source_url);
  const productQuery = product ? [...new Set([product.brand, facts.name, product.sku ?? product.mpn, product.color, product.size].filter(Boolean))].join(' ') : '';
  const placeQuery = place?.geo ? `${place.geo.latitude},${place.geo.longitude}`
    : place?.address ? [facts.name, ...Object.values(place.address)].filter(Boolean).join(', ') : '';
  // No empty decoration for a classification with no displayable facts or useful action.
  if (!visibleRows.length && !productQuery && !placeQuery) return null;
  return (
    <section className="mt-[30px]" aria-label={product ? 'Product details' : 'Place details'}>
      <SectionHead label={product ? 'Product details' : 'Place details'} aside={<span className="bg-ink px-1.5 py-0.5 font-pixel text-pixel text-white">beta</span>} />
      {visibleRows.length > 0 && <dl className="mt-3.5 grid grid-cols-[minmax(90px,124px)_minmax(0,1fr)] gap-x-3 gap-y-2">
        {visibleRows.map(([label, value]) => <div key={label} className="contents">
          <dt className="font-pixel text-pixel lowercase text-muted-foreground">{label}</dt>
          <dd className="min-w-0 text-[14px] leading-[1.45] text-ink [overflow-wrap:anywhere]">{value}</dd>
        </div>)}
      </dl>}
      <p className="mt-3 text-[12px] leading-relaxed text-muted-foreground [overflow-wrap:anywhere]">
        Observed {observed} on{' '}
        <a href={source.href} target="_blank" rel="noopener noreferrer" className="underline underline-offset-2 hover:text-ink">{source.hostname.replace(/^www\./, '')}</a>.
        {product?.offer && ' Prices and availability can change.'}
      </p>
      {(productQuery || placeQuery) && <div className="mt-3.5 flex flex-wrap gap-2">
        {product && productQuery && <>
          <Action href={`https://search.brave.com/search?q=${encodeURIComponent(`${productQuery} buy price`)}`}>Compare retailers</Action>
          <Action href={`https://search.brave.com/search?q=${encodeURIComponent(`${productQuery} similar alternatives`)}`}>Find similar</Action>
        </>}
        {place && placeQuery && <Action href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(placeQuery)}`}>Open map</Action>}
      </div>}
      {product && productQuery && <p className="mt-2 text-[12px] text-muted-foreground">Opens a web search. Prices have not been compared.</p>}
    </section>
  );
}
