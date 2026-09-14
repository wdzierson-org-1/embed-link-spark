import React from 'react';
import { AudioLines, File, Mic, ScanLine, Table2 } from 'lucide-react';
import { audioSubtype, isScreenshotItem, isSpreadsheetExt, mimeExtensionLabel, TypeChip, MetaChip } from './CardBits';
import type { ItemAttributes } from '@/types/itemAttributes';

const CHIP_ICON = 'h-[11px] w-[11px]';

const LINK_FLAVOR_LABELS: Record<string, string> = {
  article: 'article',
  video: 'video',
  repo: 'repo',
  book: 'book',
  social: 'post',
  generic: 'link',
};

/** Type identity, disclosed beside the date on rollover. */
export const typeChipFor = (item: {
  type: string;
  title?: string;
  mime_type?: string;
  attributes?: ItemAttributes;
}): React.ReactNode => {
  switch (item.type) {
    case 'audio':
      return audioSubtype(item.attributes) === 'voice_note' ? (
        <TypeChip key="type" tint="voice" icon={<Mic className={CHIP_ICON} />}>
          voice note
        </TypeChip>
      ) : (
        <TypeChip key="type" tint="audio" icon={<AudioLines className={CHIP_ICON} />}>
          recording
        </TypeChip>
      );
    case 'document': {
      const ext = mimeExtensionLabel(item.mime_type);
      return isSpreadsheetExt(ext) ? (
        <TypeChip key="type" tint="doc" icon={<Table2 className={CHIP_ICON} />}>
          spreadsheet
        </TypeChip>
      ) : (
        <TypeChip key="type" tint="doc" icon={<File className={CHIP_ICON} />}>
          {ext ? ext.toLowerCase() : 'document'}
        </TypeChip>
      );
    }
    case 'image':
      return isScreenshotItem(item) ? (
        <TypeChip key="type" tint="shot" icon={<ScanLine className={CHIP_ICON} />}>
          screenshot
        </TypeChip>
      ) : (
        <MetaChip key="type">photo</MetaChip>
      );
    case 'video':
      return <MetaChip key="type">video</MetaChip>;
    case 'text':
      return <MetaChip key="type">note</MetaChip>;
    case 'link':
      return (
        <MetaChip key="type">{LINK_FLAVOR_LABELS[item.attributes?.link?.flavor ?? 'generic'] ?? 'link'}</MetaChip>
      );
    default:
      return null;
  }
};
