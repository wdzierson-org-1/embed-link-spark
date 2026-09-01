// Citation links in Ask Stash answers.
//
// The server has the model cite saved items two ways: titles as markdown links
// targeting the citation number (`[Beyond the Basics](#3)`) and bare bracket
// markers (`[3]`). At stream end we "bake" both into stable item links
// (`[Beyond the Basics](#item=<uuid>)`) using the sources' citation numbers,
// and persist the baked text — so links keep working when history is reloaded
// later, when the sources array is no longer around.

export interface CitedSource {
  id: string;
  n?: number;
}

export const ITEM_LINK_PREFIX = '#item=';

export const bakeCitationLinks = (content: string, sources: CitedSource[]): string => {
  const byN = new Map<number, string>();
  for (const source of sources) {
    if (typeof source.n === 'number') byN.set(source.n, source.id);
  }
  if (!byN.size) return content;

  return content
    // Linked titles: [Title](#3) → [Title](#item=<id>)
    .replace(/\]\(#(\d+)\)/g, (match, n) => {
      const id = byN.get(Number(n));
      return id ? `](${ITEM_LINK_PREFIX}${id})` : match;
    })
    // Bare markers: [3] → [[3]](#item=<id>), skipping ones that are already
    // link text (followed by "(") or part of a baked link (preceded by "[")
    .replace(/(?<!\[)\[(\d+)\](?!\()/g, (match, n) => {
      const id = byN.get(Number(n));
      return id ? `[[${n}]](${ITEM_LINK_PREFIX}${id})` : match;
    });
};

export const extractLinkedItemIds = (content: string): Set<string> => {
  const ids = new Set<string>();
  for (const match of content.matchAll(/\(#item=([0-9a-f-]+)\)/g)) {
    ids.add(match[1]);
  }
  return ids;
};

export const itemIdFromHref = (href: string | undefined): string | null => {
  if (!href || !href.startsWith(ITEM_LINK_PREFIX)) return null;
  return href.slice(ITEM_LINK_PREFIX.length) || null;
};
