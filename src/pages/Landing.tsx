
import React from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ArrowRight, Zap, Brain, Search, Shield, Smartphone, Globe, FileText, Image, Mic, Video, MessageSquare, Star, CheckCircle } from 'lucide-react';

const Landing = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-pink-50 via-purple-50 to-orange-50">
      {/* Navigation */}
      <nav className="relative z-10 flex items-center justify-between px-6 py-4 max-w-7xl mx-auto">
        <div className="flex items-center space-x-2">
          <div className="w-8 h-8 bg-gradient-to-br from-purple-600 to-pink-600 rounded-lg flex items-center justify-center">
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
            <Button className="bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-700 hover:to-pink-700">
              Get Started
            </Button>
          </Link>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="relative px-6 py-20 max-w-7xl mx-auto text-center">
        <Badge className="mb-6 bg-purple-100 text-purple-700 border-purple-200">
          Your Smart Content Companion
        </Badge>
        
        <h1 className="text-5xl md:text-7xl font-bold text-gray-900 mb-6 leading-tight">
          Thinking made
          <span className="block bg-gradient-to-r from-purple-600 to-pink-600 bg-clip-text text-transparent">
            simple
          </span>
        </h1>
        
        <p className="text-xl text-gray-600 mb-8 max-w-2xl mx-auto leading-relaxed">
          Capture, organize, and chat with your content. From quick notes to complex documents, 
          Noodle helps you remember everything and find insights you never knew existed.
        </p>
        
        <div className="flex flex-col sm:flex-row gap-4 justify-center items-center mb-16">
          <Link to="/auth">
            <Button size="lg" className="bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-700 hover:to-pink-700 text-lg px-8 py-4">
              Start for Free
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
                  <span>Meeting Notes - Today</span>
                </div>
                <h3 className="text-lg font-semibold">Product Strategy Meeting</h3>
                <p className="text-gray-600 text-sm">
                  Discussed Q4 roadmap, user feedback integration, and new AI features...
                </p>
                <div className="flex flex-wrap gap-2">
                  <Badge variant="secondary" className="text-xs">strategy</Badge>
                  <Badge variant="secondary" className="text-xs">roadmap</Badge>
                  <Badge variant="secondary" className="text-xs">AI</Badge>
                </div>
              </div>
              <div className="bg-gradient-to-br from-purple-50 to-pink-50 rounded-lg p-4">
                <div className="flex items-center space-x-2 mb-3">
                  <MessageSquare className="h-4 w-4 text-purple-600" />
                  <span className="text-sm font-medium text-purple-700">AI Chat</span>
                </div>
                <div className="space-y-2 text-sm">
                  <div className="bg-white rounded-lg p-2 text-gray-600">
                    "What were the key decisions from today's meeting?"
                  </div>
                  <div className="bg-purple-100 rounded-lg p-2 text-purple-700">
                    Based on your notes, you decided to prioritize user feedback integration and explore new AI-powered features for Q4...
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="px-6 py-20 max-w-7xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-4xl font-bold text-gray-900 mb-4">
            Everything you need to grow your team
          </h2>
          <p className="text-xl text-gray-600 max-w-2xl mx-auto">
            Powerful features that adapt to how you work, helping you capture ideas and find insights effortlessly.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          <Card className="border-0 shadow-lg bg-white/80 backdrop-blur">
            <CardContent className="p-6">
              <div className="w-12 h-12 bg-gradient-to-br from-purple-500 to-pink-500 rounded-lg flex items-center justify-center mb-4">
                <Brain className="h-6 w-6 text-white" />
              </div>
              <h3 className="text-xl font-semibold mb-2">Smart Capture</h3>
              <p className="text-gray-600">
                Capture text, images, audio, video, and documents. Noodle automatically organizes and tags everything for easy retrieval.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 shadow-lg bg-white/80 backdrop-blur">
            <CardContent className="p-6">
              <div className="w-12 h-12 bg-gradient-to-br from-blue-500 to-cyan-500 rounded-lg flex items-center justify-center mb-4">
                <MessageSquare className="h-6 w-6 text-white" />
              </div>
              <h3 className="text-xl font-semibold mb-2">AI-Powered Chat</h3>
              <p className="text-gray-600">
                Chat with your content using advanced AI. Ask questions, get summaries, and discover insights from everything you've saved.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 shadow-lg bg-white/80 backdrop-blur">
            <CardContent className="p-6">
              <div className="w-12 h-12 bg-gradient-to-br from-green-500 to-emerald-500 rounded-lg flex items-center justify-center mb-4">
                <Search className="h-6 w-6 text-white" />
              </div>
              <h3 className="text-xl font-semibold mb-2">Instant Search</h3>
              <p className="text-gray-600">
                Find anything instantly with intelligent search that understands context, content, and connections between your items.
              </p>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Content Types Section */}
      <section className="px-6 py-20 max-w-7xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
          <div>
            <Badge className="mb-4 bg-orange-100 text-orange-700 border-orange-200">
              Multiple Content Types
            </Badge>
            <h2 className="text-4xl font-bold text-gray-900 mb-6">
              Manage the entire hiring workflow
            </h2>
            <p className="text-xl text-gray-600 mb-8">
              From quick voice memos to detailed documents, Noodle handles every type of content you throw at it. Everything is searchable, organized, and ready when you need it.
            </p>
            
            <div className="space-y-4">
              <div className="flex items-center space-x-3">
                <div className="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
                  <FileText className="h-4 w-4 text-blue-600" />
                </div>
                <span className="text-gray-700">Rich text notes and documents</span>
              </div>
              <div className="flex items-center space-x-3">
                <div className="w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center">
                  <Image className="h-4 w-4 text-green-600" />
                </div>
                <span className="text-gray-700">Images with automatic text extraction</span>
              </div>
              <div className="flex items-center space-x-3">
                <div className="w-8 h-8 bg-purple-100 rounded-lg flex items-center justify-center">
                  <Mic className="h-4 w-4 text-purple-600" />
                </div>
                <span className="text-gray-700">Audio recordings and transcriptions</span>
              </div>
              <div className="flex items-center space-x-3">
                <div className="w-8 h-8 bg-red-100 rounded-lg flex items-center justify-center">
                  <Video className="h-4 w-4 text-red-600" />
                </div>
                <span className="text-gray-700">Video content and analysis</span>
              </div>
            </div>
          </div>
          
          <div className="relative">
            <div className="grid grid-cols-2 gap-4">
              <Card className="bg-gradient-to-br from-blue-50 to-blue-100 border-blue-200">
                <CardContent className="p-4">
                  <FileText className="h-8 w-8 text-blue-600 mb-2" />
                  <h4 className="font-semibold text-blue-900">Notes</h4>
                  <p className="text-sm text-blue-700">Rich text editing</p>
                </CardContent>
              </Card>
              <Card className="bg-gradient-to-br from-green-50 to-green-100 border-green-200">
                <CardContent className="p-4">
                  <Image className="h-8 w-8 text-green-600 mb-2" />
                  <h4 className="font-semibold text-green-900">Images</h4>
                  <p className="text-sm text-green-700">OCR & analysis</p>
                </CardContent>
              </Card>
              <Card className="bg-gradient-to-br from-purple-50 to-purple-100 border-purple-200">
                <CardContent className="p-4">
                  <Mic className="h-8 w-8 text-purple-600 mb-2" />
                  <h4 className="font-semibold text-purple-900">Audio</h4>
                  <p className="text-sm text-purple-700">Auto transcription</p>
                </CardContent>
              </Card>
              <Card className="bg-gradient-to-br from-red-50 to-red-100 border-red-200">
                <CardContent className="p-4">
                  <Video className="h-8 w-8 text-red-600 mb-2" />
                  <h4 className="font-semibold text-red-900">Video</h4>
                  <p className="text-sm text-red-700">Content extraction</p>
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
                <div className="w-8 h-8 bg-gradient-to-br from-purple-400 to-pink-400 rounded-lg flex items-center justify-center">
                  <MessageSquare className="h-4 w-4 text-white" />
                </div>
                <span className="font-medium">AI Assistant</span>
              </div>
              
              <div className="space-y-4">
                <div className="bg-gray-700/50 rounded-lg p-3">
                  <p className="text-sm text-gray-300">You:</p>
                  <p className="text-white">"Summarize my meeting notes from last week"</p>
                </div>
                <div className="bg-gradient-to-r from-purple-600/20 to-pink-600/20 rounded-lg p-3 border border-purple-500/30">
                  <p className="text-sm text-purple-300">Noodle:</p>
                  <p className="text-white text-sm">I found 3 meeting notes from last week. Key themes include product roadmap discussions, budget approvals for Q4, and team restructuring. The main decisions were...</p>
                </div>
              </div>
            </div>
          </div>
          
          <div className="order-1 lg:order-2">
            <Badge className="mb-4 bg-purple-100 text-purple-700 border-purple-200">
              AI-Powered Intelligence
            </Badge>
            <h2 className="text-4xl font-bold text-gray-900 mb-6">
              Keep track of everything
            </h2>
            <p className="text-xl text-gray-600 mb-8">
              Never lose an idea again. Our AI understands your content and helps you find connections, patterns, and insights you might have missed.
            </p>
            
            <div className="space-y-6">
              <div className="flex items-start space-x-4">
                <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <CheckCircle className="h-5 w-5 text-purple-600" />
                </div>
                <div>
                  <h4 className="font-semibold text-gray-900 mb-1">Smart Summaries</h4>
                  <p className="text-gray-600">Get instant summaries of your content, meetings, and documents.</p>
                </div>
              </div>
              
              <div className="flex items-start space-x-4">
                <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <CheckCircle className="h-5 w-5 text-blue-600" />
                </div>
                <div>
                  <h4 className="font-semibold text-gray-900 mb-1">Content Connections</h4>
                  <p className="text-gray-600">Discover relationships between different pieces of content automatically.</p>
                </div>
              </div>
              
              <div className="flex items-start space-x-4">
                <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <CheckCircle className="h-5 w-5 text-green-600" />
                </div>
                <div>
                  <h4 className="font-semibold text-gray-900 mb-1">Intelligent Search</h4>
                  <p className="text-gray-600">Ask questions in natural language and get precise answers from your content.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Integration Section */}
      <section className="px-6 py-20 max-w-7xl mx-auto">
        <div className="text-center mb-16">
          <Badge className="mb-4 bg-blue-100 text-blue-700 border-blue-200">
            Works Everywhere
          </Badge>
          <h2 className="text-4xl font-bold text-gray-900 mb-4">
            Work together
          </h2>
          <p className="text-xl text-gray-600 max-w-2xl mx-auto">
            Access your content from anywhere. Noodle works seamlessly across all your devices and integrates with the tools you already use.
          </p>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-8 mb-16">
          <div className="text-center">
            <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-blue-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <Globe className="h-8 w-8 text-white" />
            </div>
            <h4 className="font-semibold text-gray-900">Web App</h4>
            <p className="text-sm text-gray-600">Full-featured web interface</p>
          </div>
          
          <div className="text-center">
            <div className="w-16 h-16 bg-gradient-to-br from-green-500 to-green-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <Smartphone className="h-8 w-8 text-white" />
            </div>
            <h4 className="font-semibold text-gray-900">Mobile Ready</h4>
            <p className="text-sm text-gray-600">Optimized for all devices</p>
          </div>
          
          <div className="text-center">
            <div className="w-16 h-16 bg-gradient-to-br from-purple-500 to-purple-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <Shield className="h-8 w-8 text-white" />
            </div>
            <h4 className="font-semibold text-gray-900">Secure</h4>
            <p className="text-sm text-gray-600">End-to-end encryption</p>
          </div>
          
          <div className="text-center">
            <div className="w-16 h-16 bg-gradient-to-br from-orange-500 to-orange-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <Zap className="h-8 w-8 text-white" />
            </div>
            <h4 className="font-semibold text-gray-900">Fast</h4>
            <p className="text-sm text-gray-600">Lightning-quick search</p>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="px-6 py-20 max-w-4xl mx-auto text-center">
        <div className="bg-gradient-to-br from-purple-600 to-pink-600 rounded-3xl p-12 text-white">
          <h2 className="text-4xl font-bold mb-4">
            Get to hiring in minutes
          </h2>
          <p className="text-xl mb-8 text-purple-100">
            Join thousands of teams who have streamlined their content workflow with Noodle. Start capturing, organizing, and discovering insights today.
          </p>
          
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Link to="/auth">
              <Button size="lg" className="bg-white text-purple-600 hover:bg-gray-100 text-lg px-8 py-4">
                Start Free Trial
                <ArrowRight className="ml-2 h-5 w-5" />
              </Button>
            </Link>
            <Button variant="outline" size="lg" className="border-white text-white hover:bg-white/10 text-lg px-8 py-4">
              Schedule Demo
            </Button>
          </div>
          
          <div className="flex items-center justify-center space-x-1 mt-8 text-purple-200">
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
            <div className="w-8 h-8 bg-gradient-to-br from-purple-600 to-pink-600 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-sm">N</span>
            </div>
            <span className="text-xl font-bold text-gray-900">Noodle</span>
          </div>
          <p className="text-gray-600 mb-6">
            Your smart content companion for capturing, organizing, and discovering insights.
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
