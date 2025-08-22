import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Plus, ChevronUp, ChevronDown, Send } from 'lucide-react';
import InputChip from '@/components/InputChip';
import { useToast } from '@/components/ui/use-toast';
import { supabase } from '@/integrations/supabase/client';

interface UnifiedInputPanelProps {
  isInputUICollapsed: boolean;
  onToggleInputUI: () => void;
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (content: any) => Promise<string[]>;
}

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  url?: string;
  siteName?: string;
  videoUrl?: string;
}

interface InputItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'video' | 'audio' | 'file';
  content: any;
  ogData?: OpenGraphData;
}

const UnifiedInputPanel = ({ 
  isInputUICollapsed, 
  onToggleInputUI, 
  onAddContent, 
  getSuggestedTags 
}: UnifiedInputPanelProps) => {
  const [inputText, setInputText] = useState('');
  const [inputItems, setInputItems] = useState<InputItem[]>([]);
  const [isDragOver, setIsDragOver] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { toast } = useToast();

  const generateId = () => Math.random().toString(36).substr(2, 9);

  const fetchOgData = async (url: string): Promise<OpenGraphData | null> => {
    try {
      const { data, error } = await supabase.functions.invoke('extract-link-metadata', {
        body: { url }
      });
      
      if (error) {
        console.error('Error fetching metadata:', error);
        return null;
      }
      
      return data;
    } catch (error) {
      console.error('Error:', error);
      return null;
    }
  };

  const detectUrl = (text: string) => {
    const urlRegex = /(https?:\/\/[^\s]+)/g;
    return text.match(urlRegex);
  };

  const handleInputChange = async (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const value = e.target.value;
    setInputText(value);

    // Auto-detect URLs and add as link chips
    const urls = detectUrl(value);
    if (urls) {
      for (const url of urls) {
        const existingLink = inputItems.find(item => 
          item.type === 'link' && item.content.url === url
        );
        if (!existingLink) {
          const newItem: InputItem = {
            id: generateId(),
            type: 'link',
            content: { url, title: url }
          };
          
          setInputItems(prev => [...prev, newItem]);
          
          // Fetch OG data in background
          fetchOgData(url).then(ogData => {
            if (ogData) {
              setInputItems(prev => prev.map(item => 
                item.id === newItem.id ? { ...item, ogData } : item
              ));
            }
          });
          
          // Remove URL from text
          setInputText(prev => prev.replace(url, '').trim());
        }
      }
    }
  };

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);

    const files = Array.from(e.dataTransfer.files);
    files.forEach(file => {
      const fileType = file.type.startsWith('image/') ? 'image' :
                      file.type.startsWith('video/') ? 'video' :
                      file.type.startsWith('audio/') ? 'audio' : 'file';
      
      setInputItems(prev => [...prev, {
        id: generateId(),
        type: fileType,
        content: {
          file,
          name: file.name,
          size: file.size,
          type: file.type
        }
      }]);
    });
  }, []);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    files.forEach(file => {
      const fileType = file.type.startsWith('image/') ? 'image' :
                      file.type.startsWith('video/') ? 'video' :
                      file.type.startsWith('audio/') ? 'audio' : 'file';
      
      setInputItems(prev => [...prev, {
        id: generateId(),
        type: fileType,
        content: {
          file,
          name: file.name,
          size: file.size,
          type: file.type
        }
      }]);
    });
  };

  const removeInputItem = (id: string) => {
    setInputItems(prev => prev.filter(item => item.id !== id));
  };

  const handleSubmit = async () => {
    if (!inputText.trim() && inputItems.length === 0) return;

    try {
      // Handle text content
      if (inputText.trim()) {
        await onAddContent('text', {
          content: inputText.trim(),
          type: 'text'
        });
      }

      // Handle each input item
      for (const item of inputItems) {
        if (item.type === 'link') {
          await onAddContent('link', {
            url: item.content.url,
            type: 'link'
          });
        } else if (item.type === 'image' || item.type === 'video' || item.type === 'audio' || item.type === 'file') {
          await onAddContent('media', {
            file: item.content.file,
            type: 'media'
          });
        }
      }

      // Clear the form
      setInputText('');
      setInputItems([]);
      
      toast({
        title: "Content added",
        description: "Your content has been added to your stash.",
      });
    } catch (error) {
      console.error('Error adding content:', error);
      toast({
        title: "Error",
        description: "Failed to add content. Please try again.",
        variant: "destructive",
      });
    }
  };

  return (
    <div className="w-full relative">
      {/* Animated gradient background */}
      <div className="absolute inset-0 animated-gradient opacity-30" />
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-background/50 to-transparent" />
      
      <div className="relative pt-8 pb-8">
        <div className="container mx-auto px-4">
          <div className="bg-white/90 backdrop-blur-sm border border-border rounded-xl shadow-lg">
            {/* Input area with minimize button */}
            <div className={`overflow-hidden transition-all duration-300 ease-in-out ${
              isInputUICollapsed ? 'max-h-0 opacity-0' : 'max-h-96 opacity-100'
            }`}>
              <div 
                className={`p-4 space-y-4 relative ${
                  isDragOver ? 'bg-primary/5 border-2 border-dashed border-primary' : ''
                }`}
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
              >
                {/* Minimize button in top right */}
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={onToggleInputUI}
                  className="absolute top-2 right-2 h-6 w-6 p-0"
                >
                  <ChevronUp className="h-4 w-4" />
                </Button>

                <Textarea
                  value={inputText}
                  onChange={handleInputChange}
                  placeholder="What's on your mind? Drop files, paste links, or just start typing..."
                  className="min-h-[100px] resize-none border-0 bg-transparent focus:ring-0 focus:border-0 text-base pr-10"
                />
                
                {/* Input chips */}
                {inputItems.length > 0 && (
                  <div className="flex flex-wrap gap-2 pt-2 border-t border-border">
                    {inputItems.map(item => (
                      <InputChip
                        key={item.id}
                        type={item.type}
                        content={item.content}
                        onRemove={() => removeInputItem(item.id)}
                        ogData={item.ogData}
                      />
                    ))}
                  </div>
                )}
                
                {/* Bottom actions */}
                <div className="flex items-center justify-between pt-2">
                  <div className="flex items-center gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => fileInputRef.current?.click()}
                      className="gap-2"
                    >
                      <Plus className="h-4 w-4" />
                      Attach
                    </Button>
                    <input
                      ref={fileInputRef}
                      type="file"
                      multiple
                      className="hidden"
                      onChange={handleFileSelect}
                    />
                  </div>
                  
                  <Button 
                    onClick={handleSubmit}
                    disabled={!inputText.trim() && inputItems.length === 0}
                    className="gap-2"
                  >
                    <Send className="h-4 w-4" />
                    Add to Stash
                  </Button>
                </div>
              </div>
            </div>

            {/* Collapsed state - show expand button */}
            {isInputUICollapsed && (
              <div className="p-4 flex justify-center">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={onToggleInputUI}
                  className="flex items-center gap-1"
                >
                  <ChevronDown className="h-4 w-4" />
                  Expand
                </Button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default UnifiedInputPanel;