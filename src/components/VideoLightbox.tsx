
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

  const handleBackdropClick = (e: React.MouseEvent) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  return (
    <div 
      className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center p-4"
      onClick={handleBackdropClick}
    >
      <div className="relative max-w-6xl w-full max-h-full">
        <Button
          variant="ghost"
          size="sm"
          onClick={onClose}
          className="absolute -top-12 right-0 text-white hover:text-gray-300 hover:bg-white/10 h-10 w-10 p-0 z-10"
        >
          <X className="h-6 w-6" />
        </Button>
        
        <div className="bg-black rounded-lg overflow-hidden shadow-2xl">
          <video
            src={src}
            controls
            autoPlay
            className="w-full max-h-[85vh] object-contain"
            controlsList="nodownload"
            onLoadedMetadata={(e) => {
              // Optional: Add any metadata handling here
            }}
          >
            Your browser does not support the video tag.
          </video>
          
          <div className="p-4 bg-gray-900 text-white border-t border-gray-700">
            <p className="text-sm font-medium truncate">{fileName}</p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default VideoLightbox;
