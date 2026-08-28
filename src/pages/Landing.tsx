import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import Lenis from 'lenis';
import { Button } from '@/components/ui/button';
import { ArrowRight } from 'lucide-react';

import StashWordmark from '@/components/StashWordmark';
import LandingChatDemo from '@/components/LandingChatDemo';
import LightRays from '@/components/landing/LightRays';
import TryStash from '@/components/landing/TryStash';
import demoAddLink from '@/assets/demo_add_link.mp4';

// Quiet section label — plain tracked small caps, no numbering, no rules.
// The page's sections aren't a sequence; pretending otherwise is decoration.
const SectionLabel = ({ children }: { children: React.ReactNode }) => (
  <p className="mb-4 font-mori text-[11px] uppercase tracking-[0.24em] text-muted-foreground/70">
    {children}
  </p>
);

// What you toss in → what Stash does with it. The ledger IS the product
// explanation: each row is one real transformation the pipeline performs.
const LEDGER: { thing: string; done: string }[] = [
  { thing: 'A link you’ll want later', done: 'Title, preview, and the full page text — fetched and made searchable.' },
  { thing: 'A PDF', done: 'Read and summarized, ready to quote.' },
  { thing: 'A voice memo', done: 'Transcribed word for word.' },
  { thing: 'A screenshot', done: 'Every pixel read — names, prices, places.' },
  { thing: 'A half-formed thought', done: 'Titled, tagged, and filed for you.' },
  { thing: 'A text from your phone', done: 'WhatsApp or SMS, straight into your stash.' },
];

const Landing = () => {
  const [scrollY, setScrollY] = useState(0);

  useEffect(() => {
    const handleScroll = () => setScrollY(window.scrollY);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  // Lenis smooth scrolling, landing only; skipped for reduced motion
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const lenis = new Lenis({ autoRaf: true, lerp: 0.12 });
    return () => lenis.destroy();
  }, []);

  const gradientOpacity = Math.max(0, 1 - (scrollY / 800));

  return (
    <div className="min-h-screen bg-background font-inter relative overflow-hidden paper-texture">
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

      {/* Main Content */}
      <div className="relative z-[1000]">
        {/* Navigation */}
        <nav className="flex items-center justify-between px-6 py-4 max-w-5xl mx-auto relative z-[1100]">
          <div className="flex items-center">
            <StashWordmark className="h-5 text-[#666666]" />
          </div>

          <div className="flex items-center space-x-3">
            <Link to="/auth">
              <Button variant="ghost" className="text-muted-foreground hover:text-foreground text-sm font-mori">
                Sign In
              </Button>
            </Link>
            <Link to="/pricing">
              <Button className="bg-foreground text-background hover:bg-foreground/90 text-sm px-4 py-2 rounded-full font-mori">
                Get Started
              </Button>
            </Link>
          </div>
        </nav>

        {/* Hero: the product, working. The headline makes the promise and the
            capture box underneath keeps it thirty seconds later. */}
        <section className="px-6 pt-16 pb-24 max-w-4xl mx-auto text-center">
          <div className="fade-in">
            <h1 className="text-5xl md:text-6xl font-tobias font-thin text-foreground mb-5 leading-[1.05] tracking-tight">
              Save anything <span className="font-editorial-italic">easily</span>.<br />
              <span className="text-muted-foreground">Find everything <span className="font-editorial-italic">effortlessly</span>.</span>
            </h1>

            <p className="text-lg font-mori text-muted-foreground max-w-xl mx-auto leading-relaxed">
              Stash reads whatever you toss in and hands it back the moment you ask.
            </p>

            <TryStash />
          </div>
        </section>

        {/* The ledger: input → what the pipeline actually does */}
        <section className="px-6 py-24 max-w-3xl mx-auto">
          <div className="text-center">
            <SectionLabel>Your every thing app</SectionLabel>
            <h2 className="text-3xl md:text-4xl font-tobias tracking-tight leading-[1.15] text-foreground mb-12">
              Toss it in. Stash <span className="font-editorial-italic">does the rest</span>.
            </h2>
          </div>

          <div className="border-t border-black/10">
            {LEDGER.map(row => (
              <div
                key={row.thing}
                className="grid grid-cols-1 gap-1 border-b border-black/10 py-5 sm:grid-cols-[1fr_auto_1.3fr] sm:items-baseline sm:gap-6"
              >
                <span className="font-tobias text-xl text-foreground">{row.thing}</span>
                <span aria-hidden className="hidden font-mori text-violet-600 sm:block">→</span>
                <span className="font-mori text-[15px] leading-relaxed text-muted-foreground">{row.done}</span>
              </div>
            ))}
          </div>
        </section>

        {/* Paste Demo Section */}
        <section className="px-6 py-24 max-w-6xl mx-auto">
          <div className="text-center mb-14">
            <SectionLabel>Watch it work</SectionLabel>
            <h2 className="text-3xl md:text-4xl font-tobias tracking-tight leading-[1.15] text-foreground mb-4 max-w-3xl mx-auto">Just paste the link and Stash does the describing <span className="font-editorial-italic">automagically</span>.</h2>
            <p className="text-lg font-mori text-muted-foreground max-w-2xl mx-auto">
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
            <SectionLabel>Your library</SectionLabel>
            <h2 className="text-3xl md:text-4xl font-tobias tracking-tight leading-[1.15] text-foreground mb-4">Capture everything, search anything</h2>
            <p className="text-lg font-mori text-muted-foreground max-w-2xl mx-auto">
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
            <SectionLabel>Total recall</SectionLabel>
            <h2 className="text-4xl md:text-5xl font-tobias text-foreground mb-5 tracking-tight leading-[1.1]">
              Forget about forgetting
            </h2>
            <p className="text-xl md:text-2xl font-tobias text-muted-foreground mb-5 max-w-2xl mx-auto">
              Chat with your notes, insights, memories, and photos
            </p>
            <p className="text-lg font-mori text-muted-foreground max-w-2xl mx-auto">
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
          <p className="text-xl font-mori text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
            Try it free for two weeks — save a handful of things, then ask for them back. That's the whole pitch.
          </p>
          <Link to="/pricing">
            <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg font-mori">
              Start your free two week trial
              <ArrowRight className="ml-3 h-5 w-5" />
            </Button>
          </Link>
          <p className="text-sm font-mori text-muted-foreground mt-4">
            14 days free, then $4.99/month.
          </p>
        </section>

        {/* Footer */}
        <footer className="px-6 py-16 max-w-4xl mx-auto text-center border-t border-border mt-20 relative z-[1000]">
          <div className="flex items-center justify-center mb-6">
            <StashWordmark className="h-5 text-foreground" />
          </div>
          <p className="text-sm font-mori text-muted-foreground mb-8">
            Forget about forgetting.
          </p>
          <div className="flex justify-center space-x-6 text-sm font-mori text-muted-foreground">
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
