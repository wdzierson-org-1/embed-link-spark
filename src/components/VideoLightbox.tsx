
import React from 'react';
import { Button } from '@/components/ui/button';
import { X } from 'lucide-react';

interface VideoLightboxProps {
  src: string;
  fileName: string;
  isOpen: boolean;
  onClose: () => void;
}

const VideoLightbox = ({ src, fileName, isOpen, onClose }: VideoLightboxProps) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4">
      <div className="relative max-w-4xl w-full">
        <Button
          variant="ghost"
          size="sm"
          onClick={onClose}
          className="absolute -top-12 right-0 text-white hover:text-gray-300 h-8 w-8 p-0"
        >
          <X className="h-6 w-6" />
        </Button>
        
        <div className="bg-black rounded-lg overflow-hidden">
          <video
            src={src}
            controls
            autoPlay
            className="w-full max-h-[80vh]"
            onLoadedMetadata={(e) => {
              // Optional: Add any metadata handling here
            }}
          >
            Your browser does not support the video tag.
          </video>
          
          <div className="p-3 bg-gray-900 text-white">
            <p className="text-sm truncate">{fileName}</p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default VideoLightbox;
