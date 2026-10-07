import { audioSubtype, isScreenshotItem, isSpreadsheetExt, mimeExtensionLabel } from './CardBits';
import type { GlyphName } from '@/components/machine/PixelGlyph';
import type { ItemAttributes } from '@/types/itemAttributes';

const LINK_FLAVOR_LABELS: Record<string, string> = {
  article: 'article',
  video: 'video',
  repo: 'repo',
  book: 'book',
  social: 'post',
  generic: 'link',
};

interface KindItem {
  type: string;
  title?: string;
  mime_type?: string;
  attributes?: ItemAttributes;
}

/**
 * What kind of thing a save is, in the machine's words: the black tag on a card's media
 * (DESIGN-v2: "the kind is a black tag"), lowercase. Replaces v1's tinted type chips.
 */
export const kindLabel = (item: KindItem): string => {
  switch (item.type) {
    case 'audio':
      return audioSubtype(item.attributes) === 'voice_note' ? 'voice note' : 'recording';
    case 'document': {
      const ext = mimeExtensionLabel(item.mime_type);
      if (isSpreadsheetExt(ext)) return 'spreadsheet';
      return ext ? ext.toLowerCase() : 'document';
    }
    case 'image':
      return isScreenshotItem(item) ? 'screenshot' : 'photo';
    case 'video':
      return 'video';
    case 'text':
      return 'note';
    case 'collection':
      return 'multi-part';
    case 'link':
      return LINK_FLAVOR_LABELS[item.attributes?.link?.flavor ?? 'generic'] ?? 'link';
    default:
      return item.type;
  }
};

// Places carry no link flavor of their own; their hosts give them away (as on the homepage)
const PLACE_HOST = /^((maps\.)?google\.[a-z.]+\/maps|maps\.google\.|maps\.apple\.com|maps\.app\.goo\.gl|goo\.gl\/maps|yelp\.[a-z.]+\/biz|opentable\.|resy\.com|tripadvisor\.|airbnb\.[a-z.]+\/rooms|booking\.com\/hotel)/i;

/** The pixel glyph a placeholder draws for this kind of save when it has no picture */
export const kindGlyph = (item: KindItem & { url?: string }): GlyphName => {
  switch (item.type) {
    case 'audio':
      return audioSubtype(item.attributes) === 'voice_note' ? 'voice' : 'recording';
    case 'image':
      return 'photo';
    case 'video':
      return 'video';
    case 'text':
    case 'collection':
      return 'note';
    case 'document':
      return 'page';
    case 'link': {
      const where = (item.url ?? '').replace(/^https?:\/\/(www\.)?/i, '');
      if (PLACE_HOST.test(where)) return 'place';
      const flavor = item.attributes?.link?.flavor;
      return flavor === 'repo' || flavor === 'video' || flavor === 'book' || flavor === 'social' || flavor === 'article'
        ? flavor
        : 'page';
    }
    default:
      return 'page';
  }
};
