import React, { useEffect, useRef, useState } from 'react';
import { X, FileText, Link as LinkIcon, Image, Video, FileAudio, File } from 'lucide-react';
import { StatusLine } from '@/components/machine/Machine';
import { SUPABASE_URL } from '@/integrations/supabase/client';
import type { FileAnalysis } from '@/utils/chipFileAnalysis';

interface OpenGraphData {
  title?: string;
  description?: string;
  image?: string;
  previewImageUrl?: string; // Supabase public URL for downloaded images
  url?: string;
  siteName?: string;
  videoUrl?: string;
  strategyUsed?: string;
  traceId?: string;
}

interface InputChipProps {
  type: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
  content: any;
  onRemove: () => void;
  ogData?: OpenGraphData;
  metadataStatus?: 'fast-loading' | 'deep-loading' | 'inferred' | 'ready' | 'failed';
  fileAnalysis?: FileAnalysis;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  analysisState?: 'local' | 'ready';
}

const PROGRESS_BAR_MIN_BYTES = 3 * 1024 * 1024;

const formatMb = (bytes: number) => `${(bytes / 1024 / 1024).toFixed(1)} MB`;

// Stable object URL per file (and revoked on cleanup) instead of a fresh
// createObjectURL every render.
const useFileObjectUrl = (file?: File) => {
  const [url, setUrl] = useState<string | undefined>(undefined);
  useEffect(() => {
    if (!file) {
      setUrl(undefined);
      return;
    }
    const objectUrl = URL.createObjectURL(file);
    setUrl(objectUrl);
    return () => URL.revokeObjectURL(objectUrl);
  }, [file]);
  return url;
};

interface FileChipContentProps {
  type: 'image' | 'video' | 'audio' | 'document';
  content: any;
  fileAnalysis?: FileAnalysis;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  analysisState?: 'local' | 'ready';
  isTransitioning: boolean;
}

const FileChipContent = ({
  type,
  content,
  fileAnalysis,
  uploadState,
  uploadProgress,
  analysisState,
  isTransitioning,
}: FileChipContentProps) => {
  const objectUrl = useFileObjectUrl(type === 'image' ? content.file : undefined);
  const thumbnailUrl = fileAnalysis?.thumbnailDataUrl || objectUrl;

  // The chip shows what the file itself says (its own title, pages, duration, a thumbnail);
  // the saved object's title and description come from the platform after the save
  const title = fileAnalysis?.metadataTitle || content.name;
  const factsLine =
    fileAnalysis?.factsLine || (content.size ? formatMb(content.size) : undefined);
  const isBusy = analysisState === 'local';
  const showPercent =
    uploadState === 'uploading' && (content.size ?? 0) >= PROGRESS_BAR_MIN_BYTES;

  const fallbackIcon = () => {
    switch (type) {
      case 'image':
        return <Image className="h-5 w-5 text-muted-foreground" />;
      case 'video':
        return <Video className="h-5 w-5 text-muted-foreground" />;
      case 'audio':
        return <FileAudio className="h-5 w-5 text-muted-foreground" />;
      default:
        return <File className="h-5 w-5 text-muted-foreground" />;
    }
  };

  return (
    <div className="flex items-center gap-3 max-w-[300px]">
      {thumbnailUrl ? (
        <img src={thumbnailUrl} alt="" className="h-10 w-10 flex-shrink-0 object-cover" />
      ) : (
        <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center bg-fill">
          {fallbackIcon()}
        </div>
      )}
      <div
        className={`flex-1 min-w-0 transition-opacity duration-200 ${
          isTransitioning ? 'opacity-70' : 'opacity-100'
        }`}
      >
        <div className="line-clamp-2 text-sm font-medium leading-tight text-ink">{title}</div>
        {factsLine && (
          <div className="mt-0.5 truncate font-pixel text-pixel text-muted-foreground">{factsLine}</div>
        )}
        {uploadState === 'uploading' && (
          <div className="mt-0.5">
            <StatusLine tone="busy">{showPercent ? `uploading · ${uploadProgress ?? 0}%` : 'uploading…'}</StatusLine>
          </div>
        )}
        {uploadState === 'failed' && (
          <div className="mt-0.5 text-[13px] text-muted-foreground">Will upload when you save</div>
        )}
        {uploadState !== 'uploading' && isBusy && (
          <div className="mt-0.5">
            <StatusLine tone="busy">analyzing…</StatusLine>
          </div>
        )}
      </div>
    </div>
  );
};

const InputChip = ({ type, content, onRemove, ogData, metadataStatus, fileAnalysis, uploadState, uploadProgress, analysisState }: InputChipProps) => {
  const isLoadingMetadata = type === 'link' && (metadataStatus === 'fast-loading' || metadataStatus === 'deep-loading');
  const isInferredMetadata = type === 'link' && metadataStatus === 'inferred';
  const metadataSignature =
    type === 'link'
      ? `${ogData?.title || ''}|${ogData?.description || ''}|${ogData?.image || ''}|${ogData?.previewImageUrl || ''}`
      : `${fileAnalysis?.metadataTitle || ''}|${fileAnalysis?.factsLine || ''}|${fileAnalysis?.thumbnailDataUrl ? 't' : ''}`;
  const previousSignatureRef = useRef(metadataSignature);
  const [isMetadataTransitioning, setIsMetadataTransitioning] = useState(false);

  useEffect(() => {
    if (type === 'text') return;
    if (previousSignatureRef.current === metadataSignature) return;

    previousSignatureRef.current = metadataSignature;
    setIsMetadataTransitioning(true);
    const timeoutId = window.setTimeout(() => {
      setIsMetadataTransitioning(false);
    }, 220);

    return () => window.clearTimeout(timeoutId);
  }, [metadataSignature, type]);

  const getIcon = () => {
    switch (type) {
      case 'text':
        return <FileText className="h-4 w-4" />;
      case 'link':
        return <LinkIcon className="h-4 w-4" />;
      default:
        return <File className="h-4 w-4" />;
    }
  };

  const getDisplayContent = () => {
    switch (type) {
      case 'link':
        if (ogData && (ogData.previewImageUrl || ogData.image || ogData.title || ogData.description)) {
          const imageUrl = ogData.previewImageUrl || ogData.image;
          return (
            <div className="flex items-center gap-3 max-w-[300px]">
              {imageUrl && (
                <img
                  src={imageUrl}
                  alt=""
                  className="h-10 w-10 flex-shrink-0 object-cover"
                  referrerPolicy="no-referrer"
                  loading="lazy"
                  decoding="async"
                  onError={(e) => {
                    console.log('InputChip image failed to load:', imageUrl);
                    // Try proxy URL if current URL isn't already proxied
                    if (!e.currentTarget.src.includes('/functions/v1/image-proxy')) {
                      const proxiedUrl = `${SUPABASE_URL}/functions/v1/image-proxy?url=${encodeURIComponent(imageUrl)}`;
                      console.log('Trying proxy URL:', proxiedUrl);
                      e.currentTarget.src = proxiedUrl;
                    } else {
                      // Proxy also failed, hide image
                      e.currentTarget.style.display = 'none';
                    }
                  }}
                />
              )}
              <div className={`flex-1 min-w-0 transition-opacity duration-200 ${isMetadataTransitioning ? 'opacity-70' : 'opacity-100'}`}>
                <div className="line-clamp-2 text-sm font-medium leading-tight text-ink">
                  {ogData.title || content.url}
                </div>
                {ogData.description && (
                  <div className="mt-0.5 line-clamp-2 text-[13px] text-muted-foreground">
                    {ogData.description}
                  </div>
                )}
                {isLoadingMetadata && (
                  <div className="mt-0.5">
                    <StatusLine tone="busy">fetching more details…</StatusLine>
                  </div>
                )}
                {isInferredMetadata && (
                  <div className="mt-0.5 text-[13px] text-muted-foreground">
                    Site blocks previews — got the gist; full details after saving
                  </div>
                )}
              </div>
            </div>
          );
        }
        return (
          <div className="flex items-center gap-2">
            <span className="max-w-[200px] truncate font-pixel text-pixel text-ink">{content.url || content.title}</span>
            {isLoadingMetadata && <StatusLine tone="busy">reading the link…</StatusLine>}
          </div>
        );
      case 'image':
      case 'video':
      case 'audio':
      case 'document':
        return (
          <FileChipContent
            type={type}
            content={content}
            fileAnalysis={fileAnalysis}
            uploadState={uploadState}
            uploadProgress={uploadProgress}
            analysisState={analysisState}
            isTransitioning={isMetadataTransitioning}
          />
        );
      default:
        return <span className="truncate max-w-[200px]">{content.title || content.text}</span>;
    }
  };

  const showProgressBar =
    uploadState === 'uploading' && (content?.size ?? 0) >= PROGRESS_BAR_MIN_BYTES;

  return (
    // A chip is the person's thing about to be saved: a small white object, near-square
    <div className="relative flex max-w-fit items-center gap-2.5 overflow-hidden rounded-object border border-line bg-white py-2 pl-2.5 pr-1.5">
      {(type === 'link' || type === 'text') && !ogData?.previewImageUrl && !ogData?.image && getIcon()}
      {getDisplayContent()}
      <button
        type="button"
        aria-label="Remove"
        onClick={onRemove}
        className="grid h-6 w-6 flex-shrink-0 place-items-center self-start text-muted-foreground transition-colors hover:bg-ink hover:text-white"
      >
        <X className="h-3 w-3" />
      </button>
      {showProgressBar && (
        <div
          className="absolute bottom-0 left-0 h-[3px] bg-ink transition-[width] duration-200"
          style={{ width: `${uploadProgress ?? 0}%` }}
        />
      )}
    </div>
  );
};

export default InputChip;
