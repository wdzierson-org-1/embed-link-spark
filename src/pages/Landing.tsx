import React from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Star, FileText, Image, MessageSquare, Brain, Search, Smartphone, Globe, Shield } from 'lucide-react';

const Landing = () => {
  return (
    <div className="min-h-screen bg-background">
      {/* Navigation */}
      <nav className="relative z-10 flex items-center justify-between px-6 py-6 max-w-6xl mx-auto">
        <div className="flex items-center space-x-2">
          <div className="w-8 h-8 bg-primary rounded-lg flex items-center justify-center">
            <span className="text-primary-foreground font-bold text-sm">N</span>
          </div>
          <span className="text-xl font-semibold text-foreground">notes2me</span>
        </div>
        
        <div className="flex items-center space-x-4">
          <Link to="/auth">
            <Button variant="ghost" className="text-muted-foreground hover:text-foreground">
              Sign In
            </Button>
          </Link>
          <Link to="/auth">
            <Button className="bg-foreground text-background hover:bg-foreground/90">
              Get Started - it's FREE
            </Button>
          </Link>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="relative px-6 py-32 max-w-4xl mx-auto text-center">
        <h1 className="text-5xl md:text-6xl lg:text-7xl font-bold text-foreground mb-8 leading-tight tracking-tight">
          Get Organized.
        </h1>
        
        <div className="text-lg md:text-xl text-muted-foreground mb-12 space-y-2 leading-relaxed">
          <p>All your thoughts, organized with ease.</p>
          <p>Switch by context when you please.</p>
          <p>No more juggling notes all day.</p>
          <p>Make your moves without delay,</p>
          <p>No dropped ideas along the way.</p>
          <p className="text-foreground font-medium">Start Organizing Today! ✨</p>
        </div>
        
        <div className="mb-20">
          <Link to="/auth">
            <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-8 py-4">
              Get Started - it's FREE
            </Button>
          </Link>
        </div>

        {/* Hero Visual */}
        <div className="relative">
          <div className="bg-card rounded-xl shadow-2xl border border-border overflow-hidden max-w-5xl mx-auto">
            <div className="bg-muted/30 p-4 border-b border-border">
              <div className="flex items-center space-x-2">
                <div className="w-3 h-3 bg-red-500 rounded-full"></div>
                <div className="w-3 h-3 bg-yellow-500 rounded-full"></div>
                <div className="w-3 h-3 bg-green-500 rounded-full"></div>
                <div className="flex-1 text-center">
                  <span className="text-xs text-muted-foreground">notes2me - Your Life, Organized</span>
                </div>
              </div>
            </div>
            <div className="p-8 bg-gradient-to-br from-background to-muted/20">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="bg-card rounded-lg p-4 border border-border">
                  <div className="flex items-center space-x-2 mb-3">
                    <FileText className="h-4 w-4 text-primary" />
                    <span className="text-sm text-muted-foreground">Journal Entry</span>
                  </div>
                  <h4 className="font-medium mb-2">Morning Reflections</h4>
                  <p className="text-sm text-muted-foreground">Felt really energized today after...</p>
                </div>
                <div className="bg-card rounded-lg p-4 border border-border">
                  <div className="flex items-center space-x-2 mb-3">
                    <Image className="h-4 w-4 text-primary" />
                    <span className="text-sm text-muted-foreground">Photo</span>
                  </div>
                  <h4 className="font-medium mb-2">Workout Progress</h4>
                  <div className="bg-muted/50 rounded h-16 flex items-center justify-center">
                    <Image className="h-6 w-6 text-muted-foreground" />
                  </div>
                </div>
                <div className="bg-card rounded-lg p-4 border border-border">
                  <div className="flex items-center space-x-2 mb-3">
                    <MessageSquare className="h-4 w-4 text-primary" />
                    <span className="text-sm text-muted-foreground">AI Insight</span>
                  </div>
                  <h4 className="font-medium mb-2">Health Pattern</h4>
                  <p className="text-sm text-muted-foreground">You exercise most on Mondays...</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="px-6 py-16 max-w-4xl mx-auto text-center">
        <p className="text-muted-foreground mb-8">Used by productive folks from</p>
        <div className="flex justify-center items-center space-x-8 opacity-60">
          <div className="text-2xl font-bold text-muted-foreground">Apple</div>
          <div className="text-2xl font-bold text-muted-foreground">Google</div>
          <div className="text-2xl font-bold text-muted-foreground">Meta</div>
          <div className="text-2xl font-bold text-muted-foreground">Stripe</div>
        </div>
      </section>

      {/* Features Section */}
      <section className="px-6 py-20 max-w-4xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-6">Features</h2>
          <h3 className="text-2xl md:text-3xl font-semibold text-foreground mb-8">Your workspace that works</h3>
        </div>

        <div className="space-y-16">
          {/* Universal Capture */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
            <div>
              <h3 className="text-2xl font-bold text-foreground mb-4">Universal Capture</h3>
              <p className="text-lg text-muted-foreground mb-6 leading-relaxed">
                Text, photos, voice memos, videos, and documents. Everything you need to capture life's moments.
              </p>
            </div>
            <div className="bg-muted/30 rounded-xl p-8 flex items-center justify-center min-h-64">
              <Brain className="h-16 w-16 text-muted-foreground" />
            </div>
          </div>

          {/* AI Insights */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
            <div className="order-2 lg:order-1 bg-muted/30 rounded-xl p-8 flex items-center justify-center min-h-64">
              <MessageSquare className="h-16 w-16 text-muted-foreground" />
            </div>
            <div className="order-1 lg:order-2">
              <h3 className="text-2xl font-bold text-foreground mb-4">AI Life Insights</h3>
              <p className="text-lg text-muted-foreground mb-6 leading-relaxed">
                Chat with your life data. Ask about patterns and get insights about your habits.
              </p>
            </div>
          </div>

          {/* Access Everywhere */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
            <div>
              <h3 className="text-2xl font-bold text-foreground mb-4">Access Everywhere</h3>
              <p className="text-lg text-muted-foreground mb-6 leading-relaxed">
                Web app, mobile, SMS, WhatsApp. Capture thoughts wherever you are.
              </p>
            </div>
            <div className="bg-muted/30 rounded-xl p-8 flex items-center justify-center min-h-64">
              <Smartphone className="h-16 w-16 text-muted-foreground" />
            </div>
          </div>
        </div>
      </section>

      {/* Call to Action */}
      <section className="px-6 py-20 max-w-4xl mx-auto text-center">
        <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-6">Ready to get organized?</h2>
        <p className="text-lg text-muted-foreground mb-8 max-w-2xl mx-auto">
          Start capturing your life's moments and discover patterns you never knew existed.
        </p>
        <div className="flex flex-col sm:flex-row gap-4 justify-center items-center mb-8">
          <Link to="/auth">
            <Button size="lg" className="bg-foreground text-background hover:bg-foreground/90 text-lg px-8 py-4">
              Start Free
            </Button>
          </Link>
          <Button variant="outline" size="lg" className="text-lg px-8 py-4">
            See How It Works
          </Button>
        </div>
        
        <div className="flex items-center justify-center space-x-2 text-sm text-muted-foreground">
          <div className="flex space-x-1">
            {[1, 2, 3, 4, 5].map((star) => (
              <Star key={star} className="h-4 w-4 fill-current text-yellow-400" />
            ))}
          </div>
          <span>4.9/5 from 2,847 users</span>
        </div>
      </section>

      {/* Footer */}
      <footer className="px-6 py-12 max-w-4xl mx-auto text-center border-t border-border">
        <div className="flex items-center justify-center space-x-2 mb-4">
          <div className="w-8 h-8 bg-primary rounded-lg flex items-center justify-center">
            <span className="text-primary-foreground font-bold text-sm">N</span>
          </div>
          <span className="text-xl font-semibold text-foreground">notes2me</span>
        </div>
        <p className="text-muted-foreground mb-6 max-w-md mx-auto">
          Your personal life organizer. Capture everything that matters and discover patterns with AI insights.
        </p>
        <div className="flex justify-center space-x-8 text-sm text-muted-foreground mb-6">
          <a href="#" className="hover:text-foreground">Privacy Policy</a>
          <a href="#" className="hover:text-foreground">Terms of Service</a>
          <a href="#" className="hover:text-foreground">Contact</a>
        </div>
        <p className="text-sm text-muted-foreground">© 2024 notes2me. All rights reserved.</p>
      </footer>
    </div>
  );
};

export default Landing;