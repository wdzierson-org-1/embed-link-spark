/**
 * What Firecrawl v2 returns for a YouTube watch page (spec 2026-09-05): markdown with the video's
 * facts (`**Length**`, `**Uploaded by**`), a `## Description` block (often fenced) and a
 * `## Transcript` block of caption lines. This reads those parts out; everything is tolerant of
 * small format drift, and a page without a transcript section yields `transcript: null`.
 */
export interface YouTubeMarkdown {
  transcript: string | null;
  description: string | null;
  durationS: number | null;
  author: string | null;
}

export const MAX_TRANSCRIPT_CHARS = 200_000;

const clockToSeconds = (clock: string): number | null => {
  const parts = clock.trim().split(':').map((part) => Number(part));
  if (parts.some((part) => !Number.isFinite(part)) || parts.length < 2 || parts.length > 3) return null;
  return parts.reduce((total, part) => total * 60 + part, 0);
};

const unfence = (block: string): string =>
  block.replace(/^\s*```[a-z]*\s*\n?/i, '').replace(/\n?\s*```\s*$/i, '').trim();

const stripLink = (text: string): string => text.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').trim();

/** The lines of a markdown section: from its heading to the next heading of the same or higher level */
const section = (markdown: string, heading: RegExp): string | null => {
  const lines = markdown.split(/\r?\n/);
  const start = lines.findIndex((line) => heading.test(line.trim()));
  if (start < 0) return null;
  const level = (lines[start].match(/^#+/) ?? ['##'])[0].length;
  const body: string[] = [];
  for (const line of lines.slice(start + 1)) {
    const match = line.match(/^(#+)\s/);
    if (match && match[1].length <= level) break;
    body.push(line);
  }
  return body.join('\n').trim();
};

/** Caption lines: timestamps and cue numbers dropped, blank runs collapsed */
const cleanTranscript = (text: string): string | null => {
  const lines = text
    .split(/\r?\n/)
    .map((line) =>
      line
        .replace(/^\s*(?:\[\d{1,2}:\d{2}(?::\d{2})?\]|\(\d{1,2}:\d{2}(?::\d{2})?\)|\d{1,2}:\d{2}(?::\d{2})?(?:\s*-->\s*\d{1,2}:\d{2}(?::\d{2})?)?)\s*/, '')
        .replace(/^\s*\d+\s*$/, '')
        .trim(),
    )
    .filter((line) => line.length > 0);
  const joined = lines.join('\n').trim();
  if (!joined || /^(?:no transcript|transcript (?:is )?(?:unavailable|not available)|captions? (?:are )?(?:disabled|unavailable))/i.test(joined)) return null;
  return joined.slice(0, MAX_TRANSCRIPT_CHARS);
};

const fact = (markdown: string, label: RegExp): string | null => {
  const match = markdown.match(new RegExp(`\\*\\*\\s*(?:${label.source})\\s*\\*\\*\\s*:?\\s*([^\\n]+)`, 'i'));
  return match ? stripLink(match[1]).trim() : null;
};

export const parseYouTubeMarkdown = (markdown: string | null | undefined): YouTubeMarkdown => {
  const source = (markdown ?? '').replace(/\r\n/g, '\n');
  if (!source.trim()) return { transcript: null, description: null, durationS: null, author: null };

  const transcriptBlock = section(source, /^#{1,4}\s*transcript\b/i);
  const descriptionBlock = section(source, /^#{1,4}\s*description\b/i);
  const descriptionText = descriptionBlock ? unfence(descriptionBlock) : '';
  const firstParagraph = descriptionText
    .split(/\n\s*\n/)
    .map((paragraph) => stripLink(paragraph).replace(/\s+/g, ' ').trim())
    .find((paragraph) => paragraph.length > 0);
  const length = fact(source, /length|duration/);
  const author = fact(source, /uploaded by|channel|author|uploader/);

  return {
    transcript: transcriptBlock ? cleanTranscript(transcriptBlock) : null,
    description: firstParagraph ? firstParagraph.slice(0, 300) : null,
    durationS: length ? clockToSeconds(length.replace(/[^\d:]/g, '')) : null,
    author: author || null,
  };
};
