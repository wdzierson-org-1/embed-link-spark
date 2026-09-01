import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Plus, Send, Loader2, MapPin } from 'lucide-react';
import { AnimatePresence, motion } from 'framer-motion';
import InputChip from '@/components/InputChip';
import CaptureEditor, { type CaptureEditorHandle } from '@/components/capture/CaptureEditor';
import { useToast } from '@/hooks/use-toast';
import { useSubscription } from '@/hooks/useSubscription';
import { useCaptureLocation } from '@/hooks/useCaptureLocation';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { MAX_FILE_SIZE_MB, MAX_VIDEO_SIZE_MB, MAX_AUDIO_SIZE_MB } from '@/services/imageUpload/MediaUploadTypes';
import { humanizeUrlSlug, isWeakLinkMetadata } from '@/utils/urlInference';
import { analyzeDroppedFile, type ChipAnalysisHandle, type ChipAnalysisUpdate, type ChipFileKind, type FileAnalysis } from '@/utils/chipFileAnalysis';
import { removeStagedFile } from '@/utils/stagedUploader';
import {
  docIsEmpty,
  docIsPlainText,
  docToPlainText,
  stripUrlsFromDoc,
} from '@/utils/captureDoc';
import { classifyLinkFlavor } from '@/utils/linkFlavor';
import type { ItemAttributes } from '@/types/itemAttributes';

interface UnifiedInputPanelProps {
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

type MetadataStatus = 'fast-loading' | 'deep-loading' | 'inferred' | 'ready' | 'failed';

interface InputItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
  content: any;
  ogData?: OpenGraphData;
  metadataStatus?: MetadataStatus;
  fileAnalysis?: FileAnalysis;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  analysisState?: 'local' | 'analyzing' | 'ready';
}

const ANALYSIS_SUBMIT_TIMEOUT_MS = 20000;

const UnifiedInputPanel = ({
  onAddContent,
  getSuggestedTags
}: UnifiedInputPanelProps) => {
  const [inputText, setInputText] = useState('');
  const [editorIsEmpty, setEditorIsEmpty] = useState(true);
  const [isEditorFocused, setIsEditorFocused] = useState(false);
  const [inputItems, setInputItems] = useState<InputItem[]>([]);
  const [isDragOver, setIsDragOver] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isPanelBuilding, setIsPanelBuilding] = useState(false);
  const [isPublic, setIsPublic] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const captureEditorRef = useRef<CaptureEditorHandle>(null);
  const previousInputItemsCountRef = useRef(0);
  const metadataCacheRef = useRef<Map<string, OpenGraphData>>(new Map());
  const metadataInFlightRef = useRef<Map<string, Promise<OpenGraphData | null>>>(new Map());
  const youtubeOEmbedInFlightRef = useRef<Map<string, Promise<OpenGraphData | null>>>(new Map());
  const youtubeRetryAttemptsRef = useRef<Map<string, number>>(new Map());
  const youtubeRetryTimersRef = useRef<Map<string, number>>(new Map());
  const fileAnalysisHandlesRef = useRef<Map<string, ChipAnalysisHandle>>(new Map());
  const { toast } = useToast();
  const { user } = useAuth();
  const { canAddContent } = useSubscription();
  const {
    enabled: locationEnabled,
    status: locationStatus,
    label: locationLabel,
    toggle: toggleLocation,
    getLocationForSubmit,
  } = useCaptureLocation();

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

  const applyChipUpdate = useCallback((itemId: string, update: ChipAnalysisUpdate) => {
    setInputItems(prev =>
      prev.map(item => {
        if (item.id !== itemId) return item;
        return {
          ...item,
          fileAnalysis: update.analysis
            ? { ...item.fileAnalysis, ...update.analysis }
            : item.fileAnalysis,
          uploadState: update.uploadState ?? item.uploadState,
          uploadProgress: update.uploadProgress ?? item.uploadProgress,
          analysisState: update.analysisState ?? item.analysisState,
        };
      })
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

    // The fast result settles the chip; all heavier extraction (image storage,
    // blocked-site rescue tiers) runs after save via enrichSavedLinkItem. When
    // the site blocks previews, infer the topic from the URL slug instantly so
    // the user can add with confidence — the card upgrades itself later.
    const settled = metadataCacheRef.current.get(url);
    if (fastMetadata && hasMeaningfulMetadata(settled) && !isWeakLinkMetadata(settled, url)) {
      updateMetadataStatus(itemId, 'ready');
      return;
    }

    const inferredTitle = humanizeUrlSlug(url);
    if (inferredTitle) {
      const inferredMetadata = mergeOpenGraphData(
        metadataCacheRef.current.get(url),
        { title: inferredTitle, url },
        url
      );
      metadataCacheRef.current.set(url, inferredMetadata);
      updateLinkMetadata(itemId, inferredMetadata);
      updateMetadataStatus(itemId, 'inferred');
    } else {
      updateMetadataStatus(itemId, hasMeaningfulMetadata(metadataCacheRef.current.get(url)) ? 'ready' : 'failed');
    }
  }, [updateLinkMetadata, updateMetadataStatus]);

  // CaptureEditor reads this through a ref, so a fresh identity per render is
  // fine — and lets the URL check see the latest inputItems, as the old
  // textarea onChange did
  const handleEditorDocChange = ({ plainText, isEmpty }: { plainText: string; isEmpty: boolean }) => {
    setInputText(plainText);
    setEditorIsEmpty(isEmpty);

    // Auto-detect URLs and add as link chips
    const urls = detectUrl(plainText);

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

  // Paste anywhere on the page (when not typing in another field) lands in the
  // capture box — the fastest possible save
  useEffect(() => {
    const onWindowPaste = (e: ClipboardEvent) => {
      const target = e.target as HTMLElement | null;
      const tag = target?.tagName?.toLowerCase();
      const isEditable = tag === 'input' || tag === 'textarea' || target?.isContentEditable;
      if (isEditable) return;

      const text = e.clipboardData?.getData('text');
      if (!text?.trim()) return;

      e.preventDefault();
      captureEditorRef.current?.insertText(text.trim());
    };

    window.addEventListener('paste', onWindowPaste);
    return () => window.removeEventListener('paste', onWindowPaste);
  });

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);
  }, []);

  const addFileItem = useCallback((file: File) => {
    const validation = validateFileSize(file);
    if (!validation.valid) {
      toast({
        title: "File too large",
        description: validation.error,
        variant: "destructive",
      });
      return;
    }

    let fileType: ChipFileKind;
    if (file.type.startsWith('image/')) {
      fileType = 'image';
    } else if (file.type.startsWith('video/')) {
      fileType = 'video';
    } else if (file.type.startsWith('audio/')) {
      fileType = 'audio';
    } else {
      fileType = 'document';
    }

    const itemId = generateId();
    setInputItems(prev => [...prev, {
      id: itemId,
      type: fileType,
      content: { file, name: file.name, size: file.size, type: file.type },
      analysisState: 'local',
    }]);

    // Chip-time understanding starts immediately (local facts + staged upload +
    // cloud summary); without a signed-in user the chip stays static and the
    // save path handles everything as before.
    if (user?.id) {
      const handle = analyzeDroppedFile(file, fileType, user.id, (update) =>
        applyChipUpdate(itemId, update)
      );
      fileAnalysisHandlesRef.current.set(itemId, handle);
    }
  }, [toast, user?.id, applyChipUpdate]);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);
    Array.from(e.dataTransfer.files).forEach(addFileItem);
  }, [addFileItem]);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    Array.from(e.target.files || []).forEach(addFileItem);
  };

  const removeInputItem = (id: string) => {
    const item = inputItems.find(candidate => candidate.id === id);
    const handle = fileAnalysisHandlesRef.current.get(id);
    handle?.abort();
    fileAnalysisHandlesRef.current.delete(id);
    const stagedPath = item?.fileAnalysis?.uploadedFilePath;
    if (stagedPath) {
      void removeStagedFile(stagedPath);
    }
    setInputItems(prev => prev.filter(candidate => candidate.id !== id));
  };

  // Submit reuses whatever the chip pipeline produced; if it's still running,
  // wait briefly rather than redoing the work — past the timeout the save path
  // simply falls back to today's post-save processing.
  const resolveFileAnalysis = async (item: InputItem): Promise<FileAnalysis | undefined> => {
    const handle = fileAnalysisHandlesRef.current.get(item.id);
    if (!handle) return item.fileAnalysis;
    const timeout = new Promise<FileAnalysis | undefined>((resolve) =>
      window.setTimeout(() => resolve(item.fileAnalysis), ANALYSIS_SUBMIT_TIMEOUT_MS)
    );
    return Promise.race([handle.done, timeout]);
  };

  const handleImageFilesPasted = useCallback((files: File[]) => {
    files.forEach((file) => {
      const namedFile = new File([file], `screenshot-${Date.now()}.png`, { type: file.type });
      addFileItem(namedFile);
    });
  }, [addFileItem]);

  const handleSubmit = async () => {
    const docJson = captureEditorRef.current?.getJSON();
    const editorHasContent = docJson ? !docIsEmpty(docJson) : false;
    if (!editorHasContent && inputItems.length === 0) return;

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
    const docToRestore = docJson;
    const itemsToProcess = [...inputItems];
    captureEditorRef.current?.clear();
    setInputItems([]);

    try {
      const linkUrls = itemsToProcess
        .filter(item => item.type === 'link')
        .map(item => item.content.url as string | undefined)
        .filter((url): url is string => Boolean(url));

      // Detected URLs live in both the note and their chips; drop them from the
      // note so the URL isn't saved twice (once as link, once as note)
      const noteDoc = docJson ? stripUrlsFromDoc(docJson, linkUrls) : null;
      const noteHasContent = noteDoc ? !docIsEmpty(noteDoc) : false;
      const noteIsRich = noteDoc ? !docIsPlainText(noteDoc) : false;
      const notePlain = noteDoc ? docToPlainText(noteDoc).trim() : '';

      // Location lives only in the structured attributes blob (cards show the
      // pin, the edit sheet edits it) — no "posted from" text in note content
      const capturedLocation = await getLocationForSubmit();

      /** Per-item attributes: shared location + type-specific facts */
      const buildAttributes = (extra?: Partial<ItemAttributes>): ItemAttributes | undefined => {
        const merged: ItemAttributes = {
          ...(capturedLocation ? { location: capturedLocation } : {}),
          ...(extra ?? {}),
        };
        return Object.keys(merged).length > 0 ? merged : undefined;
      };

      /** The note in its richest storable form (novel JSON when formatted) */
      const noteContent = noteIsRich && noteDoc ? JSON.stringify(noteDoc) : notePlain;

      // One object per stash item, always. A capture with no objects is a text
      // note; a capture with N objects saves N items (collections are retired —
      // legacy ones still render, new ones are never created). The note and its
      // "posted from" line ride on the first object.
      if (itemsToProcess.length === 0) {
        await onAddContent('text', {
          content: noteContent,
          type: 'text',
          attributes: buildAttributes()
        });
      } else {
        for (let index = 0; index < itemsToProcess.length; index++) {
          const objectItem = itemsToProcess[index];
          const isFirst = index === 0;

          if (objectItem.type === 'link') {
            const url = objectItem.content.url as string;
            await onAddContent('link', {
              url,
              title: objectItem.ogData?.title || objectItem.content.title || url,
              // description stays the object's own (og/AI); the user's note is
              // the annotation and lives in content like every other type
              description: objectItem.ogData?.description,
              content: isFirst && noteHasContent ? noteContent : undefined,
              previewImagePath: objectItem.ogData?.previewImagePath,
              ogData: {
                ...objectItem.ogData,
                // Ensure we have image fallback for contentProcessor
                image: objectItem.ogData?.previewImageUrl || objectItem.ogData?.image
              },
              type: 'link',
              is_public: isPublic,
              attributes: buildAttributes({ link: { flavor: classifyLinkFlavor(url) } })
            });
          } else {
            const analysis = await resolveFileAnalysis(objectItem);
            const durationSeconds = analysis?.durationSeconds;
            await onAddContent(objectItem.type, {
              file: objectItem.content.file,
              uploadedFilePath: analysis?.uploadedFilePath,
              title: analysis?.title || analysis?.metadataTitle || objectItem.content.name,
              description: analysis?.description,
              // content = the user's note (rich JSON when formatted); the chip
              // transcript is source material and belongs in page_body
              content: isFirst && noteHasContent ? noteContent : undefined,
              page_body: analysis?.transcription,
              detectedText: analysis?.detectedText,
              tags: analysis?.tags,
              snippet: analysis?.snippet,
              type: objectItem.type,
              is_public: isPublic,
              attributes: buildAttributes({
                media: {
                  ...(typeof durationSeconds === 'number' ? { duration_s: Math.round(durationSeconds) } : {}),
                  ...(objectItem.content.name ? { file_name: objectItem.content.name as string } : {}),
                }
              })
            });
          }
        }

        if (itemsToProcess.length > 1) {
          toast({
            title: `Saved as ${itemsToProcess.length} items`,
            description: noteHasContent
              ? 'Stash keeps one object per item — your note went with the first one.'
              : 'Stash keeps one object per item, so each got its own.',
          });
        }
      }

      // Handles are only released on success; on error the restored chips keep
      // their live analysis
      fileAnalysisHandlesRef.current.clear();

    } catch (error) {
      // Restore the form data on error
      if (docToRestore) {
        captureEditorRef.current?.setJSON(docToRestore);
      }
      setInputItems(itemsToProcess);

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
  const hasSatisfactoryTextLength = inputText.trim().length >= 3;
  const hasAnyContent = !editorIsEmpty || inputItems.length > 0;
  const canSubmit = hasAnyContent && !isSubmitting;
  const sendIsHot = hasSatisfactoryTextLength || inputItems.length > 0 || (!editorIsEmpty && inputText.trim().length === 0);
  const isPanelActive = isEditorFocused || hasAnyContent;

  return (
    <div className="w-full relative">
      {/* Gradient backdrop lives at the page level (Index) so it persists
          when this panel is hidden in retrieval states */}
      <div className="relative pt-5 pb-8">
        <div className="container mx-auto px-4">
          {/* The shell lifts, glows, and takes a violet border while capturing */}
          <motion.div
            data-testid="input-panel-shell"
            className="bg-white/90 backdrop-blur-sm rounded-[6px]"
            initial={false}
            animate={{
              scale: isPanelActive ? 1.006 : 1,
              y: isPanelActive ? -2 : 0,
              boxShadow: isPanelActive
                ? '0 0 0 1.5px rgba(139, 92, 246, 0.5), 0 0 0 6px rgba(139, 92, 246, 0.08), 0 24px 48px -20px rgba(139, 92, 246, 0.35)'
                : '0 0 0 1px rgba(0, 0, 0, 0.05), 0 10px 30px -18px rgba(0, 0, 0, 0.3)',
            }}
            transition={{ type: 'spring', stiffness: 320, damping: 28, mass: 0.7 }}
          >
            <div
              data-testid="capture-dropzone"
              className={`p-4 space-y-4 relative transition-colors duration-150 ${
                isDragOver
                  ? 'bg-violet-50 border-2 border-dashed border-violet-400 rounded-[6px]'
                  : 'border-2 border-transparent'
              }`}
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
              onDrop={handleDrop}
            >
              <motion.div
                layout
                initial={false}
                animate={{
                  scale: isPanelBuilding ? 1.008 : 1,
                  y: isPanelBuilding ? -1 : 0,
                }}
                transition={{ duration: 0.22, ease: panelEase }}
              >
                <CaptureEditor
                  ref={captureEditorRef}
                  onDocChange={handleEditorDocChange}
                  onSubmit={handleSubmit}
                  onFocusChange={setIsEditorFocused}
                  onImageFilesPasted={handleImageFilesPasted}
                />
              </motion.div>

              {/* Drag-over overlay */}
              <AnimatePresence>
                {isDragOver && (
                  <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.12 }}
                    className="absolute inset-0 z-10 flex items-center justify-center pointer-events-none rounded-[4px]"
                  >
                    <div className="flex flex-col items-center gap-2 text-violet-500">
                      <Plus className="h-8 w-8" />
                      <span className="text-sm font-medium">Drop to add</span>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>

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
                            fileAnalysis={item.fileAnalysis}
                            uploadState={item.uploadState}
                            uploadProgress={item.uploadProgress}
                            analysisState={item.analysisState}
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
                  <Button
                    variant="outline"
                    size="icon"
                    aria-label="Attach"
                    onClick={() => fileInputRef.current?.click()}
                    className="h-12 w-12 rounded-full border border-gray-300 bg-white text-gray-500 hover:bg-gray-50 hover:text-gray-700 shadow-sm"
                  >
                    <Plus className="h-6 w-6" />
                  </Button>
                  <input
                    ref={fileInputRef}
                    type="file"
                    multiple
                    className="hidden"
                    onChange={handleFileSelect}
                  />
                </div>

                <div className="flex items-center gap-2">
                  <AnimatePresence>
                    {locationEnabled && (
                      <motion.span
                        initial={{ opacity: 0, x: 8 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: 8 }}
                        transition={{ duration: 0.18, ease: panelEase }}
                        className="text-xs text-muted-foreground max-w-[220px] truncate"
                      >
                        {locationStatus === 'locating'
                          ? 'finding your location…'
                          : locationLabel
                            ? `posted from ${locationLabel}`
                            : ''}
                      </motion.span>
                    )}
                  </AnimatePresence>

                  <Button
                    variant="outline"
                    size="icon"
                    aria-label="Include your location"
                    aria-pressed={locationEnabled}
                    onClick={toggleLocation}
                    className={`h-12 w-12 rounded-full border shadow-sm transition-colors duration-150 ${
                      locationEnabled
                        ? 'bg-violet-50 border-violet-300 text-violet-600 hover:bg-violet-100 hover:text-violet-700'
                        : 'bg-white border-gray-300 text-gray-400 hover:bg-gray-50 hover:text-gray-600'
                    }`}
                  >
                    <MapPin className={`h-5 w-5 ${locationStatus === 'locating' ? 'animate-pulse' : ''}`} />
                  </Button>

                  <motion.div
                    initial={false}
                    animate={{ scale: sendIsHot ? 1 : 0.97 }}
                    transition={{ type: 'tween', duration: 0.14, ease: panelEase }}
                  >
                    <Button
                      aria-label="Add to Stash"
                      onClick={handleSubmit}
                      disabled={!canSubmit}
                      size="icon"
                      className={`h-12 w-12 rounded-full border shadow-sm transition-all duration-150 ${
                        sendIsHot
                          ? 'bg-[#8B5CF6] border-[#8B5CF6] text-white hover:bg-[#7C3AED] hover:border-[#7C3AED]'
                          : 'bg-white border-gray-300 text-gray-400 hover:bg-gray-50 hover:border-gray-300'
                      } disabled:opacity-100`}
                    >
                      {isSubmitting ? (
                        <Loader2 className="h-5 w-5 animate-spin" />
                      ) : (
                        <Send className="h-5 w-5" />
                      )}
                    </Button>
                  </motion.div>
                </div>
              </div>
            </div>
          </motion.div>
        </div>
      </div>
    </div>
  );
};

export default UnifiedInputPanel;
