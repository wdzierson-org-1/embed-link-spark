import React from 'react';
import {
  AudioLines,
  FileText,
  Github,
  Link2,
  MapPin,
  MoreVertical,
  Play,
  Star,
  StickyNote,
} from 'lucide-react';
import ContentItem from '@/components/ContentItem';

/**
 * Dev-only design review page (/design/cards) — not routed in production.
 *
 * REV 2 of the single-object card system. Changes from rev 1:
 *  - Height scale: exactly two hero heights (standard 10rem / tall 14rem for
 *    portrait media) instead of ad-hoc sizes — masonry reads intentional
 *  - Metadata-poor fallback designed (blocked sites get a favicon plate +
 *    slug-derived title, never a broken hero)
 *  - Filenames are never titles — media gets an AI title; the filename
 *    demotes to a mono metadata chip
 *  - Annotation (your words) and description (extracted) coexist with a clear
 *    hierarchy on the same card
 *  - Location appears only as the pin — no "posted from" line in note text
 */

const cardShell =
  'group flex flex-col bg-card border-0 shadow-[0_1px_2px_rgba(20,22,30,0.05),0_8px_24px_rgba(30,33,44,0.08)] hover:shadow-[0_2px_4px_rgba(20,22,30,0.06),0_14px_36px_rgba(30,33,44,0.13)] hover:-translate-y-0.5 transition-all duration-200 relative rounded-2xl';

/** The height scale — the only two hero heights in the system */
const HERO_STANDARD = 'h-40'; // 10rem — landscape imagery, plates
const HERO_TALL = 'h-56'; // 14rem — portrait media, contained

const REAL_IMAGE =
  'https://uqqsgmwkvslaomzxptnp.supabase.co/storage/v1/object/public/stash-media/0a0afaa8-0e11-47e9-887f-223816a9bb53/staging/1786462595740-kna3wd.png';
const TIKTOK_THUMB = 'https://picsum.photos/seed/ramen/360/640';
const ARTICLE_THUMB = 'https://picsum.photos/seed/tokyo/640/360';
const BOOK_COVER = 'https://picsum.photos/seed/hardcover/380/560';
const MEETING_THUMB = 'https://picsum.photos/seed/meeting/640/360';

const MetaChip = ({ icon, mono, children }: { icon?: React.ReactNode; mono?: boolean; children: React.ReactNode }) => (
  <span
    className={`inline-flex max-w-full items-center gap-1 truncate rounded-full bg-black/[0.04] px-2 py-0.5 text-[11px] font-medium text-foreground/60 ${mono ? 'font-mono text-[10px]' : ''}`}
  >
    {icon}
    <span className="truncate">{children}</span>
  </span>
);

/** The user's words — always visually distinct from extracted text */
const Annotation = ({ children }: { children: React.ReactNode }) => (
  <p className="border-l-2 border-violet-300 pl-3 text-[13.5px] leading-snug text-foreground/75 line-clamp-2">
    {children}
  </p>
);

const CardFooter = ({ date, location, badge }: { date: string; location?: string; badge: string }) => (
  <div className="mt-auto flex items-center justify-between pt-3">
    <div className="flex min-w-0 items-center gap-2">
      <p className="whitespace-nowrap text-xs text-muted-foreground">{date}</p>
      {location && (
        <p className="flex min-w-0 items-center gap-0.5 text-xs text-muted-foreground">
          <MapPin className="h-3 w-3 flex-none" />
          <span className="max-w-[150px] truncate">{location}</span>
        </p>
      )}
    </div>
    <div className="flex items-center gap-2">
      <span className="rounded-full bg-secondary px-2.5 py-0.5 text-[11px] font-medium text-secondary-foreground/80">
        {badge}
      </span>
      <MoreVertical className="h-4 w-4 text-muted-foreground" />
    </div>
  </div>
);

const Waveform = ({ bars = 28, className = '' }: { bars?: number; className?: string }) => (
  <div className={`flex items-center gap-[3px] ${className}`}>
    {Array.from({ length: bars }, (_, i) => (
      <span
        key={i}
        className="w-[3px] rounded-full bg-violet-400/70"
        style={{ height: `${6 + Math.abs(Math.sin(i * 1.7)) * 18}px` }}
      />
    ))}
  </div>
);

/** Portrait media contained on a blurred self-backdrop — never center-cropped */
const ContainedMedia = ({ src, overlay }: { src: string; overlay?: React.ReactNode }) => (
  <div className={`relative ${HERO_TALL} overflow-hidden rounded-t-2xl bg-gray-900`}>
    <img src={src} alt="" className="absolute inset-0 h-full w-full scale-125 object-cover opacity-40 blur-xl" />
    <img src={src} alt="" className="relative mx-auto h-full object-contain" />
    {overlay}
  </div>
);

/* -------------------------------- the cards ------------------------------- */

/** Link · article — the default. Extracted description AND user annotation
    coexist: extraction speaks first in muted text, your words get the bar. */
const ArticleLinkCard = () => (
  <div className={cardShell}>
    <div className={`${HERO_STANDARD} overflow-hidden rounded-t-2xl`}>
      <img src={ARTICLE_THUMB} alt="" className="h-full w-full object-cover" />
    </div>
    <div className="flex flex-1 flex-col gap-2.5 p-6">
      <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
        medium.com · Kenji Ito · 6 min read
      </p>
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight line-clamp-2">Five days in Tokyo, done right</h3>
      <p className="line-clamp-2 text-sm text-muted-foreground">
        Skip the checklist tourism. A neighborhood-first itinerary that leaves room for the city to surprise you.
      </p>
      <Annotation>Route the Yanaka day around this — it matches the counter-guy's advice.</Annotation>
      <CardFooter date="Aug 13, 2026" badge="article" />
    </div>
  </div>
);

/** Link · metadata-poor — the promise held even when the site blocks us.
    Favicon plate + slug-derived title; honest about what we could get. */
const BlockedLinkCard = () => (
  <div className={cardShell}>
    <div className="flex items-center gap-3 rounded-t-2xl border-b border-black/5 bg-gradient-to-b from-gray-50 to-gray-100/60 p-5">
      <span className="grid h-12 w-12 flex-none place-items-center rounded-2xl bg-[#0a66c2] text-lg font-bold text-white shadow-sm">
        in
      </span>
      <div className="min-w-0">
        <p className="text-[13px] font-medium text-foreground/80">linkedin.com</p>
        <p className="text-[11px] text-muted-foreground">preview limited · saved anyway</p>
      </div>
    </div>
    <div className="flex flex-1 flex-col gap-2.5 p-6">
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight line-clamp-2">Senior Product Designer — Linear</h3>
      <Annotation>Send to Dana before Friday.</Annotation>
      <CardFooter date="Aug 12, 2026" badge="link" />
    </div>
  </div>
);

/** Link · book — portrait cover, location recall */
const BookLinkCard = () => (
  <div className={cardShell}>
    <ContainedMedia src={BOOK_COVER} />
    <div className="flex flex-1 flex-col gap-2.5 p-6">
      <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
        bookshop.org · Vintage · 2024
      </p>
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight line-clamp-2">The Extended Mind</h3>
      <Annotation>Recommended by the guy at the counter — about thinking outside the brain.</Annotation>
      <CardFooter date="Aug 9, 2026" location="Bleecker St, New York" badge="book" />
    </div>
  </div>
);

/** Link · short-form video */
const TikTokCard = () => (
  <div className={cardShell}>
    <ContainedMedia
      src={TIKTOK_THUMB}
      overlay={
        <span className="absolute left-1/2 top-1/2 grid h-12 w-12 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-black/50 backdrop-blur">
          <Play className="h-5 w-5 fill-white text-white" />
        </span>
      }
    />
    <div className="flex flex-1 flex-col gap-2.5 p-6">
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight line-clamp-2">7 ramen counters worth the line in Shinjuku</h3>
      <div className="flex flex-wrap gap-1.5">
        <MetaChip icon={<Play className="h-3 w-3" />}>tiktok.com</MetaChip>
        <MetaChip>0:42</MetaChip>
        <MetaChip>@tokyoeats</MetaChip>
      </div>
      <CardFooter date="Aug 14, 2026" badge="video link" />
    </div>
  </div>
);

/** Link · GitHub repo */
const GitHubCard = () => (
  <div className={cardShell}>
    <div className="rounded-t-2xl bg-[#0d1117] p-5">
      <p className="flex items-center gap-2 font-mono text-sm text-white/90">
        <Github className="h-4 w-4" />
        pmndrs<span className="text-white/40">/</span>
        <span className="font-semibold">zustand</span>
      </p>
      <p className="mt-2 line-clamp-2 text-[13px] leading-snug text-white/60">
        Bear necessities for state management in React
      </p>
      <div className="mt-3 flex items-center gap-3 text-[11px] text-white/50">
        <span className="flex items-center gap-1">
          <span className="h-2.5 w-2.5 rounded-full bg-[#3178c6]" />
          TypeScript
        </span>
        <span className="flex items-center gap-1">
          <Star className="h-3 w-3" />
          48.2k
        </span>
        <span>Updated 2d ago</span>
      </div>
    </div>
    <div className="flex flex-1 flex-col gap-2.5 p-6">
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight">zustand — tiny state manager</h3>
      <Annotation>Try this instead of Redux for the mole rewrite.</Annotation>
      <CardFooter date="Aug 13, 2026" badge="repo" />
    </div>
  </div>
);

/** Image — AI title; the filename is metadata, not a headline */
const PhotoCard = () => (
  <div className={cardShell}>
    <ContainedMedia src={REAL_IMAGE} />
    <div className="flex flex-1 flex-col gap-2.5 p-6">
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight line-clamp-2">Books that shaped my thinking</h3>
      <div className="flex flex-wrap gap-1.5">
        <MetaChip mono>CleanShot 2026-08-11.png</MetaChip>
        <MetaChip>PNG · 1.0 MB</MetaChip>
        <MetaChip>text detected</MetaChip>
      </div>
      <CardFooter date="Aug 11, 2026" badge="image" />
    </div>
  </div>
);

/** Audio · voice note */
const VoiceNoteCard = () => (
  <div className={cardShell}>
    <div className="flex flex-1 flex-col gap-3 p-6">
      <div className="flex items-center gap-3 rounded-xl bg-violet-50/70 p-3.5">
        <span className="grid h-10 w-10 flex-none place-items-center rounded-full bg-violet-500 shadow-sm">
          <Play className="h-4 w-4 fill-white text-white" />
        </span>
        <Waveform bars={26} className="flex-1" />
        <span className="text-xs font-medium text-violet-600">0:58</span>
      </div>
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight line-clamp-2">Neighborhood ideas for the trip</h3>
      <p className="line-clamp-2 text-sm text-muted-foreground">
        "Okay so — Yanaka for the old-town feel, then maybe base ourselves in Shimokitazawa instead of Shibuya…"
      </p>
      <div className="flex flex-wrap gap-1.5">
        <MetaChip icon={<AudioLines className="h-3 w-3" />}>voice note</MetaChip>
        <MetaChip>transcribed</MetaChip>
      </div>
      <CardFooter date="Aug 12, 2026" location="Brooklyn, NY" badge="audio" />
    </div>
  </div>
);

/** Video · meeting recording */
const MeetingRecordingCard = () => (
  <div className={cardShell}>
    <div className={`relative ${HERO_STANDARD} overflow-hidden rounded-t-2xl bg-gray-900`}>
      <img src={MEETING_THUMB} alt="" className="h-full w-full object-cover opacity-80" />
      <span className="absolute left-1/2 top-1/2 grid h-12 w-12 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-black/50 backdrop-blur">
        <Play className="h-5 w-5 fill-white text-white" />
      </span>
      <span className="absolute bottom-2 right-2 rounded-md bg-black/70 px-1.5 py-0.5 text-[11px] font-medium text-white">
        47:12
      </span>
    </div>
    <div className="flex flex-1 flex-col gap-2.5 p-6">
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight line-clamp-2">Q3 partner sync — InsideTracker</h3>
      <p className="line-clamp-2 text-sm text-muted-foreground">
        Decisions: ship the demo revision by Friday; Sam owns the pricing one-pager; revisit SSO next call.
      </p>
      <div className="flex flex-wrap gap-1.5">
        <MetaChip mono>partner-sync-0814.mp4</MetaChip>
        <MetaChip>412 MB</MetaChip>
        <MetaChip>transcribed · 3 speakers</MetaChip>
      </div>
      <CardFooter date="Aug 14, 2026" badge="video" />
    </div>
  </div>
);

/** Document · PDF */
const DocumentCard = () => (
  <div className={cardShell}>
    <div className="flex items-center gap-3 rounded-t-2xl border-b border-black/5 bg-gray-50/80 p-4">
      <span className="grid h-11 w-11 flex-none place-items-center rounded-xl bg-red-50">
        <FileText className="h-5 w-5 text-red-500" />
      </span>
      <div className="min-w-0">
        <p className="truncate font-mono text-[12px] text-foreground/70">wine-pairing-notes.pdf</p>
        <p className="text-[11px] text-muted-foreground">PDF · 24 pages · 2.1 MB</p>
      </div>
    </div>
    <div className="flex flex-1 flex-col gap-2.5 p-6">
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight line-clamp-2">Wine pairings for the tasting menu</h3>
      <p className="line-clamp-2 text-sm text-muted-foreground">
        A sommelier's working notes on matching the spring menu — leans natural, heavy on Jura whites.
      </p>
      <CardFooter date="Aug 10, 2026" badge="document" />
    </div>
  </div>
);

/** Text · note — the words are the object */
const TextNoteCard = () => (
  <div className={cardShell}>
    <div className="flex flex-1 flex-col gap-2.5 p-6">
      <h3 className="font-montreal font-medium tracking-[-0.014em] text-xl leading-tight line-clamp-2">Morning pages</h3>
      <p className="line-clamp-4 whitespace-pre-line text-sm leading-relaxed text-foreground/75">
        The best interface is the one that disappears. Stop designing screens; start designing exits.
        {'\n'}Also: call the framer about the two prints.
      </p>
      <div className="flex flex-wrap gap-1.5">
        <MetaChip icon={<StickyNote className="h-3 w-3" />}>note</MetaChip>
      </div>
      <CardFooter date="Aug 16, 2026" location="Brooklyn, NY" badge="note" />
    </div>
  </div>
);

/* -------------------------------- the page ------------------------------- */

const Captioned = ({ caption, children }: { caption: string; children: React.ReactNode }) => (
  <div className="flex flex-col gap-2">
    <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{caption}</p>
    {children}
  </div>
);

const masonryItems: Array<{ key: string; node: React.ReactNode }> = [
  { key: 'article', node: <ArticleLinkCard /> },
  { key: 'voice', node: <VoiceNoteCard /> },
  { key: 'book', node: <BookLinkCard /> },
  { key: 'note', node: <TextNoteCard /> },
  { key: 'github', node: <GitHubCard /> },
  { key: 'photo', node: <PhotoCard /> },
  { key: 'blocked', node: <BlockedLinkCard /> },
  { key: 'tiktok', node: <TikTokCard /> },
  { key: 'meeting', node: <MeetingRecordingCard /> },
  { key: 'pdf', node: <DocumentCard /> },
];

const noop = () => {};
const emptySet = new Set<string>();

/** Real ContentItem components fed per-type mock rows — verifies the wiring */
const wiredItems = [
  {
    id: 'w-article',
    type: 'link' as const,
    title: 'Five days in Tokyo, done right',
    url: 'https://medium.com/@kenji/five-days-in-tokyo',
    file_path: 'https://picsum.photos/seed/tokyo/640/360',
    description: 'Skip the checklist tourism. A neighborhood-first itinerary.',
    content: 'Route the Yanaka day around this.',
    created_at: '2026-08-13T10:00:00Z',
    attributes: { link: { flavor: 'article' as const } },
  },
  {
    id: 'w-repo',
    type: 'link' as const,
    title: 'zustand — tiny state manager',
    url: 'https://github.com/pmndrs/zustand',
    description: 'Bear necessities for state management in React',
    content: 'Try this instead of Redux for the mole rewrite.',
    created_at: '2026-08-13T09:00:00Z',
    attributes: { link: { flavor: 'repo' as const } },
  },
  {
    id: 'w-tiktok',
    type: 'link' as const,
    title: '7 ramen counters worth the line in Shinjuku',
    url: 'https://www.tiktok.com/@tokyoeats/video/724',
    file_path: 'https://picsum.photos/seed/ramen/360/640',
    created_at: '2026-08-14T10:00:00Z',
    attributes: { link: { flavor: 'video' as const } },
  },
  {
    id: 'w-blocked',
    type: 'link' as const,
    title: 'Senior Product Designer — Linear',
    url: 'https://www.linkedin.com/jobs/view/4373761967',
    content: 'Send to Dana before Friday.',
    created_at: '2026-08-12T10:00:00Z',
    attributes: { link: { flavor: 'generic' as const } },
  },
  {
    id: 'w-image',
    type: 'image' as const,
    title: 'Books that shaped my thinking',
    file_path: '0a0afaa8-0e11-47e9-887f-223816a9bb53/staging/1786462595740-kna3wd.png',
    file_size: 1048576,
    mime_type: 'image/png',
    created_at: '2026-08-11T10:00:00Z',
    attributes: {
      media: { file_name: 'CleanShot 2026-08-11.png' },
      location: { label: 'Bleecker St, New York', source: 'browser-geolocation' as const },
    },
  },
  {
    id: 'w-audio',
    type: 'audio' as const,
    title: 'Neighborhood ideas for the trip',
    description: '"Okay so — Yanaka for the old-town feel, then maybe Shimokitazawa…"',
    mime_type: 'audio/mp4',
    file_size: 2411724,
    created_at: '2026-08-12T08:00:00Z',
    attributes: { media: { duration_s: 58, file_name: 'memo.m4a' }, location: { label: 'Brooklyn, NY', source: 'manual' as const } },
  },
  {
    id: 'w-doc',
    type: 'document' as const,
    title: 'Wine pairings for the tasting menu',
    description: "A sommelier's working notes on matching the spring menu.",
    mime_type: 'application/pdf',
    file_size: 2202009,
    summary: 'present',
    created_at: '2026-08-10T10:00:00Z',
    attributes: { media: { file_name: 'wine-pairing-notes.pdf' } },
  },
  {
    id: 'w-text',
    type: 'text' as const,
    title: 'Morning pages',
    content: 'The best interface is the one that disappears. Stop designing screens; start designing exits.',
    created_at: '2026-08-16T08:00:00Z',
    attributes: { location: { label: 'Brooklyn, NY', source: 'manual' as const } },
  },
];

const DesignCardPreview = () => (
  <div className="min-h-screen bg-gradient-to-b from-[#fdf4fb] to-white">
    <div className="container mx-auto px-6 py-10">
      <h1 className="font-montreal font-semibold tracking-[-0.02em] text-3xl">Card system · rev 2</h1>
      <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
        Changes from rev 1: a two-height hero scale (10rem / 14rem for portrait), a designed fallback for
        metadata-poor links, filenames demoted to mono chips (AI titles everywhere), extracted description and your
        annotation coexisting with clear hierarchy, and location only as the pin — no text line.
      </p>

      <h2 className="mt-10 font-montreal font-semibold tracking-[-0.02em] text-2xl">Wired — the real components</h2>
      <p className="mb-5 mt-0.5 text-sm text-muted-foreground">
        Actual ContentItem renders in the app's row-major grid: newest reads left-to-right, each row
        stretches to its tallest card, footers pin to the bottom.
      </p>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
        {wiredItems.map((item) => (
          <ContentItem
            key={item.id}
            item={item}
            tags={[]}
            imageErrors={emptySet}
            expandedContent={emptySet}
            onImageError={noop}
            onToggleExpansion={noop}
            onDeleteItem={noop}
            onEditItem={noop}
            onTagsUpdated={noop}
          />
        ))}
      </div>

      <h2 className="mt-10 font-montreal font-semibold tracking-[-0.02em] text-2xl">The dashboard, together</h2>
      <p className="mb-5 mt-0.5 text-sm text-muted-foreground">
        All ten cards flowing in a masonry column layout — how a real mixed feed would read.
      </p>
      <div className="columns-1 gap-6 md:columns-2 xl:columns-3 [&>*]:mb-6 [&>*]:break-inside-avoid">
        {masonryItems.map(({ key, node }) => (
          <div key={key}>{node}</div>
        ))}
      </div>

      <h2 className="mt-12 font-montreal font-semibold tracking-[-0.02em] text-2xl">Rev 2 details, called out</h2>
      <div className="mt-5 grid grid-cols-1 gap-8 md:grid-cols-2 xl:grid-cols-3">
        <Captioned caption="Fallback · blocked site → favicon plate, slug title, honest chip">
          <BlockedLinkCard />
        </Captioned>
        <Captioned caption="Hierarchy · extracted description first, your annotation barred">
          <ArticleLinkCard />
        </Captioned>
        <Captioned caption="Filenames are metadata now — AI title leads">
          <PhotoCard />
        </Captioned>
      </div>
    </div>
  </div>
);

export default DesignCardPreview;
