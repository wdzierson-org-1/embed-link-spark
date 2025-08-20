import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { ArrowRight, Smartphone, Brain, MessageSquare, FileText, Calendar, Image, Heart, Globe, BookOpen, Music, MapPin } from 'lucide-react';

import jotThoughts from '@/assets/jot-thoughts.jpg';
import healthTracking from '@/assets/health-tracking.jpg';
import creativeProjects from '@/assets/creative-projects.jpg';
import readingNotes from '@/assets/reading-notes.jpg';
import remindersMemoryAids from '@/assets/reminders-memory-aids.jpg';

const Landing = () => {
  const [scrollY, setScrollY] = useState(0);

  useEffect(() => {
    const handleScroll = () => setScrollY(window.scrollY);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <div className="min-h-screen bg-background font-inter relative overflow-hidden">
      {/* Mobile Overlay Layer */}
      <div 
        className="fixed inset-0 bg-black/80 pointer-events-none z-5 md:hidden transition-opacity duration-500 ease-out"
        style={{ opacity: Math.max(0, 1 - (scrollY * 0.005)) }}
      />
      
      {/* Floating Content Elements - Left Side */}
      <div className="fixed left-0 top-0 w-72 h-screen pointer-events-none z-0">
        <div 
          className="absolute top-16 left-2 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${-scrollY * 0.25}px) rotate(${scrollY * 0.03}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-48 rotate-6">
            <img src={jotThoughts} alt="Jot thoughts interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-mori text-sm mb-1">Jot random thoughts</h4>
            <p className="text-xs text-muted-foreground font-mori">Quick capture moments</p>
          </div>
        </div>
        
        <div 
          className="absolute top-72 left-4 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${-scrollY * 0.3}px) rotate(${-scrollY * 0.02}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-52 -rotate-3">
            <img src={healthTracking} alt="Health tracking interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-mori text-sm mb-1">Health Tracking</h4>
            <p className="text-xs text-muted-foreground font-mori">Monitor wellness patterns</p>
          </div>
        </div>

        <div 
          className="absolute top-[28rem] left-1 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${-scrollY * 0.2}px) rotate(${scrollY * 0.025}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-44 rotate-12">
            <img src={readingNotes} alt="Reading notes interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-mori text-sm mb-1">Reading Notes</h4>
            <p className="text-xs text-muted-foreground font-mori">Book insights & quotes</p>
          </div>
        </div>
      </div>

      {/* Floating Content Elements - Right Side */}
      <div className="fixed right-0 top-0 w-72 h-screen pointer-events-none z-0">
        <div 
          className="absolute top-24 right-2 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${scrollY * 0.28}px) rotate(${-scrollY * 0.03}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-52 -rotate-6">
            <img src="/lovable-uploads/c567f7f6-ad96-43ff-a02a-57cb70891849.png" alt="Jean-Georges restaurant interior" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-mori text-sm mb-1">Restaurant Discovery</h4>
            <p className="text-xs text-muted-foreground font-mori">World's best dining spots</p>
          </div>
        </div>

        <div 
          className="absolute top-80 right-4 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${scrollY * 0.22}px) rotate(${scrollY * 0.02}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-48 rotate-3">
            <div className="flex items-center space-x-2 mb-2">
              <Calendar className="h-4 w-4 text-green-500" />
              <span className="text-sm font-mori">Event Planning</span>
            </div>
            <p className="text-xs text-muted-foreground font-mori">Organize life's moments</p>
          </div>
        </div>

        <div 
          className="absolute top-[36.06rem] right-6 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${scrollY * 0.25}px) rotate(${scrollY * 0.02}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-48 -rotate-6">
            <img src={remindersMemoryAids} alt="Reminders and memory aids interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-mori text-sm mb-1">Reminders & Memory Aids</h4>
            <p className="text-xs text-muted-foreground font-mori">Never forget important moments</p>
          </div>
        </div>

        <div 
          className="absolute top-[26rem] right-1 transform-gpu transition-transform duration-500 ease-out"
          style={{ transform: `translateX(${scrollY * 0.15}px) rotate(${-scrollY * 0.015}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-50 -rotate-12">
            <img src={creativeProjects} alt="Creative projects interface" className="w-full h-24 object-cover rounded-md mb-2" />
            <h4 className="font-mori text-sm mb-1">Creative Projects</h4>
            <p className="text-xs text-muted-foreground font-mori">Ideas & inspiration</p>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="relative z-10">
        {/* Navigation */}
        <nav className="flex items-center justify-between px-6 py-4 max-w-5xl mx-auto">
          <div className="flex items-center space-x-2">
            <div className="w-6 h-6 bg-foreground rounded flex items-center justify-center">
              <span className="text-background font-medium text-xs">N</span>
            </div>
            <span className="text-lg font-editorial text-white md:text-foreground">notes2me</span>
          </div>
          
          <div className="flex items-center space-x-3">
            <Link to="/auth">
              <Button variant="ghost" className="text-muted-foreground hover:text-foreground text-sm font-mori">
                Sign In
              </Button>
            </Link>
            <Link to="/auth">
              <Button className="bg-foreground text-background hover:bg-foreground/90 text-sm px-4 py-2 rounded-full font-mori">
                Get Started
              </Button>
            </Link>
          </div>
        </nav>

        {/* Hero Section */}
        <section className="px-6 pt-24 pb-32 max-w-4xl mx-auto text-center">
          <div className="fade-in">
            <h1 className="text-5xl md:text-7xl font-editorial text-white md:text-foreground mb-8 leading-tight tracking-tight">
              Capture everything.<br />
              <span className="text-white/80 md:text-muted-foreground">Organize nothing.</span>
            </h1>
            
            <p className="text-xl font-mori text-white/90 md:text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
              Your universal inbox for thoughts, photos, voice memos, and documents.<br />
              Chat with your data to discover patterns and insights.
            </p>
            
            <div className="slide-up">
              <Link to="/auth">
                <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg font-mori">
                  Start organizing in seconds
                </Button>
              </Link>
            </div>
          </div>
        </section>

        {/* Use Cases Grid */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-editorial text-foreground mb-4">Everything you need to organize your life</h2>
            <p className="text-lg font-mori text-muted-foreground max-w-2xl mx-auto">
              Powerful features that adapt to how you think, helping you organize everything effortlessly.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {/* Universal Capture */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-blue-100 rounded-2xl mb-6 group-hover:bg-blue-200 transition-colors">
                <Brain className="h-8 w-8 text-blue-600" />
              </div>
              <h3 className="text-xl font-editorial text-foreground mb-3">Universal Capture</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Text, photos, voice memos, PDFs, and links. Everything you need to capture life's moments in one place.
              </p>
            </div>

            {/* AI Insights */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-purple-100 rounded-2xl mb-6 group-hover:bg-purple-200 transition-colors">
                <MessageSquare className="h-8 w-8 text-purple-600" />
              </div>
              <h3 className="text-xl font-editorial text-foreground mb-3">AI Insights</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Chat with your data to discover patterns, generate summaries, and unlock insights about your life.
              </p>
            </div>

            {/* Smart Organization */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-green-100 rounded-2xl mb-6 group-hover:bg-green-200 transition-colors">
                <Smartphone className="h-8 w-8 text-green-600" />
              </div>
              <h3 className="text-xl font-editorial text-foreground mb-3">Access Everywhere</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Web, mobile, SMS, and WhatsApp. Capture thoughts wherever you are, whenever inspiration strikes.
              </p>
            </div>

            {/* Health & Wellness */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-red-100 rounded-2xl mb-6 group-hover:bg-red-200 transition-colors">
                <Heart className="h-8 w-8 text-red-600" />
              </div>
              <h3 className="text-xl font-editorial text-foreground mb-3">Health Tracking</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Log workouts, meals, and wellness notes. Track patterns to optimize your health journey.
              </p>
            </div>

            {/* Creative Projects */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-orange-100 rounded-2xl mb-6 group-hover:bg-orange-200 transition-colors">
                <Image className="h-8 w-8 text-orange-600" />
              </div>
              <h3 className="text-xl font-editorial text-foreground mb-3">Creative Projects</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Collect inspiration, mood boards, and project ideas. Turn scattered thoughts into organized creativity.
              </p>
            </div>

            {/* Travel & Places */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-teal-100 rounded-2xl mb-6 group-hover:bg-teal-200 transition-colors">
                <MapPin className="h-8 w-8 text-teal-600" />
              </div>
              <h3 className="text-xl font-editorial text-foreground mb-3">Travel & Places</h3>
              <p className="text-muted-foreground font-mori leading-relaxed">
                Save restaurant recommendations, travel plans, and location memories. Never forget a great discovery.
              </p>
            </div>
          </div>
        </section>

        {/* Product Screenshots - Overlapping Cards Style */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-editorial text-foreground mb-4">Capture everything, search anything</h2>
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
            <h2 className="text-3xl font-editorial text-foreground mb-4">
              Forget about forgetting<br />
              <span className="text-muted-foreground">Chat with your notes, insights, memories, and photos</span>
            </h2>
            <p className="text-lg font-mori text-muted-foreground max-w-2xl mx-auto">
              Ask questions about anything you've saved. Our AI understands the context and connections across all your content.
            </p>
          </div>

          <div className="max-w-2xl mx-auto">
            <img 
              src="/lovable-uploads/3104c97b-bf39-4633-b73a-c705a2d42a5f.png" 
              alt="Chat with AI about your content"
              className="w-full rounded-2xl shadow-2xl border border-border"
            />
          </div>
        </section>

        {/* Call to Action */}
        <section className="px-6 py-32 max-w-4xl mx-auto text-center">
          <h2 className="text-4xl font-editorial text-foreground mb-6">Ready to organize your life?</h2>
          <p className="text-xl font-mori text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
            Join thousands who've transformed chaos into clarity. Start capturing everything that matters.
          </p>
          <Link to="/auth">
            <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg font-mori">
              Get Started for Free
              <ArrowRight className="ml-3 h-5 w-5" />
            </Button>
          </Link>
        </section>

        {/* Footer */}
        <footer className="px-6 py-16 max-w-4xl mx-auto text-center border-t border-border mt-20">
          <div className="flex items-center justify-center space-x-2 mb-6">
            <div className="w-6 h-6 bg-foreground rounded flex items-center justify-center">
              <span className="text-background font-medium text-xs">N</span>
            </div>
            <span className="text-lg font-editorial text-foreground">notes2me</span>
          </div>
          <p className="text-sm font-mori text-muted-foreground mb-8">
            Your personal life organizer.
          </p>
          <div className="flex justify-center space-x-6 text-sm font-mori text-muted-foreground">
            <a href="#" className="hover:text-foreground transition-colors">Privacy</a>
            <a href="#" className="hover:text-foreground transition-colors">Terms</a>
            <a href="#" className="hover:text-foreground transition-colors">Contact</a>
          </div>
        </footer>
      </div>
    </div>
  );
};

export default Landing;