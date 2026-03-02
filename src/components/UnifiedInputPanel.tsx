import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Plus, ChevronUp, ChevronDown, Send } from 'lucide-react';
import { AnimatePresence, motion } from 'framer-motion';
import InputChip from '@/components/InputChip';
import { useToast } from '@/hooks/use-toast';
import { useSubscription } from '@/hooks/useSubscription';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { MAX_FILE_SIZE_MB, MAX_VIDEO_SIZE_MB, MAX_AUDIO_SIZE_MB } from '@/services/imageUpload/MediaUploadTypes';

interface UnifiedInputPanelProps {
  isInputUICollapsed: boolean;
  onToggleInputUI: () => void;
  onUserToggleInputUI?: () => void;
  onInputFocusChange?: (isFocused: boolean) => void;
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (content: any) => Promise<string[]>;
}

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  previewImagePath?: string; // Supabase storage path for database storage
  previewImageUrl?: string; // Public URL for display purposes
  url: string; // Required to match LinkPreview interface
  siteName?: string;
  videoUrl?: string;
  strategyUsed?: string;
  traceId?: string;
}

type MetadataStatus = 'fast-loading' | 'deep-loading' | 'ready' | 'failed';

interface InputItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
  content: any;
  ogData?: OpenGraphData;
  metadataStatus?: MetadataStatus;
}

const UnifiedInputPanel = ({ 
  isInputUICollapsed, 
  onToggleInputUI, 
  onUserToggleInputUI,
  onInputFocusChange,
  onAddContent, 
  getSuggestedTags 
}: UnifiedInputPanelProps) => {
  const [inputText, setInputText] = useState('');
  const [inputItems, setInputItems] = useState<InputItem[]>([]);
  const [isDragOver, setIsDragOver] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isPanelBuilding, setIsPanelBuilding] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const previousInputItemsCountRef = useRef(0);
  const metadataCacheRef = useRef<Map<string, OpenGraphData>>(new Map());
  const metadataInFlightRef = useRef<Map<string, Promise<OpenGraphData | null>>>(new Map());
  const youtubeOEmbedInFlightRef = useRef<Map<string, Promise<OpenGraphData | null>>>(new Map());
  const youtubeRetryAttemptsRef = useRef<Map<string, number>>(new Map());
  const youtubeRetryTimersRef = useRef<Map<string, number>>(new Map());
  const { toast } = useToast();
  const { user } = useAuth();
  const { canAddContent } = useSubscription();

  useEffect(() => {
    const activeLinkUrls = new Set(
      inputItems
        .filter((item) => item.type === 'link')
        .map((item) => item.content.url as string)
    );

    for (const [url, timerId] of youtubeRetryTimersRef.current.entries()) {
      if (!activeLinkUrls.has(url)) {
        window.clearTimeout(timerId);
        youtubeRetryTimersRef.current.delete(url);
        youtubeRetryAttemptsRef.current.delete(url);
      }
    }
  }, [inputItems]);

  useEffect(() => {
    const previousCount = previousInputItemsCountRef.current;
    const currentCount = inputItems.length;

    if (currentCount > previousCount) {
      setIsPanelBuilding(true);
      const timer = window.setTimeout(() => {
        setIsPanelBuilding(false);
      }, 240);

      previousInputItemsCountRef.current = currentCount;
      return () => {
        window.clearTimeout(timer);
      };
    }

    previousInputItemsCountRef.current = currentCount;
  }, [inputItems.length]);

  useEffect(() => {
    if (!textareaRef.current) return;
    const textarea = textareaRef.current;
    textarea.style.height = 'auto';
    textarea.style.height = `${textarea.scrollHeight}px`;
  }, [inputText]);

  const generateId = () => Math.random().toString(36).substr(2, 9);

  const getYouTubeVideoId = (url: string): string | null => {
    try {
      const parsed = new URL(url);
      const host = parsed.hostname.toLowerCase();

      if (!host.includes('youtube.com') && !host.includes('youtu.be')) {
        return null;
      }

      if (host.includes('youtu.be')) {
        return parsed.pathname.split('/').filter(Boolean)[0] || null;
      }

      const queryId = parsed.searchParams.get('v');
      if (queryId) return queryId;

      const segments = parsed.pathname.split('/').filter(Boolean);
      const markerIndex = segments.findIndex((segment) => ['embed', 'shorts', 'live'].includes(segment));
      if (markerIndex !== -1 && segments[markerIndex + 1]) {
        return segments[markerIndex + 1];
      }
    } catch {
      return null;
    }

    return null;
  };

  const buildYouTubeFallback = (url: string): OpenGraphData | null => {
    const videoId = getYouTubeVideoId(url);
    if (!videoId) return null;

    return {
      url,
      title: 'YouTube Video',
      description: 'Video link from YouTube',
      image: `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
      siteName: 'YouTube',
      videoUrl: `https://www.youtube.com/watch?v=${videoId}`,
      strategyUsed: 'client-youtube-fallback',
    };
  };

  const buildProvisionalLinkMetadata = (url: string): OpenGraphData | null => {
    const youtubeFallback = buildYouTubeFallback(url);
    if (youtubeFallback) return youtubeFallback;

    try {
      const parsed = new URL(url);
      const host = parsed.hostname.replace(/^www\./, '');
      return {
        url,
        title: host,
        siteName: host,
        strategyUsed: 'client-provisional-domain-fallback',
      };
    } catch {
      return null;
    }
  };

  const fetchYouTubeOEmbed = async (url: string): Promise<OpenGraphData | null> => {
    const videoId = getYouTubeVideoId(url);
    if (!videoId) return null;

    try {
      // noembed supports CORS in browsers; YouTube's oEmbed often does not.
      const noembedUrl = `https://noembed.com/embed?url=${encodeURIComponent(`https://www.youtube.com/watch?v=${videoId}`)}`;
      const noembedResponse = await fetch(noembedUrl);
      if (noembedResponse.ok) {
        const noembedData = await noembedResponse.json();
        if (noembedData?.title) {
          return {
            url,
            title: noembedData.title,
            description: noembedData.author_name ? `Watch "${noembedData.title}" by ${noembedData.author_name} on YouTube` : 'YouTube video',
            image: noembedData.thumbnail_url || `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
            siteName: 'YouTube',
            videoUrl: `https://www.youtube.com/watch?v=${videoId}`,
            strategyUsed: 'client-noembed-youtube',
          };
        }
      }

      const oembedUrl = `https://www.youtube.com/oembed?url=${encodeURIComponent(`https://www.youtube.com/watch?v=${videoId}`)}&format=json`;
      const oembedResponse = await fetch(oembedUrl);
      if (!oembedResponse.ok) return null;

      const oembedData = await oembedResponse.json();
      if (!oembedData?.title) return null;

      return {
        url,
        title: oembedData.title,
        description: oembedData.author_name ? `Watch "${oembedData.title}" by ${oembedData.author_name} on YouTube` : 'YouTube video',
        image: oembedData.thumbnail_url || `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
        siteName: 'YouTube',
        videoUrl: `https://www.youtube.com/watch?v=${videoId}`,
        strategyUsed: 'client-youtube-oembed',
      };
    } catch (error) {
      console.log('YouTube oEmbed fallback failed in client:', error);
      return null;
    }
  };

  const mergeOpenGraphData = (current: OpenGraphData | undefined, incoming: OpenGraphData, url: string): OpenGraphData => {
    const getValue = (...values: Array<string | undefined>) => {
      for (const value of values) {
        if (typeof value === 'string' && value.trim().length > 0) {
          return value.trim();
        }
      }
      return undefined;
    };

    const shouldPreferCurrent = (field: 'title' | 'description') => {
      const currentValue = current?.[field];
      const incomingValue = incoming[field];
      if (!currentValue || !incomingValue) return false;

      const normalizedIncoming = incomingValue.trim().toLowerCase();
      const normalizedCurrent = currentValue.trim().toLowerCase();
      if (normalizedIncoming === normalizedCurrent) return false;

      if (field === 'title' && normalizedIncoming === 'youtube video') {
        return true;
      }
      if (field === 'description' && normalizedIncoming === 'video link from youtube') {
        return true;
      }

      return false;
    };

    return {
      url,
      title: shouldPreferCurrent('title') ? current?.title : getValue(incoming.title, current?.title),
      description: shouldPreferCurrent('description') ? current?.description : getValue(incoming.description, current?.description),
      image: getValue(incoming.image, current?.image),
      previewImagePath: getValue(incoming.previewImagePath, current?.previewImagePath),
      previewImageUrl: getValue(incoming.previewImageUrl, current?.previewImageUrl),
      siteName: getValue(incoming.siteName, current?.siteName),
      videoUrl: getValue(incoming.videoUrl, current?.videoUrl),
      strategyUsed: getValue(incoming.strategyUsed, current?.strategyUsed),
      traceId: getValue(incoming.traceId, current?.traceId),
    };
  };

  const hasMeaningfulMetadata = (metadata: OpenGraphData | null | undefined) => {
    if (!metadata) return false;
    return Boolean(
      metadata.title ||
      metadata.description ||
      metadata.image ||
      metadata.previewImageUrl ||
      metadata.siteName ||
      metadata.videoUrl
    );
  };

  const isGenericYouTubeMetadata = (metadata: OpenGraphData | null | undefined, url: string) => {
    if (!metadata) return false;
    if (!getYouTubeVideoId(url)) return false;

    const title = metadata.title?.toLowerCase().trim();
    return (
      title === 'youtube video' ||
      metadata.strategyUsed === 'client-youtube-fallback' ||
      metadata.strategyUsed === 'youtube-thumbnail-fallback'
    );
  };

  const validateFileSize = (file: File): { valid: boolean; error?: string } => {
    const fileSizeMB = file.size / 1024 / 1024;
    
    if (file.type.startsWith('video/')) {
      if (fileSizeMB > MAX_VIDEO_SIZE_MB) {
        return {
          valid: false,
          error: `"${file.name}" is ${fileSizeMB.toFixed(1)}MB. Stash only accepts videos less than ${MAX_VIDEO_SIZE_MB}MB. Perhaps you can compress the video further?`
        };
      }
    } else if (file.type.startsWith('audio/')) {
      if (fileSizeMB > MAX_AUDIO_SIZE_MB) {
        return {
          valid: false,
          error: `"${file.name}" is ${fileSizeMB.toFixed(1)}MB. Maximum audio size is ${MAX_AUDIO_SIZE_MB}MB. Please choose a smaller file.`
        };
      }
    } else if (file.type.startsWith('image/') || file.type === 'application/pdf' || file.type.startsWith('text/') || file.type.startsWith('application/')) {
      if (fileSizeMB > MAX_FILE_SIZE_MB) {
        return {
          valid: false,
          error: `"${file.name}" is ${fileSizeMB.toFixed(1)}MB. Maximum file size is ${MAX_FILE_SIZE_MB}MB. Please choose a smaller file.`
        };
      }
    }
    
    return { valid: true };
  };

  const fetchOgData = async (url: string, fastOnly: boolean = true): Promise<OpenGraphData | null> => {
    try {
      console.log('fetchOgData called with URL:', url);
      console.log('User ID:', user?.id);
      console.log('Calling extract-link-metadata edge function...');
      
      const { data, error } = await supabase.functions.invoke('extract-link-metadata', {
        body: { url, userId: user?.id, fastOnly }
      });
      
      console.log('Edge function response:', { data, error });
      
      if (error) {
        console.error('Error fetching metadata:', error);
        return null;
      }
      
      if (data && data.success) {
        console.log('✓ Successfully fetched metadata:', {
          title: !!data.title,
          description: !!data.description, 
          image: data.image,
          previewImagePath: data.previewImagePath,
          previewImageUrl: data.previewImagePublicUrl
        });
        
        const ogDataResult: OpenGraphData = {
          title: data.title,
          description: data.description,
          image: data.image,
          previewImagePath: data.previewImagePath,
          previewImageUrl: data.previewImagePublicUrl,
          url: url,
          siteName: data.siteName,
          videoUrl: data.videoUrl,
          strategyUsed: data.strategyUsed,
          traceId: data.traceId,
        };

        console.log('fetchOgData result:', ogDataResult);
        return ogDataResult;
      }

      if (data) {
        const fallbackResult: OpenGraphData = {
          title: data.title,
          description: data.description,
          image: data.image,
          previewImagePath: data.previewImagePath,
          previewImageUrl: data.previewImagePublicUrl,
          url,
          siteName: data.siteName,
          videoUrl: data.videoUrl,
          strategyUsed: data.strategyUsed,
          traceId: data.traceId,
        };

        if (hasMeaningfulMetadata(fallbackResult)) {
          console.log('Edge function returned partial metadata, using fallback result');
          return fallbackResult;
        }
      }

      const youtubeFallback = buildYouTubeFallback(url);
      if (youtubeFallback) {
        console.log('Using client-side YouTube fallback metadata');
        return youtubeFallback;
      }

      console.log('Edge function returned no usable metadata');
      return null;
    } catch (error) {
      console.error('Error:', error);
      const youtubeFallback = buildYouTubeFallback(url);
      if (youtubeFallback) {
        console.log('Using client-side YouTube fallback metadata after error');
        return youtubeFallback;
      }
      return null;
    }
  };

  const detectUrl = (text: string) => {
    const urlRegex = /(https?:\/\/[^\s]+)/g;
    const matches = text.match(urlRegex) || [];
    const normalizedUrls = matches
      .map((rawUrl) => rawUrl.replace(/^[<("']+/, '').replace(/[>\])"',.!?;|]+$/, ''))
      .filter((candidate) => {
        try {
          new URL(candidate);
          return true;
        } catch {
          return false;
        }
      });

    return Array.from(new Set(normalizedUrls));
  };

  const updateLinkMetadata = useCallback((itemId: string, ogData: OpenGraphData | null) => {
    if (!ogData) return;
    setInputItems(prev =>
      prev.map(item => (
        item.id === itemId
          ? { ...item, ogData: mergeOpenGraphData(item.ogData, ogData, item.content.url || ogData.url) }
          : item
      ))
    );
  }, []);

  const updateMetadataStatus = useCallback((itemId: string, metadataStatus: MetadataStatus) => {
    setInputItems(prev =>
      prev.map(item => (item.id === itemId ? { ...item, metadataStatus } : item))
    );
  }, []);

  const hydrateLinkMetadata = useCallback(async (itemId: string, url: string) => {
    const clearYouTubeRetry = () => {
      const timerId = youtubeRetryTimersRef.current.get(url);
      if (timerId) {
        window.clearTimeout(timerId);
      }
      youtubeRetryTimersRef.current.delete(url);
      youtubeRetryAttemptsRef.current.delete(url);
    };

    const maybeScheduleYouTubeRetry = () => {
      if (!getYouTubeVideoId(url)) return;
      const cached = metadataCacheRef.current.get(url);
      if (!isGenericYouTubeMetadata(cached, url)) {
        clearYouTubeRetry();
        return;
      }

      const attempts = youtubeRetryAttemptsRef.current.get(url) ?? 0;
      if (attempts >= 8) return;
      if (youtubeRetryTimersRef.current.has(url)) return;

      const delays = [1200, 2500, 4500, 7000, 10000, 14000, 18000, 22000];
      const delay = delays[Math.min(attempts, delays.length - 1)];
      const timerId = window.setTimeout(async () => {
        youtubeRetryTimersRef.current.delete(url);
        youtubeRetryAttemptsRef.current.set(url, attempts + 1);

        maybeEnrichFromYouTubeOEmbed();
        const retryMetadata = await fetchOgData(url, false);
        if (retryMetadata) {
          const merged = mergeOpenGraphData(metadataCacheRef.current.get(url), retryMetadata, url);
          metadataCacheRef.current.set(url, merged);
          updateLinkMetadata(itemId, merged);
          if (!isGenericYouTubeMetadata(merged, url)) {
            clearYouTubeRetry();
            updateMetadataStatus(itemId, 'ready');
            return;
          }
        }

        maybeScheduleYouTubeRetry();
      }, delay);

      youtubeRetryTimersRef.current.set(url, timerId);
    };

    const maybeEnrichFromYouTubeOEmbed = () => {
      if (!getYouTubeVideoId(url)) return;

      const cacheEntry = metadataCacheRef.current.get(url);
      if (cacheEntry?.strategyUsed === 'client-youtube-oembed') return;

      const existingRequest = youtubeOEmbedInFlightRef.current.get(url);
      const request = existingRequest || fetchYouTubeOEmbed(url);
      youtubeOEmbedInFlightRef.current.set(url, request);

      request
        .then((youtubeMetadata) => {
          if (!youtubeMetadata) return;
          const mergedMetadata = mergeOpenGraphData(metadataCacheRef.current.get(url), youtubeMetadata, url);
          metadataCacheRef.current.set(url, mergedMetadata);
          updateLinkMetadata(itemId, mergedMetadata);
          console.log('[link-metadata] youtube oembed enrichment complete', {
            itemId,
            url,
            strategyUsed: mergedMetadata.strategyUsed,
            hasTitle: Boolean(mergedMetadata.title),
            hasDescription: Boolean(mergedMetadata.description),
          });
          if (!isGenericYouTubeMetadata(mergedMetadata, url)) {
            clearYouTubeRetry();
          }
        })
        .finally(() => {
          youtubeOEmbedInFlightRef.current.delete(url);
        });
    };

    const cachedMetadata = metadataCacheRef.current.get(url);
    if (cachedMetadata) {
      updateLinkMetadata(itemId, cachedMetadata);
      updateMetadataStatus(itemId, 'ready');
      maybeEnrichFromYouTubeOEmbed();
      maybeScheduleYouTubeRetry();
      return;
    }

    updateMetadataStatus(itemId, 'fast-loading');
    maybeEnrichFromYouTubeOEmbed();

    const fastCacheKey = `fast:${url}`;
    const existingFastRequest = metadataInFlightRef.current.get(fastCacheKey);
    const fastRequest = existingFastRequest || fetchOgData(url, true);
    metadataInFlightRef.current.set(fastCacheKey, fastRequest);

    const fastMetadata = await fastRequest;
    metadataInFlightRef.current.delete(fastCacheKey);

    if (fastMetadata) {
      const mergedFastMetadata = mergeOpenGraphData(metadataCacheRef.current.get(url), fastMetadata, url);
      metadataCacheRef.current.set(url, mergedFastMetadata);
      updateLinkMetadata(itemId, mergedFastMetadata);
      console.log('[link-metadata] fast stage complete', {
        itemId,
        url,
        strategyUsed: mergedFastMetadata.strategyUsed,
        traceId: mergedFastMetadata.traceId,
        hasTitle: Boolean(mergedFastMetadata.title),
        hasDescription: Boolean(mergedFastMetadata.description),
        hasImage: Boolean(mergedFastMetadata.previewImageUrl || mergedFastMetadata.image),
      });
      maybeEnrichFromYouTubeOEmbed();
      maybeScheduleYouTubeRetry();
    }

    updateMetadataStatus(itemId, 'deep-loading');

    const deepCacheKey = `deep:${url}`;
    if (!metadataInFlightRef.current.has(deepCacheKey)) {
      const deepRequest = fetchOgData(url, false)
        .then((deepMetadata) => {
          if (deepMetadata) {
            const mergedMetadata = mergeOpenGraphData(metadataCacheRef.current.get(url), deepMetadata, url);
            metadataCacheRef.current.set(url, mergedMetadata);
            updateLinkMetadata(itemId, mergedMetadata);
            console.log('[link-metadata] deep stage complete', {
              itemId,
              url,
              strategyUsed: mergedMetadata.strategyUsed,
              traceId: mergedMetadata.traceId,
              hasTitle: Boolean(mergedMetadata.title),
              hasDescription: Boolean(mergedMetadata.description),
              hasImage: Boolean(mergedMetadata.previewImageUrl || mergedMetadata.image),
            });
            updateMetadataStatus(itemId, 'ready');
            maybeScheduleYouTubeRetry();
          } else {
            updateMetadataStatus(itemId, hasMeaningfulMetadata(metadataCacheRef.current.get(url)) ? 'ready' : 'failed');
            maybeScheduleYouTubeRetry();
          }
          return deepMetadata;
        })
        .finally(() => {
          metadataInFlightRef.current.delete(deepCacheKey);
        });

      metadataInFlightRef.current.set(deepCacheKey, deepRequest);
    } else {
      metadataInFlightRef.current.get(deepCacheKey)?.then((deepMetadata) => {
        updateMetadataStatus(itemId, deepMetadata || hasMeaningfulMetadata(metadataCacheRef.current.get(url)) ? 'ready' : 'failed');
        maybeScheduleYouTubeRetry();
      });
    }
  }, [updateLinkMetadata, updateMetadataStatus]);

  const handleInputChange = async (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const value = e.target.value;
    setInputText(value);

    // Auto-detect URLs and add as link chips
    const urls = detectUrl(value);
    
    if (urls.length > 0) {
      for (const url of urls) {
        const existingLink = inputItems.find(item => 
          item.type === 'link' && item.content.url === url
        );
        if (!existingLink) {
          const provisionalMetadata = buildProvisionalLinkMetadata(url);
          const newItem: InputItem = {
            id: generateId(),
            type: 'link',
            content: { url, title: url },
            ogData: provisionalMetadata || undefined,
            metadataStatus: 'fast-loading',
          };
          
          setInputItems(prev => [...prev, newItem]);
          
          hydrateLinkMetadata(newItem.id, url);
        }
      }
    }
    
    // Remove link items if URL was deleted/modified
    setInputItems(prev => prev.filter(item => 
      item.type !== 'link' || urls.includes(item.content.url)
    ));
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
      // Validate file size
      const validation = validateFileSize(file);
      if (!validation.valid) {
        toast({
          title: "File too large",
          description: validation.error,
          variant: "destructive",
        });
        return;
      }

      // Classify file type correctly
      let fileType: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
      if (file.type.startsWith('image/')) {
        fileType = 'image';
      } else if (file.type.startsWith('video/')) {
        fileType = 'video';
      } else if (file.type.startsWith('audio/')) {
        fileType = 'audio';
      } else {
        // PDFs, Word docs, text files, etc. are 'document'
        fileType = 'document';
      }
      
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
  }, [toast]);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    files.forEach(file => {
      // Validate file size
      const validation = validateFileSize(file);
      if (!validation.valid) {
        toast({
          title: "File too large",
          description: validation.error,
          variant: "destructive",
        });
        return;
      }

      // Classify file type correctly
      let fileType: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
      if (file.type.startsWith('image/')) {
        fileType = 'image';
      } else if (file.type.startsWith('video/')) {
        fileType = 'video';
      } else if (file.type.startsWith('audio/')) {
        fileType = 'audio';
      } else {
        // PDFs, Word docs, text files, etc. are 'document'
        fileType = 'document';
      }
      
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
    
    if (!canAddContent) {
      toast({
        title: "Feature Restricted",
        description: "Please subscribe to add new content.",
        variant: "destructive",
      });
      return;
    }
    
    setIsSubmitting(true);
    
    // Clear the form immediately for better UX
    const textToProcess = inputText;
    const itemsToProcess = [...inputItems];
    setInputText('');
    setInputItems([]);
    
    // Auto-collapse the input panel after submission to free up space
    if (!isInputUICollapsed) {
      onToggleInputUI();
    }

    try {
      const hasText = textToProcess.trim();
      const linkItems = itemsToProcess.filter(item => item.type === 'link');
      const mediaItems = itemsToProcess.filter(item => item.type !== 'link');

      // Case 1: Single link (with or without text) -> Individual link item
      if (linkItems.length === 1 && mediaItems.length === 0) {
        const linkItem = linkItems[0];
        console.log('Single link submission:', linkItem);
        await onAddContent('link', {
          url: linkItem.content.url,
          title: linkItem.ogData?.title || linkItem.content.title || linkItem.content.url,
          description: hasText || linkItem.ogData?.description,
          previewImagePath: linkItem.ogData?.previewImagePath,
          ogData: {
            ...linkItem.ogData,
            // Ensure we have image fallback for contentProcessor
            image: linkItem.ogData?.previewImageUrl || linkItem.ogData?.image
          },
          type: 'link'
        });
      }
      // Case 2: Only a single media file, no text, no other items -> Individual media item
      else if (mediaItems.length === 1 && !hasText && linkItems.length === 0) {
        const mediaItem = mediaItems[0];
        await onAddContent(mediaItem.type, {
          file: mediaItem.content.file,
          title: mediaItem.content.name,
          type: mediaItem.type
        });
      }
      // Case 3: Only text, no attachments -> Text note
      else if (hasText && linkItems.length === 0 && mediaItems.length === 0) {
        await onAddContent('text', {
          content: hasText,
          type: 'text'
        });
      }
      // Case 4: Multiple links or mixed items -> Collection
      else {
        const attachments = [];
        
        // Add link attachments
        for (const linkItem of linkItems) {
          attachments.push({
            type: 'link',
            url: linkItem.content.url,
            title: linkItem.ogData?.title || linkItem.content.url,
            description: linkItem.ogData?.description,
            image: linkItem.ogData?.previewImageUrl || linkItem.ogData?.image,
            siteName: linkItem.ogData?.siteName
          });
        }
        
        // Add media attachments
        for (const mediaItem of mediaItems) {
          attachments.push({
            type: mediaItem.type,
            file: mediaItem.content.file,
            name: mediaItem.content.name,
            size: mediaItem.content.size,
            fileType: mediaItem.content.type
          });
        }

        await onAddContent('collection', {
          content: hasText || '',
          type: 'collection',
          attachments: attachments
        });
      }

    } catch (error) {
      // Restore the form data on error
      setInputText(textToProcess);
      setInputItems(itemsToProcess);
      
      // Re-expand input panel on error
      if (isInputUICollapsed) {
        onToggleInputUI();
      }
      console.error('Error adding content:', error);
      toast({
        title: "Error",
        description: "Failed to add content. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const panelEase: [number, number, number, number] = [0.22, 1, 0.36, 1];
  const panelDuration = 0.36;
  const addToStashDelay = 0.02;
  const attachDelay = 0.1;
  const handleManualToggleInputUI = onUserToggleInputUI ?? onToggleInputUI;
  const hasSatisfactoryTextLength = inputText.trim().length >= 3;
  const canSubmit = (!inputText.trim() && inputItems.length === 0) || isSubmitting ? false : true;

  const getActionTransition = (delayAfterPanel: number) => {
    if (isInputUICollapsed) {
      return {
        opacity: { type: 'tween' as const, duration: 0.14, ease: panelEase, delay: 0 },
        y: { type: 'tween' as const, duration: 0.14, ease: panelEase, delay: 0 },
      };
    }

    return {
      opacity: { type: 'tween' as const, duration: 0.2, ease: panelEase, delay: panelDuration + delayAfterPanel },
      y: { type: 'tween' as const, duration: 0.2, ease: panelEase, delay: panelDuration + delayAfterPanel },
    };
  };

  return (
    <div className="w-full relative">
      {/* Extended animated gradient background */}
      <div className="absolute inset-0 h-[200vh] animated-gradient opacity-30" />
      <div className="absolute inset-0 h-[200vh] bg-gradient-to-b from-transparent via-background/50 via-background/30 to-background" />
      
      <div className="relative pt-5 pb-8">
        <div className="container mx-auto px-4">
          <div data-testid="input-panel-shell" className="bg-white/90 backdrop-blur-sm rounded-[6px] shadow-lg">
            {/* Input area with minimize button */}
            <motion.div
              initial={false}
              animate={{
                height: isInputUICollapsed ? 0 : 'auto',
                opacity: isInputUICollapsed ? 0.1 : 1,
              }}
              transition={{
                // Use the same ease-out tween in both directions for smooth, non-bouncy motion.
                height: { type: 'tween', duration: panelDuration, ease: panelEase },
                opacity: { type: 'tween', duration: 0.3, ease: panelEase },
              }}
              className="overflow-hidden"
              style={{ pointerEvents: isInputUICollapsed ? 'none' : 'auto' }}
            >
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
                  onClick={handleManualToggleInputUI}
                  className="absolute top-2 right-2 h-6 w-6 p-0"
                >
                  <ChevronUp className="h-4 w-4" />
                </Button>

                <motion.div
                  layout
                  initial={false}
                  animate={{
                    scale: isPanelBuilding ? 1.008 : 1,
                    y: isPanelBuilding ? -1 : 0,
                  }}
                  transition={{ duration: 0.22, ease: panelEase }}
                >
                  <Textarea
                    ref={textareaRef}
                    value={inputText}
                    onChange={handleInputChange}
                    onFocus={() => {
                      onInputFocusChange?.(true);
                    }}
                    onBlur={() => {
                      onInputFocusChange?.(false);
                    }}
                    placeholder="What's on your mind? Drop files, paste links, or just start typing..."
                    className="min-h-[100px] resize-none overflow-hidden border-0 bg-transparent focus:ring-0 focus:border-0 focus-visible:ring-0 focus-visible:ring-offset-0 text-base pr-10"
                  />
                </motion.div>
                
                {/* Input chips */}
                <AnimatePresence initial={false}>
                  {inputItems.length > 0 && (
                    <motion.div
                      layout
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -6 }}
                      transition={{ duration: 0.2, ease: panelEase }}
                      className="flex flex-wrap gap-2 pt-2 border-t border-border"
                    >
                      <AnimatePresence initial={false}>
                        {inputItems.map(item => (
                          <motion.div
                            key={item.id}
                            layout
                            initial={{ opacity: 0, y: 8, scale: 0.96 }}
                            animate={{ opacity: 1, y: 0, scale: 1 }}
                            exit={{ opacity: 0, y: -8, scale: 0.96 }}
                            transition={{ duration: 0.2, ease: panelEase }}
                          >
                            <InputChip
                              type={item.type}
                              content={item.content}
                              onRemove={() => removeInputItem(item.id)}
                              ogData={item.ogData}
                              metadataStatus={item.metadataStatus}
                            />
                          </motion.div>
                        ))}
                      </AnimatePresence>
                    </motion.div>
                  )}
                </AnimatePresence>
                
                {/* Bottom actions */}
                <div className="flex items-center justify-between pt-2">
                  <div className="flex items-center gap-2">
                    <motion.div
                      initial={false}
                      animate={{
                        opacity: isInputUICollapsed ? 0 : 1,
                        y: isInputUICollapsed ? 4 : 0,
                      }}
                      transition={getActionTransition(attachDelay)}
                    >
                      <Button
                        variant="outline"
                        size="icon"
                        aria-label="Attach"
                        onClick={() => fileInputRef.current?.click()}
                        className="h-12 w-12 rounded-full border border-gray-300 bg-white text-gray-500 hover:bg-gray-50 hover:text-gray-700 shadow-sm"
                      >
                        <Plus className="h-6 w-6" />
                      </Button>
                    </motion.div>
                    <input
                      ref={fileInputRef}
                      type="file"
                      multiple
                      className="hidden"
                      onChange={handleFileSelect}
                    />
                  </div>
                  
                  <motion.div
                    initial={false}
                    animate={{
                      opacity: isInputUICollapsed ? 0 : 1,
                      y: isInputUICollapsed ? 4 : 0,
                      scale: hasSatisfactoryTextLength ? 1 : 0.97,
                    }}
                    transition={{
                      ...getActionTransition(addToStashDelay),
                      scale: { type: 'tween', duration: 0.14, ease: panelEase },
                    }}
                  >
                    <Button 
                      aria-label="Add to Stash"
                      onClick={handleSubmit}
                      disabled={!canSubmit}
                      size="icon"
                      className={`h-12 w-12 rounded-full border shadow-sm transition-all duration-150 ${
                        hasSatisfactoryTextLength
                          ? 'bg-[#8B5CF6] border-[#8B5CF6] text-white hover:bg-[#7C3AED] hover:border-[#7C3AED]'
                          : 'bg-white border-gray-300 text-gray-400 hover:bg-gray-50 hover:border-gray-300'
                      } disabled:opacity-100`}
                    >
                      {isSubmitting ? (
                        <div className="h-5 w-5 animate-spin rounded-full border-2 border-current border-t-transparent" />
                      ) : (
                        <Send className="h-5 w-5" />
                      )}
                    </Button>
                  </motion.div>
                </div>
              </div>
            </motion.div>

            {/* Collapsed state - show expand button */}
            <motion.div
              initial={false}
              animate={{
                height: isInputUICollapsed ? 'auto' : 0,
                opacity: isInputUICollapsed ? 1 : 0,
              }}
              transition={{
                height: { type: 'tween', duration: panelDuration, ease: panelEase },
                opacity: { type: 'tween', duration: 0.24, ease: panelEase },
              }}
              className="overflow-hidden"
              style={{ pointerEvents: isInputUICollapsed ? 'auto' : 'none' }}
            >
              <div className="p-4 flex justify-center">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleManualToggleInputUI}
                  className="flex items-center gap-1"
                >
                  <Plus className="h-4 w-4" />
                  Add something
                </Button>
              </div>
            </motion.div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default UnifiedInputPanel;