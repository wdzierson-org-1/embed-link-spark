import React from 'react';
import { domainOfUrl } from '@/utils/linkFlavor';
import { kindLabel } from '@/components/cards/ItemTypeChip';
import { St4shSymbol } from '@/components/brand/St4sh';
import type { ItemAttributes } from '@/types/itemAttributes';

export interface WindowBarItem {
  type?: string | null;
  title?: string | null;
  mime_type?: string | null;
  attributes?: ItemAttributes | null;
  url?: string | null;
  created_at?: string | null;
}

/** `saved oct 6 2026`, the machine's date */
export const savedOnLabel = (createdAt?: string | null): string => {
  if (!createdAt) return '';
  const date = new Date(createdAt);
  return Number.isNaN(date.getTime())
    ? ''
    : date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }).replace(',', '').toLowerCase();
};

/**
 * The window bar (DESIGN-v2 §12.8: Stash's own furniture is a window): what this save is and
 * where it came from, in the machine voice. The item panel puts its share cell and close at the
 * right end; the shared page (§12.15) shows the same bar over the same object.
 */
const ItemWindowBar = ({ item, children }: { item: WindowBarItem; children?: React.ReactNode }) => {
  const savedOn = savedOnLabel(item.created_at);
  const source = item.type === 'link' ? domainOfUrl(item.url ?? undefined) : '';
  return (
    <div className="flex h-11 flex-none items-center gap-2.5 bg-ink pl-4 pr-12 text-white sm:pl-10">
      <St4shSymbol className="h-[13px] w-[12px] flex-none text-spot-on-ink" />
      <span className="flex min-w-0 items-center gap-2 truncate font-pixel text-pixel leading-none">
        <span className="bg-white px-1.5 pb-[3px] pt-1 text-ink">
          {kindLabel({ type: item.type ?? 'text', title: item.title, mime_type: item.mime_type, attributes: item.attributes })}
        </span>
        {source && <span className="truncate">{source}</span>}
        {savedOn && <span className="truncate text-white/60">saved {savedOn}</span>}
      </span>
      {children && <div className="ml-auto flex flex-none items-center">{children}</div>}
    </div>
  );
};

export default ItemWindowBar;
