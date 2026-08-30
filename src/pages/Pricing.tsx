import StashWordmark from '@/components/StashWordmark';
import React from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Check } from 'lucide-react';

const Pricing = () => {
  return (
    <div className="min-h-screen bg-background font-montreal">
      {/* Navigation */}
      <nav className="flex items-center justify-between px-6 py-4 max-w-5xl mx-auto">
        <Link to="/" className="flex items-center">
          <StashWordmark className="h-5 text-foreground" />
        </Link>
        
        <div className="flex items-center space-x-3">
          <Link to="/auth">
            <Button variant="ghost" className="text-muted-foreground hover:text-foreground text-sm font-montreal">
              Sign In
            </Button>
          </Link>
        </div>
      </nav>

      {/* Pricing Section */}
      <section className="px-6 pt-16 pb-32 max-w-2xl mx-auto">
        <div className="text-center mb-12 fade-in">
          <h1 className="text-4xl md:text-5xl font-tobias text-foreground mb-4 leading-tight tracking-tight">
            Start your free trial
          </h1>
          <p className="text-lg font-montreal text-muted-foreground max-w-xl mx-auto leading-relaxed">
            Experience all premium features for 14 days. No credit card required.
          </p>
        </div>

        <div className="slide-up">
          <Card className="border-2 border-foreground shadow-xl hover:shadow-2xl transition-shadow duration-300">
            <CardHeader className="text-center pb-8 pt-8">
              <CardDescription className="text-base font-montreal text-muted-foreground mb-2">
                14 day free trial
              </CardDescription>
              <CardTitle className="text-3xl font-tobias text-foreground mb-4">
                Stash Premium
              </CardTitle>
              <div className="text-4xl font-tobias text-foreground">
                $4.99
                <span className="text-lg text-muted-foreground font-montreal">/month</span>
              </div>
            </CardHeader>
            <CardContent className="pb-8">
              <ul className="space-y-4 mb-8">
                <li className="flex items-start space-x-3">
                  <Check className="h-5 w-5 text-green-600 mt-0.5 flex-shrink-0" />
                  <span className="font-montreal text-foreground">
                    AI-powered search and conversation with all your content
                  </span>
                </li>
                <li className="flex items-start space-x-3">
                  <Check className="h-5 w-5 text-green-600 mt-0.5 flex-shrink-0" />
                  <span className="font-montreal text-foreground">
                    Automatic link previews with rich metadata (OpenGraph)
                  </span>
                </li>
                <li className="flex items-start space-x-3">
                  <Check className="h-5 w-5 text-green-600 mt-0.5 flex-shrink-0" />
                  <span className="font-montreal text-foreground">
                    Searchable image descriptions powered by AI
                  </span>
                </li>
                <li className="flex items-start space-x-3">
                  <Check className="h-5 w-5 text-green-600 mt-0.5 flex-shrink-0" />
                  <span className="font-montreal text-foreground">
                    Auto-transcription of audio files and voice notes
                  </span>
                </li>
                <li className="flex items-start space-x-3">
                  <Check className="h-5 w-5 text-green-600 mt-0.5 flex-shrink-0" />
                  <span className="font-montreal text-foreground">
                    WhatsApp integration for capturing on the go
                  </span>
                </li>
                <li className="flex items-start space-x-3">
                  <Check className="h-5 w-5 text-green-600 mt-0.5 flex-shrink-0" />
                  <span className="font-montreal text-foreground">
                    Smart tagging system for easy organization
                  </span>
                </li>
                <li className="flex items-start space-x-3">
                  <Check className="h-5 w-5 text-green-600 mt-0.5 flex-shrink-0" />
                  <span className="font-montreal text-foreground">
                    Personalized public feed to share with friends
                  </span>
                </li>
              </ul>
              
              <Link to="/auth?mode=signup" className="block">
                <Button 
                  size="lg" 
                  className="w-full bg-foreground text-background hover:bg-foreground/90 text-lg px-10 py-6 rounded-full shadow-lg font-montreal"
                >
                  Sign up
                </Button>
              </Link>
              
              <p className="text-center text-sm text-muted-foreground font-montreal mt-6">
                Cancel anytime. No questions asked.
              </p>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Footer */}
      <footer className="px-6 py-8 max-w-4xl mx-auto text-center border-t border-border">
        <p className="text-sm text-muted-foreground font-montreal">
          © 2024 Stash. All rights reserved.
        </p>
      </footer>
    </div>
  );
};

export default Pricing;
