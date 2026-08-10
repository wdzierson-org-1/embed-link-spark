import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { ArrowRight, Brain, MessageSquare, FileText, Calendar, Globe, BookOpen, Mic } from 'lucide-react';

import StashWordmark from '@/components/StashWordmark';
import LandingChatDemo from '@/components/LandingChatDemo';
import jotThoughts from '@/assets/jot-thoughts.jpg';
import healthTracking from '@/assets/health-tracking.jpg';
import creativeProjects from '@/assets/creative-projects.jpg';
import readingNotes from '@/assets/reading-notes.jpg';
import remindersMemoryAids from '@/assets/reminders-memory-aids.jpg';
import demoAddLink from '@/assets/demo_add_link.mp4';

const Landing = () => {
  const [scrollY, setScrollY] = useState(0);

  useEffect(() => {
    const handleScroll = () => setScrollY(window.scrollY);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const gradientOpacity = Math.max(0, 1 - (scrollY / 800));
  const cardsTranslate = Math.min(scrollY * 0.5, 400);

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
      
      {/* Mobile & Tablet Overlay Layer */}
      <div 
        className="fixed inset-0 bg-black/80 pointer-events-none z-[900] lg:hidden transition-opacity duration-500 ease-out"
        style={{ opacity: Math.max(0, 1 - (scrollY * 0.005)) }}
      />
      
      {/* Floating Content Elements - Left Side */}
      <div className="fixed left-0 top-0 w-72 h-screen pointer-events-none z-[800]">
        <div 
          className="absolute top-16 left-2 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${-cardsTranslate}px) rotate(${scrollY * 0.03}deg)` }}
        >
          <div className="bg-card border border-border/20 rounded-lg p-3 shadow-md w-48 rotate-6">
            <img src={jotThoughts} alt="Jot thoughts interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-tobias text-sm mb-1">Jot random thoughts</h4>
            <p className="text-xs text-muted-foreground font-mori">Quick capture moments</p>
          </div>
        </div>
        
        <div 
          className="absolute top-72 left-4 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${-cardsTranslate}px) rotate(${-scrollY * 0.02}deg)` }}
        >
          <div className="bg-card border border-border/20 rounded-lg p-3 shadow-md w-52 -rotate-3">
            <img src={healthTracking} alt="Health tracking interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-tobias text-sm mb-1">Health Tracking</h4>
            <p className="text-xs text-muted-foreground font-mori">Monitor wellness patterns</p>
          </div>
        </div>

        <div 
          className="absolute top-[28rem] left-1 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${-cardsTranslate}px) rotate(${scrollY * 0.025}deg)` }}
        >
          <div className="bg-card border border-border/20 rounded-lg p-3 shadow-md w-44 rotate-12">
            <img src={readingNotes} alt="Reading notes interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-tobias text-sm mb-1">Reading Notes</h4>
            <p className="text-xs text-muted-foreground font-mori">Book insights & quotes</p>
          </div>
        </div>
      </div>

      {/* Floating Content Elements - Right Side */}
      <div className="fixed right-0 top-0 w-72 h-screen pointer-events-none z-[850]">
        <div 
          className="absolute top-24 right-2 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${cardsTranslate}px) rotate(${-scrollY * 0.03}deg)` }}
        >
          <div className="bg-card border border-border/20 rounded-lg p-3 shadow-md w-52 -rotate-6">
            <img src="/lovable-uploads/c567f7f6-ad96-43ff-a02a-57cb70891849.png" alt="Jean-Georges restaurant interior" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-tobias text-sm mb-1">Restaurant Discovery</h4>
            <p className="text-xs text-muted-foreground font-mori">World's best dining spots</p>
          </div>
        </div>

        <div 
          className="absolute top-80 right-4 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${cardsTranslate}px) rotate(${scrollY * 0.02}deg)` }}
        >
          <div className="bg-card border border-border/20 rounded-lg p-3 shadow-md w-48 rotate-3">
            <div className="flex items-center space-x-2 mb-2">
              <Calendar className="h-4 w-4 text-green-500" />
              <span className="text-sm font-mori">Event Planning</span>
            </div>
            <p className="text-xs text-muted-foreground font-mori">Organize life's moments</p>
          </div>
        </div>

        <div 
          className="absolute top-[36.06rem] right-6 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${cardsTranslate}px) rotate(${scrollY * 0.02}deg)` }}
        >
          <div className="bg-card border border-border/20 rounded-lg p-3 shadow-md w-48 -rotate-6">
            <img src={remindersMemoryAids} alt="Reminders and memory aids interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-tobias text-sm mb-1">Reminders & Memory Aids</h4>
            <p className="text-xs text-muted-foreground font-mori">Never forget important moments</p>
          </div>
        </div>

        <div 
          className="absolute top-[26rem] right-1 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${scrollY * 0.15}px) rotate(${-scrollY * 0.015}deg)` }}
        >
          <div className="bg-card border border-border/20 rounded-lg p-3 shadow-md w-50 -rotate-12">
            <img src={creativeProjects} alt="Creative projects interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-tobias text-sm mb-1">Creative Projects</h4>
            <p className="text-xs text-muted-foreground font-mori">Ideas & inspiration</p>
          </div>
        </div>
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

        {/* Hero Section */}
        <section className="px-6 pt-24 pb-32 max-w-4xl mx-auto text-center">
          <div className="fade-in">
            <h1 className="text-5xl md:text-7xl font-tobias font-thin text-white lg:text-foreground mb-8 leading-tight tracking-tight">
              Stash <span className="font-editorial-italic">anything</span> easily.<br />
              <span className="text-white/80 lg:text-muted-foreground">Find anything <span className="font-editorial-italic">effortlessly</span>.</span>
            </h1>

            <p className="text-xl font-mori text-white/90 lg:text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
              Links, PDFs, screenshots, voice notes — toss them into Stash with the thought that made you save them. Stash reads each one, describes it, and hands it back the moment you ask.
            </p>

            <div className="slide-up">
              <Link to="/pricing">
                <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg font-mori">
                  Start stashing — free for 14 days
                </Button>
              </Link>
              <p className="text-sm font-mori text-white/70 lg:text-muted-foreground mt-4">
                Then $4.99/month. No credit card to start.
              </p>
            </div>
          </div>
        </section>

        {/* The Middle Section */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center">
            <h2 className="text-3xl font-tobias text-foreground mb-4">An <span className="font-editorial-italic">everything</span> app.</h2>
            <p className="text-lg font-mori text-muted-foreground max-w-2xl mx-auto">
              Notes, links, files, photos, voice memos — everything you'd normally scatter across five apps, in one place that remembers all of it.
            </p>
          </div>
        </section>

        {/* Capabilities Grid */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-tobias text-foreground max-w-3xl mx-auto">No need to tag, describe, organize, or think. We do it all for you.</h2>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-blue-100 rounded-2xl mb-6 group-hover:bg-blue-200 transition-colors">
                <FileText className="h-8 w-8 text-blue-600" />
              </div>
              <h3 className="text-xl font-tobias text-foreground mb-3">Drop anything in</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Links, PDFs, images, voice notes, video, plain thoughts. One box for all of it — no sorting first.
              </p>
            </div>

            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-green-100 rounded-2xl mb-6 group-hover:bg-green-200 transition-colors">
                <Globe className="h-8 w-8 text-green-600" />
              </div>
              <h3 className="text-xl font-tobias text-foreground mb-3">Links describe themselves</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Paste a URL and Stash fetches the title, preview image, and full page text on its own.
              </p>
            </div>

            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-orange-100 rounded-2xl mb-6 group-hover:bg-orange-200 transition-colors">
                <BookOpen className="h-8 w-8 text-orange-600" />
              </div>
              <h3 className="text-xl font-tobias text-foreground mb-3">Documents read themselves</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                PDFs are read, summarized, and made searchable the moment they land in your stash.
              </p>
            </div>

            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-red-100 rounded-2xl mb-6 group-hover:bg-red-200 transition-colors">
                <Mic className="h-8 w-8 text-red-600" />
              </div>
              <h3 className="text-xl font-tobias text-foreground mb-3">Voice becomes text</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Voice notes are transcribed and summarized automatically, so spoken thoughts are findable too.
              </p>
            </div>

            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-teal-100 rounded-2xl mb-6 group-hover:bg-teal-200 transition-colors">
                <MessageSquare className="h-8 w-8 text-teal-600" />
              </div>
              <h3 className="text-xl font-tobias text-foreground mb-3">Text it by WhatsApp or SMS</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Text a link, photo, or voice note to your Stash number without opening the app at all.
              </p>
            </div>

            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-purple-100 rounded-2xl mb-6 group-hover:bg-purple-200 transition-colors">
                <Brain className="h-8 w-8 text-purple-600" />
              </div>
              <h3 className="text-xl font-tobias text-foreground mb-3">Ask instead of dig</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Chat with everything you've saved and get answers back with the sources they came from.
              </p>
            </div>
          </div>
        </section>

        {/* Paste Demo Section */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-tobias text-foreground mb-4">Just paste the link and watch Stash fill in the rest.</h2>
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
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-tobias text-foreground mb-4">Capture everything, search anything</h2>
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
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-6xl font-tobias text-foreground mb-5 tracking-tight">
              Forget about forgetting
            </h2>
            <p className="text-xl md:text-2xl font-tobias text-muted-foreground mb-5">
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
          <h2 className="text-4xl font-tobias text-foreground mb-6">
            Your future self will ask.<br />
            <span className="text-muted-foreground">Stash will have the <span className="font-editorial-italic">answer</span>.</span>
          </h2>
          <p className="text-xl font-mori text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
            Try it free for a week — save a handful of things, then ask for them back. That's the whole pitch.
          </p>
          <Link to="/pricing">
            <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg font-mori">
              Start your free trial
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