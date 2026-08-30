import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { motion, useReducedMotion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import {
  ArrowRight,
  Brain,
  MessageSquare,
  FileText,
  Globe,
  BookOpen,
  Mic,
  MapPin,
  Link2,
  UtensilsCrossed,
  ImageIcon,
  StickyNote,
  Play,
  type LucideIcon,
} from 'lucide-react';

import StashWordmark from '@/components/StashWordmark';
import LandingChatDemo from '@/components/LandingChatDemo';
import Cloth, { supportsHtmlInCanvas } from '@/components/landing/Cloth';
import LightRays from '@/components/landing/LightRays';
import demoAddLink from '@/assets/demo_add_link.mp4';
// Cover photos are real photographs via Unsplash (unsplash.com/license) —
// never AI renders or mocked-up interfaces; the cards must read as items a
// real person saved. IDs/credits in the commit that introduced each file.
import coverRecipe from '@/assets/landing/cover-recipe.jpg';
import coverArticle from '@/assets/landing/cover-article.jpg';
import coverRestaurant from '@/assets/landing/cover-restaurant.jpg';
import coverInspiration from '@/assets/landing/cover-inspiration.jpg';

// Static waveform for the voice-note card — heights are fixed so the Cloth
// canvas capture and reduced-motion renders are deterministic.
const VOICE_WAVE = [6, 11, 16, 9, 18, 13, 20, 8, 15, 19, 11, 17, 7, 13, 20, 12, 16, 9, 18, 12, 8, 14, 10, 6];

// The floating hero cards stand in for real stashed items — one believable
// object per capture type, each with the anatomy that type actually has in
// the library: covers for photos and places, a waveform for voice, tag chips
// on plain notes. No type gets a stock photo standing in for an interface.
const StashedCard = ({
  kind,
  icon: KindIcon,
  meta,
  title,
  note,
  coverSrc,
  coverClass = 'h-28',
  wave = false,
  tags,
  className,
}: {
  kind: string;
  icon: LucideIcon;
  meta?: string;
  title: string;
  note: string;
  coverSrc?: string;
  coverClass?: string;
  wave?: boolean;
  tags?: string[];
  className?: string;
}) => (
  <div className={`flex flex-col bg-card border border-border/20 rounded-lg p-3 ${className ?? ''}`}>
    {coverSrc && (
      <div className={`relative ${coverClass} flex-none overflow-hidden rounded-md mb-2`}>
        <img src={coverSrc} alt="" className="absolute inset-0 h-full w-full object-cover" />
      </div>
    )}
    {wave && (
      <div className="mb-2 flex h-11 flex-none items-center gap-2 rounded-md bg-violet-50/80 px-2.5">
        <span className="grid h-6 w-6 flex-none place-items-center rounded-full bg-violet-500 text-white">
          <Play className="h-3 w-3 fill-current" aria-hidden />
        </span>
        <span className="flex h-full flex-1 items-center gap-[3px]" aria-hidden>
          {VOICE_WAVE.map((h, i) => (
            <span key={i} className="w-[3px] flex-none rounded-full bg-violet-400/80" style={{ height: h }} />
          ))}
        </span>
      </div>
    )}
    <div className="mb-1.5 flex items-center justify-between gap-2">
      <span className="flex items-center gap-1 font-montreal text-[10px] uppercase tracking-wider text-muted-foreground/80">
        <KindIcon className="h-3 w-3" aria-hidden />
        {kind}
      </span>
      {meta && <span className="font-montreal text-[10px] text-muted-foreground/60">{meta}</span>}
    </div>
    <h4 className="font-tobias text-[15px] mb-1 leading-snug line-clamp-2">{title}</h4>
    <p className="text-xs text-muted-foreground font-montreal leading-snug line-clamp-2">{note}</p>
    {tags && (
      <div className="mt-2 flex flex-wrap gap-1">
        {tags.map(tag => (
          <span key={tag} className="rounded-full border border-border/40 bg-secondary/70 px-2 py-0.5 font-montreal text-[10px] text-muted-foreground">
            {tag}
          </span>
        ))}
      </div>
    )}
  </div>
);

// Scattered-on-a-table layout for the floating hero cards: uneven insets from
// the screen edge, irregular vertical gaps, and per-card entrance motion so
// nothing reads as a tidy column. Width/height are explicit pixels because the
// Cloth capture canvas can't derive intrinsic size from its children.
interface FloatingCardSpec {
  side: 'left' | 'right';
  pos: string;          // absolute top/inset classes
  size: { w: number; h: number };
  tilt: number;         // resting rotation, deg
  entrance: { x: number; y: number; rotate: number };
  delay: number;        // entrance delay, s (deliberately out of visual order)
  float: { dur: number; y: number; rot: number };
  scrollRot: number;    // scroll-linked rotation factor
  card: React.ComponentProps<typeof StashedCard>;
}

const FLOATING_CARDS: FloatingCardSpec[] = [
  {
    side: 'left',
    pos: 'top-16 left-5',
    size: { w: 224, h: 244 },
    tilt: 2.5,
    entrance: { x: -170, y: -50, rotate: -12 },
    delay: 0.5,
    float: { dur: 6.4, y: 7, rot: 1.2 },
    scrollRot: 0.03,
    card: {
      kind: 'Recipe',
      icon: UtensilsCrossed,
      meta: '40 min',
      title: 'Tomato & mozzarella penne',
      note: 'For Sunday — full recipe captured.',
      coverSrc: coverRecipe,
    },
  },
  {
    side: 'left',
    pos: 'top-[21.5rem] left-12',
    size: { w: 240, h: 158 },
    tilt: -4,
    entrance: { x: -200, y: 40, rotate: 10 },
    delay: 0.15,
    float: { dur: 7.8, y: 9, rot: 1.5 },
    scrollRot: -0.02,
    card: {
      kind: 'Voice note',
      icon: Mic,
      meta: '2:41',
      title: 'Ideas from the drive home',
      note: '“…and don’t forget — book the cabin for the long weekend…”',
      wave: true,
    },
  },
  {
    side: 'left',
    pos: 'top-[33.5rem] left-7',
    size: { w: 216, h: 252 },
    tilt: 5.5,
    entrance: { x: -150, y: 70, rotate: 18 },
    delay: 0.85,
    float: { dur: 5.6, y: 6, rot: 1 },
    scrollRot: 0.025,
    card: {
      kind: 'Image',
      icon: ImageIcon,
      meta: 'inspiration',
      title: 'Ceramics for the open shelves',
      note: 'Ask for “those cream vases” — Stash will know.',
      coverSrc: coverInspiration,
      coverClass: 'h-32',
    },
  },
  {
    side: 'right',
    pos: 'top-20 right-8',
    size: { w: 240, h: 248 },
    tilt: -2.5,
    entrance: { x: 180, y: -60, rotate: 11 },
    delay: 0.05,
    float: { dur: 7.1, y: 8, rot: 1.3 },
    scrollRot: -0.03,
    card: {
      kind: 'Place',
      icon: MapPin,
      meta: 'West Village',
      title: 'Chez Colette',
      note: 'Anniversary dinner? Ask for the corner table.',
      coverSrc: coverRestaurant,
    },
  },
  {
    side: 'right',
    pos: 'top-[23rem] right-4',
    size: { w: 232, h: 240 },
    tilt: 3.5,
    entrance: { x: 160, y: 30, rotate: -14 },
    delay: 0.65,
    float: { dur: 6.9, y: 7, rot: 1.4 },
    scrollRot: 0.02,
    card: {
      kind: 'Link',
      icon: Link2,
      meta: '9 min read',
      title: 'Why you remember so little of what you read',
      note: 'Full text saved — ask for it anytime.',
      coverSrc: coverArticle,
      coverClass: 'h-24',
    },
  },
  {
    side: 'right',
    pos: 'top-[39rem] right-14',
    size: { w: 224, h: 168 },
    tilt: -5,
    entrance: { x: 190, y: 80, rotate: -20 },
    delay: 0.35,
    float: { dur: 8.4, y: 9, rot: 1.1 },
    scrollRot: 0.02,
    card: {
      kind: 'Note',
      icon: StickyNote,
      meta: 'auto-tagged',
      title: 'Gift idea for Sam',
      note: 'The ceramic pour-over from the market — birthday is Oct 12.',
      tags: ['gifts', 'sam'],
    },
  },
];

// Numbered kickers that give the page's sections a visible spine
const SectionEyebrow = ({ index, label }: { index: string; label: string }) => (
  <div className="mb-5 flex items-center justify-center gap-3 font-montreal text-[11px] uppercase tracking-[0.28em] text-muted-foreground/70">
    <span className="h-px w-10 bg-border" aria-hidden />
    <span>{index} — {label}</span>
    <span className="h-px w-10 bg-border" aria-hidden />
  </div>
);

const CAPABILITIES: { icon: LucideIcon; chip: string; iconColor: string; title: string; body: string }[] = [
  {
    icon: FileText,
    chip: 'border-blue-200/60 bg-blue-100 group-hover:bg-blue-200/70',
    iconColor: 'text-blue-600',
    title: 'Drop anything in',
    body: 'Links, PDFs, images, voice notes, video, plain thoughts. One box for all of it — no sorting first.',
  },
  {
    icon: Globe,
    chip: 'border-green-200/60 bg-green-100 group-hover:bg-green-200/70',
    iconColor: 'text-green-600',
    title: 'Links describe themselves',
    body: 'Paste a URL and Stash fetches the title, preview image, and full page text on its own.',
  },
  {
    icon: BookOpen,
    chip: 'border-orange-200/60 bg-orange-100 group-hover:bg-orange-200/70',
    iconColor: 'text-orange-600',
    title: 'Documents read themselves',
    body: 'PDFs are read, summarized, and made searchable the moment they land in your stash.',
  },
  {
    icon: Mic,
    chip: 'border-red-200/60 bg-red-100 group-hover:bg-red-200/70',
    iconColor: 'text-red-600',
    title: 'Voice becomes text',
    body: 'Voice notes are transcribed and summarized automatically, so spoken thoughts are findable too.',
  },
  {
    icon: MessageSquare,
    chip: 'border-teal-200/60 bg-teal-100 group-hover:bg-teal-200/70',
    iconColor: 'text-teal-600',
    title: 'Text it by WhatsApp or SMS',
    body: 'Text a link, photo, or voice note to your Stash number without opening the app at all.',
  },
  {
    icon: Brain,
    chip: 'border-purple-200/60 bg-purple-100 group-hover:bg-purple-200/70',
    iconColor: 'text-purple-600',
    title: 'Ask instead of dig',
    body: "Chat with everything you've saved and get answers back with the sources they came from.",
  },
];

const Landing = () => {
  const [scrollY, setScrollY] = useState(0);
  const prefersReducedMotion = useReducedMotion();
  // When the browser can render the cloth (HTML-in-canvas), the fabric supplies
  // the idle motion; without it, framer's float keeps the cards alive.
  const [clothActive] = useState(() => supportsHtmlInCanvas());

  useEffect(() => {
    const handleScroll = () => setScrollY(window.scrollY);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const gradientOpacity = Math.max(0, 1 - (scrollY / 800));
  const cardsTranslate = Math.min(scrollY * 0.5, 400);

  return (
    <div className="min-h-screen bg-background font-montreal relative overflow-hidden paper-texture">
      {/* Animated Hero Gradient */}
      <div
        className="fixed inset-0 hero-gradient pointer-events-none z-[700] transition-opacity duration-300"
        style={{
          opacity: gradientOpacity,
          height: '100vh'
        }}
      />

      {/* Dusk the top of the hero slightly so the screen-blended rays have
          something to glow against — fades to nothing well before the fold */}
      <div
        className="fixed inset-x-0 top-0 pointer-events-none z-[720] transition-opacity duration-300"
        style={{
          opacity: gradientOpacity,
          height: '65vh',
          background:
            'linear-gradient(to bottom, rgba(74,42,125,0.30) 0%, rgba(74,42,125,0.13) 35%, transparent 70%)',
        }}
      />

      {/* Soft light rays over the hero — fades out with the gradient on scroll.
          Screen blend keeps only the light: the canvas's dark field disappears
          into the page instead of graying it out. */}
      <div
        className="fixed inset-x-0 top-0 pointer-events-none z-[750] mix-blend-screen transition-opacity duration-300"
        style={{ opacity: gradientOpacity, height: '100vh' }}
      >
        <LightRays
          raysOrigin="top-center"
          raysColor="#eadaff"
          raysSpeed={0.8}
          lightSpread={0.9}
          rayLength={2.0}
          followMouse
          mouseInfluence={0.06}
          noiseAmount={0.06}
          distortion={0.04}
        />
      </div>

      {/* Floating stashed cards, scattered like cards on a table. Only from lg
          up, where there are margins for them to sit in; below that they crowd
          the hero copy. Each card springs in from its screen edge on its own
          schedule, then hangs like fabric rippling in the wind (Cloth) — brush
          them with the cursor. Browsers without HTML-in-canvas get the same
          cards with a gentle framer float instead. */}
      {(['left', 'right'] as const).map(side => (
        <div
          key={side}
          className={`hidden lg:block fixed top-0 h-screen w-80 pointer-events-none ${
            side === 'left' ? 'left-0 z-[800]' : 'right-0 z-[850]'
          }`}
        >
          {FLOATING_CARDS.filter(c => c.side === side).map(c => (
            <div
              key={c.card.title}
              className={`absolute ${c.pos} transform-gpu transition-transform duration-500 ease-out`}
              style={{
                transform: `translateX(${side === 'left' ? -cardsTranslate : cardsTranslate}px) rotate(${scrollY * c.scrollRot}deg)`,
              }}
            >
              <motion.div
                initial={prefersReducedMotion ? false : {
                  opacity: 0,
                  x: c.entrance.x,
                  y: c.entrance.y,
                  rotate: c.entrance.rotate,
                  scale: 0.85,
                }}
                animate={{ opacity: 1, x: 0, y: 0, rotate: c.tilt, scale: 1 }}
                transition={{ type: 'spring', stiffness: 78, damping: 11.5, mass: 1, delay: c.delay }}
              >
                <motion.div
                  animate={prefersReducedMotion || clothActive ? undefined : {
                    y: [0, -c.float.y, 0],
                    rotate: [0, c.float.rot, 0],
                  }}
                  transition={{
                    duration: c.float.dur,
                    repeat: Infinity,
                    repeatType: 'mirror',
                    ease: 'easeInOut',
                    delay: c.delay + 1.4,
                  }}
                >
                  <Cloth
                    // Fallback browsers get a CSS shadow here — the card's own
                    // shadow is clipped by the cloth's overflow-hidden capture
                    // box; when the fabric renders it draws its own shadow.
                    className={`pointer-events-auto rounded-lg ${clothActive ? '' : 'shadow-md'}`}
                    style={{ width: c.size.w, height: c.size.h }}
                    pin="top"
                    wind={3}
                    speed={0.5}
                    amplitude={18}
                    drape={22}
                    brush={2.05}
                    brushSize={120}
                    damping={1}
                    light={0.5}
                    sheen={0.1}
                    shadow={0.25}
                    cornerRadius={12}
                    perspective={1000}
                  >
                    <StashedCard className="h-full w-full" {...c.card} />
                  </Cloth>
                </motion.div>
              </motion.div>
            </div>
          ))}
        </div>
      ))}

      {/* Main Content */}
      <div className="relative z-[1000]">
        {/* Navigation */}
        <nav className="flex items-center justify-between px-6 py-4 max-w-5xl mx-auto relative z-[1100]">
          <div className="flex items-center">
            <StashWordmark className="h-5 text-[#666666]" />
          </div>

          <div className="flex items-center space-x-3">
            <Link to="/auth">
              <Button variant="ghost" className="text-muted-foreground hover:text-foreground text-sm font-montreal">
                Sign In
              </Button>
            </Link>
            <Link to="/pricing">
              <Button className="bg-foreground text-background hover:bg-foreground/90 text-sm px-4 py-2 rounded-full font-montreal">
                Get Started
              </Button>
            </Link>
          </div>
        </nav>

        {/* Hero Section */}
        <section className="px-6 pt-24 pb-32 max-w-4xl mx-auto text-center">
          <div className="fade-in">
            <h1 className="text-5xl md:text-7xl font-tobias font-thin text-foreground mb-8 leading-[1.05] tracking-tight">
              Save anything <span className="font-editorial-italic">easily</span>.<br />
              <span className="text-muted-foreground">Find everything <span className="font-editorial-italic">effortlessly</span>.</span>
            </h1>

            <p className="text-xl font-montreal text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
              Links, PDFs, screenshots, voice notes — toss them into Stash. Stash understands each one, describes it, stores it for later, and makes it easy to find.
            </p>

            <div className="slide-up">
              <Link to="/pricing">
                <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg font-montreal">
                  Start stashing — free for 14 days
                </Button>
              </Link>
              <p className="text-sm font-montreal text-muted-foreground mt-4">
                Then $4.99/month. No credit card to start.
              </p>
            </div>
          </div>
        </section>

        {/* The Middle Section */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center">
            <SectionEyebrow index="01" label="One place" />
            <h2 className="text-3xl md:text-4xl font-tobias tracking-tight leading-[1.15] text-foreground mb-4">Your every <span className="font-editorial-italic">thing</span> app.</h2>
            <p className="text-lg font-montreal text-muted-foreground max-w-2xl mx-auto">
              Notes, links, files, photos, voice memos — everything you'd normally scatter across five apps, in one place that remembers all of it.
            </p>
          </div>
        </section>

        {/* Capabilities Grid */}
        <section className="px-6 py-24 max-w-6xl mx-auto">
          <div className="text-center mb-14">
            <SectionEyebrow index="02" label="Zero effort" />
            <h2 className="text-3xl md:text-4xl font-tobias tracking-tight leading-[1.15] text-foreground max-w-3xl mx-auto">No need to tag, describe, organize, or think. We do it all for you.</h2>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {CAPABILITIES.map(({ icon: Icon, chip, iconColor, title, body }) => (
              <div
                key={title}
                className="group rounded-2xl border border-border/60 bg-card/70 p-6 text-left backdrop-blur-[2px] transition-all duration-300 hover:-translate-y-1 hover:border-violet-200 hover:shadow-[0_12px_32px_rgba(160,120,200,0.16)]"
              >
                <div className={`mb-4 grid h-10 w-10 place-items-center rounded-xl border transition-colors ${chip}`}>
                  <Icon className={`h-5 w-5 ${iconColor}`} />
                </div>
                <h3 className="text-lg font-tobias leading-snug text-foreground mb-2">{title}</h3>
                <p className="text-sm text-muted-foreground font-montreal leading-relaxed">{body}</p>
              </div>
            ))}
          </div>
        </section>

        {/* Paste Demo Section */}
        <section className="px-6 py-24 max-w-6xl mx-auto">
          <div className="text-center mb-14">
            <SectionEyebrow index="03" label="Watch it work" />
            <h2 className="text-3xl md:text-4xl font-tobias tracking-tight leading-[1.15] text-foreground mb-4 max-w-3xl mx-auto">Just paste the link and Stash does the describing <span className="font-editorial-italic">automagically</span>.</h2>
            <p className="text-lg font-montreal text-muted-foreground max-w-2xl mx-auto">
              Stash collects everything it can about a link the moment you paste it — title, preview, full text — and makes it searchable. No description to write, nothing to categorize.
            </p>
          </div>

          <div className="max-w-3xl mx-auto">
            <video
              src={demoAddLink}
              autoPlay
              loop
              muted
              playsInline
              className="w-full rounded-2xl shadow-2xl border border-border"
            >
              Your browser does not support the video tag.
            </video>
          </div>
        </section>

        {/* Product Screenshots - Overlapping Cards Style */}
        <section className="px-6 py-24 max-w-6xl mx-auto">
          <div className="text-center mb-14">
            <SectionEyebrow index="04" label="Your library" />
            <h2 className="text-3xl md:text-4xl font-tobias tracking-tight leading-[1.15] text-foreground mb-4">Capture everything, search anything</h2>
            <p className="text-lg font-montreal text-muted-foreground max-w-2xl mx-auto">
              Voice, video, text, links, and images. We transcribe the contents and make everything searchable and conversational.
            </p>
          </div>

          {/* Mobile: simple stack */}
          <div className="md:hidden max-w-md mx-auto space-y-5">
            <img
              src="/lovable-uploads/6913186c-7298-435f-8962-6d5a231a5a0f.png"
              alt="Input panel interface"
              className="w-full rounded-xl shadow-lg border border-border"
            />
            <img
              src="/lovable-uploads/0515aeee-180b-4aa5-bfa0-b96ae2b400c5.png"
              alt="Content management interface"
              className="w-full rounded-xl shadow-lg border border-border"
            />
            <img
              src="/lovable-uploads/4171b995-b0c1-447a-90fe-f204f543463b.png"
              alt="Public feed example"
              className="w-full rounded-xl shadow-lg border border-border"
            />
          </div>

          {/* Desktop: tight fanned cluster */}
          <div className="hidden md:block relative h-[28rem] max-w-4xl mx-auto">
            {/* Public feed peeking through behind */}
            <div className="absolute top-32 left-1/2 -translate-x-1/2 z-10 hover:z-40">
              <img
                src="/lovable-uploads/4171b995-b0c1-447a-90fe-f204f543463b.png"
                alt="Public feed example"
                className="w-72 rounded-xl shadow-lg border border-border rotate-1 hover:rotate-0 transition-transform duration-300"
              />
            </div>

            {/* Left card grid */}
            <div className="absolute top-20 left-6 z-20 hover:z-40">
              <img
                src="/lovable-uploads/0515aeee-180b-4aa5-bfa0-b96ae2b400c5.png"
                alt="Content management interface"
                className="w-96 rounded-xl shadow-xl border border-border -rotate-2 hover:rotate-0 transition-transform duration-300"
              />
            </div>

            {/* Right card grid */}
            <div className="absolute top-24 right-6 z-20 hover:z-40">
              <img
                src="/lovable-uploads/157b2b06-2c4f-4e1c-aea1-e690e426776b.png"
                alt="Content organization example"
                className="w-96 rounded-xl shadow-xl border border-border rotate-2 hover:rotate-0 transition-transform duration-300"
              />
            </div>

            {/* Input panel front and center on top */}
            <div className="absolute top-0 left-1/2 -translate-x-1/2 z-30 hover:z-40">
              <img
                src="/lovable-uploads/6913186c-7298-435f-8962-6d5a231a5a0f.png"
                alt="Input panel interface"
                className="w-[34rem] max-w-none rounded-xl shadow-xl border border-border -rotate-1 hover:rotate-0 transition-transform duration-300"
              />
            </div>
          </div>
        </section>

        {/* AI Chat Section */}
        <section className="px-6 py-24 max-w-6xl mx-auto">
          <div className="text-center mb-14">
            <SectionEyebrow index="05" label="Total recall" />
            <h2 className="text-4xl md:text-5xl font-tobias text-foreground mb-5 tracking-tight leading-[1.1]">
              Forget about forgetting
            </h2>
            <p className="text-xl md:text-2xl font-tobias text-muted-foreground mb-5 max-w-2xl mx-auto">
              Chat with your notes, insights, memories, and photos
            </p>
            <p className="text-lg font-montreal text-muted-foreground max-w-2xl mx-auto">
              Ask questions about anything you've saved. Our AI understands the context and connections across all your content.
            </p>
          </div>

          <LandingChatDemo />
        </section>

        {/* Call to Action */}
        <section className="px-6 py-32 max-w-4xl mx-auto text-center">
          <h2 className="text-4xl font-tobias tracking-tight leading-[1.15] text-foreground mb-6">
            Your future self will ask.<br />
            <span className="text-muted-foreground">Stash will have the <span className="font-editorial-italic">answer</span>.</span>
          </h2>
          <p className="text-xl font-montreal text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
            Try it free for two weeks — save a handful of things, then ask for them back. That's the whole pitch.
          </p>
          <Link to="/pricing">
            <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg font-montreal">
              Start your free two week trial
              <ArrowRight className="ml-3 h-5 w-5" />
            </Button>
          </Link>
          <p className="text-sm font-montreal text-muted-foreground mt-4">
            14 days free, then $4.99/month.
          </p>
        </section>

        {/* Footer */}
        <footer className="px-6 py-16 max-w-4xl mx-auto text-center border-t border-border mt-20 relative z-[1000]">
          <div className="flex items-center justify-center mb-6">
            <StashWordmark className="h-5 text-foreground" />
          </div>
          <p className="text-sm font-montreal text-muted-foreground mb-8">
            Forget about forgetting.
          </p>
          <div className="flex justify-center space-x-6 text-sm font-montreal text-muted-foreground">
            <Link to="/privacy" className="hover:text-foreground transition-colors">Privacy</Link>
            <Link to="/terms" className="hover:text-foreground transition-colors">Terms</Link>
            <a href="mailto:will@dzierson.com" className="hover:text-foreground transition-colors">Contact</a>
          </div>
        </footer>
      </div>

      {/* Bottom Gradient */}
      <div className="absolute bottom-0 inset-x-0 hero-gradient pointer-events-none z-[700] rotate-180" style={{ height: '60vh' }} />
    </div>
  );
};

export default Landing;
