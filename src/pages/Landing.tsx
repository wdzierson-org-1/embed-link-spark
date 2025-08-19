import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { ArrowRight, Smartphone, Brain, MessageSquare, FileText, Calendar, Image, Heart, Globe, BookOpen, Music, MapPin } from 'lucide-react';

const Landing = () => {
  const [scrollY, setScrollY] = useState(0);

  useEffect(() => {
    const handleScroll = () => setScrollY(window.scrollY);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <div className="min-h-screen bg-background font-inter relative overflow-hidden">
      {/* Floating Content Elements - Left Side */}
      <div className="fixed left-0 top-0 w-80 h-screen pointer-events-none z-0">
        <div 
          className="absolute top-20 left-4 transform-gpu transition-transform duration-1000 ease-out"
          style={{ transform: `translateX(${-scrollY * 0.1}px) rotate(${scrollY * 0.02}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-4 shadow-sm w-64">
            <div className="w-full h-32 bg-gradient-to-br from-purple-400 to-pink-400 rounded-md mb-3"></div>
            <h4 className="font-medium text-sm mb-1">Liquid AI Models</h4>
            <p className="text-xs text-muted-foreground">Faster, smarter AI architecture</p>
          </div>
        </div>
        
        <div 
          className="absolute top-80 left-8 transform-gpu transition-transform duration-1000 ease-out"
          style={{ transform: `translateX(${-scrollY * 0.15}px) rotate(${-scrollY * 0.01}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-56">
            <div className="flex items-center space-x-2 mb-2">
              <Heart className="h-4 w-4 text-red-500" />
              <span className="text-sm font-medium">Health Tracking</span>
            </div>
            <p className="text-xs text-muted-foreground">Monitor wellness patterns</p>
          </div>
        </div>

        <div 
          className="absolute top-[32rem] left-2 transform-gpu transition-transform duration-1000 ease-out"
          style={{ transform: `translateX(${-scrollY * 0.08}px) rotate(${scrollY * 0.015}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-48">
            <div className="flex items-center space-x-2 mb-2">
              <BookOpen className="h-4 w-4 text-blue-500" />
              <span className="text-sm font-medium">Reading Notes</span>
            </div>
            <p className="text-xs text-muted-foreground">Book insights & quotes</p>
          </div>
        </div>
      </div>

      {/* Floating Content Elements - Right Side */}
      <div className="fixed right-0 top-0 w-80 h-screen pointer-events-none z-0">
        <div 
          className="absolute top-32 right-4 transform-gpu transition-transform duration-1000 ease-out"
          style={{ transform: `translateX(${scrollY * 0.12}px) rotate(${-scrollY * 0.02}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-4 shadow-sm w-60">
            <div className="w-full h-24 bg-gradient-to-br from-emerald-400 to-blue-400 rounded-md mb-3"></div>
            <h4 className="font-medium text-sm mb-1">Restaurant Discovery</h4>
            <p className="text-xs text-muted-foreground">World's best dining spots</p>
          </div>
        </div>

        <div 
          className="absolute top-96 right-8 transform-gpu transition-transform duration-1000 ease-out"
          style={{ transform: `translateX(${scrollY * 0.1}px) rotate(${scrollY * 0.01}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-52">
            <div className="flex items-center space-x-2 mb-2">
              <Calendar className="h-4 w-4 text-green-500" />
              <span className="text-sm font-medium">Event Planning</span>
            </div>
            <p className="text-xs text-muted-foreground">Organize life's moments</p>
          </div>
        </div>

        <div 
          className="absolute top-[36rem] right-2 transform-gpu transition-transform duration-1000 ease-out"
          style={{ transform: `translateX(${scrollY * 0.14}px) rotate(${-scrollY * 0.015}deg)` }}
        >
          <div className="bg-card border border-border rounded-lg p-3 shadow-sm w-56">
            <div className="flex items-center space-x-2 mb-2">
              <Music className="h-4 w-4 text-purple-500" />
              <span className="text-sm font-medium">Creative Projects</span>
            </div>
            <p className="text-xs text-muted-foreground">Ideas & inspiration</p>
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
            <span className="text-lg font-medium text-foreground">notes2me</span>
          </div>
          
          <div className="flex items-center space-x-3">
            <Link to="/auth">
              <Button variant="ghost" className="text-muted-foreground hover:text-foreground text-sm">
                Sign In
              </Button>
            </Link>
            <Link to="/auth">
              <Button className="bg-foreground text-background hover:bg-foreground/90 text-sm px-4 py-2 rounded-full">
                Get Started
              </Button>
            </Link>
          </div>
        </nav>

        {/* Hero Section */}
        <section className="px-6 pt-24 pb-32 max-w-3xl mx-auto text-center">
          <div className="fade-in">
            <h1 className="text-5xl md:text-6xl font-bold text-foreground mb-8 leading-tight tracking-tight">
              Capture everything<br />
              <span className="text-muted-foreground">around you</span>
            </h1>
            
            <p className="text-xl text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
              Your universal inbox for thoughts, photos, voice memos, and documents.<br />
              Chat with your data to discover patterns and insights.
            </p>
            
            <div className="slide-up">
              <Link to="/auth">
                <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg">
                  Start organizing in seconds
                </Button>
              </Link>
            </div>
          </div>
        </section>

        {/* Use Cases Grid */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-bold text-foreground mb-4">Everything you need to organize your life</h2>
            <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
              Powerful features that adapt to how you think, helping you organize everything effortlessly.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {/* Universal Capture */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-blue-100 rounded-2xl mb-6 group-hover:bg-blue-200 transition-colors">
                <Brain className="h-8 w-8 text-blue-600" />
              </div>
              <h3 className="text-xl font-semibold text-foreground mb-3">Universal Capture</h3>
              <p className="text-muted-foreground leading-relaxed">
                Text, photos, voice memos, PDFs, and links. Everything you need to capture life's moments in one place.
              </p>
            </div>

            {/* AI Insights */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-purple-100 rounded-2xl mb-6 group-hover:bg-purple-200 transition-colors">
                <MessageSquare className="h-8 w-8 text-purple-600" />
              </div>
              <h3 className="text-xl font-semibold text-foreground mb-3">AI Insights</h3>
              <p className="text-muted-foreground leading-relaxed">
                Chat with your data to discover patterns, generate summaries, and unlock insights about your life.
              </p>
            </div>

            {/* Smart Organization */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-green-100 rounded-2xl mb-6 group-hover:bg-green-200 transition-colors">
                <Smartphone className="h-8 w-8 text-green-600" />
              </div>
              <h3 className="text-xl font-semibold text-foreground mb-3">Access Everywhere</h3>
              <p className="text-muted-foreground leading-relaxed">
                Web, mobile, SMS, and WhatsApp. Capture thoughts wherever you are, whenever inspiration strikes.
              </p>
            </div>

            {/* Health & Wellness */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-red-100 rounded-2xl mb-6 group-hover:bg-red-200 transition-colors">
                <Heart className="h-8 w-8 text-red-600" />
              </div>
              <h3 className="text-xl font-semibold text-foreground mb-3">Health Tracking</h3>
              <p className="text-muted-foreground leading-relaxed">
                Log workouts, meals, and wellness notes. Track patterns to optimize your health journey.
              </p>
            </div>

            {/* Creative Projects */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-orange-100 rounded-2xl mb-6 group-hover:bg-orange-200 transition-colors">
                <Image className="h-8 w-8 text-orange-600" />
              </div>
              <h3 className="text-xl font-semibold text-foreground mb-3">Creative Projects</h3>
              <p className="text-muted-foreground leading-relaxed">
                Collect inspiration, mood boards, and project ideas. Turn scattered thoughts into organized creativity.
              </p>
            </div>

            {/* Travel & Places */}
            <div className="text-center group hover:transform hover:scale-105 transition-all duration-300">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-teal-100 rounded-2xl mb-6 group-hover:bg-teal-200 transition-colors">
                <MapPin className="h-8 w-8 text-teal-600" />
              </div>
              <h3 className="text-xl font-semibold text-foreground mb-3">Travel & Places</h3>
              <p className="text-muted-foreground leading-relaxed">
                Save restaurant recommendations, travel plans, and location memories. Never forget a great discovery.
              </p>
            </div>
          </div>
        </section>

        {/* Product Screenshots */}
        <section className="px-6 py-20 max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-bold text-foreground mb-4">See it in action</h2>
            <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
              Real examples of how notes2me organizes the chaos of daily life into meaningful insights.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <div className="group">
              <img 
                src="/lovable-uploads/157b2b06-2c4f-4e1c-aea1-e690e426776b.png" 
                alt="Content organization example"
                className="w-full rounded-xl shadow-lg group-hover:shadow-2xl transition-shadow duration-300 border border-border"
              />
            </div>
            <div className="group">
              <img 
                src="/lovable-uploads/4171b995-b0c1-447a-90fe-f204f543463b.png" 
                alt="Public feed example"
                className="w-full rounded-xl shadow-lg group-hover:shadow-2xl transition-shadow duration-300 border border-border"
              />
            </div>
            <div className="group">
              <img 
                src="/lovable-uploads/0515aeee-180b-4aa5-bfa0-b96ae2b400c5.png" 
                alt="Content management interface"
                className="w-full rounded-xl shadow-lg group-hover:shadow-2xl transition-shadow duration-300 border border-border"
              />
            </div>
          </div>
        </section>

        {/* Call to Action */}
        <section className="px-6 py-32 max-w-4xl mx-auto text-center">
          <h2 className="text-4xl font-bold text-foreground mb-6">Ready to organize your life?</h2>
          <p className="text-xl text-muted-foreground mb-12 max-w-2xl mx-auto leading-relaxed">
            Join thousands who've transformed chaos into clarity. Start capturing everything that matters.
          </p>
          <Link to="/auth">
            <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-4 rounded-full shadow-lg">
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
            <span className="text-lg font-medium text-foreground">notes2me</span>
          </div>
          <p className="text-sm text-muted-foreground mb-8">
            Your personal life organizer.
          </p>
          <div className="flex justify-center space-x-6 text-sm text-muted-foreground">
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