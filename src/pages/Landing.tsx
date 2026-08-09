import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { ArrowRight, Brain, MessageSquare, FileText, Calendar, Globe, BookOpen, Mic } from 'lucide-react';

import jotThoughts from '@/assets/jot-thoughts.jpg';
import healthTracking from '@/assets/health-tracking.jpg';
import creativeProjects from '@/assets/creative-projects.jpg';
import readingNotes from '@/assets/reading-notes.jpg';
import remindersMemoryAids from '@/assets/reminders-memory-aids.jpg';
import demoAddLink from '@/assets/demo_add_link.mp4';
import chatDemo from '@/assets/chat-demo.mp4';

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
          <div className="flex items-center space-x-2">
            <img 
              src="/lovable-uploads/b93db9a2-7dba-4a6c-b36a-a9f982356ff6.png" 
              alt="Stash"
              className="w-8 h-8"
              style={{ filter: 'brightness(0) saturate(100%) invert(40%) sepia(0%) saturate(0%) hue-rotate(0deg) brightness(98%) contrast(86%)' }}
            />
            <span className="text-lg font-tobias" style={{ color: '#666' }}>Stash</span>
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
              Save anything.<br />
              <span className="text-white/80 lg:text-muted-foreground">Keep the <span className="font-editorial-italic">context</span>.</span>
            </h1>

            <p className="text-xl font-mori text-white/90 lg:text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
              Links, PDFs, screenshots, voice notes — toss them into Stash with the thought that made you save them. Stash reads each one, describes it, and hands it back the moment you ask.
            </p>

            <div className="slide-up">
              <Link to="/pricing">
                <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg font-mori">
                  Start stashing — free for 7 days
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
          <div className="text-center mb-16">
            <h2 className="text-3xl font-tobias text-foreground mb-4">More than a notes app. Less than a second job.</h2>
            <p className="text-lg font-mori text-muted-foreground max-w-2xl mx-auto">
              Basic notes apps swallow what you save. Serious knowledge systems make you the librarian. Stash sits in the middle — on purpose.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 max-w-5xl mx-auto items-stretch">
            <div className="rounded-2xl border border-border bg-card/60 p-8 text-left">
              <p className="text-xs font-mori uppercase tracking-widest text-muted-foreground mb-3">Notes apps</p>
              <h3 className="text-xl font-mori text-foreground mb-3">Easy in, impossible out</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Everything piles into one long scroll. Six months later, that link you saved might as well be gone.
              </p>
            </div>

            <div className="rounded-2xl border-2 border-foreground bg-card p-8 text-left shadow-xl md:-my-3">
              <p className="text-xs font-mori uppercase tracking-widest text-foreground mb-3">Stash</p>
              <h3 className="text-2xl font-tobias text-foreground mb-3">Capture in seconds, <span className="font-editorial-italic">find it forever</span></h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Drop it in, add a thought if you want, done. Stash titles it, describes it, and finds it when you ask — no filing, ever.
              </p>
            </div>

            <div className="rounded-2xl border border-border bg-card/60 p-8 text-left">
              <p className="text-xs font-mori uppercase tracking-widest text-muted-foreground mb-3">Knowledge systems</p>
              <h3 className="text-xl font-mori text-foreground mb-3">Powerful, if you keep up</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Folders, tags, backlinks, weekly reviews. Most people stop maintaining the system by week two.
              </p>
            </div>
          </div>
        </section>

        {/* Capabilities Grid */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-tobias text-foreground mb-4">Capture with zero filing</h2>
            <p className="text-lg font-mori text-muted-foreground max-w-2xl mx-auto">
              No folders to design, no tags to invent. Add a thought if you want — Stash handles the rest.
            </p>
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
              <h3 className="text-xl font-tobias text-foreground mb-3">Save by WhatsApp</h3>
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
            <h2 className="text-3xl font-tobias text-foreground mb-4">Paste a link, get the whole page</h2>
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

          <div className="relative h-80 max-w-4xl mx-auto">
            {/* Input panel image at the top */}
            <div 
              className="absolute top-2 left-1/2 transform -translate-x-1/2 z-30 rotate-1"
              style={{ transform: `translateX(calc(-50% + ${scrollY * 0.02}px)) translateY(${10 - scrollY * 0.01}px) rotate(${1 + scrollY * 0.005}deg)` }}
            >
              <img 
                src="/lovable-uploads/6913186c-7298-435f-8962-6d5a231a5a0f.png" 
                alt="Input panel interface"
                className="w-80 rounded-xl shadow-xl border border-border hover:rotate-0 hover:z-40 transition-all duration-300"
              />
            </div>

            {/* Left overlapping image */}
            <div 
              className="absolute top-16 left-28 z-20 -rotate-6"
              style={{ transform: `translateX(${-scrollY * 0.02}px) translateY(${scrollY * 0.01}px) rotate(-6deg)` }}
            >
              <img 
                src="/lovable-uploads/4171b995-b0c1-447a-90fe-f204f543463b.png" 
                alt="Public feed example"
                className="w-72 rounded-xl shadow-xl border border-border hover:rotate-0 hover:z-40 transition-all duration-300"
              />
            </div>
            
            {/* Right overlapping image */}
            <div 
              className="absolute top-20 right-16 z-20 rotate-12"
              style={{ transform: `translateX(${scrollY * 0.02}px) translateY(${scrollY * 0.01}px) rotate(12deg)` }}
            >
              <img 
                src="/lovable-uploads/0515aeee-180b-4aa5-bfa0-b96ae2b400c5.png" 
                alt="Content management interface"
                className="w-72 rounded-xl shadow-xl border border-border hover:rotate-0 hover:z-40 transition-all duration-300"
              />
            </div>

            {/* Content organization example moved to bottom */}
            <div 
              className="absolute bottom-8 right-1/4 z-10 -rotate-3"
              style={{ transform: `translateX(${scrollY * 0.01}px) translateY(${scrollY * 0.005}px) rotate(-3deg)` }}
            >
              <img 
                src="/lovable-uploads/157b2b06-2c4f-4e1c-aea1-e690e426776b.png" 
                alt="Content organization example"
                className="w-64 rounded-xl shadow-lg border border-border hover:rotate-0 hover:z-40 transition-all duration-300"
              />
            </div>
          </div>
        </section>

        {/* AI Chat Section */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-tobias text-foreground mb-4">
              Forget about forgetting<br />
              <span className="text-muted-foreground">Chat with your notes, insights, memories, and photos</span>
            </h2>
            <p className="text-lg font-mori text-muted-foreground max-w-2xl mx-auto">
              Ask questions about anything you've saved. Our AI understands the context and connections across all your content.
            </p>
          </div>

          <div className="max-w-2xl mx-auto rounded-2xl overflow-hidden shadow-2xl border border-border">
            <video 
              src={chatDemo}
              autoPlay
              loop
              muted
              playsInline
              className="w-full scale-[1.02]"
            >
              Your browser does not support the video tag.
            </video>
          </div>
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
            7 days free, then $4.99/month.
          </p>
        </section>

        {/* Footer */}
        <footer className="px-6 py-16 max-w-4xl mx-auto text-center border-t border-border mt-20 relative z-[1000]">
          <div className="flex items-center justify-center space-x-2 mb-6">
            <img 
              src="/lovable-uploads/2b719fd5-c695-425b-9c8e-71fc6a7f4959.png" 
              alt="Stash"
              className="w-8 h-8"
            />
            <span className="text-lg font-tobias text-foreground">Stash</span>
          </div>
          <p className="text-sm font-mori text-muted-foreground mb-8">
            Save anything. Keep the context.
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