import { useEffect, useState } from 'react';
import { ArrowUpRight, ChevronDown } from 'lucide-react';
import { SectionHead } from './EditPanelSection';
import { FactRow } from './FactTree';
import type { PlaceAttributes } from '../../../supabase/functions/_shared/place';
import { SUPABASE_URL } from '@/integrations/supabase/client';
import {
  addressLines, directionsUrl, formatPhone, hostOf, hoursRows, openInLabel, openLabel, openState, priceLabel, providerName, ratingLabel, telHref,
} from '@/utils/placeFacts';

interface Props {
  place: PlaceAttributes;
}

const Cell = ({ href, children }: { href: string; children: React.ReactNode }) => (
  <a
    href={href}
    target={href.startsWith('tel:') ? undefined : '_blank'}
    rel="noopener noreferrer"
    className="inline-flex min-h-11 items-center gap-2 border border-ink px-3 text-[13px] text-ink transition-colors hover:bg-ink hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
  >
    {children}
    <ArrowUpRight aria-hidden="true" className="h-3.5 w-3.5" />
  </a>
);

const External = ({ href, children }: { href: string; children: React.ReactNode }) => (
  <a href={href} target="_blank" rel="noopener noreferrer" className="text-ink underline decoration-ink/40 underline-offset-[3px] hover:decoration-ink">
    {children}
  </a>
);

/**
 * The location section (DESIGN-v2 §12.8; Will, 2026-10-10: "a new 'location details' section,
 * similar to the item details section"): what the place's own page says — address, hours,
 * phone, website, menu, rating, price — as a fact tree, then the cells that act on it.
 * "open · closes 9:00 PM" is said only when the provider gave the place's time zone.
 */
export default function LocationDetailsSection({ place }: Props) {
  const [hoursOpen, setHoursOpen] = useState(false);
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  const lines = addressLines(place);
  const rows = hoursRows(place.hours);
  const state = openState(place.hours, place.timezone, now);
  const todayIndex = state ? undefined : now.getDay();
  const todayRow = rows.find((row) => row.days.includes(todayIndex ?? -1));
  const directions = directionsUrl(place);
  const provider = providerName(place);
  const observed = new Date(place.evidence.observed_at);
  const observedLabel = Number.isNaN(observed.getTime()) ? '' : observed.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  const hasFacts = lines.length > 0 || rows.length > 0 || place.phone || place.website || place.menu_url || place.rating || place.price_range || place.category;
  if (!hasFacts && !directions) return null;
  // A place read from a picture's own text keeps the photo as the save's picture, so its map
  // sits here instead; a map link's map is the picture on the stage above
  const mapInSection = place.provider.kind === 'ocr' && place.map?.file_path
    ? `${SUPABASE_URL}/storage/v1/object/public/stash-media/${place.map.file_path}`
    : undefined;

  return (
    <section className="mt-[30px]" aria-label="Location details">
      <SectionHead
        label="location"
        aside={
          <a href={place.provider.url} target="_blank" rel="noopener noreferrer" className="font-pixel text-pixel lowercase text-muted-foreground hover:text-ink hover:underline">
            open in {openInLabel(place)}
          </a>
        }
      />
      {mapInSection && (
        <a href={place.provider.url} target="_blank" rel="noopener noreferrer" className="mt-3 block max-w-[520px]">
          <img src={mapInSection} alt={`Map of ${lines.join(', ') || 'the place'}`} className="block w-full border border-line shadow-object" loading="lazy" />
        </a>
      )}
      <div className="v2-tree mt-2">
        {lines.length > 0 && (
          <FactRow label="Address">
            <External href={place.provider.url}>{lines.join(', ')}</External>
          </FactRow>
        )}
        {rows.length > 0 && (
          <FactRow label="Hours">
            <button
              type="button"
              onClick={() => setHoursOpen((open) => !open)}
              aria-expanded={hoursOpen}
              className="group inline-flex max-w-full items-baseline gap-2 text-left"
            >
              <span className={state ? 'font-pixel text-pixel text-ink' : 'text-[14px] text-ink'}>
                {state ? openLabel(state) : todayRow ? `${todayRow.label} ${todayRow.value}` : rows[0].value}
              </span>
              <ChevronDown
                aria-hidden="true"
                className={`h-[15px] w-[15px] flex-none self-center text-muted-foreground transition-transform duration-[180ms] group-hover:text-ink motion-reduce:transition-none ${hoursOpen ? 'rotate-180' : ''}`}
              />
            </button>
            {hoursOpen && (
              <dl className="mt-2 grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-1">
                {rows.map((row) => (
                  <div key={row.label} className="contents">
                    <dt className="font-pixel text-pixel lowercase text-muted-foreground">{row.label}</dt>
                    <dd className="text-[14px] tabular-nums text-ink">{row.value}</dd>
                  </div>
                ))}
              </dl>
            )}
          </FactRow>
        )}
        {place.phone && (
          <FactRow label="Phone">
            <a href={telHref(place.phone)} className="text-ink underline decoration-ink/40 underline-offset-[3px] hover:decoration-ink">{formatPhone(place.phone)}</a>
          </FactRow>
        )}
        {place.website && (
          <FactRow label="Website">
            <External href={place.website}>{hostOf(place.website) ?? place.website}</External>
          </FactRow>
        )}
        {place.menu_url && (
          <FactRow label="Menu">
            <External href={place.menu_url}>{hostOf(place.menu_url) === 'yelp.com' ? 'menu on yelp' : hostOf(place.menu_url) ?? 'menu'}</External>
          </FactRow>
        )}
        {place.rating && <FactRow label="Rating">{ratingLabel(place.rating)}</FactRow>}
        {place.price_range && <FactRow label="Price">{priceLabel(place.price_range)}</FactRow>}
        {place.category && <FactRow label="Category">{place.category}</FactRow>}
      </div>
      <div className="mt-3.5 flex flex-wrap gap-2">
        {directions && <Cell href={directions}>Directions</Cell>}
        {place.phone && <Cell href={telHref(place.phone)}>Call</Cell>}
        {place.menu_url && <Cell href={place.menu_url}>Menu</Cell>}
        {place.website && <Cell href={place.website}>Website</Cell>}
      </div>
      <p className="mt-3 text-[12px] leading-relaxed text-muted-foreground">
        From {provider}{place.provider.kind === 'ocr' ? ', confirmed on the map' : ''}{observedLabel ? `, observed ${observedLabel}` : ''}. Hours and details can change.
      </p>
    </section>
  );
}
