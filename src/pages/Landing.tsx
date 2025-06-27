import React from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ArrowRight, Zap, Brain, Search, Shield, Smartphone, Globe, FileText, Image, Mic, Video, MessageSquare, Star, CheckCircle, Heart, Calendar, Shirt } from 'lucide-react';

const Landing = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-pink-50 via-rose-50 to-orange-50">
      {/* Navigation */}
      <nav className="relative z-10 flex items-center justify-between px-6 py-4 max-w-7xl mx-auto">
        <div className="flex items-center space-x-2">
          <div className="w-8 h-8 bg-gradient-to-br from-pink-500 to-orange-500 rounded-lg flex items-center justify-center">
            <span className="text-white font-bold text-sm">N</span>
          </div>
          <span className="text-xl font-bold text-gray-900">Noodle</span>
        </div>
        
        <div className="flex items-center space-x-4">
          <Link to="/auth">
            <Button variant="ghost" className="text-gray-600">
              Sign In
            </Button>
          </Link>
          <Link to="/auth">
            <Button className="bg-gradient-to-r from-pink-500 to-orange-500 hover:from-pink-600 hover:to-orange-600">
              Get Started
            </Button>
          </Link>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="relative px-6 py-20 max-w-7xl mx-auto text-center">
        <Badge className="mb-6 bg-pink-100 text-pink-700 border-pink-200">
          Life made organized
        </Badge>
        
        <h1 className="text-5xl md:text-7xl font-bold text-gray-900 mb-6 leading-tight">
          <span className="block bg-gradient-to-r from-pink-500 to-orange-500 bg-clip-text text-transparent">
            You & Improved.
          </span>
        </h1>
        
        <p className="text-xl text-gray-600 mb-8 max-w-2xl mx-auto leading-relaxed">
          Capture everything that matters - from workout logs to travel plans, health information tracking to daily thoughts. 
          Noodle keeps your life organized and helps you discover patterns and insights you never knew existed.
        </p>
        
        <div className="flex flex-col sm:flex-row gap-4 justify-center items-center mb-16">
          <Link to="/auth">
            <Button size="lg" className="bg-gradient-to-r from-pink-500 to-orange-500 hover:from-pink-600 hover:to-orange-600 text-lg px-8 py-4">
              Start Organizing
              <ArrowRight className="ml-2 h-5 w-5" />
            </Button>
          </Link>
          <Button variant="outline" size="lg" className="text-lg px-8 py-4">
            Watch Demo
          </Button>
        </div>

        {/* Hero Visual */}
        <div className="relative">
          <div className="bg-white rounded-2xl shadow-2xl p-8 max-w-4xl mx-auto border">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-4">
                <div className="flex items-center space-x-2 text-sm text-gray-500">
                  <FileText className="h-4 w-4" />
                  <span>Health Log - Today</span>
                </div>
                <h3 className="text-lg font-semibold">Morning Workout & Vitamins</h3>
                <p className="text-gray-600 text-sm">
                  45min cardio session, felt energized. Took vitamin D and B12. Weight: 165lbs...
                </p>
                <div className="flex flex-wrap gap-2">
                  <Badge variant="secondary" className="text-xs">fitness</Badge>
                  <Badge variant="secondary" className="text-xs">health</Badge>
                  <Badge variant="secondary" className="text-xs">routine</Badge>
                </div>
              </div>
              <div className="bg-gradient-to-br from-pink-50 to-orange-50 rounded-lg p-4">
                <div className="flex items-center space-x-2 mb-3">
                  <MessageSquare className="h-4 w-4 text-pink-600" />
                  <span className="text-sm font-medium text-pink-700">AI Insights</span>
                </div>
                <div className="space-y-2 text-sm">
                  <div className="bg-white rounded-lg p-2 text-gray-600">
                    "How's my fitness progress this month?"
                  </div>
                  <div className="bg-pink-100 rounded-lg p-2 text-pink-700">
                    You've worked out 18 days this month! Your energy levels are highest on days you exercise in the morning. Consider scheduling more AM workouts...
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Use Cases Section */}
      <section className="px-6 py-20 max-w-7xl mx-auto">
        <div className="text-center mb-16">
          <Badge className="mb-4 bg-rose-100 text-rose-700 border-rose-200">
            Perfect For Your Life
          </Badge>
          <h2 className="text-4xl font-bold text-gray-900 mb-4">
            Three ways to transform your daily life
          </h2>
          <p className="text-xl text-gray-600 max-w-2xl mx-auto">
            Whether you're tracking wellness, planning experiences, or curating your style, Noodle helps you capture and organize what matters most.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          <Card className="border-0 shadow-lg bg-white/80 backdrop-blur hover:shadow-xl transition-shadow">
            <CardContent className="p-8 text-center">
              <div className="w-16 h-16 bg-gradient-to-br from-pink-500 to-rose-500 rounded-2xl flex items-center justify-center mx-auto mb-6">
                <Heart className="h-8 w-8 text-white" />
              </div>
              <h3 className="text-2xl font-semibold mb-4 text-gray-900">Health Tracking</h3>
              <p className="text-gray-600 mb-6 leading-relaxed">
                Log workouts, meals, symptoms, and mood. Track your energy patterns, discover what makes you feel your best, and build healthier habits with AI insights.
              </p>
              <div className="space-y-2 text-sm text-gray-500">
                <div className="flex items-center justify-center space-x-2">
                  <div className="w-2 h-2 bg-pink-400 rounded-full"></div>
                  <span>Workout logs & progress photos</span>
                </div>
                <div className="flex items-center justify-center space-x-2">
                  <div className="w-2 h-2 bg-rose-400 rounded-full"></div>
                  <span>Meal tracking & nutrition notes</span>
                </div>
                <div className="flex items-center justify-center space-x-2">
                  <div className="w-2 h-2 bg-pink-400 rounded-full"></div>
                  <span>Sleep & mood patterns</span>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card className="border-0 shadow-lg bg-white/80 backdrop-blur hover:shadow-xl transition-shadow">
            <CardContent className="p-8 text-center">
              <div className="w-16 h-16 bg-gradient-to-br from-rose-500 to-orange-500 rounded-2xl flex items-center justify-center mx-auto mb-6">
                <Calendar className="h-8 w-8 text-white" />
              </div>
              <h3 className="text-2xl font-semibold mb-4 text-gray-900">Event Planning</h3>
              <p className="text-gray-600 mb-6 leading-relaxed">
                Plan perfect vacations, parties, and special moments. Save inspiration, track ideas, and create detailed itineraries. Never forget the details that make events memorable.
              </p>
              <div className="space-y-2 text-sm text-gray-500">
                <div className="flex items-center justify-center space-x-2">
                  <div className="w-2 h-2 bg-rose-400 rounded-full"></div>
                  <span>Travel itineraries & bookings</span>
                </div>
                <div className="flex items-center justify-center space-x-2">
                  <div className="w-2 h-2 bg-orange-400 rounded-full"></div>
                  <span>Party planning & guest lists</span>
                </div>
                <div className="flex items-center justify-center space-x-2">
                  <div className="w-2 h-2 bg-rose-400 rounded-full"></div>
                  <span>Special occasion memories</span>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card className="border-0 shadow-lg bg-white/80 backdrop-blur hover:shadow-xl transition-shadow">
            <CardContent className="p-8 text-center">
              <div className="w-16 h-16 bg-gradient-to-br from-orange-500 to-amber-500 rounded-2xl flex items-center justify-center mx-auto mb-6">
                <Shirt className="h-8 w-8 text-white" />
              </div>
              <h3 className="text-2xl font-semibold mb-4 text-gray-900">Fashion & Style</h3>
              <p className="text-gray-600 mb-6 leading-relaxed">
                Curate your perfect wardrobe. Save outfit ideas, track what you love wearing, and discover your personal style patterns. Never run out of inspiration again.
              </p>
              <div className="space-y-2 text-sm text-gray-500">
                <div className="flex items-center justify-center space-x-2">
                  <div className="w-2 h-2 bg-orange-400 rounded-full"></div>
                  <span>Outfit photos & combinations</span>
                </div>
                <div className="flex items-center justify-center space-x-2">
                  <div className="w-2 h-2 bg-amber-400 rounded-full"></div>
                  <span>Style inspiration & mood boards</span>
                </div>
                <div className="flex items-center justify-center space-x-2">
                  <div className="w-2 h-2 bg-orange-400 rounded-full"></div>
                  <span>Shopping lists & wishlist items</span>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Features Section */}
      <section className="px-6 py-20 max-w-7xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-4xl font-bold text-gray-900 mb-4">
            Everything you need to organize your life
          </h2>
          <p className="text-xl text-gray-600 max-w-2xl mx-auto">
            Powerful features that adapt to how you live, helping you capture moments and discover insights effortlessly.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          <Card className="border-0 shadow-lg bg-white/80 backdrop-blur">
            <CardContent className="p-6">
              <div className="w-12 h-12 bg-gradient-to-br from-pink-500 to-rose-500 rounded-lg flex items-center justify-center mb-4">
                <Brain className="h-6 w-6 text-white" />
              </div>
              <h3 className="text-xl font-semibold mb-2">Universal Capture</h3>
              <p className="text-gray-600">
                Capture text, photos, voice memos, videos, and documents. Noodle automatically organizes everything from workouts to recipes to travel plans.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 shadow-lg bg-white/80 backdrop-blur">
            <CardContent className="p-6">
              <div className="w-12 h-12 bg-gradient-to-br from-rose-500 to-orange-500 rounded-lg flex items-center justify-center mb-4">
                <MessageSquare className="h-6 w-6 text-white" />
              </div>
              <h3 className="text-xl font-semibold mb-2">AI Life Insights</h3>
              <p className="text-gray-600">
                Chat with your life data using AI. Ask about your habits, health patterns, or find that recipe you saved months ago.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 shadow-lg bg-white/80 backdrop-blur">
            <CardContent className="p-6">
              <div className="w-12 h-12 bg-gradient-to-br from-orange-500 to-amber-500 rounded-lg flex items-center justify-center mb-4">
                <Search className="h-6 w-6 text-white" />
              </div>
              <h3 className="text-xl font-semibold mb-2">Smart Search</h3>
              <p className="text-gray-600">
                Find anything instantly with intelligent search that understands context - from that doctor's note to your vacation photos.
              </p>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Content Types Section */}
      <section className="px-6 py-20 max-w-7xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
          <div>
            <Badge className="mb-4 bg-rose-100 text-rose-700 border-rose-200">
              All Life Content Types
            </Badge>
            <h2 className="text-4xl font-bold text-gray-900 mb-6">
              Capture your entire life
            </h2>
            <p className="text-xl text-gray-600 mb-8">
              From quick voice memos about meal ideas to detailed travel itineraries, Noodle handles every aspect of your life. Everything is searchable, organized, and ready when you need it.
            </p>
            
            <div className="space-y-4">
              <div className="flex items-center space-x-3">
                <div className="w-8 h-8 bg-pink-100 rounded-lg flex items-center justify-center">
                  <FileText className="h-4 w-4 text-pink-600" />
                </div>
                <span className="text-gray-700">Journal entries, goals, and daily reflections</span>
              </div>
              <div className="flex items-center space-x-3">
                <div className="w-8 h-8 bg-rose-100 rounded-lg flex items-center justify-center">
                  <Image className="h-4 w-4 text-rose-600" />
                </div>
                <span className="text-gray-700">Photos from workouts, meals, and life moments</span>
              </div>
              <div className="flex items-center space-x-3">
                <div className="w-8 h-8 bg-orange-100 rounded-lg flex items-center justify-center">
                  <Mic className="h-4 w-4 text-orange-600" />
                </div>
                <span className="text-gray-700">Voice notes about ideas and daily experiences</span>
              </div>
              <div className="flex items-center space-x-3">
                <div className="w-8 h-8 bg-amber-100 rounded-lg flex items-center justify-center">
                  <Video className="h-4 w-4 text-amber-600" />
                </div>
                <span className="text-gray-700">Video logs of progress and special moments</span>
              </div>
            </div>
          </div>
          
          <div className="relative">
            <div className="grid grid-cols-2 gap-4">
              <Card className="bg-gradient-to-br from-pink-50 to-pink-100 border-pink-200">
                <CardContent className="p-4">
                  <FileText className="h-8 w-8 text-pink-600 mb-2" />
                  <h4 className="font-semibold text-pink-900">Journal</h4>
                  <p className="text-sm text-pink-700">Daily thoughts</p>
                </CardContent>
              </Card>
              <Card className="bg-gradient-to-br from-rose-50 to-rose-100 border-rose-200">
                <CardContent className="p-4">
                  <Image className="h-8 w-8 text-rose-600 mb-2" />
                  <h4 className="font-semibold text-rose-900">Photos</h4>
                  <p className="text-sm text-rose-700">Life moments</p>
                </CardContent>
              </Card>
              <Card className="bg-gradient-to-br from-orange-50 to-orange-100 border-orange-200">
                <CardContent className="p-4">
                  <Mic className="h-8 w-8 text-orange-600 mb-2" />
                  <h4 className="font-semibold text-orange-900">Voice</h4>
                  <p className="text-sm text-orange-700">Quick thoughts</p>
                </CardContent>
              </Card>
              <Card className="bg-gradient-to-br from-amber-50 to-amber-100 border-amber-200">
                <CardContent className="p-4">
                  <Video className="h-8 w-8 text-amber-600 mb-2" />
                  <h4 className="font-semibold text-amber-900">Video</h4>
                  <p className="text-sm text-amber-700">Progress logs</p>
                </CardContent>
              </Card>
            </div>
          </div>
        </div>
      </section>

      {/* AI Features Section */}
      <section className="px-6 py-20 max-w-7xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
          <div className="relative order-2 lg:order-1">
            <div className="bg-gradient-to-br from-gray-900 to-gray-800 rounded-2xl shadow-2xl p-8 text-white">
              <div className="flex items-center space-x-2 mb-6">
                <div className="w-8 h-8 bg-gradient-to-br from-pink-400 to-orange-400 rounded-lg flex items-center justify-center">
                  <MessageSquare className="h-4 w-4 text-white" />
                </div>
                <span className="font-medium">AI Life Coach</span>
              </div>
              
              <div className="space-y-4">
                <div className="bg-gray-700/50 rounded-lg p-3">
                  <p className="text-sm text-gray-300">You:</p>
                  <p className="text-white">"What's been helping my energy levels lately?"</p>
                </div>
                <div className="bg-gradient-to-r from-pink-600/20 to-orange-600/20 rounded-lg p-3 border border-pink-500/30">
                  <p className="text-sm text-pink-300">Noodle:</p>
                  <p className="text-white text-sm">Based on your logs, you have the most energy on days when you exercise in the morning and get 7+ hours of sleep. Your mood also improves when you spend time outdoors...</p>
                </div>
              </div>
            </div>
          </div>
          
          <div className="order-1 lg:order-2">
            <Badge className="mb-4 bg-pink-100 text-pink-700 border-pink-200">
              AI-Powered Life Intelligence
            </Badge>
            <h2 className="text-4xl font-bold text-gray-900 mb-6">
              Discover patterns in your life
            </h2>
            <p className="text-xl text-gray-600 mb-8">
              Never lose track of what matters. Our AI understands your lifestyle and helps you find connections, patterns, and insights that improve your well-being.
            </p>
            
            <div className="space-y-6">
              <div className="flex items-start space-x-4">
                <div className="w-10 h-10 bg-pink-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <CheckCircle className="h-5 w-5 text-pink-600" />
                </div>
                <div>
                  <h4 className="font-semibold text-gray-900 mb-1">Health Insights</h4>
                  <p className="text-gray-600">Track patterns in your wellness, mood, and energy levels.</p>
                </div>
              </div>
              
              <div className="flex items-start space-x-4">
                <div className="w-10 h-10 bg-rose-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <CheckCircle className="h-5 w-5 text-rose-600" />
                </div>
                <div>
                  <h4 className="font-semibold text-gray-900 mb-1">Life Connections</h4>
                  <p className="text-gray-600">Discover how different aspects of your life influence each other.</p>
                </div>
              </div>
              
              <div className="flex items-start space-x-4">
                <div className="w-10 h-10 bg-orange-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <CheckCircle className="h-5 w-5 text-orange-600" />
                </div>
                <div>
                  <h4 className="font-semibold text-gray-900 mb-1">Smart Reminders</h4>
                  <p className="text-gray-600">Get intelligent suggestions based on your habits and goals.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Integration Section */}
      <section className="px-6 py-20 max-w-7xl mx-auto">
        <div className="text-center mb-16">
          <Badge className="mb-4 bg-rose-100 text-rose-700 border-rose-200">
            Access Anywhere
          </Badge>
          <h2 className="text-4xl font-bold text-gray-900 mb-4">
            Life happens everywhere
          </h2>
          <p className="text-xl text-gray-600 max-w-2xl mx-auto">
            Capture moments from anywhere. Noodle works seamlessly across all your devices, plus you can text or message us directly.
          </p>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-8 mb-16">
          <div className="text-center">
            <div className="w-16 h-16 bg-gradient-to-br from-pink-500 to-pink-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <Globe className="h-8 w-8 text-white" />
            </div>
            <h4 className="font-semibold text-gray-900">Web & Mobile</h4>
            <p className="text-sm text-gray-600">Full-featured on any device</p>
          </div>
          
          <div className="text-center">
            <div className="w-16 h-16 bg-gradient-to-br from-rose-500 to-rose-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <MessageSquare className="h-8 w-8 text-white" />
            </div>
            <h4 className="font-semibold text-gray-900">SMS & WhatsApp</h4>
            <p className="text-sm text-gray-600">Text us your thoughts</p>
          </div>
          
          <div className="text-center">
            <div className="w-16 h-16 bg-gradient-to-br from-orange-500 to-orange-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <Shield className="h-8 w-8 text-white" />
            </div>
            <h4 className="font-semibold text-gray-900">Private & Secure</h4>
            <p className="text-sm text-gray-600">Your data stays yours</p>
          </div>
          
          <div className="text-center">
            <div className="w-16 h-16 bg-gradient-to-br from-amber-500 to-amber-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <Zap className="h-8 w-8 text-white" />
            </div>
            <h4 className="font-semibold text-gray-900">Instant</h4>
            <p className="text-sm text-gray-600">Lightning-quick capture</p>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="px-6 py-20 max-w-4xl mx-auto text-center">
        <div className="bg-gradient-to-br from-pink-500 to-orange-500 rounded-3xl p-12 text-white">
          <h2 className="text-4xl font-bold mb-4">
            Start organizing your life today
          </h2>
          <p className="text-xl mb-8 text-pink-100">
            Join thousands of people who have transformed how they track, organize, and understand their lives with Noodle. Start capturing moments and discovering insights today.
          </p>
          
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Link to="/auth">
              <Button size="lg" className="bg-white text-pink-600 hover:bg-gray-100 text-lg px-8 py-4">
                Start Free
                <ArrowRight className="ml-2 h-5 w-5" />
              </Button>
            </Link>
            <Button variant="outline" size="lg" className="border-white text-white hover:bg-white/10 text-lg px-8 py-4">
              See How It Works
            </Button>
          </div>
          
          <div className="flex items-center justify-center space-x-1 mt-8 text-pink-200">
            {[1, 2, 3, 4, 5].map((star) => (
              <Star key={star} className="h-5 w-5 fill-current" />
            ))}
            <span className="ml-2">Loved by 10,000+ users</span>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="px-6 py-12 max-w-7xl mx-auto border-t border-gray-200 mt-20">
        <div className="text-center">
          <div className="flex items-center justify-center space-x-2 mb-4">
            <div className="w-8 h-8 bg-gradient-to-br from-pink-500 to-orange-500 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-sm">N</span>
            </div>
            <span className="text-xl font-bold text-gray-900">Noodle</span>
          </div>
          <p className="text-gray-600 mb-6">
            Your personal life assistant for capturing, organizing, and understanding what matters most.
          </p>
          
          <div className="flex flex-col sm:flex-row gap-4 justify-center items-center">
            <Link to="/auth" className="text-gray-600 hover:text-gray-900">
              Privacy Policy
            </Link>
            <Link to="/auth" className="text-gray-600 hover:text-gray-900">
              Terms of Service
            </Link>
            <Link to="/auth" className="text-gray-600 hover:text-gray-900">
              Contact
            </Link>
          </div>
          
          <div className="mt-8 pt-8 border-t border-gray-200">
            <p className="text-gray-500">
              © 2024 Noodle. All rights reserved.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
};

export default Landing;
