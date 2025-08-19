import React from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { ArrowRight, Smartphone, Brain, MessageSquare } from 'lucide-react';

const Landing = () => {
  return (
    <div className="min-h-screen bg-background font-inter">
      {/* Navigation */}
      <nav className="relative z-10 flex items-center justify-between px-6 py-4 max-w-5xl mx-auto">
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
            <Button className="bg-foreground text-background hover:bg-foreground/90 text-sm px-4 py-2">
              Get Started
            </Button>
          </Link>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="relative px-6 pt-20 pb-24 max-w-4xl mx-auto text-center">
        <div className="fade-in">
          <h1 className="text-4xl md:text-5xl font-semibold text-foreground mb-6 leading-tight tracking-tight">
            Capture everything.<br />
            Understand anything.
          </h1>
          
          <p className="text-lg text-muted-foreground mb-10 max-w-2xl mx-auto leading-relaxed">
            Your universal inbox for thoughts, photos, voice memos, and documents. 
            Chat with your data to discover patterns and insights.
          </p>
          
          <div className="slide-up">
            <Link to="/auth">
              <Button className="bg-foreground text-background hover:bg-foreground/90 text-base px-8 py-3 rounded-md">
                Get Started
                <ArrowRight className="ml-2 h-4 w-4" />
              </Button>
            </Link>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="px-6 py-20 max-w-4xl mx-auto">
        <div className="space-y-20">
          {/* Universal Capture */}
          <div className="text-center">
            <div className="inline-flex items-center justify-center w-12 h-12 bg-muted rounded-lg mb-6">
              <Brain className="h-6 w-6 text-foreground" />
            </div>
            <h3 className="text-xl font-medium text-foreground mb-3">Universal Capture</h3>
            <p className="text-muted-foreground max-w-md mx-auto leading-relaxed">
              Text, photos, voice memos, and documents. Everything you need to capture life's moments.
            </p>
          </div>

          {/* AI Insights */}
          <div className="text-center">
            <div className="inline-flex items-center justify-center w-12 h-12 bg-muted rounded-lg mb-6">
              <MessageSquare className="h-6 w-6 text-foreground" />
            </div>
            <h3 className="text-xl font-medium text-foreground mb-3">AI Insights</h3>
            <p className="text-muted-foreground max-w-md mx-auto leading-relaxed">
              Chat with your data. Discover patterns and insights about your habits and thoughts.
            </p>
          </div>

          {/* Access Everywhere */}
          <div className="text-center">
            <div className="inline-flex items-center justify-center w-12 h-12 bg-muted rounded-lg mb-6">
              <Smartphone className="h-6 w-6 text-foreground" />
            </div>
            <h3 className="text-xl font-medium text-foreground mb-3">Access Everywhere</h3>
            <p className="text-muted-foreground max-w-md mx-auto leading-relaxed">
              Web, mobile, SMS, WhatsApp. Capture thoughts wherever you are.
            </p>
          </div>
        </div>
      </section>

      {/* Call to Action */}
      <section className="px-6 py-20 max-w-4xl mx-auto text-center">
        <h2 className="text-2xl font-medium text-foreground mb-4">Ready to get started?</h2>
        <p className="text-muted-foreground mb-8 max-w-md mx-auto leading-relaxed">
          Start capturing your thoughts and discover what patterns emerge.
        </p>
        <Link to="/auth">
          <Button className="bg-foreground text-background hover:bg-foreground/90 px-8 py-3 rounded-md">
            Get Started
            <ArrowRight className="ml-2 h-4 w-4" />
          </Button>
        </Link>
      </section>

      {/* Footer */}
      <footer className="px-6 py-16 max-w-4xl mx-auto text-center border-t border-border">
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
  );
};

export default Landing;