import React, { useEffect, useMemo, useState } from 'react';
import { ChevronDown } from 'lucide-react';
import { SECTION_LABEL_CLASS } from '@/components/edit/EditPanelSection';
import { FactRow } from '@/components/edit/FactTree';
import EditItemLocationSection from '@/components/EditItemLocationSection';
import { domainOfUrl } from '@/utils/linkFlavor';
import { fileBasename, fileExtensionLabel, formatBytes, formatClock } from '@/utils/itemFacts';
import type { ItemAttributes } from '@/types/itemAttributes';

/**
 * The Details drawer: open by default, listing the facts as a tree, the way a terminal lists
 * them (DESIGN-v2: `├─` / `└─` in Departure Mono): original filename, format, source, saved
 * date, and the location editor. Collapsed, its head answers the common question inline
 * (format · size · duration).
 */

interface DrawerItem {
  id: string;
  type?: string;
  title?: string;
  url?: string;
  file_path?: string;
  mime_type?: string;
  file_size?: number;
  created_at?: string;
  attributes?: ItemAttributes;
}

interface EditItemDetailsDrawerProps {
  item: DrawerItem;
  onSaveAttributes?: (attributes: ItemAttributes) => Promise<void>;
}

const FILE_BACKED_TYPES = new Set(['audio', 'video', 'image', 'document', 'pdf']);

const EditItemDetailsDrawer = ({ item, onSaveAttributes }: EditItemDetailsDrawerProps) => {
  const [open, setOpen] = useState(true);

  // A different item opens the drawer expanded again
  useEffect(() => {
    setOpen(true);
  }, [item.id]);

  // Only an upload has an original file; a link's file_path is the cover Stash stored for it
  const isFileBacked = FILE_BACKED_TYPES.has(item.type ?? '');
  const fileName = isFileBacked ? item.attributes?.media?.file_name || fileBasename(item.file_path) : '';
  const extLabel = fileExtensionLabel(fileName, item.mime_type);
  const sizeLabel = formatBytes(item.file_size);
  const durationLabel = formatClock(item.attributes?.media?.duration_s);
  const domain = item.type === 'link' ? domainOfUrl(item.url) : '';

  const savedAt = useMemo(() => {
    if (!item.created_at) return '';
    const date = new Date(item.created_at);
    if (Number.isNaN(date.getTime())) return '';
    const day = date.toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
    const time = date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    return `${day} · ${time}`;
  }, [item.created_at]);

  const summary = useMemo(() => {
    const parts = (
      isFileBacked
        ? [extLabel, sizeLabel, durationLabel]
        : [domain, item.attributes?.link?.read_time_min
            ? `${item.attributes.link.read_time_min} min`
            : '']
    ).filter(Boolean);
    if (parts.length > 0) return parts.join(' · ');
    return savedAt.split(' · ')[0] || '';
  }, [isFileBacked, extLabel, sizeLabel, durationLabel, domain, item.attributes, savedAt]);

  const formatLabel = [extLabel, sizeLabel].filter(Boolean).join(' · ');

  return (
    <div className="mt-[30px]">
      <button
        type="button"
        onClick={() => setOpen((current) => !current)}
        aria-expanded={open}
        className="group flex min-h-7 w-full items-end justify-between gap-3 border-b border-ink pb-1.5 text-left"
      >
        <span className={`${SECTION_LABEL_CLASS} group-hover:underline`}>
          details
        </span>
        <span className="inline-flex items-center gap-2 font-pixel text-pixel text-muted-foreground">
          {!open && summary && <span className="tabular-nums">{summary.toLowerCase()}</span>}
          <ChevronDown
            className={`h-[15px] w-[15px] transition-transform duration-[180ms] motion-reduce:transition-none ${
              open ? 'rotate-180' : ''
            }`}
          />
        </span>
      </button>

      {/* Kept mounted while closed: the location editor's local state is the
          source of truth after a save (the sheet's item prop stays frozen) */}
      <div
        className={`v2-tree mt-2 ${open ? 'block' : 'hidden'}`}
      >
          {fileName && (
            <FactRow label="Original file" mono>
              {fileName}
            </FactRow>
          )}
          {formatLabel && <FactRow label="Format">{formatLabel}</FactRow>}
          {durationLabel && <FactRow label="Duration">{durationLabel}</FactRow>}
          {item.type === 'link' && item.url && (
            <FactRow label="Source URL">
              <a
                href={item.url}
                target="_blank"
                rel="noreferrer"
                className="text-ink underline decoration-ink/40 underline-offset-[3px] hover:decoration-ink"
              >
                {domain || item.url}
              </a>
            </FactRow>
          )}
          {savedAt && <FactRow label="Saved">{savedAt}</FactRow>}
          {onSaveAttributes && (
            <FactRow label="Location">
              <EditItemLocationSection
                itemId={item.id}
                attributes={item.attributes}
                onSaveAttributes={onSaveAttributes}
              />
            </FactRow>
          )}
      </div>
    </div>
  );
};

export default EditItemDetailsDrawer;
