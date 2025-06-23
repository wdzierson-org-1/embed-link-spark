
import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Link as LinkIcon } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import LinkPreview from './LinkPreview';
import TagInput from './TagInput';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  url: string;
  siteName?: string;
}

interface LinkTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: () => string[];
}

const LinkTab = ({ onAddContent, getSuggestedTags }: LinkTabProps) => {
  const [linkInput, setLinkInput] = useState('');
  const [tags, setTags] = useState<string[]>([]);
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
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 3000);
      
      const response = await fetch(`https://api.microlink.io/?url=${encodeURIComponent(url)}&timeout=2000`, {
        signal: controller.signal
      });
      
      clearTimeout(timeoutId);
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
      console.log('OG fetch failed or timed out:', error);
      try {
        const urlObj = new URL(url);
        setOgData({
          title: urlObj.hostname,
          url: url,
          siteName: urlObj.hostname
        });
      } catch {
        setOgData(null);
      }
    } finally {
      setIsLoadingOg(false);
    }
  };

  useEffect(() => {
    const trimmedInput = linkInput.trim();
    
    if (isValidUrl(trimmedInput)) {
      const timeoutId = setTimeout(() => {
        fetchOpenGraph(trimmedInput);
      }, 200);
      
      return () => clearTimeout(timeoutId);
    } else {
      setOgData(null);
    }
  }, [linkInput]);

  const handleSubmit = async () => {
    if (!linkInput.trim() || !isValidUrl(linkInput.trim())) return;
    
    setIsProcessing(true);
    try {
      await onAddContent('link', {
        url: linkInput.trim(),
        title: ogData?.title || new URL(linkInput.trim()).hostname,
        ogData,
        tags
      });
      
      // Reset form
      setLinkInput('');
      setTags([]);
      setOgData(null);
      
      toast({
        title: "Success",
        description: "Link added to your stash!",
      });
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to add link",
        variant: "destructive",
      });
    } finally {
      setIsProcessing(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      handleSubmit();
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <LinkIcon className="h-5 w-5" />
          <span>Paste Link</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <Input
            placeholder="Paste a link here..."
            value={linkInput}
            onChange={(e) => setLinkInput(e.target.value)}
            onKeyDown={handleKeyPress}
            disabled={isProcessing}
          />
          <p className="text-xs text-muted-foreground mt-2">
            Tip: Press Enter to save quickly
          </p>
        </div>

        {isLoadingOg && (
          <div className="text-sm text-muted-foreground">
            Loading link preview...
          </div>
        )}

        {ogData && <LinkPreview ogData={ogData} />}

        <div>
          <label className="text-sm font-medium mb-2 block">Tags (optional)</label>
          <TagInput
            tags={tags}
            onTagsChange={setTags}
            suggestions={getSuggestedTags()}
            placeholder="Add tags to organize your link..."
          />
        </div>

        <Button
          onClick={handleSubmit}
          disabled={isProcessing || !linkInput.trim() || !isValidUrl(linkInput.trim())}
          className="w-full"
        >
          {isProcessing ? (
            'Processing...'
          ) : (
            <>
              <LinkIcon className="h-4 w-4 mr-2" />
              Save Link
            </>
          )}
        </Button>
      </CardContent>
    </Card>
  );
};

export default LinkTab;
