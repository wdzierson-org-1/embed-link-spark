import React, { useEffect, useMemo, useState } from 'react';
import { ChevronDown } from 'lucide-react';
import { SECTION_LABEL_CLASS } from '@/components/edit/EditPanelSection';
import EditItemLocationSection from '@/components/EditItemLocationSection';
import { domainOfUrl } from '@/utils/linkFlavor';
import { fileBasename, fileExtensionLabel, formatBytes, formatClock } from '@/utils/itemFacts';
import type { ItemAttributes } from '@/types/itemAttributes';

/**
 * The Details drawer (DESIGN.md "Detail panel"): collapsed by default, the
 * header answers the common question inline (format · size · duration); one
 * tap opens dotted-leader key/value rows — original filename, format, source,
 * saved date, and the location editor.
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

const FactRow = ({
  label,
  mono = false,
  children,
}: {
  label: string;
  mono?: boolean;
  children: React.ReactNode;
}) => (
  <div className="flex items-baseline gap-2.5 py-[7.5px] text-[13px]">
    <span className="flex-none text-[#959ba6]">{label}</span>
    <span className="flex-1" />
    <span
      className={`max-w-[60%] text-right [overflow-wrap:anywhere] ${
        mono
          ? 'font-mono text-[11.5px] font-normal text-[#22262f]'
          : 'font-medium text-[#22262f]'
      }`}
    >
      {children}
    </span>
  </div>
);

const EditItemDetailsDrawer = ({ item, onSaveAttributes }: EditItemDetailsDrawerProps) => {
  const [open, setOpen] = useState(false);

  // A different item reopens the drawer closed
  useEffect(() => {
    setOpen(false);
  }, [item.id]);

  const fileName = item.attributes?.media?.file_name || fileBasename(item.file_path);
  const extLabel = fileExtensionLabel(fileName, item.mime_type);
  const sizeLabel = formatBytes(item.file_size);
  const durationLabel = formatClock(item.attributes?.media?.duration_s);
  const isFileBacked = FILE_BACKED_TYPES.has(item.type ?? '');
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
        className="group flex w-full items-center justify-between gap-3 border-b border-black/[0.07] pb-[7px] text-left"
      >
        <span className={`${SECTION_LABEL_CLASS} transition-colors group-hover:text-[#646b76]`}>
          Details
        </span>
        <span className="inline-flex items-center gap-2 text-[11.5px] text-[#959ba6]">
          {!open && summary && <span className="tabular-nums">{summary}</span>}
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
        className={`mt-1.5 divide-y divide-dotted divide-[rgba(0,0,0,0.18)] ${
          open ? 'block' : 'hidden'
        }`}
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
                className="text-[#6d5bd0] hover:underline"
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
