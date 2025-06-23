
import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { FileText, Link as LinkIcon } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import LinkPreview from './LinkPreview';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  url: string;
  siteName?: string;
}

interface TextLinkInputProps {
  onAddContent: (type: string, data: any) => Promise<void>;
}

const TextLinkInput = ({ onAddContent }: TextLinkInputProps) => {
  const [textInput, setTextInput] = useState('');
  const [ogData, setOgData] = useState<OpenGraphData | null>(null);
  const [isLoadingOg, setIsLoadingOg] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const { toast } = useToast();

  const isValidUrl = (string: string) => {
    try {
      new URL(string);
      return true;
    } catch {
      return false;
    }
  };

  const fetchOpenGraph = async (url: string) => {
    setIsLoadingOg(true);
    try {
      // Use a CORS proxy or your own endpoint to fetch OG data
      const response = await fetch(`https://api.microlink.io/?url=${encodeURIComponent(url)}`);
      const data = await response.json();
      
      if (data.status === 'success') {
        setOgData({
          title: data.data.title,
          description: data.data.description,
          image: data.data.image?.url,
          url: data.data.url,
          siteName: data.data.publisher
        });
      }
    } catch (error) {
      console.error('Error fetching OG data:', error);
    } finally {
      setIsLoadingOg(false);
    }
  };

  useEffect(() => {
    const trimmedInput = textInput.trim();
    
    if (isValidUrl(trimmedInput)) {
      const timeoutId = setTimeout(() => {
        fetchOpenGraph(trimmedInput);
      }, 500); // Debounce for 500ms
      
      return () => clearTimeout(timeoutId);
    } else {
      setOgData(null);
    }
  }, [textInput]);

  const handleSubmit = async () => {
    if (!textInput.trim()) return;
    
    setIsProcessing(true);
    try {
      const isUrl = isValidUrl(textInput.trim());
      
      if (isUrl) {
        await onAddContent('link', {
          url: textInput.trim(),
          title: ogData?.title || new URL(textInput.trim()).hostname,
          ogData
        });
      } else {
        await onAddContent('text', {
          content: textInput,
          title: textInput.slice(0, 50) + (textInput.length > 50 ? '...' : '')
        });
      }
      
      setTextInput('');
      setOgData(null);
      
      toast({
        title: "Success",
        description: `${isUrl ? 'Link' : 'Text note'} added to your stash!`,
      });
    } catch (error) {
      toast({
        title: "Error",
        description: `Failed to add ${isValidUrl(textInput.trim()) ? 'link' : 'text note'}`,
        variant: "destructive",
      });
    } finally {
      setIsProcessing(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      handleSubmit();
    }
  };

  return (
    <Card className="mb-6">
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <FileText className="h-5 w-5" />
          <span>Add Text or Link</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <Textarea
            placeholder="Type your text or paste a link here..."
            value={textInput}
            onChange={(e) => setTextInput(e.target.value)}
            onKeyDown={handleKeyPress}
            disabled={isProcessing}
            className="min-h-[120px] resize-none"
          />
          <p className="text-xs text-muted-foreground mt-2">
            Tip: Press Cmd/Ctrl + Enter to save quickly
          </p>
        </div>

        {isLoadingOg && (
          <div className="text-sm text-muted-foreground">
            Loading link preview...
          </div>
        )}

        {ogData && <LinkPreview ogData={ogData} />}

        <Button
          onClick={handleSubmit}
          disabled={isProcessing || !textInput.trim()}
          className="w-full"
        >
          {isProcessing ? (
            'Processing...'
          ) : isValidUrl(textInput.trim()) ? (
            <>
              <LinkIcon className="h-4 w-4 mr-2" />
              Save Link
            </>
          ) : (
            <>
              <FileText className="h-4 w-4 mr-2" />
              Save Text
            </>
          )}
        </Button>
      </CardContent>
    </Card>
  );
};

export default TextLinkInput;
